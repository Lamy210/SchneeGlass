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

cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}:${2:-}" in
  api:--paginate)
    [[ "$#" -eq 4 && "$3" == '--slurp' && "$4" == 'repos/Lamy210/SchneeGlass/releases?per_page=100' ]] || exit 61
    [[ ! -f "$MOCK_DIR/fail-api" ]] || exit 62
    cat "$MOCK_DIR/releases.json"
    ;;
  release:view)
    [[ "$#" -eq 7 && "$4" == '--repo' && "$5" == 'Lamy210/SchneeGlass' && "$6" == '--json' && "$7" == 'targetCommitish,assets' ]] || exit 63
    [[ ! -f "$MOCK_DIR/fail-view" ]] || exit 64
    case "$3" in
      v0.2.0|v0.3.0)
        if [[ -f "$MOCK_DIR/duplicate-asset" ]]; then
          printf '%s\n' '{"targetCommitish":"0123456789abcdef0123456789abcdef01234567","assets":[{"name":"RELEASE_EVIDENCE.txt"},{"name":"RELEASE_EVIDENCE.txt"}]}'
        else
          printf '%s\n' '{"targetCommitish":"0123456789abcdef0123456789abcdef01234567","assets":[{"name":"RELEASE_EVIDENCE.txt"}]}'
        fi
        ;;
      *) exit 65 ;;
    esac
    ;;
  release:download)
    [[ "$#" -eq 9 && "$4" == '--repo' && "$5" == 'Lamy210/SchneeGlass' && "$6" == '--pattern' && "$7" == 'RELEASE_EVIDENCE.txt' && "$8" == '--dir' ]] || exit 66
    [[ ! -f "$MOCK_DIR/fail-download" ]] || exit 67
    case "$3" in
      v0.2.0) build=3 ;;
      v0.3.0) build=4 ;;
      *) exit 68 ;;
    esac
    printf 'schema_version=1\nbundle_build=%s\n' "$build" > "$9/RELEASE_EVIDENCE.txt"
    ;;
  *) echo "Unexpected gh invocation: $*" >&2; exit 69 ;;
esac
MOCK
chmod +x "$TMP/bin/gh"

cat > "$TMP/base-releases.json" <<'JSON'
[
  [
    {"id": 10, "tag_name": "v0.3.0", "draft": false},
    {"id": 11, "tag_name": "v0.5.0", "draft": true}
  ],
  [
    {"id": 12, "tag_name": "v0.2.0", "draft": false}
  ]
]
JSON
cp "$TMP/base-releases.json" "$TMP/releases.json"

run() {
  bash Scripts/materialize-authenticated-adhoc-release-history.sh "$1"
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
[[ "$(cat "$TMP/complete/published-tags.txt")" == $'v0.2.0\nv0.3.0' ]]
grep -Fxq 'bundle_build=3' "$TMP/complete/history/1/RELEASE_EVIDENCE.txt"
grep -Fxq 'bundle_build=4' "$TMP/complete/history/2/RELEASE_EVIDENCE.txt"
[[ ! -d "$TMP/complete/history/3" ]]
[[ -f "$TMP/complete/release-inventory.json" ]]

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

mutate 'duplicate id' '.[1][0].id=10' 'duplicate IDs/tags' 'dup-id'
mutate 'duplicate published tag' '.[1][0].tag_name="v0.3.0"' 'duplicate IDs/tags' 'dup-tag'
mutate 'unsupported public tag' '.[1][0].tag_name="nightly"' 'duplicate IDs/tags' 'bad-tag'
mutate 'missing published id' 'del(.[1][0].id)' 'page inventory is malformed' 'missing-id'
mutate 'malformed draft flag' '.[1][0].draft="false"' 'page inventory is malformed' 'bad-draft'
mutate 'missing tags' 'del(.[0][0].tag_name)' 'page inventory is malformed' 'missing-tag'
mutate 'missing pages' '[]' 'page inventory is malformed' 'no-pages'
mutate 'invalid outer envelope' '{data: .}' 'page inventory is malformed' 'bad-envelope'

printf '[[]]\n' > "$TMP/releases.json"
run "$TMP/empty" >/dev/null
[[ ! -s "$TMP/empty/published-tags.txt" ]]
[[ -d "$TMP/empty/history" && ! -e "$TMP/empty/history/1" ]]
cp "$TMP/base-releases.json" "$TMP/releases.json"

for case_name in fail-api fail-view fail-download duplicate-asset; do
  touch "$TMP/$case_name"
  case "$case_name" in
    fail-api) expected='unable to enumerate public Releases' ;;
    fail-view|fail-download|duplicate-asset) expected='published Release history could not be fully materialized' ;;
  esac
  reject "$case_name" "$expected" run "$TMP/fail-$case_name"
  [[ ! -e "$TMP/fail-$case_name" ]] || { echo "Leaked failed history snapshot: $case_name" >&2; exit 1; }
  rm "$TMP/$case_name"
done

reject 'missing output argument' 'usage:' bash Scripts/materialize-authenticated-adhoc-release-history.sh
reject 'missing parent' 'output parent must be an existing real directory' run "$TMP/absent/snapshot"

run "$TMP/final" >/dev/null
grep -Fxq 'bundle_build=4' "$TMP/final/history/2/RELEASE_EVIDENCE.txt"
echo 'Authenticated full public Release history fixtures passed'
