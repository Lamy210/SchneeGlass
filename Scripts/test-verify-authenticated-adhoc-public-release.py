#!/usr/bin/env python3
"""Mock authenticated API; actual downloads, validator and build comparator."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parent
READER = ROOT / "verify-authenticated-adhoc-public-release.py"
PREFIX = "repos/Lamy210/SchneeGlass"
TAG = "v0.2.0"
SHA = "a" * 40
TAG_SHA = "b" * 40
NAME = "SchneeGlass-0.2.0-adhoc.zip"

MOCK = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
root = Path(os.environ["MOCK_RELEASE_DIR"])
args = sys.argv[1:]
if len(args) != 8 or args[:6] != ["api", "--hostname", "github.com", "--method", "GET", "-H"]:
    sys.exit(81)
accept, endpoint = args[6:]
prefix = "repos/Lamy210/SchneeGlass"
if accept == "Accept: application/octet-stream" and endpoint.startswith(prefix + "/releases/assets/"):
    identity = endpoint.rsplit("/", 1)[1]
    data = (root / ("asset-" + identity)).read_bytes()
    if (root / "overflow").exists():
        data += b"x"
    sys.stdout.buffer.write(data)
    if (root / "producer-failure").exists():
        sys.exit(82)
elif accept == "Accept: application/vnd.github+json":
    paths = {prefix: "repository", prefix + "/releases/123": "release",
             prefix + "/git/ref/tags/v0.2.0": "ref",
             prefix + "/git/tags/" + "b" * 40: "tag"}
    if endpoint not in paths:
        sys.exit(83)
    name = paths[endpoint]
    if name == "ref" and (root / "change-ref").exists():
        marker = root / "ref-read"
        if marker.exists():
            print(json.dumps({"ref": "refs/tags/v0.2.0",
                              "object": {"type": "commit", "sha": "c" * 40}}))
            sys.exit(0)
        marker.touch()
    sys.stdout.buffer.write((root / (name + ".json")).read_bytes())
else:
    sys.exit(84)
'''


class ReleaseReaderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        gh = bin_dir / "gh"
        gh.write_text(MOCK.replace("#!/usr/bin/env python3", "#!" + sys.executable))
        gh.chmod(0o700)
        self.env = os.environ | {"MOCK_RELEASE_DIR": str(self.root),
                                 "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"]}
        with zipfile.ZipFile(self.root / "asset-104", "w") as archive:
            archive.writestr("Synthetic.txt", "not a real application")
        digest = self.digest("asset-104")
        evidence = {
            "schema_version": 1, "distribution": "github-adhoc",
            "repository_id": "1359347782", "tag": TAG, "version": "0.2.0",
            "bundle_identifier": "io.github.lamy210.schneeglass", "bundle_build": "3",
            "source_sha": SHA, "run_id": "12345", "run_attempt": "1",
            "artifact_id": "777", "outer_artifact_sha256": "e" * 64,
            "inner_zip_sha256": digest, "public_zip_name": NAME, "public_zip_sha256": digest,
            "qa_comment_id": "888", "qa_owner_id": "90091196",
            "qa_approved_at": "2026-01-02T03:04:05Z",
            "code_signature": "adhoc", "apple_developer_id_signed": False,
            "apple_notarized": False,
        }
        self.write_json("asset-101", evidence)
        (self.root / "asset-102").write_text(
            f"version=0.2.0\nbuild=3\nsource_commit={SHA}\nsource_branch=main\n"
            "code_signature=adhoc\napple_developer_id_signed=false\napple_notarized=false\n"
            "minimum_macos=15.0\nexecutable_info=synthetic\ndistribution=github-adhoc\n")
        (self.root / "asset-103").write_text(f"{digest}  {NAME}\n")
        self.assets = [
            {"id": i, "name": name, "size": (self.root / f"asset-{i}").stat().st_size,
             "digest": "sha256:" + self.digest(f"asset-{i}"), "state": "uploaded"}
            for i, name in enumerate(["ADHOC_RELEASE_EVIDENCE.json", "BUILD_INFO.txt",
                                      "SHA256SUMS", NAME], 101)
        ]
        self.release = {"id": 123, "tag_name": TAG, "draft": False,
                        "immutable": True, "target_commitish": "main", "assets": self.assets}
        self.write_json("repository.json", {"id": 1359347782, "full_name": "Lamy210/SchneeGlass"})
        self.write_json("release.json", self.release)
        self.ref = {"ref": "refs/tags/" + TAG, "object": {"type": "commit", "sha": SHA}}
        self.write_json("ref.json", self.ref)

    def write_json(self, name, value):
        (self.root / name).write_text(json.dumps(value), encoding="utf-8")

    def digest(self, name):
        return hashlib.sha256((self.root / name).read_bytes()).hexdigest()

    def run_reader(self, tag=TAG):
        return subprocess.run([sys.executable, str(READER), "123", tag],
                              env=self.env, capture_output=True, text=True, timeout=30)

    def reject(self, diagnostic, tag=TAG):
        result = self.run_reader(tag)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertIn(diagnostic, result.stderr)

    def test_round_trip_and_monotonic_build(self):
        result = self.run_reader()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "3\n")
        history = self.root / "history"
        history.mkdir()
        (history / "RELEASE_EVIDENCE.txt").write_text("schema_version=1\nbundle_build=" + result.stdout)
        current = self.root / "current"
        for build, accepted in [("4", True), ("3", False), ("2", False)]:
            current.write_text(f"schema_version=1\nbundle_build={build}\n")
            check = subprocess.run(["bash", str(ROOT / "verify-release-build-history.sh"),
                                    str(current), str(history)], capture_output=True, text=True)
            self.assertEqual(check.returncode == 0, accepted, check.stdout + check.stderr)

    def test_annotated_tag(self):
        self.ref["object"] = {"type": "tag", "sha": TAG_SHA}
        self.write_json("ref.json", self.ref)
        self.write_json("tag.json", {"sha": TAG_SHA, "object": {"type": "commit", "sha": SHA}})
        result = self.run_reader()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "3\n")
        self.write_json("tag.json", {"sha": TAG_SHA, "object": {"type": "tag", "sha": TAG_SHA}})
        self.reject("invalid tag target")

    def test_legacy_and_release_identity(self):
        self.reject("legacy release", tag="v0.1.1")
        for changes, diagnostic in [
            ({"id": 124}, "release identity mismatch"),
            ({"tag_name": "v0.3.0"}, "release identity mismatch"),
            ({"draft": True}, "published and immutable"),
            ({"immutable": False}, "published and immutable"),
            ({"immutable": "true"}, "published and immutable"),
            ({"assets": self.assets[:-1]}, "asset set"),
            ({"assets": self.assets + [{"name": "RELEASE_EVIDENCE.txt"}]}, "asset set"),
        ]:
            with self.subTest(changes=changes):
                self.write_json("release.json", self.release | changes)
                self.reject(diagnostic)

    def test_asset_metadata(self):
        for changes, diagnostic in [
            ({"id": 102}, "duplicate asset ID"),
            ({"size": 16385}, "asset size"),
            ({"size": True}, "asset size"),
            ({"digest": None}, "API asset digest"),
            ({"state": "starter"}, "not uploaded"),
            ({"name": "BUILD_INFO.txt"}, "duplicate release asset"),
        ]:
            with self.subTest(changes=changes):
                assets = [self.assets[0] | changes, *self.assets[1:]]
                self.write_json("release.json", self.release | {"assets": assets})
                self.reject(diagnostic)

    def test_download_integrity_and_failure(self):
        for marker, diagnostic in [
            ("overflow", "exceeds size limit"), ("producer-failure", "API request failed"),
        ]:
            (self.root / marker).touch()
            self.reject(diagnostic)
            (self.root / marker).unlink()
        archive = self.root / "asset-104"
        original = archive.read_bytes()
        archive.write_bytes(original[:-1])
        self.reject("size mismatch")
        archive.write_bytes(original[:-1] + bytes([original[-1] ^ 1]))
        self.reject("digest mismatch")

    def test_tag_binding_and_change(self):
        self.ref["object"]["sha"] = "c" * 40
        self.write_json("ref.json", self.ref)
        self.reject("source SHA mismatch")
        self.ref["object"]["sha"] = SHA
        self.write_json("ref.json", self.ref)
        (self.root / "change-ref").touch()
        self.reject("tag changed during validation")

    def test_wrong_repository(self):
        self.write_json("repository.json", {"id": 1, "full_name": "Lamy210/SchneeGlass"})
        self.reject("repository identity mismatch")


if __name__ == "__main__":
    unittest.main(verbosity=2)
