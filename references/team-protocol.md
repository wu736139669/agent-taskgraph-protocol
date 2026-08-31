# Agent Team Protocol

进入 `Team` 模式时读取。本协议定义逻辑团队；Codex 和 Claude Code 的具体实现由 [`native-runtimes.md`](native-runtimes.md) 映射。

## 1. Team Charter

Lead 在创建成员前确定：

| 字段 | 要求 |
|---|---|
| Team outcome | 一个团队级可观察结果 |
| Non-goals | 当前批次明确不做什么 |
| Topology | `hub-and-spoke` 或 `peer-capable` |
| Lead | 唯一协调和集成责任人 |
| Roster | 只列有当前任务的角色/成员 |
| Task graph | Task、Owner、Needs、Produces、Writes、Acceptance |
| Decision rule | 成员、Lead、Human Gate 分别决定什么 |
| Done definition | 集成后的团队级完成条件 |
| Lifecycle phase | 当前所处阶段 |

Team Charter 可以展示在对话中；需要跨会话恢复时写入 `TEAM.md` 和 `PLAN.md`。

## 2. 角色模型

角色按任务动态创建，不使用固定组织架构。

### Lead（必需）

- 建立 Charter 和任务图
- 分配 Owner、保护依赖与写入范围
- 处理跨任务冲突和决策
- 组织 Review、Integration、Disband

### Builder / Specialist（按需）

- 对一个边界清楚的产出负责
- 只在任务合同范围内决策和写入
- 发现跨范围问题时报告，不擅自扩张范围

### Reviewer（按风险创建）

- 独立于被审查任务的实现者
- 根据目标、diff、测试和风险给出证据化结论
- 默认只读；不以顺手重写代替审查

### Integrator（必需职责，可由 Lead 兼任）

- 消费各 Task handoff
- 解决集成冲突并运行团队级验证
- 确认最终结果符合 Team outcome

一个 Agent 同时只能拥有一个 active Task。一个角色可在同一批次连续承担多个 Task，但必须逐个完成或交接。

## 3. 任务图

每个 Task 至少包含：

```text
id, owner, role, goal, needs, produces, consumes, writes, acceptance, consumer, status
```

规则：

- `needs` 只列真实前置依赖；无依赖写 `none`。
- 只有依赖完成并提供 handoff 后，下游 Task 才进入 `ready`。
- 独立 Task 可以并行；共享写入范围的 Task 必须串行或改用独立 worktree。
- 每个关键产出必须有下游消费者或由 Integrator 消费。
- 不为过程动作创建无产出的伪 Task。

Task 状态：

```text
pending → ready → active → review → done
                         ↘ blocked / failed / cancelled
```

## 4. 协作协议

### Assignment

Lead 派发的信息应让空白上下文成员直接开始：

```text
你是 <role>，负责 Task <id>。
目标：...
读取：...
写入：...
不负责：...
Needs：...
产出给：...
验收：...
完成时发送 HANDOFF；阻塞时发送 BLOCKED。
```

### READY

成员确认目标、范围和依赖。如果合同矛盾或依赖未满足，应发送 `BLOCKED`，不能假装开工。

### BLOCKED

至少包含：

- Task ID
- 阻塞事实
- 已尝试内容
- 需要的交付或决策
- 不处理会影响什么

成员可决定本任务范围内的实现细节；跨任务范围、架构冲突、Owner 冲突交给 Lead；权限扩大、删除、迁移、发布和其他外部副作用交给 Human Gate。

### HANDOFF

至少包含：

- 结果与是否达到 Acceptance
- 修改/产物路径
- 实际运行的验证及结果
- 未解决风险
- 下游消费者必须知道的事实

下游以产物和 handoff 为事实源，不读取上游完整聊天。

### REVIEW

Reviewer 返回：

- `PASS` 或 `CHANGES_REQUIRED`
- 对应需求/风险
- 代码、diff、测试或产物证据
- 最小修正边界

修正优先回到原 Owner；Reviewer 不接管实现，除非 Lead 明确重新分配。

## 5. 生命周期

### forming

- 确认 Team outcome、非目标和运行时能力
- 选择拓扑与成员
- 划分写入所有权

退出条件：Charter 完整，成员都有真实职责。

### briefing

- 建立任务图和依赖
- 为每个成员创建自包含合同
- 成员确认 `READY` 或报告合同问题

退出条件：首批无依赖 Task 可执行。

### executing

- 独立 Task 并行推进
- Lead 维护依赖、状态、决策和范围
- 只在完成、阻塞、异常或需要决策时介入

退出条件：关键 Task 已进入 handoff/review，或团队停止。

### reviewing

- Lead 检查成员自验和产物
- 按风险安排独立 Reviewer
- 修正返回原 Owner

退出条件：所有关键 Task 通过或被明确接受为失败/取消。

### integrating

- Integrator 消费 handoff、解决冲突
- 运行团队级测试/构建/验收
- 检查未披露风险和外部副作用

退出条件：Team outcome 达成，或形成明确阻塞。

### complete / stopped

- 停止或结束不再需要的 Agent
- 更新/归档持久化状态
- 汇报结果、验证、风险和未完成项

`stopped` 必须说明原因：用户终止、能力不足、权限阻塞、不可安全集成或成本超过收益。

## 6. 推荐团队形态

这些是可选起点，不是固定组织架构。

### Development Team

- Lead/Integrator
- 1-3 个按模块划分的 Builders
- 高风险或跨模块时增加 Reviewer

### Research Team

- Lead/Synthesizer
- 多个按问题域划分的 Researchers
- 一个 Evidence Reviewer（需要高可信结论时）

### Review Team

- Lead
- 按安全、正确性、测试、产品意图划分的只读 Reviewers
- Lead 去重并形成最终结论

不要创建成员来填满模板；任务图中没有工作就不创建该角色。
