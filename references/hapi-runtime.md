# HAPI Runtime Adapter

只在 `PROJECT.md` 的 `已启用可选适配器` 包含 `hapi`，或 Owner 在本批次明确选择 HAPI 后读取本文件。仅检测到 `hapi` 命令、runner 或历史会话时，不得自动启用。

## 选择规则

- 不再用 `native-first` 静默选择。首次接入把探测到的 HAPI 与真实可用 native 路径放在同一选择表；PROJECT 已记录 Preferred runtime=HAPI 且 Hub READY 时优先推荐 HAPI，但仍由 Owner 明确确认。
- 选择 HAPI 前说明它会怎样改变会话可见性、远程控制、成本、权限和日志位置；结果写入 `PROJECT.md` 的 Execution profile，并与运行机器、flavor、模型策略、准确 permission 和 fallback 一次确认。
- HAPI 不满足当前 Goal 所需能力时，只能使用 Execution profile 已确认的准确 fallback；fallback=none 时停止并报告，禁止静默换成 native。若 runtime、machine、flavor、权限或可见性变化，先把 profile 改回 `PENDING` 并确认 diff。

## 能力探测

先区分三台逻辑机器：Owner 的操作端、PMO 会话真正执行 Bash 的机器、HAPI runner 执行 worker 的机器。它们可以相同，也可以不同。操作端没有 HAPI CLI 不是失败证据；PMO 只看到 inspect/ping 工具也不是失败证据。

按当前安装版本提供的命令、正式 Hub API 和宿主工具做只读探测：

1. 在线机器：从当前 Skill 根目录运行 `scripts/hapi-hub-session.py machines`，不要误用目标项目中的同名相对路径。它即使遇到 settings 中已离线的旧 machine ID 也会返回脱敏在线候选。PMO 用名称/host 让 Owner 选择，把准确 ID 写入 Execution profile；不得自动改 HAPI settings。
2. 正式控制面：对选中 ID 运行 `scripts/hapi-hub-session.py probe --machine-id '<id>'`。返回 `READY` 代表已认证 Hub、已选中在线 runner，且 helper 可使用 spawn/inspect/message-observation/path-preflight/catalog/reuse/archive 路径。Goal 发送能力仍须单独确认。
3. CLI（若 PMO 执行机安装）：`command -v hapi`、`hapi auth status`。
4. runner（若 CLI 可用）：先读 `hapi runner --help`，再使用版本实际支持的 status/list 命令。
5. 宿主工具：记录当前真实暴露的 spawn/create、inspect、message/ping、resume 和 stop 能力；工具缺失时继续检查正式 Hub helper。
6. 目录与模型：确定 flavor 后运行 `scripts/hapi-hub-session.py catalog --machine-id '<id>' --flavor <claude|codex>`。Codex 目录和每个模型的 effort 来自该 runner 动态能力；Claude 来自 HAPI presets + custom models。只从输出中推荐组合。spawn/reuse 还会通过 runner 的 paths API 确认 worktree 已存在。

`probe` 输出只含脱敏 URL、machine ID/名称/host 与能力；不得输出 JWT、CLI token 或完整 settings。命令存在或 `runner list` 只能证明局部能力；正式 helper `READY` 才证明当前 PMO 可以自动请求 runner 创建。不得从 settings 读取 token 后拼进内联 `curl`，也不得把认证值写入 shell history、Goal、ledger 或日志。不得自动启动、重启或重配 runner/hub，也不得修改认证设置，除非 Owner 对该动作单独授权。

`hapi runner start --help` 不是只读探测：部分版本会忽略 `--help` 并直接重启 runner。只允许读取父命令 `hapi runner --help`，再调用其中明确列出的只读 `status/list`；未经单独授权不得调用任何 `start/stop/restart` 变体。

## 派发硬门

- HAPI 创建路径按顺序选择：宿主正式 spawn 工具 → `scripts/hapi-hub-session.py` 正式 Hub API → Owner HAPI UI。前两项都不可用才允许走 PROJECT 已确认的原生 fallback；不得只因 MCP 缺少 spawn 工具就声称“HAPI 不存在”。
- Owner 批准派发预览后，PMO 应自行执行 helper；不得只把内部命令丢给普通 Owner。若有多台在线 runner，使用 PROJECT 已确认的 machine ID 或在预览中让 Owner 选择，不能用模糊的“本机”。
- 不得在 Claude worker/PMO 的普通 Bash 中执行 `hapi claude ...` 或 `hapi codex ...`，再把这个短暂子进程登记成 runner 创建的可见会话。helper 使用的是 HAPI Web UI 同一正式接口 `/api/machines/:id/spawn`，不是临时子进程。
- 不得把 HAPI 启动命令接到 `head`、`tail`、`grep` 等会提前关闭 stdin 的管道；wrapper 必须保持 stdin，直到注册完成。
- 模型标识作为一个完整参数传递并正确引用。包含方括号等 shell 元字符的模型名必须加引号，避免被 zsh 展开。
- `model` 与 `effort` 必须是当前 runner 目录中被证明可用、Owner 在整批预览确认的显式值；`default`、`auto`、`pending`、`待确认` 等占位值不得用于 spawn 或生成 VERIFIED 证据。Codex effort 必须出现在所选模型自己的 supported 列表。`permission=default` 可以是 Execution profile 中明确选择的平台标准权限，但这意味着执行中仍可能频繁询问。
- 禁止直接调用 runner 本地 `/spawn-session`：它不是完整的远程配置接口，可能忽略 model/effort/permission。请求 JSON、HTTP 2xx、返回的 session ID 和 ledger 中的计划值都不能证明参数已生效。
- spawn 后保持任务在 `inbox`，且**先不要 `ping_peer`**。`hapi-hub-session.py spawn` 重新验证 runner 目录与模型目录，再等待 Hub metadata，核对 goal_ref、session、machine、PID、cwd、flavor、model、effort、permission、runner 身份、active/running、idle/not-thinking 和零消息 watermark；成功时写当前 Goal 专属 `runtime-evidence.json`。UI 创建的全新会话可用 `verify` 执行同一硬门。
- 同一 persistent Role 复用旧 session 时必须运行 `reuse`。它允许历史消息，但要求会话 active/running、配置匹配、idle/not-thinking，并为新 Goal 写新的 `verification_id`、`goal_ref` 和消息 watermark。禁止复制上一 Goal evidence 或把历史 `pre-dispatch` 当作本次核验。
- 把 helper JSON 保存为当前 inbox 任务目录的 `runtime-evidence.json`。只有输出为 `VERIFIED` 才能更新本次 `dispatch.md` 的真实 Session ID，并用 `scripts/render-dispatch.py --project <project> --goal task:<id>` 生成首条 Role bootstrap。通过 `ping_peer`/等价消息能力发送后，从真实 HAPI 消息观察完全匹配的 `IDENTITY_READY`，把 ACK 与 message/session 证据写回 dispatch/Goal/ledger，才迁移到 `active`。`validate-state.py` 会核对 goal_ref、phase、idle、catalog、machine、requested/observed、watermark 和身份 revision；shell 退出码 0、API 返回成功或人工推断都不构成合格证据。`verify-hapi-session.py` 旧日志解析器只用于诊断/audit，不能替代当前 Hub evidence 硬门。
- 配置不匹配时标记 `RUNTIME_CONFIG_MISMATCH`：不要发 Goal，不要让 Owner 逐次批准工具。helper 默认只归档它本次刚创建且尚未派发的会话；不得停止 runner/hub/其他会话。然后修正参数、改由 HAPI UI，或走 PROJECT.md 已确认 fallback。若 Goal 已经发送，保留失败证据并按失败重试处理；事后配置变更只能用 audit 记录恢复，不能把原派发改写为合格。
- 每个 Goal/ledger 记录 runtime=`hapi`、`Runtime requested`、`Runtime observed`、`Runtime verification`、完整创建方式、会话 ID、PID、runner/peer 观察证据、日志路径、Dispatch ID、首条 bootstrap 送达与 Identity ACK 证据和 fallback。不得记录认证 token、完整 settings 或未脱敏诊断输出。

自动派发示例（Skill 根目录执行；普通 Owner 无需手写）。派发预览先运行 dry-run：

```bash
scripts/hapi-hub-session.py spawn \
  --directory '<worktree>' --flavor claude \
  --model 'deepseek-v4-flash[1m]' --effort max \
  --permission yolo --goal-ref 'task:<task-id>' --dry-run
```

Owner 批准预览后才去掉 `--dry-run`，并把证据写进 inbox 任务：

```bash
scripts/hapi-hub-session.py spawn \
  --directory '<worktree>' --flavor claude \
  --model 'deepseek-v4-flash[1m]' --effort max \
  --permission yolo --goal-ref 'task:<task-id>' \
  --evidence-output '<project>/.agent-taskgraph/queue/inbox/<task-id>/runtime-evidence.json'
```

只有输出 `VERIFIED` 后才渲染并使用 `ping_peer` 发送 Role bootstrap，不直接发送裸 Goal。复用已有角色会话：

```bash
scripts/hapi-hub-session.py reuse \
  --session-id '<hapi-session-id>' \
  --directory '<worktree>' --flavor claude \
  --model '<approved-model>' --effort '<approved-effort>' \
  --permission '<approved-permission>' --goal-ref 'task:<new-task-id>' \
  --evidence-output '<project>/.agent-taskgraph/queue/inbox/<new-task-id>/runtime-evidence.json'
```

## 会话与消息

- 同一模块连续工作优先复用同一 Role 的 HAPI session，但每个 Goal 必须先通过 `reuse`；thinking 状态、目录/配置不匹配或无法生成新 watermark 时不发送消息。并行任务、污染失败和独立 reviewer 新开隔离会话。
- 宿主暴露 `inspect_peer` / `ping_peer`（或等价工具）时优先使用宿主工具；shell 命令只作为已验证的 fallback。工具名以当前环境实际列表为准。
- 聊天只作为控制通道。Goal、冻结规格、图节点、验收和长期状态仍必须落盘。
- `active/idle`、runner 存活或聊天里的“完成”都不是验收证据；仍需 legal terminal、revision、测试证据和独立 reviewer。

## HAPI 监控适配器

- HAPI session 是独立 peer，不属于 Codex `spawn_agent` tree 或 native thread list。`wait_agent`/`wait_threads` 不能等待 HAPI 完成，禁止因为 PMO 自身运行在 Codex 中就选择它们。
- 主事件路径：Goal 要求 worker 在完成、失败、阻塞时向 PMO HAPI session 发消息；PMO 收到后用 `inspect_peer`/Hub metadata 核对消息与 session，再对账 ledger/产物。
- 周期兜底：PROJECT 记录 `Monitoring wait primitive = HAPI event + timer-cell/functions.wait(real cell_id)`，`Monitoring observe primitive = inspect_peer/session metadata/log + ledger`，targets 从 active/review ledger 的 HAPI Session ID 解析。PMO 必须先实际启动 timer/observe cell；只有工具返回真实 `cell_id` 才能用 `functions.wait` 恢复。
- `functions.wait` 本身不是观察，但成功恢复并完成 `inspect_peer`/日志读取的 cell 构成一次合格监控周期。`cell not found` 记为 `WAIT_TOOL_MISROUTE`，停止猜 ID，并重建 HAPI timer/observe cell；不得切换到 `wait_agent`。
- Owner 要求“可见等待”时，HAPI 会话本身仍在侧栏可见；若宿主不能为 HAPI target 生成原生等待卡片，应如实说明，不能用一个看不见 HAPI 的原生 wait 卡片冒充监控。

## 监督与清理

- 使用当前版本真实提供的 wait/observe 能力或 HAPI 日志作为观察信号；队列目录和 ledger 仍是动态事实源。
- 只终止本批次明确拥有的会话或进程。runner、hub 和其他用户会话不属于某个 Goal，不能在任务收尾时顺带停止。
- HAPI 诊断输出可能包含本机设置或凭据材料。不要把完整 `hapi doctor`、settings、环境变量或日志直接写入仓库、Goal、ledger、报告或公开 Issue；只摘录脱敏后的必要状态。
- 创建、续接或停止失败时保留失败证据，按 fallback 降级；不得把历史会话或已退出状态描述为仍在运行。
