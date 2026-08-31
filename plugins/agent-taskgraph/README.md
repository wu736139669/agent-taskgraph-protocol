# Agent TaskGraph

Build goal-driven native Agent Teams in Codex and Claude Code.

Source version: [`v0.8.0-beta.19`](../../VERSION) | License: [Apache-2.0](../../LICENSE)

## Quick start

```text
Use agent-taskgraph to form a development team for this request.
Define the shared outcome, Roles, Task Graph, collaboration protocol,
write ownership, lifecycle, and Definition of done, then execute and integrate
with the current host's native Agents.
```

Agent TaskGraph selects Solo, Delegation, or Team. A Team has an Outcome, dynamic Roles, dependency-aware Tasks, `READY / BLOCKED / HANDOFF / REVIEW` events, explicit write ownership, and a complete lifecycle.

Codex maps Teams to Lead-centered native subagents. Claude Code uses subagents for Lead-centered Teams and Agent Teams only when Members need peer collaboration. No external orchestration service is required.

Durable Team state is optional:

```bash
~/.codex/skills/agent-taskgraph/init.sh /path/to/project
# or ~/.claude/skills/agent-taskgraph/init.sh /path/to/project
```

## Documentation

- [Repository README](../../README.md)
- [Skill entrypoint](skills/agent-taskgraph/SKILL.md)
- [Team protocol](skills/agent-taskgraph/references/team-protocol.md)
- [Native runtime mapping](skills/agent-taskgraph/references/native-runtimes.md)
- [Development Team example](skills/agent-taskgraph/references/development-team-example.md)
