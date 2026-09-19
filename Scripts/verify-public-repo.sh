#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

die() {
  echo "Public repository verification failed: $*" >&2
  exit 1
}

violations=0

if ! TRACKED_FILES="$(git ls-files)"; then
  die "unable to enumerate tracked repository files"
fi

sensitive_path_regex='(^|/)(\.env($|\.)|[^/]+\.(p8|p12|pem|key|mobileprovision|cer|crt|der))$'

set +e
SENSITIVE_CANDIDATES="$(printf '%s\n' "$TRACKED_FILES" | grep -Ei "$sensitive_path_regex")"
SENSITIVE_FILTER_STATUS=$?
set -e

case "$SENSITIVE_FILTER_STATUS" in
  0)
    ;;
  1)
    SENSITIVE_CANDIDATES=''
    ;;
  *)
    die "unable to filter tracked repository files for credential-like paths"
    ;;
esac

tracked_sensitive_paths=''
if [[ -n "$SENSITIVE_CANDIDATES" ]]; then
  set +e
  tracked_sensitive_paths="$(printf '%s\n' "$SENSITIVE_CANDIDATES" | grep -vE '(^|/)\.env\.example$')"
  EXEMPTION_FILTER_STATUS=$?
  set -e

  case "$EXEMPTION_FILTER_STATUS" in
    0)
      ;;
    1)
      tracked_sensitive_paths=''
      ;;
    *)
      die "unable to apply public repository path exemptions"
      ;;
  esac
fi

if [[ -n "$tracked_sensitive_paths" ]]; then
  printf '%s\n' "$tracked_sensitive_paths"
  echo 'Public repository violation: credential-like file is tracked.' >&2
  violations=1
fi

secret_regex='-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'

set +e
secret_hits="$(git grep -nEI "$secret_regex" -- ':!Package.resolved')"
SECRET_SCAN_STATUS=$?
set -e

case "$SECRET_SCAN_STATUS" in
  0)
    ;;
  1)
    secret_hits=''
    ;;
  *)
    die "unable to scan repository content for secret patterns"
    ;;
esac

if [[ -n "$secret_hits" ]]; then
  printf '%s\n' "$secret_hits"
  echo 'Public repository violation: high-confidence secret pattern detected.' >&2
  violations=1
fi

exit "$violations"
