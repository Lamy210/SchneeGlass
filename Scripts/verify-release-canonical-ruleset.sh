#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Canonical release ruleset verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 2 ]] || fail "usage: $0 <canonical-recipe-json> <live-ruleset-json>"
RECIPE="$1"
LIVE="$2"

command -v jq >/dev/null 2>&1 || fail "jq is required"
[[ -f "$RECIPE" ]] || fail "canonical recipe is missing: $RECIPE"
[[ -f "$LIVE" ]] || fail "live ruleset detail is missing: $LIVE"

TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

EXPECTED="$TMP/expected.json"
OBSERVED="$TMP/observed.json"

NORMALIZE_FILTER='
  def normalize_rule:
    if .type == "pull_request" then
      {
        type: .type,
        parameters: {
          allowed_merge_methods: ((.parameters.allowed_merge_methods // []) | sort),
          dismiss_stale_reviews_on_push: .parameters.dismiss_stale_reviews_on_push,
          require_code_owner_review: .parameters.require_code_owner_review,
          require_last_push_approval: .parameters.require_last_push_approval,
          required_approving_review_count: .parameters.required_approving_review_count,
          required_review_thread_resolution: .parameters.required_review_thread_resolution
        }
      }
    elif .type == "required_status_checks" then
      {
        type: .type,
        parameters: {
          do_not_enforce_on_create: .parameters.do_not_enforce_on_create,
          strict_required_status_checks_policy: .parameters.strict_required_status_checks_policy,
          required_status_checks: (
            (.parameters.required_status_checks // [])
            | map({
                context: .context,
                integration_id: .integration_id
              })
            | sort_by(.context, .integration_id)
          )
        }
      }
    else
      {type: .type}
    end;

  {
    name: .name,
    target: .target,
    enforcement: .enforcement,
    conditions: {
      ref_name: {
        include: ((.conditions.ref_name.include // []) | sort),
        exclude: ((.conditions.ref_name.exclude // []) | sort)
      }
    },
    rules: (
      (.rules // [])
      | map(normalize_rule)
      | sort_by(.type)
    )
  }
'

jq -e 'type == "object" and (.rules | type == "array")' "$RECIPE" >/dev/null   || fail "canonical recipe must be a JSON object with a rules array"
jq -e 'type == "object" and (.rules | type == "array")' "$LIVE" >/dev/null   || fail "live ruleset detail must be a JSON object with a rules array"

jq "$NORMALIZE_FILTER" "$RECIPE" > "$EXPECTED"   || fail "unable to normalize canonical recipe"
jq "$NORMALIZE_FILTER" "$LIVE" > "$OBSERVED"   || fail "unable to normalize live ruleset detail"

if ! cmp -s "$EXPECTED" "$OBSERVED"; then
  echo 'Canonical ruleset semantic mismatch:' >&2
  diff -u "$EXPECTED" "$OBSERVED" >&2 || true
  fail "live ruleset does not match the checked-in canonical recipe"
fi

echo "Canonical release ruleset detail verified: $LIVE"
