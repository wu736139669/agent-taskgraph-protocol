---
name: agent-taskgraph
description: "为 Codex 和 Claude Code 编排原生多 Agent 会话。主会话作为 PMO 理解需求、拆分任务、创建独立 Agent 会话、控制每个 Agent 的最小上下文，并通过共享任务文档交接、监督和验收。默认简单、native-first；HAPI 仅在用户明确要求跨机器控制时作为可选补充。Triggers: 多agent, 多会话, agent team, subagents, task graph, graph engineering, PMO, 派任务, 并行开发, 拆任务, 编排"
---

# Agent TaskGraph

只面向 **Codex** 和 **Claude Code**。优先使用当前宿主的原生多 Agent 能力，不要求 HAPI。

## 1. 默认原则

1. 一句话可以开始。先读项目，再问代码无法回答的问题。
2. 简单任务由当前会话直接完成，不成立团队。
3. 复杂或可并行任务才成立团队；主会话成为 PMO，不写产品实现。
4. 一个 Agent = 一个独立 Agent thread/session + 一个明确职责 + 一个当前任务。
5. 每个 Agent 只加载自己的最小上下文，不复制 PMO 全部聊天历史。
6. Agent 之间通过稳定共享文档交接，不以互相转发长聊天作为事实源。
7. 默认使用当前 Codex/Claude Code 的原生模型、权限、会话和等待机制。
8. HAPI 默认关闭；只有用户明确说“使用 HAPI”或确有跨机器控制需求时才加载 [`references/hapi-runtime.md`](references/hapi-runtime.md)。

## 2. 用户看到的流程

PMO 先输出一段短摘要：

```text
我的理解：<目标与当前项目事实>
需要你决定：<0-3 个真正阻塞的问题，附推荐>
建议团队：<当前会话直接做 / PMO + N 个 Agent>
```

需要团队时，再展示一次团队预览：

| Agent | 长期职责 | 本次任务 | 原生运行形态 | 模型/推理 | 权限 | Worktree/写入范围 |
|---|---|---|---|---|---|---|

同时用一句话说明 PMO 只做计划、派发、监督和验收。用户确认“开始”后一次性创建团队；不要让用户确认 Goal 路径、Session ID、wait primitive、runtime evidence 或内部命令。只有运行形态、可见方式或权限扩大时才重新确认。

**最短用法**：

```text
使用 agent-taskgraph。先理解这个项目和需求；如果值得并行，就由你作为 PMO 创建几个原生 Codex/Claude Agent 会话，分别完成、交接和验收；如果不值得并行，就当前会话直接完成。先告诉我理解和分工，确认后开始。
```

## 3. 什么时候成立团队

使用当前会话直接完成：

- 局部 bug、单文件或同一模块小改动
- 顺序工作，拆开后没有速度收益
- 多人会同时修改相同文件
- 任务本身还没聊清楚

使用 PMO + 原生 Agent 团队：

- 至少两个任务能独立推进和验收
- 大范围只读探索、测试、审查或资料分析可并行
- 不同模块有清楚且不重叠的写入范围
- 用户明确要求多 Agent、多会话或团队协作

默认 2-3 个工作 Agent，最多按宿主和项目能力扩展。更多 Agent 不等于更快；没有当前任务的角色不创建。

高风险的迁移、权限、支付、删除、发布或共享基础设施变更，在普通团队流程上增加完整规格、独立 Reviewer 和 Human Gate。不要让所有日常任务承担这套成本。

## 4. 原生运行时

### Codex

- 优先使用当前会话暴露的原生 subagent/agent-thread 能力。
- CLI 中 Agent thread 可由 `/agent` 查看；App/IDE 使用其原生 Agent 面板。
- Codex 自己负责 spawn、wait、steer、stop 和结果回传；Skill 不再用 HAPI 模拟这些能力。
- 原生 Agent thread 默认不是新 Terminal，也不保证自动隔离 checkout。读任务可共享；并行写任务必须使用宿主 worktree 或互不重叠的路径。
- 自定义长期岗位可放在 `.codex/agents/`，但只在角色确实反复使用时创建。

### Claude Code

- 复杂团队任务优先使用 **Agent Teams**：主会话是 Lead/PMO，teammates 拥有独立 Claude Code 会话和独立上下文。只在已启用实验能力时使用；未启用时说明降级，不静默把“多会话团队”替换成 subagents。
- 需要跨 PMO 恢复、长期后台运行或独立 worktree 的 Worker，优先使用 **Agent View background sessions**；`claude agents` 是管理界面，Worker 不需要绑定单独终端。
- **Subagents** 只用于一次性探索、测试、日志分析或 Reviewer 等短支线；它们不算长期 Team Worker。
- 默认显示是当前终端内的 Agent 面板或后台列表。只有用户明确要求可见分屏时才使用 tmux/iTerm2；不要自动打开多个 Terminal.app 窗口。
- Agent Teams teammates 不自动隔离 worktree；并行写任务必须分区。需要强隔离时改用 background sessions 或支持 worktree isolation 的 subagents。

仅在实际创建团队时读取 [`references/native-runtimes.md`](references/native-runtimes.md)，按宿主当前能力选择运行形态，不凭记忆编造 CLI flag。

### 能力不足

当前宿主没有原生多 Agent 能力时，直接降级为单 Agent并告知用户。除非用户明确选择 HAPI，否则不探测、不配置、不调用 HAPI。

## 5. PMO 职责

PMO 只负责：

1. **理解**：读项目、澄清目标、识别约束和验收。
2. **计划**：把工作拆成有明确输入、输出、依赖和写入范围的任务。
3. **组队**：定义每个 Agent 的长期职责和本次任务，选择新建或复用原生会话。
4. **派发**：创建任务文档，启动会话，把稳定任务路径发给 Agent。
5. **监督**：使用宿主原生 Agent 状态和事件；正常进展不打扰。
6. **验收**：检查交付 revision/diff、运行验收命令、必要时安排独立 Reviewer。
7. **汇总**：更新共享状态，向用户说明结果、风险和下一步。

PMO 不在团队运行期间偷偷承担 Worker 的实现任务。团队控制面连续失败时，停止新建会话，请用户选择修复团队或降级当前会话直接完成。

## 6. 最小共享文档

项目状态位于 `.agent-taskgraph/`：

```text
.agent-taskgraph/
├── PROJECT.md       # 稳定项目事实、命令、约束
├── PLAN.md          # 当前任务和真实依赖
├── TEAM.md          # Agent 职责与原生 session/thread 绑定
├── STATUS.md        # 当前进度、阻塞和下一步
├── DECISIONS.md     # 用户/PMO 的关键决定
├── tasks/<id>.md    # 每个 Agent 唯一当前任务与 handoff
└── archive/         # 已完成任务
```

规则：

- `PLAN/TEAM/STATUS/DECISIONS` 只有 PMO 修改。
- Worker 只修改代码、自己的任务完成区和约定产物。
- 任务文件路径稳定，不在 `inbox/active/review/done` 目录间移动。
- 完成后 PMO 把任务文件移入 `archive/`，不是每次状态变化都提交一批控制文件。
- 共享文档不记录聊天全文、长日志或可从代码重新搜索的信息。

旧 `.agent-taskgraph/queue/` 项目可以继续使用旧校验脚本，但新项目不再默认创建这套状态机。旧项目不需要迁移才能继续工作；下一批新任务可以逐步写入 `tasks/`。

## 7. Agent 上下文合同

PMO 为每个 Agent 创建 `tasks/<task-id>.md`，只包含：

- 角色和本次目标
- 允许写入与明确不负责的范围
- 必须读取的 3-6 个路径/符号/文档
- 直接依赖及其 handoff
- 验收命令和完成条件
- 当前状态、原生 session/thread ID
- 完成后的简短 handoff

Agent 启动时只读：

1. 仓库内适用的 `AGENTS.md` / `CLAUDE.md`
2. `PROJECT.md` 相关章节
3. 自己的 `tasks/<id>.md`
4. 直接依赖任务的 handoff
5. 通过搜索定位到的相关源码

禁止默认读取全部 `PLAN`、全部其他任务、整个 archive、PMO 聊天或其他 Agent 日志。需要新上下文时，PMO把稳定引用追加到本任务文件，不粘贴整段历史。

如果宿主的 spawn API 支持 history/context fork，必须显式选择空白或最小任务上下文；不得省略该选项后意外继承 PMO 全部历史。Claude 不用 `/fork` 创建隔离 Worker；Codex 不使用 full-history fork。稳定上下文只通过 task 文件和直接 handoff 传递。

## 8. 派发和交接

派发消息保持短：

```text
你是 <role>。执行 task:<id>。
读取 .agent-taskgraph/tasks/<id>.md；只处理其中范围。
先回复 TASK_READY <id>，然后执行。完成时写 handoff 并通知 PMO。
```

PMO 观察到准确的 `TASK_READY` 后才认为 Agent 开工。Agent 完成时必须写：

- 结果摘要
- 修改/产物路径
- revision 或 diff 状态
- 实际运行的验证及结果
- 残余风险与下游需要知道的内容

下游 Agent 只读取这段 handoff 和产物，不读取上游聊天。

## 9. 模型、推理和权限

- 派发前读取宿主的**有效**模型、推理、sandbox/permission 和可见方式；只记录脱敏结果，不读取或复制 token、API key、settings 中的 secret。
- AI 按任务复杂度推荐配置，团队预览一次展示最终选择，不逐字段追问。
- 用户明确要求控制成本或模型时，才逐 Agent 调整。
- 轻量探索/格式整理用较快模型和较低推理；架构、复杂调试、Reviewer 使用更强模型和较高推理。
- Claude 建议：探索/只读 Reviewer 用 `plan` 或只读 tools；实现 Worker 用独立 worktree + `acceptEdits`/`auto`；无人值守且不弹窗时用 `dontAsk` + 精确 allowlist，让越权操作失败。
- Codex 建议：探索/Reviewer 用 `read-only`；实现 Worker 用 `workspace-write + on-request`。需要无人值守时可用 `workspace-write + never`，让越界操作失败而不是取消 sandbox。
- `bypassPermissions`、`danger-full-access + never` 或 `--yolo` 只在用户明确授权且环境已隔离时使用。检测到父会话已经是 Full Access/Yolo，必须在团队预览中说明它会传播给 Workers，并确认一次。
- Claude Agent Teams teammates 在 spawn 时继承 Lead 权限，不能逐人设置；需要混合权限时改用 background sessions/subagents，或在开工前逐个调整并验证。
- Codex Agent thread 继承父会话 sandbox/approval；父会话 live override 和 Yolo 会传播。自定义 Agent 文件只能在宿主允许时收紧，不得把请求值当成实际生效证据。
- 权限扩大、安装、联网、迁移、删除、合并和发布仍是 Human Gate。不要由 Skill 强制 yolo。

## 10. 监督、失败和验收

- 使用宿主原生 Agent 事件、状态和 wait 能力；不要自己维护 timer-cell 协议。
- 正常运行不 ping；只在完成、失败、阻塞、静默异常或需要决策时介入。
- 同一个产品问题优先让原 Agent 在原会话修复一次，保留上下文。
- 会话/派发/验收脚本错误在原边界修复，不创建新的任务、角色、session 或 worktree。
- 同一控制面错误连续两次，停止团队并向用户提供“重试团队 / 降级单 Agent / 终止”三选一。
- 独立 Reviewer 只用于中高风险、跨模块合并或用户明确要求；普通小任务由 Worker 自验 + PMO 复核。
- PMO 验收必须基于代码、diff、测试和产物，不以 Agent 口头“完成”作为通过。

## 11. 完成标准

批次完成时：

1. 所有任务到达 `done/failed/blocked`。
2. PMO 运行最终集成验证。
3. `STATUS.md` 只保留结果、风险和唯一下一步。
4. 已完成 task 文件移入 `archive/`。
5. 关闭不再需要的原生 Agent thread/session；长期角色保留在 `TEAM.md` 和宿主角色定义中。Claude Agent Teams 的 in-process teammates 不假定可跨 Lead resume，需跨批次恢复时使用 Agent View background session。
6. 向用户报告做了什么、如何验证、哪些未完成。

## 12. HAPI 可选补充

仅在用户明确要求跨机器、统一远程控制面或从另一台设备接管 Claude/Codex 会话时使用 HAPI。HAPI 失败不阻塞原生 Codex/Claude 工作；立即回到原生能力或单 Agent，不进入 HAPI 修复循环。
