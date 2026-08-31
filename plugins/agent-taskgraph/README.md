# Agent TaskGraph

Native multi-agent orchestration for Codex and Claude Code.

Source version: [`v0.8.0-beta.17`](../../VERSION) | License: [Apache-2.0](../../LICENSE)

The Skill keeps small tasks in the current session and uses native Agents only when independent work can run in parallel. Codex uses native subagents. Claude Code defaults to subagents and uses Agent Teams only when teammates need to coordinate with each other.

Workers receive self-contained assignments, minimal context, explicit write ownership, and acceptance checks. Parallel writers need separate worktrees or disjoint paths. The main session verifies the integrated diff and tests.

Optional durable state preserves task facts and handoffs; it does not promise that native Agent threads or teammates survive a client restart.

## Usage

```text
Use agent-taskgraph for this task. Use native Agents when parallel work is worthwhile; otherwise finish in the current session. Isolate writes and verify the final result.
```

Durable project state is optional. Initialize it only for resumable, cross-session, or auditable work:

```bash
~/.codex/skills/agent-taskgraph/init.sh /path/to/project
# or ~/.claude/skills/agent-taskgraph/init.sh /path/to/project
```

See the repository [README](../../README.md) for installation, runtime selection, assignment contracts, and safety boundaries.
