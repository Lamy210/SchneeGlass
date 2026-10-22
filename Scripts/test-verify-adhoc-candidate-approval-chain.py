#!/usr/bin/env python3
"""End-to-end, credential-free integration fixtures for candidate QA preflight."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from zipfile import ZipFile, ZIP_STORED

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "Scripts/verify-adhoc-candidate-approval-chain.sh"
RUN_ID = 123456789
ARTIFACT_ID = 777
COMMENT_ID = 987654321
VERSION = "0.2.0"
BUILD = "3"
SOURCE_SHA = "0123456789abcdef0123456789abcdef01234567"
REPO_ID = 1359347782
OWNER_ID = 90091196


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class CandidateChainTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.outer = self.root / "downloaded-actions.zip"
        self.output = self.root / "candidate"
        self.mock = self.root / "gh"
        self.mock.write_text(
            """#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'api repos/Lamy210/SchneeGlass') cat "$MOCK_DIR/repository.json" ;;
  'api repos/Lamy210/SchneeGlass/actions/runs/123456789') cat "$MOCK_DIR/run.json" ;;
  'api repos/Lamy210/SchneeGlass/branches/main') cat "$MOCK_DIR/main.json" ;;
  'api --paginate --slurp repos/Lamy210/SchneeGlass/actions/runs/123456789/artifacts?per_page=100') cat "$MOCK_DIR/artifacts.json" ;;
  'api repos/Lamy210/SchneeGlass/issues/comments/987654321') cat "$MOCK_DIR/comment.json" ;;
  *) exit 43 ;;
esac
""", encoding="utf-8"
        )
        self.mock.chmod(0o700)
        self.write_json(
            "repository.json",
            {"full_name": "Lamy210/SchneeGlass", "id": REPO_ID,
             "owner": {"login": "Lamy210", "id": OWNER_ID, "type": "User"}},
        )
        self.write_json(
            "run.json",
            {
                "id": RUN_ID,
                "name": "Ad-Hoc Release Candidate",
                "path": ".github/workflows/adhoc-release-candidate.yml",
                "event": "workflow_dispatch",
                "status": "completed",
                "conclusion": "success",
                "head_branch": "main",
                "head_sha": SOURCE_SHA,
                "run_attempt": 1,
                "workflow_id": 369218665,
                "repository": {"full_name": "Lamy210/SchneeGlass", "id": REPO_ID},
                "head_repository": {"full_name": "Lamy210/SchneeGlass", "id": REPO_ID},
            },
        )
        self.write_json(
            "main.json", {"name": "main", "commit": {"sha": SOURCE_SHA}}
        )
        self.build_wrapper()
        self.write_comment()

    def write_json(self, name: str, data: dict | list) -> None:
        (self.root / name).write_text(json.dumps(data), encoding="utf-8")

    def read_json(self, name: str) -> dict | list:
        return json.loads((self.root / name).read_text(encoding="utf-8"))

    def build_wrapper(
        self, *, inner_build: str = BUILD, valid_manifest: bool = True,
    ) -> None:
        inner = b"synthetic ad-hoc candidate archive - not a macOS application\n"
        inner_name = f"SchneeGlass-{VERSION}-adhoc-candidate.zip"
        checksum = sha(inner)
        manifest = f"{checksum}  {inner_name}\n".encode()
        if not valid_manifest:
            manifest = f"{'0' * 64}  {inner_name}\n".encode()
        meta = (
            f"version={VERSION}\nbuild={inner_build}\nsource_commit={SOURCE_SHA}\n"
            "source_branch=main\ncode_signature=adhoc\n"
            "apple_developer_id_signed=false\napple_notarized=false\n"
            "minimum_macos=15.0\nexecutable_info=synthetic-fixture\n"
            "distribution=github-adhoc-candidate\n"
        ).encode()
        files = {
            inner_name: inner,
            "BUILD_INFO.txt": meta,
            "SHA256SUMS": manifest,
            "README.txt": b"synthetic install information\n",
            "CODESIGN_DETAILS.txt": b"synthetic signature metadata\n",
            "ENTITLEMENTS.plist": b"synthetic entitlements\n",
        }
        with ZipFile(self.outer, "w", ZIP_STORED) as archive:
            for name, data in files.items():
                archive.writestr(name, data)
        self.inner_digest = checksum
        outer_digest = "sha256:" + sha(self.outer.read_bytes())
        self.write_json(
            "artifacts.json",
            [{
                "total_count": 1,
                "artifacts": [{
                    "id": ARTIFACT_ID,
                    "name": f"SchneeGlass-{VERSION}-adhoc-candidate",
                    "size_in_bytes": self.outer.stat().st_size,
                    "expired": False,
                    "digest": outer_digest,
                    "workflow_run": {
                        "id": RUN_ID,
                        "repository_id": REPO_ID,
                        "head_repository_id": REPO_ID,
                        "head_branch": "main",
                        "head_sha": SOURCE_SHA,
                    },
                }],
            }],
        )

    def write_comment(self, *, qa: str = "pass", digest: str | None = None) -> None:
        body = (
            "SCHNEEGLASS_ADHOC_QA_APPROVAL_V1\n"
            f"run_id={RUN_ID}\nrun_attempt=1\nsource_sha={SOURCE_SHA}\n"
            f"version={VERSION}\nbuild={BUILD}\n"
            f"archive_sha256={digest if digest is not None else self.inner_digest}\n"
            f"qa_result={qa}"
        )
        self.write_json(
            "comment.json",
            {
                "id": COMMENT_ID,
                "issue_url": "https://api.github.com/repos/Lamy210/SchneeGlass/issues/520",
                "author_association": "OWNER",
                "user": {"id": OWNER_ID, "login": "Lamy210", "type": "User"},
                "created_at": "2026-10-22T01:02:03Z",
                "updated_at": "2026-10-22T01:02:03Z",
                "body": body,
            },
        )

    def run_gate(self, *, artifact_id: str = str(ARTIFACT_ID),
                 build: str = BUILD, source: str = SOURCE_SHA,
                 output: Path | None = None) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update(GH_BIN=str(self.mock), JQ_BIN="jq", MOCK_DIR=str(self.root))
        return subprocess.run(
            [
                "bash", str(SCRIPT), str(RUN_ID), artifact_id, VERSION, build,
                source, str(COMMENT_ID), str(self.outer), str(output or self.output),
            ],
            cwd=ROOT, env=env, capture_output=True, text=True, check=False,
        )

    def test_exact_run_artifact_inner_digest_and_qa(self) -> None:
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("NOT publication authorization", result.stdout)
        self.assertIn(f"inner_zip_sha256={self.inner_digest}", result.stdout)
        self.assertEqual(len(list(self.output.iterdir())), 6)

    def test_wrong_artifact_id_fails_before_extraction(self) -> None:
        result = self.run_gate(artifact_id="778")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("selected artifact ID", result.stderr)
        self.assertFalse(self.output.exists())

    def test_wrapper_tampering_is_rejected(self) -> None:
        with self.outer.open("ab") as handle:
            handle.write(b"tamper")
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("safe extraction failed", result.stderr)
        self.assertFalse(self.output.exists())

    def test_inner_manifest_tampering_is_rejected(self) -> None:
        self.build_wrapper(valid_manifest=False)
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inner ad-hoc candidate metadata or checksum failed", result.stderr)

    def test_wrong_build_is_rejected(self) -> None:
        result = self.run_gate(build="4")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inner ad-hoc candidate metadata or checksum failed", result.stderr)

    def test_wrong_qa_digest_is_rejected(self) -> None:
        self.write_comment(digest="a" * 64)
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("authenticated owner QA approval missing or mismatched", result.stderr)

    def test_unapproved_qa_result_is_rejected(self) -> None:
        self.write_comment(qa="fail")
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("authenticated owner QA approval missing or mismatched", result.stderr)

    def test_stale_main_is_rejected_before_extraction(self) -> None:
        self.write_json("main.json", {"name": "main", "commit": {"sha": "f" * 40}})
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("authenticated Actions artifact or current main check failed", result.stderr)
        self.assertFalse(self.output.exists())

    def test_artifact_claims_wrong_run(self) -> None:
        inv = self.read_json("artifacts.json")
        inv[0]["artifacts"][0]["workflow_run"]["id"] = 111
        self.write_json("artifacts.json", inv)
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("authenticated Actions artifact or current main check failed", result.stderr)
        self.assertFalse(self.output.exists())

    def test_existing_output_is_never_overwritten(self) -> None:
        self.output.mkdir()
        marker = self.output / "owner-file"
        marker.write_text("preserve", encoding="utf-8")
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("output directory must be new", result.stderr)
        self.assertEqual(marker.read_text(encoding="utf-8"), "preserve")

    def test_invalid_source_and_artifact_id(self) -> None:
        self.assertIn("source SHA must be lowercase", self.run_gate(source="invalid").stderr)
        self.assertIn("artifact ID must be positive", self.run_gate(artifact_id="0").stderr)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    if subprocess.run(["bash", "-c", "command -v jq"], capture_output=True).returncode:
        raise SystemExit("jq is required")
    unittest.main(verbosity=2)
