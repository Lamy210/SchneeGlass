#!/usr/bin/env python3
"""Create-only ad-hoc publisher. Only the explicit main-branch owner workflow may execute."""

import argparse
import http.client
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import quote

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent
REPO = "Lamy210/SchneeGlass"
PREFIX = "repos/" + REPO
API_VERSION = "2026-03-10"
WORKFLOW_REF = REPO + "/.github/workflows/publish-adhoc-release.yml@refs/heads/main"
READBACK = ROOT / "verify-adhoc-release-readback.py"


def load_readback():
    spec = importlib.util.spec_from_file_location("release_readback", READBACK)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


readback = load_readback()
reader = readback.reader
require = reader.require


def command(args, *, data=None, capture=False, timeout=600):
    result = subprocess.run(args, input=data, check=True, text=True,
                            stdout=subprocess.PIPE if capture else sys.stderr,
                            cwd=ROOT.parent, timeout=timeout)
    return result.stdout if capture else None


def gate(name, *args, capture=False):
    return command(["bash", str(ROOT / name), *map(str, args)], capture=capture)


def parse_json(raw):
    value = json.loads(raw, object_pairs_hook=reader.unique_object,
                       parse_constant=reader.invalid_constant)
    return value


def gh_json(method, endpoint, payload=None, paginate=False):
    args = ["gh", "api", "--hostname", "github.com", "--method", method,
            "-H", "X-GitHub-Api-Version: " + API_VERSION,
            "-H", "Accept: application/vnd.github+json"]
    if paginate:
        args += ["--paginate", "--slurp"]
    if payload is not None:
        args += ["--input", "-"]
    args.append(endpoint)
    return parse_json(command(args, data=json.dumps(payload) if payload is not None else None,
                              capture=True, timeout=120))


def validate_context(args):
    for value in (args.run_id, args.artifact_id, args.comment_id):
        require(re.fullmatch(r"[1-9][0-9]*", value), "invalid positive ID")
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version), "invalid version")
    require(re.fullmatch(r"[1-9][0-9]{0,8}", args.build), "invalid build")
    require(reader.SHA.fullmatch(args.source_sha), "invalid source SHA")
    require(args.confirm == "PUBLISH v" + args.version, "explicit publication confirmation required")
    expected = {
        "GITHUB_ACTIONS": "true", "GITHUB_REPOSITORY": REPO,
        "GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REF": "refs/heads/main",
        "GITHUB_WORKFLOW_REF": WORKFLOW_REF, "GITHUB_ACTOR_ID": "90091196",
        "GITHUB_RUN_ATTEMPT": "1", "GITHUB_SHA": args.source_sha,
    }
    require(all(os.environ.get(key) == value for key, value in expected.items()),
            "publication restricted to owner-dispatched first attempt on exact main")
    for name in ("prepare-verified-adhoc-public-assets.py",
                 "materialize-strict-authenticated-release-history.py"):
        require((ROOT / name).is_file(), "required publisher dependency not integrated: " + name)
    wrapper = (ROOT / "materialize-authenticated-adhoc-release-history.sh").read_text()
    require("materialize-strict-authenticated-release-history.py" in wrapper,
            "strict full-history integration required")


REQUIRED_CHECKS = {
    "Canonical / Xcode 26.6 / App Build / Safety Guards",
    "Compatibility / macOS 15 / App Build",
}


def verify_exact_main_checks(pages, sha):
    require(type(pages) is list and pages, "invalid check run pages")
    found = {name: [] for name in REQUIRED_CHECKS}
    ids = set()
    total_count = None
    for page in pages:
        require(type(page) is dict and type(page.get("check_runs")) is list
                and type(page.get("total_count")) is int and page["total_count"] >= 0,
                "malformed check run page")
        if total_count is None:
            total_count = page["total_count"]
        require(page["total_count"] == total_count, "check run inventory count changed")
        for check in page["check_runs"]:
            require(type(check) is dict and type(check.get("id")) is int
                    and check["id"] > 0 and check["id"] not in ids
                    and type(check.get("name")) is str, "malformed or duplicate check run")
            ids.add(check["id"])
            if check["name"] in found:
                found[check["name"]].append(check)
    require(len(ids) == total_count, "incomplete check run inventory")
    for name, checks in found.items():
        require(len(checks) == 1, "missing or ambiguous required CI: " + name)
        check = checks[0]
        require(check.get("head_sha") == sha and type(check.get("app")) is dict
                and type(check["app"].get("id")) is int and check["app"]["id"] == 15368
                and check.get("status") == "completed" and check.get("conclusion") == "success",
                "required exact-main CI not successful: " + name)


class GitHub:
    def verify_authority(self, args):
        user = gh_json("GET", "user")
        require(type(user) is dict and user.get("id") == 90091196
                and user.get("login") == "Lamy210" and user.get("type") == "User",
                "authenticated publisher must be repository owner")
        repo = gh_json("GET", PREFIX)
        require(type(repo) is dict and repo.get("id") == 1359347782
                and repo.get("full_name") == REPO, "repository identity mismatch")
        gate("verify-local-release-source.sh", REPO)
        gate("setup-release-governance.sh", REPO, "--verify-only")
        setting = gh_json("GET", PREFIX + "/immutable-releases")
        require(type(setting) is dict and setting.get("enabled") is True,
                "immutable releases not enabled")
        main = gh_json("GET", PREFIX + "/branches/main")
        require(type(main) is dict and main.get("name") == "main"
                and type(main.get("commit")) is dict
                and main["commit"].get("sha") == args.source_sha,
                "live main differs from candidate")
        checks = gh_json("GET", PREFIX + "/commits/" + args.source_sha
                         + "/check-runs?per_page=100&filter=latest", paginate=True)
        verify_exact_main_checks(checks, args.source_sha)

    def prepare(self, args, workspace):
        outer = workspace / "outer.zip"
        public = workspace / "public"
        gate("download-verified-adhoc-actions-artifact.sh", args.run_id, args.artifact_id,
             args.version, args.source_sha, outer)
        command([sys.executable, str(ROOT / "prepare-verified-adhoc-public-assets.py"),
                 args.run_id, args.artifact_id, args.version, args.build, args.source_sha,
                 args.comment_id, str(outer), str(public)])
        return public

    def check_empty_slot(self, tag):
        gate("verify-adhoc-release-slot.sh", tag)

    def create_tag(self, tag, sha):
        ref = gh_json("POST", PREFIX + "/git/refs", {"ref": "refs/tags/" + tag, "sha": sha})
        require(type(ref) is dict and ref.get("ref") == "refs/tags/" + tag
                and type(ref.get("object")) is dict and ref["object"].get("type") == "commit"
                and ref["object"].get("sha") == sha, "created ref identity mismatch")

    def create_draft(self, tag, sha):
        body = ("Ad-hoc signed macOS application (macOS 15 or later). "
                "Not Developer ID signed or Apple notarized. Verify checksums and the source "
                "before opening. Do not disable Gatekeeper system-wide.")
        release = gh_json("POST", PREFIX + "/releases", {
            "tag_name": tag, "target_commitish": sha, "name": "SchneeGlass " + tag[1:],
            "body": body, "draft": True, "prerelease": False, "generate_release_notes": True,
            "make_latest": "false",
        })
        # Return the original create response; never discover/adopt by tag.
        return release

    def owned_slot(self, identity, tag, sha):
        pages = gh_json("GET", PREFIX + "/releases?per_page=100", paginate=True)
        require(type(pages) is list and pages and all(type(p) is list for p in pages),
                "malformed release inventory")
        ids, same_tag = set(), []
        for page in pages:
            for entry in page:
                require(type(entry) is dict and type(entry.get("id")) is int
                        and entry["id"] > 0 and entry["id"] not in ids
                        and type(entry.get("tag_name")) is str
                        and type(entry.get("draft")) is bool, "malformed or duplicate release inventory")
                ids.add(entry["id"])
                if entry["tag_name"] == tag:
                    same_tag.append(entry)
        require(len(same_tag) == 1 and str(same_tag[0]["id"]) == identity
                and same_tag[0]["draft"] is True, "draft slot no longer uniquely run-owned")
        require(reader.resolve_tag(tag) == sha, "owned tag changed")
        release = gh_json("GET", PREFIX + "/releases/" + identity)
        require(type(release) is dict and str(release.get("id")) == identity
                and release.get("tag_name") == tag and release.get("draft") is True
                and release.get("immutable") is False and release.get("prerelease") is False,
                "run-owned draft state changed")
        return release

    def upload(self, identity, name, directory, expected):
        # Exact fixed upload host and path; never send a token to a response-supplied URL.
        token = command(["gh", "auth", "token", "--hostname", "github.com"],
                        capture=True, timeout=30).strip()
        require(token and not any(c.isspace() for c in token), "invalid owner authentication")
        fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            limit = readback.validator.ARCHIVE_LIMIT if name.endswith(".zip") else readback.validator.METADATA_LIMIT
            with readback.validator.regular_file(fd, name, limit) as file:
                require(os.fstat(file.fileno()).st_size == expected[0], "asset size changed before upload")
                conn = http.client.HTTPSConnection("uploads.github.com", timeout=60)
                try:
                    conn.request("POST", "/" + PREFIX + "/releases/" + identity + "/assets?name=" + quote(name, safe=""),
                                 body=file, headers={
                                     "Authorization": "Bearer " + token,
                                     "Accept": "application/vnd.github+json",
                                     "X-GitHub-Api-Version": API_VERSION,
                                     "Content-Type": "application/octet-stream",
                                     "Content-Length": str(expected[0]),
                                 })
                    response = conn.getresponse()
                    require(response.status == 201, "asset upload failed; remote state may be ambiguous")
                    raw = response.read(1024 * 1024 + 1)
                    require(len(raw) <= 1024 * 1024, "upload response too large")
                    asset = parse_json(raw)
                finally:
                    conn.close()
        finally:
            os.close(fd)
        require(type(asset) is dict and type(asset.get("id")) is int and asset["id"] > 0
                and asset.get("name") == name and asset.get("state") == "uploaded"
                and asset.get("size") == expected[0] and asset.get("digest") == expected[1],
                "uploaded asset identity or digest mismatch")
        return asset["id"]

    def readback(self, phase, directory, identity, tag, sha):
        return readback.verify(directory, identity, tag, sha, phase)

    def fresh_checks(self, args, public, workspace):
        # Revalidate exact candidate identity and owner approval, not merely a prior PASS.
        fd = os.open(public, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            evidence = readback.validator.validate_json(
                readback.validator.metadata(fd, "ADHOC_RELEASE_EVIDENCE.json"),
                "v" + args.version, args.source_sha)
        finally:
            os.close(fd)
        require(evidence["run_id"] == args.run_id and evidence["artifact_id"] == args.artifact_id
                and evidence["qa_comment_id"] == args.comment_id and evidence["bundle_build"] == args.build,
                "prepared evidence identity mismatch")
        report = gate("verify-adhoc-run-artifact-from-github.sh", args.run_id,
                      args.version, args.source_sha, capture=True)
        require(report == "artifact_id=" + args.artifact_id + "\nartifact_digest=sha256:"
                + evidence["outer_artifact_sha256"] + "\n", "artifact identity changed")
        qa = gate("verify-adhoc-qa-comment-from-github.sh", args.comment_id, args.run_id,
                  args.version, args.build, args.source_sha, evidence["inner_zip_sha256"], capture=True)
        expected = ("Verified GitHub owner QA approval comment ID=" + args.comment_id
                    + " run=" + args.run_id + " source=" + args.source_sha
                    + " inner_zip_sha256=" + evidence["inner_zip_sha256"]
                    + " approved_at=" + evidence["qa_approved_at"] + "\n")
        require(qa == expected, "owner QA identity changed")
        with tempfile.TemporaryDirectory(prefix="fresh-history-", dir=workspace) as tmp:
            history = Path(tmp) / "snapshot"
            gate("materialize-authenticated-adhoc-release-history.sh", history)
            current = Path(tmp) / "current.txt"
            current.write_text("schema_version=1\nbundle_build=" + args.build + "\n")
            gate("verify-release-build-history.sh", current, history / "history")
        self.verify_authority(args)

    def final_assets(self, phase, identity, tag, expected, uploaded):
        require(phase in {"draft", "published"}, "invalid final asset verification phase")
        require(set(expected) == set(uploaded), "incomplete captured upload identities")
        remote = readback.remote_assets(identity, tag, phase)
        require({name: (uploaded[name], *value) for name, value in expected.items()} == remote,
                "final " + phase + " asset identities differ from uploads")

    def publish(self, identity):
        return gh_json("PATCH", PREFIX + "/releases/" + identity,
                       {"draft": False, "make_latest": "true"})


def execute(args, workspace, api):
    tag, sha = "v" + args.version, args.source_sha
    identity = None
    stage = "preflight"
    uploaded_ids = {}
    try:
        api.verify_authority(args)
        public = api.prepare(args, workspace)
        require(readback.validator.validate(public, tag, sha) == args.build, "prepared build mismatch")
        expected = readback.local_assets(public, tag)
        api.fresh_checks(args, public, workspace)
        api.check_empty_slot(tag)
        stage = "create-tag"
        api.create_tag(tag, sha)
        stage = "create-draft"
        draft = api.create_draft(tag, sha)
        # Capture ID even if a later field is malformed; provide exact reconciliation detail.
        if type(draft) is dict and type(draft.get("id")) is int and draft["id"] > 0:
            identity = str(draft["id"])
        require(identity is not None and draft.get("tag_name") == tag
                and draft.get("draft") is True and draft.get("immutable") is False
                and draft.get("prerelease") is False and draft.get("assets") == [],
                "unexpected create-draft response")
        stage = "upload"
        for name in sorted(expected):
            api.owned_slot(identity, tag, sha)
            require(readback.local_assets(public, tag) == expected, "prepared assets changed")
            asset_id = api.upload(identity, name, public, expected[name])
            require(asset_id not in uploaded_ids.values(), "duplicate created asset ID")
            uploaded_ids[name] = asset_id
        stage = "draft-readback"
        require(api.readback("draft", public, identity, tag, sha) == args.build, "draft build mismatch")
        stage = "final-preflight"
        api.fresh_checks(args, public, workspace)
        api.owned_slot(identity, tag, sha)
        require(readback.local_assets(public, tag) == expected, "prepared assets changed")
        require(api.readback("draft", public, identity, tag, sha) == args.build, "draft build mismatch")
        # Repeat authority after the potentially long read-back, then verify the owned slot.
        api.verify_authority(args)
        api.owned_slot(identity, tag, sha)
        api.final_assets("draft", identity, tag, expected, uploaded_ids)
        stage = "publish"
        response = api.publish(identity)
        require(type(response) is dict and str(response.get("id")) == identity
                and response.get("tag_name") == tag and response.get("draft") is False,
                "unexpected publish response")
        stage = "published-readback"
        require(api.readback("published", public, identity, tag, sha) == args.build,
                "published build mismatch")
        api.final_assets("published", identity, tag, expected, uploaded_ids)
        require(readback.local_assets(public, tag) == expected, "prepared assets changed")
        return identity
    except Exception:
        print(f"Publisher stopped: stage={stage} tag={tag} release_id={identity or 'unknown'} "
              f"uploaded_asset_ids={','.join(map(str, uploaded_ids.values())) or 'none'}. "
              "No retry, deletion, overwrite or adoption; reconcile observed remote state manually.",
              file=sys.stderr)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("run_id", "artifact_id", "version", "build", "source_sha", "comment_id", "confirm"):
        parser.add_argument(name)
    args = parser.parse_args()
    try:
        validate_context(args)
        with tempfile.TemporaryDirectory(prefix="schneeglass-publisher-") as tmp:
            identity = execute(args, Path(tmp), GitHub())
    except (OSError, ValueError, RecursionError, subprocess.SubprocessError, http.client.HTTPException) as exc:
        print(f"Publication not certified: {type(exc).__name__}", file=sys.stderr)
        return 1
    print(f"Published and verified immutable Release ID={identity} tag=v{args.version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
