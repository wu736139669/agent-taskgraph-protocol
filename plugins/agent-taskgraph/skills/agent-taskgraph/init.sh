#!/usr/bin/env bash
# Initialize optional durable Agent TaskGraph state without overwriting existing files.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET="."
TARGET_SET=0
MIGRATE=0

usage() {
  cat <<'USAGE'
Usage: ./init.sh [--migrate] [project-directory]

  --migrate  Rename an existing .agent-queue directory to .agent-taskgraph.
             Refuses to run when both directories already exist.

Initialization is optional. Use it only for work that must survive multiple sessions
or needs an auditable task plan.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --migrate) MIGRATE=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [ "$TARGET_SET" -eq 1 ]; then
        echo "Choose only one project directory." >&2
        usage >&2
        exit 2
      fi
      TARGET="$1"
      TARGET_SET=1
      ;;
  esac
  shift
done

if [ ! -d "$TARGET" ]; then
  echo "Project directory does not exist: $TARGET" >&2
  exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"
INSTANCE="$TARGET/.agent-taskgraph"
LEGACY_INSTANCE="$TARGET/.agent-queue"

if [ "$MIGRATE" -eq 1 ]; then
  if [ -e "$INSTANCE" ] || [ -L "$INSTANCE" ]; then
    echo "Current state already exists: $INSTANCE" >&2
    exit 1
  fi
  if [ ! -d "$LEGACY_INSTANCE" ] || [ -L "$LEGACY_INSTANCE" ]; then
    echo "Legacy state directory does not exist: $LEGACY_INSTANCE" >&2
    exit 1
  fi
  mv "$LEGACY_INSTANCE" "$INSTANCE"
  printf 'migrate %s -> %s\n' "$LEGACY_INSTANCE" "$INSTANCE"
elif [ -e "$LEGACY_INSTANCE" ] || [ -L "$LEGACY_INSTANCE" ]; then
  echo "Legacy state found: $LEGACY_INSTANCE" >&2
  echo "Review it, then run: ./init.sh --migrate '$TARGET'" >&2
  exit 1
fi

install_if_missing() {
  local source="$1" destination="$2"
  if [ -e "$destination" ]; then
    printf 'keep   %s\n' "$destination"
  else
    cp "$source" "$destination"
    printf 'create %s\n' "$destination"
  fi
}

mkdir -p "$INSTANCE/tasks" "$INSTANCE/archive"
install_if_missing "$SRC/templates/PROJECT.md" "$INSTANCE/PROJECT.md"
install_if_missing "$SRC/templates/PLAN.md" "$INSTANCE/PLAN.md"
install_if_missing "$SRC/templates/TEAM.md" "$INSTANCE/TEAM.md"
install_if_missing "$SRC/templates/STATUS.md" "$INSTANCE/STATUS.md"
install_if_missing "$SRC/templates/DECISIONS.md" "$INSTANCE/DECISIONS.md"
install_if_missing "$SRC/templates/task.md" "$INSTANCE/tasks/TEMPLATE.md"
: > "$INSTANCE/tasks/.gitkeep"
: > "$INSTANCE/archive/.gitkeep"

echo
echo "Optional Agent TaskGraph state initialized at $INSTANCE"
echo "Existing files were preserved. Use native runtime tasks/messages for ordinary one-session work."
