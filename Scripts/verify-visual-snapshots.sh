#!/bin/bash
set -euo pipefail
export LC_ALL=C

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <suite> <log-file>" >&2
  exit 2
fi

suite="$1"
log_file="$2"

case "$suite" in
  DesktopGlassVisualSnapshotTests)
    marker="SCHNEEGLASS_VISUAL_SNAPSHOT_RESULT"
    ;;
  DesignSystemComponentVisualSnapshotTests)
    marker="SCHNEEGLASS_DESIGN_SYSTEM_SNAPSHOT_RESULT"
    ;;
  WorkspaceVisualSnapshotTests)
    marker="SCHNEEGLASS_WORKSPACE_SNAPSHOT_RESULT"
    ;;
  *)
    echo "unsupported visual snapshot suite: $suite" >&2
    exit 2
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
contract="$script_dir/visual-snapshot-contract.txt"
refs_dir="$repo_root/Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/$suite"
suffix=".macos-26-xcode-26-6.png"

[[ -f "$contract" ]] || { echo "visual snapshot contract not found: $contract" >&2; exit 1; }
[[ -f "$log_file" ]] || { echo "visual snapshot log not found: $log_file" >&2; exit 1; }
[[ -d "$refs_dir" ]] || { echo "visual snapshot reference directory not found: $refs_dir" >&2; exit 1; }

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/schneeglass-visual-contract.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

awk '
  !/^[A-Za-z0-9_]+\.[A-Za-z0-9_]+$/ {
    printf "invalid visual snapshot contract entry at line %d: %s\n", NR, $0 > "/dev/stderr"
    invalid = 1
  }
  { print }
  END { exit invalid }
' "$contract" > "$tmp_dir/manifest"

sort "$tmp_dir/manifest" > "$tmp_dir/manifest.sorted"
if ! cmp -s "$tmp_dir/manifest" "$tmp_dir/manifest.sorted"; then
  echo "visual snapshot contract must be sorted lexicographically" >&2
  diff -u "$tmp_dir/manifest.sorted" "$tmp_dir/manifest" >&2 || true
  exit 1
fi

uniq -d "$tmp_dir/manifest" > "$tmp_dir/manifest.duplicates"
if [[ -s "$tmp_dir/manifest.duplicates" ]]; then
  echo "visual snapshot contract contains duplicate entries:" >&2
  cat "$tmp_dir/manifest.duplicates" >&2
  exit 1
fi

awk -v prefix="$suite." 'index($0, prefix) == 1 { print }' "$tmp_dir/manifest" > "$tmp_dir/expected"
if [[ ! -s "$tmp_dir/expected" ]]; then
  echo "visual snapshot contract contains no entries for $suite" >&2
  exit 1
fi

: > "$tmp_dir/references"
found_reference=0
for path in "$refs_dir"/*.png; do
  [[ -e "$path" ]] || continue
  found_reference=1
  name="${path##*/}"
  case "$name" in
    *"$suffix")
      case_name="${name%"$suffix"}"
      case "$case_name" in
        ''|*[!A-Za-z0-9_]*)
          echo "invalid visual snapshot reference name: $name" >&2
          exit 1
          ;;
      esac
      printf '%s.%s\n' "$suite" "$case_name" >> "$tmp_dir/references"
      ;;
    *)
      echo "unexpected visual snapshot reference baseline: $name" >&2
      exit 1
      ;;
  esac
done

if [[ "$found_reference" -ne 1 ]]; then
  echo "no committed visual snapshot references found for $suite" >&2
  exit 1
fi

sort "$tmp_dir/references" > "$tmp_dir/references.sorted"
uniq -d "$tmp_dir/references.sorted" > "$tmp_dir/references.duplicates"
if [[ -s "$tmp_dir/references.duplicates" ]]; then
  echo "duplicate visual snapshot references detected:" >&2
  cat "$tmp_dir/references.duplicates" >&2
  exit 1
fi

awk -v marker="$marker" -v suite="$suite" '
  {
    prefix = marker " "
    position = index($0, prefix)
    if (position == 0) {
      next
    }

    value = substr($0, position + length(prefix))
    sub(/\r$/, "", value)
    sub(/\(\)$/, "", value)
    if (value !~ /^[A-Za-z0-9_]+$/) {
      printf "invalid visual snapshot result marker: %s\n", value > "/dev/stderr"
      invalid = 1
      next
    }

    print suite "." value
  }
  END { exit invalid }
' "$log_file" > "$tmp_dir/executed"

if [[ ! -s "$tmp_dir/executed" ]]; then
  echo "no visual snapshot result markers found for $suite" >&2
  exit 1
fi

sort "$tmp_dir/executed" > "$tmp_dir/executed.sorted"
uniq -d "$tmp_dir/executed.sorted" > "$tmp_dir/executed.duplicates"
if [[ -s "$tmp_dir/executed.duplicates" ]]; then
  echo "duplicate visual snapshot result markers detected:" >&2
  cat "$tmp_dir/executed.duplicates" >&2
  exit 1
fi

if ! cmp -s "$tmp_dir/expected" "$tmp_dir/references.sorted"; then
  echo "committed references do not match the visual snapshot contract for $suite" >&2
  diff -u "$tmp_dir/expected" "$tmp_dir/references.sorted" >&2 || true
  exit 1
fi

if ! cmp -s "$tmp_dir/expected" "$tmp_dir/executed.sorted"; then
  echo "executed cases do not match the visual snapshot contract for $suite" >&2
  diff -u "$tmp_dir/expected" "$tmp_dir/executed.sorted" >&2 || true
  exit 1
fi

case_count="$(wc -l < "$tmp_dir/expected" | tr -d '[:space:]')"
echo "Verified visual snapshot contract for $suite ($case_count cases)."
