#!/usr/bin/env bash
set -euo pipefail

RUNTIME=""
PROJECT=""
NAME=""
GOAL=""
GOAL_REF=""
GOAL_PATH=""
MODEL=""
EFFORT=""
PERMISSION_MODE="plan"
PLUGIN_DIR=""
VERIFY_TIMEOUT=15
DRY_RUN=0
ALLOW_DANGEROUS=0

usage() {
  cat <<'EOF'
Usage: open-worker-terminal.sh --runtime claude|codex --project DIR \
  --name NAME --goal FILE|task:ID [options]

Open a visible macOS Terminal window running a native Claude or Codex worker.

Options:
  --model MODEL              Runtime model override.
  --effort LEVEL             low|medium|high|xhigh|max.
  --permission-mode MODE     plan (default), acceptEdits, auto, manual,
                             dontAsk, or bypassPermissions.
  --plugin-dir DIR           Claude plugin directory. Claude only.
  --verify-timeout SECONDS   Wait for the worker PID (default: 15).
  --allow-dangerous          Required with bypassPermissions.
  --dry-run                  Print the native command without opening Terminal.
  -h, --help                 Show this help.

Use task:ID for queue-managed work so the Goal remains resolvable when its state
directory moves. File paths may be absolute or relative to --project. Launcher
artifacts are written under ${TMPDIR:-/tmp}/agent-taskgraph-terminal.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

need_value() {
  [ "$#" -ge 2 ] || die "$1 requires a value"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --runtime)
      need_value "$@"
      RUNTIME="$2"
      shift 2
      ;;
    --project)
      need_value "$@"
      PROJECT="$2"
      shift 2
      ;;
    --name)
      need_value "$@"
      NAME="$2"
      shift 2
      ;;
    --goal)
      need_value "$@"
      GOAL="$2"
      shift 2
      ;;
    --model)
      need_value "$@"
      MODEL="$2"
      shift 2
      ;;
    --effort)
      need_value "$@"
      EFFORT="$2"
      shift 2
      ;;
    --permission-mode)
      need_value "$@"
      PERMISSION_MODE="$2"
      shift 2
      ;;
    --plugin-dir)
      need_value "$@"
      PLUGIN_DIR="$2"
      shift 2
      ;;
    --verify-timeout)
      need_value "$@"
      VERIFY_TIMEOUT="$2"
      shift 2
      ;;
    --allow-dangerous)
      ALLOW_DANGEROUS=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[ "$RUNTIME" = "claude" ] || [ "$RUNTIME" = "codex" ] || \
  die "--runtime must be claude or codex"
[ -n "$PROJECT" ] || die "--project is required"
[ -n "$NAME" ] || die "--name is required"
[ -n "$GOAL" ] || die "--goal is required"
[ -d "$PROJECT" ] || die "project directory does not exist: $PROJECT"

case "$NAME" in
  *[!A-Za-z0-9._-]*|'')
    die "--name may contain only letters, digits, dot, underscore, and hyphen"
    ;;
esac

case "$PERMISSION_MODE" in
  plan|acceptEdits|auto|manual|dontAsk|bypassPermissions) ;;
  *) die "unsupported permission mode: $PERMISSION_MODE" ;;
esac

if [ -n "$EFFORT" ]; then
  case "$EFFORT" in
    low|medium|high|xhigh|max) ;;
    *) die "unsupported effort: $EFFORT" ;;
  esac
fi

case "$VERIFY_TIMEOUT" in
  ''|*[!0-9]*) die "--verify-timeout must be a positive integer" ;;
esac
[ "$VERIFY_TIMEOUT" -gt 0 ] || die "--verify-timeout must be greater than zero"

if [ "$PERMISSION_MODE" = "bypassPermissions" ] && [ "$ALLOW_DANGEROUS" -ne 1 ]; then
  die "bypassPermissions requires the explicit --allow-dangerous flag"
fi

PROJECT="$(cd "$PROJECT" && pwd -P)"
case "$GOAL" in
  task:*)
    TASK_ID="${GOAL#task:}"
    case "$TASK_ID" in
      *[!A-Za-z0-9._-]*|'') die "task Goal refs may contain only letters, digits, dot, underscore, and hyphen" ;;
    esac
    GOAL_REF="$GOAL"
    GOAL_MATCHES=()
    for state in inbox active review done failed; do
      candidate="$PROJECT/.agent-taskgraph/queue/$state/$TASK_ID/goal.md"
      [ ! -f "$candidate" ] || GOAL_MATCHES+=("$candidate")
    done
    [ "${#GOAL_MATCHES[@]}" -eq 1 ] || \
      die "$GOAL_REF must resolve to exactly one queue Goal; found ${#GOAL_MATCHES[@]}"
    GOAL_PATH="${GOAL_MATCHES[0]}"
    ;;
  /*)
    GOAL_PATH="$GOAL"
    ;;
  *)
    GOAL_PATH="$PROJECT/$GOAL"
    ;;
esac
[ -f "$GOAL_PATH" ] || die "Goal file does not exist: $GOAL_PATH"
GOAL_PATH="$(cd "$(dirname "$GOAL_PATH")" && pwd -P)/$(basename "$GOAL_PATH")"

if [ -n "$PLUGIN_DIR" ]; then
  [ "$RUNTIME" = "claude" ] || die "--plugin-dir is supported only for Claude"
  [ -d "$PLUGIN_DIR" ] || die "plugin directory does not exist: $PLUGIN_DIR"
  PLUGIN_DIR="$(cd "$PLUGIN_DIR" && pwd -P)"
fi

if [ -n "$GOAL_REF" ]; then
  GOAL_INSTRUCTION="Use stable Goal ref $GOAL_REF. Before each Goal read or write, resolve exactly one current file at $PROJECT/.agent-taskgraph/queue/{inbox,active,review,done,failed}/$TASK_ID/goal.md because its state directory may move."
else
  GOAL_INSTRUCTION="Read the Goal at $GOAL_PATH."
fi
PROMPT="Use \$agent-taskgraph. You are worker $NAME. $GOAL_INSTRUCTION Then read the PROJECT, frozen spec, graph node, ledger, and direct dependencies referenced by that Goal. Execute only the Goal's writes and Frozen scope. Do not edit PMO-owned queue state, STATUS, DECISIONS, or ledger unless the Goal explicitly assigns that file. Report the legal terminal and evidence before exiting."

CMD=()
if [ "$RUNTIME" = "claude" ]; then
  CMD=(claude --name "$NAME" --permission-mode "$PERMISSION_MODE")
  [ -z "$PLUGIN_DIR" ] || CMD+=(--plugin-dir "$PLUGIN_DIR")
  [ -z "$MODEL" ] || CMD+=(--model "$MODEL")
  [ -z "$EFFORT" ] || CMD+=(--effort "$EFFORT")
  CMD+=("$PROMPT")
else
  CMD=(codex -C "$PROJECT")
  case "$PERMISSION_MODE" in
    plan)
      CMD+=(-s read-only -a on-request)
      ;;
    acceptEdits|auto|manual)
      CMD+=(-s workspace-write -a on-request)
      ;;
    dontAsk)
      CMD+=(-s workspace-write -a never)
      ;;
    bypassPermissions)
      CMD+=(--dangerously-bypass-approvals-and-sandbox)
      ;;
  esac
  [ -z "$MODEL" ] || CMD+=(-m "$MODEL")
  [ -z "$EFFORT" ] || CMD+=(-c "model_reasoning_effort=\"$EFFORT\"")
  CMD+=("$PROMPT")
fi

print_command() {
  printf 'command:'
  printf ' %q' "${CMD[@]}"
  printf '\n'
}

printf 'runtime: %s\n' "$RUNTIME"
printf 'name: %s\n' "$NAME"
printf 'project: %s\n' "$PROJECT"
if [ -n "$GOAL_REF" ]; then
  printf 'goal-ref: %s\n' "$GOAL_REF"
  printf 'goal-current: %s\n' "$GOAL_PATH"
else
  printf 'goal: %s\n' "$GOAL_PATH"
fi
printf 'permission-mode: %s\n' "$PERMISSION_MODE"
print_command

if [ "$DRY_RUN" -eq 1 ]; then
  echo "mode: dry-run (Terminal not opened)"
  exit 0
fi

[ "$(uname -s)" = "Darwin" ] || die "visible Terminal mode currently supports macOS only"
command -v open >/dev/null 2>&1 || die "macOS open command is unavailable"
command -v "$RUNTIME" >/dev/null 2>&1 || die "$RUNTIME command is unavailable"

RUNTIME_ROOT="${AGENT_TASKGRAPH_TERMINAL_DIR:-${TMPDIR:-/tmp}/agent-taskgraph-terminal}"
LAUNCH_ID="$(date +%Y%m%d-%H%M%S)-$$-${RANDOM:-0}"
LAUNCH_DIR="$RUNTIME_ROOT/$LAUNCH_ID-$NAME"
LAUNCHER="$LAUNCH_DIR/$NAME.command"
PID_FILE="$LAUNCH_DIR/worker.pid"
META_FILE="$LAUNCH_DIR/metadata.txt"
mkdir -p "$LAUNCH_DIR"

{
  printf '#!/usr/bin/env bash\n'
  printf 'set -euo pipefail\n'
  printf 'cd %q\n' "$PROJECT"
  printf 'printf "%%s\\n" %q\n' "Agent TaskGraph visible worker: $NAME"
  printf 'printf "%%s\\n" %q\n' "Runtime: $RUNTIME"
  printf 'printf "%%s\\n" %q\n' "Goal: ${GOAL_REF:-$GOAL_PATH}"
  printf 'printf "%%s\\n" "$$" > %q\n' "$PID_FILE"
  printf 'exec'
  printf ' %q' "${CMD[@]}"
  printf '\n'
} > "$LAUNCHER"
chmod +x "$LAUNCHER"

{
  printf 'runtime=%s\n' "$RUNTIME"
  printf 'name=%s\n' "$NAME"
  printf 'project=%s\n' "$PROJECT"
  printf 'goal_ref=%s\n' "$GOAL_REF"
  printf 'goal_current=%s\n' "$GOAL_PATH"
  printf 'permission_mode=%s\n' "$PERMISSION_MODE"
  printf 'launcher=%s\n' "$LAUNCHER"
  printf 'pid_file=%s\n' "$PID_FILE"
} > "$META_FILE"

open -a Terminal "$LAUNCHER"

deadline=$((SECONDS + VERIFY_TIMEOUT))
while [ "$SECONDS" -lt "$deadline" ]; do
  if [ -s "$PID_FILE" ]; then
    WORKER_PID="$(cat "$PID_FILE")"
    if kill -0 "$WORKER_PID" 2>/dev/null; then
      sleep 1
      if kill -0 "$WORKER_PID" 2>/dev/null; then
        printf 'launched: true\n'
        printf 'pid: %s\n' "$WORKER_PID"
        printf 'launcher: %s\n' "$LAUNCHER"
        printf 'metadata: %s\n' "$META_FILE"
        exit 0
      fi
    fi
  fi
  sleep 1
done

die "Terminal opened but the worker process was not verified within ${VERIFY_TIMEOUT}s; inspect $LAUNCHER"
