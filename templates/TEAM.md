# Team Charter

> Lead-maintained source of truth for the current Team contract and Roster.
> Keep field names in English; values may use the project's primary language.

## Charter

| Field | Value |
|---|---|
| Protocol version | <Agent TaskGraph version> |
| Team ID | <short stable id> |
| Created at | <ISO 8601 timestamp> |
| Updated at | <ISO 8601 timestamp> |
| Outcome | <one observable integrated result> |
| Non-goals | <explicit exclusions> |
| Mode | Team |
| Topology | <hub-and-spoke / peer-capable> |
| Native runtime | <Codex subagents / Claude subagents / Claude Agent Teams> |
| Lead | <coordinating session> |
| Integrator | <Lead or assigned Member> |
| Lifecycle phase | forming |
| Definition of done | <integrated acceptance> |
| Human Gates | <none / permissions, migration, deletion, release, other> |

## Roster

| Member | Role | Responsibility | Current Task | Native session/thread | Worktree/Writes | Status |
|---|---|---|---|---|---|---|

Status: `planned / ready / active / blocked / idle / stopped / failed`.

## Decision boundaries

- Member decides: implementation details inside its Task contract.
- Lead decides: ownership, dependencies, integration, and cross-Task conflicts.
- Human Gate decides: permission expansion and listed external side effects.

## Collaboration events

- `READY <task-id>`: contract understood and dependencies satisfied.
- `BLOCKED <task-id>`: fact, attempts, requested decision/deliverable, impact.
- `HANDOFF <task-id>`: result, paths, verification, risks, downstream notes.
- `REVIEW <task-id>`: pass/changes required, evidence, correction boundary.
