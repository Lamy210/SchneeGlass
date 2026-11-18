#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
WORKFLOW=".github/workflows/adhoc-release-candidate.yml"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

fail() { echo "Extracted app workflow gate fixture failed: $*" >&2; exit 1; }
step_line() { awk -v label="$2" '$0 == "      - name: " label { print NR; exit }' "$1"; }

verify_gate() {
  local file="$1" build gate next upload section
  build="$(step_line "$file" 'Build and verify ad-hoc candidate')"
  gate="$(step_line "$file" 'Verify real extracted ad-hoc app')"
  next="$(step_line "$file" 'Verify candidate artifact set')"
  upload="$(step_line "$file" 'Upload ad-hoc candidate')"
  [[ "$build" =~ ^[1-9][0-9]*$ && "$gate" =~ ^[1-9][0-9]*$ &&
     "$next" =~ ^[1-9][0-9]*$ && "$upload" =~ ^[1-9][0-9]*$ ]] || return 1
  (( build < gate && gate < next && next < upload )) || return 1
  [[ "$(grep -Fc '      - name: Verify real extracted ad-hoc app' "$file")" == 1 ]] || return 1
  section="$(awk -v start="$gate" -v stop="$next" 'NR>=start && NR<stop' "$file")"
  printf '%s\n' "$section" | grep -Fxq '          RELEASE_VERSION: ${{ steps.release.outputs.version }}' || return 1
  printf '%s\n' "$section" | grep -Fxq '          RELEASE_BUILD: ${{ steps.release.outputs.build }}' || return 1
  printf '%s\n' "$section" | grep -Fq 'ditto -x -k "adhoc-release-output/SchneeGlass-$RELEASE_VERSION-adhoc-candidate.zip"' || return 1
  printf '%s\n' "$section" | grep -Fq 'bash Scripts/verify-extracted-adhoc-app.sh' || return 1
  printf '%s\n' "$section" | grep -Fq '"$QA_DIR/SchneeGlass.app" "$RELEASE_VERSION" "$RELEASE_BUILD"' || return 1
  printf '%s\n' "$section" | grep -Fxq '          python3 Scripts/verify-localization-bundle.py "$QA_DIR/SchneeGlass.app"' || return 1
  local strict extract signature localization
  strict="$(printf '%s\n' "$section" | grep -nFx '          set -euo pipefail' | cut -d: -f1)"
  extract="$(printf '%s\n' "$section" | grep -nF 'ditto -x -k "adhoc-release-output/SchneeGlass-$RELEASE_VERSION-adhoc-candidate.zip"' | cut -d: -f1)"
  signature="$(printf '%s\n' "$section" | grep -nF 'bash Scripts/verify-extracted-adhoc-app.sh' | cut -d: -f1)"
  localization="$(printf '%s\n' "$section" | grep -nFx '          python3 Scripts/verify-localization-bundle.py "$QA_DIR/SchneeGlass.app"' | cut -d: -f1)"
  [[ "$strict" =~ ^[1-9][0-9]*$ && "$extract" =~ ^[1-9][0-9]*$ &&
     "$signature" =~ ^[1-9][0-9]*$ && "$localization" =~ ^[1-9][0-9]*$ ]] || return 1
  (( strict < extract && extract < signature && signature < localization )) || return 1
  if printf '%s\n' "$section" | grep -Eq 'continue-on-error|if:|\|\|[[:space:]]*true'; then return 1; fi
  return 0
}

verify_gate "$WORKFLOW" || fail 'live workflow has no strict extracted-app gate'

expect_rejected() {
  if verify_gate "$2"; then fail "mutation unexpectedly accepted: $1"; fi
}

grep -Fv '      - name: Verify real extracted ad-hoc app' "$WORKFLOW" > "$FIXTURE/missing.yml"
expect_rejected 'missing gate' "$FIXTURE/missing.yml"

sed 's/RELEASE_BUILD: \${{ steps.release.outputs.build }}/RELEASE_BUILD: 0/' "$WORKFLOW" > "$FIXTURE/wrong-build.yml"
expect_rejected 'incorrect build source' "$FIXTURE/wrong-build.yml"

sed 's/ditto -x -k /ditto -c -k /' "$WORKFLOW" > "$FIXTURE/not-extracted.yml"
expect_rejected 'incorrect archive operation' "$FIXTURE/not-extracted.yml"

sed 's|bash Scripts/verify-extracted-adhoc-app.sh|bash Scripts/verify-adhoc-candidate-artifact.sh|' "$WORKFLOW" > "$FIXTURE/wrong-check.yml"
expect_rejected 'wrong validator' "$FIXTURE/wrong-check.yml"

sed '/^      - name: Verify real extracted ad-hoc app$/,/^      - name: Verify candidate artifact set$/{
  s/^        run: |$/        continue-on-error: true\n        run: |/
}' "$WORKFLOW" > "$FIXTURE/ignored-error.yml"
expect_rejected 'ignored validator failure' "$FIXTURE/ignored-error.yml"

grep -Fv '          python3 Scripts/verify-localization-bundle.py "$QA_DIR/SchneeGlass.app"' "$WORKFLOW" > "$FIXTURE/no-localization.yml"
expect_rejected 'missing localization validator' "$FIXTURE/no-localization.yml"

sed 's|python3 Scripts/verify-localization-bundle.py "\$QA_DIR/SchneeGlass.app"|python3 Scripts/verify-localization-bundle.py /tmp/wrong.app|' "$WORKFLOW" > "$FIXTURE/wrong-localization-app.yml"
expect_rejected 'wrong localization app' "$FIXTURE/wrong-localization-app.yml"

sed '/^      - name: Verify real extracted ad-hoc app$/,/^      - name: Verify candidate artifact set$/{
  s/^          set -euo pipefail$/          set -uo pipefail/
}' "$WORKFLOW" > "$FIXTURE/non-strict.yml"
expect_rejected 'missing strict shell failure handling' "$FIXTURE/non-strict.yml"

awk '
  /^          python3 Scripts\/verify-localization-bundle.py / { next }
  /^          ditto -x -k / {
    print "          python3 Scripts/verify-localization-bundle.py \"$QA_DIR/SchneeGlass.app\""
  }
  { print }
' "$WORKFLOW" > "$FIXTURE/localization-before-extraction.yml"
expect_rejected 'localization before extraction' "$FIXTURE/localization-before-extraction.yml"

echo 'Extracted app workflow wiring regression fixtures passed'
