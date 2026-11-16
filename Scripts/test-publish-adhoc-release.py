#!/usr/bin/env python3
"""Exercise the publisher orchestration with no real network or mutation."""

import argparse
import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
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
        self.assertEqual(api.events[-2:], ["publish", "readback:published"])

    def test_publisher_stops_at_every_failed_step(self):
        for event in ["authority", "prepare", "fresh", "empty", "tag", "draft", "owned",
                      "upload:ADHOC_RELEASE_EVIDENCE.json", "readback:draft",
                      "publish", "readback:published"]:
            with self.subTest(event=event):
                api = FakeGitHub(self)
                api.fail = event
                with self.assertRaises(ValueError):
                    self.run_publisher(api)
                self.assertEqual(api.events[-1], event)
                self.assertEqual(api.events.count(event), 1)
                self.assertIn("No retry, deletion, overwrite or adoption", self.failure_log)
                if event not in {"publish", "readback:published"}:
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

    def test_publisher_owner_workflow_context_required(self):
        with patch.dict(publisher.os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "owner-dispatched"):
                publisher.validate_context(ARGS)
        wrong = argparse.Namespace(**vars(ARGS))
        wrong.confirm = "yes"
        with self.assertRaisesRegex(ValueError, "explicit publication confirmation"):
            publisher.validate_context(wrong)


def load_tests(loader, tests, pattern):
    return unittest.TestSuite(
        PublisherTests(name) for name in loader.getTestCaseNames(PublisherTests)
        if name.startswith("test_publisher_")
    )


if __name__ == "__main__":
    unittest.main(verbosity=2)
