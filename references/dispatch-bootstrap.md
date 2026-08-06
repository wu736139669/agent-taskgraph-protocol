# Role Bootstrap And Identity ACK

在创建、复用、替换任何 worker 会话，或 Role/Team/Goal/Context revision 变化时读取本文件。

## 身份模型

- `Role` 是跨 Goal 延续的职责身份，保存在 `ROLES.md` 与 `roles/<role-id>/ROLE.md`。
- `Session` 是可替换的运行容器。换会话不换 Role；复用 Session 也不复用旧 Dispatch/ACK。
- `Goal` 是一次性工作授权，不能被 Role 的长期职责扩大。
- `context.md` 是本 Goal 的最小恢复入口，只列稳定引用、revision 和最近 Delta。

长期运行依赖文件 checkpoint，不依赖无限增长的聊天。每个 Goal 完成、失败、压缩或换会话前，把关键结论、未决项和证据指针追加到 ROLE.md/handoff；新会话从当前 Role + Context + Goal 恢复。

## 每次派发

1. 在当前任务目录由 `templates/dispatch.md` 生成 `dispatch.md`，填入具体 Role、Team revision、Goal、Context revision、连续性和全新的 Dispatch ID。
2. 从 Skill 根目录运行 `scripts/render-dispatch.py --project <project> --goal task:<id>`。它校验引用并生成 runtime-neutral bootstrap；原生 launcher 会自动调用它，HAPI/宿主线程把同一输出作为首条消息。
3. runtime 验证通过后发送 bootstrap。不得只发送 worker 名称、模糊任务或裸 Goal ref。
4. worker 在任何实现动作前输出完全匹配的 `IDENTITY_READY` 状态行；若读取不到引用、revision 不一致或职责冲突，输出 `IDENTITY_BLOCKED` 并停止。
5. PMO 从真实会话消息、线程事件或日志观察 ACK，把完整行和证据写回 `dispatch.md`、Goal、ledger；然后才完成 `active` 状态事务。

标准 ACK：

```text
IDENTITY_READY dispatch_id=dispatch:<task-id>:<attempt> role=role:<role-id> team_revision=<rev-N> goal=task:<task-id> context_revision=<revision>
```

## 新建与复用

- 首次 session：Role profile 必须已有具体职责和边界；Continuity 写 `新角色 + <session>`。
- persistent Role 复用：先完成 runtime reuse 验证，再生成新的 Dispatch ID、当前 Goal/Context revision 和 ACK；旧 ACK 对新 Goal 无效。
- 同一 Role 换 session：先写 handoff，Continuity 引用 handoff revision；新 session 仍使用同一 Role ID。
- 动态加人/拆岗/替换：Team revision 变化后，受影响会话的新 Dispatch 必须使用新 revision；旧身份 ACK 失效。

## 上下文预算

bootstrap 只携带 Role/Goal/Context 的稳定引用与 revision，不粘贴 ROLE、PROJECT、spec、历史聊天或日志正文。worker 按 `context.md` 默认不超过 8 个必读项加载，其余内容 search 后局部读取。这样角色可以长期存在，但每次会话只恢复当前任务真正需要的上下文。

## 拒绝条件

以下任一情况不得标记 active：

- 缺 `dispatch.md` 或 Dispatch ID 被复用；
- Role ref/profile/lifecycle、Team revision 与 registry/ledger 不一致；
- Goal 或 Context revision 漂移；
- 首条消息只说“你是某 worker”而没有稳定身份引用；
- ACK 为 `PENDING`、内容不完全匹配或没有真实消息/日志证据；
- 复制上一 Goal/Session 的 ACK；
- worker 报 `IDENTITY_BLOCKED` 后仍继续实现。
