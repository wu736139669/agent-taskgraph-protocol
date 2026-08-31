![Agent TaskGraph](promo/agent-taskgraph-hero.svg)

[English](README.md) | [中文](README.zh-CN.md)

# Agent TaskGraph

**在 Codex 和 Claude Code 中建立有目标、角色、任务关系、协作协议和生命周期的原生 Agent Team。**

版本：[`v0.8.0-beta.18`](VERSION) | 许可证：[Apache-2.0](LICENSE)

Agent TaskGraph 不只是并行启动几个 Agent。它让当前会话成为 Lead，根据任务选择 Solo、Delegation 或 Team，并负责组建团队、分配角色、建立任务依赖、监督交接、组织审查、完成集成和解散团队。

它只使用当前宿主的原生 Agent 能力，不运行外部调度服务。

## 三种工作模式

| 模式 | 适用情况 | 运行方式 |
|---|---|---|
| **Solo** | 小修复、单模块或顺序任务 | 当前会话直接完成 |
| **Delegation** | 多个独立支线，只需分别交给 Lead | Lead + 原生 subagents |
| **Team** | 有共同目标、角色协作、任务依赖或跨模块集成 | Team Charter + 角色 + 任务图 + 生命周期 |

用户明确要求“组一个团队”时优先进入 Team 模式。只有原生 Agent 不可用、任务无法安全拆分或写入无法隔离时才降级。

## 一个 Team 包含什么

### 共同目标

团队有一个可观察的集成结果，同时声明当前批次的非目标和完成条件。

### 角色

- **Lead**：组队、派发、依赖、决策、监督和集成。
- **Builder / Specialist**：负责边界清楚的 Task。
- **Reviewer**：按风险独立审查，不重新实现任务。
- **Integrator**：消费 handoff、解决冲突、运行团队级验收，默认由 Lead 担任。

角色按真实任务动态创建。默认团队包含 Lead 在内共 2-4 个 active members，不为了组织结构完整创建空闲成员。

### 任务关系

每个 Task 都有：

```text
Owner / Role / Goal / Needs / Produces / Consumer / Writes / Acceptance
```

独立 Task 可以并行；有依赖的 Task 等待 handoff；共享写入范围必须串行或使用独立 worktree。

### 协作协议

团队使用四种简洁的语义事件：

- `READY`：任务合同清楚且可以开始。
- `BLOCKED`：报告阻塞、尝试和需要的决定或交付。
- `HANDOFF`：交付结果、路径、验证和下游注意事项。
- `REVIEW`：给出通过/修正结论及证据。

### 生命周期

```text
forming → briefing → executing → reviewing → integrating → complete/stopped
```

Team 只有在关键任务收口、handoff 被消费、集成验证完成、风险被披露并结束不再需要的 Agent 后才算完成。

## Codex 与 Claude Code

### Codex

Codex Team 默认是 **Lead 中心化的 hub-and-spoke 团队**：当前主线程是 Lead，原生 subagents/agent threads 是成员。成员间不需要直接通信；Lead 通过任务合同、代码产物和 handoff 协调依赖。

### Claude Code

- **Subagents**：用于 Lead 中心化团队，适合开发、研究和审查。
- **Agent Teams**：只有 teammates 需要互相通信、认领共享任务或协作决策时使用。

逻辑 Team 不等同于 Claude Agent Teams。Agent Teams 不可用时，仍然可以用 subagents 建立中心化 Team。

## 写入和 Git 所有权

- 并行写任务使用独立 worktree 或不重叠路径。
- 一个文件、生成物或迁移状态同一时刻只有一个 Owner。
- Worker 默认不 commit、merge、rebase、打 Tag、推送或发布。
- Integrator 负责最终 diff、冲突处理和团队级验证。
- 多 Agent 不扩大当前会话已有的权限和外部操作授权。

## 安装

```bash
git clone https://github.com/wu736139669/agent-taskgraph-protocol.git
cd agent-taskgraph-protocol
./install.sh
./install.sh --status
```

安装器会把同一个 Skill 链接到：

- `~/.codex/skills/agent-taskgraph`
- `~/.claude/skills/agent-taskgraph`

## 使用

建立开发团队：

```text
使用 agent-taskgraph 组一个开发团队完成这个需求。先理解项目，建立共同目标、角色、任务依赖、写入边界和完成条件，然后用当前宿主的原生 Agent 执行、交接、审查和集成。
```

只做独立并行委派：

```text
使用 agent-taskgraph。可以独立并行的任务交给原生 subagents，主会话负责汇总和验收，不需要成员互相协作。
```

让 Skill 自动选择：

```text
使用 agent-taskgraph 完成这个任务。根据复杂度选择 Solo、Delegation 或 Team；并行写入必须隔离，最后统一验收。
```

## 可选的持久化 Team 状态

短 Team 可以只使用宿主原生任务和消息。跨会话、任务依赖复杂或需要审计时运行：

```bash
./init.sh /path/to/project
```

生成：

```text
.agent-taskgraph/
├── PROJECT.md
├── TEAM.md          # Team Charter 和成员
├── PLAN.md          # 任务图和依赖
├── STATUS.md        # 团队生命周期
├── DECISIONS.md
├── tasks/TEMPLATE.md
└── archive/
```

持久化目录恢复的是团队事实和 handoff，不是假定仍然在线的 Agent。新 Lead 会话必须先检查原生状态，再恢复或重新创建成员。

## 团队预设

以下只是起点，不是固定组织结构：

- **Development Team**：Lead/Integrator + 按模块划分的 Builders + 按风险创建 Reviewer。
- **Research Team**：Lead/Synthesizer + 按问题域划分的 Researchers。
- **Review Team**：Lead + 按正确性、安全、测试或产品意图划分的只读 Reviewers。

## 验证和更新

```bash
./tests/smoke.sh
./install.sh --check-update
```

完整入口见 [`SKILL.md`](SKILL.md)，团队合同见 [`references/team-protocol.md`](references/team-protocol.md)，运行时映射见 [`references/native-runtimes.md`](references/native-runtimes.md)。
