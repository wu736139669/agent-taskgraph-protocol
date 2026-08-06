# Role: <岗位名称>

> 这是长期职责身份，不是本次任务说明。本次范围、交付和验收只写入对应 Goal。

| 字段 | 值 |
|---|---|
| Role ID | <稳定小写 ID，如 frontend-ui> |
| Team revision | <当前 rev-N> |
| Origin | <initial:<spec/graph revision> / staffing:<change-id>> |
| 名称 | <面向 Owner 的岗位名> |
| 生命周期 | <persistent / task-scoped> |
| 状态 | <available / assigned / paused / retired> |
| 核心职责 | <长期负责什么> |
| 负责范围 | <模块、目录、产物或业务域> |
| 明确不负责 | <职责边界；方案决策和越界修改默认不负责> |
| 默认能力 | <需要的工具、领域知识、测试能力> |
| 默认 Runtime | <runtime/flavor/model/effort/permission/visibility 建议；实际值仍须每次派发验证> |
| 当前 Goal | <none / task:<task-id>> |
| 当前 Session ID | <PENDING / N/A / 真实会话 ID> |
| 连续性记录 | <最近完成的 Goal、关键上下文/handoff 路径；不得只存在聊天记忆> |
| 最后更新 | <时间 + PMO> |

## 开工必读

- `.agent-taskgraph/PROJECT.md`
- 当前冻结 spec、graph 节点、Goal、ledger 与直接依赖产物
- 与本职责有关的 `DECISIONS.md` 标题和连续性记录

## 职责规则

- 角色负责长期判断边界，Goal 负责单次授权；角色不能扩大 Goal。
- 同一 persistent 角色不得并发执行多个 active/review Goal。
- 同模块串行任务优先复用本角色及其可恢复会话；失败污染、上下文耗尽或隔离要求出现时换会话，但保留同一 Role ID 并写 handoff。
- task-scoped 角色完成后标记 `retired`；persistent 角色完成后回到 `available`。
- 动态新增、拆分、替换、暂停或退役必须引用 staffing change；不能只改会话名称或聊天称呼。

## 连续性历史（追加式）

| 时间 | Goal | Session ID | 状态变化 | handoff / 证据 |
|---|---|---|---|---|
| | | | | |
