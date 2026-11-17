#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
command -v jq >/dev/null 2>&1 || { echo 'jq needed for fixture' >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export MOCK_DIR="$TMP"
export PATH="$TMP/bin:$PATH"

# Isolate synthetic legacy pins from the real, checked-in immutable digest
# baseline; the production scripts themselves are copied unchanged.
FIXTURE_REPO="$TMP/fixture-repo"
mkdir -p "$FIXTURE_REPO/Scripts" "$FIXTURE_REPO/docs/release-history"
for script in materialize-authenticated-adhoc-release-history.sh \
  materialize-strict-authenticated-release-history.py \
  verify-authenticated-adhoc-public-release.py \
  verify-adhoc-public-release-evidence.py verify-legacy-release-build-info.sh \
  verify-release-evidence.sh verify-release-build-history.sh; do
  cp "Scripts/$script" "$FIXTURE_REPO/Scripts/$script"
done
git -C "$FIXTURE_REPO" init -q

python3 - "$TMP" "$FIXTURE_REPO" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
import zipfile

root, repo = map(Path, sys.argv[1:])
prefix = "repos/Lamy210/SchneeGlass"
assets = root / "assets"
assets.mkdir()
pins = []
releases = []
for identity, tag, build, kind in [
    (8, "v0.1.0", "1", "legacy"),
    (9, "v0.1.1", "2", "legacy"),
    (12, "v0.2.0", "3", "adhoc"),
    (10, "v0.3.0", "4", "notarized"),
]:
    version, commit = tag[1:], build * 40
    distribution = "github-unsigned" if build == "1" else "github-adhoc"
    info = (
        f"version={version}\nbuild={build}\nsource_commit={commit}\n"
        "source_branch=main\ncode_signature=adhoc\n"
        "apple_developer_id_signed=false\napple_notarized=false\n"
        f"minimum_macos=15.0\nexecutable_info=synthetic\ndistribution={distribution}\n"
    ).encode()
    contents = {"BUILD_INFO.txt": info}
    if kind == "legacy":
        pins.append("\t".join([tag, commit, version, build, distribution,
                              hashlib.sha256(info).hexdigest()]))
    elif kind == "adhoc":
        name = f"SchneeGlass-{version}-adhoc.zip"
        archive_path = root / "fixture.zip"
        with zipfile.ZipFile(archive_path, "w") as archive:
            archive.writestr("Synthetic.txt", "not a real application")
        archive_bytes = archive_path.read_bytes()
        digest = hashlib.sha256(archive_bytes).hexdigest()
        contents[name] = archive_bytes
        contents["SHA256SUMS"] = f"{digest}  {name}\n".encode()
        contents["ADHOC_RELEASE_EVIDENCE.json"] = json.dumps({
            "schema_version": 1, "distribution": "github-adhoc",
            "repository_id": "1359347782", "tag": tag, "version": version,
            "bundle_identifier": "io.github.lamy210.schneeglass", "bundle_build": build,
            "source_sha": commit, "run_id": "123", "run_attempt": "1",
            "artifact_id": "456", "outer_artifact_sha256": "a" * 64,
            "inner_zip_sha256": digest, "public_zip_name": name, "public_zip_sha256": digest,
            "qa_comment_id": "789", "qa_owner_id": "90091196",
            "qa_approved_at": "2026-01-02T03:04:05Z",
            "code_signature": "adhoc", "apple_developer_id_signed": False,
            "apple_notarized": False,
        }).encode()
    else:
        contents = {"RELEASE_EVIDENCE.txt": (
            f"schema_version=1\nversion={version}\n"
            "notarization_id=00000000-0000-0000-0000-000000000001\n"
            "notarization_status=Accepted\ncodesign=verified\nstapler=validated\n"
            "gatekeeper=accepted\nbundle_identifier=io.github.lamy210.schneeglass\n"
            f"bundle_version={version}\nbundle_build={build}\ncommit_sha={commit}\n"
        ).encode()}
    metadata = []
    for index, (name, data) in enumerate(contents.items(), 1):
        asset_id = identity * 100 + index
        (assets / str(asset_id)).write_bytes(data)
        metadata.append({"id": asset_id, "name": name, "size": len(data),
                         "digest": "sha256:" + hashlib.sha256(data).hexdigest(),
                         "state": "uploaded"})
    release = {"id": identity, "tag_name": tag, "draft": False,
               "immutable": kind != "legacy", "assets": metadata}
    (root / f"release-{identity}.json").write_text(json.dumps(release))
    (root / f"ref-{tag}.json").write_text(json.dumps({
        "ref": "refs/tags/" + tag, "object": {"type": "commit", "sha": commit},
    }))
    releases.append({"id": identity, "tag_name": tag, "draft": False})
(repo / "docs/release-history/legacy-public-releases.tsv").write_text("\n".join(pins) + "\n")
(root / "base-releases.json").write_text(json.dumps([
    [releases[3], {"id": 11, "tag_name": "v0.5.0", "draft": True}, releases[0], releases[1]],
    [releases[2]],
]))
PY

cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

root = Path(os.environ["MOCK_DIR"])
args = sys.argv[1:]
prefix = "repos/Lamy210/SchneeGlass"
if args == ["api", "--hostname", "github.com", "--method", "GET",
            "--paginate", "--slurp", prefix + "/releases?per_page=100"]:
    if (root / "fail-api").exists():
        sys.exit(62)
    pages = json.loads((root / "releases.json").read_text())
    if (root / "inventory-change").exists():
        marker = root / "inventory-read"
        if marker.exists():
            pages[0].append({"id": 1000, "tag_name": "v0.4.0", "draft": False})
        else:
            marker.touch()
    print(json.dumps(pages))
    sys.exit(0)
if len(args) != 8 or args[:6] != ["api", "--hostname", "github.com", "--method", "GET", "-H"]:
    sys.exit(63)
accept, endpoint = args[6:]
if accept == "Accept: application/octet-stream" and endpoint.startswith(prefix + "/releases/assets/"):
    if (root / "fail-download").exists():
        sys.exit(67)
    data = (root / "assets" / endpoint.rsplit("/", 1)[1]).read_bytes()
    if (root / "tampered-asset").exists():
        data += b"x"
    sys.stdout.buffer.write(data)
elif accept == "Accept: application/vnd.github+json":
    if endpoint == prefix:
        response = {"id": 1359347782, "full_name": "Lamy210/SchneeGlass"}
    elif endpoint.startswith(prefix + "/releases/"):
        if (root / "fail-view").exists():
            sys.exit(64)
        identity = endpoint.rsplit("/", 1)[1]
        response = json.loads((root / f"release-{identity}.json").read_text())
        if (root / "duplicate-asset").exists():
            response["assets"].append(response["assets"][0])
        if identity == "8" and (root / "legacy-override").exists():
            response["assets"].append({"id": 999, "name": "RELEASE_EVIDENCE.txt"})
        if identity == "12" and (root / "dual-schema").exists():
            response["assets"].append({"id": 999, "name": "RELEASE_EVIDENCE.txt"})
        if identity == "12" and (root / "mutable-new").exists():
            response["immutable"] = False
    elif endpoint.startswith(prefix + "/git/ref/tags/"):
        tag = endpoint.rsplit("/", 1)[1]
        response = json.loads((root / f"ref-{tag}.json").read_text())
        if tag == "v0.1.0" and (root / "wrong-legacy-ref").exists():
            response["object"]["sha"] = "f" * 40
    else:
        sys.exit(65)
    print(json.dumps(response))
else:
    sys.exit(69)
MOCK
chmod +x "$TMP/bin/gh"

cp "$TMP/base-releases.json" "$TMP/releases.json"

run() {
  bash "$FIXTURE_REPO/Scripts/materialize-authenticated-adhoc-release-history.sh" "$1"
}

reject() {
  local name="$1" diagnostic="$2"
  shift 2
  local result
  if result="$("$@" 2>&1)"; then
    echo "Accepted bad release-history fixture: $name" >&2
    exit 1
  fi
  [[ "$result" == *"$diagnostic"* ]] || {
    echo "Unexpected failure for $name: $result" >&2
    exit 1
  }
}

run "$TMP/complete" >/dev/null
[[ "$(wc -l < "$TMP/complete/published-tags.txt")" -eq 4 ]]
grep -Fxq 'v0.1.0' "$TMP/complete/published-tags.txt"
grep -Fxq 'v0.1.1' "$TMP/complete/published-tags.txt"
grep -Fxq 'v0.2.0' "$TMP/complete/published-tags.txt"
grep -Fxq 'v0.3.0' "$TMP/complete/published-tags.txt"
grep -Fxq 'bundle_build=1' "$TMP/complete/history/1/RELEASE_EVIDENCE.txt"
grep -Fxq 'bundle_build=2' "$TMP/complete/history/2/RELEASE_EVIDENCE.txt"
grep -Fxq 'bundle_build=3' "$TMP/complete/history/3/RELEASE_EVIDENCE.txt"
grep -Fxq 'bundle_build=4' "$TMP/complete/history/4/RELEASE_EVIDENCE.txt"
[[ ! -d "$TMP/complete/history/5" ]]
[[ -f "$TMP/complete/release-inventory.json" ]]
[[ -f "$TMP/complete/history/1/BUILD_INFO.txt" ]]
[[ -f "$TMP/complete/history/2/BUILD_INFO.txt" ]]
[[ -f "$TMP/complete/history/4/NOTARIZED_EVIDENCE.txt" ]]
for build in 5 4 3; do
  printf 'schema_version=1\nbundle_build=%s\n' "$build" > "$TMP/current-evidence.txt"
  if [[ "$build" == 5 ]]; then
    bash Scripts/verify-release-build-history.sh "$TMP/current-evidence.txt" "$TMP/complete/history" >/dev/null
  else
    reject "nonincreasing build $build" 'must be greater than published maximum' \
      bash Scripts/verify-release-build-history.sh "$TMP/current-evidence.txt" "$TMP/complete/history"
  fi
done


mkdir "$TMP/existing"
printf 'retain this snapshot\n' > "$TMP/existing/marker.txt"
reject 'already existing destination' 'output directory already exists' run "$TMP/existing"
grep -Fxq 'retain this snapshot' "$TMP/existing/marker.txt"

mutate() {
  local name="$1" jq_filter="$2" expected="$3" dest="$4"
  jq "$jq_filter" "$TMP/base-releases.json" > "$TMP/releases.json"
  reject "$name" "$expected" run "$TMP/$dest"
  [[ ! -e "$TMP/$dest" ]] || { echo "Partial history directory leaked for $name" >&2; exit 1; }
  cp "$TMP/base-releases.json" "$TMP/releases.json"
}

mutate 'missing known v0.1.1 public Release' '.[0] |= map(select(.tag_name != "v0.1.1"))' 'known public Release missing from GitHub inventory' 'missing-legacy'
mutate 'duplicate id' '.[1][0].id=10' 'duplicate IDs/tags' 'dup-id'
mutate 'duplicate published tag' '.[1][0].tag_name="v0.3.0"' 'duplicate IDs/tags' 'dup-tag'
mutate 'unsupported public tag' '.[1][0].tag_name="nightly"' 'duplicate IDs/tags' 'bad-tag'
mutate 'missing published id' 'del(.[1][0].id)' 'page inventory is malformed' 'missing-id'
mutate 'malformed draft flag' '.[1][0].draft="false"' 'page inventory is malformed' 'bad-draft'
mutate 'missing tags' 'del(.[0][0].tag_name)' 'page inventory is malformed' 'missing-tag'
mutate 'missing pages' '[]' 'page inventory is malformed' 'no-pages'
mutate 'invalid outer envelope' '{data: .}' 'page inventory is malformed' 'bad-envelope'

printf '[[]]\n' > "$TMP/releases.json"
reject 'empty inventory missing legacy Releases' 'known public Release missing from GitHub inventory' run "$TMP/empty"
[[ ! -e "$TMP/empty" ]]
cp "$TMP/base-releases.json" "$TMP/releases.json"

for case_name in fail-api fail-view fail-download duplicate-asset legacy-override dual-schema mutable-new wrong-legacy-ref tampered-asset; do
  touch "$TMP/$case_name"
  case "$case_name" in
    fail-api) expected='unable to enumerate public Releases' ;;
    fail-view|fail-download|duplicate-asset|legacy-override|dual-schema|mutable-new|wrong-legacy-ref|tampered-asset) expected='published Release history could not be fully materialized' ;;
  esac
  reject "$case_name" "$expected" run "$TMP/fail-$case_name"
  [[ ! -e "$TMP/fail-$case_name" ]] || { echo "Leaked failed history snapshot: $case_name" >&2; exit 1; }
  rm "$TMP/$case_name"
done

touch "$TMP/inventory-change"
reject 'new release during collection' 'published Release inventory changed during collection' run "$TMP/changed-inventory"
[[ ! -e "$TMP/changed-inventory" ]]
rm "$TMP/inventory-change" "$TMP/inventory-read"

reject 'missing output argument' 'usage:' bash Scripts/materialize-authenticated-adhoc-release-history.sh
reject 'missing parent' 'output parent must be an existing real directory' run "$TMP/absent/snapshot"

# Inject a destination immediately after the final shell existence check.
# Wrap both the original mv and the replacement python3, so the regression
# actually fails on the old implementation rather than only the new path.
export REAL_PYTHON3="$(command -v python3)"
export REAL_MV="$(command -v mv)"
cat > "$TMP/bin/inject-promotion" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
case "${0##*/}" in
  python3)
    if [[ "$#" -ne 3 || "$1" != "-" ]]; then
      exec "$REAL_PYTHON3" "$@"
    fi
    shift
    src="$1"
    dst="$2"
    command_path="$REAL_PYTHON3"
    ;;
  mv)
    if [[ "$#" -ne 3 || "$1" != "--" || "$2" != */.schneeglass-public-history.* ]]; then
      exec "$REAL_MV" "$@"
    fi
    shift
    src="$1"
    dst="$2"
    command_path="$REAL_MV"
    ;;
  *) exit 71 ;;
esac
[[ "$src" == */.schneeglass-public-history.* ]] || exit 72
case "${MOCK_PROMOTION_RACE:-}" in
  directory) mkdir "$dst" ;;
  nonempty) mkdir "$dst"; printf 'preserve marker\n' > "$dst/marker.txt" ;;
  symlink) ln -s "$MOCK_DIR/race-owner" "$dst" ;;
  file) printf 'preserve file\n' > "$dst" ;;
  '') ;;
  *) exit 73 ;;
esac
if [[ "$command_path" == "$REAL_PYTHON3" ]]; then
  exec "$command_path" - "$src" "$dst"
fi
exec "$command_path" -- "$src" "$dst"
SHIM
chmod +x "$TMP/bin/inject-promotion"
ln -s inject-promotion "$TMP/bin/python3"
ln -s inject-promotion "$TMP/bin/mv"
mkdir "$TMP/race-owner"
printf 'owner marker\n' > "$TMP/race-owner/keep.txt"
for race in directory nonempty symlink file; do
  export MOCK_PROMOTION_RACE="$race"
  dest="$TMP/race-$race"
  reject "$race at promotion" 'unable to finalize verified history snapshot without replacement' run "$dest"
  # No private stage leaks, no destination replacement, no nested snapshot.
  [[ -z "$(find "$TMP" -maxdepth 1 -name '.schneeglass-public-history.*' -print)" ]]
  case "$race" in
    directory) [[ -d "$dest" && -z "$(ls -A "$dest")" ]] ;;
    nonempty) [[ -d "$dest" && "$(ls -A "$dest")" == 'marker.txt' ]]; grep -Fxq 'preserve marker' "$dest/marker.txt" ;;
    symlink) [[ -L "$dest" && "$(ls -A "$TMP/race-owner")" == 'keep.txt' ]]; grep -Fxq 'owner marker' "$TMP/race-owner/keep.txt" ;;
    file) [[ -f "$dest" ]]; grep -Fxq 'preserve file' "$dest" ;;
  esac
done
unset MOCK_PROMOTION_RACE

run "$TMP/final" >/dev/null
grep -Fxq 'bundle_build=4' "$TMP/final/history/4/RELEASE_EVIDENCE.txt"
# The actual Publisher requires a clean source checkout again after history
# acquisition. The helper must not generate bytecode/cache files alongside code.
[[ -z "$(find "$FIXTURE_REPO/Scripts" -name '__pycache__' -o -name '*.pyc')" ]] \
  || { echo 'Read-only history acquisition dirtied the source tree' >&2; exit 1; }
echo 'Authenticated full public Release history fixtures passed'
