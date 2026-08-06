# Dispatch Bootstrap: <稳定 Task ID>

> PMO 维护。它是 Role 到 Session 的本次绑定合同，不代替 ROLE.md、Goal 或 context.md。
> 首条消息只发送本文件中的稳定身份与引用，不复制项目背景。每次新建、复用或替换会话都生成新的 Dispatch ID。

| 字段 | 值 |
|---|---|
| Task ID | <与 Goal、queue 目录一致> |
| Dispatch ID | <dispatch:<task-id>:<attempt-or-session>> |
| Role ref | role:<role-id> |
| Role profile | roles/<role-id>/ROLE.md |
| Role lifecycle | <persistent / task-scoped> |
| Team revision | <与 ROLES.md、ROLE.md 一致的 rev-N> |
| Goal ref | task:<task-id> |
| Context manifest | context.md |
| Context revision | <与 Goal、ledger、context.md 一致> |
| Continuity | <新角色 / 复用 session-id / 新会话 + handoff 路径> |
| Session ID | <PENDING / 实际会话 ID> |
| Expected identity ACK | IDENTITY_READY dispatch_id=<dispatch-id> role=role:<role-id> team_revision=<rev-N> goal=task:<task-id> context_revision=<revision> |
| Delivery | <NOT_SENT / SENT: 时间 + 通道 + message/log 证据> |
| Identity ACK | <PENDING / VERIFIED: 完整 IDENTITY_READY 行> |
| ACK evidence | <PENDING / session + message ID、线程事件或日志位置> |

## 启动读取顺序

1. `Role profile`：确认长期职责、负责范围、明确不负责和连续性。
2. `.agent-taskgraph/PROJECT.md` 中与本职责和 Goal 有关的章节。
3. 当前任务目录的 `context.md`，按其中“必须读取”顺序加载。
4. 当前唯一 Goal、直接依赖产物和本轮 Delta。

## 身份纪律

- Role 是长期身份，Session 是可替换容器，Goal 是本次唯一工作授权。
- worker 首个状态行必须与 `Expected identity ACK` 完全一致；引用缺失、revision 漂移或职责冲突时改报 `IDENTITY_BLOCKED`，不得猜测后开工。
- 身份确认不授权扩大 Goal、writes、Frozen、权限或 Human Gates。
- 完成或换会话前把连续性 checkpoint 写回 ROLE.md/handoff；不得把聊天记录当作唯一长期记忆。
