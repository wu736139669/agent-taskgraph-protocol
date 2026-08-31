![Agent TaskGraph](promo/agent-taskgraph-hero.svg)

[English](README.md) | [中文](README.zh-CN.md)

# Agent TaskGraph

**Build native Codex and Claude Code Agent Teams with a shared goal, roles, task relationships, a collaboration protocol, and a lifecycle.**

Version: [`v0.8.0-beta.18`](VERSION) | License: [Apache-2.0](LICENSE)

Agent TaskGraph does more than launch several Agents in parallel. The current session becomes the Lead, selects Solo, Delegation, or Team mode, forms the team, assigns roles, manages task dependencies, supervises handoffs, organizes review, integrates the result, and disbands the team.

It uses only the current host's native Agent capabilities and runs no external orchestration service.

## Three execution modes

| Mode | Use when | Shape |
|---|---|---|
| **Solo** | Small fix, one module, or sequential work | Current session |
| **Delegation** | Independent branches only need to report to the Lead | Lead + native subagents |
| **Team** | Shared outcome, role collaboration, task dependencies, or cross-module integration | Team Charter + roles + task graph + lifecycle |

An explicit request to “form a team” selects Team mode unless native Agents are unavailable, the work cannot be safely decomposed, or writes cannot be isolated.

## What makes a Team

### Shared outcome

The team has one observable integrated result, explicit non-goals, and a team-level definition of done.

### Roles

- **Lead:** formation, assignment, dependencies, decisions, supervision, and integration.
- **Builder / Specialist:** owns one bounded Task at a time.
- **Reviewer:** independently reviews according to risk without reimplementing the task.
- **Integrator:** consumes handoffs, resolves conflicts, and runs team-level acceptance; normally the Lead.

Roles are created from real work. A default Team has two to four active members including the Lead, never idle members added to fill an organization chart.

### Task relationships

Every Task records:

```text
Owner / Role / Goal / Needs / Produces / Consumer / Writes / Acceptance
```

Independent Tasks can run in parallel. Dependent Tasks wait for handoffs. Shared writes run sequentially or in isolated worktrees.

### Collaboration protocol

Teams use four concise semantic events:

- `READY`: the assignment is clear and executable.
- `BLOCKED`: the blocker, attempts, and required decision or deliverable.
- `HANDOFF`: result, paths, verification, risks, and downstream notes.
- `REVIEW`: pass or changes-required with evidence.

### Lifecycle

```text
forming → briefing → executing → reviewing → integrating → complete/stopped
```

A Team is complete only after critical Tasks reach terminal states, handoffs are consumed, integration checks pass, risks are disclosed, and unused Agents are ended.

## Codex and Claude Code

### Codex

A Codex Team defaults to a **Lead-centered hub-and-spoke topology**: the main thread is Lead and native subagents/Agent threads are members. Peer messaging is not required; the Lead coordinates dependencies through assignment contracts, artifacts, and handoffs.

### Claude Code

- **Subagents:** Lead-centered Teams for development, research, and review.
- **Agent Teams:** only when teammates must message each other, claim shared tasks, or coordinate decisions.

A logical Team is not synonymous with Claude Agent Teams. If Agent Teams are unavailable, subagents can still implement a Lead-centered Team.

## Write and Git ownership

- Parallel writers use separate worktrees or disjoint paths.
- A file, generated artifact, or migration state has one Owner at a time.
- Workers do not commit, merge, rebase, tag, push, or release by default.
- The Integrator owns the final diff, conflict resolution, and team-level verification.
- Multi-agent execution never expands existing permissions or authorization for external effects.

## Install

```bash
git clone https://github.com/wu736139669/agent-taskgraph-protocol.git
cd agent-taskgraph-protocol
./install.sh
./install.sh --status
```

The installer links the same Skill into:

- `~/.codex/skills/agent-taskgraph`
- `~/.claude/skills/agent-taskgraph`

## Use

Form a development team:

```text
Use agent-taskgraph to form a development team for this request. Understand the project, establish the shared outcome, roles, task dependencies, write boundaries, and definition of done, then use the current host's native Agents to execute, hand off, review, and integrate the work.
```

Use independent delegation only:

```text
Use agent-taskgraph. Delegate independent branches to native subagents; the main session will synthesize and verify them. The members do not need to collaborate with each other.
```

Let the Skill choose:

```text
Use agent-taskgraph for this task. Choose Solo, Delegation, or Team based on the work. Isolate parallel writes and verify the integrated result.
```

## Optional durable Team state

Short Teams can use only native tasks and messages. For cross-session work, important dependencies, or an audit trail, run:

```bash
./init.sh /path/to/project
```

This creates:

```text
.agent-taskgraph/
├── PROJECT.md
├── TEAM.md          # Team Charter and roster
├── PLAN.md          # Task graph and dependencies
├── STATUS.md        # Team lifecycle
├── DECISIONS.md
├── tasks/TEMPLATE.md
└── archive/
```

Durable state restores team facts and handoffs, not presumed-live Agents. A new Lead session checks native state first, then resumes or recreates members.

## Team presets

These are starting points, not fixed organization charts:

- **Development Team:** Lead/Integrator, module Builders, and risk-driven Reviewers.
- **Research Team:** Lead/Synthesizer and Researchers divided by question domain.
- **Review Team:** Lead and read-only Reviewers divided by correctness, security, testing, or product intent.

## Validate and update

```bash
./tests/smoke.sh
./install.sh --check-update
```

See [`SKILL.md`](SKILL.md) for the entrypoint, [`references/team-protocol.md`](references/team-protocol.md) for the Team contract, and [`references/native-runtimes.md`](references/native-runtimes.md) for runtime mapping.
