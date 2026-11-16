#!/usr/bin/env python3
"""Verify exact draft or published ad-hoc assets against prepared local bytes."""

import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import re
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = load_module("release_reader", "verify-authenticated-adhoc-public-release.py")
validator = load_module("public_evidence", "verify-adhoc-public-release-evidence.py")
require = reader.require


def asset_names(tag):
    return {"ADHOC_RELEASE_EVIDENCE.json", "BUILD_INFO.txt", "SHA256SUMS",
            "SchneeGlass-" + tag[1:] + "-adhoc.zip"}


def local_assets(directory, tag):
    names = asset_names(tag)
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        require(set(os.listdir(fd)) == names, "unexpected prepared local asset set")
        assets = {}
        for name in sorted(names):
            size_limit = validator.ARCHIVE_LIMIT if name.endswith(".zip") else validator.METADATA_LIMIT
            digest = hashlib.sha256()
            size = 0
            with validator.regular_file(fd, name, size_limit) as stream:
                while chunk := stream.read(65536):
                    size += len(chunk)
                    require(size <= size_limit, "prepared asset exceeds limit")
                    digest.update(chunk)
            require(size > 0, "empty prepared asset")
            assets[name] = (size, "sha256:" + digest.hexdigest())
        return assets
    finally:
        os.close(fd)


def remote_assets(identity, tag, phase):
    release = reader.api_json(reader.PREFIX + "/releases/" + identity)
    require(type(release.get("id")) is int and str(release["id"]) == identity
            and release.get("tag_name") == tag, "release identity mismatch")
    require(release.get("prerelease") is False, "unexpected prerelease state")
    if phase == "draft":
        require(release.get("draft") is True and release.get("immutable") is False,
                "expected mutable draft release")
    else:
        require(release.get("draft") is False and release.get("immutable") is True,
                "expected published immutable release")
    names = asset_names(tag)
    assets = release.get("assets")
    require(type(assets) is list and len(assets) == len(names), "unexpected remote asset set")
    observed, ids = {}, set()
    for asset in assets:
        require(type(asset) is dict, "malformed release asset")
        name, asset_id = asset.get("name"), asset.get("id")
        require(type(name) is str and name in names and name not in observed,
                "unexpected or duplicate remote asset")
        require(type(asset_id) is int and asset_id > 0 and asset_id not in ids,
                "invalid or duplicate asset ID")
        size, digest = asset.get("size"), asset.get("digest")
        limit = validator.ARCHIVE_LIMIT if name.endswith(".zip") else validator.METADATA_LIMIT
        require(type(size) is int and 0 < size <= limit, "invalid remote asset size")
        require(type(digest) is str and re.fullmatch(r"sha256:[0-9a-f]{64}", digest),
                "missing or malformed remote digest")
        require(asset.get("state") == "uploaded", "remote asset upload incomplete")
        observed[name] = (asset_id, size, digest)
        ids.add(asset_id)
    require(set(observed) == names, "incomplete remote asset set")
    return observed


def verify(directory, identity, tag, source_sha, phase):
    require(phase in {"draft", "published"}, "unsupported read-back phase")
    require(re.fullmatch(r"[1-9][0-9]*", identity), "invalid release ID")
    require(re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag), "invalid tag")
    require(reader.SHA.fullmatch(source_sha), "invalid expected source SHA")
    pins = ROOT.parent / "docs/release-history/legacy-public-releases.tsv"
    with pins.open(encoding="utf-8") as file:
        require(not any(line.split("\t")[0] == tag for line in file), "legacy tag not eligible")
    expected = local_assets(directory, tag)
    build = validator.validate(directory, tag, source_sha)
    require(local_assets(directory, tag) == expected, "prepared local assets changed")
    repo = reader.api_json(reader.PREFIX)
    require(type(repo.get("id")) is int and repo["id"] == 1359347782
            and repo.get("full_name") == reader.REPO, "repository identity mismatch")
    require(reader.resolve_tag(tag) == source_sha, "actual tag commit mismatch")
    remote = remote_assets(identity, tag, phase)
    require({name: value[1:] for name, value in remote.items()} == expected,
            "remote assets differ from prepared assets")
    with tempfile.TemporaryDirectory(prefix="schneeglass-release-readback-") as stage:
        received = Path(stage)
        for name, value in sorted(remote.items()):
            reader.download_asset(received, name, value)
        require(local_assets(received, tag) == expected, "downloaded bytes differ from prepared assets")
        require(validator.validate(received, tag, source_sha) == build, "remote build mismatch")
    require(remote_assets(identity, tag, phase) == remote, "remote assets changed during read-back")
    require(reader.resolve_tag(tag) == source_sha, "tag changed during read-back")
    require(local_assets(directory, tag) == expected, "prepared local assets changed during read-back")
    return build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("draft", "published"))
    parser.add_argument("prepared_directory", type=Path)
    parser.add_argument("release_id")
    parser.add_argument("tag")
    parser.add_argument("source_sha")
    args = parser.parse_args()
    try:
        build = verify(args.prepared_directory, args.release_id, args.tag, args.source_sha, args.phase)
    except (OSError, ValueError, RecursionError) as exc:
        print(f"Ad-hoc release read-back failed: {exc}", file=sys.stderr)
        return 1
    print(f"Verified {args.phase} release {args.release_id} tag={args.tag} build={build}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
