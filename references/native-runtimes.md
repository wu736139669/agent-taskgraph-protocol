# Codex and Claude Code Native Agent Teams

仅在需要创建多个 Agent 会话时读取。先探测当前宿主实际能力；版本或能力不匹配时降级，不猜测命令。

## 统一概念

| TaskGraph 概念 | Claude Code | Codex |
|---|---|---|
| PMO | Agent Team Lead / 主 session | 主 Agent thread |
| 长期 Worker | teammate 或 Agent View background session | native Agent thread + durable agent definition |
| 短期支线 | subagent | explorer/subagent thread |
| 团队查看 | Agent panel / `claude agents` | `/agent` / Agent panel |
| 角色定义 | `.claude/agents/` | `.codex/agents/` |
| 稳定交接 | `.agent-taskgraph/tasks/*.md` | `.agent-taskgraph/tasks/*.md` |

“独立会话”表示独立可寻址的上下文，不表示必须打开一个 Terminal 窗口。默认不要创建额外 Terminal.app 窗口。

## Claude Code

### 运行形态选择

1. **Agent Teams**：PMO 需要自动拆分、派发、监督，多名 Worker 在一个活跃批次内协作。它最接近 PMO-led Agent Team，但属于实验能力。
2. **Agent View background sessions**：Worker 需要跨 PMO 恢复、长期后台运行、独立 attach 或自动 worktree 隔离。
3. **Subagents**：一次性探索、测试、日志分析或 Reviewer；只需向调用者返回摘要。
4. **单 Agent**：Agent Teams 未启用、background sessions 不可派发，或任务没有并行价值。

用户明确要求“Agent Team/多个独立会话”时，不得静默用 subagents 冒充。说明实际降级结果。

### Agent Teams

- 检查 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 是否已启用；未启用不自动改用户设置。
- Lead 是 PMO；teammates 有独立 context，不继承 Lead 聊天历史，只接收项目上下文和 spawn prompt。
- 默认使用 in-process Agent panel。只有用户明确要求可见分屏时才使用 `teammateMode=auto/tmux/iterm2`。
- teammates 在 spawn 时继承 Lead permission mode，不能逐人设置；可以在 spawn 后调整，但必须在开工前验证。
- teammates 不自动使用独立 worktree。只并行派发写入范围不重叠的任务；需要强隔离时使用 background sessions。
- in-process teammates 不保证随 Lead `/resume` 恢复。跨天或跨 PMO 连续性保存在任务文档和角色定义中，运行时使用 background session。

### Agent View background sessions

每个 background session 是完整 Claude Code conversation，由 supervisor 运行，不需要附着终端。用户用 `claude agents` 查看、attach、回复或停止。

宿主允许 PMO 调用 CLI 时，可按实际版本使用类似命令；先 dry-run/查看 `claude --help`，不要照抄未知 flag：

```bash
claude --bg \
  --name worker-ui \
  --agent frontend-worker \
  --permission-mode acceptEdits \
  --model sonnet \
  --effort high \
  "读取 .agent-taskgraph/tasks/T1-ui.md，回复 TASK_READY T1-ui 后执行"
```

管理示例：

```bash
claude agents --cwd /path/to/project
claude agents --cwd /path/to/project --json
```

- Git 项目中的 background session 通常在写入前进入 `.claude/worktrees/` 隔离；必须观察实际 cwd/worktree 后再标记 ready。
- Cross-session messaging 只作为唤醒、状态和短通知通道；任务范围、决定和 handoff 仍写共享文档。
- 当前宿主无法从 PMO 自动派发 background session 时，不伪装成功；使用 Agent Teams、subagent 或单 Agent。

### Claude 权限

| 角色 | 默认建议 | 说明 |
|---|---|---|
| Explorer | `plan` 或只读 tools | 不允许 Edit/Write |
| Reviewer | 只读 tools + 精确测试命令 | 测试产生缓存时使用隔离 worktree |
| Worker | `acceptEdits` 或 `auto` | 配合独立 worktree；风险命令仍询问 |
| 无人值守 Worker | `dontAsk` + 精确 allowlist | 未授权操作失败，不扩大权限 |
| 发布/迁移 | `default/manual` | Human Gate |

`bypassPermissions` 只在用户明确授权且外部环境已隔离时使用。Agent Teams 中 Lead 使用 bypass 时 teammates 也会继承。

## Codex

### 创建与观察

- 使用当前 Codex 暴露的 native spawn/wait/steer/stop 能力创建 Agent thread，不启动新的 `codex` Terminal 进程来模拟 subagent。
- CLI 用户用 `/agent` 查看和切换 thread；App/IDE 使用 Agent panel。
- 每个 Worker 有独立 thread/context。若 spawn API 支持 `fork_context`、history 或类似选项，显式选择空白/最小上下文；不要使用 full-history fork。
- 需要稳定岗位时使用 `.codex/agents/<role>.toml`；文件定义职责、model、reasoning 和允许的 sandbox。Task 仍写在 `.agent-taskgraph/tasks/<id>.md`。
- Codex Cloud 是另一种远程任务形态，只有用户选择 Cloud 时使用。

### Worktree

- Native Agent thread 不等于独立 worktree。CLI/IDE 中先假定同一 checkout，除非宿主返回了不同 cwd/worktree 证据。
- 只读任务可以共享 checkout。
- 并行写任务必须使用 Codex App managed worktree、显式 Git worktree，或严格不重叠的写入路径。
- PMO 验收前记录每个 Worker 的真实 cwd、branch/revision 和 diff；不要只记录计划路径。

### Codex 权限

Codex child thread 通常继承父会话的 effective sandbox、approval 和 live runtime overrides。`/permissions`、CLI override 和 `--yolo` 可能覆盖 custom agent 文件中的默认值。

| 角色 | Sandbox | Approval |
|---|---|---|
| Explorer/Reviewer | `read-only` | 继承父会话；必要命令精确授权 |
| Worker | `workspace-write` | `on-request` |
| 无人值守 Worker | `workspace-write` | `never`，越界操作失败 |
| 发布/迁移 | `workspace-write` | `on-request` + Human Gate |

推荐的低摩擦父会话配置：

```toml
sandbox_mode = "workspace-write"
approval_policy = "on-request"

[agents]
max_concurrent_threads_per_session = 3
```

`danger-full-access + never` / `--yolo` 会移除 sandbox 和审批。检测到父会话已处于该模式时，在团队预览中明确说明所有 Workers 将继承它，并向用户确认一次；不要静默沿用。

## 派发硬规则

派发前必须得到并记录：

1. 真实运行形态：Agent Teams / background session / subagent / Agent thread
2. session/thread ID 或宿主可寻址名称
3. model 与 reasoning/effort
4. effective permission/sandbox，不是请求值
5. cwd/worktree 与写入范围
6. 能否观察、发送后续消息、停止和获得完成结果

任一关键能力无法确认时降级，不创建替代性的 HAPI 会话。任务文档是事实源，原生消息只负责通知。
