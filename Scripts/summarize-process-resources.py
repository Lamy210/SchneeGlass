#!/usr/bin/env python3
"""Summarize a completed numeric sampler CSV from stdin; no paths or raw rows in output."""
import argparse
import csv
from decimal import Decimal
import json
import math
import re
import statistics
import sys

HEADER = ["sample", "elapsed_seconds", "cpu_percent_ps", "rss_kib", "fd_count"]
MAX_SAMPLES = 10_000
MAX_LINE = 256
# Bounded decimal syntax, no exponents, NaN, Infinity, whitespace or arbitrary text.
DECIMAL = re.compile(r"(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,12})?")
INTEGER = re.compile(r"(?:0|[1-9][0-9]{0,11})")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def rows(stream):
    while True:
        line = stream.readline(MAX_LINE + 1)
        if not line:
            return
        require(len(line) <= MAX_LINE and line.endswith("\n"), "Invalid CSV record length")
        # The sampler only emits plain numeric fields; no quoting or embedded lines.
        require('"' not in line and "\x00" not in line, "Invalid CSV record syntax")
        yield next(csv.reader([line], strict=True))


def parse(stream, expected):
    require(type(expected) is int and 1 <= expected <= MAX_SAMPLES, "Invalid sample count")
    records = rows(stream)
    require(next(records, None) == HEADER, "Invalid CSV header")
    result = []
    previous = None
    for index, record in enumerate(records, start=1):
        require(index <= expected, "Sample count mismatch")
        require(len(record) == len(HEADER), "Invalid CSV column count")
        require(record[0] == str(index), "Invalid sample sequence")
        require(all(DECIMAL.fullmatch(value) for value in record[1:3]),
                "Invalid decimal metric")
        require(all(INTEGER.fullmatch(value) for value in record[3:]),
                "Invalid integer metric")
        # Preserve the CSV's full decimal precision for monotonicity and gap checks.
        elapsed, cpu = Decimal(record[1]), float(record[2])
        rss, fd = map(int, record[3:])
        require(previous is None or elapsed >= previous, "Elapsed time decreased")
        previous = elapsed
        result.append((elapsed, cpu, rss, fd))
    require(len(result) == expected, "Sample count mismatch")
    return result


def metrics(values, width):
    ordered = sorted(values)
    result = {
        "min": ordered[0],
        "median": statistics.median(ordered),
        "p95_nearest_rank": ordered[math.ceil(len(ordered) * 0.95) - 1],
        "max": ordered[-1],
        "first_window_median": None,
        "last_window_median": None,
        "last_minus_first_median": None,
    }
    if width:
        first = statistics.median(values[:width])
        last = statistics.median(values[-width:])
        result.update(first_window_median=first, last_window_median=last,
                      last_minus_first_median=round(last - first, 6))
    return result


def summarize(stream, expected, interval, *, minimum_observed_seconds=None):
    require(type(interval) is int and 5 <= interval <= 3600, "Invalid interval")
    records = parse(stream, expected)
    elapsed = [row[0] for row in records]
    span = elapsed[-1] - elapsed[0]
    if minimum_observed_seconds is not None:
        require(type(minimum_observed_seconds) is int
                and 1 <= minimum_observed_seconds <= 999_999_999_999,
                "Invalid minimum observed duration")
        # Compare the original decimal values, not the rounded diagnostic span.
        require(span >= minimum_observed_seconds, "Observed duration below minimum")
    gaps = [b - a for a, b in zip(elapsed, elapsed[1:])]
    # Sample-based, non-overlapping windows, not time-weighted estimates.
    width = max(1, expected // 5) if expected >= 2 else 0
    return {
        "schema_version": 1,
        "sample_count": expected,
        "nominal_interval_seconds": interval,
        "first_elapsed_seconds": float(elapsed[0]),
        "last_elapsed_seconds": float(elapsed[-1]),
        "observed_span_seconds": float(round(span, 3)),
        "max_observation_gap_seconds": float(round(max(gaps), 6)) if gaps else None,
        # Evaluate strictly against the unrounded CSV timestamps. Rounding a
        # near-threshold gap first would silently misclassify a missed interval.
        "gaps_over_twice_nominal_interval": sum(gap > 2 * interval for gap in gaps),
        "window_sample_count": width,
        **{name: metrics([row[i] for row in records], width)
           for i, name in enumerate(HEADER[2:], start=1)},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-samples", type=int, required=True)
    parser.add_argument("--interval", type=int, required=True)
    parser.add_argument("--minimum-observed-seconds", type=int,
                        help="reject a completed CSV whose observed span is shorter than this")
    args = parser.parse_args()
    try:
        result = summarize(sys.stdin, args.expected_samples, args.interval,
                           minimum_observed_seconds=args.minimum_observed_seconds)
        print(json.dumps(result, sort_keys=True, indent=2, allow_nan=False))
    except (ValueError, OSError, csv.Error, UnicodeError):
        # Input could contain private strings; never echo the raw record.
        print("Resource summary failed: invalid or incomplete numeric CSV", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
