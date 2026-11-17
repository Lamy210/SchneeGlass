#!/usr/bin/env python3
"""Prepare verified-public-asset bytes locally; never create a GitHub tag or Release."""

import argparse
import ctypes
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location(
    "public_evidence", ROOT / "verify-adhoc-public-release-evidence.py"
)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
require = validator.require


def run_gate(name, args, capture=False):
    result = subprocess.run(
        ["bash", str(ROOT / name), *map(str, args)], check=True,
        stdout=subprocess.PIPE if capture else sys.stderr, text=True,
    )
    return result.stdout if capture else None


def copy_and_digest(directory_fd, name, destination=None):
    digest = hashlib.sha256()
    total = 0
    with validator.regular_file(directory_fd, name, validator.ARCHIVE_LIMIT) as stream:
        if destination is None:
            while chunk := stream.read(65536):
                total += len(chunk)
                require(total <= validator.ARCHIVE_LIMIT, "archive exceeds size limit")
                digest.update(chunk)
        else:
            with destination.open("xb") as output:
                while chunk := stream.read(65536):
                    total += len(chunk)
                    require(total <= validator.ARCHIVE_LIMIT, "archive exceeds size limit")
                    output.write(chunk)
                    digest.update(chunk)
        require(total > 0, "empty archive")
    return digest.hexdigest()


def exclusive_promote(source, destination):
    # Same local filesystem, no replace, even if an empty directory appears.
    libc = ctypes.CDLL(None, use_errno=True)
    if sys.platform == "darwin":
        rename = getattr(libc, "renameatx_np", None)
        flag = 0x00000004  # RENAME_EXCL
    elif sys.platform.startswith("linux"):
        rename = getattr(libc, "renameat2", None)
        flag = 1  # RENAME_NOREPLACE
    else:
        raise validator.InvalidEvidence("exclusive directory promotion unsupported")
    require(rename is not None, "native exclusive directory promotion unavailable")
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    source_fd = os.open(source.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        destination_fd = os.open(destination.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            if rename(source_fd, os.fsencode(source.name),
                      destination_fd, os.fsencode(destination.name), flag) != 0:
                error = ctypes.get_errno()
                raise OSError(error, "exclusive public asset promotion failed: " + os.strerror(error))
        finally:
            os.close(destination_fd)
    finally:
        os.close(source_fd)


def prepare(args):
    run_id, artifact_id, version, build, source_sha, comment_id = (
        args.run_id, args.artifact_id, args.version, args.build, args.source_sha, args.comment_id
    )
    for identity in (run_id, artifact_id, comment_id):
        require(re.fullmatch(r"[1-9][0-9]*", identity), "invalid positive ID")
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version), "invalid version")
    require(re.fullmatch(r"[1-9][0-9]{0,8}", build), "invalid build")
    require(re.fullmatch(r"[0-9a-f]{40}", source_sha), "invalid source SHA")
    output = args.output
    require(output.name not in {"", ".", ".."} and output.parent.is_dir()
            and not output.parent.is_symlink(), "output needs a real parent directory")
    output = output.parent.resolve() / output.name
    require(not os.path.lexists(output), "output already exists")
    outer = args.outer_zip
    # All candidate/history/public asset files stay in an invocation-owned stage.
    with tempfile.TemporaryDirectory(prefix=".schneeglass-public-assets-", dir=output.parent) as tmp:
        workspace = Path(tmp)
        candidate, history, public = workspace / "candidate", workspace / "history", workspace / "public"
        run_gate("verify-adhoc-publication-preflight.sh",
                 [run_id, artifact_id, version, build, source_sha, comment_id, outer, candidate, history])
        public.mkdir(mode=0o700)
        public_name = f"SchneeGlass-{version}-adhoc.zip"
        candidate_fd = os.open(candidate, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            inner_digest = copy_and_digest(
                candidate_fd, f"SchneeGlass-{version}-adhoc-candidate.zip", public / public_name
            )
            info = validator.metadata(candidate_fd, "BUILD_INFO.txt")
        finally:
            os.close(candidate_fd)
        # Require an exact single candidate distribution field, not a broad replacement.
        lines = info.split("\n")
        require(lines.count("distribution=github-adhoc-candidate") == 1,
                "candidate distribution missing or duplicated")
        lines[lines.index("distribution=github-adhoc-candidate")] = "distribution=github-adhoc"
        (public / "BUILD_INFO.txt").write_text("\n".join(lines), encoding="utf-8")
        (public / "SHA256SUMS").write_text(f"{inner_digest}  {public_name}\n", encoding="utf-8")

        # Check the actual copied public bytes against authenticated, unedited owner QA.
        # Never accept a caller-supplied QA timestamp or claimed approval.
        qa = run_gate("verify-adhoc-qa-comment-from-github.sh",
                      [comment_id, run_id, version, build, source_sha, inner_digest], capture=True)
        prefix = (f"Verified GitHub owner QA approval comment ID={comment_id} run={run_id} "
                  f"source={source_sha} inner_zip_sha256={inner_digest} approved_at=")
        require(qa.startswith(prefix) and qa.endswith("\n"), "malformed authenticated QA response")
        approved_at = qa[len(prefix):-1]

        outer_fd = os.open(outer.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            outer_digest = copy_and_digest(outer_fd, outer.name)
        finally:
            os.close(outer_fd)
        run_gate("verify-current-release-governance.sh", ["Lamy210/SchneeGlass"])
        report = run_gate("verify-adhoc-run-artifact-from-github.sh",
                          [run_id, version, source_sha], capture=True)
        require(report == f"artifact_id={artifact_id}\nartifact_digest=sha256:{outer_digest}\n",
                "authenticated outer artifact identity changed")
        run_gate("verify-adhoc-release-slot.sh", ["v" + version])

        evidence = {
            "schema_version": 1, "distribution": "github-adhoc",
            "repository_id": "1359347782", "tag": "v" + version, "version": version,
            "bundle_identifier": "io.github.lamy210.schneeglass", "bundle_build": build,
            "source_sha": source_sha, "run_id": run_id, "run_attempt": "1",
            "artifact_id": artifact_id, "outer_artifact_sha256": outer_digest,
            "inner_zip_sha256": inner_digest, "public_zip_name": public_name,
            "public_zip_sha256": inner_digest, "qa_comment_id": comment_id,
            "qa_owner_id": "90091196", "qa_approved_at": approved_at,
            "code_signature": "adhoc", "apple_developer_id_signed": False, "apple_notarized": False,
        }
        with (public / "ADHOC_RELEASE_EVIDENCE.json").open("x", encoding="utf-8") as stream:
            json.dump(evidence, stream, indent=2, sort_keys=True)
            stream.write("\n")
        require(validator.validate(public, "v" + version, source_sha) == build,
                "prepared public asset set failed validation")
        exclusive_promote(public, output)
    # The caller must run fresh preflight and read-back validation before publishing.
    print(f"Prepared local public assets (NOT publication authorization): {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ("run_id", "artifact_id", "version", "build", "source_sha", "comment_id"):
        parser.add_argument(field)
    parser.add_argument("outer_zip", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        prepare(args)
    except (OSError, ValueError, RecursionError, subprocess.CalledProcessError) as exc:
        print(f"Ad-hoc public asset preparation failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
