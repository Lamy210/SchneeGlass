#!/usr/bin/env python3
"""Mock macOS signature, bundle, and entitlements validation (no app mutation)."""
from __future__ import annotations
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
CHECK = ROOT / "Scripts/verify-extracted-adhoc-app.sh"


class AppSignatureFixtures(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "SchneeGlass.app"
        info = self.app / "Contents" / "Info.plist"
        binary = self.app / "Contents" / "MacOS" / "SchneeGlass"
        binary.parent.mkdir(parents=True)
        info.write_text("synthetic plist", encoding="utf-8")
        binary.write_bytes(b"synthetic binary")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        mocks = {
            "plutil": """#!/bin/bash
set -euo pipefail
[[ "$#" == 2 && "$1" == '-lint' && -s "$2" ]] || exit 42
[[ "$MOCK_PLUTIL_FAIL" != 1 ]] || exit 43
""",
            "PlistBuddy": """#!/bin/bash
set -euo pipefail
[[ "$#" == 3 && "$1" == '-c' ]] || exit 44
key="$2"
key="${key#Print :}"
case "$key" in
  CFBundleIdentifier) echo "$MOCK_BUNDLE_ID" ;;
  CFBundleShortVersionString) echo "$MOCK_VERSION" ;;
  CFBundleVersion) echo "$MOCK_BUILD" ;;
  LSMultipleInstancesProhibited) echo true ;;
  com.apple.security.app-sandbox) echo "$MOCK_SANDBOX" ;;
  com.apple.security.files.user-selected.read-write) echo "$MOCK_RW" ;;
  com.apple.security.network.client)
    if [[ "$MOCK_NETWORK" == 1 ]]; then echo true; else echo 'Does Not Exist' >&2; exit 1; fi ;;
  com.apple.security.get-task-allow)
    if [[ "$MOCK_DEBUG" == 1 ]]; then echo true; else echo 'Does Not Exist' >&2; exit 1; fi ;;
  *) echo 'Does Not Exist' >&2; exit 1 ;;
esac
""",
            "codesign": """#!/bin/bash
set -euo pipefail
case "$1" in
  --verify) [[ "$MOCK_VERIFY_FAIL" != 1 ]] || exit 48 ;;
  -dv)
    [[ "$MOCK_DETAILS_FAIL" != 1 ]] || exit 49
    echo 'Identifier=io.github.lamy210.schneeglass' >&2
    if [[ "$MOCK_SIGNATURE" == 1 ]]; then echo 'Signature=adhoc' >&2; fi
    if [[ "$MOCK_AUTHORITY" == 1 ]]; then echo 'Authority=Developer ID: Wrong' >&2; fi
    if [[ "$MOCK_RUNTIME" == 1 ]]; then
      echo 'CodeDirectory flags=0x10002(adhoc,runtime)' >&2
    else
      echo 'CodeDirectory flags=0x2(adhoc)' >&2
    fi
    ;;
  -d)
    [[ "$MOCK_ENTITLEMENTS_FAIL" != 1 ]] || exit 50
    printf 'synthetic entitlements\\n'
    ;;
  *) exit 51 ;;
esac
""",
        }
        for name, source in mocks.items():
            target = self.bin / name
            target.write_text(source, encoding="utf-8")
            target.chmod(0o700)

    def verify(self, app: Path | None = None, version: str = "0.2.0",
               build: str = "3", **options: str) -> subprocess.CompletedProcess[str]:
        values = {
            "MOCK_BUNDLE_ID": "io.github.lamy210.schneeglass",
            "MOCK_VERSION": "0.2.0", "MOCK_BUILD": "3",
            "MOCK_SANDBOX": "true", "MOCK_RW": "true",
            "MOCK_NETWORK": "0", "MOCK_DEBUG": "0",
            "MOCK_VERIFY_FAIL": "0", "MOCK_DETAILS_FAIL": "0",
            "MOCK_SIGNATURE": "1", "MOCK_RUNTIME": "1",
            "MOCK_AUTHORITY": "0", "MOCK_ENTITLEMENTS_FAIL": "0",
            "MOCK_PLUTIL_FAIL": "0",
        }
        values.update(options)
        env = os.environ.copy()
        env.update(values)
        env.update(
            PATH=str(self.bin) + os.pathsep + env["PATH"],
            CODESIGN_BIN=str(self.bin / "codesign"),
            PLIST_BUDDY_BIN=str(self.bin / "PlistBuddy"),
        )
        return subprocess.run(
            ["/bin/bash", str(CHECK), str(app or self.app), version, build],
            cwd=ROOT, env=env, capture_output=True, text=True, check=False,
        )

    def reject(self, message: str, **options: str) -> None:
        result = self.verify(**options)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stderr)
        self.assertTrue(self.app.is_dir(), "verifier changed user app directory")

    def test_valid(self) -> None:
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("NOT Apple notarization", result.stdout)

    def test_wrong_bundle_identity_or_build(self) -> None:
        self.reject("bundle identifier mismatch", MOCK_BUNDLE_ID="org.example.wrong")
        self.reject("bundle version mismatch", MOCK_VERSION="0.1.1")
        self.reject("bundle build mismatch", MOCK_BUILD="2")

    def test_codesign_failure_authority_or_missing_hardened_runtime(self) -> None:
        self.reject("codesign strict verification failed", MOCK_VERIFY_FAIL="1")
        self.reject("unable to read real app signing identity", MOCK_DETAILS_FAIL="1")
        self.reject("app signature must be ad-hoc", MOCK_SIGNATURE="0")
        self.reject("app signature must be ad-hoc", MOCK_RUNTIME="0")
        self.reject("app signature must be ad-hoc", MOCK_AUTHORITY="1")

    def test_sandbox_and_unexpected_entitlements(self) -> None:
        self.reject("App Sandbox entitlement missing", MOCK_SANDBOX="false")
        self.reject("user-selected read-write entitlement missing", MOCK_RW="false")
        self.reject("unexpected optional entitlement", MOCK_NETWORK="1")
        self.reject("unexpected optional entitlement", MOCK_DEBUG="1")
        self.reject("unable to read real app entitlements", MOCK_ENTITLEMENTS_FAIL="1")

    def test_missing_or_symlinked_info_plist(self) -> None:
        info = self.app / "Contents" / "Info.plist"
        info.unlink()
        self.reject("required app member")
        info.symlink_to(self.app / "Contents" / "MacOS" / "SchneeGlass")
        self.reject("required app member")

    def test_symlinked_app_directory(self) -> None:
        link = self.root / "linked.app"
        link.symlink_to(self.app, target_is_directory=True)
        self.reject("app must be a real directory", app=link)

    def test_invalid_input_and_plist(self) -> None:
        self.reject("version must be X.Y.Z", version="../wrong")
        self.reject("build must be positive decimal", build="0")
        self.reject("Info.plist is invalid", MOCK_PLUTIL_FAIL="1")


if __name__ == "__main__":
    unittest.main(verbosity=2)
