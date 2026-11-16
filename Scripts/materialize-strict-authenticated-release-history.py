#!/usr/bin/env python3
"""Materialize a full authenticated release inventory into a private history stage."""

import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

# Reuse the exact-ID and bounded streaming reader; do not implement a second downloader.
ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "authenticated_release", ROOT / "verify-authenticated-adhoc-public-release.py"
)
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)
require = reader.require
LEGACY = ROOT.parent / "docs/release-history/legacy-public-releases.tsv"


def inventory(path):
    with path.open("rb") as stream:
        raw = stream.read(16 * 1024 * 1024 + 1)
    require(len(raw) <= 16 * 1024 * 1024, "inventory size limit")
    pages = json.loads(raw, object_pairs_hook=reader.unique_object,
                       parse_constant=reader.invalid_constant)
    require(type(pages) is list and pages, "invalid inventory")
    result, ids = {}, set()
    for page in pages:
        require(type(page) is list, "invalid inventory page")
        for release in page:
            require(type(release) is dict, "invalid inventory entry")
            identity, tag, draft = release.get("id"), release.get("tag_name"), release.get("draft")
            require(type(identity) is int and identity > 0 and identity not in ids,
                    "invalid or duplicate release ID")
            require(type(tag) is str and tag and type(draft) is bool, "invalid inventory fields")
            ids.add(identity)
            if not draft:
                require(re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag) and tag not in result,
                        "invalid or duplicate published tag")
                result[tag] = str(identity)
    return result


def legacy_pins():
    result = {}
    for line in LEGACY.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        columns = line.split("\t")
        require(len(columns) == 6, "malformed legacy manifest")
        tag, commit, version, build, distribution, digest = columns
        require(re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag) and tag not in result
                and tag == "v" + version and reader.SHA.fullmatch(commit)
                and re.fullmatch(r"[1-9][0-9]*", build)
                and distribution in {"github-unsigned", "github-adhoc"}
                and re.fullmatch(r"[0-9a-f]{64}", digest), "malformed legacy pin")
        result[tag] = (commit, build, digest)
    require(bool(result), "missing legacy manifest entries")
    return result


def release_metadata(identity, tag):
    release = reader.api_json(reader.PREFIX + "/releases/" + identity)
    require(type(release.get("id")) is int and str(release["id"]) == identity
            and release.get("tag_name") == tag and release.get("draft") is False,
            "release identity mismatch")
    assets = release.get("assets")
    require(type(assets) is list, "malformed release asset list")
    by_name, ids = {}, set()
    for asset in assets:
        require(type(asset) is dict, "malformed release asset")
        name, asset_id = asset.get("name"), asset.get("id")
        require(type(name) is str and name and name not in by_name, "duplicate release asset")
        require(type(asset_id) is int and asset_id > 0 and asset_id not in ids,
                "invalid or duplicate release asset ID")
        by_name[name] = asset
        ids.add(asset_id)
    return release, by_name


def metadata_asset(assets, name):
    require(name in assets, "missing historical metadata asset")
    asset = assets[name]
    size, digest = asset.get("size"), asset.get("digest")
    require(type(size) is int and 0 < size <= reader.METADATA_LIMIT
            and type(digest) is str and re.fullmatch(r"sha256:[0-9a-f]{64}", digest)
            and asset.get("state") == "uploaded", "invalid historical metadata asset identity")
    return asset["id"], size, digest


def build_for_release(identity, tag, pins, directory):
    release, assets = release_metadata(identity, tag)
    commit = reader.resolve_tag(tag)
    adhoc = "ADHOC_RELEASE_EVIDENCE.json" in assets
    notarized = "RELEASE_EVIDENCE.txt" in assets
    require(not (adhoc and notarized), "mixed public evidence schemas")
    if tag in pins:
        # The known mutable grandfathered releases MUST use pinned BUILD_INFO.
        # Evidence added later cannot bypass the immutable legacy pins.
        require(not adhoc and not notarized, "legacy evidence override")
        expected_commit, expected_build, expected_digest = pins[tag]
        require(commit == expected_commit, "legacy tag commit mismatch")
        info = metadata_asset(assets, "BUILD_INFO.txt")
        require(info[2] == "sha256:" + expected_digest, "legacy BUILD_INFO API digest mismatch")
        reader.download_asset(directory, "BUILD_INFO.txt", info)
        build = subprocess.run(
            ["bash", str(ROOT / "verify-legacy-release-build-info.sh"),
             str(LEGACY), tag, commit, str(directory / "BUILD_INFO.txt")],
            check=True, stdout=subprocess.PIPE, text=True,
        ).stdout
        require(build == expected_build + "\n", "legacy build mismatch")
        build = build.rstrip("\n")
    elif adhoc:
        require(release.get("immutable") is True, "ad-hoc history must be immutable")
        build = reader.validate_release(identity, tag)
    elif notarized:
        require(release.get("immutable") is True, "notarized history must be immutable")
        # Historical notarized schema lacks archive digests. Verify its historical
        # evidence, not a claim of independent signature or ZIP verification.
        evidence = metadata_asset(assets, "RELEASE_EVIDENCE.txt")
        name = "RELEASE_EVIDENCE.txt"
        reader.download_asset(directory, name, evidence)
        subprocess.run(["bash", str(ROOT / "verify-release-evidence.sh"),
                        str(directory / name), tag[1:], commit],
                       check=True, stdout=subprocess.DEVNULL)
        builds = [line.split("=", 1)[1] for line in (directory / name).read_text().splitlines()
                  if line.startswith("bundle_build=")]
        require(len(builds) == 1, "invalid historical notarized build")
        build = builds[0]
        # Preserve original evidence by a different name; comparator only reads normalized files.
        (directory / name).rename(directory / "NOTARIZED_EVIDENCE.txt")
    else:
        raise reader.InvalidRelease("unknown or missing public evidence schema")
    require(re.fullmatch(r"[1-9][0-9]*", build), "invalid normalized build")
    # For all schema paths bind to the same release metadata and actual tag.
    again, again_assets = release_metadata(identity, tag)
    require(again.get("immutable") == release.get("immutable") and again_assets == assets
            and reader.resolve_tag(tag) == commit, "historical release changed")
    with (directory / "RELEASE_EVIDENCE.txt").open("x", encoding="utf-8") as output:
        output.write("schema_version=1\nbundle_build=" + build + "\n")
    with (directory / "release.json").open("x", encoding="utf-8") as output:
        json.dump({"release_id": identity, "tag": tag, "source_sha": commit,
                   "immutable": release.get("immutable"), "metadata": release}, output)
        output.write("\n")


def materialize(inventory_path, history):
    require(history.is_dir() and not history.is_symlink() and not any(history.iterdir()),
            "history stage must be an empty real directory")
    repository = reader.api_json(reader.PREFIX)
    require(type(repository.get("id")) is int and repository["id"] == 1359347782
            and repository.get("full_name") == reader.REPO, "repository identity mismatch")
    releases = inventory(inventory_path)
    pins = legacy_pins()
    require(set(pins) <= set(releases), "missing pinned historical release")
    for index, tag in enumerate(sorted(releases), 1):
        directory = history / str(index)
        directory.mkdir(mode=0o700)
        build_for_release(releases[tag], tag, pins, directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inventory", type=Path)
    parser.add_argument("private_history_stage", type=Path)
    args = parser.parse_args()
    try:
        materialize(args.inventory, args.private_history_stage)
    except (OSError, ValueError, RecursionError, subprocess.CalledProcessError) as exc:
        print(f"Strict authenticated history failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
