# Agent TaskGraph

Native multi-session orchestration for complex work in Codex and Claude Code.

Source version: [`v0.8.0-beta.15`](../../VERSION) | License: [Apache-2.0](../../LICENSE)

The current session is the PMO. It clarifies the request, creates native Codex threads or Claude Code subagents only when parallel work is useful, gives each Agent an independent context and explicit write scope, coordinates document-based handoffs, and verifies the result. Small tasks stay in the current session.

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
