---
name: agent-taskgraph
description: "在 Codex 或 Claude Code 中建立有共同目标、角色、任务关系、协作协议和生命周期的原生 Agent Team，并负责拆分、并行、监督、交接、审查与集成。适用于用户明确要求 Agent Team、多 Agent、subagents、任务图、PMO、并行开发，或复杂工作存在多个可独立推进且需要协调的任务；简单任务仍由当前会话完成。"
---

# Agent TaskGraph

使用当前宿主的原生 Agent 能力完成工作。Team 是逻辑协作模型，不等同于“启动多个进程”，也不需要外部控制面或自建队列。

## 1. 选择最小有效模式

先读适用的 `AGENTS.md` / `CLAUDE.md`、相关代码和验证命令。

| 模式 | 选择条件 | 形态 |
|---|---|---|
| **Solo** | 小修复、单模块、顺序工作，拆分收益低 | 当前会话直接完成 |
| **Delegation** | 多个独立支线只需分别交给 Lead | Lead + 原生 Members |
| **Team** | 有共同目标、角色协作、任务依赖、共同决策或跨模块集成 | Team Charter + Task Graph + 协作协议 + 生命周期 |

用户明确要求“组团队”时优先使用 **Team**。只有原生 Agent 不可用、任务无法拆出独立职责，或写入无法安全隔离时才降级，并说明原因。

默认包含 Lead 在内共 2-4 个有真实职责的 active Members。不要为组织结构完整而创建空闲 Agent。调用本 Skill 已授权合理的内部拆分和原生 Agent 创建；只有代码无法回答的产品决策、权限扩大或外部副作用需要提问。用户明确要求先看分工时才等待确认。

## 2. 建立 Team

Team 必须具备：

1. 一个可观察的共同目标、非目标和完成条件。
2. Lead、Integrator 和当前任务真正需要的执行/审查 Roles。
3. 包含 Owner、Needs、Produces、Consumer、Writes、Acceptance 的 Task Graph。
4. `READY / BLOCKED / HANDOFF / REVIEW` 协作事件和决策升级边界。
5. `forming → briefing → executing → reviewing → integrating → complete/stopped` 生命周期。

实际进入 Team 模式时读取 [`references/team-protocol.md`](references/team-protocol.md)，按其中的 Charter、角色、任务和阶段合同执行。需要一个完整示例时读取 [`references/development-team-example.md`](references/development-team-example.md)。

## 3. 映射到原生运行时

- **Codex**：Team 默认是 `hub-and-spoke`；当前主线程是 Lead，原生 subagents/agent threads 是 Members。不要假设 Members 可以直接互相通信。
- **Claude Code**：中心化 Team 使用 subagents；只有 Members 必须互相消息、认领共享任务或协作决策时才使用 Agent Teams。
- 不从 Codex shell 启动 Claude 充当 Member，也不从 Claude shell 启动 Codex。

准备创建 Member 时读取 [`references/native-runtimes.md`](references/native-runtimes.md)，以当前宿主实际暴露的工具和能力为准，不凭记忆编造命令、参数或会话能力。

## 4. 派发与协作

Lead 负责 Charter、Task Graph、成员选择、依赖、写入所有权、跨 Task 决策、Review、Integration 和最终汇报。

每个 Member 同时只有一个 active Task。派发必须对空白上下文自包含，至少说明：

- Role 和 Goal
- 必读的 3-6 个路径、符号或直接 Handoff
- Writes 和明确不负责的范围
- Needs、Produces 和 Consumer
- Acceptance 和完成 Handoff

不要复制完整用户聊天、全部计划、其他 Member 日志或无关仓库历史。若 spawn 接口暴露 `fork_turns`、`fork_context` 或类似选项，使用空白或最小上下文，并在派发消息中提供稳定任务事实。

依赖未满足的 Task 不进入 active。正常运行不频繁 ping；只有完成、阻塞、异常或需要决策时介入。结果偏离时优先在原 Member 上精确修正一次；同一控制失败两次时停止扩张团队，选择重新分配、降级 Solo 或报告阻塞。

## 5. 写入、Git 与权限

- 并行只读 Task 可以共享 checkout。
- 并行写 Task 必须使用独立 worktree，或拥有明确且不重叠的路径。
- 一个文件、生成物或迁移状态同一时刻只有一个 Owner。
- 记录已有 dirty worktree；任何 Member 不得覆盖、清理或回退用户及其他成员的改动。
- Members 默认不 commit、merge、rebase、打 Tag、推送或发布；只有 Task 合同明确授权时才允许。
- Integrator（默认 Lead）负责最终 diff、冲突处理、团队级验证和经用户授权的 Git/发布动作。
- 不启用 `--yolo`、bypass 或无 sandbox 模式。多 Agent 不扩大当前会话的授权边界。

## 6. 验收、持久化与结束

Member 的“完成”声明不等于通过。Lead 检查真实代码、diff、测试和产物。普通 Task 由 Member 自验、Lead 复核；中高风险、跨模块、迁移、权限、安全或用户明确要求时，增加独立只读 Reviewer。

短 Team 可以只使用宿主原生任务与消息。工作跨会话、依赖复杂或需要审计时维护 `.agent-taskgraph/`：

```text
PROJECT.md      稳定项目事实
TEAM.md         Team Charter 与 Roster
PLAN.md         Task Graph 与集成路径
STATUS.md       生命周期和当前状态
DECISIONS.md    改变团队合同的决策
tasks/<id>.md   单个 Task 合同与 Handoff
archive/        已完成批次
```

Lead 独占修改团队级状态；Member 只修改自己的 Task Handoff 和约定代码。持久化文件保存团队事实，不保证恢复 Agent 进程或 thread。新 Lead 先检查真实原生状态，再按 Handoff 恢复或重新创建 Members。

只有关键 Tasks 收口、依赖 Handoff 被消费、集成验证完成、风险被披露且不再需要的 Agents 已结束时，Team 才进入 `complete`。
