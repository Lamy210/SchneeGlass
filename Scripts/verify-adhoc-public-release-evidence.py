#!/usr/bin/env python3
"""Offline validation of one ad-hoc public Release asset set (not authorization)."""

import argparse
import datetime
import hashlib
import json
import os
import re
import stat
import sys
from contextlib import contextmanager

METADATA_LIMIT = 16 * 1024
ARCHIVE_LIMIT = 1024 * 1024 * 1024
FIELDS = {
    "schema_version", "distribution", "repository_id", "tag", "version",
    "bundle_identifier", "bundle_build", "source_sha", "run_id", "run_attempt",
    "artifact_id", "outer_artifact_sha256", "inner_zip_sha256", "public_zip_name",
    "public_zip_sha256", "qa_comment_id", "qa_owner_id", "qa_approved_at",
    "code_signature", "apple_developer_id_signed", "apple_notarized",
}


class InvalidEvidence(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidEvidence(message)


def matches(value, pattern):
    return type(value) is str and re.fullmatch(pattern, value) is not None


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def reject_constant(_):
    raise InvalidEvidence("nonstandard JSON constant")


@contextmanager
def regular_file(directory_fd, name, limit):
    # O_NONBLOCK prevents hanging on a FIFO before its type can be checked.
    fd = os.open(
        name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory_fd
    )
    with os.fdopen(fd, "rb") as stream:
        before = os.fstat(stream.fileno())
        require(stat.S_ISREG(before.st_mode), "asset is not a regular file")
        require(0 < before.st_size <= limit, "asset size outside allowed bounds")
        yield stream
        after = os.fstat(stream.fileno())
        require(
            (before.st_size, before.st_mtime_ns, before.st_ctime_ns)
            == (after.st_size, after.st_mtime_ns, after.st_ctime_ns),
            "asset changed during validation",
        )


def metadata(directory_fd, name):
    with regular_file(directory_fd, name, METADATA_LIMIT) as stream:
        raw = stream.read(METADATA_LIMIT + 1)
        require(0 < len(raw) <= METADATA_LIMIT, "metadata size outside allowed bounds")
        return raw.decode("utf-8", errors="strict")


def reject_legacy_evidence(directory_fd):
    try:
        os.stat("RELEASE_EVIDENCE.txt", dir_fd=directory_fd, follow_symlinks=False)
    except FileNotFoundError:
        return
    raise InvalidEvidence("mixed ad-hoc and legacy evidence")


def validate_json(raw, expected_tag, expected_sha):
    evidence = json.loads(raw, object_pairs_hook=unique_object, parse_constant=reject_constant)
    require(type(evidence) is dict and set(evidence) == FIELDS, "unexpected JSON fields")
    require(type(evidence["schema_version"]) is int and evidence["schema_version"] == 1,
            "unsupported schema version")
    require(evidence["distribution"] == "github-adhoc", "wrong distribution")
    require(evidence["repository_id"] == "1359347782", "wrong repository identity")
    require(evidence["qa_owner_id"] == "90091196", "wrong owner identity")
    require(evidence["bundle_identifier"] == "io.github.lamy210.schneeglass",
            "wrong bundle identifier")
    require(matches(evidence["version"], r"[0-9]+\.[0-9]+\.[0-9]+"), "invalid version")
    require(evidence["tag"] == expected_tag == "v" + evidence["version"], "tag/version mismatch")
    require(matches(evidence["source_sha"], r"[0-9a-f]{40}")
            and evidence["source_sha"] == expected_sha, "source SHA mismatch")
    require(matches(evidence["bundle_build"], r"[1-9][0-9]{0,8}"), "invalid build")
    for key in ("run_id", "artifact_id", "qa_comment_id"):
        require(matches(evidence[key], r"[1-9][0-9]*"), "invalid positive decimal ID")
    require(evidence["run_attempt"] == "1", "invalid run attempt")
    for key in ("outer_artifact_sha256", "inner_zip_sha256", "public_zip_sha256"):
        require(matches(evidence[key], r"[0-9a-f]{64}"), "invalid digest")
    require(evidence["public_zip_sha256"] == evidence["inner_zip_sha256"],
            "public ZIP differs from approved inner ZIP")
    require(evidence["public_zip_name"] == "SchneeGlass-" + evidence["version"] + "-adhoc.zip",
            "unexpected public ZIP name")
    require(evidence["code_signature"] == "adhoc", "wrong signature claim")
    require(evidence["apple_developer_id_signed"] is False
            and evidence["apple_notarized"] is False, "invalid Apple signing claims")
    timestamp = evidence["qa_approved_at"]
    require(matches(timestamp, r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"),
            "invalid QA timestamp")
    try:
        datetime.datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as exc:
        raise InvalidEvidence("invalid QA calendar timestamp") from exc
    return evidence


def validate_build_info(raw, evidence):
    expected = {
        "version": evidence["version"],
        "build": evidence["bundle_build"],
        "source_commit": evidence["source_sha"],
        "source_branch": "main",
        "code_signature": "adhoc",
        "apple_developer_id_signed": "false",
        "apple_notarized": "false",
        "minimum_macos": "15.0",
        "distribution": "github-adhoc",
    }
    parsed = {}
    # Explicit LF only; do not silently normalize malformed metadata.
    for line in raw.removesuffix("\n").split("\n"):
        key, separator, value = line.partition("=")
        require(separator == "=" and value and not any(ord(c) < 32 or ord(c) == 127 for c in value),
                "malformed BUILD_INFO")
        require(key not in parsed, "duplicate BUILD_INFO key")
        parsed[key] = value
    require(set(parsed) == set(expected) | {"executable_info"}, "unexpected BUILD_INFO fields")
    require(all(parsed[key] == value for key, value in expected.items()),
            "BUILD_INFO mismatch")


def archive_digest(directory_fd, name):
    digest = hashlib.sha256()
    total = 0
    with regular_file(directory_fd, name, ARCHIVE_LIMIT) as stream:
        while chunk := stream.read(65536):
            total += len(chunk)
            require(total <= ARCHIVE_LIMIT, "archive exceeds size limit")
            digest.update(chunk)
        require(total > 0, "empty archive")
    return digest.hexdigest()


def validate(directory, expected_tag, expected_sha):
    require(matches(expected_tag, r"v[0-9]+\.[0-9]+\.[0-9]+"), "invalid expected tag")
    require(matches(expected_sha, r"[0-9a-f]{40}"), "invalid expected SHA")
    directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        reject_legacy_evidence(directory_fd)
        evidence = validate_json(metadata(directory_fd, "ADHOC_RELEASE_EVIDENCE.json"),
                                 expected_tag, expected_sha)
        validate_build_info(metadata(directory_fd, "BUILD_INFO.txt"), evidence)
        expected_manifest = evidence["public_zip_sha256"] + "  " + evidence["public_zip_name"] + "\n"
        require(metadata(directory_fd, "SHA256SUMS") == expected_manifest, "SHA256SUMS mismatch")
        require(archive_digest(directory_fd, evidence["public_zip_name"])
                == evidence["public_zip_sha256"], "public ZIP digest mismatch")
        return evidence["bundle_build"]
    finally:
        os.close(directory_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", help="trusted, stable directory containing public assets")
    parser.add_argument("expected_tag", help="independently obtained release tag")
    parser.add_argument("expected_sha", help="independently resolved tag commit SHA")
    args = parser.parse_args()
    try:
        build = validate(args.directory, args.expected_tag, args.expected_sha)
    except (OSError, ValueError, RecursionError) as exc:
        print(f"Ad-hoc public evidence validation failed: {exc}", file=sys.stderr)
        return 1
    # Machine-readable normalized build only. Not authenticating API/QA here.
    print(build)
    return 0


if __name__ == "__main__":
    sys.exit(main())
