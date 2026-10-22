#!/usr/bin/env python3
"""Verify an Actions artifact wrapper ZIP and extract only the six candidate files.

This is a read-only input validator. It does not publish or sign anything.
Expected digest/version must come from independently authenticated GitHub data.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import sys
from zipfile import BadZipFile, ZIP_DEFLATED, ZIP_STORED, ZipFile

CHUNK = 1024 * 1024
MAX_OUTER_BYTES = 1024 * 1024 * 1024
MAX_INNER_ARCHIVE_BYTES = 768 * 1024 * 1024
MAX_METADATA_BYTES = 4 * 1024 * 1024
MAX_COMPRESSION_RATIO = 200


class VerificationError(Exception):
    """Candidate archive is missing, invalid, or potentially unsafe."""


def verify_and_extract(
    source: Path, expected_digest: str, version: str, destination: Path
) -> None:
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", expected_digest):
        raise VerificationError("expected outer ZIP digest must be sha256:<64 lowercase hex>")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise VerificationError("expected version must be strict X.Y.Z")

    expected = {
        f"SchneeGlass-{version}-adhoc-candidate.zip",
        "BUILD_INFO.txt",
        "SHA256SUMS",
        "README.txt",
        "CODESIGN_DETAILS.txt",
        "ENTITLEMENTS.plist",
    }

    # Do not follow a symlink to a different ZIP, including a replacement
    # between the initial check and open. Read/verify/extract the same fd.
    if not stat.S_ISREG(source.lstat().st_mode):
        raise VerificationError("outer ZIP must be a regular file, not a symlink")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    with os.fdopen(os.open(source, flags), "rb") as handle:
        st = os.fstat(handle.fileno())
        if not stat.S_ISREG(st.st_mode) or not 0 < st.st_size <= MAX_OUTER_BYTES:
            raise VerificationError("outer ZIP must be a nonempty regular file within size limit")

        digest = hashlib.sha256()
        while chunk := handle.read(CHUNK):
            digest.update(chunk)
        if digest.hexdigest() != expected_digest.removeprefix("sha256:"):
            raise VerificationError("outer Actions ZIP SHA-256 mismatch")

        handle.seek(0)
        with ZipFile(handle, "r") as archive:
            infos = archive.infolist()
            names = [info.filename for info in infos]
            if len(infos) != len(expected) or set(names) != expected:
                raise VerificationError("outer ZIP has missing, duplicate or unexpected entries")

            for info in infos:
                kind = stat.S_IFMT(info.external_attr >> 16)
                if (
                    info.is_dir()
                    or kind not in (0, stat.S_IFREG)
                    or (info.flag_bits & 1)
                    or info.compress_type not in (ZIP_STORED, ZIP_DEFLATED)
                    or info.file_size <= 0
                    or info.compress_size <= 0
                ):
                    raise VerificationError(f"unsafe ZIP member: {info.filename}")
                limit = (
                    MAX_INNER_ARCHIVE_BYTES
                    if info.filename.endswith("-adhoc-candidate.zip")
                    else MAX_METADATA_BYTES
                )
                if info.file_size > limit:
                    raise VerificationError(f"oversized ZIP member: {info.filename}")
                if info.file_size > info.compress_size * MAX_COMPRESSION_RATIO:
                    raise VerificationError(f"excessive ZIP compression ratio: {info.filename}")

            parent = destination.absolute().parent
            if not stat.S_ISDIR(parent.lstat().st_mode):
                raise VerificationError("destination parent must be a real directory")
            # mkdir, rather than a replace/rename, is fail-closed on any
            # existing file, symlink or directory at the requested destination.
            destination.mkdir(mode=0o700, exist_ok=False)
            try:
                for info in infos:
                    # Flat, ASCII allowlisted basenames guarantee that no
                    # archive-supplied path can escape the new directory.
                    with archive.open(info, "r") as reader:
                        with (destination / info.filename).open("xb") as writer:
                            shutil.copyfileobj(reader, writer, CHUNK)
                    if (destination / info.filename).stat().st_size != info.file_size:
                        raise VerificationError(f"extracted size mismatch: {info.filename}")
            except BaseException:
                shutil.rmtree(destination)
                raise

    print(f"Verified Actions wrapper SHA-256 and extracted six candidate files: {destination}")


def main() -> int:
    if len(sys.argv) != 5:
        print(
            "usage: extract-verified-adhoc-actions-archive.py "
            "<downloaded-actions.zip> <sha256:64-hex> <X.Y.Z> <new-directory>",
            file=sys.stderr,
        )
        return 2
    try:
        verify_and_extract(
            Path(sys.argv[1]), sys.argv[2], sys.argv[3], Path(sys.argv[4])
        )
    except (VerificationError, OSError, BadZipFile, ValueError, EOFError) as exc:
        print(f"Actions artifact extraction rejected: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
