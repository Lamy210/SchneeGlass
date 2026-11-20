#!/usr/bin/env python3
"""Synthetic tests only: do not inspect live processes or write files."""
import io
import pathlib
import runpy
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
                      "p42\nf0\nf0\n", "p42\nf0u\n", "p42\nn/private/path\n"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                PARSE_FDS(value, 42)

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
