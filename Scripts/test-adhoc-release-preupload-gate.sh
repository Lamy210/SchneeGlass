#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

WORKFLOW='.github/workflows/adhoc-release-candidate.yml'
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

fail() {
  echo "Ad-hoc pre-upload gate fixture failed: $*" >&2
  exit 1
}

step_line() {
  awk -v label="$2" '$0 == "      - name: " label { print NR; exit }' "$1"
}

verify_gate() {
  local workflow="$1"
  local build_line verify_line gate_line upload_line end_line section

  build_line="$(step_line "$workflow" 'Build and verify ad-hoc candidate')"
  verify_line="$(step_line "$workflow" 'Verify candidate artifact set')"
  gate_line="$(step_line "$workflow" 'Verify candidate artifact integrity before upload')"
  upload_line="$(step_line "$workflow" 'Upload ad-hoc candidate')"

  [[ "$build_line" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$verify_line" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$gate_line" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$upload_line" =~ ^[1-9][0-9]*$ ]] || return 1
  (( build_line < verify_line && verify_line < gate_line && gate_line < upload_line )) || return 1

  [[ "$(grep -Fc '      - name: Verify candidate artifact integrity before upload' "$workflow")" == '1' ]] || return 1

  end_line=$((upload_line - 1))
  section="$(sed -n "${gate_line},${end_line}p" "$workflow")"

  printf '%s\n' "$section" | grep -Fxq "        if: github.event_name == 'workflow_dispatch'" || return 1
  printf '%s\n' "$section" | grep -Fxq '          RELEASE_VERSION: ${{ steps.release.outputs.version }}' || return 1
  printf '%s\n' "$section" | grep -Fxq '          RELEASE_BUILD: ${{ steps.release.outputs.build }}' || return 1
  printf '%s\n' "$section" | grep -Fq 'bash Scripts/verify-adhoc-candidate-artifact.sh' || return 1
  for arg in 'adhoc-release-output' '"$RELEASE_VERSION"' '"$RELEASE_BUILD"' '"$GITHUB_SHA"'; do
    printf '%s\n' "$section" | grep -Fq "$arg" || return 1
  done
  if printf '%s\n' "$section" | grep -Eq 'continue-on-error|\|\|[[:space:]]*true'; then
    return 1
  fi

  grep -Fq 'echo "build=$BUILD_NUMBER" >> "$GITHUB_OUTPUT"' "$workflow" || return 1
  return 0
}

verify_gate "$WORKFLOW" || fail 'live workflow lost its fail-closed pre-upload gate'

expect_rejection() {
  local name="$1"
  local candidate="$2"
  if verify_gate "$candidate"; then
    fail "mutated workflow unexpectedly passed: $name"
  fi
}

grep -Fv '      - name: Verify candidate artifact integrity before upload' "$WORKFLOW" > "$FIXTURE/no-gate.yml"
expect_rejection 'deleted gate' "$FIXTURE/no-gate.yml"

sed 's/RELEASE_BUILD: \${{ steps.release.outputs.build }}/RELEASE_BUILD: 0/' "$WORKFLOW" > "$FIXTURE/hardcoded-build.yml"
expect_rejection 'hardcoded build' "$FIXTURE/hardcoded-build.yml"

sed 's/GITHUB_SHA/GITHUB_REF/g' "$WORKFLOW" > "$FIXTURE/wrong-commit.yml"
expect_rejection 'wrong source identity' "$FIXTURE/wrong-commit.yml"

sed '/^      - name: Verify candidate artifact integrity before upload$/,/^      - name: Upload ad-hoc candidate$/{
  s/^        if: github.event_name == '\''workflow_dispatch'\''$/        if: github.event_name == '\''pull_request'\''/
}' "$WORKFLOW" > "$FIXTURE/wrong-event.yml"
expect_rejection 'wrong event guard' "$FIXTURE/wrong-event.yml"

echo 'Ad-hoc pre-upload workflow gate fixtures passed'
