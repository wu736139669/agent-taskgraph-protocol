# Codex and Claude Code Native Multi-Agent Runtimes

仅在需要创建多个 Agent 会话时读取。

## Codex

- 当前 Codex 原生支持 subagent workflows；CLI、IDE、App 都能观察 Agent thread。
- 使用宿主实际暴露的 spawn/wait/steer/stop 能力，不在 Skill 中假定具体工具名。
- CLI 用户可以用 `/agent` 查看和切换 Agent thread。
- 并行写任务使用原生 worktree 或互不重叠的路径；读任务可以共享 checkout。
- 需要稳定角色时用 `.codex/agents/<role>.toml`；临时任务不创建配置文件。
- Codex Cloud 是独立的远程任务形态，不是本地主会话 subagent。只有用户选择 Cloud 时使用。

## Claude Code

- 默认使用 subagents；它们有独立上下文并把结果返回主会话。
- 需要可直接交互的多个独立 Claude Code 会话时，可使用 Agent Teams，但必须先确认该实验能力已启用。
- Agent Teams 未启用时使用 subagents，不安装或切换 HAPI。
- 使用宿主真实能力决定 foreground/background、显示面板、模型与权限；不要编造 flags。

## 通用

- 能力探测只回答：能否 spawn、观察、发送后续指令、停止、获得完成结果。
- 缺少任一必要能力时降级单 Agent。
- 原生 Agent 默认继承父会话权限；扩大权限时才询问。
- 每个 Agent 的 session/thread ID 写入 `TEAM.md` 和自己的 task 文件即可，不生成额外 evidence 文件。
