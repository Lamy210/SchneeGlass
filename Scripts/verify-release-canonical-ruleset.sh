#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Canonical release ruleset verification failed: $*" >&2
  exit 1
}

[[ "$#" -ge 1 && "$#" -le 2 ]] \
  || fail "usage: $0 <canonical-recipe-json> [live-ruleset-json]"
RECIPE="$1"
LIVE="${2:-}"

command -v jq >/dev/null 2>&1 || fail "jq is required"
[[ -f "$RECIPE" ]] || fail "canonical recipe is missing: $RECIPE"
if [[ -n "$LIVE" ]]; then
  [[ -f "$LIVE" ]] || fail "live ruleset detail is missing: $LIVE"
fi

TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

EXPECTED="$TMP/expected.json"
OBSERVED="$TMP/observed.json"
BASELINE="$TMP/baseline.json"

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

CANONICAL_BASELINE_FILTER='
  {
    name: "SchneeGlass main release governance",
    target: "branch",
    enforcement: "active",
    conditions: {
      ref_name: {
        include: ["refs/heads/main"],
        exclude: []
      }
    },
    rules: (
      [
        {type: "deletion"},
        {type: "non_fast_forward"},
        {
          type: "pull_request",
          parameters: {
            allowed_merge_methods: ["merge", "rebase", "squash"],
            dismiss_stale_reviews_on_push: false,
            require_code_owner_review: false,
            require_last_push_approval: false,
            required_approving_review_count: 0,
            required_review_thread_resolution: true
          }
        },
        {
          type: "required_status_checks",
          parameters: {
            do_not_enforce_on_create: false,
            strict_required_status_checks_policy: true,
            required_status_checks: [
              {
                context: "Canonical / Xcode 26.6 / App Build / Safety Guards",
                integration_id: 15368
              },
              {
                context: "Compatibility / macOS 15 / App Build",
                integration_id: 15368
              }
            ]
          }
        }
      ]
      | sort_by(.type)
    )
  }
'

jq -e '
  type == "object" and
  has("bypass_actors") and
  (.bypass_actors | type == "array") and
  (.bypass_actors | length == 0) and
  (.rules | type == "array")
' "$RECIPE" >/dev/null \
  || fail "canonical recipe must be an object with an empty bypass_actors array and a rules array"

jq -S "$NORMALIZE_FILTER" "$RECIPE" > "$EXPECTED" \
  || fail "unable to normalize canonical recipe"

if [[ -z "$LIVE" ]]; then
  jq -n -S "$CANONICAL_BASELINE_FILTER" > "$BASELINE" \
    || fail "unable to build fixed canonical governance baseline"

  if ! cmp -s "$BASELINE" "$EXPECTED"; then
    echo 'Canonical ruleset recipe policy mismatch:' >&2
    diff -u "$BASELINE" "$EXPECTED" >&2 || true
    fail "canonical recipe does not match the fixed release governance baseline"
  fi

  echo "Canonical release ruleset recipe verified: $RECIPE"
  exit 0
fi

jq -e 'type == "object" and (.rules | type == "array")' "$LIVE" >/dev/null \
  || fail "live ruleset detail must be a JSON object with a rules array"

jq -S "$NORMALIZE_FILTER" "$LIVE" > "$OBSERVED" \
  || fail "unable to normalize live ruleset detail"

if ! cmp -s "$EXPECTED" "$OBSERVED"; then
  echo 'Canonical ruleset semantic mismatch:' >&2
  diff -u "$EXPECTED" "$OBSERVED" >&2 || true
  fail "live ruleset does not match the checked-in canonical recipe"
fi

echo "Canonical release ruleset detail verified: $LIVE"
