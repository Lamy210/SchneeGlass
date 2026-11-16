#!/usr/bin/env python3
"""Real file fixtures; all provenance values and ZIP bytes are synthetic."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().with_name("verify-adhoc-public-release-evidence.py")
SHA = "a" * 40
TAG = "v0.2.0"
NAME = "SchneeGlass-0.2.0-adhoc.zip"


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.archive = self.directory / NAME
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("Synthetic.txt", "fixture, not a macOS application\n")
        self.digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.evidence = {
            "schema_version": 1, "distribution": "github-adhoc",
            "repository_id": "1359347782", "tag": TAG, "version": "0.2.0",
            "bundle_identifier": "io.github.lamy210.schneeglass", "bundle_build": "3",
            "source_sha": SHA, "run_id": "9007199254740993", "run_attempt": "1",
            "artifact_id": "777", "outer_artifact_sha256": "b" * 64,
            "inner_zip_sha256": self.digest, "public_zip_name": NAME,
            "public_zip_sha256": self.digest, "qa_comment_id": "987654321",
            "qa_owner_id": "90091196", "qa_approved_at": "2026-01-02T03:04:05Z",
            "code_signature": "adhoc", "apple_developer_id_signed": False,
            "apple_notarized": False,
        }
        self.json_path = self.directory / "ADHOC_RELEASE_EVIDENCE.json"
        self.info_path = self.directory / "BUILD_INFO.txt"
        self.manifest = self.directory / "SHA256SUMS"
        self.info = (
            f"version=0.2.0\nbuild=3\nsource_commit={SHA}\nsource_branch=main\n"
            "code_signature=adhoc\napple_developer_id_signed=false\napple_notarized=false\n"
            "minimum_macos=15.0\nexecutable_info=synthetic-test\ndistribution=github-adhoc\n"
        )
        self.write_evidence()
        self.info_path.write_text(self.info, encoding="utf-8")
        self.manifest.write_text(f"{self.digest}  {NAME}\n", encoding="utf-8")

    def write_evidence(self, **changes):
        self.json_path.write_text(json.dumps(self.evidence | changes), encoding="utf-8")

    def run_validator(self, tag=TAG, sha=SHA, directory=None):
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(directory or self.directory), tag, sha],
            capture_output=True, text=True, timeout=10,
        )

    def reject(self, message, **kwargs):
        result = self.run_validator(**kwargs)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertIn(message, result.stderr)

    def test_valid(self):
        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "3\n")

    def test_invalid_field_variants(self):
        for key, value, diagnostic in [
            ("schema_version", True, "schema version"),
            ("schema_version", 1.0, "schema version"),
            ("schema_version", 2, "schema version"),
            ("distribution", "github-adhoc-candidate", "distribution"),
            ("repository_id", 1359347782, "repository"),
            ("qa_owner_id", "1", "owner"),
            ("tag", "v0.3.0", "tag/version"),
            ("source_sha", "c" * 40, "source SHA"),
            ("bundle_build", "18446744073709551616", "invalid build"),
            ("bundle_build", "03", "invalid build"),
            ("bundle_build", 3, "invalid build"),
            ("bundle_build", "0", "invalid build"),
            ("run_id", 9007199254740993, "decimal ID"),
            ("artifact_id", "01", "decimal ID"),
            ("qa_comment_id", "0", "decimal ID"),
            ("run_attempt", "2", "run attempt"),
            ("outer_artifact_sha256", "B" * 64, "invalid digest"),
            ("inner_zip_sha256", "c" * 64, "differs"),
            ("public_zip_name", "../" + NAME, "ZIP name"),
            ("bundle_identifier", "other", "bundle identifier"),
            ("apple_notarized", 0, "signing claims"),
            ("apple_developer_id_signed", True, "signing claims"),
            ("code_signature", "developer-id", "signature claim"),
            ("qa_approved_at", "2026-02-30T00:00:00Z", "calendar timestamp"),
            ("qa_approved_at", "2026-01-01T00:00:00+00:00", "QA timestamp"),
        ]:
            with self.subTest(key=key, value=value):
                self.write_evidence(**{key: value})
                self.reject(diagnostic)

    def test_malformed_json(self):
        for raw, diagnostic in [
            ('{"schema_version":1,"schema_version":1}', "duplicate JSON key"),
            (json.dumps(self.evidence | {"unexpected": True}), "unexpected JSON fields"),
            (json.dumps({k: v for k, v in self.evidence.items() if k != "run_id"}),
             "unexpected JSON fields"),
            ("[]", "unexpected JSON fields"),
            ('{"schema_version":NaN}', "nonstandard JSON constant"),
            (json.dumps(self.evidence) + "\n{}", "Extra data"),
            (" " * 16385, "asset size"),
        ]:
            with self.subTest(diagnostic=diagnostic):
                self.json_path.write_text(raw, encoding="utf-8")
                self.reject(diagnostic)
        self.json_path.write_bytes(b"\xff")
        self.reject("utf-8")

    def test_external_identity(self):
        self.reject("tag/version mismatch", tag="v0.3.0")
        self.reject("source SHA mismatch", sha="c" * 40)

    def test_wrong_public_build_info(self):
        for info, diagnostic in [
            (self.info.replace("build=3", "build=4"), "BUILD_INFO mismatch"),
            (self.info.replace("github-adhoc", "github-adhoc-candidate"), "BUILD_INFO mismatch"),
            (self.info + "build=3\n", "duplicate BUILD_INFO key"),
            (self.info + "notarization_id=fake\n", "unexpected BUILD_INFO fields"),
            (self.info.replace("\n", "\r\n"), "malformed BUILD_INFO"),
        ]:
            with self.subTest(diagnostic=diagnostic):
                self.info_path.write_bytes(info.encode("utf-8"))
                self.reject(diagnostic)

    def test_manifest_and_archive(self):
        original = self.manifest.read_bytes()
        for raw in [
            original + original,
            original.replace(NAME.encode(), b"unrelated.zip"),
            original.replace(b"  ", b" *"),
            original.rstrip(b"\n"),
        ]:
            self.manifest.write_bytes(raw)
            self.reject("SHA256SUMS mismatch")
        self.manifest.write_bytes(original)
        self.archive.write_bytes(b"tampered")
        self.reject("public ZIP digest mismatch")

    def test_mixed_evidence(self):
        legacy = self.directory / "RELEASE_EVIDENCE.txt"
        legacy.write_text("schema_version=1\nbundle_build=1\n", encoding="utf-8")
        self.reject("mixed ad-hoc and legacy evidence")
        legacy.unlink()
        legacy.symlink_to(self.directory / "missing")
        self.reject("mixed ad-hoc and legacy evidence")

    def test_nonregular_assets(self):
        for path in [self.json_path, self.info_path, self.manifest, self.archive]:
            with self.subTest(path=path.name):
                saved = path.with_suffix(path.suffix + ".saved")
                path.rename(saved)
                path.symlink_to(saved)
                self.reject("validation failed")
                path.unlink()
                os.mkfifo(path)
                self.reject("not a regular file")
                path.unlink()
                saved.rename(path)

    def test_missing_asset_and_symlink_root(self):
        self.manifest.unlink()
        self.reject("validation failed")
        root_link = self.directory / "link"
        root_link.symlink_to(self.directory, target_is_directory=True)
        self.reject("validation failed", directory=root_link)


if __name__ == "__main__":
    unittest.main(verbosity=2)
