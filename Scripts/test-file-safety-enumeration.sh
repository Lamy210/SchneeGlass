#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
OUTPUT="$FIXTURE/output.log"
LOCK_SOURCE="$ROOT/Packages/SchneeGlassKit/Sources/SchneeGlassPersistenceAdapter/ApplicationProcessLock.swift"
LOCK_BACKUP="$FIXTURE/ApplicationProcessLock.swift.backup"

REAL_GREP="$(command -v grep)"

cleanup() {
  if [[ -f "$LOCK_BACKUP" ]]; then
    cp "$LOCK_BACKUP" "$LOCK_SOURCE"
  fi
  rm -rf "$FIXTURE"
}
trap cleanup EXIT

cat > "$FIXTURE/bin/grep" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
echo 'fixture: grep enumeration unavailable' >&2
exit 42
SHIM
chmod +x "$FIXTURE/bin/grep"

set +e
PATH="$FIXTURE/bin:$PATH" bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'File Safety Guard unexpectedly passed when mutation enumeration failed.' >&2
  exit 1
fi

"$REAL_GREP" -Fq \
  'File safety verification failed: unable to enumerate filesystem mutation pattern' \
  "$OUTPUT"

cp "$LOCK_SOURCE" "$LOCK_BACKUP"
printf '%s\n' \
  'private let fileSafetySmuggledMutation = unlink("/tmp/schneeglass-file-safety-fixture")  // O_CREAT' \
  >> "$LOCK_SOURCE"

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
STATUS=$?
set -e

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
rm -f "$LOCK_BACKUP"

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'File Safety Guard unexpectedly allowed a forbidden mutation hidden by an allowlisted token.' >&2
  exit 1
fi

"$REAL_GREP" -Fq 'ApplicationProcessLock.swift' "$OUTPUT"
"$REAL_GREP" -Fq 'unlink(' "$OUTPUT"

echo 'File Safety Guard enumeration and allowlist-boundary fixtures passed'
