#!/usr/bin/env python3
"""Exercise the publisher orchestration with no real network or mutation."""

import argparse
import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("publisher", ROOT / "publish-adhoc-release.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
spec = importlib.util.spec_from_file_location(
    "reader_fixture", ROOT / "test-verify-authenticated-adhoc-public-release.py"
)
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
spec = importlib.util.spec_from_file_location(
    "prepare_fixture", ROOT / "test-prepare-verified-adhoc-public-assets.py"
)
prepare_fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare_fixture)

ARGS = argparse.Namespace(run_id="12345", artifact_id="777", version="0.2.0",
                          build="3", source_sha=fixture.SHA, comment_id="888",
                          confirm="PUBLISH v0.2.0")


class FakeGitHub:
    def __init__(self, test):
        self.test = test
        self.events = []
        self.fail = None
        self.upload_count = 0
        self.response_id = 123

    def record(self, event):
        self.events.append(event)
        if event == self.fail:
            raise ValueError("fixture failure: " + event)

    def verify_authority(self, args):
        self.record("authority")

    def prepare(self, args, workspace):
        self.record("prepare")
        return self.test.prepared

    def fresh_checks(self, args, public, workspace):
        self.record("fresh")

    def check_empty_slot(self, tag):
        self.record("empty")

    def create_tag(self, tag, sha):
        self.record("tag")

    def create_draft(self, tag, sha):
        self.record("draft")
        return {"id": self.response_id, "tag_name": tag, "draft": True,
                "immutable": False, "prerelease": False, "assets": []}

    def owned_slot(self, identity, tag, sha):
        self.record("owned")
        assert identity == "123"

    def upload(self, identity, name, directory, expected):
        self.record("upload:" + name)
        assert identity == "123"
        self.upload_count += 1
        return 200 + self.upload_count

    def readback(self, phase, directory, identity, tag, sha):
        self.record("readback:" + phase)
        assert identity == "123"
        return ARGS.build

    def final_assets(self, phase, identity, tag, expected, uploaded):
        self.record("final-assets:" + phase)
        assert identity == "123"
        assert set(expected) == set(uploaded)

    def publish(self, identity):
        self.record("publish")
        assert identity == "123"
        return {"id": 123, "tag_name": fixture.TAG, "draft": False}


class PublisherTests(fixture.ReleaseReaderTests):
    def setUp(self):
        super().setUp()
        self.prepared = self.root / "prepared"
        self.prepared.mkdir()
        for asset in self.assets:
            shutil.copyfile(self.root / f"asset-{asset['id']}", self.prepared / asset["name"])

    def run_publisher(self, api):
        with contextlib.redirect_stderr(io.StringIO()) as log:
            try:
                return publisher.execute(ARGS, self.root, api)
            finally:
                self.failure_log = log.getvalue()

    def test_publisher_success_order(self):
        api = FakeGitHub(self)
        self.assertEqual(self.run_publisher(api), "123")
        self.assertEqual(api.events[:5], ["authority", "prepare", "fresh", "empty", "tag"])
        self.assertEqual(api.events.count("draft"), 1)
        self.assertEqual(api.upload_count, 4)
        self.assertEqual(api.events.count("readback:draft"), 2)
        self.assertEqual(api.events.count("fresh"), 2)
        self.assertEqual(api.events[-4:], ["final-assets:draft", "publish", "readback:published", "final-assets:published"])

    def test_publisher_stops_at_every_failed_step(self):
        for event in ["authority", "prepare", "fresh", "empty", "tag", "draft", "owned",
                      "upload:ADHOC_RELEASE_EVIDENCE.json", "readback:draft",
                      "final-assets:draft", "publish", "readback:published", "final-assets:published"]:
            with self.subTest(event=event):
                api = FakeGitHub(self)
                api.fail = event
                with self.assertRaises(ValueError):
                    self.run_publisher(api)
                self.assertEqual(api.events[-1], event)
                self.assertEqual(api.events.count(event), 1)
                self.assertIn("No retry, deletion, overwrite or adoption", self.failure_log)
                if event not in {"publish", "readback:published", "final-assets:published"}:
                    self.assertNotIn("publish", api.events)

    def test_publisher_second_fresh_check_blocks_publication(self):
        api = FakeGitHub(self)
        original = api.fresh_checks

        def fresh(*args):
            original(*args)
            if api.events.count("fresh") == 2:
                raise ValueError("new release appeared")
        api.fresh_checks = fresh
        with self.assertRaisesRegex(ValueError, "new release"):
            self.run_publisher(api)
        self.assertNotIn("publish", api.events)
        self.assertIn("stage=final-preflight", self.failure_log)
        self.assertIn("release_id=123", self.failure_log)

    def test_publisher_invalid_draft_never_adopted(self):
        api = FakeGitHub(self)
        api.response_id = 0
        with self.assertRaises(ValueError):
            self.run_publisher(api)
        self.assertEqual(api.events[-1], "draft")
        self.assertIn("release_id=unknown", self.failure_log)

    def test_publisher_refuses_local_asset_change_before_upload(self):
        api = FakeGitHub(self)
        original = api.owned_slot

        def owned(*args):
            original(*args)
            (self.prepared / fixture.NAME).write_bytes(b"changed")
        api.owned_slot = owned
        with self.assertRaisesRegex(ValueError, "prepared assets changed"):
            self.run_publisher(api)
        self.assertEqual(api.upload_count, 0)
        self.assertNotIn("publish", api.events)

    def test_publisher_exact_id_mutation_http_payload(self):
        api = publisher.GitHub()
        with patch.object(publisher, "gh_json") as request:
            request.return_value = {"ref": "refs/tags/v0.2.0",
                                    "object": {"type": "commit", "sha": fixture.SHA}}
            api.create_tag(fixture.TAG, fixture.SHA)
            request.assert_called_once_with(
                "POST", publisher.PREFIX + "/git/refs",
                {"ref": "refs/tags/v0.2.0", "sha": fixture.SHA})
            request.reset_mock()
            api.publish("123")
            request.assert_called_once_with("PATCH", publisher.PREFIX + "/releases/123",
                                            {"draft": False, "make_latest": "true"})

    def test_publisher_exact_main_checks(self):
        names = sorted(publisher.REQUIRED_CHECKS)
        checks = [{"id": i, "name": name, "head_sha": fixture.SHA, "app": {"id": 15368},
                   "status": "completed", "conclusion": "success"}
                  for i, name in enumerate(names, 1)]
        publisher.verify_exact_main_checks([{"total_count": 2, "check_runs": checks}], fixture.SHA)
        publisher.verify_exact_main_checks(
            [{"total_count": 2, "check_runs": checks[:1]},
             {"total_count": 2, "check_runs": checks[1:]}], fixture.SHA)
        for changes in [{"head_sha": "b" * 40}, {"app": {"id": 7}}, {"conclusion": "failure"},
                        {"status": "queued"}, {"conclusion": "skipped"}]:
            with self.subTest(changes=changes):
                with self.assertRaises(ValueError):
                    publisher.verify_exact_main_checks(
                        [{"total_count": 2, "check_runs": [checks[0] | changes, checks[1]]}], fixture.SHA)
        with self.assertRaises(ValueError):
            publisher.verify_exact_main_checks([{"total_count": 1, "check_runs": checks[:1]}], fixture.SHA)
        with self.assertRaises(ValueError):
            publisher.verify_exact_main_checks(
                [{"total_count": 3, "check_runs": checks + [checks[0] | {"id": 100}]}], fixture.SHA)
        for pages in (
            [{"total_count": 3, "check_runs": checks}],
            [{"check_runs": checks}],
            [{"total_count": True, "check_runs": checks}],
            [{"total_count": 2, "check_runs": checks[:1]},
             {"total_count": 3, "check_runs": checks[1:]}],
            [{"total_count": 3, "check_runs": checks},
             {"total_count": 3, "check_runs": checks[:1]}],
        ):
            with self.subTest(pages=pages), self.assertRaises(ValueError):
                publisher.verify_exact_main_checks(pages, fixture.SHA)

    def test_publisher_final_asset_ids_must_match(self):
        api = publisher.GitHub()
        expected = {"one": (10, "sha256:" + "a" * 64)}
        for phase in ("draft", "published"):
            with self.subTest(phase=phase), patch.object(
                publisher.readback, "remote_assets", return_value={"one": (5, *expected["one"])}
            ) as remote:
                api.final_assets(phase, "123", fixture.TAG, expected, {"one": 5})
                remote.assert_called_once_with("123", fixture.TAG, phase)
                # A replacement with identical bytes but a different upload ID is not ours.
                with self.assertRaisesRegex(ValueError, "identities differ"):
                    api.final_assets(phase, "123", fixture.TAG, expected, {"one": 6})
                with self.assertRaisesRegex(ValueError, "incomplete captured"):
                    api.final_assets(phase, "123", fixture.TAG, expected, {})

    def test_publisher_owner_workflow_context_required(self):
        with patch.dict(publisher.os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "owner-dispatched"):
                publisher.validate_context(ARGS)
        wrong = argparse.Namespace(**vars(ARGS))
        wrong.confirm = "yes"
        with self.assertRaisesRegex(ValueError, "explicit publication confirmation"):
            publisher.validate_context(wrong)


class PreparedIntegrationTests(prepare_fixture.PreparationTests):
    """Real local asset preparation, validator, fresh checks and read-back.

    GitHub transport and the already-verified history snapshot boundary are
    synthetic; the actual history acquisition has its own integration suite.
    """

    def setUp(self):
        super().setUp()
        result = self.run_prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.args = argparse.Namespace(run_id="123", artifact_id="456",
                                       version=prepare_fixture.VERSION, build="3",
                                       source_sha=prepare_fixture.SHA, comment_id="789",
                                       confirm="PUBLISH v0.2.0")
        self.history_build = "2"
        self.real_gate = publisher.gate

    def dispatch_gate(self, name, *args, capture=False):
        if name == "materialize-authenticated-adhoc-release-history.sh":
            # Simulate the authenticated consumer's normalized output, not
            # the comparator itself: the real comparator is executed below.
            history = Path(args[0]) / "history" / "1"
            history.mkdir(parents=True)
            (history / "RELEASE_EVIDENCE.txt").write_text(
                "schema_version=1\nbundle_build=" + self.history_build + "\n"
            )
            return None
        if name == "verify-release-build-history.sh":
            return self.real_gate(name, *args, capture=capture)
        if name not in ("verify-adhoc-run-artifact-from-github.sh",
                        "verify-adhoc-qa-comment-from-github.sh"):
            raise AssertionError("unexpected live gate: " + name)
        result = subprocess.run(["bash", str(self.scripts / name), *map(str, args)],
                                env=self.env, check=True, capture_output=True,
                                text=True, timeout=10)
        return result.stdout if capture else None

    def test_integrated_prepared_bytes_fresh_checks_and_readback(self):
        api = publisher.GitHub()
        with patch.object(publisher, "gate", side_effect=self.dispatch_gate), \
                patch.object(api, "verify_authority") as authority:
            api.fresh_checks(self.args, self.output, self.root)
            authority.assert_called_once_with(self.args)

        # Replace the reader fixture's assets with the exact OUTPUT of the
        # real preparer, not separately manufactured matching metadata.
        remote = fixture.ReleaseReaderTests()
        self.addCleanup(remote.doCleanups)
        remote.setUp()
        for asset in remote.assets:
            target = remote.root / f"asset-{asset['id']}"
            shutil.copyfile(self.output / asset["name"], target)
            asset["size"] = target.stat().st_size
            asset["digest"] = "sha256:" + remote.digest(target.name)
        remote.release.update(draft=True, immutable=False, prerelease=False)
        remote.write_json("release.json", remote.release)
        with patch.dict(publisher.os.environ, remote.env, clear=True):
            self.assertEqual(api.readback("draft", self.output, "123",
                                         fixture.TAG, self.args.source_sha), "3")
            remote.release.update(draft=False, immutable=True)
            remote.write_json("release.json", remote.release)
            self.assertEqual(api.readback("published", self.output, "123",
                                         fixture.TAG, self.args.source_sha), "3")
            # Downloaded bytes may change even with stale matching metadata.
            archive = remote.root / "asset-104"
            raw = archive.read_bytes()
            archive.write_bytes(raw[:-1] + bytes([raw[-1] ^ 1]))
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                api.readback("published", self.output, "123", fixture.TAG,
                             self.args.source_sha)

    def test_integrated_fresh_checks_reject_regression_and_changed_qa(self):
        api = publisher.GitHub()
        with patch.object(publisher, "gate", side_effect=self.dispatch_gate), \
                patch.object(api, "verify_authority") as authority:
            for build in ("3", "4"):
                self.history_build = build
                with self.subTest(build=build):
                    with self.assertRaises(subprocess.CalledProcessError):
                        api.fresh_checks(self.args, self.output, self.root)
            self.history_build = "2"
            self.env["OUTER_DIGEST"] = "b" * 64
            with self.assertRaisesRegex(ValueError, "artifact identity changed"):
                api.fresh_checks(self.args, self.output, self.root)
            self.env["OUTER_DIGEST"] = self.outer_digest
            self.gate_script_qa_changed()
            with self.assertRaisesRegex(ValueError, "owner QA identity changed"):
                api.fresh_checks(self.args, self.output, self.root)
            authority.assert_not_called()

    def gate_script_qa_changed(self):
        prepare_fixture.PreparationTests.gate(
            self, "verify-adhoc-qa-comment-from-github.sh",
            self.gates["verify-adhoc-qa-comment-from-github.sh"].replace(
                "2026-01-02", "2026-01-03")
        )


def load_tests(loader, tests, pattern):
    return unittest.TestSuite(
        cls(name)
        for cls, prefix in ((PublisherTests, "test_publisher_"),
                            (PreparedIntegrationTests, "test_integrated_"))
        for name in loader.getTestCaseNames(cls)
        if name.startswith(prefix)
    )


if __name__ == "__main__":
    unittest.main(verbosity=2)
