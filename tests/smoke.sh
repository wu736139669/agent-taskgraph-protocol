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

echo "[1/11] shell and Python syntax"
bash -n "$ROOT/install.sh" "$ROOT/init.sh" "$ROOT/scripts/check-update.sh" \
  "$ROOT/scripts/open-worker-terminal.sh" "$ROOT/workers/watch-worker.sh" \
  "$ROOT/workers/log-cleanup.sh" "$ROOT/tests/smoke.sh"
python3 - "$ROOT/workers/parse-worker-log.py" \
  "$ROOT/scripts/validate-graph.py" "$ROOT/scripts/validate-state.py" <<'PY'
from pathlib import Path
import sys

for filename in sys.argv[1:]:
    source = Path(filename).read_text()
    compile(source, filename, "exec")
PY

echo "[2/11] Codex log parser fixtures"
python3 "$ROOT/workers/parse-worker-log.py" --format jsonl \
  < "$ROOT/tests/fixtures/codex-events.jsonl" > "$TMP/parser.out"
diff -u "$ROOT/tests/fixtures/codex-events.expected" "$TMP/parser.out"

echo "[3/11] update checker states"
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
grep -q 'version: 0.8.0-beta.3' "$TMP/update-current.out"
grep -q 'Update status: current' "$TMP/update-current.out"
AGENT_TASKGRAPH_ROOT="$TMP/update-local" "$ROOT/scripts/check-update.sh" --quiet > "$TMP/update-quiet-current.out"
[ ! -s "$TMP/update-quiet-current.out" ] || fail "quiet update check printed while current"
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
git -C "$TMP/update-local" pull --ff-only >/dev/null
AGENT_TASKGRAPH_ROOT="$TMP/update-local" "$ROOT/scripts/check-update.sh" > "$TMP/update-after-pull.out"
grep -q 'Update status: current' "$TMP/update-after-pull.out"

mkdir -p "$TMP/update-not-git"
cp "$ROOT/VERSION" "$TMP/update-not-git/VERSION"
AGENT_TASKGRAPH_ROOT="$TMP/update-not-git" "$ROOT/scripts/check-update.sh" > "$TMP/update-unavailable.out"
grep -q 'Update status: unavailable' "$TMP/update-unavailable.out"

echo "[4/11] install, status, conflict, force, and uninstall"
HOME="$TMP/home-install" "$ROOT/install.sh" > "$TMP/install.out"
assert_link_to "$TMP/home-install/.claude/skills/agent-taskgraph" "$ROOT"
assert_link_to "$TMP/home-install/.codex/skills/agent-taskgraph" "$ROOT"
HOME="$TMP/home-install" "$ROOT/install.sh" --status > "$TMP/status.out"
grep -q "$ROOT" "$TMP/status.out"
grep -q 'Version: 0.8.0-beta.3' "$TMP/status.out"
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

echo "[5/11] project initialization preserves existing files"
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

echo "[6/11] visible Terminal launcher dry-run and permission gates"
mkdir -p "$TMP/terminal-project/.agent-taskgraph/queue/inbox/T1-test"
echo '# Goal: launcher test' > "$TMP/terminal-project/.agent-taskgraph/queue/inbox/T1-test/goal.md"
AGENT_TASKGRAPH_TERMINAL_DIR="$TMP/terminal-runtime" \
  "$ROOT/scripts/open-worker-terminal.sh" --runtime claude \
  --project "$TMP/terminal-project" --name test-claude \
  --goal task:T1-test \
  --plugin-dir "$ROOT/plugins/agent-taskgraph" --model sonnet --effort high \
  --permission-mode plan --dry-run > "$TMP/terminal-claude.out"
grep -q '^runtime: claude$' "$TMP/terminal-claude.out"
grep -q '^goal-ref: task:T1-test$' "$TMP/terminal-claude.out"
grep -q 'command: claude .*--name test-claude .*--permission-mode plan' "$TMP/terminal-claude.out"
if sed -n '/^command:/p' "$TMP/terminal-claude.out" | grep -q 'queue/inbox'; then
  fail "stable Goal launch command embedded the inbox path"
fi
grep -q 'mode: dry-run (Terminal not opened)' "$TMP/terminal-claude.out"
[ ! -e "$TMP/terminal-runtime" ] || fail "launcher dry-run created runtime artifacts"

"$ROOT/scripts/open-worker-terminal.sh" --runtime codex \
  --project "$TMP/terminal-project" --name test-codex \
  --goal task:T1-test \
  --model gpt-test --effort high --permission-mode acceptEdits --dry-run \
  > "$TMP/terminal-codex.out"
grep -q '^runtime: codex$' "$TMP/terminal-codex.out"
grep -q 'command: codex .* -s workspace-write -a on-request' "$TMP/terminal-codex.out"

if "$ROOT/scripts/open-worker-terminal.sh" --runtime claude \
  --project "$TMP/terminal-project" --name test-danger \
  --goal task:T1-test \
  --permission-mode bypassPermissions --dry-run > "$TMP/terminal-danger.out" 2>&1; then
  fail "launcher allowed bypassPermissions without --allow-dangerous"
fi
grep -q 'requires the explicit --allow-dangerous flag' "$TMP/terminal-danger.out"

mkdir -p "$TMP/terminal-project/.agent-taskgraph/queue/active"
mv "$TMP/terminal-project/.agent-taskgraph/queue/inbox/T1-test" \
  "$TMP/terminal-project/.agent-taskgraph/queue/active/T1-test"

mkdir -p "$TMP/terminal-bin"
cat > "$TMP/terminal-bin/open" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = "-a" ] && [ "$2" = "Terminal" ]
bash "$3" >/dev/null 2>&1 &
SH
cat > "$TMP/terminal-bin/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exec sleep 30
SH
chmod +x "$TMP/terminal-bin/open" "$TMP/terminal-bin/claude"
PATH="$TMP/terminal-bin:$PATH" AGENT_TASKGRAPH_TERMINAL_DIR="$TMP/terminal-runtime" \
  "$ROOT/scripts/open-worker-terminal.sh" --runtime claude \
  --project "$TMP/terminal-project" --name test-visible \
  --goal task:T1-test \
  --permission-mode plan --verify-timeout 5 > "$TMP/terminal-visible.out"
grep -q '^launched: true$' "$TMP/terminal-visible.out"
VISIBLE_PID="$(sed -n 's/^pid: //p' "$TMP/terminal-visible.out")"
[ -n "$VISIBLE_PID" ] || fail "launcher did not report a worker PID"
kill "$VISIBLE_PID"
for _ in 1 2 3 4 5; do
  kill -0 "$VISIBLE_PID" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$VISIBLE_PID" 2>/dev/null; then
  fail "launcher test worker was not cleaned up"
fi

echo "[7/11] graph validator rejects broken dependencies and write conflicts"
cat > "$TMP/graph-valid.yaml" <<'YAML'
version: 1
nodes:
  - id: "base"
    title: "Create the base contract"
    kind: "worker"
    goal_ref: "task:base"
    needs: []
    consumes: []
    produces: ["build/base.json"]
    writes: ["src/base"]
    on_pass: "api"
    on_fail: "failed"
    max_attempts: 1
  - id: "api"
    title: "Build the API"
    kind: "worker"
    goal_ref: "task:api"
    needs: ["base"]
    consumes: ["build/base.json"]
    produces: ["build/api.json"]
    writes: ["src/api"]
    on_pass: "merge"
    on_fail: "failed"
    max_attempts: 1
  - id: "ui"
    title: "Build the UI"
    kind: "worker"
    goal_ref: "task:ui"
    needs: ["base"]
    consumes: ["build/base.json"]
    produces: ["build/ui.json"]
    writes: ["src/ui"]
    on_pass: "merge"
    on_fail: "failed"
    max_attempts: 1
  - id: "merge"
    title: "Integrate the outputs"
    kind: "merge"
    goal_ref: "task:merge"
    needs: ["api", "ui"]
    consumes: ["build/api.json", "build/ui.json"]
    produces: ["build/release.json"]
    writes: ["release"]
    on_pass: "done"
    on_fail: "failed"
    max_attempts: 1
YAML
"$ROOT/scripts/validate-graph.py" "$TMP/graph-valid.yaml" > "$TMP/graph-valid.out"
grep -q 'Graph validation passed' "$TMP/graph-valid.out"

cp "$TMP/graph-valid.yaml" "$TMP/graph-missing-dependency.yaml"
sed -i.bak 's/needs: \["api", "ui"\]/needs: ["api"]/' "$TMP/graph-missing-dependency.yaml"
if "$ROOT/scripts/validate-graph.py" "$TMP/graph-missing-dependency.yaml" \
  > "$TMP/graph-missing-dependency.out" 2>&1; then
  fail "graph validator accepted a consumed output without dependency ancestry"
fi
grep -q 'none is in its needs ancestry' "$TMP/graph-missing-dependency.out"

cp "$TMP/graph-valid.yaml" "$TMP/graph-dynamic-goal.yaml"
sed -i.bak 's/goal_ref: "task:base"/goal_ref: "queue\/inbox\/base\/goal.md"/' \
  "$TMP/graph-dynamic-goal.yaml"
if "$ROOT/scripts/validate-graph.py" "$TMP/graph-dynamic-goal.yaml" \
  > "$TMP/graph-dynamic-goal.out" 2>&1; then
  fail "graph validator accepted a dynamic queue Goal path"
fi
grep -q 'goal_ref contains a dynamic queue path' "$TMP/graph-dynamic-goal.out"

cp "$TMP/graph-valid.yaml" "$TMP/graph-write-overlap.yaml"
sed -i.bak 's/writes: \["src\/ui"\]/writes: ["src\/api\/components"]/' \
  "$TMP/graph-write-overlap.yaml"
if "$ROOT/scripts/validate-graph.py" "$TMP/graph-write-overlap.yaml" \
  > "$TMP/graph-write-overlap.out" 2>&1; then
  fail "graph validator accepted overlapping parallel writes"
fi
grep -q 'parallel write overlap' "$TMP/graph-write-overlap.out"

echo "[8/11] state validator keeps queue, ledger, Goal, and STATUS atomic"
mkdir -p "$TMP/state-valid"
"$ROOT/init.sh" "$TMP/state-valid" > "$TMP/state-init.out"
mkdir -p "$TMP/state-valid/.agent-taskgraph/queue/active/P5-ui"
cat > "$TMP/state-valid/.agent-taskgraph/queue/active/P5-ui/goal.md" <<'MD'
# Goal: Build UI

> Task ID: `P5-ui`
MD
cat > "$TMP/state-valid/.agent-taskgraph/queue/active/P5-ui/ledger.md" <<'MD'
# Ledger

| 字段 | 值 |
|---|---|
| 任务 ID | P5-ui |
| Goal ref | task:P5-ui |
| Goal current path | queue/active/P5-ui/goal.md |
| 状态 | active |
MD
cat > "$TMP/state-valid/.agent-taskgraph/STATUS.md" <<'MD'
# Status

| 任务 ID | 标题 | 状态 | 负责人 | 轮次 | 最后更新 | 卡点 |
|---|---|---|---|---|---|---|
| P5-ui | Build UI | active | worker | 1 | now | none |
MD
"$ROOT/scripts/validate-state.py" "$TMP/state-valid" > "$TMP/state-valid.out"
grep -q 'State validation passed' "$TMP/state-valid.out"

cp -R "$TMP/state-valid" "$TMP/state-stale"
printf '%s\n' '| stale-task | Stale | active | worker | 1 | now | none |' \
  >> "$TMP/state-stale/.agent-taskgraph/STATUS.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-stale" > "$TMP/state-stale.out" 2>&1; then
  fail "state validator accepted a stale STATUS row"
fi
grep -q 'stale or unknown STATUS.md row' "$TMP/state-stale.out"

cp -R "$TMP/state-valid" "$TMP/state-short-id"
sed -i.bak 's/| P5-ui | Build UI/| P5 | Build UI/' \
  "$TMP/state-short-id/.agent-taskgraph/STATUS.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-short-id" > "$TMP/state-short-id.out" 2>&1; then
  fail "state validator accepted a shortened STATUS task ID"
fi
grep -q 'P5-ui: missing from STATUS.md' "$TMP/state-short-id.out"

cp -R "$TMP/state-valid" "$TMP/state-wrong-ledger"
sed -i.bak 's/queue\/active\/P5-ui\/goal.md/queue\/inbox\/P5-ui\/goal.md/' \
  "$TMP/state-wrong-ledger/.agent-taskgraph/queue/active/P5-ui/ledger.md"
sed -i.bak 's/| 状态 | active |/| 状态 | inbox |/' \
  "$TMP/state-wrong-ledger/.agent-taskgraph/queue/active/P5-ui/ledger.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-wrong-ledger" \
  > "$TMP/state-wrong-ledger.out" 2>&1; then
  fail "state validator accepted a stale ledger state and Goal path"
fi
grep -q "ledger state 'inbox' != directory state 'active'" "$TMP/state-wrong-ledger.out"
grep -q 'Goal current path must be queue/active/P5-ui/goal.md' "$TMP/state-wrong-ledger.out"

echo "[9/11] cleanup is dry-run and archived-only by default"
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

echo "[10/11] skill metadata, templates, links, version, license, and graph YAML"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
assert (root / "VERSION").read_text().strip() == "0.8.0-beta.3"
assert "Apache License" in (root / "LICENSE").read_text()
skill = (root / "SKILL.md").read_text()
assert skill.startswith("---\nname: agent-taskgraph\n")
assert "description:" in skill.split("---", 2)[1]
for phrase in ("一句话足以发起需求", "spec.md", "graph.yaml", "Human Gate"):
    assert phrase in skill, phrase
assert "references/hapi-runtime.md" in skill
for adapter_detail in ("HAPI 派发硬门", "hapi runner list", "hapi resume <id>"):
    assert adapter_detail not in skill, f"HAPI detail leaked into core skill: {adapter_detail}"
hapi_reference = (root / "references/hapi-runtime.md").read_text()
for phrase in ("只在", "native-first", "派发硬门", "不得自动启用", "fallback"):
    assert phrase in hapi_reference, phrase
project_template = (root / "templates/PROJECT.md").read_text()
for phrase in ("Runtime preference", "原生运行时优先", "已启用可选适配器", "Runtime fallback"):
    assert phrase in project_template, phrase

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

echo "[11/11] platform plugin package and marketplace catalog"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import sys

root = Path(sys.argv[1])
version = (root / "VERSION").read_text().strip()
package = root / "plugins" / "agent-taskgraph"
assert package.is_dir(), "missing plugin package"

required = (
    ".codex-plugin/plugin.json",
    ".claude-plugin/plugin.json",
    "LICENSE",
    "README.md",
    "skills/agent-taskgraph/SKILL.md",
    "skills/agent-taskgraph/VERSION",
    "skills/agent-taskgraph/agents/openai.yaml",
    "skills/agent-taskgraph/init.sh",
    "skills/agent-taskgraph/references/hapi-runtime.md",
    "skills/agent-taskgraph/scripts/check-update.sh",
    "skills/agent-taskgraph/scripts/open-worker-terminal.sh",
    "skills/agent-taskgraph/scripts/validate-graph.py",
    "skills/agent-taskgraph/scripts/validate-state.py",
    "skills/agent-taskgraph/templates/PROJECT.md",
    "skills/agent-taskgraph/workers/parse-worker-log.py",
)
for relative in required:
    assert (package / relative).is_file(), f"missing plugin file: {relative}"

for manifest_name in (".codex-plugin/plugin.json", ".claude-plugin/plugin.json"):
    manifest = json.loads((package / manifest_name).read_text())
    assert manifest["name"] == "agent-taskgraph"
    assert manifest["version"] == version, f"version drift in {manifest_name}"
    assert manifest["license"] == "Apache-2.0"

assert (package / "skills/agent-taskgraph/VERSION").read_text().strip() == version
assert (package / "skills/agent-taskgraph/SKILL.md").read_text() == (root / "SKILL.md").read_text()
assert (package / "LICENSE").read_text() == (root / "LICENSE").read_text()
for relative in (
    "init.sh",
    "references/hapi-runtime.md",
    "scripts/check-update.sh",
    "scripts/open-worker-terminal.sh",
    "scripts/validate-graph.py",
    "scripts/validate-state.py",
    "agents/openai.yaml",
    "templates/PROJECT.md",
    "templates/STATUS.md",
    "templates/DECISIONS.md",
    "templates/spec.md",
    "templates/graph.yaml",
    "templates/goal.md",
    "templates/ledger.md",
    "templates/report.md",
    "workers/log-cleanup.sh",
    "workers/parse-worker-log.py",
    "workers/watch-worker.sh",
):
    packaged = package / "skills/agent-taskgraph" / relative
    canonical = root / relative
    assert packaged.read_text() == canonical.read_text(), f"package drift: {relative}"

catalog = json.loads((root / ".claude-plugin/marketplace.json").read_text())
assert catalog["name"] == "agent-taskgraph-marketplace"
assert catalog["plugins"][0]["name"] == "agent-taskgraph"
assert catalog["plugins"][0]["source"] == "./plugins/agent-taskgraph"
assert catalog["plugins"][0]["version"] == version
PY

echo "All smoke tests passed."
