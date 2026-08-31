# Agent TaskGraph

Build goal-driven native Agent Teams in Codex and Claude Code.

Source version: [`v0.8.0-beta.18`](../../VERSION) | License: [Apache-2.0](../../LICENSE)

Agent TaskGraph chooses Solo, Delegation, or Team mode. A Team has a shared outcome, explicit roles, a dependency-aware task graph, collaboration events, write ownership, integrated acceptance, and a complete lifecycle.

Codex maps Teams to Lead-centered native subagents. Claude Code uses subagents for Lead-centered Teams and Agent Teams only when teammates need peer collaboration. No external orchestration service is required.

## Usage

```text
Use agent-taskgraph to form a development team for this request. Define the shared outcome, roles, task graph, collaboration protocol, lifecycle, write ownership, and definition of done, then execute with native Agents and integrate the result.
```

Durable Team state is optional. Initialize it for cross-session, dependency-heavy, or auditable Teams:

```bash
~/.codex/skills/agent-taskgraph/init.sh /path/to/project
# or ~/.claude/skills/agent-taskgraph/init.sh /path/to/project
```

See the repository [README](../../README.md), the Team protocol, and native runtime mapping for details.
