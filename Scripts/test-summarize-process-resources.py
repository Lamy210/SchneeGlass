#!/usr/bin/env python3
"""Synthetic CSV fixtures; no private telemetry is used."""
import io
import pathlib
import runpy
import unittest

M = runpy.run_path(str(pathlib.Path(__file__).with_name("summarize-process-resources.py")))
SUMMARY = M["summarize"]
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

    def test_invalid_sampling_parameters(self):
        for count, interval in ((0,60), (10001,60), (1,4), (1,3601)):
            with self.subTest(count=count, interval=interval), self.assertRaises(ValueError):
                summarize("1,0,0,512,4\n", count, interval)


if __name__ == "__main__":
    unittest.main()
