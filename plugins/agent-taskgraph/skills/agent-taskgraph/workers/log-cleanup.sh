#!/usr/bin/env bash
# Preview or delete old session logs. Archived Codex sessions are the safe default scope.
set -euo pipefail

APPLY=0
INCLUDE_LIVE=0
DAYS=30

usage() {
  cat <<'EOF'
Usage: ./workers/log-cleanup.sh [--apply] [--days N] [--include-live]

  --apply         Delete the listed files. The default is dry-run.
  --days N        Select files older than N days (default: 30).
  --include-live  Also inspect Codex sessions/ and HAPI logs/.

By default only ~/.codex/archived_sessions/*.jsonl is inspected. Preserve any
logs referenced by task evidence before applying cleanup.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --include-live)
      INCLUDE_LIVE=1
      shift
      ;;
    --days)
      [ "$#" -ge 2 ] || { echo "--days requires a value" >&2; exit 2; }
      DAYS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$DAYS" in
  ''|*[!0-9]*) echo "--days must be a non-negative integer" >&2; exit 2 ;;
esac

CANDIDATES="$(mktemp)"
trap 'rm -f "$CANDIDATES"' EXIT

process_directory() {
  local label="$1" directory="$2" pattern="$3" found=0 file
  printf '\n== %s (older than %s days) ==\n' "$label" "$DAYS"
  if [ ! -d "$directory" ]; then
    echo "not found: $directory"
    return 0
  fi

  : > "$CANDIDATES"
  if ! find "$directory" -type f -name "$pattern" -mtime "+$DAYS" -print0 > "$CANDIDATES"; then
    echo "Failed to inspect: $directory" >&2
    return 1
  fi

  while IFS= read -r -d '' file; do
    found=1
    printf '%s\n' "$file"
    if [ "$APPLY" -eq 1 ]; then
      rm -- "$file"
    fi
  done < "$CANDIDATES"

  [ "$found" -eq 1 ] || echo "no candidates"
}

if [ "$APPLY" -eq 1 ]; then
  echo "mode: apply"
else
  echo "mode: dry-run (no files will be deleted)"
fi
echo "scope: archived Codex sessions$( [ "$INCLUDE_LIVE" -eq 1 ] && printf ' + live Codex/HAPI logs' )"

process_directory "Codex archived sessions" "$HOME/.codex/archived_sessions" "*.jsonl"

if [ "$INCLUDE_LIVE" -eq 1 ]; then
  process_directory "Codex live sessions" "$HOME/.codex/sessions" "*.jsonl"
  process_directory "HAPI logs" "$HOME/.hapi/logs" "*.log"
fi

if [ "$APPLY" -eq 1 ]; then
  echo "Cleanup completed."
else
  echo "Dry-run completed. Re-run with --apply after reviewing every path."
fi
