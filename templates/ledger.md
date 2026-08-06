# 台账记录：<稳定 Task ID>

> 每个任务一条记录。状态只有 PMO 能改。文件放在 `queue/<state>/<task>/ledger.md`。

| 字段 | 值 |
|---|---|
| 任务 ID | <与 queue 目录名、graph goal_ref、STATUS 完全一致> |
| Goal ref | task:<task-id> |
| Goal current path | queue/<当前 state>/<task-id>/goal.md |
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
| 等待归属 | 在等谁：<PMO / worker / Owner>；等什么：<验收 / 指示 / 外部条件>；静默多久算异常：<N 分钟> |

## 备注

（卡住原因、方案变更、Owner 的临时指示等——供复盘的原始记录）

## 状态转换历史（追加式）

| 时间 | from → to | 操作者 | 依据/证据 | 唯一下一步 |
|---|---|---|---|---|
| | | PMO | | |
