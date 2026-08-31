![Agent TaskGraph](promo/agent-taskgraph-hero.svg)

[English](README.md) | [中文](README.zh-CN.md)

# Agent TaskGraph

**Build native Codex and Claude Code Agent Teams with a shared outcome, roles, task relationships, a collaboration protocol, and a lifecycle.**

Version: [`v0.8.0-beta.19`](VERSION) | License: [Apache-2.0](LICENSE)

Agent TaskGraph makes the current session the Lead, selects Solo, Delegation, or Team mode, and uses the host's native Agents to form the team, delegate work, coordinate Handoffs, review changes, and integrate the result. It runs no external orchestration service.

## Start in 60 seconds

### 1. Install

```bash
git clone https://github.com/wu736139669/agent-taskgraph-protocol.git
cd agent-taskgraph-protocol
./install.sh
./install.sh --status
```

The same Skill is linked into:

- `~/.codex/skills/agent-taskgraph`
- `~/.claude/skills/agent-taskgraph`

### 2. Form a development team

```text
Use agent-taskgraph to form a development team for this request.
Understand the project, define the shared outcome, roles, task dependencies,
write boundaries, and definition of done, then execute, hand off, review,
and integrate the work with the current host's native Agents.
```

The Lead produces a preview such as:

```text
Mode and topology: Team / hub-and-spoke
Team outcome: ...
Members: Lead/Integrator, Backend Builder, Frontend Builder, Reviewer
Task relationships: T1 → T2/T3 → T4 Review → T5 Integration
Definition of done: integration tests, build, and risk checks pass
```

Invoking the Skill authorizes reasonable internal team formation. Only product decisions, permission expansion, or external side effects require additional confirmation.

## Three modes

| Mode | Use when | Shape |
|---|---|---|
| **Solo** | Small fix, one module, or sequential work | Current session |
| **Delegation** | Independent branches only need to report to the Lead | Lead + native Members |
| **Team** | Shared outcome, role collaboration, dependencies, or cross-module integration | Team Charter + Task Graph + lifecycle |

### Do not form a Team for appearances

Use Solo or Delegation when:

- the work cannot produce two independent, testable outputs
- Members would edit the same files concurrently
- coordination costs more than the work itself
- the request is too unclear to define Task Acceptance

## Five parts of a Team

1. **Outcome:** the shared result, Non-goals, and Definition of done.
2. **Roles:** Lead, Integrator, and the Builders, Specialists, or Reviewers required by current Tasks.
3. **Task Graph:** Owner, Needs, Produces, Consumer, Writes, and Acceptance.
4. **Collaboration:** `READY / BLOCKED / HANDOFF / REVIEW`.
5. **Lifecycle:**

```text
forming → briefing → executing → reviewing → integrating → complete/stopped
```

A default Team has two to four active Members including the Lead. No real Task means no corresponding Member.

## Complete development example

[`references/development-team-example.md`](references/development-team-example.md) follows an asynchronous report-export feature through the full Team lifecycle:

```text
T1 API contract
 ├─ T2 Backend implementation
 └─ T3 Frontend implementation
       ↓
T4 Independent review
       ↓
T5 Integration and team acceptance
```

The example includes the Team Charter, Roster, Task Graph, assignment contract, blocker, Handoff, Review, and completion report.

## Native runtimes

### Codex

A Codex Team defaults to `hub-and-spoke`: the main thread is Lead and native subagents/Agent threads are Members. The Lead manages dependencies through Task contracts, artifacts, and Handoffs without assuming peer messaging.

### Claude Code

- **Subagents:** Lead-centered Teams.
- **Agent Teams:** only when Members must message each other, claim shared tasks, or coordinate decisions.

A logical Team is not synonymous with Claude Agent Teams. If Agent Teams are unavailable, subagents can still implement a Lead-centered Team.

## Writes, Git, and permissions

- Parallel writers use separate worktrees or disjoint paths.
- A file, generated artifact, or migration state has one Owner at a time.
- Members do not commit, merge, rebase, tag, push, or release by default.
- The Integrator owns the final diff, conflict resolution, and team-level verification.
- Multi-agent execution never expands current permissions or authorization for external effects.

## Optional durable state

Short Teams use native tasks and messages. For cross-session work, important dependencies, or an audit trail, run:

```bash
./init.sh /path/to/project
```

```text
.agent-taskgraph/
├── PROJECT.md       # stable project facts
├── TEAM.md          # Team Charter and Roster
├── PLAN.md          # Task Graph and integration path
├── STATUS.md        # lifecycle, progress, and blockers
├── DECISIONS.md     # decisions that changed the team contract
├── tasks/<id>.md    # one Task contract and Handoff
└── archive/         # ended Team batches
```

Templates use stable English field names; values can use the project's primary language. Durable files restore team facts, not presumed-live Agents.

## Documentation map

| Document | Read when |
|---|---|
| [`SKILL.md`](SKILL.md) | Skill routing and non-negotiable constraints |
| [`references/team-protocol.md`](references/team-protocol.md) | Entering Team mode |
| [`references/native-runtimes.md`](references/native-runtimes.md) | Creating or controlling native Members |
| [`references/development-team-example.md`](references/development-team-example.md) | Learning the complete end-to-end flow |
| [`templates/`](templates/) | Persisting Team state across sessions |

## Validate and update

```bash
./tests/smoke.sh
python3 ./scripts/check-docs.py
./install.sh --check-update
```
