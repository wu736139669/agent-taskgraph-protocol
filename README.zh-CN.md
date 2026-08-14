![Agent TaskGraph](promo/agent-taskgraph-hero.svg)

[English](README.md) | [中文](README.zh-CN.md)

# Agent TaskGraph Protocol

**专为 Codex 和 Claude Code 设计的原生多会话任务编排技能。**

源码版本：[`v0.8.0-beta.16`](VERSION) | 许可证：[Apache-2.0](LICENSE)

Agent TaskGraph 是一种轻量的 graph engineering（图工程）协议，用来构建 **PMO 主导的原生 Agent Team**。当前 Codex 或 Claude Code 会话担任 PMO：先理解需求和项目，再只询问仓库无法回答的关键问题；之后拆出小任务，在确实有并行收益时创建原生 Agent 会话，最后统一验收并向用户汇报。

它是一个 Skill 和协作协议，不是托管式调度服务。HAPI 只作为明确需要跨机器控制时的可选适配器，正常流程不会启用或探测 HAPI。

## 它解决什么问题

- 复杂需求先澄清，再开始实现。
- 每个 Worker 都是独立的 Codex thread 或 Claude Code session，有自己的上下文。
- 每个 Worker 只有一个长期职责、一个当前任务、一个写入边界和一份精简上下文契约。
- Worker 之间通过项目文档和 handoff 交接，不复制漫长聊天记录。
- PMO 负责理解、拆解、派发、监督、集成、验收和最终汇报。
- 小任务留在当前会话完成，不为了“多 Agent”增加额外开销。

## 快速开始

### 安装

```bash
git clone https://github.com/wu736139669/agent-taskgraph-protocol.git
cd agent-taskgraph-protocol
./install.sh
./install.sh --status
```

安装器会同时链接到：

- Claude Code：`~/.claude/skills/agent-taskgraph`
- Codex：`~/.codex/skills/agent-taskgraph`

已有的非符号链接目录默认拒绝覆盖。使用 `./install.sh --check-update` 可以只检查远程版本，不修改本地文件。

### 初始化项目

```bash
./init.sh /path/to/your-project
```

新项目只创建轻量的共享状态目录：

```text
.agent-taskgraph/
├── PROJECT.md       # 稳定项目事实、命令和约束
├── PLAN.md          # 当前任务图和依赖
├── TEAM.md          # 长期职责与原生 session/thread
├── STATUS.md        # 进度、阻塞和下一步
├── DECISIONS.md     # 用户与 PMO 的关键决定
├── tasks/<id>.md    # 每个 Worker 的任务与 handoff
└── archive/         # 已完成任务记录
```

初始化会保留已有文件。旧版 beta 队列项目需要兼容旧校验时，才使用 `./init.sh --legacy-queue <project>`；新项目不要默认使用这个选项。

### 启动技能

在目标项目中打开 Codex 或 Claude Code，然后直接说：

```text
使用 agent-taskgraph。先理解项目和需求；如果值得并行，就由你作为 PMO 创建原生 Codex/Claude 多会话，每个 Agent 使用独立上下文，通过共享文档交接并统一验收；如果不值得并行，就当前会话直接完成。开始前先告诉我你的理解和分工。
```

这句话已经足够。PMO 会先读项目，然后给出：

```text
我的理解：...
需要你决定：...（0-3 个真正阻塞的问题）
计划：当前会话 / PMO + N 个原生 Agent
```

用户确认后，PMO 才会创建会话并派发任务。用户不需要填写 Goal ID、session ID、worktree 路径、wait 命令或 HAPI 参数。

## 一批任务如何运行

1. **发现**：PMO 读取项目规范、相关代码、测试和构建命令。
2. **澄清**：把无法从代码确定的产品或风险决策连同推荐默认值交给用户。
3. **计划**：写入 `PROJECT.md`、`PLAN.md`、`TEAM.md`，并为每个 Worker 创建 `tasks/<id>.md`。
4. **预览**：一次展示每个角色、任务、原生会话类型、模型/推理、有效权限、可见方式、worktree 和写入范围。
5. **派发**：Codex 使用原生 Agent thread；Claude Code 的协作批次优先 Agent Teams，长期 Worker 使用 Agent View background session，subagent 只做短支线。
6. **交接**：Worker 将结果、修改路径、revision/diff、验证结果和风险写入自己的任务文件。
7. **验收**：PMO 检查 diff 并运行项目验收命令。只有中高风险或跨模块变更才增加独立 Reviewer。
8. **收口**：PMO 更新状态、归档完成任务，并向用户总结结果。

## 上下文隔离

每个 Agent 都有独立对话上下文。Worker 只读取：

- 适用的 `AGENTS.md` 或 `CLAUDE.md`
- `.agent-taskgraph/PROJECT.md` 的相关部分
- 自己的 `.agent-taskgraph/tasks/<id>.md`
- 直接依赖任务的 handoff
- 通过定向搜索找到的相关源码

PMO 不会把完整聊天记录粘贴给 Worker。宿主支持 history/context fork 时，必须显式选择空白或最小任务上下文，不使用默认 full-history fork。稳定事实放在文档里，长项目不会反复消耗同一份上下文。

## 角色怎么确定

PMO 根据真实项目和当前任务动态定义角色，而不是强行使用固定团队。常见角色有前端、后端、数据、测试、研究和 Reviewer。需要长期复用的职责记录在 `TEAM.md`；每次新任务仍然拥有新的范围和 handoff。没有当前任务的角色不会创建 Agent。

团队运行期间，PMO 不偷偷编写产品代码；它负责计划、依赖、监督、证据检查和验收。

## Codex 与 Claude Code

### Codex

使用 Codex 原生 subagent/thread 能力。它们是当前 Codex 客户端里的 Agent thread，不是多个终端窗口。CLI 中用 `/agent` 查看和切换，App/IDE 使用 Agent 面板。原生 thread 不代表已经隔离 worktree；并行写任务必须观察到真实 worktree，或保证写入路径不重叠。长期角色可定义在 `.codex/agents/`。

### Claude Code

PMO 主导的协作批次优先使用 Claude **Agent Teams**。Lead 是 PMO，teammates 是拥有独立上下文的完整 Claude Code session。Agent Teams 是实验能力，需要先启用：

```bash
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

Agent Teams 默认显示在当前终端内的 Agent 面板中，不会为每个 Agent 新开 Terminal.app。只有用户明确要求时才使用 tmux/iTerm2 可见分屏。

需要跨 PMO 恢复、长期后台运行或独立 worktree 的 Worker，使用 **Agent View background sessions**，通过 `claude agents` 查看和 attach。一次性探索、测试、日志分析或 Reviewer 才使用 **subagents**。未启用 Agent Teams 时，技能必须报告实际降级，不会把 subagent 冒充多会话团队，也不会静默切换到 HAPI。

如果宿主没有创建、观察原生 Agent 的能力，技能会明确降级为当前单会话，而不是制造虚假的多 Agent 状态。

## 权限

权限属于一次性团队预览。PMO 记录启动后观察到的有效权限，而不是只记录请求值。

| 角色 | Claude Code | Codex |
|---|---|---|
| Explorer/Reviewer | `plan` 或只读 tools | `read-only` |
| 实现 Worker | 独立 worktree + `acceptEdits`/`auto` | `workspace-write + on-request` |
| 无人值守的受限 Worker | `dontAsk` + 精确 allowlist | `workspace-write + never` |
| 迁移/发布 | 正常询问 + Human Gate | `on-request` + Human Gate |

`bypassPermissions`、`danger-full-access + never` 和 `--yolo` 只有 Owner 明确授权且外部环境已经隔离时才能使用。检测到父会话已经是 Full Access/Yolo 时，PMO 必须一次性说明它会传播给所有原生 Workers。

## 什么时候只用一个 Agent

单文件、小 bug、单模块、必须顺序进行的工作，或者多个角色会修改同一批文件时，留在当前会话更合适。只有至少两个任务可以独立推进并独立验收时，才创建多会话。

## HAPI：可选高级适配器

HAPI 不是必需品，正常流程不会探测或配置。只有跨机器控制、远程终端或统一外部控制面时，才明确要求启用。如果 HAPI 不可用或失败，回到 Codex/Claude 原生能力或单 Agent，不进入 HAPI 修复循环。

## 更新

Owner 会话可以运行：

```bash
./install.sh --check-update
```

检查是只读的。发现新版本时只提示建议命令，不会自动 pull、替换正在使用的 Skill 或重启会话。当前批次继续使用它记录的协议版本，下一批任务开始前再更新。

## Beta 边界

这是公开 Beta，依赖本机安装的 Codex 或 Claude Code 版本所提供的原生多 Agent 能力。它不提供无人值守的云端队列，也不保证不同宿主的界面完全一致，更不会绕过项目权限。迁移、删除、扩大权限、合并和发布仍然需要用户作为 Human Gate 做最终决定。

## 许可证

Apache License 2.0，详见 [LICENSE](LICENSE)。
