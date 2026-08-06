#!/usr/bin/env bash
# Initialize an agent-taskgraph instance inside a target project without overwriting state.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET="."
TARGET_SET=0
MIGRATE=0

usage() {
  cat <<'EOF'
Usage: ./init.sh [--migrate] [project-directory]

  --migrate  Rename an existing .agent-queue instance to .agent-taskgraph.
             Refuses to run when both directories already exist.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --migrate)
      MIGRATE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
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

if [ -e "$LEGACY_INSTANCE" ] || [ -L "$LEGACY_INSTANCE" ]; then
  if [ -e "$INSTANCE" ] || [ -L "$INSTANCE" ]; then
    echo "Both legacy and current state directories exist:" >&2
    echo "  $LEGACY_INSTANCE" >&2
    echo "  $INSTANCE" >&2
    echo "Reconcile them manually before running init again." >&2
    exit 1
  fi
  if [ "$MIGRATE" -ne 1 ]; then
    echo "Legacy Agent Queue state found: $LEGACY_INSTANCE" >&2
    echo "Review it, then run: ./init.sh --migrate '$TARGET'" >&2
    exit 1
  fi
  if [ -L "$LEGACY_INSTANCE" ] || [ ! -d "$LEGACY_INSTANCE" ]; then
    echo "Legacy state path is not a directory: $LEGACY_INSTANCE" >&2
    exit 1
  fi
  mv "$LEGACY_INSTANCE" "$INSTANCE"
  printf 'migrate %s -> %s\n' "$LEGACY_INSTANCE" "$INSTANCE"
elif [ "$MIGRATE" -eq 1 ]; then
  echo "No legacy .agent-queue directory found; initializing current state."
fi

install_if_missing() {
  local source="$1" destination="$2"
  if [ -e "$destination" ]; then
    printf 'keep  %s\n' "$destination"
  else
    cp "$source" "$destination"
    printf 'create %s\n' "$destination"
  fi
}

touch_if_missing() {
  local destination="$1"
  if [ ! -e "$destination" ]; then
    : > "$destination"
  fi
}

mkdir -p \
  "$INSTANCE/templates" \
  "$INSTANCE/roles" \
  "$INSTANCE/staffing" \
  "$INSTANCE/queue/inbox" \
  "$INSTANCE/queue/active" \
  "$INSTANCE/queue/review" \
  "$INSTANCE/queue/done" \
  "$INSTANCE/queue/failed" \
  "$INSTANCE/archive"

install_if_missing "$SRC/templates/PROJECT.md" "$INSTANCE/PROJECT.md"
install_if_missing "$SRC/templates/STATUS.md" "$INSTANCE/STATUS.md"
install_if_missing "$SRC/templates/DECISIONS.md" "$INSTANCE/DECISIONS.md"
install_if_missing "$SRC/templates/ROLES.md" "$INSTANCE/ROLES.md"

for name in spec.md graph.yaml goal.md ledger.md report.md role.md context.md staffing-change.md; do
  install_if_missing "$SRC/templates/$name" "$INSTANCE/templates/$name"
done

for state in inbox active review done failed; do
  touch_if_missing "$INSTANCE/queue/$state/.gitkeep"
done
touch_if_missing "$INSTANCE/archive/.gitkeep"

echo
echo "agent-taskgraph initialized at $INSTANCE"
echo "Existing files were preserved. Ask the agent to analyze the project and fill PROJECT.md."
