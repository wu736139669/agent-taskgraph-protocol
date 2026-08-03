[English](README.md) | [中文](README.zh-CN.md)

# agent-queue

Multi-agent **team orchestration**: a PMO/secretary session commands a team of independent agents (Claude or Codex) to get work done. Vague requirements flow through a pipeline — product architect → tech architect → specialized workers → reviewer — backed by a ledger-based state machine, executable acceptance gates, log-based retries, and a reviewer gate before merge.

> Positioning: an **operating model + process definitions + scripts**, not a project-specific solution. Any agent (Claude or Codex) on any machine can run this team by reading `SKILL.md`.

## How to use

**Trigger**: in a Claude Code or Codex session, say "use agent-queue to dispatch work" (or trigger keywords: dispatch / task queue / multi-agent coding / orchestrate). The session agent becomes the PMO and runs the team per SKILL.md.

**As the boss, you only do three things**:
1. **Give requirements** — one sentence is fine; vagueness is fine too (vague inputs make the PMO assemble a product architect to produce a PRD)
2. **Approve PROJECT.md** — the PMO auto-analyzes the project on first contact (stack / roles / conventions); you just approve, never write it
3. **Final review** — visual / product / release decisions that machines can't judge stay with you

**Three typical scenarios**:

| You say | The PMO does |
|---|---|
| "Add a year filter to book-reader" | Triage → single task → do it directly or dispatch one worker → verify & report |
| "Dispatch these 5 requirements together" | Conflict-surface analysis → parallel / serial grouping → multiple workers at once |
| "Polish 5 games until App Store ready" | Decompose → assemble experts (product / tech) → pipeline execution → stage-wise acceptance |

## What you get

| Your need | How this system delivers |
|---|---|
| Stop babysitting every agent session | PMO is the single interface; proactively monitors (logs + ledger); only pings you on completion / stuck / decision |
| Parallel dev without stepping on each other | One task = one worktree (isolated dir + branch) |
| No permission-prompt interruptions | Workers always run `--yolo`; safety comes from structure (Goal Frozen + worktree isolation + reviewer gate) |
| Don't trust "it's done" | Three-stage acceptance: worker self-check → reviewer → your final call; command output counts |
| No arbitrary session churn | Persistence is the norm (ledger / decisions); session switches only for isolation / failure / your request |
| No memory loss across sessions | Durable files are the source of truth (SESSION_CONTINUITY philosophy), not chat memory |
| Team that learns the project | Decisions log + role memory keep accumulating |
| No stuck workers going unnoticed | PMO actively checks log silence; every wait has ownership; stalemates are visible at a glance |

## Team structure (see SKILL.md §0)

| Role | Form | Job |
|---|---|---|
| PMO / Secretary | Always-on, single interface | Triage → assemble team → decompose / orchestrate → dispatch → follow up → verify → close → report (never writes code) |
| Expert roles (on-demand) | Defined per project | Turn vague input into executable specs (PRD / tech plan / art direction / …) |
| Workers (specialized) | Independent sessions ×N | Execute Goals (roles defined per project) |
| Reviewer | Spawned for acceptance | Reviews diffs + reruns acceptance commands |

Expert roles are a **mechanism, not fixed job titles**: the PMO defines them per project (in PROJECT.md); roles listed in SKILL.md are examples only. Small tasks only need "PMO + worker".

## Directory layout

```
agent-queue/
├── SKILL.md                # ★ Skill definition (full team operating model)
├── README.md               # This file
├── templates/
│   ├── PROJECT.md          # Project profile (stable facts, workers read first)
│   ├── STATUS.md           # Task board (refreshed on every state change)
│   ├── DECISIONS.md        # Decision log (append-only team memory)
│   ├── goal.md             # ★ Goal dispatch template (legal terminal / evidence chain / Frozen / Estimate)
│   ├── ledger.md           # Ledger entry format (state flow, PMO-only writes)
│   └── report.md           # Completion report format (one page)
├── queue/                  # Ledger state machine (filesystem as memory)
│   ├── inbox/ active/ review/ done/ failed/
│   └── <one dir per task: goal.md + ledger.md + report.md>
└── workers/
    ├── watch-worker.sh     # Optional: tail worker logs as event stream (real-time needs)
    ├── log-cleanup.sh      # Session-log hygiene (dry-run by default)
    ├── dispatch.sh         # TODO: poll inbox → dispatch → archive
    └── run-worker.sh       # TODO: spawn a worker (hapi / claude -p / codex exec)
```

## Workflow (see SKILL.md)

1. **Triage** (30s): form (single / big goal / multiple / mixed) + two sensitivities (vagueness → product architect; architecture sensitivity → tech architect)
2. **Assemble team**: on-demand expert roles; unqualified outputs are bounced back
3. **Decompose / Orchestrate**: four decomposition dimensions (module / pipeline / role / risk) or orchestration (conflict-surface analysis + grouping)
4. **Assign & dispatch**: relevance → role match → load balance; one task = one Goal = one worktree; workers default to independent visible sessions (HAPI) with `--yolo`; related tasks reuse sessions (`hapi resume`); fresh sessions only on first work or failure
5. **Follow up**: **PMO must create a real monitoring mechanism at kickoff** — Codex automation / background task / cron (per PROJECT.md local environment), registered with ID + interval; **no mechanism evidence = not started**. Each cycle it checks worker log tails + ledger; silence = stuck signal; broken mechanism (restart/deleted) → rebuild when stale ledger is noticed; boss gets a STATUS.md summary on request
6. **Accept**: three gates — worker self-check (command output) → reviewer → boss final review
7. **Retry**: fresh session with error log, max 3 times
8. **Merge gate**: dependency-ordered merges with regression after each; reviewer gate stays before auto-merge

## Reporting (three levels, no spam)

| Level | Trigger | Content |
|---|---|---|
| **Routine progress** | Key nodes: new worker starts / fault handled / milestone / stuck / waiting on decision | One-line ping to boss: what's happening / why / next — no need for boss to ask (boss not knowing is also a gap) |
| Completion report | After each task acceptance | One page (templates/report.md): what / evidence / risk / next |
| Exception report | Retry limit hit, vague requirement, boss decision needed | Immediate, with suggested options |
| Batch summary | End of a batch | Table: task / status / time / cost |

## Principles (from real battles)

- Acceptance = runnable commands + checkable artifacts; "agent says done" doesn't count; **data-level equality over byte-level**
- No orchestration for small tasks; PMO never writes code
- Workers never change the plan on the fly — report plan issues to PMO; unqualified expert outputs get bounced
- One task = one worktree; ledger lives on the filesystem; only PMO changes state
- Failure = fresh session with the error log, not PMO fixing in place
- **PMO proactive monitoring is the first line of defense**; worker completion pings are accelerators; boss checking STATUS.md is the last resort — three layers against the "worker done, PMO idle" stalemate
- Conflicts are solved by PMO before dispatch, never between workers on the fly
- Reviewer gate stays before auto-merge
- Monitoring relies on mechanisms, not intentions: "do X every N minutes" needs a real timer or event stream, or it will never happen
- **Session = project**: one PMO session serves one project (switch = new session); kickoff loads only current scope (PROJECT + STATUS + related goals/decision titles), history is never loaded; STATUS.md holds active tasks only (done = removed)

## Install (other machines / sharing)

```bash
git clone https://github.com/wu736139669/agent-queue.git agent-queue
cd agent-queue && ./install.sh
```

`install.sh` symlinks both skill dirs (Claude Code `~/.claude/skills/agent-queue` + Codex `~/.codex/skills/agent-queue`) to the same source — edit once, both sides see it.

> Note: what's distributed is the **operating model** (templates + rules + empty queue). Instance data (task archives) lives in each project's own `.agent-queue/` and is not shipped with the skill.

## Roadmap

- [ ] `workers/dispatch.sh` + `run-worker.sh` (dispatch automation)
- [ ] ledger.json metrics (rounds per task, pass rate, token cost) to evaluate PMO decomposition quality
