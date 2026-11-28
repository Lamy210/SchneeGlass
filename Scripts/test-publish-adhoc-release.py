#!/usr/bin/env python3
"""Exercise the publisher orchestration with no real network or mutation."""

import argparse
import contextlib
import importlib.util
import io
import json
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
        self.owned_snapshots = []

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

    def owned_slot(self, identity, tag, sha, expected, uploaded):
        self.record("owned")
        assert identity == "123"
        assert set(uploaded).issubset(expected)
        self.owned_snapshots.append(dict(uploaded))

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
        self.assertEqual([len(x) for x in api.owned_snapshots], [0, 1, 2, 3, 4, 4])
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

    def test_publisher_failure_log_binds_active_asset_to_captured_ids(self):
        api = FakeGitHub(self)
        api.fail = "upload:BUILD_INFO.txt"
        with self.assertRaisesRegex(ValueError, "fixture failure"):
            self.run_publisher(api)
        self.assertEqual(api.upload_count, 1)
        self.assertIn("stage=upload", self.failure_log)
        self.assertIn("active_asset=BUILD_INFO.txt", self.failure_log)
        self.assertIn("uploaded_asset_ids=ADHOC_RELEASE_EVIDENCE.json:201", self.failure_log)
        self.assertNotIn("uploaded_asset_ids=201", self.failure_log)
        self.assertNotIn("publish", api.events)

    def test_publisher_failure_log_clears_active_asset_after_uploads(self):
        api = FakeGitHub(self)
        api.fail = "readback:draft"
        with self.assertRaisesRegex(ValueError, "fixture failure"):
            self.run_publisher(api)
        self.assertEqual(api.upload_count, 4)
        self.assertIn("stage=draft-readback", self.failure_log)
        self.assertIn("active_asset=none", self.failure_log)
        for name in self.assets:
            self.assertIn("name", name)
            self.assertIn(name["name"] + ":", self.failure_log)
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

    def test_publisher_upload_fixed_host_no_redirect_or_retry(self):
        # Exercise the real upload method without opening a network connection.
        # A 3xx response must never forward the owner credential to another host.
        api = publisher.GitHub()
        assets = publisher.readback.local_assets(self.prepared, fixture.TAG)
        name = next(name for name in assets if name.endswith(".zip"))
        expected = assets[name]
        local_bytes = (self.prepared / name).read_bytes()
        valid = {
            "id": 901, "name": name, "state": "uploaded",
            "size": expected[0], "digest": expected[1],
        }

        class StubConnection:
            def __init__(self, status, response):
                self.status = status
                self.response = json.dumps(response).encode("utf-8")
                self.requests = []
                self.closed = False

            def request(self, method, url, body, headers):
                self.requests.append((method, url, body.read(), headers))

            def getresponse(self):
                return self

            def read(self, limit):
                return self.response[:limit]

            def close(self):
                self.closed = True

        cases = [
            ("success", 201, valid, True),
            ("redirect", 302, valid, False),
            ("not-created", 200, valid, False),
            ("missing-identity", 201, {**valid, "id": 0}, False),
            ("wrong-name", 201, {**valid, "name": "other.zip"}, False),
            ("wrong-size", 201, {**valid, "size": expected[0] + 1}, False),
            ("wrong-digest", 201, {**valid, "digest": "sha256:" + "0" * 64}, False),
        ]
        for label, status, response, allowed in cases:
            with self.subTest(case=label):
                connection = StubConnection(status, response)
                with patch.object(publisher, "command", return_value="fixture-owner-token\n") as token, \
                     patch.object(publisher.http.client, "HTTPSConnection",
                                  return_value=connection) as transport:
                    if allowed:
                        self.assertEqual(api.upload("123", name, self.prepared, expected), 901)
                    else:
                        with self.assertRaises(ValueError):
                            api.upload("123", name, self.prepared, expected)
                token.assert_called_once_with(
                    ["gh", "auth", "token", "--hostname", "github.com"],
                    capture=True, timeout=30,
                )
                transport.assert_called_once_with("uploads.github.com", timeout=60)
                self.assertEqual(len(connection.requests), 1)
                method, url, sent, headers = connection.requests[0]
                self.assertEqual(method, "POST")
                self.assertEqual(
                    url, "/" + publisher.PREFIX + "/releases/123/assets?name="
                    + publisher.quote(name, safe=""),
                )
                self.assertEqual(sent, local_bytes)
                self.assertEqual(headers["Authorization"], "Bearer fixture-owner-token")
                self.assertEqual(headers["Content-Length"], str(expected[0]))
                self.assertEqual(headers["Content-Type"], "application/octet-stream")
                self.assertTrue(connection.closed)

    def test_publisher_duplicate_upload_id_never_publishes(self):
        api = FakeGitHub(self)
        original = api.upload

        def duplicated_id(*args):
            original(*args)
            return 201

        api.upload = duplicated_id
        with self.assertRaisesRegex(ValueError, "duplicate created asset ID"):
            self.run_publisher(api)
        self.assertEqual(api.upload_count, 2)
        self.assertNotIn("publish", api.events)
        self.assertIn("stage=upload", self.failure_log)

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

    def test_publisher_owned_slot_rejects_foreign_or_changed_assets(self):
        api = publisher.GitHub()
        expected = publisher.readback.local_assets(self.prepared, fixture.TAG)
        name = sorted(expected)[0]
        size, digest = expected[name]
        good = {
            "id": 201, "name": name, "size": size,
            "digest": digest, "state": "uploaded",
        }
        release = {
            "id": 123, "tag_name": fixture.TAG, "draft": True,
            "immutable": False, "prerelease": False, "assets": [],
        }
        inventory = [[{"id": 123, "tag_name": fixture.TAG, "draft": True}]]
        cases = [
            ("empty initial draft", [], {}, True),
            ("known first upload", [good], {name: 201}, True),
            ("unexpected foreign asset", [good], {}, False),
            ("known upload missing", [], {name: 201}, False),
            ("replaced asset ID", [{**good, "id": 202}], {name: 201}, False),
            ("unknown asset name", [{**good, "name": "foreign.zip"}], {name: 201}, False),
            ("changed asset size", [{**good, "size": size + 1}], {name: 201}, False),
            ("changed asset digest", [{**good, "digest": "sha256:" + "0" * 64}],
             {name: 201}, False),
            ("incomplete upload state", [{**good, "state": "starter"}],
             {name: 201}, False),
            ("missing asset metadata", [{**good, "digest": None}], {name: 201}, False),
            ("malformed asset identity", [{**good, "id": True}], {name: 201}, False),
        ]
        for label, assets, uploaded, allowed in cases:
            with self.subTest(case=label):
                details = {**release, "assets": assets}
                with patch.object(publisher, "gh_json",
                                  side_effect=[inventory, details]) as query, \
                     patch.object(publisher.reader, "resolve_tag",
                                  return_value=fixture.SHA) as ref:
                    if allowed:
                        self.assertEqual(
                            api.owned_slot("123", fixture.TAG, fixture.SHA,
                                           expected, uploaded), details)
                    else:
                        with self.assertRaises(ValueError):
                            api.owned_slot("123", fixture.TAG, fixture.SHA,
                                           expected, uploaded)
                    self.assertEqual(query.call_count, 2)
                    ref.assert_called_once_with(fixture.TAG)

    def test_publisher_foreign_asset_detected_before_next_upload(self):
        api = FakeGitHub(self)
        owned = api.owned_slot

        def foreign_asset(identity, tag, sha, expected, uploaded):
            owned(identity, tag, sha, expected, uploaded)
            if len(uploaded) == 2:
                raise ValueError("foreign release asset appeared")

        api.owned_slot = foreign_asset
        with self.assertRaisesRegex(ValueError, "foreign release asset appeared"):
            self.run_publisher(api)
        self.assertEqual(api.upload_count, 2)
        self.assertNotIn("publish", api.events)
        self.assertIn("stage=upload", self.failure_log)

    def test_publisher_governance_job_isolated_from_release_token(self):
        text = (ROOT.parent / ".github/workflows/publish-adhoc-release.yml").read_text()
        self.assertIn("\n  governance:\n", text)
        self.assertIn("\n  publish:\n", text)
        attestation = text.split("\n  governance:\n", 1)[1].split("\n  publish:\n", 1)[0]
        publication = text.split("\n  publish:\n", 1)[1]
        self.assertIn("SCHNEEGLASS_RELEASE_GOVERNANCE_TOKEN", attestation)
        self.assertNotIn("SCHNEEGLASS_RELEASE_OWNER_TOKEN", attestation)
        self.assertNotIn("publish-adhoc-release.py", attestation)
        self.assertIn("setup-release-governance.sh Lamy210/SchneeGlass --verify-only",
                      attestation)
        self.assertIn('test "$INPUT_SOURCE_SHA" = "$GITHUB_SHA"', attestation)
        self.assertIn("source_sha: ${{ steps.verify.outputs.source_sha }}", attestation)
        self.assertIn("needs: governance", publication)
        self.assertIn("needs.governance.result == 'success'", publication)
        self.assertIn("SCHNEEGLASS_GOVERNANCE_ATTESTED_SHA: "
                      "${{ needs.governance.outputs.source_sha }}", publication)
        self.assertIn("SCHNEEGLASS_RELEASE_OWNER_TOKEN", publication)
        self.assertNotIn("SCHNEEGLASS_RELEASE_GOVERNANCE_TOKEN", publication)
        self.assertNotIn("setup-release-governance.sh", publication)

    def test_publisher_attestation_matches_exact_owner_workflow(self):
        context = {
            "GITHUB_ACTIONS": "true",
            "GITHUB_REPOSITORY": publisher.REPO,
            "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_WORKFLOW_REF": publisher.WORKFLOW_REF,
            "GITHUB_ACTOR_ID": "90091196",
            "GITHUB_RUN_ATTEMPT": "1",
            "GITHUB_SHA": ARGS.source_sha,
            "GITHUB_JOB": "publish",
            "SCHNEEGLASS_GOVERNANCE_ATTESTED_SHA": ARGS.source_sha,
        }
        with patch.dict(publisher.os.environ, context, clear=True):
            publisher.validate_context(ARGS)
            for key in ("GITHUB_JOB", "SCHNEEGLASS_GOVERNANCE_ATTESTED_SHA",
                        "GITHUB_SHA", "GITHUB_ACTOR_ID", "GITHUB_WORKFLOW_REF",
                        "GITHUB_RUN_ATTEMPT"):
                with self.subTest(missing=key):
                    with patch.dict(publisher.os.environ, {key: ""}):
                        with self.assertRaisesRegex(ValueError, "owner-dispatched"):
                            publisher.validate_context(ARGS)
            with patch.dict(publisher.os.environ,
                            {"SCHNEEGLASS_GOVERNANCE_ATTESTED_SHA": "f" * 40}):
                with self.assertRaisesRegex(ValueError, "owner-dispatched"):
                    publisher.validate_context(ARGS)

    def test_publisher_effective_rules_rechecked_without_admin_credential(self):
        api = publisher.GitHub()
        checks = [{"total_count": 2, "check_runs": [
            {"id": i, "name": name, "head_sha": ARGS.source_sha,
             "app": {"id": 15368}, "status": "completed", "conclusion": "success"}
            for i, name in enumerate(sorted(publisher.REQUIRED_CHECKS), 1)
        ]}]
        values = [
            {"id": 90091196, "login": "Lamy210", "type": "User"},
            {"id": 1359347782, "full_name": publisher.REPO},
            {"enabled": True},
            {"name": "main", "commit": {"sha": ARGS.source_sha}},
            checks,
        ]
        with patch.object(publisher, "gh_json", side_effect=values) as gh, \
             patch.object(publisher, "gate") as gate:
            api.verify_authority(ARGS)
            self.assertEqual(gate.call_args_list, [
                unittest.mock.call("verify-local-release-source.sh", publisher.REPO),
                unittest.mock.call("verify-current-release-governance.sh", publisher.REPO),
            ])
            self.assertEqual(gh.call_count, 5)

    def test_publisher_missing_immutable_setting_fails_closed(self):
        api = publisher.GitHub()
        values = [
            {"id": 90091196, "login": "Lamy210", "type": "User"},
            {"id": 1359347782, "full_name": publisher.REPO},
            {"enabled": False},
        ]
        with patch.object(publisher, "gh_json", side_effect=values) as gh, \
             patch.object(publisher, "gate") as gate:
            with self.assertRaisesRegex(ValueError, "immutable releases"):
                api.verify_authority(ARGS)
            self.assertEqual(gh.call_count, 3)
            self.assertEqual(gate.call_count, 2)

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
