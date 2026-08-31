# Team Charter

> Maintained by the Lead. Record the logical team and observed native sessions, not requested or imagined state.

## Charter

| Field | Value |
|---|---|
| Team ID | <short stable id> |
| Team outcome | <one observable integrated result> |
| Non-goals | <explicit exclusions> |
| Mode | Team |
| Topology | <hub-and-spoke / peer-capable> |
| Native runtime | <Codex subagents / Claude subagents / Claude Agent Teams> |
| Lead | <coordinating session> |
| Integrator | <Lead or assigned member> |
| Lifecycle phase | forming |
| Team done when | <integrated acceptance> |
| Human gates | <none / permissions, migration, deletion, release, other> |

## Roster

| Agent | Role | Responsibility | Current Task | Native session/thread | Worktree/write scope | Status |
|---|---|---|---|---|---|---|

Status: `planned / ready / active / blocked / idle / stopped / failed`.

## Decision boundaries

- Member decides: implementation details inside its Task contract.
- Lead decides: scope allocation, dependencies, integration, cross-Task conflicts.
- Human Gate decides: permission expansion and external side effects listed above.

## Collaboration events

- `READY <task-id>`: assignment understood and dependencies satisfied.
- `BLOCKED <task-id>`: blocking fact, attempts, requested decision/deliverable, impact.
- `HANDOFF <task-id>`: result, paths, verification, risks, downstream notes.
- `REVIEW <task-id>`: pass/changes required, evidence, minimal correction boundary.
