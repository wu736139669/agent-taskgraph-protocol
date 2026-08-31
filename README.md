![Agent TaskGraph](promo/agent-taskgraph-hero.svg)

[English](README.md) | [中文](README.zh-CN.md)

# Agent TaskGraph

**Native multi-agent orchestration for Codex and Claude Code.**

Version: [`v0.8.0-beta.17`](VERSION) | License: [Apache-2.0](LICENSE)

Agent TaskGraph helps the current session decide whether a task is worth parallelizing, then uses the host's built-in Agent capabilities to delegate, supervise, and verify the work. It does not run a second orchestration service, and it does not require project-state files for every task.

## What is different

- **Single Agent first:** small work stays in the current session.
- **Native execution only:** Codex uses native subagents. Claude Code defaults to subagents and uses Agent Teams only when teammates need to coordinate with each other.
- **No idle coordinator:** the main session may complete a non-overlapping task while Workers run. It becomes lead-only only when requested or required by risk.
- **Minimal context:** Workers receive self-contained assignments instead of the complete conversation.
- **Write isolation:** parallel writers need separate worktrees or disjoint paths.
- **Optional durable state:** `.agent-taskgraph/` is reserved for resumable, cross-session, or auditable work.
- **Native supervision:** use the host's spawn, message, wait, resume, and stop capabilities instead of duplicating session state.

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

It refuses to overwrite unrelated paths. Use `./install.sh --force` only when you want it to back up and replace a conflict.

## Use

Say this in Codex or Claude Code:

```text
Use agent-taskgraph for this task. Use the current host's native Agents when parallel work is worthwhile; otherwise finish in the current session. Isolate parallel writes and verify the final diff and tests.
```

When you explicitly want approval before delegation:

```text
Use agent-taskgraph. First show the execution mode, task split, write boundaries, and acceptance checks, then wait for my confirmation.
```

The Skill reads the project first, then chooses:

| Situation | Mode |
|---|---|
| Small fix, one module, or sequential work | Current session |
| Two or more independent research or implementation tasks | Native subagents |
| Claude teammates must discuss or claim shared work | Claude Agent Teams |
| Native delegation or safe write isolation is unavailable | Current session fallback |

## Codex

Codex uses the native subagent or Agent-thread tools exposed by the current client. Every Agent receives a self-contained assignment. When the spawn interface exposes context-inheritance controls, the Skill selects blank or minimal context rather than copying the entire parent conversation.

An independent Agent thread does not necessarily mean an independent worktree. Parallel writers must have observed isolation or explicitly disjoint file ownership. The main session supervises through native Agent status, messages, and waits, and continues an incomplete result in the original thread when possible.

## Claude Code

Focused implementation, exploration, testing, and review default to subagents. Custom subagents can define tools, permissions, skills, and worktree isolation in `.claude/agents/`.

Agent Teams are reserved for work where teammates must message each other, share a task list, or coordinate decisions. If Agent Teams are unavailable or unsafe for the current write layout, the Skill uses subagents or the current session instead of pretending that a multi-session team exists.

## Assignment contract

Each Worker receives only the facts needed to begin:

1. One observable outcome
2. Three to six required paths, symbols, or direct handoffs
3. Allowed writes and explicit exclusions
4. Real dependencies
5. A command or observable acceptance check
6. A final summary, changed paths, verification, and remaining risks

Workers do not commit, merge, tag, push, or release by default. Final Git operations and external side effects stay with the main session and the user's existing authorization.

## Optional durable state

Ordinary one-session work needs no initialization. For cross-session recovery, complex dependencies, or an audit trail, run:

```bash
./init.sh /path/to/project
```

This creates:

```text
.agent-taskgraph/
├── PROJECT.md
├── PLAN.md
├── TEAM.md
├── STATUS.md
├── DECISIONS.md
├── tasks/TEMPLATE.md
└── archive/
```

An old `.agent-queue` directory can be migrated explicitly:

```bash
./init.sh --migrate /path/to/project
```

Migration renames the directory and fills in missing minimal templates without rewriting existing content.

Durable state restores task facts and handoffs, not live Agents. Codex subagent threads and Claude teammates must not be assumed to survive a client restart or main-session resume. A new session checks the real native state first, then resumes or recreates work from the handoff.

## Permissions and cost

The Skill inherits the current host's model, reasoning, and permissions. It does not hardcode model names or enable bypass, sandbox-free, or `--yolo` modes. If Workers would inherit unusually broad parent permissions, the Skill discloses that once before the first spawn. Multi-agent execution does not expand authorization for installation, network writes, migrations, deletion, merge, tags, pushes, or releases.

Agent Teams and large parallel batches consume more tokens. The default is only two or three Agents with real independent work, never a fixed organization chart with idle roles.

## Validate and update

```bash
./tests/smoke.sh
./install.sh --check-update
```

The update check is read-only and never modifies the active installation. See [`SKILL.md`](SKILL.md) for the full protocol and [`references/native-runtimes.md`](references/native-runtimes.md) for runtime selection details.
