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

echo "[1/13] shell and Python syntax"
bash -n "$ROOT/install.sh" "$ROOT/init.sh" "$ROOT/scripts/check-update.sh" \
  "$ROOT/scripts/open-worker-terminal.sh" "$ROOT/workers/watch-worker.sh" \
  "$ROOT/workers/log-cleanup.sh" "$ROOT/tests/smoke.sh"
python3 - "$ROOT/workers/parse-worker-log.py" \
  "$ROOT/scripts/render-dispatch.py" "$ROOT/scripts/prepare-task.py" \
  "$ROOT/scripts/validate-graph.py" "$ROOT/scripts/validate-state.py" \
  "$ROOT/scripts/verify-hapi-session.py" "$ROOT/scripts/hapi-hub-session.py" <<'PY'
from pathlib import Path
import sys

for filename in sys.argv[1:]:
    source = Path(filename).read_text()
    compile(source, filename, "exec")
PY

echo "[2/13] Codex log parser fixtures"
python3 "$ROOT/workers/parse-worker-log.py" --format jsonl \
  < "$ROOT/tests/fixtures/codex-events.jsonl" > "$TMP/parser.out"
diff -u "$ROOT/tests/fixtures/codex-events.expected" "$TMP/parser.out"

echo "[3/13] update checker states"
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
grep -q 'version: 0.8.0-beta.15' "$TMP/update-current.out"
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

echo "[4/13] install, status, conflict, force, and uninstall"
HOME="$TMP/home-install" "$ROOT/install.sh" > "$TMP/install.out"
assert_link_to "$TMP/home-install/.claude/skills/agent-taskgraph" "$ROOT"
assert_link_to "$TMP/home-install/.codex/skills/agent-taskgraph" "$ROOT"
HOME="$TMP/home-install" "$ROOT/install.sh" --status > "$TMP/status.out"
grep -q "$ROOT" "$TMP/status.out"
grep -q 'Version: 0.8.0-beta.15' "$TMP/status.out"
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

echo "[5/13] project initialization preserves existing files"
mkdir -p "$TMP/project"
"$ROOT/init.sh" "$TMP/project" > "$TMP/init.out"
assert_file "$TMP/project/.agent-taskgraph/PROJECT.md"
for file in PLAN.md TEAM.md STATUS.md DECISIONS.md tasks/TEMPLATE.md; do
  assert_file "$TMP/project/.agent-taskgraph/$file"
done
assert_dir "$TMP/project/.agent-taskgraph/tasks"
assert_dir "$TMP/project/.agent-taskgraph/archive"
grep -q 'PMO 维护' "$TMP/project/.agent-taskgraph/STATUS.md"
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
"$ROOT/init.sh" --migrate --legacy-queue "$TMP/project-legacy" > "$TMP/legacy-migrate.out"
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

echo "[6/13] visible Terminal launcher dry-run and permission gates"
mkdir -p "$TMP/terminal-project/.agent-taskgraph/queue/inbox/T1-test"
cat > "$TMP/terminal-project/.agent-taskgraph/queue/inbox/T1-test/goal.md" <<'MD'
# Goal: launcher test

> Task ID: `T1-test`
> Context manifest: `context.md`
> Context revision: `ctx-1`

## 分配记录

- Role ref：`role:test-worker`
MD
cat > "$TMP/terminal-project/.agent-taskgraph/queue/inbox/T1-test/context.md" <<'MD'
# Context

> Task ID: `T1-test`
> Revision: `ctx-1`
MD
mkdir -p "$TMP/terminal-project/.agent-taskgraph/roles/test-worker"
cat > "$TMP/terminal-project/.agent-taskgraph/roles/test-worker/ROLE.md" <<'MD'
# Role: Test Worker

| 字段 | 值 |
|---|---|
| Role ID | test-worker |
| Team revision | rev-1 |
| 生命周期 | persistent |
MD
cat > "$TMP/terminal-project/.agent-taskgraph/ROLES.md" <<'MD'
# Roles

> Team revision: `rev-1`
MD
cat > "$TMP/terminal-project/.agent-taskgraph/queue/inbox/T1-test/dispatch.md" <<'MD'
# Dispatch Bootstrap: T1-test

| 字段 | 值 |
|---|---|
| Task ID | T1-test |
| Dispatch ID | dispatch:T1-test:attempt-1 |
| Role ref | role:test-worker |
| Role profile | roles/test-worker/ROLE.md |
| Role lifecycle | persistent |
| Team revision | rev-1 |
| Goal ref | task:T1-test |
| Context manifest | context.md |
| Context revision | ctx-1 |
| Continuity | new-role |
| Session ID | PENDING |
| Expected identity ACK | IDENTITY_READY dispatch_id=dispatch:T1-test:attempt-1 role=role:test-worker team_revision=rev-1 goal=task:T1-test context_revision=ctx-1 |
| Delivery | NOT_SENT |
| Identity ACK | PENDING |
| ACK evidence | PENDING |
MD
cp "$TMP/terminal-project/.agent-taskgraph/queue/inbox/T1-test/context.md" \
  "$TMP/terminal-project/context.saved"
sed -i.bak 's/Revision: `ctx-1`/Revision: `ctx-2`/' \
  "$TMP/terminal-project/.agent-taskgraph/queue/inbox/T1-test/context.md"
if "$ROOT/scripts/render-dispatch.py" --project "$TMP/terminal-project" \
  --goal task:T1-test > "$TMP/terminal-context-drift.out" 2>&1; then
  fail "dispatch renderer accepted Context revision drift"
fi
grep -q 'context revision differs from dispatch' "$TMP/terminal-context-drift.out"
mv "$TMP/terminal-project/context.saved" \
  "$TMP/terminal-project/.agent-taskgraph/queue/inbox/T1-test/context.md"
AGENT_TASKGRAPH_TERMINAL_DIR="$TMP/terminal-runtime" \
  "$ROOT/scripts/open-worker-terminal.sh" --runtime claude \
  --project "$TMP/terminal-project" --name test-claude \
  --goal task:T1-test \
  --plugin-dir "$ROOT/plugins/agent-taskgraph" --model sonnet --effort high \
  --permission-mode plan --dry-run > "$TMP/terminal-claude.out"
grep -q '^runtime: claude$' "$TMP/terminal-claude.out"
grep -q '^goal-ref: task:T1-test$' "$TMP/terminal-claude.out"
grep -q 'command: claude .*--name test-claude .*--permission-mode plan' "$TMP/terminal-claude.out"
grep -q 'role=role:test-worker' "$TMP/terminal-claude.out"
grep -q 'context_revision=ctx-1' "$TMP/terminal-claude.out"
grep -q 'IDENTITY_READY dispatch_id=dispatch:T1-test:attempt-1' "$TMP/terminal-claude.out"
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
cat > "$TMP/terminal-bin/uname" <<'SH'
#!/usr/bin/env bash
echo Darwin
SH
chmod +x "$TMP/terminal-bin/open" "$TMP/terminal-bin/claude" "$TMP/terminal-bin/uname"
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

echo "[7/13] HAPI runtime evidence must match before dispatch"
mkdir -p "$TMP/hapi-worktree"
cat > "$TMP/hapi-verified.log" <<LOG
[10:00:00.000] Starting hapi CLI with args:  ["bun","/hapi","claude","--started-by","runner"]
  "workingDirectory": "$TMP/hapi-worktree",
  "processPid": $$,
[10:00:00.100] [START] Reporting session 11111111-2222-4333-8444-555555555555 to runner
[10:00:00.200] Session: 11111111-2222-4333-8444-555555555555
[10:00:00.300] [loop] Synced session config for keepalive: permissionMode=bypassPermissions, model=deepseek-v4-flash[1m], effort=max
LOG
"$ROOT/scripts/verify-hapi-session.py" \
  --log "$TMP/hapi-verified.log" \
  --session-id 11111111-2222-4333-8444-555555555555 --pid $$ \
  --cwd "$TMP/hapi-worktree" --flavor claude \
  --model 'deepseek-v4-flash[1m]' --effort max --permission yolo \
  --json > "$TMP/hapi-verified.out"
grep -q '"status": "VERIFIED"' "$TMP/hapi-verified.out"
grep -q '"permission": "bypassPermissions"' "$TMP/hapi-verified.out"

cp "$TMP/hapi-verified.log" "$TMP/hapi-default.log"
sed -i.bak 's/permissionMode=bypassPermissions/permissionMode=default/' \
  "$TMP/hapi-default.log"
if "$ROOT/scripts/verify-hapi-session.py" \
  --log "$TMP/hapi-default.log" \
  --session-id 11111111-2222-4333-8444-555555555555 --pid $$ \
  --cwd "$TMP/hapi-worktree" --flavor claude \
  --model 'deepseek-v4-flash[1m]' --effort max --permission yolo \
  > "$TMP/hapi-default.out" 2>&1; then
  fail "HAPI verifier accepted default permission when yolo was approved"
fi
grep -q "permission mismatch" "$TMP/hapi-default.out"

cp "$TMP/hapi-verified.log" "$TMP/hapi-dispatched.log"
echo '[10:00:01.000] [loop] User message received with permission mode: bypassPermissions, model: deepseek-v4-flash[1m], effort: max' \
  >> "$TMP/hapi-dispatched.log"
if "$ROOT/scripts/verify-hapi-session.py" \
  --log "$TMP/hapi-dispatched.log" \
  --session-id 11111111-2222-4333-8444-555555555555 --pid $$ \
  --cwd "$TMP/hapi-worktree" --flavor claude \
  --model 'deepseek-v4-flash[1m]' --effort max --permission yolo \
  > "$TMP/hapi-dispatched.out" 2>&1; then
  fail "HAPI verifier authorized a session after its first Goal message"
fi
grep -q 'pre-dispatch verification must pass before the first Goal message' \
  "$TMP/hapi-dispatched.out"
"$ROOT/scripts/verify-hapi-session.py" \
  --log "$TMP/hapi-dispatched.log" \
  --session-id 11111111-2222-4333-8444-555555555555 --pid $$ \
  --cwd "$TMP/hapi-worktree" --flavor claude \
  --model 'deepseek-v4-flash[1m]' --effort max --permission yolo \
  --phase audit > "$TMP/hapi-audit.out"
grep -q 'HAPI runtime verification passed' "$TMP/hapi-audit.out"
python3 "$ROOT/tests/test_hapi_hub_session.py" -v

echo "[8/13] graph validator rejects broken dependencies and write conflicts"
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

echo "[9/13] state validator keeps queue, ledger, Goal, and STATUS atomic"
mkdir -p "$TMP/state-valid"
"$ROOT/init.sh" --legacy-queue "$TMP/state-valid" > "$TMP/state-init.out"
mkdir -p "$TMP/state-valid/.agent-taskgraph/queue/active/P5-ui"
cat > "$TMP/state-valid/.agent-taskgraph/queue/active/P5-ui/goal.md" <<'MD'
# Goal: Build UI

> Task ID: `P5-ui`
> Baseline: `abc1234 main clean`
> Context manifest: `context.md`
> Context revision: `ctx-1`

## 分配记录

- Role ref：`role:frontend-ui`
- 角色职责：负责前端界面实现；本 Goal 属于 UI 模块
- 角色生命周期：persistent
- 连续性：新角色 + session-123
- Runtime requested：`runtime=hapi; flavor=claude; model=sonnet; effort=high; permission=bypassPermissions; visibility=visible`
- Runtime observed：`runtime=hapi; flavor=claude; model=sonnet; effort=high; permission=bypassPermissions; visibility=visible`
- Runtime verification：VERIFIED: pre-dispatch check
- Session evidence：session-123 + pid 456 + /tmp/session.log
- Dispatch bootstrap：dispatch.md
- Dispatch message：SENT: 2026-08-06 via ping_peer dispatch:P5-ui:attempt-1
- Identity ACK：VERIFIED: IDENTITY_READY dispatch_id=dispatch:P5-ui:attempt-1 role=role:frontend-ui team_revision=rev-1 goal=task:P5-ui context_revision=ctx-1
MD
cat > "$TMP/state-valid/.agent-taskgraph/queue/active/P5-ui/ledger.md" <<'MD'
# Ledger

| 字段 | 值 |
|---|---|
| 任务 ID | P5-ui |
| Goal ref | task:P5-ui |
| Goal current path | queue/active/P5-ui/goal.md |
| Context manifest | context.md |
| Context revision | ctx-1 |
| Role ref | role:frontend-ui |
| Role lifecycle | persistent |
| Role profile | roles/frontend-ui/ROLE.md |
| Role continuity | 新角色 + session-123 |
| Reviewer Role ref | PENDING |
| Reviewer Role profile | PENDING |
| 状态 | active |
| Runtime requested | runtime=hapi; flavor=claude; model=sonnet; effort=high; permission=bypassPermissions; visibility=visible |
| Runtime observed | runtime=hapi; flavor=claude; model=sonnet; effort=high; permission=bypassPermissions; visibility=visible |
| Runtime verification | VERIFIED |
| Session ID | session-123 |
| Runtime evidence | runtime-evidence.json |
| Dispatch bootstrap | dispatch.md |
| Dispatch message | SENT: 2026-08-06 via ping_peer dispatch:P5-ui:attempt-1 |
| Identity ACK | VERIFIED: IDENTITY_READY dispatch_id=dispatch:P5-ui:attempt-1 role=role:frontend-ui team_revision=rev-1 goal=task:P5-ui context_revision=ctx-1 |
MD
cat > "$TMP/state-valid/.agent-taskgraph/queue/active/P5-ui/context.md" <<'MD'
# Context Manifest: P5-ui

> Task ID: `P5-ui`
> Revision: `ctx-1`
> Mode: `lean`
> Budget exception: `none`

## 必须读取（默认不超过 8 项）

| 路径或稳定引用 | Revision / 范围 | 为什么本 Goal 必须读 |
|---|---|---|
| `.agent-taskgraph/PROJECT.md` | relevant-sections | 项目硬约束 |
| `.agent-taskgraph/roles/frontend-ui/ROLE.md` | rev-1 | 长期职责与连续性 |
| `dispatch.md` | dispatch:P5-ui:attempt-1 | Role 与 Session 身份绑定 |
| `task:P5-ui` | current | 单次执行合同 |

## 按需检索（先搜索，再局部读取）

| 路径/范围 | 触发条件 | 检索提示 |
|---|---|---|
| `src/ui` | 确认实现细节 | `rg P5` |

## 明确不加载

- 无关历史与长日志
MD
mkdir -p "$TMP/state-valid/.agent-taskgraph/roles/frontend-ui"
cat > "$TMP/state-valid/.agent-taskgraph/roles/frontend-ui/ROLE.md" <<'MD'
# Role: Frontend UI

| 字段 | 值 |
|---|---|
| Role ID | frontend-ui |
| Team revision | rev-1 |
| Origin | initial:spec-rev-1 |
| 生命周期 | persistent |
| 状态 | assigned |
| 当前 Goal | task:P5-ui |
| 当前 Session ID | session-123 |
MD
cat > "$TMP/state-valid/.agent-taskgraph/ROLES.md" <<'MD'
# Roles

> Team revision: `rev-1`

| Role ID | 名称 | 生命周期 | 状态 | 核心职责 | 当前 Goal | Session ID | 最后更新 |
|---|---|---|---|---|---|---|---|
| frontend-ui | Frontend UI | persistent | assigned | UI | task:P5-ui | session-123 | now |
MD
cat > "$TMP/state-valid/.agent-taskgraph/queue/active/P5-ui/dispatch.md" <<'MD'
# Dispatch Bootstrap: P5-ui

| 字段 | 值 |
|---|---|
| Task ID | P5-ui |
| Dispatch ID | dispatch:P5-ui:attempt-1 |
| Role ref | role:frontend-ui |
| Role profile | roles/frontend-ui/ROLE.md |
| Role lifecycle | persistent |
| Team revision | rev-1 |
| Goal ref | task:P5-ui |
| Context manifest | context.md |
| Context revision | ctx-1 |
| Continuity | 新角色 + session-123 |
| Session ID | session-123 |
| Expected identity ACK | IDENTITY_READY dispatch_id=dispatch:P5-ui:attempt-1 role=role:frontend-ui team_revision=rev-1 goal=task:P5-ui context_revision=ctx-1 |
| Delivery | SENT: 2026-08-06 via ping_peer dispatch:P5-ui:attempt-1 |
| Identity ACK | VERIFIED: IDENTITY_READY dispatch_id=dispatch:P5-ui:attempt-1 role=role:frontend-ui team_revision=rev-1 goal=task:P5-ui context_revision=ctx-1 |
| ACK evidence | session-123 message=msg-001 observed=2026-08-06T10:01:00Z |
MD
cat > "$TMP/state-valid/.agent-taskgraph/queue/active/P5-ui/runtime-evidence.json" <<'JSON'
{
  "status": "VERIFIED",
  "phase": "pre-dispatch",
  "verification_id": "verification-p5-ui-001",
  "goal_ref": "task:P5-ui",
  "session_id": "session-123",
  "machine_id": "machine-1",
  "machine_name": "Test Runner",
  "machine_host": "test.local",
  "pid": "456",
  "flavor": "claude",
  "cwd": "/tmp/project-worktree",
  "model": "sonnet",
  "effort": "high",
  "permission": "bypassPermissions",
  "messages_received": 0,
  "message_watermark": {
    "latest_page_count": 0,
    "latest_message_id": "",
    "snapshot_head_seq": null,
    "snapshot_head_at": null,
    "epoch": 1,
    "captured_at": "2026-08-06T10:00:00Z"
  },
  "active": true,
  "thinking": false,
  "lifecycle": "running",
  "catalog": {
    "status": "VERIFIED",
    "source": "/api/claude/custom-models",
    "checked_at": "2026-08-06T09:59:00Z",
    "model": "sonnet",
    "effort": "high",
    "model_supported": true,
    "effort_supported": true
  },
  "evidence": "HAPI Hub metadata"
}
JSON
cat > "$TMP/state-valid/.agent-taskgraph/PROJECT.md" <<'MD'
# Project

| 配置 | 项目选择 |
|---|---|
| Agent TaskGraph 协议版本 | 0.8.0-beta.10 |
| Source baseline | READY: repo=/tmp/project; HEAD=abc1234; branch=main; clean |

| Execution profile | Confirmed value |
|---|---|
| Execution profile status | CONFIRMED |
| Execution profile confirmed by/at | Owner / 2026-08-06T09:55:00Z / test batch |
| Execution runtime | hapi |
| Execution control | scripts/hapi-hub-session.py |
| Execution machine | id=machine-1; name=Test Runner; host=test.local |
| Execution flavor | claude |
| Model selection policy | adaptive-batch |
| Fixed model/effort | none |
| Model catalog evidence | machine-1 / 2026-08-06T09:59:00Z / catalog READY |
| Execution permission | bypassPermissions |
| Permission scope | runtime-only |
| Execution visibility | visible |
| Execution fallback | none |
MD
cat > "$TMP/state-valid/.agent-taskgraph/STATUS.md" <<'MD'
# Status

| 任务 ID | 标题 | 状态 | 负责人 | 轮次 | 最后更新 | 卡点 |
|---|---|---|---|---|---|---|
| P5-ui | Build UI | active | worker | 1 | now | none |
MD
"$ROOT/scripts/validate-state.py" "$TMP/state-valid" > "$TMP/state-valid.out"
grep -q 'State validation passed' "$TMP/state-valid.out"

cp -R "$TMP/state-valid" "$TMP/state-beta8-compatible"
sed -i.bak 's/0.8.0-beta.10/0.8.0-beta.8/' \
  "$TMP/state-beta8-compatible/.agent-taskgraph/PROJECT.md"
rm "$TMP/state-beta8-compatible/.agent-taskgraph/queue/active/P5-ui/dispatch.md"
"$ROOT/scripts/validate-state.py" "$TMP/state-beta8-compatible" \
  > "$TMP/state-beta8-compatible.out"
grep -q 'State validation passed' "$TMP/state-beta8-compatible.out"

cp -R "$TMP/state-valid" "$TMP/state-missing-dispatch"
rm "$TMP/state-missing-dispatch/.agent-taskgraph/queue/active/P5-ui/dispatch.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-missing-dispatch" \
  > "$TMP/state-missing-dispatch.out" 2>&1; then
  fail "state validator accepted an active task without dispatch.md"
fi
grep -q 'missing dispatch.md' "$TMP/state-missing-dispatch.out"

cp -R "$TMP/state-valid" "$TMP/state-dispatch-role-drift"
sed -i.bak 's/| Role ref | role:frontend-ui |/| Role ref | role:other-worker |/' \
  "$TMP/state-dispatch-role-drift/.agent-taskgraph/queue/active/P5-ui/dispatch.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-dispatch-role-drift" \
  > "$TMP/state-dispatch-role-drift.out" 2>&1; then
  fail "state validator accepted dispatch Role drift"
fi
grep -q 'dispatch Role ref differs from ledger/registry' \
  "$TMP/state-dispatch-role-drift.out"

cp -R "$TMP/state-valid" "$TMP/state-identity-ack-drift"
sed -i.bak '/| Identity ACK |/s/context_revision=ctx-1/context_revision=ctx-2/' \
  "$TMP/state-identity-ack-drift/.agent-taskgraph/queue/active/P5-ui/dispatch.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-identity-ack-drift" \
  > "$TMP/state-identity-ack-drift.out" 2>&1; then
  fail "state validator accepted an unverified identity ACK"
fi
grep -q 'dispatch Identity ACK must exactly match' \
  "$TMP/state-identity-ack-drift.out"

cp -R "$TMP/state-valid" "$TMP/state-missing-context"
rm "$TMP/state-missing-context/.agent-taskgraph/queue/active/P5-ui/context.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-missing-context" \
  > "$TMP/state-missing-context.out" 2>&1; then
  fail "state validator accepted an active task without context.md"
fi
grep -q 'missing context.md' "$TMP/state-missing-context.out"

cp -R "$TMP/state-valid" "$TMP/state-context-drift"
sed -i.bak 's/Revision: `ctx-1`/Revision: `ctx-2`/' \
  "$TMP/state-context-drift/.agent-taskgraph/queue/active/P5-ui/context.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-context-drift" \
  > "$TMP/state-context-drift.out" 2>&1; then
  fail "state validator accepted context revision drift"
fi
grep -q 'context revision differs from ledger' "$TMP/state-context-drift.out"

cp -R "$TMP/state-valid" "$TMP/state-context-over-budget"
cat > "$TMP/state-context-over-budget/.agent-taskgraph/queue/active/P5-ui/context.md" <<'MD'
# Context Manifest: P5-ui

> Task ID: `P5-ui`
> Revision: `ctx-1`
> Mode: `lean`
> Budget exception: `none`

## 必须读取（默认不超过 8 项）

| 路径或稳定引用 | Revision / 范围 | 为什么本 Goal 必须读 |
|---|---|---|
| `context-1.md` | rev-1 | required-1 |
| `context-2.md` | rev-2 | required-2 |
| `context-3.md` | rev-3 | required-3 |
| `context-4.md` | rev-4 | required-4 |
| `context-5.md` | rev-5 | required-5 |
| `context-6.md` | rev-6 | required-6 |
| `context-7.md` | rev-7 | required-7 |
| `context-8.md` | rev-8 | required-8 |
| `context-9.md` | rev-9 | required-9 |

## 按需检索（先搜索，再局部读取）

| 路径/范围 | 触发条件 | 检索提示 |
|---|---|---|
| `src/ui` | 确认实现细节 | `rg P5` |
MD
if "$ROOT/scripts/validate-state.py" "$TMP/state-context-over-budget" \
  > "$TMP/state-context-over-budget.out" 2>&1; then
  fail "state validator accepted an oversized context without exception"
fi
grep -q 'more than 8 required items without Budget exception' \
  "$TMP/state-context-over-budget.out"

cp -R "$TMP/state-valid" "$TMP/state-missing-role"
sed -i.bak '/frontend-ui | Frontend UI/d' "$TMP/state-missing-role/.agent-taskgraph/ROLES.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-missing-role" \
  > "$TMP/state-missing-role.out" 2>&1; then
  fail "state validator accepted a role absent from ROLES.md"
fi
grep -q 'role frontend-ui is missing from ROLES.md' "$TMP/state-missing-role.out"

cp -R "$TMP/state-valid" "$TMP/state-role-concurrent"
cp -R "$TMP/state-role-concurrent/.agent-taskgraph/queue/active/P5-ui" \
  "$TMP/state-role-concurrent/.agent-taskgraph/queue/active/P6-ui"
sed -i.bak 's/P5-ui/P6-ui/g' \
  "$TMP/state-role-concurrent/.agent-taskgraph/queue/active/P6-ui/goal.md" \
  "$TMP/state-role-concurrent/.agent-taskgraph/queue/active/P6-ui/ledger.md"
printf '%s\n' '| P6-ui | Build more UI | active | worker | 1 | now | none |' \
  >> "$TMP/state-role-concurrent/.agent-taskgraph/STATUS.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-role-concurrent" \
  > "$TMP/state-role-concurrent.out" 2>&1; then
  fail "state validator allowed one persistent role on concurrent Goals"
fi
grep -q 'persistent role assigned to concurrent tasks: P5-ui, P6-ui' \
  "$TMP/state-role-concurrent.out"

cp -R "$TMP/state-valid" "$TMP/state-review-role"
mv "$TMP/state-review-role/.agent-taskgraph/queue/active/P5-ui" \
  "$TMP/state-review-role/.agent-taskgraph/queue/review/P5-ui"
sed -i.bak 's|queue/active/P5-ui/goal.md|queue/review/P5-ui/goal.md|' \
  "$TMP/state-review-role/.agent-taskgraph/queue/review/P5-ui/ledger.md"
sed -i.bak 's/| 状态 | active |/| 状态 | review |/' \
  "$TMP/state-review-role/.agent-taskgraph/queue/review/P5-ui/ledger.md"
sed -i.bak 's/| Reviewer Role ref | PENDING |/| Reviewer Role ref | role:review-p5-ui |/' \
  "$TMP/state-review-role/.agent-taskgraph/queue/review/P5-ui/ledger.md"
sed -i.bak 's@Reviewer Role profile | PENDING@Reviewer Role profile | roles/review-p5-ui/ROLE.md@' \
  "$TMP/state-review-role/.agent-taskgraph/queue/review/P5-ui/ledger.md"
sed -i.bak 's/| P5-ui | Build UI | active |/| P5-ui | Build UI | review |/' \
  "$TMP/state-review-role/.agent-taskgraph/STATUS.md"
mkdir -p "$TMP/state-review-role/.agent-taskgraph/roles/review-p5-ui"
cat > "$TMP/state-review-role/.agent-taskgraph/roles/review-p5-ui/ROLE.md" <<'MD'
# Role: P5 UI Reviewer

| 字段 | 值 |
|---|---|
| Role ID | review-p5-ui |
| Team revision | rev-1 |
| Origin | initial:graph-rev-1 |
| 生命周期 | task-scoped |
| 状态 | assigned |
| 当前 Goal | task:P5-ui |
| 当前 Session ID | reviewer-session-456 |
MD
printf '%s\n' '| review-p5-ui | P5 UI Reviewer | task-scoped | assigned | Review P5 | task:P5-ui | reviewer-session-456 | now |' \
  >> "$TMP/state-review-role/.agent-taskgraph/ROLES.md"
"$ROOT/scripts/validate-state.py" "$TMP/state-review-role" \
  > "$TMP/state-review-role.out"
grep -q 'State validation passed' "$TMP/state-review-role.out"

cp -R "$TMP/state-review-role" "$TMP/state-review-not-independent"
sed -i.bak 's/Reviewer Role ref | role:review-p5-ui/Reviewer Role ref | role:frontend-ui/' \
  "$TMP/state-review-not-independent/.agent-taskgraph/queue/review/P5-ui/ledger.md"
sed -i.bak 's@Reviewer Role profile | roles/review-p5-ui/ROLE.md@Reviewer Role profile | roles/frontend-ui/ROLE.md@' \
  "$TMP/state-review-not-independent/.agent-taskgraph/queue/review/P5-ui/ledger.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-review-not-independent" \
  > "$TMP/state-review-not-independent.out" 2>&1; then
  fail "state validator allowed the worker role to review its own task"
fi
grep -q 'reviewer role must differ from worker role' \
  "$TMP/state-review-not-independent.out"

cp -R "$TMP/state-valid" "$TMP/state-staffing-missing"
sed -i.bak 's/Origin | initial:spec-rev-1/Origin | staffing:add-frontend-ui/' \
  "$TMP/state-staffing-missing/.agent-taskgraph/roles/frontend-ui/ROLE.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-staffing-missing" \
  > "$TMP/state-staffing-missing.out" 2>&1; then
  fail "state validator accepted a dynamic role without staffing record"
fi
grep -q 'missing staffing change record for staffing:add-frontend-ui' \
  "$TMP/state-staffing-missing.out"

cp -R "$TMP/state-staffing-missing" "$TMP/state-staffing-applied"
mkdir -p "$TMP/state-staffing-applied/.agent-taskgraph/staffing"
cat > "$TMP/state-staffing-applied/.agent-taskgraph/staffing/add-frontend-ui.md" <<'MD'
# Staffing Change: add-frontend-ui

> Team revision: `rev-0 → rev-1`
> Status: `APPLIED`
> Type: `ADD`
> Proposed by: `PMO / 2026-08-06`
> Approved by: `Owner / 2026-08-06`
MD
"$ROOT/scripts/validate-state.py" "$TMP/state-staffing-applied" \
  > "$TMP/state-staffing-applied.out"
grep -q 'State validation passed' "$TMP/state-staffing-applied.out"

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

cp -R "$TMP/state-valid" "$TMP/state-runtime-mismatch"
sed -i.bak 's/Runtime observed | runtime=hapi; flavor=claude; model=sonnet; effort=high; permission=bypassPermissions/Runtime observed | runtime=hapi; flavor=claude; model=sonnet; effort=high; permission=default/' \
  "$TMP/state-runtime-mismatch/.agent-taskgraph/queue/active/P5-ui/ledger.md"
sed -i.bak 's/Runtime observed：`runtime=hapi; flavor=claude; model=sonnet; effort=high; permission=bypassPermissions/Runtime observed：`runtime=hapi; flavor=claude; model=sonnet; effort=high; permission=default/' \
  "$TMP/state-runtime-mismatch/.agent-taskgraph/queue/active/P5-ui/goal.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-runtime-mismatch" \
  > "$TMP/state-runtime-mismatch.out" 2>&1; then
  fail "state validator accepted requested yolo with observed default permission"
fi
grep -q "runtime permission mismatch" "$TMP/state-runtime-mismatch.out"

cp -R "$TMP/state-valid" "$TMP/state-missing-runtime-evidence"
rm "$TMP/state-missing-runtime-evidence/.agent-taskgraph/queue/active/P5-ui/runtime-evidence.json"
if "$ROOT/scripts/validate-state.py" "$TMP/state-missing-runtime-evidence" \
  > "$TMP/state-missing-runtime-evidence.out" 2>&1; then
  fail "state validator accepted a HAPI task without verifier JSON"
fi
grep -q 'HAPI Runtime evidence file is missing' "$TMP/state-missing-runtime-evidence.out"

cp -R "$TMP/state-valid" "$TMP/state-late-runtime-evidence"
sed -i.bak 's/"messages_received": 0/"messages_received": 1/' \
  "$TMP/state-late-runtime-evidence/.agent-taskgraph/queue/active/P5-ui/runtime-evidence.json"
if "$ROOT/scripts/validate-state.py" "$TMP/state-late-runtime-evidence" \
  > "$TMP/state-late-runtime-evidence.out" 2>&1; then
  fail "state validator accepted HAPI evidence captured after dispatch"
fi
grep -q 'HAPI evidence must precede the first Goal message' \
  "$TMP/state-late-runtime-evidence.out"

cp -R "$TMP/state-valid" "$TMP/state-default-runtime"
sed -i.bak \
  -e 's/model=sonnet/model=default/g' \
  -e 's/effort=high/effort=auto/g' \
  "$TMP/state-default-runtime/.agent-taskgraph/queue/active/P5-ui/goal.md" \
  "$TMP/state-default-runtime/.agent-taskgraph/queue/active/P5-ui/ledger.md"
sed -i.bak \
  -e 's/"model": "sonnet"/"model": "default"/g' \
  -e 's/"effort": "high"/"effort": "auto"/g' \
  "$TMP/state-default-runtime/.agent-taskgraph/queue/active/P5-ui/runtime-evidence.json"
if "$ROOT/scripts/validate-state.py" "$TMP/state-default-runtime" \
  > "$TMP/state-default-runtime.out" 2>&1; then
  fail "state validator accepted default/auto model settings as VERIFIED"
fi
grep -q 'Runtime requested missing concrete fields: model, effort' \
  "$TMP/state-default-runtime.out"

cp -R "$TMP/state-valid" "$TMP/state-copied-evidence"
sed -i.bak 's/"goal_ref": "task:P5-ui"/"goal_ref": "task:P4-old"/' \
  "$TMP/state-copied-evidence/.agent-taskgraph/queue/active/P5-ui/runtime-evidence.json"
if "$ROOT/scripts/validate-state.py" "$TMP/state-copied-evidence" \
  > "$TMP/state-copied-evidence.out" 2>&1; then
  fail "state validator accepted HAPI evidence copied from another Goal"
fi
grep -q 'HAPI evidence goal_ref must match this Goal' \
  "$TMP/state-copied-evidence.out"

cp -R "$TMP/state-valid" "$TMP/state-unconfirmed-profile"
sed -i.bak 's/Execution profile status | CONFIRMED/Execution profile status | PENDING/' \
  "$TMP/state-unconfirmed-profile/.agent-taskgraph/PROJECT.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-unconfirmed-profile" \
  > "$TMP/state-unconfirmed-profile.out" 2>&1; then
  fail "state validator accepted an unconfirmed Execution profile"
fi
grep -q 'Execution profile status must be CONFIRMED' \
  "$TMP/state-unconfirmed-profile.out"

cp -R "$TMP/state-valid" "$TMP/state-valid-reuse"
sed -i.bak \
  -e 's/"phase": "pre-dispatch"/"phase": "pre-redispatch"/' \
  -e 's/"messages_received": 0/"messages_received": 1/' \
  -e 's/"latest_page_count": 0/"latest_page_count": 1/' \
  -e 's/"latest_message_id": ""/"latest_message_id": "message-7"/' \
  -e 's/"snapshot_head_seq": null/"snapshot_head_seq": 7/' \
  -e 's/"snapshot_head_at": null/"snapshot_head_at": 7000/' \
  "$TMP/state-valid-reuse/.agent-taskgraph/queue/active/P5-ui/runtime-evidence.json"
"$ROOT/scripts/validate-state.py" "$TMP/state-valid-reuse" \
  > "$TMP/state-valid-reuse.out"
grep -q 'State validation passed' "$TMP/state-valid-reuse.out"

cp -R "$TMP/state-valid" "$TMP/state-done-runtime-mismatch"
mv "$TMP/state-done-runtime-mismatch/.agent-taskgraph/queue/active/P5-ui" \
  "$TMP/state-done-runtime-mismatch/.agent-taskgraph/queue/done/P5-ui"
sed -i.bak 's/| 状态 | active |/| 状态 | done |/' \
  "$TMP/state-done-runtime-mismatch/.agent-taskgraph/queue/done/P5-ui/ledger.md"
sed -i.bak 's|queue/active/P5-ui/goal.md|queue/done/P5-ui/goal.md|' \
  "$TMP/state-done-runtime-mismatch/.agent-taskgraph/queue/done/P5-ui/ledger.md"
sed -i.bak 's/Runtime observed | runtime=hapi; flavor=claude; model=sonnet; effort=high; permission=bypassPermissions/Runtime observed | runtime=hapi; flavor=claude; model=sonnet; effort=high; permission=default/' \
  "$TMP/state-done-runtime-mismatch/.agent-taskgraph/queue/done/P5-ui/ledger.md"
sed -i.bak 's/Runtime observed：`runtime=hapi; flavor=claude; model=sonnet; effort=high; permission=bypassPermissions/Runtime observed：`runtime=hapi; flavor=claude; model=sonnet; effort=high; permission=default/' \
  "$TMP/state-done-runtime-mismatch/.agent-taskgraph/queue/done/P5-ui/goal.md"
cat > "$TMP/state-done-runtime-mismatch/.agent-taskgraph/STATUS.md" <<'MD'
# Status

| 任务 ID | 标题 | 状态 | 负责人 | 轮次 | 最后更新 | 卡点 |
|---|---|---|---|---|---|---|
MD
if "$ROOT/scripts/validate-state.py" "$TMP/state-done-runtime-mismatch" \
  > "$TMP/state-done-runtime-mismatch.out" 2>&1; then
  fail "state validator forgot runtime drift after a task moved to done"
fi
grep -q "runtime permission mismatch" "$TMP/state-done-runtime-mismatch.out"

cp -R "$TMP/state-valid" "$TMP/state-stale-baseline"
sed -i.bak 's/READY: repo=\/tmp\/project; HEAD=abc1234; branch=main; clean/待确认：尚未初始化 Git/' \
  "$TMP/state-stale-baseline/.agent-taskgraph/PROJECT.md"
if "$ROOT/scripts/validate-state.py" "$TMP/state-stale-baseline" \
  > "$TMP/state-stale-baseline.out" 2>&1; then
  fail "state validator accepted a stale project baseline"
fi
grep -q 'Source baseline must start with READY:' "$TMP/state-stale-baseline.out"

cp -R "$TMP/state-valid" "$TMP/state-frozen-open"
cat > "$TMP/state-frozen-open/.agent-taskgraph/spec.md" <<'MD'
# Spec
> Status: FROZEN
> Frozen by: Owner / 2026-08-06

## 开放问题

- Git baseline 仍待确认
MD
if "$ROOT/scripts/validate-state.py" "$TMP/state-frozen-open" \
  > "$TMP/state-frozen-open.out" 2>&1; then
  fail "state validator accepted unresolved questions in a Frozen spec"
fi
grep -q 'FROZEN requires 开放问题 to be exactly 无' "$TMP/state-frozen-open.out"

echo "[10/13] structured task preparation validates runtime and real worktrees"
mkdir -p "$TMP/prepare-project"
git -C "$TMP/prepare-project" init >/dev/null
git -C "$TMP/prepare-project" checkout -b main >/dev/null
git -C "$TMP/prepare-project" config user.name "Agent TaskGraph Tests"
git -C "$TMP/prepare-project" config user.email "tests@example.invalid"
printf 'baseline\n' > "$TMP/prepare-project/README.md"
git -C "$TMP/prepare-project" add README.md
git -C "$TMP/prepare-project" commit -m baseline >/dev/null
"$ROOT/init.sh" --legacy-queue "$TMP/prepare-project" >/dev/null
PREPARE_HEAD="$(git -C "$TMP/prepare-project" rev-parse HEAD)"
git -C "$TMP/prepare-project" worktree add -b agent/T1-prepare \
  "$TMP/prepare-worktree" "$PREPARE_HEAD" >/dev/null
cat > "$TMP/prepare-project/.agent-taskgraph/PROJECT.md" <<MD
# Project

| 配置 | 项目选择 |
|---|---|
| Agent TaskGraph 协议版本 | 0.8.0-beta.15 |
| Source baseline | READY: repo=$TMP/prepare-project; HEAD=$PREPARE_HEAD; branch=main; clean |
| 已启用可选适配器 | hapi |
| Preferred runtime | hapi |
| Preferred machine | id=machine-1; name=Test Runner; host=test.local |

| Execution profile | Confirmed value |
|---|---|
| Execution profile status | CONFIRMED |
| Runtime choice confirmed by/at | Owner / 2026-08-10T10:00:00Z / test batch / hapi |
| Execution profile confirmed by/at | Owner / 2026-08-10T10:00:00Z / test batch |
| Execution runtime | hapi |
| Execution control | HAPI Hub helper spawn/inspect/message |
| Execution machine | id=machine-1; name=Test Runner; host=test.local |
| Execution flavor | codex |
| Model selection policy | fixed |
| Fixed model/effort | model=gpt-5.6-sol; effort=xhigh |
| Model catalog evidence | test catalog / 2026-08-10T09:59:00Z |
| Execution permission | yolo |
| Permission scope | runtime-only |
| Execution visibility | visible |
| Execution fallback | none |
| Monitoring wait primitive | HAPI event + timer-cell/functions.wait(real cell_id) |
| Monitoring observe primitive | inspect_peer + HAPI session metadata/log + ledger |
| Monitoring target evidence | active/review ledger Session ID; inbox Goal ref before spawn |
MD
cat > "$TMP/prepare-project/.agent-taskgraph/spec.md" <<'MD'
# Spec
> Status: FROZEN
> Frozen by: Owner / 2026-08-10

## 开放问题

无
MD
cat > "$TMP/prepare-project/.agent-taskgraph/ROLES.md" <<'MD'
# Roles
> Team revision: `rev-1`

| Role ID | 名称 | 生命周期 | 状态 | 核心职责 | 当前 Goal | Session ID | 最后更新 |
|---|---|---|---|---|---|---|---|
| prepare-worker | Prepare Worker | persistent | reserved | Prepare one output | task:T1-prepare | PENDING | now |
MD
mkdir -p "$TMP/prepare-project/.agent-taskgraph/roles/prepare-worker"
cat > "$TMP/prepare-project/.agent-taskgraph/roles/prepare-worker/ROLE.md" <<'MD'
# Role

| 字段 | 值 |
|---|---|
| Role ID | prepare-worker |
| Team revision | rev-1 |
| Origin | initial:graph-r1 |
| 生命周期 | persistent |
| 状态 | reserved |
| 当前 Goal | task:T1-prepare |
| 当前 Session ID | PENDING |
MD
cat > "$TMP/prepare-manifest.json" <<MD
{
  "task_id": "T1-prepare",
  "title": "Prepare one output",
  "orchestration_mode": "lite",
  "stage": "implementation",
  "baseline": "$PREPARE_HEAD",
  "branch": "agent/T1-prepare",
  "worktree": "$TMP/prepare-worktree",
  "frozen_spec": ".agent-taskgraph/spec.md revision spec-r1",
  "graph_node": ".agent-taskgraph/graph.yaml#prepare",
  "context_revision": "ctx-1",
  "context_mode": "lean",
  "context_items": [
    {"path": ".agent-taskgraph/PROJECT.md", "revision": "profile-r1", "reason": "runtime contract"}
  ],
  "role_id": "prepare-worker",
  "role_lifecycle": "persistent",
  "role_responsibility": "Prepare one bounded output",
  "role_continuity": "new role and new session",
  "runtime_requested": {
    "runtime": "hapi",
    "flavor": "codex",
    "model": "gpt-5.6-sol",
    "effort": "xhigh",
    "permission": "yolo",
    "visibility": "visible"
  },
  "objective": "Create one bounded output.",
  "needs": ["none"],
  "consumes": [".agent-taskgraph/spec.md"],
  "produces": ["docs/output.md"],
  "writes": ["docs/"],
  "pass_route": "done",
  "fail_route": "failed",
  "max_attempts": 1,
  "failure_policy": "PRODUCT_FAIL returns to worker; HARNESS_INVALID reuses reviewer; DISPATCH_INVALID/RUNTIME_INVALID repair control plane in place",
  "acceptance": ["[ ] output exists"],
  "frozen": ["Do not edit another scope"],
  "estimate": "20 minutes"
}
MD
"$ROOT/scripts/prepare-task.py" --project "$TMP/prepare-project" \
  --manifest "$TMP/prepare-manifest.json" > "$TMP/prepare-task.out"
assert_file "$TMP/prepare-project/.agent-taskgraph/queue/inbox/T1-prepare/task-manifest.json"
grep -q '| T1-prepare | Prepare one output | inbox |' \
  "$TMP/prepare-project/.agent-taskgraph/STATUS.md"
"$ROOT/scripts/validate-state.py" --phase pre-dispatch "$TMP/prepare-project" \
  > "$TMP/prepare-state.out"
cp "$TMP/prepare-project/.agent-taskgraph/PROJECT.md" "$TMP/prepare-project.md"
sed -i.bak \
  's@HAPI event + timer-cell/functions.wait(real cell_id)@wait_agent(90000)@' \
  "$TMP/prepare-project/.agent-taskgraph/PROJECT.md"
if "$ROOT/scripts/validate-state.py" --phase pre-dispatch "$TMP/prepare-project" \
  > "$TMP/prepare-hapi-wait-agent.out" 2>&1; then
  fail "pre-dispatch validator allowed wait_agent to monitor a HAPI peer"
fi
grep -q 'HAPI monitoring cannot use wait_agent/wait_threads' \
  "$TMP/prepare-hapi-wait-agent.out"
cp "$TMP/prepare-project.md" "$TMP/prepare-project/.agent-taskgraph/PROJECT.md"
sed -i.bak '/Runtime choice confirmed by\/at/d' \
  "$TMP/prepare-project/.agent-taskgraph/PROJECT.md"
if "$ROOT/scripts/validate-state.py" --phase pre-dispatch "$TMP/prepare-project" \
  > "$TMP/prepare-missing-runtime-choice.out" 2>&1; then
  fail "pre-dispatch validator inferred runtime approval from other settings"
fi
grep -q 'Runtime choice confirmed by/at must be explicit' \
  "$TMP/prepare-missing-runtime-choice.out"
cp "$TMP/prepare-project.md" "$TMP/prepare-project/.agent-taskgraph/PROJECT.md"
cp "$TMP/prepare-project/.agent-taskgraph/roles/prepare-worker/ROLE.md" \
  "$TMP/prepare-role.md"
sed -i.bak 's/| 状态 | reserved |/| 状态 | assigned |/' \
  "$TMP/prepare-project/.agent-taskgraph/roles/prepare-worker/ROLE.md"
if "$ROOT/scripts/validate-state.py" --phase pre-dispatch "$TMP/prepare-project" \
  > "$TMP/prepare-assigned-too-early.out" 2>&1; then
  fail "pre-dispatch validator accepted assigned before identity ACK"
fi
grep -q 'inbox role must be reserved before spawn' \
  "$TMP/prepare-assigned-too-early.out"
cp "$TMP/prepare-role.md" \
  "$TMP/prepare-project/.agent-taskgraph/roles/prepare-worker/ROLE.md"
sed -i.bak "s@$TMP/prepare-worktree@$TMP/missing-worktree@" \
  "$TMP/prepare-project/.agent-taskgraph/queue/inbox/T1-prepare/goal.md"
if "$ROOT/scripts/validate-state.py" --phase pre-dispatch "$TMP/prepare-project" \
  > "$TMP/prepare-wrong-worktree.out" 2>&1; then
  fail "pre-dispatch validator accepted a nonexistent Goal worktree"
fi
grep -q 'not a registered Git worktree' "$TMP/prepare-wrong-worktree.out"

echo "[11/13] cleanup is dry-run and archived-only by default"
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

echo "[11b/13] operational health opens the circuit on repeated control failures"
mkdir -p "$TMP/health-project/.agent-taskgraph/queue/failed" \
  "$TMP/health-project/.agent-taskgraph/queue/active" \
  "$TMP/health-project/.agent-taskgraph/queue/inbox"
git -C "$TMP/health-project" init -q
git -C "$TMP/health-project" config user.name "Agent TaskGraph Tests"
git -C "$TMP/health-project" config user.email "tests@example.invalid"
printf 'baseline\n' > "$TMP/health-project/README.md"
git -C "$TMP/health-project" add README.md
git -C "$TMP/health-project" commit -qm baseline
"$ROOT/init.sh" --legacy-queue "$TMP/health-project" >/dev/null
for n in 1 2; do
  task="$TMP/health-project/.agent-taskgraph/queue/failed/T1-review-R$n"
  mkdir -p "$task"
  cat > "$task/ledger.md" <<MD
# Ledger
| 任务 ID | T1-review-R$n |
| 状态 | failed |
| 最后更新 | 2026-08-13T00:0${n}:00+00:00 |
| 验收结果 | INVALID_HARNESS |
| Failure class | HARNESS_INVALID |
| Failure boundary | T1-review |
| Harness attempt | 1 |
MD
done
if "$ROOT/scripts/check-operational-health.py" "$TMP/health-project" > "$TMP/health.out" 2>&1; then
  fail "operational health accepted repeated control failures"
fi
grep -q 'CIRCUIT_OPEN' "$TMP/health.out"
grep -q 'consecutive control-plane INVALID' "$TMP/health.out"

echo "[12/13] skill metadata, templates, links, version, license, and graph YAML"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
assert (root / "VERSION").read_text().strip() == "0.8.0-beta.15"
assert "Apache License" in (root / "LICENSE").read_text()
skill = (root / "SKILL.md").read_text()
assert skill.startswith("---\nname: agent-taskgraph\n")
assert "description:" in skill.split("---", 2)[1]
for phrase in ("一句话可以开始", "PROJECT.md", "PLAN.md", "TEAM.md", "Human Gate", "独立上下文"):
    assert phrase in skill, phrase
assert "references/hapi-runtime.md" in skill
assert "HAPI 默认关闭" in skill
assert "当前会话直接完成" in skill
for adapter_detail in ("HAPI 派发硬门", "hapi runner list", "hapi resume <id>"):
    assert adapter_detail not in skill, f"HAPI detail leaked into core skill: {adapter_detail}"
hapi_reference = (root / "references/hapi-runtime.md").read_text()
for phrase in ("只在", "native-first", "派发硬门", "不得自动启用", "fallback"):
    assert phrase in hapi_reference, phrase
for phrase in ("verify-hapi-session.py", "RUNTIME_CONFIG_MISMATCH", "先不要 `ping_peer`"):
    assert phrase in hapi_reference, phrase
project_template = (root / "templates/PROJECT.md").read_text()
for phrase in ("原生宿主", "模型/推理", "HAPI", "Human Gates"):
    assert phrase in project_template, phrase
runtime_profiles = (root / "references/runtime-profiles.md").read_text()
for phrase in ("一次确认协议", "adaptive-batch", "Permission scope", "目录探测"):
    assert phrase in runtime_profiles, phrase
for path in ("templates/ROLES.md", "templates/role.md", "templates/context.md", "templates/dispatch.md", "templates/staffing-change.md", "templates/PLAN.md", "templates/TEAM.md", "templates/task.md"):
    assert (root / path).is_file(), path
assert "Agent thread/session" in skill
assert "TASK_READY" in skill

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

echo "[13/13] platform plugin package and marketplace catalog"
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
    "skills/agent-taskgraph/references/native-runtimes.md",
    "skills/agent-taskgraph/references/hapi-runtime.md",
    "skills/agent-taskgraph/references/dispatch-bootstrap.md",
    "skills/agent-taskgraph/references/runtime-profiles.md",
    "skills/agent-taskgraph/scripts/check-update.sh",
    "skills/agent-taskgraph/scripts/check-operational-health.py",
    "skills/agent-taskgraph/scripts/hapi-hub-session.py",
    "skills/agent-taskgraph/scripts/open-worker-terminal.sh",
    "skills/agent-taskgraph/scripts/prepare-task.py",
    "skills/agent-taskgraph/scripts/render-dispatch.py",
    "skills/agent-taskgraph/scripts/validate-graph.py",
    "skills/agent-taskgraph/scripts/validate-state.py",
    "skills/agent-taskgraph/scripts/verify-hapi-session.py",
    "skills/agent-taskgraph/templates/PROJECT.md",
    "skills/agent-taskgraph/templates/PLAN.md",
    "skills/agent-taskgraph/templates/TEAM.md",
    "skills/agent-taskgraph/templates/task.md",
    "skills/agent-taskgraph/templates/ROLES.md",
    "skills/agent-taskgraph/templates/context.md",
    "skills/agent-taskgraph/templates/dispatch.md",
    "skills/agent-taskgraph/templates/role.md",
    "skills/agent-taskgraph/templates/staffing-change.md",
    "skills/agent-taskgraph/templates/task-manifest.json",
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
    "references/native-runtimes.md",
    "references/hapi-runtime.md",
    "references/dispatch-bootstrap.md",
    "references/runtime-profiles.md",
    "scripts/check-update.sh",
    "scripts/check-operational-health.py",
    "scripts/hapi-hub-session.py",
    "scripts/open-worker-terminal.sh",
    "scripts/prepare-task.py",
    "scripts/render-dispatch.py",
    "scripts/validate-graph.py",
    "scripts/validate-state.py",
    "scripts/verify-hapi-session.py",
    "agents/openai.yaml",
    "templates/PROJECT.md",
    "templates/PLAN.md",
    "templates/TEAM.md",
    "templates/ROLES.md",
    "templates/context.md",
    "templates/dispatch.md",
    "templates/STATUS.md",
    "templates/DECISIONS.md",
    "templates/spec.md",
    "templates/graph.yaml",
    "templates/goal.md",
    "templates/ledger.md",
    "templates/report.md",
    "templates/role.md",
    "templates/staffing-change.md",
    "templates/task-manifest.json",
    "templates/task.md",
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
