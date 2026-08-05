#!/usr/bin/env bash
# Initialize an agent-queue instance inside a target project without overwriting state.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-.}"

if [ "$#" -gt 1 ]; then
  echo "Usage: ./init.sh [project-directory]" >&2
  exit 2
fi

if [ "$TARGET" = "-h" ] || [ "$TARGET" = "--help" ]; then
  echo "Usage: ./init.sh [project-directory]"
  exit 0
fi

if [ ! -d "$TARGET" ]; then
  echo "Project directory does not exist: $TARGET" >&2
  exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"
INSTANCE="$TARGET/.agent-queue"

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
  "$INSTANCE/queue/inbox" \
  "$INSTANCE/queue/active" \
  "$INSTANCE/queue/review" \
  "$INSTANCE/queue/done" \
  "$INSTANCE/queue/failed" \
  "$INSTANCE/archive"

install_if_missing "$SRC/templates/PROJECT.md" "$INSTANCE/PROJECT.md"
install_if_missing "$SRC/templates/STATUS.md" "$INSTANCE/STATUS.md"
install_if_missing "$SRC/templates/DECISIONS.md" "$INSTANCE/DECISIONS.md"

for name in spec.md graph.yaml goal.md ledger.md report.md; do
  install_if_missing "$SRC/templates/$name" "$INSTANCE/templates/$name"
done

for state in inbox active review done failed; do
  touch_if_missing "$INSTANCE/queue/$state/.gitkeep"
done
touch_if_missing "$INSTANCE/archive/.gitkeep"

echo
echo "agent-queue initialized at $INSTANCE"
echo "Existing files were preserved. Ask the agent to analyze the project and fill PROJECT.md."
