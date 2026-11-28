#!/usr/bin/env python3
"""Synthetic CSV fixtures; no private telemetry is used."""
import io
import pathlib
import runpy
import subprocess
import sys
import unittest

M = runpy.run_path(str(pathlib.Path(__file__).with_name("summarize-process-resources.py")))
SUMMARY = M["summarize"]
SAMPLER = runpy.run_path(str(pathlib.Path(__file__).with_name("sample-process-resources.py")))
COLLECT = SAMPLER["collect"]
HEADER = ",".join(M["HEADER"]) + "\n"


def summarize(body, count=3, interval=60):
    return SUMMARY(io.StringIO(HEADER + body), count, interval)


class ResourceSummaryTests(unittest.TestCase):
    def test_statistics_and_gap(self):
        result = summarize("1,1.000,1.5,100,4\n2,61.000,125.0,110,5\n3,240.000,3.0,130,7\n")
        self.assertEqual(result["sample_count"], 3)
        self.assertEqual(result["observed_span_seconds"], 239)
        self.assertEqual(result["max_observation_gap_seconds"], 179)
        self.assertEqual(result["gaps_over_twice_nominal_interval"], 1)
        self.assertEqual(result["cpu_percent_ps"]["median"], 3)
        self.assertEqual(result["cpu_percent_ps"]["p95_nearest_rank"], 125)
        self.assertEqual(result["rss_kib"]["last_minus_first_median"], 30)
        self.assertEqual(result["fd_count"]["last_minus_first_median"], 3)

    def test_windows_are_nonoverlapping(self):
        body = "".join(f"{i},{i * 60},0.0,{i},2\n" for i in range(1, 11))
        result = summarize(body, 10)
        self.assertEqual(result["window_sample_count"], 2)
        self.assertEqual(result["rss_kib"]["first_window_median"], 1.5)
        self.assertEqual(result["rss_kib"]["last_window_median"], 9.5)
        self.assertEqual(result["rss_kib"]["last_minus_first_median"], 8)

    def test_single_sample_no_comparison(self):
        result = summarize("1,0.010,0.0,512,4\n", 1)
        self.assertIsNone(result["max_observation_gap_seconds"])
        self.assertIsNone(result["rss_kib"]["last_minus_first_median"])
        self.assertEqual(result["window_sample_count"], 0)

    def test_count_mismatch_or_truncated_record(self):
        for body in ("", "1,0,0,512,4\n", "1,0,0,512,4\n2,60,0,512,4"):
            with self.subTest(body=body), self.assertRaises(ValueError):
                summarize(body)
        with self.assertRaises(ValueError):
            summarize("1,0,0,512,4\n2,60,0,512,4\n", 1)

    def test_schema_and_sequence(self):
        for body in ("2,0,0,512,4\n", "1,0,0,512\n", "1,0,0,512,4,extra\n",
                     "1,0,0,512,4\n1,60,0,512,4\n"):
            with self.subTest(body=body), self.assertRaises(ValueError):
                summarize(body, 1 if "\n1," not in body else 2)
        with self.assertRaises(ValueError):
            SUMMARY(io.StringIO("wrong\n1,0,0,512,4\n"), 1, 60)

    def test_rejects_bad_numeric_or_text_fields(self):
        for token in ("NaN", "Infinity", "-1", "1e9", " ", "01", "private/path",
                      '"1"', "9" * 300):
            with self.subTest(token=token), self.assertRaises(ValueError):
                summarize(f"1,0,{token},512,4\n", 1)
        for body in ("1,0,0,1.5,4\n", "1,0,0,512,-1\n", "1,0,0,512,4\n\n"):
            with self.subTest(body=body), self.assertRaises(ValueError):
                summarize(body, 1)

    def test_elapsed_regression_rejected_but_equal_elapsed_allowed(self):
        with self.assertRaises(ValueError):
            summarize("1,1,0,512,4\n2,0,0,512,4\n", 2)
        result = summarize("1,1,0,512,4\n2,1,0,512,4\n", 2)
        self.assertEqual(result["max_observation_gap_seconds"], 0)

    def test_gap_threshold_and_p95_definition(self):
        body = "".join(f"{i},{i * 120},{i},512,4\n" for i in range(1, 21))
        result = summarize(body, 20)
        self.assertEqual(result["cpu_percent_ps"]["p95_nearest_rank"], 19)
        self.assertEqual(result["gaps_over_twice_nominal_interval"], 0)

    def test_gap_threshold_is_strict_even_below_report_rounding_precision(self):
        exact = summarize("1,0,0,512,4\n2,120.000000000000,0,512,4\n", 2)
        self.assertEqual(exact["gaps_over_twice_nominal_interval"], 0)

        just_over = summarize("1,0,0,512,4\n2,120.000000000001,0,512,4\n", 2)
        self.assertEqual(just_over["gaps_over_twice_nominal_interval"], 1)
        # The public diagnostic has bounded precision; the decision does not.
        self.assertEqual(just_over["max_observation_gap_seconds"], 120.0)

        visible_over = summarize("1,0,0,512,4\n2,120.0004,0,512,4\n", 2)
        self.assertEqual(visible_over["gaps_over_twice_nominal_interval"], 1)
        self.assertEqual(visible_over["max_observation_gap_seconds"], 120.0004)

    def test_elapsed_subfloat_regression_is_rejected(self):
        with self.assertRaises(ValueError):
            summarize(
                "1,100000000000.000000000002,0,512,4\n"
                "2,100000000000.000000000001,0,512,4\n",
                2,
            )

    def test_sampler_csv_round_trip_preserves_sleep_gap_and_safe_metrics(self):
        now = [0.0]
        starts = []
        output = io.StringIO()

        def observe(pid, previous):
            self.assertEqual(pid, 42)
            starts.append(now[0])
            now[0] += 0.5
            return ("private-folder-name", "SchneeGlass"), 2.5, 1000 + len(starts), 5

        def sleep(seconds):
            # Model a late wakeup from sleep without running real timers.
            now[0] += seconds + (180 if len(starts) == 1 else 0)

        COLLECT(42, 60, 4, output, observe=observe,
                clock=lambda: now[0], sleep=sleep)
        csv_text = output.getvalue()
        self.assertNotIn("private-folder-name", csv_text)
        self.assertNotIn("SchneeGlass", csv_text)
        self.assertEqual(starts, [0.0, 240.0, 300.0, 360.0])

        result = SUMMARY(io.StringIO(csv_text), 4, 60)
        self.assertEqual(result["sample_count"], 4)
        self.assertEqual(result["observed_span_seconds"], 360)
        self.assertEqual(result["max_observation_gap_seconds"], 240)
        self.assertEqual(result["gaps_over_twice_nominal_interval"], 1)
        self.assertEqual(result["rss_kib"]["last_minus_first_median"], 3)
        self.assertEqual(result["fd_count"]["max"], 5)

    def test_partial_sampler_csv_is_rejected_by_summary(self):
        output = io.StringIO()
        observations = [0]

        def observe(pid, previous):
            observations[0] += 1
            if observations[0] == 2:
                raise ValueError("Target process changed")
            return ("private-folder-name", "SchneeGlass"), 1.0, 512, 4

        with self.assertRaisesRegex(ValueError, "Target process changed"):
            COLLECT(42, 60, 3, output, observe=observe,
                    clock=lambda: 0.0, sleep=lambda _: None)

        self.assertEqual(len(output.getvalue().splitlines()), 2)
        with self.assertRaisesRegex(ValueError, "Sample count mismatch"):
            SUMMARY(io.StringIO(output.getvalue()), 3, 60)

    def test_minimum_observed_duration_requires_actual_span(self):
        def checked(body, minimum):
            return SUMMARY(io.StringIO(HEADER + body), 2, 60,
                           minimum_observed_seconds=minimum)

        # A correct row count does not imply a sufficient elapsed duration.
        for second in ("1", "59.999999999999"):
            with self.subTest(second=second), self.assertRaisesRegex(
                    ValueError, "Observed duration below minimum"):
                checked(f"1,0,0,512,4\n2,{second},0,512,4\n", 60)

        # The first elapsed value is not necessarily zero.
        with self.assertRaisesRegex(ValueError, "Observed duration below minimum"):
            checked("1,10,0,512,4\n2,69,0,512,4\n", 60)
        exact = checked("1,10,0,512,4\n2,70,0,512,4\n", 60)
        self.assertEqual(exact["observed_span_seconds"], 60)
        self.assertEqual(checked("1,10,0,512,4\n2,71,0,512,4\n", 60)
                         ["observed_span_seconds"], 61)

    def test_minimum_duration_cli_failure_has_no_json(self):
        script = pathlib.Path(__file__).with_name("summarize-process-resources.py")
        args = [sys.executable, str(script), "--expected-samples", "2",
                "--interval", "60", "--minimum-observed-seconds", "60"]
        for second, expected_code in (("59", 1), ("60", 0)):
            with self.subTest(second=second):
                result = subprocess.run(
                    args, input=HEADER + f"1,0,0,512,4\n2,{second},0,512,4\n",
                    text=True, capture_output=True, timeout=10)
                self.assertEqual(result.returncode, expected_code)
                if expected_code:
                    self.assertEqual(result.stdout, "")
                    self.assertIn("Resource summary failed", result.stderr)
                else:
                    self.assertIn('"observed_span_seconds": 60.0', result.stdout)

    def test_invalid_minimum_duration_is_rejected(self):
        for minimum in (0, -1, True, 1.5, 1_000_000_000_000):
            with self.subTest(minimum=minimum), self.assertRaisesRegex(
                    ValueError, "Invalid minimum observed duration"):
                SUMMARY(io.StringIO(HEADER + "1,0,0,512,4\n"), 1, 60,
                        minimum_observed_seconds=minimum)

    def test_invalid_sampling_parameters(self):
        for count, interval in ((0,60), (10001,60), (1,4), (1,3601)):
            with self.subTest(count=count, interval=interval), self.assertRaises(ValueError):
                summarize("1,0,0,512,4\n", count, interval)


if __name__ == "__main__":
    unittest.main()
