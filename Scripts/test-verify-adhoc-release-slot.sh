#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
command -v jq >/dev/null 2>&1 || { echo 'jq required for fixtures' >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GH_BIN="$TMP/gh" JQ_BIN="$(command -v jq)" MOCK_DIR="$TMP"

cat > "$GH_BIN" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" -eq 4 && "$1" == 'api' && "$2" == '--paginate' && "$3" == '--slurp' ]] || exit 60
case "$4" in
  repos/Lamy210/SchneeGlass/releases\?per_page=100)
    [[ ! -f "$MOCK_DIR/fail-release" ]] || exit 61
    cat "$MOCK_DIR/releases.json"
    ;;
  repos/Lamy210/SchneeGlass/git/matching-refs/tags/v0.2.0\?per_page=100)
    [[ ! -f "$MOCK_DIR/fail-tags" ]] || exit 62
    cat "$MOCK_DIR/tags.json"
    ;;
  *) echo "Unexpected GH API path: $4" >&2; exit 63 ;;
esac
MOCK
chmod +x "$GH_BIN"

printf '[[],[{"id":42,"tag_name":"v0.1.1","draft":false}]]\n' > "$TMP/base-releases.json"
printf '[[],[{"ref":"refs/tags/v0.1.1","object":{"sha":"0123456789abcdef0123456789abcdef01234567"}}]]\n' > "$TMP/base-tags.json"
cp "$TMP/base-releases.json" "$TMP/releases.json"
cp "$TMP/base-tags.json" "$TMP/tags.json"

verify() { bash Scripts/verify-adhoc-release-slot.sh v0.2.0; }
reject() {
  local name="$1" diagnostic="$2"; shift 2
  local result
  if result="$("$@" 2>&1)"; then
    echo "Accepted invalid Release collision fixture: $name" >&2
    exit 1
  fi
  [[ "$result" == *"$diagnostic"* ]] || {
    echo "Wrong diagnostic for $name: $result" >&2
    exit 1
  }
}
verify >/dev/null

# An empty, fully enumerated repository is valid.
printf '[[]]\n' > "$TMP/releases.json"
printf '[[]]\n' > "$TMP/tags.json"
verify >/dev/null
cp "$TMP/base-releases.json" "$TMP/releases.json"
cp "$TMP/base-tags.json" "$TMP/tags.json"

mutate_releases() {
  local name="$1" transform="$2" expected="$3"
  jq "$transform" "$TMP/base-releases.json" > "$TMP/releases.json"
  reject "$name" "$expected" verify
  cp "$TMP/base-releases.json" "$TMP/releases.json"
}
mutate_tags() {
  local name="$1" transform="$2" expected="$3"
  jq "$transform" "$TMP/base-tags.json" > "$TMP/tags.json"
  reject "$name" "$expected" verify
  cp "$TMP/base-tags.json" "$TMP/tags.json"
}

mutate_releases 'published release collision' '.[1][0].tag_name="v0.2.0"' 'Release already uses target tag'
mutate_releases 'draft release collision' '.[1][0].tag_name="v0.2.0" | .[1][0].draft=true' 'Release already uses target tag'
mutate_tags 'lightweight tag collision' '.[1][0].ref="refs/tags/v0.2.0"' 'Git tag already exists'
mutate_tags 'annotated tag collision' '.[1][0].ref="refs/tags/v0.2.0" | .[1][0].object.sha="89abcdef0123456789abcdef0123456789abcdef"' 'Git tag already exists'

mutate_releases 'missing release id' 'del(.[1][0].id)' 'malformed paginated Release inventory'
mutate_releases 'malformed release draft' '.[1][0].draft="false"' 'malformed paginated Release inventory'
mutate_releases 'missing pages' '[]' 'malformed paginated Release inventory'
mutate_releases 'non-page response' '{data: .}' 'malformed paginated Release inventory'
mutate_tags 'malformed ref' '.[1][0].ref="refs/heads/main"' 'malformed paginated Git tag inventory'
mutate_tags 'missing tag object' 'del(.[1][0].object)' 'malformed paginated Git tag inventory'
mutate_tags 'unexpected object id' '.[1][0].object.sha="xyz"' 'malformed paginated Git tag inventory'
mutate_tags 'non-page response' '{data: .}' 'malformed paginated Git tag inventory'
mutate_tags 'missing pages' '[]' 'malformed paginated Git tag inventory'

touch "$TMP/fail-release"
reject 'Release API unavailable' 'unable to enumerate all GitHub Releases' verify
rm "$TMP/fail-release"
touch "$TMP/fail-tags"
reject 'tags API unavailable' 'unable to enumerate matching Git tags' verify
rm "$TMP/fail-tags"

reject 'missing candidate tag' 'usage:' bash Scripts/verify-adhoc-release-slot.sh
reject 'invalid tag' 'tag must be vX.Y.Z' bash Scripts/verify-adhoc-release-slot.sh 'v0.2.0/unsafe'
reject 'injected tag' 'tag must be vX.Y.Z' bash Scripts/verify-adhoc-release-slot.sh 'v0.2.0; echo x'

verify >/dev/null
echo 'Ad-hoc release slot collision and inventory fixtures passed'
