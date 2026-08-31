#!/usr/bin/env bash
# Check the configured Git remote without changing the working tree or merging commits.
set -u

ROOT="${AGENT_TASKGRAPH_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REMOTE="${AGENT_TASKGRAPH_UPDATE_REMOTE:-origin}"
BRANCH="${AGENT_TASKGRAPH_UPDATE_BRANCH:-}"
QUIET=0

usage() {
  cat <<'EOF'
Usage: ./scripts/check-update.sh [--quiet]

  --quiet  Print only actionable update or divergence notices.

The check fetches remote commit metadata but never pulls, merges, or edits working files.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet)
      QUIET=1
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
  shift
done

VERSION_FILE="$ROOT/VERSION"
if [ -f "$VERSION_FILE" ]; then
  CURRENT_VERSION="$(tr -d '\r\n' < "$VERSION_FILE")"
else
  CURRENT_VERSION="unknown"
fi

print_header() {
  if [ "$QUIET" -eq 0 ]; then
    printf 'Agent TaskGraph version: %s\n' "$CURRENT_VERSION"
  fi
}

unavailable() {
  print_header
  if [ "$QUIET" -eq 0 ]; then
    printf 'Update status: unavailable (%s)\n' "$1"
  fi
  exit 0
}

if [ "${AGENT_TASKGRAPH_SKIP_UPDATE_CHECK:-0}" = "1" ]; then
  unavailable "disabled by AGENT_TASKGRAPH_SKIP_UPDATE_CHECK=1"
fi

command -v git >/dev/null 2>&1 || unavailable "Git is not installed"
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || unavailable "source is not a Git checkout"

LOCAL_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" \
  || unavailable "local commit cannot be resolved"

if [ -z "$BRANCH" ]; then
  UPSTREAM="$(git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [ -n "$UPSTREAM" ] && [ "$UPSTREAM" != '@{upstream}' ]; then
    REMOTE="${UPSTREAM%%/*}"
    BRANCH="${UPSTREAM#*/}"
  else
    BRANCH="$(git -C "$ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  fi
fi

[ -n "$BRANCH" ] || unavailable "detached HEAD has no configured update branch"
git -C "$ROOT" remote get-url "$REMOTE" >/dev/null 2>&1 \
  || unavailable "remote '$REMOTE' is not configured"

if ! GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" \
  git -C "$ROOT" fetch --quiet --no-tags "$REMOTE" "$BRANCH"; then
  unavailable "remote '$REMOTE/$BRANCH' could not be fetched"
fi

REMOTE_SHA="$(git -C "$ROOT" rev-parse FETCH_HEAD 2>/dev/null)" \
  || unavailable "fetched commit cannot be resolved"

print_header
if [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
  if [ "$QUIET" -eq 0 ]; then
    printf 'Update status: current (%s/%s)\n' "$REMOTE" "$BRANCH"
  fi
elif git -C "$ROOT" merge-base --is-ancestor "$LOCAL_SHA" "$REMOTE_SHA"; then
  printf 'Update available: %s -> %s (%s/%s)\n' \
    "${LOCAL_SHA:0:12}" "${REMOTE_SHA:0:12}" "$REMOTE" "$BRANCH"
  printf "Run: git -C '%s' pull --ff-only\n" "$ROOT"
elif git -C "$ROOT" merge-base --is-ancestor "$REMOTE_SHA" "$LOCAL_SHA"; then
  if [ "$QUIET" -eq 0 ]; then
    printf 'Update status: local checkout is ahead of %s/%s\n' "$REMOTE" "$BRANCH"
  fi
else
  printf 'Update warning: local checkout has diverged from %s/%s\n' "$REMOTE" "$BRANCH"
  printf "Inspect: git -C '%s' status --short --branch\n" "$ROOT"
fi
