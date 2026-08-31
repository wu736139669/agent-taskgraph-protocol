#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() { [ -f "$1" ] || fail "missing file: $1"; }
assert_dir() { [ -d "$1" ] || fail "missing directory: $1"; }
assert_not_exists() { [ ! -e "$1" ] && [ ! -L "$1" ] || fail "unexpected path: $1"; }
assert_link_to() {
  [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ] || fail "unexpected symlink: $1"
}

VERSION="$(tr -d '\r\n' < "$ROOT/VERSION")"
[ "$VERSION" = "0.8.0-beta.19" ] || fail "unexpected VERSION: $VERSION"

echo "[1/8] shell and metadata syntax"
bash -n "$ROOT/install.sh" "$ROOT/init.sh" "$ROOT/scripts/check-update.sh" "$ROOT/tests/smoke.sh"
python3 - "$ROOT/scripts/check-docs.py" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY
python3 - "$ROOT" "$VERSION" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
version = sys.argv[2]
for path in (
    root / ".claude-plugin/marketplace.json",
    root / "plugins/agent-taskgraph/.claude-plugin/plugin.json",
    root / "plugins/agent-taskgraph/.codex-plugin/plugin.json",
):
    data = json.loads(path.read_text())
    if path.name == "marketplace.json":
        actual = data["plugins"][0]["version"]
    else:
        actual = data["version"]
    assert actual == version, (path, actual, version)

skill = (root / "SKILL.md").read_text()
assert skill.startswith("---\nname: agent-taskgraph\n")
assert "description:" in skill.split("---", 2)[1]
assert "references/native-runtimes.md" in skill
assert "references/team-protocol.md" in skill
assert "references/development-team-example.md" in skill
assert (root / "references/native-runtimes.md").is_file()
assert (root / "references/team-protocol.md").is_file()
assert (root / "references/development-team-example.md").is_file()
assert "<TODO>" not in skill
PY

echo "[2/8] native-only source inventory"
for path in \
  "$ROOT/references/dispatch-bootstrap.md" \
  "$ROOT/references/runtime-profiles.md" \
  "$ROOT/scripts/open-worker-terminal.sh" \
  "$ROOT/scripts/prepare-task.py" \
  "$ROOT/scripts/render-dispatch.py" \
  "$ROOT/scripts/validate-graph.py" \
  "$ROOT/scripts/validate-state.py" \
  "$ROOT/workers" \
  "$ROOT/queue"; do
  assert_not_exists "$path"
done

EXTERNAL_RUNTIME_TERM="$(printf '\150\141\160\151')"
if find "$ROOT" -path "$ROOT/.git" -prune -o -path "$ROOT/videos" -prune -o -type f -print0 \
  | xargs -0 grep -Iil "$EXTERNAL_RUNTIME_TERM" > "$TMP/external-runtime-files"; then
  cat "$TMP/external-runtime-files" >&2
  fail "external runtime references remain"
fi

grep -q '\*\*Solo\*\*' "$ROOT/SKILL.md"
grep -q '\*\*Delegation\*\*' "$ROOT/SKILL.md"
grep -q '\*\*Team\*\*' "$ROOT/SKILL.md"
grep -q '共同目标' "$ROOT/SKILL.md"
grep -q '角色' "$ROOT/SKILL.md"
grep -q '任务关系' "$ROOT/SKILL.md"
grep -q '协作协议' "$ROOT/SKILL.md"
grep -q '生命周期' "$ROOT/SKILL.md"
grep -q 'forming.*briefing.*executing.*reviewing.*integrating' "$ROOT/SKILL.md"
grep -q 'READY' "$ROOT/SKILL.md"
grep -q 'BLOCKED' "$ROOT/SKILL.md"
grep -q 'HANDOFF' "$ROOT/SKILL.md"
grep -q 'REVIEW' "$ROOT/SKILL.md"
grep -q '不保证恢复 Agent' "$ROOT/SKILL.md"
grep -q 'fork_turns' "$ROOT/SKILL.md"
grep -q 'worktree' "$ROOT/SKILL.md"
grep -q 'hub-and-spoke' "$ROOT/references/native-runtimes.md"
grep -q '可能成为 teammate' "$ROOT/references/native-runtimes.md"
grep -q 'Team Charter' "$ROOT/references/team-protocol.md"
grep -q 'Development Team' "$ROOT/references/team-protocol.md"
grep -q 'T1-contract' "$ROOT/references/development-team-example.md"

echo "[3/8] optional durable-state initialization"
mkdir -p "$TMP/project"
"$ROOT/init.sh" "$TMP/project" > "$TMP/init.out"
for name in PROJECT.md PLAN.md TEAM.md STATUS.md DECISIONS.md; do
  assert_file "$TMP/project/.agent-taskgraph/$name"
done
assert_file "$TMP/project/.agent-taskgraph/tasks/TEMPLATE.md"
assert_dir "$TMP/project/.agent-taskgraph/archive"
grep -q 'Team Charter' "$TMP/project/.agent-taskgraph/TEAM.md"
grep -q 'Protocol version' "$TMP/project/.agent-taskgraph/TEAM.md"
grep -q 'Updated at' "$TMP/project/.agent-taskgraph/TEAM.md"
grep -q 'Team Task Graph' "$TMP/project/.agent-taskgraph/PLAN.md"
grep -q 'Lifecycle phase' "$TMP/project/.agent-taskgraph/STATUS.md"
grep -q 'Produces for' "$TMP/project/.agent-taskgraph/tasks/TEMPLATE.md"
printf 'user-owned\n' >> "$TMP/project/.agent-taskgraph/PROJECT.md"
"$ROOT/init.sh" "$TMP/project" > "$TMP/reinit.out"
grep -q 'user-owned' "$TMP/project/.agent-taskgraph/PROJECT.md"
grep -q 'keep' "$TMP/reinit.out"
if "$ROOT/init.sh" --legacy-queue "$TMP/project" > /dev/null 2>&1; then
  fail "removed --legacy-queue option still succeeds"
fi

mkdir -p "$TMP/migrate/.agent-queue"
printf 'legacy-data\n' > "$TMP/migrate/.agent-queue/keep.txt"
"$ROOT/init.sh" --migrate "$TMP/migrate" > "$TMP/migrate.out"
assert_file "$TMP/migrate/.agent-taskgraph/keep.txt"
assert_file "$TMP/migrate/.agent-taskgraph/PLAN.md"
assert_not_exists "$TMP/migrate/.agent-queue"

echo "[4/8] installer lifecycle"
mkdir -p "$TMP/home"
HOME="$TMP/home" "$ROOT/install.sh" > "$TMP/install.out"
assert_link_to "$TMP/home/.codex/skills/agent-taskgraph" "$ROOT"
assert_link_to "$TMP/home/.claude/skills/agent-taskgraph" "$ROOT"
HOME="$TMP/home" "$ROOT/install.sh" --status > "$TMP/status.out"
grep -q "Version: $VERSION" "$TMP/status.out"
grep -q 'Codex: installed' "$TMP/status.out"
grep -q 'Claude Code: installed' "$TMP/status.out"
HOME="$TMP/home" "$ROOT/install.sh" --uninstall > "$TMP/uninstall.out"
assert_not_exists "$TMP/home/.codex/skills/agent-taskgraph"
assert_not_exists "$TMP/home/.claude/skills/agent-taskgraph"

mkdir -p "$TMP/conflict-home/.codex/skills/agent-taskgraph"
if HOME="$TMP/conflict-home" "$ROOT/install.sh" > "$TMP/conflict.out" 2>&1; then
  fail "installer replaced an unrelated directory without --force"
fi

echo "[5/8] read-only update checker"
git init --bare "$TMP/update-remote.git" >/dev/null
git init "$TMP/update-local" >/dev/null
git -C "$TMP/update-local" checkout -b main >/dev/null
git -C "$TMP/update-local" config user.name "Agent TaskGraph Tests"
git -C "$TMP/update-local" config user.email "tests@example.invalid"
cp "$ROOT/VERSION" "$TMP/update-local/VERSION"
echo initial > "$TMP/update-local/tracked.txt"
git -C "$TMP/update-local" add VERSION tracked.txt
git -C "$TMP/update-local" commit -m initial >/dev/null
git -C "$TMP/update-local" remote add origin "$TMP/update-remote.git"
git -C "$TMP/update-local" push -u origin main >/dev/null

AGENT_TASKGRAPH_ROOT="$TMP/update-local" "$ROOT/scripts/check-update.sh" > "$TMP/update-current.out"
grep -q "version: $VERSION" "$TMP/update-current.out"
grep -q 'Update status: current' "$TMP/update-current.out"
AGENT_TASKGRAPH_ROOT="$TMP/update-local" AGENT_TASKGRAPH_SKIP_UPDATE_CHECK=1 \
  "$ROOT/scripts/check-update.sh" > "$TMP/update-disabled.out"
grep -q 'disabled by AGENT_TASKGRAPH_SKIP_UPDATE_CHECK=1' "$TMP/update-disabled.out"

git clone --quiet --branch main "$TMP/update-remote.git" "$TMP/update-publisher"
git -C "$TMP/update-publisher" config user.name "Agent TaskGraph Tests"
git -C "$TMP/update-publisher" config user.email "tests@example.invalid"
echo remote-update >> "$TMP/update-publisher/tracked.txt"
git -C "$TMP/update-publisher" add tracked.txt
git -C "$TMP/update-publisher" commit -m update >/dev/null
git -C "$TMP/update-publisher" push origin main >/dev/null
AGENT_TASKGRAPH_ROOT="$TMP/update-local" "$ROOT/scripts/check-update.sh" --quiet > "$TMP/update-available.out"
grep -q 'Update available:' "$TMP/update-available.out"
grep -q 'pull --ff-only' "$TMP/update-available.out"

echo "[6/8] plugin mirror consistency"
PLUGIN="$ROOT/plugins/agent-taskgraph/skills/agent-taskgraph"
for pair in \
  "SKILL.md:SKILL.md" \
  "VERSION:VERSION" \
  "init.sh:init.sh" \
  "agents/openai.yaml:agents/openai.yaml" \
  "references/native-runtimes.md:references/native-runtimes.md" \
  "references/team-protocol.md:references/team-protocol.md" \
  "references/development-team-example.md:references/development-team-example.md" \
  "scripts/check-update.sh:scripts/check-update.sh" \
  "templates/PROJECT.md:templates/PROJECT.md" \
  "templates/PLAN.md:templates/PLAN.md" \
  "templates/TEAM.md:templates/TEAM.md" \
  "templates/STATUS.md:templates/STATUS.md" \
  "templates/DECISIONS.md:templates/DECISIONS.md" \
  "templates/task.md:templates/task.md"; do
  source_path="${pair%%:*}"
  plugin_path="${pair#*:}"
  cmp "$ROOT/$source_path" "$PLUGIN/$plugin_path" || fail "plugin mirror drift: $source_path"
done

EXPECTED_PLUGIN_FILES="$(cat <<'FILES'
SKILL.md
VERSION
agents/openai.yaml
init.sh
references/development-team-example.md
references/native-runtimes.md
references/team-protocol.md
scripts/check-update.sh
templates/DECISIONS.md
templates/PLAN.md
templates/PROJECT.md
templates/STATUS.md
templates/TEAM.md
templates/task.md
FILES
)"
ACTUAL_PLUGIN_FILES="$(cd "$PLUGIN" && find . -type f | sed 's#^./##' | sort)"
[ "$ACTUAL_PLUGIN_FILES" = "$EXPECTED_PLUGIN_FILES" ] || {
  printf 'expected plugin files:\n%s\nactual plugin files:\n%s\n' "$EXPECTED_PLUGIN_FILES" "$ACTUAL_PLUGIN_FILES" >&2
  fail "unexpected plugin payload"
}

echo "[7/8] documentation and package version consistency"
python3 "$ROOT/scripts/check-docs.py"
grep -q "v$VERSION" "$ROOT/README.md"
grep -q "v$VERSION" "$ROOT/README.zh-CN.md"
grep -q "v$VERSION" "$ROOT/plugins/agent-taskgraph/README.md"
python3 - "$ROOT" <<'PY'
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
required = {
    "README.md": ["Start in 60 seconds", "Solo", "Delegation", "Team Charter", "Documentation map", "Agent Teams"],
    "README.zh-CN.md": ["60 秒开始", "Solo", "Delegation", "Team Charter", "文档导航", "Agent Teams"],
}
for name, phrases in required.items():
    text = (root / name).read_text()
    for phrase in phrases:
        assert phrase in text, (name, phrase)
PY

echo "[8/8] repository hygiene"
git -C "$ROOT" diff --check
[ -x "$ROOT/init.sh" ] || fail "init.sh is not executable"
[ -x "$ROOT/scripts/check-docs.py" ] || fail "check-docs.py is not executable"
[ -x "$ROOT/scripts/check-update.sh" ] || fail "check-update.sh is not executable"
[ -x "$ROOT/tests/smoke.sh" ] || fail "tests/smoke.sh is not executable"

echo "All smoke tests passed."
