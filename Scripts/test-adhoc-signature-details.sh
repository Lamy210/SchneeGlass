#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-adhoc-signature-details-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"

VALID="$FIXTURE/valid.txt"
cat > "$VALID" <<'EOF'
Executable=/tmp/SchneeGlass.app/Contents/MacOS/SchneeGlass
Identifier=io.github.lamy210.schneeglass
Format=app bundle with Mach-O thin (arm64)
CodeDirectory v=20500 size=1234 flags=0x10002(adhoc,runtime) hashes=30+7 location=embedded
Signature=adhoc
EOF

bash Scripts/verify-adhoc-signature-details.sh "$VALID"

expect_failure() {
  local label="$1"
  shift
  if "$@" >"$FIXTURE/failure.log" 2>&1; then
    cat "$FIXTURE/failure.log"
    echo "Ad-hoc signature verifier unexpectedly accepted: $label" >&2
    exit 1
  fi
}

cp "$VALID" "$FIXTURE/authority.txt"
printf '%s\n' 'Authority=Developer ID Application: Example' >> "$FIXTURE/authority.txt"
expect_failure   'certificate authority'   bash Scripts/verify-adhoc-signature-details.sh "$FIXTURE/authority.txt"
grep -Fq 'certificate authority is present' "$FIXTURE/failure.log"

grep -v '^Signature=adhoc$' "$VALID" > "$FIXTURE/no-signature.txt"
expect_failure   'missing ad-hoc signature'   bash Scripts/verify-adhoc-signature-details.sh "$FIXTURE/no-signature.txt"
grep -Fq 'ad-hoc signature marker is missing' "$FIXTURE/failure.log"

sed 's/(adhoc,runtime)/(adhoc)/' "$VALID" > "$FIXTURE/no-runtime.txt"
expect_failure   'missing Hardened Runtime'   bash Scripts/verify-adhoc-signature-details.sh "$FIXTURE/no-runtime.txt"
grep -Fq 'Hardened Runtime marker is missing' "$FIXTURE/failure.log"

cat > "$FIXTURE/bin/grep-fail" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
chmod +x "$FIXTURE/bin/grep-fail"
expect_failure   'grep enumeration failure'   env GREP_BIN="$FIXTURE/bin/grep-fail"     bash Scripts/verify-adhoc-signature-details.sh "$VALID"
grep -Fq 'grep status 42' "$FIXTURE/failure.log"

rm -rf "$FIXTURE"
echo 'Ad-hoc signature-details fixtures passed'
