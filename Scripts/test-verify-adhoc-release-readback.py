#!/usr/bin/env python3
"""Synthetic GitHub transport, real local and retrieved assets."""

import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "reader_fixture", ROOT / "test-verify-authenticated-adhoc-public-release.py"
)
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class ReadbackTests(fixture.ReleaseReaderTests):
    # Reuse the authenticated reader's synthetic API, without inheriting its
    # independent reader-specific cases into this suite (see load_tests).
    def setUp(self):
        super().setUp()
        self.prepared = self.root / "prepared"
        self.prepared.mkdir()
        for asset in self.assets:
            shutil.copyfile(self.root / f"asset-{asset['id']}", self.prepared / asset["name"])
        self.release["prerelease"] = False
        self.write_json("release.json", self.release)

    def run_readback(self, phase="published", tag=fixture.TAG, sha=fixture.SHA):
        return subprocess.run(
            [sys.executable, str(ROOT / "verify-adhoc-release-readback.py"),
             phase, str(self.prepared), "123", tag, sha],
            env=self.env, capture_output=True, text=True, timeout=30,
        )

    def reject_readback(self, message, phase="published", **kwargs):
        result = self.run_readback(phase, **kwargs)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertIn(message, result.stderr)

    def test_readback_published_and_draft_states(self):
        result = self.run_readback()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Verified published release 123", result.stdout)
        self.reject_readback("expected mutable draft", phase="draft")
        self.release.update(draft=True, immutable=False)
        self.write_json("release.json", self.release)
        result = self.run_readback("draft")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Verified draft release 123", result.stdout)
        self.reject_readback("expected published immutable")

    def test_readback_wrong_identity_and_state(self):
        for changes, message in [
            ({"id": 124}, "release identity mismatch"),
            ({"tag_name": "v0.3.0"}, "release identity mismatch"),
            ({"immutable": False}, "expected published immutable"),
            ({"prerelease": True}, "unexpected prerelease"),
        ]:
            with self.subTest(changes=changes):
                self.write_json("release.json", self.release | changes)
                self.reject_readback(message)

    def test_readback_valid_but_different_evidence(self):
        # The alternate public evidence is independently valid, but not
        # byte-identical to the prepared and authorized local asset set.
        evidence = self.root / "asset-101"
        parsed = json.loads(evidence.read_text())
        parsed["qa_comment_id"] = "999"
        evidence.write_text(json.dumps(parsed))
        self.assets[0]["size"] = evidence.stat().st_size
        self.assets[0]["digest"] = "sha256:" + self.digest("asset-101")
        self.write_json("release.json", self.release)
        self.reject_readback("remote assets differ from prepared assets")

    def test_readback_download_tamper_and_tag_change(self):
        archive = self.root / "asset-104"
        data = archive.read_bytes()
        archive.write_bytes(data[:-1] + bytes([data[-1] ^ 1]))
        self.reject_readback("digest mismatch")
        archive.write_bytes(data)
        (self.root / "change-ref").touch()
        self.reject_readback("tag changed during read-back")

    def test_readback_prepared_local_extra_and_tamper(self):
        extra = self.prepared / "README.txt"
        extra.write_text("not an approved publication asset")
        self.reject_readback("unexpected prepared local asset set")
        extra.unlink()
        (self.prepared / fixture.NAME).write_bytes(b"tampered")
        self.reject_readback("public ZIP digest mismatch")

    def test_readback_rejects_wrong_git_tag(self):
        self.ref["object"]["sha"] = "c" * 40
        self.write_json("ref.json", self.ref)
        self.reject_readback("actual tag commit mismatch")


def load_tests(loader, tests, pattern):
    return unittest.TestSuite(
        ReadbackTests(name) for name in loader.getTestCaseNames(ReadbackTests)
        if name.startswith("test_readback_")
    )


if __name__ == "__main__":
    unittest.main(verbosity=2)
