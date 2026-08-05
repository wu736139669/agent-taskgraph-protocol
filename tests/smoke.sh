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
assert_link_to() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ] || fail "unexpected symlink: $1"; }

echo "[1/6] shell and Python syntax"
bash -n "$ROOT/install.sh" "$ROOT/init.sh" "$ROOT/workers/watch-worker.sh" "$ROOT/workers/log-cleanup.sh" "$ROOT/tests/smoke.sh"
python3 - "$ROOT/workers/parse-worker-log.py" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
compile(source, sys.argv[1], "exec")
PY

echo "[2/6] Codex log parser fixtures"
python3 "$ROOT/workers/parse-worker-log.py" --format jsonl \
  < "$ROOT/tests/fixtures/codex-events.jsonl" > "$TMP/parser.out"
diff -u "$ROOT/tests/fixtures/codex-events.expected" "$TMP/parser.out"

echo "[3/6] install, status, conflict, force, and uninstall"
HOME="$TMP/home-install" "$ROOT/install.sh" > "$TMP/install.out"
assert_link_to "$TMP/home-install/.claude/skills/agent-taskgraph" "$ROOT"
assert_link_to "$TMP/home-install/.codex/skills/agent-taskgraph" "$ROOT"
HOME="$TMP/home-install" "$ROOT/install.sh" --status > "$TMP/status.out"
grep -q "$ROOT" "$TMP/status.out"
HOME="$TMP/home-install" "$ROOT/install.sh" --uninstall > "$TMP/uninstall.out"
[ ! -e "$TMP/home-install/.claude/skills/agent-taskgraph" ] || fail "Claude link was not removed"
[ ! -e "$TMP/home-install/.codex/skills/agent-taskgraph" ] || fail "Codex link was not removed"

mkdir -p "$TMP/home-legacy-owned/.claude/skills" "$TMP/home-legacy-owned/.codex/skills"
ln -s "$ROOT" "$TMP/home-legacy-owned/.claude/skills/agent-queue"
ln -s "$ROOT" "$TMP/home-legacy-owned/.codex/skills/agent-queue"
HOME="$TMP/home-legacy-owned" "$ROOT/install.sh" --status > "$TMP/legacy-status.out"
grep -q 'migration pending' "$TMP/legacy-status.out"
HOME="$TMP/home-legacy-owned" "$ROOT/install.sh" > "$TMP/legacy-install.out"
assert_link_to "$TMP/home-legacy-owned/.claude/skills/agent-taskgraph" "$ROOT"
assert_link_to "$TMP/home-legacy-owned/.codex/skills/agent-taskgraph" "$ROOT"
[ ! -e "$TMP/home-legacy-owned/.claude/skills/agent-queue" ] || fail "owned Claude legacy link was not removed"
[ ! -e "$TMP/home-legacy-owned/.codex/skills/agent-queue" ] || fail "owned Codex legacy link was not removed"

mkdir -p "$TMP/unrelated-skill" \
  "$TMP/home-legacy-unrelated/.claude/skills/agent-queue" \
  "$TMP/home-legacy-unrelated/.codex/skills"
echo keep > "$TMP/home-legacy-unrelated/.claude/skills/agent-queue/marker"
ln -s "$TMP/unrelated-skill" "$TMP/home-legacy-unrelated/.codex/skills/agent-queue"
HOME="$TMP/home-legacy-unrelated" "$ROOT/install.sh" > "$TMP/unrelated-install.out"
assert_file "$TMP/home-legacy-unrelated/.claude/skills/agent-queue/marker"
assert_link_to "$TMP/home-legacy-unrelated/.codex/skills/agent-queue" "$TMP/unrelated-skill"

mkdir -p "$TMP/home-conflict/.claude/skills/agent-taskgraph" "$TMP/home-conflict/.codex/skills/agent-taskgraph"
echo keep > "$TMP/home-conflict/.claude/skills/agent-taskgraph/marker"
if HOME="$TMP/home-conflict" "$ROOT/install.sh" > "$TMP/conflict.out" 2>&1; then
  fail "install should refuse existing directories"
fi
assert_file "$TMP/home-conflict/.claude/skills/agent-taskgraph/marker"
HOME="$TMP/home-conflict" "$ROOT/install.sh" --force > "$TMP/force.out"
assert_link_to "$TMP/home-conflict/.claude/skills/agent-taskgraph" "$ROOT"
find "$TMP/home-conflict/.claude/skills" -maxdepth 1 -name 'agent-taskgraph.backup-*' -type d \
  > "$TMP/backups.out"
[ -s "$TMP/backups.out" ] || fail "forced install did not create a backup"

echo "[4/6] project initialization preserves existing files"
mkdir -p "$TMP/project"
"$ROOT/init.sh" "$TMP/project" > "$TMP/init.out"
for state in inbox active review done failed; do
  assert_dir "$TMP/project/.agent-taskgraph/queue/$state"
done
assert_file "$TMP/project/.agent-taskgraph/PROJECT.md"
assert_file "$TMP/project/.agent-taskgraph/templates/spec.md"
assert_file "$TMP/project/.agent-taskgraph/templates/graph.yaml"
echo sentinel > "$TMP/project/.agent-taskgraph/PROJECT.md"
"$ROOT/init.sh" "$TMP/project" > "$TMP/reinit.out"
grep -qx sentinel "$TMP/project/.agent-taskgraph/PROJECT.md" || fail "init overwrote PROJECT.md"

mkdir -p "$TMP/project-legacy/.agent-queue/queue/active"
echo legacy-sentinel > "$TMP/project-legacy/.agent-queue/PROJECT.md"
echo active-sentinel > "$TMP/project-legacy/.agent-queue/queue/active/task-1"
if "$ROOT/init.sh" "$TMP/project-legacy" > "$TMP/legacy-init-refusal.out" 2>&1; then
  fail "init should require --migrate for legacy state"
fi
assert_file "$TMP/project-legacy/.agent-queue/PROJECT.md"
[ ! -e "$TMP/project-legacy/.agent-taskgraph" ] || fail "legacy state moved without --migrate"
"$ROOT/init.sh" --migrate "$TMP/project-legacy" > "$TMP/legacy-migrate.out"
[ ! -e "$TMP/project-legacy/.agent-queue" ] || fail "legacy state remained after migration"
grep -qx legacy-sentinel "$TMP/project-legacy/.agent-taskgraph/PROJECT.md" || fail "migration overwrote PROJECT.md"
grep -qx active-sentinel "$TMP/project-legacy/.agent-taskgraph/queue/active/task-1" || fail "migration lost active state"
assert_file "$TMP/project-legacy/.agent-taskgraph/templates/spec.md"

mkdir -p "$TMP/project-both/.agent-queue" "$TMP/project-both/.agent-taskgraph"
if "$ROOT/init.sh" --migrate "$TMP/project-both" > "$TMP/both-state-refusal.out" 2>&1; then
  fail "init should refuse coexisting legacy and current state"
fi
assert_dir "$TMP/project-both/.agent-queue"
assert_dir "$TMP/project-both/.agent-taskgraph"

echo "[5/6] cleanup is dry-run and archived-only by default"
mkdir -p "$TMP/home-logs/.codex/archived_sessions" "$TMP/home-logs/.codex/sessions" "$TMP/home-logs/.hapi/logs"
touch "$TMP/home-logs/.codex/archived_sessions/old.jsonl" \
  "$TMP/home-logs/.codex/sessions/live.jsonl" "$TMP/home-logs/.hapi/logs/live.log"
touch -t 202001010000 "$TMP/home-logs/.codex/archived_sessions/old.jsonl" \
  "$TMP/home-logs/.codex/sessions/live.jsonl" "$TMP/home-logs/.hapi/logs/live.log"
HOME="$TMP/home-logs" "$ROOT/workers/log-cleanup.sh" --days 1 > "$TMP/cleanup-dry.out"
grep -q 'old.jsonl' "$TMP/cleanup-dry.out"
[ -f "$TMP/home-logs/.codex/archived_sessions/old.jsonl" ] || fail "dry-run deleted a file"
if grep -q 'live.jsonl\|live.log' "$TMP/cleanup-dry.out"; then
  fail "default cleanup inspected live logs"
fi
HOME="$TMP/home-logs" "$ROOT/workers/log-cleanup.sh" --days 1 --apply > "$TMP/cleanup-apply.out"
[ ! -e "$TMP/home-logs/.codex/archived_sessions/old.jsonl" ] || fail "archived log was not deleted"
assert_file "$TMP/home-logs/.codex/sessions/live.jsonl"
assert_file "$TMP/home-logs/.hapi/logs/live.log"
chmod 500 "$TMP/home-logs/.codex/sessions"
if HOME="$TMP/home-logs" "$ROOT/workers/log-cleanup.sh" --days 1 --include-live --apply \
  > "$TMP/cleanup-failure.out" 2>&1; then
  fail "cleanup reported success after a deletion failure"
fi
assert_file "$TMP/home-logs/.codex/sessions/live.jsonl"
chmod 700 "$TMP/home-logs/.codex/sessions"
HOME="$TMP/home-logs" "$ROOT/workers/log-cleanup.sh" --days 1 --include-live --apply \
  > "$TMP/cleanup-live.out"
[ ! -e "$TMP/home-logs/.codex/sessions/live.jsonl" ] || fail "explicit live cleanup missed Codex log"
[ ! -e "$TMP/home-logs/.hapi/logs/live.log" ] || fail "explicit live cleanup missed HAPI log"

echo "[6/6] skill metadata, templates, links, and graph YAML"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
skill = (root / "SKILL.md").read_text()
assert skill.startswith("---\nname: agent-taskgraph\n")
assert "description:" in skill.split("---", 2)[1]
for phrase in ("一句话足以发起需求", "spec.md", "graph.yaml", "Human Gate"):
    assert phrase in skill, phrase

for readme_name in ("README.md", "README.zh-CN.md"):
    readme = (root / readme_name).read_text()
    for target in re.findall(r"\[[^]]+\]\(([^)]+)\)", readme):
        if target.startswith(("http://", "https://", "#")):
            continue
        assert (root / target).exists(), f"broken link in {readme_name}: {target}"
PY

if command -v ruby >/dev/null 2>&1; then
  ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$ROOT/templates/graph.yaml"
  ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$ROOT/agents/openai.yaml"
fi
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" diff --check
fi

echo "All smoke tests passed."
