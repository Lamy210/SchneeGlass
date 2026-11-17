#!/usr/bin/env python3
"""Read and validate one immutable ad-hoc Release by authenticated IDs; never publish."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

REPO = "Lamy210/SchneeGlass"
PREFIX = "repos/" + REPO
ROOT = Path(__file__).resolve().parent
API_LIMIT = 1024 * 1024
METADATA_LIMIT = 16 * 1024
ARCHIVE_LIMIT = 1024 * 1024 * 1024
SHA = re.compile(r"[0-9a-f]{40}")


class InvalidRelease(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidRelease(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate API response key")
        result[key] = value
    return result


def invalid_constant(_):
    raise InvalidRelease("nonstandard API JSON constant")


def gh_stream(endpoint, accept, limit, consume):
    # Never use a caller-provided URL, filename pattern, or shell interpolation.
    command = ["gh", "api", "--hostname", "github.com", "--method", "GET",
               "-H", "Accept: " + accept, endpoint]
    with subprocess.Popen(command, stdout=subprocess.PIPE) as process:
        total = 0
        try:
            while True:
                chunk = process.stdout.read(min(65536, limit - total + 1))
                if not chunk:
                    break
                total += len(chunk)
                require(total <= limit, "API response exceeds size limit")
                consume(chunk)
            require(process.wait() == 0, "GitHub API request failed")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    return total


def api_json(endpoint):
    raw = bytearray()
    gh_stream(endpoint, "application/vnd.github+json", API_LIMIT, raw.extend)
    value = json.loads(raw, object_pairs_hook=unique_object, parse_constant=invalid_constant)
    require(type(value) is dict, "malformed API response")
    return value


def resolve_tag(tag):
    response = api_json(PREFIX + "/git/ref/tags/" + tag)
    require(response.get("ref") == "refs/tags/" + tag, "tag ref mismatch")
    obj = response.get("object")
    visited = set()
    # Annotated tags may refer to another tag; bound traversal and fail on cycles.
    for _ in range(16):
        require(type(obj) is dict, "malformed Git object")
        sha = obj.get("sha")
        require(type(sha) is str and SHA.fullmatch(sha), "invalid Git object SHA")
        if obj.get("type") == "commit":
            return sha
        require(obj.get("type") == "tag" and sha not in visited, "invalid tag target")
        visited.add(sha)
        nested = api_json(PREFIX + "/git/tags/" + sha)
        require(nested.get("sha") == sha, "annotated tag identity mismatch")
        obj = nested.get("object")
    raise InvalidRelease("annotated tag depth exceeded")


def release_assets(release_id, tag):
    release = api_json(PREFIX + "/releases/" + release_id)
    require(type(release.get("id")) is int and str(release["id"]) == release_id
            and release.get("tag_name") == tag, "release identity mismatch")
    require(release.get("draft") is False and release.get("immutable") is True,
            "release must be published and immutable")
    expected_names = {
        "ADHOC_RELEASE_EVIDENCE.json", "BUILD_INFO.txt", "SHA256SUMS",
        "SchneeGlass-" + tag[1:] + "-adhoc.zip",
    }
    assets = release.get("assets")
    require(type(assets) is list and len(assets) == len(expected_names),
            "unexpected release asset set")
    result = {}
    ids = set()
    for asset in assets:
        require(type(asset) is dict, "malformed release asset")
        name, asset_id = asset.get("name"), asset.get("id")
        require(type(name) is str and name in expected_names and name not in result,
                "unexpected or duplicate release asset")
        require(type(asset_id) is int and asset_id > 0 and asset_id not in ids,
                "invalid or duplicate asset ID")
        size = asset.get("size")
        limit = ARCHIVE_LIMIT if name.endswith(".zip") else METADATA_LIMIT
        require(type(size) is int and 0 < size <= limit, "invalid release asset size")
        digest = asset.get("digest")
        require(type(digest) is str and re.fullmatch(r"sha256:[0-9a-f]{64}", digest),
                "missing or invalid API asset digest")
        require(asset.get("state") == "uploaded", "release asset is not uploaded")
        ids.add(asset_id)
        result[name] = (asset_id, size, digest)
    require(set(result) == expected_names, "incomplete release asset set")
    return result


def download_asset(directory, name, identity):
    asset_id, size, digest = identity
    calculated = hashlib.sha256()
    with (directory / name).open("xb") as output:
        def consume(chunk):
            output.write(chunk)
            calculated.update(chunk)
        actual = gh_stream(PREFIX + "/releases/assets/" + str(asset_id),
                           "application/octet-stream", size, consume)
    require(actual == size, "downloaded release asset size mismatch")
    require("sha256:" + calculated.hexdigest() == digest, "downloaded release asset digest mismatch")


def validate_release(release_id, tag):
    require(re.fullmatch(r"[1-9][0-9]*", release_id), "invalid release ID")
    require(re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag), "invalid release tag")
    # Known public releases predate this immutable schema and must retain pins.
    with (ROOT.parent / "docs/release-history/legacy-public-releases.tsv").open() as pins:
        legacy = {line.split("\t")[0] for line in pins if line.strip() and not line.startswith("#")}
    require(tag not in legacy, "legacy release requires pinned verification")
    repository = api_json(PREFIX)
    require(type(repository.get("id")) is int and repository["id"] == 1359347782
            and repository.get("full_name") == REPO, "repository identity mismatch")
    assets = release_assets(release_id, tag)
    commit = resolve_tag(tag)
    with tempfile.TemporaryDirectory(prefix="schneeglass-public-release-") as temporary:
        directory = Path(temporary)
        for name, identity in sorted(assets.items()):
            download_asset(directory, name, identity)
        build = subprocess.run(
            [sys.executable, str(ROOT / "verify-adhoc-public-release-evidence.py"),
             str(directory), tag, commit],
            check=True, stdout=subprocess.PIPE, text=True,
        ).stdout
        require(re.fullmatch(r"[1-9][0-9]{0,8}\n", build), "invalid normalized build")
        # A second authenticated read detects changes during the validation window.
        require(release_assets(release_id, tag) == assets, "release assets changed during validation")
        require(resolve_tag(tag) == commit, "release tag changed during validation")
        return build.rstrip("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release_id")
    parser.add_argument("tag")
    args = parser.parse_args()
    try:
        build = validate_release(args.release_id, args.tag)
    except (OSError, ValueError, RecursionError, subprocess.CalledProcessError) as exc:
        print(f"Authenticated ad-hoc public release validation failed: {exc}", file=sys.stderr)
        return 1
    print(build)
    return 0


if __name__ == "__main__":
    sys.exit(main())
