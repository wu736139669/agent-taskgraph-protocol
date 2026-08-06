# Context Manifest: <稳定 Task ID>

> Task ID: `<与 Goal、queue 目录一致>`
> Revision: `<递增整数或内容 hash>`
> Mode: `<lean / balanced / deep>`
> Budget exception: `<none / 超过默认 8 个必读项的原因与 Owner/PMO 记录>`

## 必须读取（默认不超过 8 项）

| 路径或稳定引用 | Revision / 范围 | 为什么本 Goal 必须读 |
|---|---|---|
| `.agent-taskgraph/PROJECT.md` | relevant sections | 项目硬约束与运行策略 |
| `.agent-taskgraph/roles/<role-id>/ROLE.md` | current | 职责边界与连续性 |
| `<frozen spec>` | `<revision>` | 本次冻结需求 |
| `<graph#node>` | `<revision>` | 本节点依赖与路由 |
| `<current goal>` | current | 单次执行合同 |

## 按需检索（先搜索，再局部读取）

| 路径/范围 | 触发条件 | 检索提示 |
|---|---|---|
| `<source directory>` | 需要确认实现细节时 | `<symbol / rg pattern>` |
| `.agent-taskgraph/DECISIONS.md` | 命中本模块决策时 | `<heading / keyword>` |

## 明确不加载

- 无关已完成任务和 archive 全量内容
- 其他 worker 的完整聊天记录
- 未被 Goal 引用的长日志、构建产物和大文件
- `<本任务额外排除项>`

## 最近 Delta

| 时间 | 来源 | 新事实/决策/阻塞 | 已落盘到 | 是否需要通知 worker |
|---|---|---|---|---|
| | | | | |
