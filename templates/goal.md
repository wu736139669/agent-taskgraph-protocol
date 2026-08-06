# Goal: <项目/模块> <一句话目标>

> Stage: <阶段标签>（如 T1 authoring checkpoint / C11E1 implementation）
> Started: <时间>
> Task ID: `<与 graph goal_ref、queue 目录、STATUS 完全一致的稳定 ID>`
> Baseline: `<git hash + branch/upstream + clean/dirty ownership>`（B/C/D 类必须可复现且能创建 worktree；无 Git 不得派实现 worker）
> Accepted 上一阶段: `<hash>`（上一个 goal 的验收 hash，证据链；首任务可省）
> Frozen spec: `<spec.md 路径 + revision>`（只有低风险 A 类快速任务可写“内嵌本 Goal”）
> Graph node: `<graph.yaml 路径#node-id>`（低风险 A 类快速任务写“不适用”）
> Independent contract: `<CONTRACT 路径>`（额外技术合同；无则写“不适用”）
> Context manifest: `<任务目录内 context.md>`（只列引用和 revision，不复制原文）
> Context revision: `<与 context.md 一致>`
> Legal terminal: **<项目> <目标> candidate ready** 或 **<项目> <目标> redesign required: <最早失败边界>**

## Objective

（一段话：只做一件事，做成的样子，精确无歧义。写不清 = 白干一轮）

## 图输入、输出与写入范围

- 直接依赖（needs）：<node-id；无则写“无”>
- 必须读取（consumes）：<上游产物/版本>
- 必须产出（produces）：<给 verifier/下游的产物>
- 唯一写入范围（writes）：<文件/目录/外部资源；不得与并行节点重叠>
- 路由：PASS → <node-id/done>；FAIL → <repair-node-id/failed>；最大尝试 <N>

## 分配记录

- Role ref：`role:<role-id>`
- 角色职责：<引用 ROLE.md 的核心职责 + 本 Goal 为什么属于该职责>
- 角色生命周期：<persistent / task-scoped>
- 派给：<会话 ID / 岗位名>
- 分配理由：相关性（同模块历史） / 职责匹配（岗位） / 负载均衡
- 连续性：<新角色 / 复用 session-id / 新会话 + handoff 路径>
- 工作区：<worktree 路径>（分支：<branch>）
- Runtime requested：`runtime=<Execution profile runtime>; flavor=<claude|codex>; model=<批次确认的准确 id>; effort=<该模型已证明支持的 level>; permission=<准确 mode>; visibility=<visible|headless>`
- Runtime observed：<spawn 后由 PMO 填；必须与 requested 一致，未验证写 `PENDING`>
- Runtime verification：<`PENDING` / `VERIFIED`；`pre-dispatch` 或复用时 `pre-redispatch` + 时间>
- Session evidence：<真实会话 ID + PID/线程 ID + 当前 goal_ref + verification ID + 日志/metadata 路径；HAPI 还要引用本任务 runtime-evidence.json 与消息 watermark>
- Dispatch message：<`NOT_SENT` / `SENT: <时间 + 通道 + 送达证据>`；VERIFIED 前必须为 NOT_SENT>
- 完整启动方式：<可复现命令或控制面动作；不得把请求值写成实际值>

## 报告协议

- 完成 / 失败 / 卡住时通过本 Goal 记录的运行时消息通道通知 PMO（消息含任务号 + 状态 + 一句话结果）；若运行时无消息能力，写完证据后由 PMO 监控循环发现
- worker 只更新本 Goal/产品 evidence ledger 并提交证据；`.agent-taskgraph/queue/*/ledger.md`、目录状态和 STATUS.md 只能由 PMO 更新
- **不通知 = 任务未完成**，验收闸不通过

## Required State-Dependent Choice（如适用）

（必须依据状态做选择的决策点——表格式：继承状态 | 条件 | 该选什么。不适用则删本节）

## 验收标准（证据门）

- [ ] 验收命令（worker 必须跑并把输出贴回）：
- [ ] 产物路径 / diff 位置：
- [ ] 终态判定：满足全部证据门 → "candidate ready"；任一失败 → 指出最早失败边界

## Frozen（禁止触碰，明确列出）

- 不允许修改的文件/模块：
- 冻结范围（后续阶段/新系统/发布类）：

## Estimate

- 实现：Xh / 调试：Xh / 跑测证据：Xh / PMO 审查：30-60m / 硬上限：Xh / 置信度：低中高

## 完成时交付

- diff 位置 / PR 链接
- graph 节点约定的 produces 与下游交接版本
- 验收命令输出（贴回）
- 残余风险
