#!/usr/bin/env bash
set -euo pipefail

DETAILS="${1:-}"
GREP_BIN="${GREP_BIN:-grep}"

fail() {
  echo "Ad-hoc signature-details verification failed: $*" >&2
  exit 1
}

[[ -n "$DETAILS" && -f "$DETAILS" ]] || fail "codesign details file is required"
command -v "$GREP_BIN" >/dev/null 2>&1 || fail "grep command is unavailable"

probe_required() {
  local label="$1"
  shift
  local status=0

  set +e
  "$GREP_BIN" "$@" "$DETAILS" >/dev/null
  status=$?
  set -e

  case "$status" in
    0)
      ;;
    1)
      fail "$label is missing"
      ;;
    *)
      fail "unable to inspect $label (grep status $status)"
      ;;
  esac
}

probe_absent() {
  local label="$1"
  shift
  local status=0

  set +e
  "$GREP_BIN" "$@" "$DETAILS" >/dev/null
  status=$?
  set -e

  case "$status" in
    0)
      fail "$label is present"
      ;;
    1)
      ;;
    *)
      fail "unable to inspect $label (grep status $status)"
      ;;
  esac
}

probe_required 'ad-hoc signature marker' -Fx 'Signature=adhoc'
probe_absent 'certificate authority' -q '^Authority='
probe_required 'Hardened Runtime marker' -E 'flags=.*\\(([^,)]*,)*runtime(,[^,)]*)*\\)'
