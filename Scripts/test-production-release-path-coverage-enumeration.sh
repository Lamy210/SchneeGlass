#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="\${RUNNER_TEMP:-/tmp}/schneeglass-production-path-coverage-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"

REAL_GREP="$(command -v grep)"
OUTPUT="$FIXTURE/output.log"

REQUIRED_PATHS=(
  'Scripts/verify-release-metadata.sh'
  'Scripts/test-release-bundle-metadata-key-probe.sh'
  'Scripts/initialize-release-evidence-schema.sh'
  'Scripts/test-release-evidence-schema-probe.sh'
  'Scripts/verify-optional-release-entitlements.sh'
  'Scripts/test-optional-release-entitlement-probes.sh'
  'Scripts/verify-required-plist-value.sh'
  'Scripts/test-required-plist-value-probes.sh'
  'Scripts/verify-production-release-path-coverage.sh'
  'Scripts/test-production-release-path-coverage-enumeration.sh'
)

# Control: the real workflow remains fully covered.
bash Scripts/verify-production-release-path-coverage.sh \
  .github/workflows/production-release.yml \
  "\${REQUIRED_PATHS[@]}" >/dev/null

cat > "$FIXTURE/bin/sed" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
  pull_request:
    paths:
      - 'Scripts/verify-release-metadata.sh'
      - 'Scripts/test-release-bundle-metadata-key-probe.sh'
      - 'Scripts/initialize-release-evidence-schema.sh'
      - 'Scripts/test-release-evidence-schema-probe.sh'
      - 'Scripts/verify-optional-release-entitlements.sh'
      - 'Scripts/test-optional-release-entitlement-probes.sh'
      - 'Scripts/verify-required-plist-value.sh'
      - 'Scripts/test-required-plist-value-probes.sh'
      - 'Scripts/verify-production-release-path-coverage.sh'
      - 'Scripts/test-production-release-path-coverage-enumeration.sh'
permissions:
EOF
echo 'fixture: pull_request.paths enumeration failed after partial output' >&2
exit 42
SHIM
chmod +x "$FIXTURE/bin/sed"

set +e
PATH="$FIXTURE/bin:$PATH" \
  bash Scripts/verify-production-release-path-coverage.sh \
  .github/workflows/production-release.yml \
  "\${REQUIRED_PATHS[@]}" \
  >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'Production release path coverage unexpectedly accepted partial enumeration output.' >&2
  exit 1
fi

"$REAL_GREP" -Fq \
  'Production release path coverage validation failed: unable to enumerate pull_request.paths (sed status 42)' \
  "$OUTPUT"

rm -rf "$FIXTURE"
echo 'Production release path-coverage enumeration failure fixture passed'
