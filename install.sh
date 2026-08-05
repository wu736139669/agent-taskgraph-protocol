#!/usr/bin/env bash
# Install this source tree as the Claude Code and Codex agent-queue skill.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DEST="$HOME/.claude/skills/agent-queue"
CODEX_DEST="$HOME/.codex/skills/agent-queue"
ACTION="install"
FORCE=0
ACTION_SET=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--force] | --status | --uninstall

  --force      Back up a conflicting install, then create the symlink.
  --status     Show the current Claude Code and Codex skill targets.
  --uninstall  Remove only symlinks that point to this source tree.
EOF
}

set_action() {
  local action="$1"
  if [ "$ACTION_SET" -eq 1 ]; then
    echo "Choose only one of --status and --uninstall." >&2
    usage >&2
    exit 2
  fi
  ACTION="$action"
  ACTION_SET=1
}

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --status) set_action "status" ;;
    --uninstall) set_action "uninstall" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$FORCE" -eq 1 ] && [ "$ACTION" != "install" ]; then
  echo "--force can only be used while installing." >&2
  exit 2
fi

describe() {
  local label="$1" dest="$2" target
  if [ -L "$dest" ]; then
    target="$(readlink "$dest")"
    if [ "$target" = "$SRC" ]; then
      printf '%s: installed (%s -> %s)\n' "$label" "$dest" "$target"
    else
      printf '%s: conflict (unrelated symlink: %s -> %s)\n' "$label" "$dest" "$target"
    fi
  elif [ -e "$dest" ]; then
    printf '%s: conflict (not a symlink): %s\n' "$label" "$dest"
  else
    printf '%s: not installed\n' "$label"
  fi
}

preflight() {
  local dest="$1"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$SRC" ]; then
    return 0
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$FORCE" -ne 1 ]; then
      echo "Refusing to replace existing path: $dest" >&2
      echo "Re-run with --force to move it to a timestamped backup." >&2
      return 1
    fi
  fi
}

install_one() {
  local label="$1" dest="$2" backup base suffix
  mkdir -p "$(dirname "$dest")"

  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$SRC" ]; then
    printf '%s: already installed at %s\n' "$label" "$dest"
    return 0
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    base="${dest}.backup-$(date +%Y%m%d%H%M%S)"
    backup="$base"
    suffix=1
    while [ -e "$backup" ] || [ -L "$backup" ]; do
      backup="${base}-${suffix}"
      suffix=$((suffix + 1))
    done
    mv "$dest" "$backup"
    printf '%s: backed up existing path to %s\n' "$label" "$backup"
  fi

  ln -s "$SRC" "$dest"
  printf '%s: %s -> %s\n' "$label" "$dest" "$SRC"
}

uninstall_one() {
  local label="$1" dest="$2"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$SRC" ]; then
    unlink "$dest"
    printf '%s: removed %s\n' "$label" "$dest"
  elif [ -e "$dest" ] || [ -L "$dest" ]; then
    printf '%s: skipped unrelated path %s\n' "$label" "$dest"
  else
    printf '%s: not installed\n' "$label"
  fi
}

case "$ACTION" in
  status)
    describe "Claude Code" "$CLAUDE_DEST"
    describe "Codex" "$CODEX_DEST"
    ;;
  uninstall)
    uninstall_one "Claude Code" "$CLAUDE_DEST"
    uninstall_one "Codex" "$CODEX_DEST"
    ;;
  install)
    preflight "$CLAUDE_DEST"
    preflight "$CODEX_DEST"
    install_one "Claude Code" "$CLAUDE_DEST"
    install_one "Codex" "$CODEX_DEST"
    echo
    echo "Installed. Start a new session and ask: use agent-queue for this project."
    ;;
esac
