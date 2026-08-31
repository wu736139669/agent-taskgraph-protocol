# Agent Team Protocol

仅在进入 **Team** 模式时读取。本文件是逻辑团队合同；具体如何创建和控制原生 Agent，见 [`native-runtimes.md`](native-runtimes.md)。

## 1. 术语

| 术语 | 定义 |
|---|---|
| Team | 为一个共同 Outcome 临时组成的逻辑工作单元 |
| Lead | 唯一的协调、依赖管理和最终汇报责任人 |
| Member | Team 中实际运行的原生 Agent；每次只拥有一个 active Task |
| Role | Member 对 Team Outcome 承担的职责，不等同于某个固定 Agent |
| Task | 可独立交付、可验收并拥有明确 Owner 的工作节点 |
| Handoff | 上游交给下游的结果、产物、验证和风险 |
| Integrator | 消费 Handoffs、解决冲突并运行团队级验收的职责 |
| Human Gate | 必须由用户决定的权限扩大或外部副作用 |

协议正文统一使用这些术语，不再混用 PMO、Worker 等近义名称。`Goal` 只表示单个 Task 内的目标字段；Skill frontmatter 可以保留搜索触发词。

## 2. Team Charter

Lead 在创建 Members 前确定：

| 字段 | 要求 |
|---|---|
| Protocol version | 当前 Agent TaskGraph 版本 |
| Team ID | 当前批次的短稳定标识 |
| Outcome | 一个团队级可观察结果 |
| Non-goals | 当前批次明确不做什么 |
| Topology | `hub-and-spoke` 或 `peer-capable` |
| Lead | 唯一协调责任人 |
| Integrator | Lead 或明确指定的 Member |
| Roster | 只列有当前职责的 Roles 和 Members |
| Task Graph | Owner、Needs、Produces、Consumer、Writes、Acceptance |
| Decision boundaries | Member、Lead、Human Gate 各自决定什么 |
| Definition of done | 集成后的团队级完成条件 |
| Lifecycle phase | 当前阶段和最后更新时间 |

短 Team 可以在对话和原生任务列表中维护 Charter。跨会话、依赖复杂或需要审计时写入 `.agent-taskgraph/`。

## 3. 角色

角色根据 Task Graph 动态创建，不使用固定组织架构。

### Lead（必需）

- 建立 Charter 和 Task Graph
- 选择 Members，分配 Owner
- 保护依赖、写入所有权和决策边界
- 处理跨 Task 冲突与阻塞
- 组织 Review、Integration 和 Team 结束

### Builder / Specialist（按需）

- 对一个边界清楚的 Task 产出负责
- 只在 Task 合同范围内决策和写入
- 发现跨范围问题时报告，不擅自扩大范围

### Reviewer（按风险创建）

- 独立于被审查 Task 的实现者
- 根据需求、diff、测试和风险给出证据化结论
- 默认只读，不以重新实现代替审查

### Integrator（必需职责）

- 消费各 Task Handoffs
- 解决集成冲突并运行团队级验证
- 确认最终结果符合 Team Outcome

Integrator 默认由 Lead 兼任。一个 Role 可以在同一批次连续承担多个 Tasks，但必须逐个完成或交接。

## 4. Task Graph

每个 Task 至少包含：

```text
ID / Owner / Role / Goal / Needs / Produces / Consumer / Writes / Acceptance / Status
```

规则：

- `Needs` 只列真实前置依赖；无依赖写 `none`。
- 只有依赖完成并提供 Handoff 后，下游 Task 才进入 `ready`。
- 独立 Tasks 可以并行；共享 Writes 的 Tasks 必须串行或使用独立 worktree。
- 每个关键产出必须有明确 Consumer，或由 Integrator 消费。
- 不为“开会”“同步”等无可验收产出的过程动作创建伪 Task。

Task 状态：

```text
pending → ready → active → review → done
                         ↘ blocked / failed / cancelled
```

## 5. 协作事件

### Assignment

Lead 的派发消息必须让空白上下文 Member 直接开始：

```text
Role：<role>
Task：<id>
Goal：<可观察结果>
Read：<3-6 个路径、符号或直接 Handoff>
Writes：<允许写入的范围>
Does not own：<明确排除项>
Needs：<none / 前置 Tasks>
Produces for：<下游 Task / Integrator>
Acceptance：<命令或可观察检查>
完成时发送 HANDOFF；阻塞时发送 BLOCKED。
```

### READY

Member 确认 Task、范围、依赖和验收均清楚。合同矛盾或依赖未满足时发送 `BLOCKED`，不能假装开工。

### BLOCKED

至少包含：

- Task ID
- 阻塞事实
- 已尝试内容
- 需要的交付或决策
- 不处理会影响什么

Member 决定 Task 范围内的实现细节；跨 Task 范围、架构和 Owner 冲突交给 Lead；权限扩大、删除、迁移、发布等外部副作用交给 Human Gate。

### HANDOFF

至少包含：

- 结果以及是否达到 Acceptance
- 修改或产物路径
- 实际运行的验证及结果
- 未解决风险
- Consumer 必须知道的事实

Consumer 以产物和 Handoff 为事实源，不读取上游完整聊天。

### REVIEW

Reviewer 返回：

- `PASS` 或 `CHANGES_REQUIRED`
- 对应需求或风险
- 代码、diff、测试或产物证据
- 最小修正边界

修正优先返回原 Owner。Reviewer 不接管实现，除非 Lead 明确重新分配。

## 6. 生命周期

| 阶段 | Lead 的动作 | 退出条件 |
|---|---|---|
| `forming` | 确认 Outcome、Non-goals、拓扑、Roles 和写入所有权 | Charter 完整，每个 Member 都有真实职责 |
| `briefing` | 建立 Task Graph，派发自包含合同 | 首批无依赖 Tasks 已 `READY` |
| `executing` | 维护依赖、范围、状态和决策；处理 `BLOCKED` | 关键 Tasks 已交付或 Team 停止 |
| `reviewing` | 检查成员自验；按风险安排 Reviewer | 关键 Tasks 通过或被明确失败/取消 |
| `integrating` | 消费 Handoffs、解决冲突、运行团队级验收 | Outcome 达成或形成明确阻塞 |
| `complete` | 结束 Members、归档状态、汇报结果 | 完成条件全部满足 |
| `stopped` | 保存已完成产物并说明停止原因 | 用户终止或无法安全继续 |

`stopped` 原因必须具体，例如：能力不足、权限阻塞、无法隔离写入、不可安全集成，或协调成本超过收益。

## 7. 持久化事实源

持久化文件采用稳定的英文标题和字段名，字段值可以使用项目主要语言。

| 文件 | 唯一职责 |
|---|---|
| `PROJECT.md` | 稳定项目事实、命令和长期约束 |
| `TEAM.md` | 当前 Team Charter、Roster 和决策边界 |
| `PLAN.md` | 当前 Task Graph、依赖和集成路径 |
| `STATUS.md` | 生命周期、最新已验证进展、阻塞和下一步 |
| `DECISIONS.md` | 改变 Charter、Task Graph、权限或外部效果的决定 |
| `tasks/<id>.md` | 单个 Task 合同、事件摘要和最终 Handoff |
| `archive/` | 已结束 Team 批次的稳定记录 |

不要在多个文件重复维护同一状态，也不要保存聊天全文、长日志或可从代码重新得到的信息。

## 8. 推荐 Team 形态

这些是起点，不是固定组织架构：

### Development Team

- Lead/Integrator
- 1-3 个按模块或产出划分的 Builders
- 高风险或跨模块时增加 Reviewer

### Research Team

- Lead/Synthesizer
- 按问题域划分的 Researchers
- 高可信结论需要 Evidence Reviewer

### Review Team

- Lead
- 按正确性、安全、测试或产品意图划分的只读 Reviewers
- Lead 去重并形成最终结论

Task Graph 中没有工作，就不创建对应 Role 或 Member。
