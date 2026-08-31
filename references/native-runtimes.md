# Native Runtime Guide

只在准备创建原生 Agent 时读取本文件。先以当前会话实际暴露的工具、帮助和配置为准；客户端版本不同，能力和字段可能不同。

## 选择表

| 场景 | Codex | Claude Code |
|---|---|---|
| 聚焦的只读探索/测试/审查 | 原生 subagent | subagent |
| 多个独立实现任务 | 原生 subagents；worktree 或不重叠路径 | 带 worktree isolation 的 subagents，或不重叠路径 |
| Worker 必须互相讨论、认领共享任务 | 原生 subagents，由主线程协调 | Agent Teams |
| 单个长任务需后台继续 | 宿主支持时使用后台/异步 Agent | background subagent |
| 无原生 delegation 能力 | 当前会话直接完成 | 当前会话直接完成 |

## Codex

### 派发

- 使用当前环境提供的 `spawn_agent` 或等价原生工具；不要用 shell 再启动一个 Codex CLI。
- 优先使用宿主内置通用、Explorer、Worker 或 Monitor 类型。只有职责会反复出现且默认角色不足时，才维护仓库或用户级自定义 Agent 配置。
- 每个 spawn 只对应一个边界清楚的任务。独立任务可以并行启动；有依赖的任务等 handoff 后再启动。
- 若 API 暴露 `fork_turns`、`fork_context` 或 history 选项，使用 `none` / 空白 / 最小最近上下文。派发 prompt 本身必须自包含。
- 不要仅为了并行而覆盖模型或推理。需要覆盖时，先确认当前 spawn 接口允许该组合；否则继承父会话。

### 监督

- 用当前环境提供的 Agent 列表、wait、message/steer、follow-up 和 stop/interrupt 工具。
- 主会话在等待期间可以做不与 Worker 重叠的工作。
- 第一次结果不完整时，在原 Agent thread 上发送精确 follow-up；不要立刻创建替代 Agent。
- 结束前等待所有相关 Agent，关闭不再需要的长期运行任务。
- 不假定 subagent thread 能跨 Codex 重启继续存在。跨会话恢复时以持久化 handoff 为准，先检查真实 Agent 列表，再决定恢复或重新创建。

### 共享工作区

Codex subagents 可能共享当前 checkout；“独立 thread”不等于“独立文件系统”。在实际观察到 worktree 隔离前，写任务必须按不重叠路径分区。

## Claude Code

### Subagents：默认选择

对聚焦、边界清楚的任务优先使用 subagents：

- 每个 subagent 有独立上下文，结果返回主会话。
- 自定义 subagent 可在 `.claude/agents/` 中定义工具、权限、模型、skills 和 `isolation: worktree`。
- 需要并行写代码时优先 worktree isolation；否则严格划分不重叠文件。
- 独立任务可以在一条请求中并行启动。需要继续时恢复原 subagent，而不是丢弃其上下文。
- 后台 subagent 适合独立且不需要频繁交互的长任务；后台化不等于获得额外权限。
- Agent Teams 已启用时，命名 Agent 在部分调用方式下可能成为 teammate。若任务必须保持为 subagent，使用当前版本 Agent 工具明确支持的 fork/worktree isolation，并在启动后检查真实运行形态。

### Agent Teams：只在需要同伴协作时使用

Agent Teams 适合 teammates 必须互相消息、共享任务列表、认领工作或协作决策的场景。若 Worker 只需把结果交回主会话，subagents 更简单且成本更低。

- 只有当前 Claude Code 已启用并实际支持 Agent Teams 时才使用；不要静默修改用户设置来开启实验或预览能力。
- Lead 负责创建共享任务、设置依赖、整合和关闭 team。
- Teammates 启动时加载项目上下文，但不会继承 Lead 的完整对话历史；spawn prompt 必须自包含。
- Teammates 可能共享同一工作目录。不要让两个 teammate 同时修改同一文件；需要强隔离时改用 worktree-isolated subagents。
- 只有用户要求纯协调，或 Lead 必须保持只读时才启用 lead-only；否则 Lead 可以完成一个非重叠任务。
- 所有 teammates 结束后再执行 team cleanup。
- 不把 Agent Team 设计成依赖 Lead resume 的持久会话。Lead 会话结束前先收集 handoff；恢复主会话后若 teammates 不存在，按 handoff 重新创建。

## 降级规则

以下任一条件成立时，不制造“伪团队”：

- 当前宿主没有原生 spawn/observe 能力
- 无法保证并行写入隔离
- 任务无法写出独立目标和验收
- 协调成本已经超过单 Agent 执行成本

直接由当前会话完成，并向用户说明没有使用多 Agent 的原因。
