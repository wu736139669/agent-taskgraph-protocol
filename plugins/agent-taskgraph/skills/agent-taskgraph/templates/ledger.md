# 台账记录：<稳定 Task ID>

> 每个任务一条记录。状态只有 PMO 能改。文件放在 `queue/<state>/<task>/ledger.md`。

| 字段 | 值 |
|---|---|
| 任务 ID | <与 queue 目录名、graph goal_ref、STATUS 完全一致> |
| Goal ref | task:<task-id> |
| Goal current path | queue/<当前 state>/<task-id>/goal.md |
| Context manifest | context.md |
| Context revision | <与 context.md 一致的递增整数或内容 hash> |
| Role ref | role:<role-id> |
| Role lifecycle | <persistent / task-scoped> |
| Role profile | roles/<role-id>/ROLE.md |
| Role continuity | <新角色 / 复用 session-id / 新会话 + handoff 路径> |
| Reviewer Role ref | <active 前写 PENDING；review/done 写独立 role:<reviewer-role-id>> |
| Reviewer Role profile | <active 前写 PENDING；review/done 写 roles/<reviewer-role-id>/ROLE.md> |
| Frozen spec | <spec.md 路径 + revision> |
| Graph node | <graph.yaml#node-id；快速任务写“不适用”> |
| 依赖/路由 | needs: <node-id>；PASS → <node-id/done>；FAIL → <node-id/failed> |
| 状态 | <inbox / active / review / done / failed 中唯一当前值> |
| 负责人 | <会话 ID / 岗位名> |
| 分配理由 | 相关性 / 职责匹配 / 负载均衡 |
| 轮次 | 第 1 次（重试 +1） |
| 开始时间 | |
| 最后更新 | |
| 验收结果 | ✅ / ❌（附命令输出） |
| 日志指针 | <当前运行时的会话日志、rollout JSONL、Terminal metadata 或等价证据路径——watch 监视器的输入> |
| Runtime requested | runtime=<name>; flavor=<claude/codex/native>; model=<id>; effort=<level>; permission=<mode>; visibility=<visible/headless> |
| Runtime observed | runtime=<name>; flavor=<claude/codex/native>; model=<id>; effort=<level>; permission=<mode>; visibility=<visible/headless> |
| Runtime verification | <PENDING / VERIFIED> |
| Session ID | <真实会话/线程 ID；inbox 未创建时写 PENDING> |
| Runtime evidence | <HAPI 写任务目录内 runtime-evidence.json；其他 runtime 写实际设置、PID/线程和日志/metadata 的脱敏证据路径；inbox 未创建时写 PENDING> |
| Dispatch message | <NOT_SENT / SENT: 时间 + 通道 + 送达证据> |
| 等待归属 | 在等谁：<PMO / worker / Owner>；等什么：<验收 / 指示 / 外部条件>；静默多久算异常：<N 分钟> |

## 备注

（卡住原因、方案变更、Owner 的临时指示等——供复盘的原始记录）

## 状态转换历史（追加式）

| 时间 | from → to | 操作者 | 依据/证据 | 唯一下一步 |
|---|---|---|---|---|
| | | PMO | | |
