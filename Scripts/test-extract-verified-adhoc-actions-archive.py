#!/usr/bin/env python3
"""Positive and adversarial fixtures for the outer Actions artifact ZIP gate."""
from __future__ import annotations

import hashlib
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

SCRIPT = Path(__file__).with_name("extract-verified-adhoc-actions-archive.py")
INNER = "SchneeGlass-0.2.0-adhoc-candidate.zip"
FILES = {
    INNER: b"synthetic inner ZIP placeholder, not an app",
    "BUILD_INFO.txt": b"version=0.2.0\nbuild=3\n",
    "SHA256SUMS": b"synthetic checksum placeholder",
    "README.txt": b"synthetic documentation",
    "CODESIGN_DETAILS.txt": b"synthetic ad-hoc info",
    "ENTITLEMENTS.plist": b"synthetic entitlements",
}


class ArtifactArchiveTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.outer = self.root / "downloaded-artifact.zip"
        self.output = self.root / "verified-candidate"

    def make_archive(
        self,
        entries: list[tuple[str | ZipInfo, bytes]] | None = None,
        *,
        compression: int = ZIP_DEFLATED,
    ) -> str:
        with ZipFile(self.outer, "w", compression=compression) as archive:
            for name, data in entries if entries is not None else FILES.items():
                archive.writestr(name, data)
        return "sha256:" + hashlib.sha256(self.outer.read_bytes()).hexdigest()

    def run_gate(
        self, digest: str, *, version: str = "0.2.0", source: Path | None = None,
        output: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable, str(SCRIPT), str(source or self.outer),
                digest, version, str(output or self.output),
            ],
            text=True, capture_output=True, check=False,
        )

    def assert_rejected(self, digest: str, expected: str, **kwargs: object) -> None:
        result = self.run_gate(digest, **kwargs)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(expected, result.stderr)
        self.assertFalse(self.output.exists(), "failed extraction left partial output")

    def test_valid_candidate_and_permissions(self) -> None:
        digest = self.make_archive()
        response = self.run_gate(digest)
        self.assertEqual(response.returncode, 0, response.stderr)
        self.assertEqual({p.name for p in self.output.iterdir()}, set(FILES))
        for name, payload in FILES.items():
            self.assertEqual((self.output / name).read_bytes(), payload)
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o700)

    def test_existing_destination_never_overwritten(self) -> None:
        digest = self.make_archive()
        self.output.mkdir()
        marker = self.output / "user-owned-file"
        marker.write_text("preserve", encoding="utf-8")
        result = self.run_gate(digest)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(marker.read_text(encoding="utf-8"), "preserve")

    def test_outer_archive_digest_mismatch(self) -> None:
        self.make_archive()
        self.assert_rejected("sha256:" + "0" * 64, "SHA-256 mismatch")

    def test_unrecognized_digest_or_version(self) -> None:
        digest = self.make_archive()
        self.assert_rejected("md5:" + "0" * 64, "digest must be sha256")
        self.assert_rejected(digest, "version must be strict", version="../0.2.0")

    def test_tampered_outer_archive(self) -> None:
        digest = self.make_archive()
        with self.outer.open("ab") as handle:
            handle.write(b"untrusted trailing content")
        self.assert_rejected(digest, "SHA-256 mismatch")

    def test_outer_symlink_rejected(self) -> None:
        digest = self.make_archive()
        alias = self.root / "symlink.zip"
        alias.symlink_to(self.outer)
        self.assert_rejected(digest, "regular file", source=alias)

    def test_destination_parent_symlink_rejected(self) -> None:
        digest = self.make_archive()
        alias = self.root / "linked-dir"
        alias.symlink_to(self.root, target_is_directory=True)
        result = self.run_gate(digest, output=alias / "candidate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("destination parent", result.stderr)
        self.assertFalse((self.root / "candidate").exists())

    def test_unexpected_archive_path(self) -> None:
        for invalid in ("../escape.txt", "/tmp/escape.txt", "nested/other.txt"):
            with self.subTest(invalid=invalid):
                entries = list(FILES.items()) + [(invalid, b"x")]
                digest = self.make_archive(entries)
                self.assert_rejected(digest, "missing, duplicate or unexpected")

    def test_missing_and_duplicate_entries(self) -> None:
        digest = self.make_archive(list(FILES.items())[:-1])
        self.assert_rejected(digest, "missing, duplicate or unexpected")
        digest = self.make_archive(list(FILES.items()) + [(INNER, b"duplicate")])
        self.assert_rejected(digest, "missing, duplicate or unexpected")

    def test_member_symlink_rejected(self) -> None:
        info = ZipInfo("README.txt")
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        entries: list[tuple[str | ZipInfo, bytes]] = [
            (info if name == "README.txt" else name, payload)
            for name, payload in FILES.items()
        ]
        digest = self.make_archive(entries)
        self.assert_rejected(digest, "unsafe ZIP member")

    def test_oversized_metadata_rejected(self) -> None:
        entries = [
            (name, b"x" * (4 * 1024 * 1024 + 1) if name == "README.txt" else data)
            for name, data in FILES.items()
        ]
        digest = self.make_archive(entries)
        self.assert_rejected(digest, "oversized ZIP member")

    def test_high_compression_ratio_rejected(self) -> None:
        entries = [
            (name, b"0" * (1024 * 1024) if name == "README.txt" else data)
            for name, data in FILES.items()
        ]
        digest = self.make_archive(entries)
        self.assert_rejected(digest, "excessive ZIP compression ratio")

    def test_corrupted_zip_rejected(self) -> None:
        self.outer.write_bytes(b"not a ZIP at all")
        digest = "sha256:" + hashlib.sha256(self.outer.read_bytes()).hexdigest()
        self.assert_rejected(digest, "not a zip file")


if __name__ == "__main__":
    unittest.main(verbosity=2)
