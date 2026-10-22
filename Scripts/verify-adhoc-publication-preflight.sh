#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Ad-hoc publication preflight failed: $*" >&2
  exit 1
}

[[ "$#" -eq 9 ]] || fail 'usage: verify-adhoc-publication-preflight.sh <run-id> <artifact-id> <version> <build> <source-sha> <owner-qa-comment-id> <downloaded-actions-zip> <new-candidate-dir> <new-history-dir>'

RUN_ID="$1"
ARTIFACT_ID="$2"
VERSION="$3"
BUILD="$4"
SOURCE_SHA="$5"
QA_COMMENT_ID="$6"
OUTER_ZIP="$7"
CANDIDATE_DIR="$8"
HISTORY_DIR="$9"
REPOSITORY='Lamy210/SchneeGlass'

[[ "$RUN_ID" =~ ^[1-9][0-9]*$ ]] || fail 'run ID must be positive decimal'
[[ "$ARTIFACT_ID" =~ ^[1-9][0-9]*$ ]] || fail 'artifact ID must be positive decimal'
[[ "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] || fail 'version must be strict X.Y.Z'
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || fail 'build must be positive decimal'
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail 'source SHA must be lowercase 40-hex'
[[ "$QA_COMMENT_ID" =~ ^[1-9][0-9]*$ ]] || fail 'QA comment ID must be positive decimal'
[[ -n "$OUTER_ZIP" && -n "$CANDIDATE_DIR" && -n "$HISTORY_DIR" ]] \
  || fail 'paths must not be empty'
[[ "$CANDIDATE_DIR" != "$HISTORY_DIR" ]] || fail 'candidate and history paths must differ'
[[ ! -e "$CANDIDATE_DIR" && ! -L "$CANDIDATE_DIR" ]] \
  || fail 'candidate destination must be new'
[[ ! -e "$HISTORY_DIR" && ! -L "$HISTORY_DIR" ]] \
  || fail 'history destination must be new'

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"

# Must fail closed with the repository's current unprotected main. Never
# weaken its required status checks or protection merely to permit ad-hoc.
bash "$ROOT/Scripts/verify-current-release-governance.sh" "$REPOSITORY" \
  || fail 'GitHub main governance is not ready'

# Authenticated run, exact artifact ID, downloaded outer ZIP digest, inner
# archive checksum and explicit, unedited repository-owner QA approval.
bash "$ROOT/Scripts/verify-adhoc-candidate-approval-chain.sh" \
  "$RUN_ID" "$ARTIFACT_ID" "$VERSION" "$BUILD" "$SOURCE_SHA" \
  "$QA_COMMENT_ID" "$OUTER_ZIP" "$CANDIDATE_DIR" \
  || fail 'authenticated run, archive or owner QA approval failed'

# Authenticated complete GitHub Release history; never use a supplied list.
bash "$ROOT/Scripts/materialize-authenticated-adhoc-release-history.sh" \
  "$HISTORY_DIR" \
  || fail 'full authenticated public Release history unavailable'

bash "$ROOT/Scripts/verify-adhoc-candidate-build-history.sh" \
  "$CANDIDATE_DIR" "$VERSION" "$BUILD" "$SOURCE_SHA" "$HISTORY_DIR/history" \
  || fail 'candidate build does not exceed the verified public history'

bash "$ROOT/Scripts/verify-adhoc-release-slot.sh" "v$VERSION" \
  || fail 'GitHub Release tag is occupied or cannot be checked'

# These final checks narrow, but cannot eliminate, a publication-time race.
bash "$ROOT/Scripts/verify-current-release-governance.sh" "$REPOSITORY" \
  || fail 'GitHub main governance changed during preflight'

ARTIFACT_REPORT="$(bash "$ROOT/Scripts/verify-adhoc-run-artifact-from-github.sh" \
  "$RUN_ID" "$VERSION" "$SOURCE_SHA")" \
  || fail 'candidate run, artifact or live main changed during preflight'
[[ "$(printf '%s\n' "$ARTIFACT_REPORT" | wc -l | tr -d ' ')" == '2' ]] \
  || fail 'malformed final artifact identity'
ID_LINE="$(printf '%s\n' "$ARTIFACT_REPORT" | sed -n '1p')"
DIGEST_LINE="$(printf '%s\n' "$ARTIFACT_REPORT" | sed -n '2p')"
[[ "$ID_LINE" == "artifact_id=$ARTIFACT_ID" ]] \
  || fail 'artifact ID changed during preflight'

command -v shasum >/dev/null 2>&1 || fail 'shasum is required'
OUTER_DIGEST="$(shasum -a 256 "$OUTER_ZIP" | awk '{print $1}')" \
  || fail 'unable to compute downloaded outer ZIP checksum'
[[ "$OUTER_DIGEST" =~ ^[0-9a-f]{64}$ ]] || fail 'malformed downloaded ZIP SHA-256'
[[ "$DIGEST_LINE" == "artifact_digest=sha256:$OUTER_DIGEST" ]] \
  || fail 'outer Actions ZIP digest changed during preflight'

echo "Ad-hoc read-only preflight passed (NOT publication authorization): run=$RUN_ID artifact=$ARTIFACT_ID source=$SOURCE_SHA version=$VERSION build=$BUILD"
