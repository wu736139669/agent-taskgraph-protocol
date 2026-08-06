# Staffing Change: <change-id>

> Team revision: `<rev-N → rev-N+1>`
> Status: `<PROPOSED / APPROVED / APPLIED / REJECTED / ROLLED_BACK>`
> Type: `<ADD / SPLIT / TEMP_AUGMENT / REPLACE / PAUSE / RETIRE>`
> Proposed by: `<PMO + 时间>`
> Approved by: `<Owner + 时间 / PROJECT.md 精确预授权条款 / PENDING>`

## 触发证据

- 当前卡点/职责缺口：<具体证据，不写“可能更快”>
- 受影响 graph 节点和关键路径：<node-id>
- 为什么现有角色不能串行完成：<边界、负载、独立性或故障证据>
- 不加人的替代方案：<继续串行 / 调整 Goal / 暂停；成本与影响>

## 变更内容

| 动作 | Role ID | 长期职责 | 本次 Goal | writes | 生命周期 | session | model/effort | 权限/可见性 |
|---|---|---|---|---|---|---|---|---|
| <add/split/replace/pause/retire> | <role-id> | <职责> | <task:id/none> | <范围> | <persistent/task-scoped> | <new/reuse/handoff> | <配置> | <配置> |

## 职责迁移

- 原角色保留：<职责和 Goal>
- 转移给新角色：<职责、文件、产物和未决项>
- 明确不再负责：<旧角色释放的边界>
- Handoff：<ROLE.md/context.md/证据路径 + revision>
- 写入冲突检查：<无 / 解决方式>

## 图、成本与授权影响

- Graph diff：<新增/保留/暂停/作废节点及依赖变化>
- Spec 影响：<不改变 Frozen / 需要新 revision 并重新冻结>
- 新增会话与并发：<数量；变更后总数与池上限>
- 预计成本/时间变化：<可用运行时指标；不可用写 unavailable>
- 新权限、依赖或 Human Gate：<无 / 具体变化>

## 应用事务

- [ ] Owner 或精确预授权已确认
- [ ] 受影响节点已暂停且状态落盘
- [ ] spec/graph/DECISIONS 已按影响更新并验证
- [ ] ROLES.md team revision 与 ROLE.md 职责边界已更新
- [ ] Goal/context/ledger 与 handoff 已更新
- [ ] 新派发预览已确认
- [ ] 新 runtime 已完成首条 Goal 前验证
- [ ] STATUS/state validator 已通过
- [ ] 旧会话/角色已恢复、暂停或退役，无双重 owner

## 回滚条件与结果

- 最早失败边界：<配置不匹配 / handoff 不完整 / 写入冲突 / 无收益等>
- 回滚动作：<停止新会话、恢复旧 owner、回退 graph/role binding>
- 最终结果：<APPLIED / REJECTED / ROLLED_BACK + 证据>
