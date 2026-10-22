#!/usr/bin/env python3
"""Mocked, credential-free regression fixtures for exact-ID Actions ZIP download."""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "Scripts/download-verified-adhoc-actions-artifact.sh"
SHA = "0123456789abcdef0123456789abcdef01234567"


class DownloadFixtures(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.archive = self.work / "source.zip"
        self.dest = self.work / "verified.zip"
        with ZipFile(self.archive, "w") as z:
            z.writestr("README.txt", b"synthetic outer Actions ZIP")
        self.digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        bash = self.bin / "bash"
        bash.write_text(
            """#!/bin/bash
set -euo pipefail
[[ "$#" -eq 4 && "$1" == */Scripts/verify-adhoc-run-artifact-from-github.sh &&
   "$2" == 123456789 && "$3" == 0.2.0 && "$4" == "$MOCK_SHA" ]] || exit 45
printf 'call\\n' >> "$MOCK_DIR/checks"
count="$(wc -l < "$MOCK_DIR/checks" | tr -d '[:space:]')"
if [[ "$MOCK_PROVENANCE_FAIL" == "$count" ]]; then exit 46; fi
digest="$MOCK_DIGEST"
if [[ "$count" -eq 2 && -n "$MOCK_SECOND_DIGEST" ]]; then
  digest="$MOCK_SECOND_DIGEST"
fi
printf 'artifact_id=%s\\nartifact_digest=sha256:%s\\n' "$MOCK_ID" "$digest"
""", encoding="utf-8"
        )
        bash.chmod(0o700)
        gh = self.bin / "gh"
        gh.write_text(
            """#!/bin/bash
set -euo pipefail
[[ "$#" -eq 2 && "$1" == api &&
   "$2" == repos/Lamy210/SchneeGlass/actions/artifacts/777/zip ]] || exit 47
printf 'call\\n' >> "$MOCK_DIR/downloads"
[[ "$MOCK_DOWNLOAD_FAIL" != 1 ]] || exit 48
[[ "$MOCK_DOWNLOAD_EMPTY" != 1 ]] || exit 0
cat "$MOCK_SOURCE"
""", encoding="utf-8"
        )
        gh.chmod(0o700)

    def run_gate(self, **changes: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["PATH"] = str(self.bin) + os.pathsep + env["PATH"]
        values = {
            "MOCK_DIR": str(self.work), "GH_BIN": str(self.bin / "gh"),
            "MOCK_SHA": SHA, "MOCK_ID": "777", "MOCK_DIGEST": self.digest,
            "MOCK_SECOND_DIGEST": "", "MOCK_PROVENANCE_FAIL": "0",
            "MOCK_SOURCE": str(self.archive), "MOCK_DOWNLOAD_FAIL": "0",
            "MOCK_DOWNLOAD_EMPTY": "0",
            "RUN_ID": "123456789", "DEST": str(self.dest),
        }
        values.update(changes)
        env.update(values)
        return subprocess.run(
            ["/bin/bash", str(SCRIPT), values["RUN_ID"], "777", "0.2.0",
             SHA, values["DEST"]],
            cwd=ROOT, env=env, capture_output=True, text=True, check=False,
        )

    def assert_rejected(self, contains: str, **kwargs: str) -> None:
        result = self.run_gate(**kwargs)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(contains, result.stderr)
        self.assertFalse(self.dest.exists(), "a failed gate left a published ZIP")
        self.assertEqual(list(self.work.glob(".schneeglass-actions-zip.*")), [])

    def test_valid_binary_preserved_exactly_and_rechecked(self) -> None:
        res = self.run_gate()
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self.dest.read_bytes(), self.archive.read_bytes())
        self.assertEqual((self.work / "checks").read_text().count("call"), 2)
        self.assertEqual((self.work / "downloads").read_text().count("call"), 1)
        self.assertIn(self.digest, res.stdout)
        self.assertEqual(list(self.work.glob(".schneeglass-actions-zip.*")), [])

    def test_untrusted_artifact_id(self) -> None:
        self.assert_rejected("requested artifact ID differs", MOCK_ID="778")
        self.assertFalse((self.work / "downloads").exists())

    def test_provenance_refused_before_download(self) -> None:
        self.assert_rejected("provenance check failed", MOCK_PROVENANCE_FAIL="1")
        self.assertFalse((self.work / "downloads").exists())

    def test_download_failure_and_empty_body(self) -> None:
        self.assert_rejected("ZIP download failed", MOCK_DOWNLOAD_FAIL="1")
        (self.work / "checks").unlink()
        self.assert_rejected("empty or not a regular file", MOCK_DOWNLOAD_EMPTY="1")

    def test_download_body_mismatch(self) -> None:
        forged = self.work / "forged.zip"
        forged.write_bytes(self.archive.read_bytes() + b"tampered")
        self.assert_rejected("does not match authenticated", MOCK_SOURCE=str(forged))

    def test_updated_digest_or_provenance_after_download(self) -> None:
        self.assert_rejected("digest changed during download", MOCK_SECOND_DIGEST="f" * 64)
        (self.work / "checks").unlink()
        self.assert_rejected("provenance check failed", MOCK_PROVENANCE_FAIL="2")

    def test_existing_destination_and_symlink_preserved(self) -> None:
        self.dest.write_text("keep original", encoding="utf-8")
        res = self.run_gate()
        self.assertNotEqual(res.returncode, 0)
        self.assertEqual(self.dest.read_text(), "keep original")
        self.assertFalse((self.work / "checks").exists())
        self.dest.unlink()
        owner = self.work / "owner-file"
        owner.write_text("keep owner", encoding="utf-8")
        self.dest.symlink_to(owner)
        res = self.run_gate()
        self.assertNotEqual(res.returncode, 0)
        self.assertEqual(owner.read_text(), "keep owner")

    def test_symlink_parent_rejected(self) -> None:
        alias = self.work / "linked"
        alias.symlink_to(self.work, target_is_directory=True)
        res = self.run_gate(DEST=str(alias / "new.zip"))
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("parent must be a real directory", res.stderr)
        self.assertFalse((self.work / "new.zip").exists())

    def test_invalid_input_before_network(self) -> None:
        for rid in ("0", "1;echo unsafe", "../bad"):
            self.assert_rejected("run ID must be positive decimal", RUN_ID=rid)
        self.assertFalse((self.work / "checks").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
