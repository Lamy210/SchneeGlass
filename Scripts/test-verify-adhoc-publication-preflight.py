#!/usr/bin/env python3
"""Purely mocked integration tests for the non-publishing ad-hoc preflight."""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
PRECHECK = ROOT / "Scripts/verify-adhoc-publication-preflight.sh"
SOURCE_SHA = "0123456789abcdef0123456789abcdef01234567"
CALLS = [
    "verify-current-release-governance.sh",
    "verify-adhoc-candidate-approval-chain.sh",
    "materialize-authenticated-adhoc-release-history.sh",
    "verify-adhoc-candidate-build-history.sh",
    "verify-adhoc-release-slot.sh",
    "verify-current-release-governance.sh",
    "verify-adhoc-run-artifact-from-github.sh",
]


class ReadOnlyPreflightFixtures(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.download = self.work / "downloaded.zip"
        self.download.write_bytes(b"synthetic outer artifact, not an app\n")
        self.digest = hashlib.sha256(self.download.read_bytes()).hexdigest()
        self.candidate = self.work / "candidate"
        self.history = self.work / "history-snapshot"
        self.calls = self.work / "calls.txt"
        shim = self.bin / "bash"
        shim.write_text(
            r"""#!/bin/bash
set -euo pipefail
name="$(basename -- "$1")"
printf '%s\n' "$name" >> "$MOCK_CALLS"
if [[ "$name" == "$MOCK_FAIL_STEP" ]]; then
  echo 'injected child check failure' >&2
  exit 27
fi
case "$name" in
  verify-current-release-governance.sh)
    [[ "$#" -eq 2 && "$2" == 'Lamy210/SchneeGlass' ]] || exit 55
    ;;
  verify-adhoc-candidate-approval-chain.sh)
    [[ "$#" -eq 9 && "$2" == '123456789' && "$3" == '777' &&
       "$4" == '0.2.0' && "$5" == '3' &&
       "$6" == "$MOCK_SOURCE_SHA" && "$7" == '987654321' ]] || exit 56
    mkdir "$9"
    ;;
  materialize-authenticated-adhoc-release-history.sh)
    [[ "$#" -eq 2 ]] || exit 57
    mkdir "$2"
    mkdir "$2/history"
    ;;
  verify-adhoc-candidate-build-history.sh)
    [[ "$#" -eq 6 && "$2" == "$MOCK_CANDIDATE" &&
       "$3" == '0.2.0' && "$4" == '3' &&
       "$5" == "$MOCK_SOURCE_SHA" && "$6" == "$MOCK_HISTORY/history" ]] || exit 58
    ;;
  verify-adhoc-release-slot.sh)
    [[ "$#" -eq 2 && "$2" == 'v0.2.0' ]] || exit 59
    ;;
  verify-adhoc-run-artifact-from-github.sh)
    [[ "$#" -eq 4 && "$2" == '123456789' &&
       "$3" == '0.2.0' && "$4" == "$MOCK_SOURCE_SHA" ]] || exit 60
    printf 'artifact_id=%s\nartifact_digest=sha256:%s\n' \
      "$MOCK_FINAL_ARTIFACT_ID" "$MOCK_FINAL_DIGEST"
    ;;
  *) echo "unexpected child: $*" >&2; exit 61 ;;
esac
""", encoding="utf-8"
        )
        shim.chmod(0o700)

    def invoke(
        self, *,
        fail_step: str = "",
        artifact_id: str = "777",
        final_digest: str | None = None,
        run_id: str = "123456789",
        output: Path | None = None,
        history: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["PATH"] = str(self.bin) + os.pathsep + env["PATH"]
        env.update(
            MOCK_CALLS=str(self.calls),
            MOCK_FAIL_STEP=fail_step,
            MOCK_SOURCE_SHA=SOURCE_SHA,
            MOCK_CANDIDATE=str(self.candidate),
            MOCK_HISTORY=str(self.history),
            MOCK_FINAL_ARTIFACT_ID=artifact_id,
            MOCK_FINAL_DIGEST=final_digest or self.digest,
        )
        return subprocess.run(
            [
                "/bin/bash", str(PRECHECK), run_id, "777", "0.2.0", "3",
                SOURCE_SHA, "987654321", str(self.download),
                str(output or self.candidate), str(history or self.history),
            ],
            env=env, cwd=ROOT, capture_output=True, text=True, check=False,
        )

    def called(self) -> list[str]:
        if not self.calls.exists():
            return []
        return self.calls.read_text(encoding="utf-8").splitlines()

    def test_all_checks_in_order_and_no_publication(self) -> None:
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.called(), CALLS)
        self.assertIn("NOT publication authorization", result.stdout)
        self.assertTrue((self.history / "history").is_dir())
        self.assertTrue(self.candidate.is_dir())

    def test_all_child_failures_stop_subsequent_checks(self) -> None:
        for step in dict.fromkeys(CALLS):
            with self.subTest(step=step):
                self.calls.unlink(missing_ok=True)
                result = self.invoke(fail_step=step)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("failed:", result.stderr)
                if step != "verify-adhoc-run-artifact-from-github.sh":
                    self.assertNotIn("verify-adhoc-run-artifact-from-github.sh", self.called())
                if self.history.exists():
                    # Child-mocked output belongs to a prior iteration;
                    # never remove it implicitly in production.
                    self.assertTrue(self.history.is_dir())
                # Use a separate fresh fixture for each failing stage.
                if self.candidate.exists():
                    self.candidate.rmdir()
                if self.history.exists():
                    (self.history / "history").rmdir()
                    self.history.rmdir()

    def test_final_artifact_id_change_is_rejected(self) -> None:
        result = self.invoke(artifact_id="778")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("artifact ID changed", result.stderr)
        self.assertEqual(self.called(), CALLS)

    def test_final_outer_digest_change_is_rejected(self) -> None:
        result = self.invoke(final_digest="f" * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outer Actions ZIP digest changed", result.stderr)

    def test_invalid_input_rejected_before_any_child(self) -> None:
        result = self.invoke(run_id="0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("run ID must be positive decimal", result.stderr)
        self.assertEqual(self.called(), [])

    def test_existing_output_is_preserved(self) -> None:
        self.candidate.mkdir()
        marker = self.candidate / "owner-file.txt"
        marker.write_text("preserve", encoding="utf-8")
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("candidate destination must be new", result.stderr)
        self.assertEqual(marker.read_text(encoding="utf-8"), "preserve")
        self.assertEqual(self.called(), [])

    def test_same_output_paths_are_rejected(self) -> None:
        result = self.invoke(history=self.candidate)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("candidate and history paths must differ", result.stderr)
        self.assertEqual(self.called(), [])

    def test_history_symlink_is_rejected(self) -> None:
        self.history.symlink_to(self.work)
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("history destination must be new", result.stderr)
        self.assertEqual(self.called(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
