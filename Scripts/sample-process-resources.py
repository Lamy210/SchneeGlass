#!/usr/bin/env python3
"""Read-only, local macOS process resource sampling; no paths in output."""
import argparse
import csv
import math
import os
import pathlib
import re
import subprocess
import sys
import time

PS = "/bin/ps"
LSOF = "/usr/sbin/lsof"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run_command(args):
    result = subprocess.run(
        args,
        capture_output=True,
        text=True,
        env={**os.environ, "LC_ALL": "C"},
        timeout=15,
    )
    require(result.returncode == 0 and not result.stderr.strip(),
            "Process observation failed or was incomplete")
    return result.stdout


def parse_ps(output, pid):
    lines = output.strip().splitlines()
    require(len(lines) == 1, "Expected exactly one process")
    fields = lines[0].split(maxsplit=8)
    require(len(fields) == 9 and fields[0] == str(pid), "Unexpected process record")
    started = " ".join(fields[1:6])
    require(re.fullmatch(r"[A-Za-z]{3} [A-Za-z]{3} \d{1,2} \d{2}:\d{2}:\d{2} \d{4}",
                         started), "Invalid process start time")
    require(re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", fields[6]), "Invalid process CPU")
    require(re.fullmatch(r"[0-9]+", fields[7]), "Invalid process RSS")
    cpu = float(fields[6])
    require(math.isfinite(cpu), "Invalid process CPU")
    command = fields[8]
    require(pathlib.PurePath(command).name == "SchneeGlass", "Target is not SchneeGlass")
    return (started, command), cpu, int(fields[7])


def parse_fds(output, pid):
    process_seen = False
    descriptors = set()
    for line in output.splitlines():
        if line.startswith("p"):
            require(not process_seen and line == f"p{pid}", "Unexpected descriptor process")
            process_seen = True
        elif line.startswith("f") and process_seen:
            value = line[1:]
            if re.fullmatch(r"[0-9]+", value):
                descriptor = int(value)
                require(descriptor not in descriptors, "Duplicate descriptor record")
                descriptors.add(descriptor)
            else:
                # lsof also reports non-descriptor entries such as cwd/txt.
                require(re.fullmatch(r"[A-Za-z]+", value), "Invalid descriptor record")
        else:
            raise ValueError("Unexpected descriptor output")
    require(process_seen and descriptors, "Descriptor observation unavailable")
    return len(descriptors)


def read_process(pid, run=run_command):
    return parse_ps(run([PS, "-p", str(pid), "-o", "pid=,lstart=,pcpu=,rss=,comm="]), pid)


def sample(pid, expected_identity=None, run=run_command):
    identity, _, _ = read_process(pid, run)
    require(expected_identity is None or identity == expected_identity, "Target process changed")
    count = parse_fds(run([LSOF, "-nP", "-a", "-p", str(pid), "-Fpf"]), pid)
    after, cpu, rss = read_process(pid, run)
    require(after == identity, "Target process changed during observation")
    return identity, cpu, rss, count


def collect(pid, interval, samples, output, observe=sample, clock=time.monotonic, sleep=time.sleep):
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(["sample", "elapsed_seconds", "cpu_percent_ps", "rss_kib", "fd_count"])
    output.flush()
    begin = clock()
    identity = None
    for index in range(samples):
        if index:
            sleep(max(0, begin + index * interval - clock()))
        identity, cpu, rss, count = observe(pid, identity)
        writer.writerow([index + 1, f"{clock() - begin:.3f}", cpu, rss, count])
        output.flush()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--interval", type=int, default=60, help="seconds between sample starts")
    parser.add_argument("--samples", type=int, default=31)
    args = parser.parse_args()
    try:
        require(sys.platform == "darwin", "This sampler requires macOS")
        require(1 <= args.pid <= 2147483647, "Invalid PID")
        require(5 <= args.interval <= 3600, "Interval must be 5 to 3600 seconds")
        require(1 <= args.samples <= 10000, "Samples must be 1 to 10000")
        collect(args.pid, args.interval, args.samples, sys.stdout)
    except (ValueError, OSError, subprocess.SubprocessError, UnicodeError) as error:
        # Never print command output, arguments, executable paths or raw exceptions.
        message = str(error) if type(error) is ValueError else "Process observation failed"
        # Only known validation strings are emitted; unknown ValueErrors stay generic.
        if message not in SAFE_ERRORS:
            message = "Process observation failed"
        print(f"Sampling incomplete: {message}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Sampling interrupted; partial output is not a completed run", file=sys.stderr)
        return 130
    return 0


SAFE_ERRORS = {
    "This sampler requires macOS", "Invalid PID", "Interval must be 5 to 3600 seconds",
    "Samples must be 1 to 10000", "Target is not SchneeGlass", "Target process changed",
    "Target process changed during observation", "Descriptor observation unavailable",
    "Process observation failed or was incomplete",
}

if __name__ == "__main__":
    sys.exit(main())
