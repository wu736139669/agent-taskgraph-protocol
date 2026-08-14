# Agent TaskGraph

PMO-led native Agent Team orchestration for complex work in Codex and Claude Code.

Source version: [`v0.8.0-beta.16`](../../VERSION) | License: [Apache-2.0](../../LICENSE)

The current session is the PMO. It clarifies the request and creates a native Agent Team only when parallel work is useful. Codex uses Agent threads. Claude Code prefers Agent Teams for an active coordinated batch, Agent View background sessions for durable workers, and subagents only for bounded side tasks. Each Agent gets an independent context, an effective permission record, and an explicit worktree/write scope.

HAPI is an optional advanced adapter for explicit cross-machine control. It is disabled by default and is never required for normal use.

## Usage

In the target project, say:

```text
Use agent-taskgraph. Understand this project and request first. If parallel work is worthwhile, act as PMO and create native Codex/Claude sessions with separate contexts, shared-document handoffs, and final acceptance. Otherwise finish in the current session. Show me the understanding and team split before starting.
```

Initialize a new project state with:

```bash
~/.codex/skills/agent-taskgraph/init.sh /path/to/project
# or ~/.claude/skills/agent-taskgraph/init.sh /path/to/project
```

This creates `.agent-taskgraph/PROJECT.md`, `PLAN.md`, `TEAM.md`, `STATUS.md`, `DECISIONS.md`, `tasks/`, and `archive/`. Use `init.sh --legacy-queue` only for old queue-based projects or compatibility tests.

See the repository [README](../../README.md) for the complete protocol, context contract, Codex/Claude capability notes, and beta boundaries.
