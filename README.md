![Agent TaskGraph](promo/agent-taskgraph-hero.svg)

[English](README.md) | [中文](README.zh-CN.md)

# Agent TaskGraph Protocol

**Native multi-session task orchestration for Codex and Claude Code.**

Source version: [`v0.8.0-beta.16`](VERSION) | License: [Apache-2.0](LICENSE)

Agent TaskGraph is a lightweight graph-engineering protocol for a **PMO-led native Agent Team**. The current Codex or Claude Code session understands the request, asks only the decisions that cannot be inferred from the repository, creates a small task graph, starts native Agent sessions when parallel work is real, and verifies the result.

It is a protocol and skill, not a hosted scheduler. HAPI is an optional adapter for users who explicitly need cross-machine control. It is disabled in the normal workflow.

## What It Solves

- Complex requests are clarified before implementation starts.
- Each worker is a separate native Codex thread or Claude Code session with its own context.
- Workers receive one role, one task, one write boundary, and a short context contract.
- Workers hand off through project documents, not copied chat history.
- The PMO owns planning, dispatch, supervision, integration, acceptance, and the user report.
- Small tasks stay in the current session, so multi-agent overhead is not added without benefit.

## Quick Start

### Install

```bash
git clone https://github.com/wu736139669/agent-taskgraph-protocol.git
cd agent-taskgraph-protocol
./install.sh
./install.sh --status
```

The installer links the skill into both supported hosts:

- Claude Code: `~/.claude/skills/agent-taskgraph`
- Codex: `~/.codex/skills/agent-taskgraph`

Existing non-symlink paths are refused. Use `./install.sh --check-update` to check the configured remote without changing files.

### Initialize a project

```bash
./init.sh /path/to/your-project
```

The new lightweight state is:

```text
.agent-taskgraph/
├── PROJECT.md       # stable project facts, commands, constraints
├── PLAN.md          # current task graph and dependencies
├── TEAM.md          # durable roles and native session/thread IDs
├── STATUS.md        # progress, blockers, next action
├── DECISIONS.md     # owner and PMO decisions
├── tasks/<id>.md    # one task and handoff per worker
└── archive/         # completed task records
```

Initialization preserves existing files. Existing beta queue projects can be initialized with the compatibility layout using `./init.sh --legacy-queue <project>`; do not use that option for a new project unless an old validator or migration requires it.

### Start the skill

Open Codex or Claude Code in the target project and say:

```text
Use agent-taskgraph. Understand this project and request first. If parallel work is worthwhile, act as PMO and create native Codex/Claude sessions with separate contexts, shared-document handoffs, and final acceptance. Otherwise finish in the current session. Show me the understanding and team split before starting.
```

That is enough. The PMO reads the repository first, then reports:

```text
Understanding: ...
Decisions needed: ... (0-3 blocking questions)
Plan: current session / PMO + N native Agents
```

After the user confirms, the PMO creates the sessions and begins dispatch. Users do not need to provide Goal IDs, session IDs, worktree paths, wait commands, or HAPI settings.

## How A Batch Works

1. **Discover**: PMO reads project rules, relevant code, tests, and build commands.
2. **Clarify**: unresolved product or risk decisions are presented with a recommended default.
3. **Plan**: PMO writes `PROJECT.md`, `PLAN.md`, `TEAM.md`, and one `tasks/<id>.md` per worker.
4. **Preview**: the user sees each role, task, native session type, model/effort, effective permission, visibility, worktree, and write scope once.
5. **Dispatch**: Codex uses native Agent threads; Claude Code uses Agent Teams for an active coordinated batch, Agent View background sessions for durable workers, and subagents only for bounded side tasks.
6. **Handoff**: a worker writes a short result, changed paths, revision/diff, verification, and risks into its task file.
7. **Accept**: PMO checks the diff and runs the project verification commands. An independent reviewer is added only for risky or cross-module work.
8. **Report**: PMO updates status, archives completed task files, and summarizes the result to the user.

## Context Isolation

Every Agent has an independent conversation context. A worker reads only:

- applicable `AGENTS.md` or `CLAUDE.md`
- the relevant part of `.agent-taskgraph/PROJECT.md`
- its own `.agent-taskgraph/tasks/<id>.md`
- direct dependency handoffs
- source files found by targeted search

The PMO does not paste its full conversation into worker prompts. When the host offers history/context forking, the PMO explicitly selects a blank or minimal task context; it never relies on a default full-history fork. Stable facts live in documents, so long projects do not repeatedly pay for the same context.

## Roles

The PMO defines roles from the actual project instead of using a fixed team. Typical roles include frontend, backend, data, test, research, or reviewer. A durable role may be recorded in `TEAM.md` and reused across tasks, but each new task still gets a fresh scope and handoff. No Agent is created without a current task.

The PMO itself does not implement product code while the team is running. It coordinates, resolves dependencies, reviews evidence, and accepts or rejects work.

## Codex And Claude Code

### Codex

Use Codex's native subagent/thread capability. These are Agent threads inside the current Codex client, not separate terminal windows. In the CLI, `/agent` shows and switches threads; App/IDE uses the Agent panel. Native threads do not prove worktree isolation, so concurrent writers need an observed worktree or non-overlapping paths. Durable roles can be defined in `.codex/agents/`.

### Claude Code

For a PMO-led coordinated batch, prefer Claude **Agent Teams** when the experimental feature is enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). The lead is the PMO and teammates are independent Claude Code sessions with separate contexts. The default display is the in-process Agent panel, not one Terminal window per Agent.

Use **Agent View background sessions** for durable, resumable workers that need independent worktrees or may outlive the PMO session. `claude agents` is the management screen; sessions run under the background supervisor and can be attached later. Use **subagents** only for short exploration, tests, log analysis, or review. If Agent Teams are unavailable, the skill reports the actual downgrade instead of silently calling subagents a multi-session team.

Visible tmux/iTerm2 panes are opt-in. HAPI is not used as a fallback.

If the host cannot create or observe native Agents, the skill clearly falls back to one current session.

## Permissions

Permissions are part of the one-time team preview. The PMO records the effective mode observed after launch, not only the requested value.

| Role | Claude Code | Codex |
|---|---|---|
| Explorer/Reviewer | `plan` or read-only tools | `read-only` |
| Implementation Worker | isolated worktree + `acceptEdits`/`auto` | `workspace-write + on-request` |
| Unattended bounded Worker | `dontAsk` + exact allowlist | `workspace-write + never` |
| Migration/release | normal prompts + Human Gate | `on-request` + Human Gate |

`bypassPermissions`, `danger-full-access + never`, and `--yolo` require explicit owner authorization and an externally isolated environment. If the parent session already uses Full Access/Yolo, the PMO warns once that native workers will inherit it.

## When To Use One Agent

Stay in the current session for a small bug, one file, one module, sequential work, or work with overlapping write scope. Use multiple sessions only when at least two tasks can proceed independently and be verified independently. More sessions are not automatically better.

## HAPI: Optional Advanced Adapter

HAPI is not required and is not probed or configured by default. Request it explicitly only for cross-machine control, remote terminals, or a unified external control plane. If HAPI is unavailable or fails, return to native Codex/Claude or the single-session path instead of entering a HAPI recovery loop.

## Updates

The owner session may run:

```bash
./install.sh --check-update
```

The check is read-only. An update notice recommends a command; it never pulls code, replaces a live skill, or restarts a running session. Finish the current batch on its recorded protocol version, then update before the next batch.

## Beta Boundaries

This is a public beta. It depends on the native multi-agent capabilities exposed by the installed Codex or Claude Code version. It does not provide an unattended cloud queue, guarantee identical UI behavior across hosts, or bypass project permission gates. Review migrations, deletion, privilege expansion, merges, and releases as human-owned gates.

## License

Apache License 2.0. See [LICENSE](LICENSE).
