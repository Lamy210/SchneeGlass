#!/usr/bin/env python3
"""Synthetic tests and a Darwin-only native command fixture using an owned child."""
import io
import pathlib
import runpy
import subprocess
import sys
import unittest

M = runpy.run_path(str(pathlib.Path(__file__).with_name("sample-process-resources.py")))
PARSE_PS = M["parse_ps"]
PARSE_FDS = M["parse_fds"]
SAMPLE = M["sample"]
COLLECT = M["collect"]
RECORD = "42 Fri Nov 20 09:00:00 2026 125.5 4096 /Example App/SchneeGlass\n"
FDS = "p42\nfcwd\nftxt\nf0\nf2\nf17\n"


class ResourceSamplerTests(unittest.TestCase):
    def test_ps_parses_multicore_cpu_and_space_in_path(self):
        identity, cpu, rss = PARSE_PS(RECORD, 42)
        self.assertEqual(identity[0], "Fri Nov 20 09:00:00 2026")
        self.assertEqual((cpu, rss), (125.5, 4096))

    def test_ps_rejects_invalid_or_wrong_process(self):
        for value in ("", RECORD * 2, RECORD.replace("42 ", "43 ", 1),
                      RECORD.replace("125.5", "NaN"), RECORD.replace("4096", "-1"),
                      RECORD.replace("/SchneeGlass", "/Other")):
            with self.subTest(value=value), self.assertRaises(ValueError):
                PARSE_PS(value, 42)

    def test_counts_only_numeric_descriptors(self):
        self.assertEqual(PARSE_FDS(FDS, 42), 3)

    def test_rejects_unavailable_or_ambiguous_fds(self):
        for value in ("", "p42\nfcwd\n", "p43\nf0\n", "p42\nf0\np42\nf1\n",
                      "p42\nf0\nf0\n", "p42\nf0u\n", "p42\nf0\nfNOFD\n", "p42\nn/private/path\n"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                PARSE_FDS(value, 42)

    def test_commands_use_explicit_pid_and_no_file_name_fields(self):
        calls = []
        records = iter([RECORD, FDS, RECORD])

        def run(args):
            calls.append(args)
            return next(records)

        SAMPLE(42, run=run)
        expected_ps = [
            "/bin/ps", "-ww", "-p", "42", "-o", "pid=", "-o", "lstart=",
            "-o", "pcpu=", "-o", "rss=", "-o", "comm=",
        ]
        self.assertEqual(calls, [
            expected_ps, ["/usr/sbin/lsof", "-nP", "-a", "-p", "42", "-Fpf"], expected_ps,
        ])

    def test_sample_rejects_pid_reuse_during_observation(self):
        records = iter([RECORD, FDS, RECORD.replace("09:00:00", "09:00:01")])
        with self.assertRaisesRegex(ValueError, "changed during"):
            SAMPLE(42, run=lambda _: next(records))

    def test_sample_rejects_changed_process_between_samples(self):
        with self.assertRaisesRegex(ValueError, "Target process changed"):
            SAMPLE(42, ("old start", "SchneeGlass"), run=lambda _: RECORD)

    def test_sample_reports_post_fd_read_metrics(self):
        records = iter([RECORD, FDS, RECORD.replace("125.5", "10.0")])
        identity, cpu, rss, count = SAMPLE(42, run=lambda _: next(records))
        self.assertEqual(identity[0], "Fri Nov 20 09:00:00 2026")
        self.assertEqual((cpu, rss, count), (10.0, 4096, 3))

    def test_collect_uses_monotonic_elapsed_and_only_numeric_fields(self):
        now = [0.0]
        output = io.StringIO()
        identities = []

        def observe(pid, previous):
            identities.append(previous)
            now[0] += 1
            return ("private path", "identity"), 25.0, 1024, 4

        def sleep(seconds):
            now[0] += seconds

        COLLECT(42, 60, 2, output, observe=observe, clock=lambda: now[0], sleep=sleep)
        self.assertEqual(identities, [None, ("private path", "identity")])
        self.assertEqual(output.getvalue().splitlines(), [
            "sample,elapsed_seconds,cpu_percent_ps,rss_kib,fd_count",
            "1,1.000,25.0,1024,4",
            "2,61.000,25.0,1024,4",
        ])

    def test_collect_does_not_catch_up_after_late_wakeup(self):
        now = [0.0]
        starts = []
        sleeps = []

        def observe(pid, previous):
            starts.append(now[0])
            now[0] += 1
            return ("start", "command"), 1.0, 512, 3

        def sleep(seconds):
            sleeps.append(seconds)
            now[0] += seconds + (180 if len(sleeps) == 1 else 0)

        COLLECT(42, 60, 4, io.StringIO(), observe=observe,
                clock=lambda: now[0], sleep=sleep)
        self.assertEqual(starts, [0, 240, 300, 360])
        self.assertEqual(sleeps, [59, 59, 59])

    def test_collect_does_not_catch_up_after_slow_observation(self):
        now = [0.0]
        starts = []
        durations = iter([181, 1, 1])

        def observe(pid, previous):
            starts.append(now[0])
            now[0] += next(durations)
            return ("start", "command"), 1.0, 512, 3

        def sleep(seconds):
            now[0] += seconds

        COLLECT(42, 60, 3, io.StringIO(), observe=observe,
                clock=lambda: now[0], sleep=sleep)
        self.assertEqual(starts, [0, 181, 241])

    @unittest.skipUnless(sys.platform == "darwin", "requires native macOS ps/lsof")
    def test_native_macos_commands_observe_owned_child(self):
        child = subprocess.Popen(
            ["/bin/sleep", "90"],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        try:
            # The production CLI must still reject this non-SchneeGlass process.
            with self.assertRaisesRegex(ValueError, "Target is not SchneeGlass"):
                SAMPLE(child.pid)
            identity, cpu, rss, count = SAMPLE(child.pid, expected_name="sleep")
            self.assertGreaterEqual(cpu, 0)
            self.assertGreater(rss, 0)
            self.assertGreaterEqual(count, 3)
            again, _, _, _ = SAMPLE(child.pid, identity, expected_name="sleep")
            self.assertEqual(again, identity)
        finally:
            # Only the disposable child created by this test is terminated.
            if child.poll() is None:
                child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=5)

    def test_collect_preserves_partial_output_and_propagates_failure(self):
        output = io.StringIO()

        def observe(pid, previous):
            if previous:
                raise ValueError("Target process changed")
            return ("start", "command"), 1.0, 512, 3

        with self.assertRaises(ValueError):
            COLLECT(42, 60, 2, output, observe=observe, clock=lambda: 0, sleep=lambda _: None)
        self.assertEqual(len(output.getvalue().splitlines()), 2)


if __name__ == "__main__":
    unittest.main()
