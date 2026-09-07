#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail=0

tracked_sensitive_paths="$({ git ls-files | grep -Ei '(^|/)(\.env($|\.)|[^/]+\.(p8|p12|pem|key|mobileprovision|cer|crt|der))$' || true; } | grep -vE '(^|/)\.env\.example$' || true)"

if [[ -n "$tracked_sensitive_paths" ]]; then
  printf '%s\n' "$tracked_sensitive_paths"
  echo 'Public repository violation: credential-like file is tracked.' >&2
  fail=1
fi

secret_regex='-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'
secret_hits="$(git grep -nEI "$secret_regex" -- ':!Package.resolved' 2>/dev/null || true)"

if [[ -n "$secret_hits" ]]; then
  printf '%s\n' "$secret_hits"
  echo 'Public repository violation: high-confidence secret pattern detected.' >&2
  fail=1
fi

exit "$fail"
