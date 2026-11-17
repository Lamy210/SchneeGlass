#!/usr/bin/env python3
"""Synthetic gates; actual preparation, file bytes, validation and native promotion."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parent
SHA = "a" * 40
VERSION = "0.2.0"
NAME = "SchneeGlass-0.2.0-adhoc.zip"


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.scripts = self.root / "Scripts"
        self.scripts.mkdir()
        for name in ("prepare-verified-adhoc-public-assets.py", "verify-adhoc-public-release-evidence.py"):
            shutil.copyfile(ROOT / name, self.scripts / name)
        self.outer = self.root / "outer.zip"
        self.outer.write_bytes(b"synthetic outer artifact")
        self.candidate = self.root / "fixture-candidate"
        self.candidate.mkdir()
        self.archive = self.candidate / "SchneeGlass-0.2.0-adhoc-candidate.zip"
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("Synthetic.txt", "not a real application")
        self.inner_digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.outer_digest = hashlib.sha256(self.outer.read_bytes()).hexdigest()
        (self.candidate / "BUILD_INFO.txt").write_text(
            f"version={VERSION}\nbuild=3\nsource_commit={SHA}\nsource_branch=main\n"
            "code_signature=adhoc\napple_developer_id_signed=false\napple_notarized=false\n"
            "minimum_macos=15.0\nexecutable_info=synthetic\n"
            "distribution=github-adhoc-candidate\n")
        self.output = self.root / "output"
        self.env = os.environ | {"FIXTURE_DIR": str(self.candidate),
                                 "INNER_DIGEST": self.inner_digest, "OUTER_DIGEST": self.outer_digest}
        self.gates = {
            "verify-adhoc-publication-preflight.sh": (
                'if [ "$#" -ne 9 ]; then exit 40; fi\n'
                'if [ "$1 $2 $3 $4 $5 $6" != "123 456 0.2.0 3 ' + SHA + ' 789" ]; then exit 40; fi\n'
                'cp -R "$FIXTURE_DIR" "$8"\nmkdir "$9"\n'),
            "verify-adhoc-qa-comment-from-github.sh": (
                'if [ "$#" -ne 6 ]; then exit 42; fi\n'
                'if [ "$6" != "$INNER_DIGEST" ]; then\n'
                '  echo "synthetic owner QA digest mismatch" >&2; exit 42\n'
                'fi\n'
                'printf "Verified GitHub owner QA approval comment ID=%s run=%s source=%s inner_zip_sha256=%s approved_at=2026-01-02T03:04:05Z\\n" "$1" "$2" "$5" "$6"\n'),
            "verify-current-release-governance.sh": '[[ "$1" == "Lamy210/SchneeGlass" ]]',
            "verify-adhoc-run-artifact-from-github.sh":
                'printf "artifact_id=456\\nartifact_digest=sha256:%s\\n" "$OUTER_DIGEST"',
            "verify-adhoc-release-slot.sh": '[[ "$1" == "v0.2.0" ]]',
        }
        for name, content in self.gates.items():
            self.gate(name, content)

    def gate(self, name, body):
        (self.scripts / name).write_text("set -euo pipefail\n" + body + "\n")

    def run_prepare(self):
        return subprocess.run(
            [sys.executable, str(self.scripts / "prepare-verified-adhoc-public-assets.py"),
             "123", "456", VERSION, "3", SHA, "789", str(self.outer), str(self.output)],
            env=self.env, capture_output=True, text=True, timeout=30,
        )

    def assert_clean_failure(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.output.exists())
        self.assertEqual(list(self.root.glob(".schneeglass-public-assets-*")), [])

    def test_round_trip(self):
        result = self.run_prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(p.name for p in self.output.iterdir()),
                         {NAME, "BUILD_INFO.txt", "SHA256SUMS", "ADHOC_RELEASE_EVIDENCE.json"})
        self.assertEqual((self.output / NAME).read_bytes(), self.archive.read_bytes())
        evidence = json.loads((self.output / "ADHOC_RELEASE_EVIDENCE.json").read_text())
        self.assertEqual(evidence["qa_approved_at"], "2026-01-02T03:04:05Z")
        self.assertEqual(evidence["outer_artifact_sha256"], self.outer_digest)
        self.assertEqual(evidence["inner_zip_sha256"], self.inner_digest)
        check = subprocess.run(
            [sys.executable, str(ROOT / "verify-adhoc-public-release-evidence.py"),
             str(self.output), "v" + VERSION, SHA], capture_output=True, text=True)
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertEqual(check.stdout, "3\n")
        before = (self.output / NAME).read_bytes()
        self.assertNotEqual(self.run_prepare().returncode, 0)
        self.assertEqual((self.output / NAME).read_bytes(), before)

    def test_every_gate_fail_closed(self):
        for name, original in self.gates.items():
            with self.subTest(gate=name):
                self.gate(name, "exit 41")
                self.assert_clean_failure(self.run_prepare())
                self.gate(name, original)

    def test_qa_and_artifact_mismatch(self):
        self.env["INNER_DIGEST"] = "b" * 64
        # Prove the synthetic owner gate itself fails on the mismatch on this OS;
        # do not assume Bash errexit behavior in a compound conditional.
        probe = subprocess.run(
            ["bash", str(self.scripts / "verify-adhoc-qa-comment-from-github.sh"),
             "789", "123", VERSION, "3", SHA, self.inner_digest],
            env=self.env, capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(probe.returncode, 42, probe.stdout + probe.stderr)
        result = self.run_prepare()
        self.assert_clean_failure(result)
        self.assertIn("synthetic owner QA digest mismatch", result.stderr)
        self.env["INNER_DIGEST"] = self.inner_digest
        self.env["OUTER_DIGEST"] = "b" * 64
        result = self.run_prepare()
        self.assert_clean_failure(result)
        self.assertIn("authenticated outer artifact identity changed", result.stderr)
        self.env["OUTER_DIGEST"] = self.outer_digest
        self.gate("verify-adhoc-qa-comment-from-github.sh",
                  self.gates["verify-adhoc-qa-comment-from-github.sh"].replace(
                      "2026-01-02", "2026-02-31"))
        result = self.run_prepare()
        self.assert_clean_failure(result)
        self.assertIn("invalid QA calendar timestamp", result.stderr)

    def test_metadata_inconsistency(self):
        info = self.candidate / "BUILD_INFO.txt"
        info.write_text(info.read_text().replace("build=3", "build=4"))
        self.assert_clean_failure(self.run_prepare())

    def test_native_promotion_does_not_replace(self):
        spec = importlib.util.spec_from_file_location("prepare", self.scripts / "prepare-verified-adhoc-public-assets.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        source = self.root / "source"
        source.mkdir()
        (source / "marker").write_text("source")
        self.output.mkdir()
        with self.assertRaises(OSError):
            module.exclusive_promote(source, self.output)
        self.assertTrue(source.is_dir())
        self.assertEqual(list(self.output.iterdir()), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
