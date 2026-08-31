---
name: agent-taskgraph
description: "在 Codex 或 Claude Code 中建立有共同目标、角色、任务关系、协作协议和生命周期的原生 Agent Team，并负责拆分、并行、监督、交接、审查与集成。适用于用户明确要求 Agent Team、多 Agent、subagents、任务图、PMO、并行开发，或复杂工作存在多个可独立推进且需要协调的任务；简单任务仍由当前会话完成。"
---

# Agent TaskGraph

只使用当前宿主的 **Codex** 或 **Claude Code** 原生 Agent 能力。Team 是逻辑协作模型，不等同于“启动多个进程”，也不要求外部控制面或自建队列。

## 1. 选择工作模式

先读适用的 `AGENTS.md` / `CLAUDE.md`、相关代码和验证命令，再选择最小有效模式：

| 模式 | 适用情况 | 协作形态 |
|---|---|---|
| **Solo** | 小修复、单模块、顺序工作、拆分收益低 | 当前会话直接完成 |
| **Delegation** | 两个以上独立支线，只需各自向主会话交付 | Lead 中心化派发；Worker 之间不必协作 |
| **Team** | 任务存在依赖、共享目标、跨模块集成、角色协作或共同决策 | 明确 Team Charter、角色、任务图、协作协议和生命周期 |

用户明确要求“团队”时优先使用 **Team**，除非当前宿主没有原生 Agent 能力、任务无法拆出独立职责，或写入范围无法安全隔离；降级时说明原因。

默认包含 Lead 在内共 2-4 个有真实职责的 active members。不要为组织结构完整而创建空闲 Agent。用户调用本 Skill 已授权合理的内部拆分和原生 Agent 创建；只有代码无法回答的产品决策、权限扩大或外部副作用才需要提问。用户明确要求先看分工时才等待确认。

## 2. Team 是完整工作单元

进入 **Team** 模式时，必须先建立以下五部分：

1. **共同目标**：一个团队级可观察结果，以及明确非目标。
2. **角色**：Lead、执行角色、必要时 Reviewer/Integrator；每个角色有责任边界。
3. **任务关系**：每项任务有 Owner、`needs`、产出、写入范围、验收和下游消费者。
4. **协作协议**：如何派发、报告阻塞、交接、做跨范围决策和升级 Human Gate。
5. **生命周期**：`forming → briefing → executing → reviewing → integrating → complete/stopped`。

Team 的详细合同和生命周期见 [`references/team-protocol.md`](references/team-protocol.md)。只有实际进入 Team 模式时才读取它。

## 3. 运行时映射

- **Codex**：逻辑 Team 默认映射为 Lead 中心化的原生 subagents/agent threads。不要假设 Worker 之间能直接通信；跨任务 handoff 由 Lead 或稳定任务产物转交。
- **Claude Code**：中心化协作使用 subagents；只有 teammates 需要互相通信、认领共享任务或协作决策时才使用 Agent Teams。
- 不从 Codex shell 启动 Claude 充当成员，也不从 Claude shell 启动 Codex。
- 实际准备创建成员时读取 [`references/native-runtimes.md`](references/native-runtimes.md)，以当前暴露的工具和能力为准，不凭记忆编造命令或 flag。

## 4. Lead 的职责

Lead 负责：

- 理解目标、建立 Team Charter 和任务图
- 选择成员、分配任务、保护依赖与写入边界
- 维护团队状态、处理阻塞和跨范围决策
- 检查 handoff、组织 Reviewer、完成集成与最终验收
- 结束成员、归档团队状态并向用户汇报

在 **Delegation** 模式，Lead 可以同时完成一个不重叠任务。在 **Team** 模式，Lead 的首要职责是协调和集成；小团队中仍可承担一个边界清楚的任务，但不得因此延误派发、监督或集成。

组队时向用户展示一次短预览：

```text
模式与拓扑：<Delegation / Team；hub-and-spoke / peer-capable>
团队目标：<结果>
成员：<角色 -> 当前任务 -> 写入范围>
任务关系：<关键依赖和集成点>
完成条件：<团队级验收>
风险：<权限、冲突或外部副作用>
```

## 5. 成员任务合同

每个成员一次只拥有一个 active Task。派发必须对空白上下文自包含，包含：

1. **Role**：本角色对团队目标承担什么责任。
2. **Goal**：一个可观察、可验收的任务结果。
3. **Context**：必须读取的 3-6 个路径、符号或直接依赖 handoff。
4. **Scope**：允许写入和明确不负责的范围。
5. **Relations**：`needs`、产出和下游消费者。
6. **Acceptance**：必须运行的命令或检查。
7. **Handoff**：结果、修改路径、验证、风险和下游注意事项。

不要复制完整用户聊天、全部计划、其他成员日志或无关仓库历史。若 spawn 接口暴露 `fork_turns`、`fork_context` 或类似选项，使用空白或最小上下文，并在派发消息中提供稳定任务事实。

## 6. 写入与 Git 所有权

- 并行只读任务可以共享 checkout。
- 并行写任务必须使用独立 worktree，或拥有明确且不重叠的路径。
- 一个文件、生成物或迁移状态在同一时刻只能有一个 Owner。
- 记录已有 dirty worktree；任何成员不得覆盖、清理或回退用户及其他成员的改动。
- Worker 默认不提交、合并、rebase、打 Tag、推送或发布；只有任务合同明确授权时才允许。
- Integrator（默认 Lead）负责最终 diff、冲突处理、集成验证和经用户授权的 Git/发布动作。

## 7. 协作与监督

使用宿主原生 Agent 列表、任务、消息、等待、恢复和停止能力，不复制第二套 session 状态机。

团队只需要四类语义事件：

- `READY`：成员理解任务并可开工。
- `BLOCKED`：说明阻塞、已尝试内容和需要谁决定/交付。
- `HANDOFF`：交付结果、产物、验证和风险。
- `REVIEW`：给出通过/不通过、证据和需要修正的边界。

无需为了机器解析强制复杂格式，但事件必须包含 Task ID。正常运行不频繁 ping；依赖未满足的任务不提前开始。结果偏离时优先在原 Agent 上精确修正一次。同一成员控制失败两次或原生能力不可用时，停止扩张团队，重新分配、降级 Solo，或向用户报告阻塞。

## 8. 验收与团队完成

成员的“完成”声明不等于任务通过。Lead 必须检查代码、diff、测试和产物。

普通 Task 由成员自验、Lead 复核。中高风险、跨模块集成、迁移、权限、安全或用户明确要求时，使用独立 Reviewer；Reviewer 默认只读，不重新实现同一任务。

只有以下条件同时成立，Team 才能进入 `complete`：

1. 所有关键 Task 已完成、失败或被用户明确取消。
2. 所有依赖 handoff 已被下游消费。
3. Integrator 已完成最终集成和团队级验证。
4. 没有未披露的阻塞、冲突或外部副作用。
5. 不再需要的原生 Agent 已停止或完成。

## 9. 持久化是团队规模选择

单次 Delegation 或短 Team 可以只用宿主原生任务与消息。以下情况维护 `.agent-taskgraph/`：

- 工作跨多个主会话或工作日
- 任务图包含重要依赖或多个集成点
- 用户要求恢复、审计或团队工作记录

```text
.agent-taskgraph/
├── PROJECT.md
├── PLAN.md          # 任务图和依赖
├── TEAM.md          # Team Charter、角色和成员
├── STATUS.md        # 生命周期与当前状态
├── DECISIONS.md
├── tasks/<id>.md
└── archive/
```

Lead 独占修改 `PLAN.md`、`TEAM.md`、`STATUS.md` 和 `DECISIONS.md`。成员只修改自己的任务 handoff 和约定代码。持久化目录保存团队事实，不保证恢复 Agent 进程或 thread；新 Lead 必须先检查真实原生状态，再按 handoff 恢复或重新创建成员。

## 10. 权限与成本

- 默认继承当前宿主的模型、推理和权限，不硬编码模型名。
- 只有用户要求，或质量/成本差异足以改变结果且宿主支持时，才按角色覆盖配置。
- 不启用 `--yolo`、bypass、无 sandbox 等危险模式。若成员会继承异常宽泛的父权限，在第一次创建前一次说明。
- 多 Agent 不扩大安装、联网写操作、迁移、删除、合并、Tag、推送或发布的授权边界。
- 成员数量以任务图为准；更多 Agent 不等于更快。
