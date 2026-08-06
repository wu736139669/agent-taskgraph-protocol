# HAPI Runtime Adapter

只在 `PROJECT.md` 的 `已启用可选适配器` 包含 `hapi`，或 Owner 在本批次明确选择 HAPI 后读取本文件。仅检测到 `hapi` 命令、runner 或历史会话时，不得自动启用。

## 选择规则

- 公开默认仍是 `auto + native-first`。首次接入可把“检测到 HAPI”列为可选项，但必须让 Owner 决定是否启用。
- 选择 HAPI 前说明它会怎样改变会话可见性、远程控制、成本、权限和日志位置；选择结果与 fallback 顺序写入 `PROJECT.md`。
- HAPI 不满足当前 Goal 所需能力时，按已确认 fallback 使用 Claude/Codex 原生运行时。若 fallback 改变成本、权限或可见性，派发前再次确认。

## 能力探测

按当前安装版本提供的命令和宿主工具做只读探测，不假定所有环境具有同名能力：

1. CLI：`command -v hapi`
2. 登录：`hapi auth status`
3. runner：先读 `hapi runner --help`，再使用版本实际支持的 status/list 命令
4. 控制面：确认宿主是否真实暴露 spawn/create、inspect、message/ping、resume 和 stop 能力
5. 工作区：确认 runner 允许目标 cwd，且 flavor、模型、effort 和权限参数受支持

命令存在不等于能远程创建会话；`runner list` 只能证明观察能力，不能证明 spawn 能力。不得自动启动、重启或重配 runner/hub，也不得修改认证设置，除非 Owner 对该动作单独授权。

`hapi runner start --help` 不是只读探测：部分版本会忽略 `--help` 并直接重启 runner。只允许读取父命令 `hapi runner --help`，再调用其中明确列出的只读 `status/list`；未经单独授权不得调用任何 `start/stop/restart` 变体。

## 派发硬门

- 不得在 Claude worker/PMO 的普通 Bash 中执行 `hapi claude ...` 或 `hapi codex ...`，再把这个短暂子进程登记成 runner 创建的可见会话。必须使用宿主真实暴露的 HAPI runner 控制面/API，或请 Owner 从 HAPI 界面创建。
- 不得把 HAPI 启动命令接到 `head`、`tail`、`grep` 等会提前关闭 stdin 的管道；wrapper 必须保持 stdin，直到注册完成。
- 模型标识作为一个完整参数传递并正确引用。包含方括号等 shell 元字符的模型名必须加引号，避免被 zsh 展开。
- `/spawn-session` 等非稳定内部接口即使接受 `model`、`effort`、`permissionMode` 字段，也可能只创建默认配置的会话。请求 JSON、HTTP 2xx、返回的 session ID 和 ledger 中的计划值都不能证明参数已生效。
- spawn 后保持任务在 `inbox`，且**先不要 `ping_peer`**。从 runner list/inspect 和该会话日志取得真实 session ID、PID、cwd、flavor、model、effort、permission；使用 `scripts/verify-hapi-session.py` 做 pre-dispatch 校验。该脚本还会拒绝已经收到消息的会话，防止事后把手动改成 yolo 冒充派发前已生效。
- 把校验器的 JSON 输出保存为当前 inbox 任务目录的 `runtime-evidence.json`。只有输出为 `VERIFIED`，同时 runner list 与 inspect/peer 等价能力确认 `active/running` 后，才能把验证结果写入 Goal/ledger、发送第一条 Goal，再迁移到 `active`。`validate-state.py` 会核对该证据文件并随任务目录保留到 done；shell 退出码 0、API 返回成功或人工推断都不构成 spawn 成功证据。
- 配置不匹配时标记 `RUNTIME_CONFIG_MISMATCH`：不要发 Goal，不要让 Owner 逐次批准工具；停止本批次刚创建且尚未派发的会话，改由 HAPI UI 按获批参数创建/配置，或走 PROJECT.md 已确认 fallback。若 Goal 已经发送，保留失败证据并按失败重试处理；事后配置变更只能用 `--phase audit` 记录恢复，不能把原派发改写为合格。
- 每个 Goal/ledger 记录 runtime=`hapi`、`Runtime requested`、`Runtime observed`、`Runtime verification`、完整创建方式、会话 ID、PID、runner/peer 观察证据、日志路径、首条消息送达证据和 fallback。不得记录认证 token、完整 settings 或未脱敏诊断输出。

示例（Skill 根目录执行；普通 Owner 无需手写）：

```bash
scripts/verify-hapi-session.py \
  --log "$HOME/.hapi/logs/<session-log>.log" \
  --session-id '<hapi-session-id>' --pid '<pid>' \
  --cwd '<worktree>' --flavor claude \
  --model '<approved-model>' --effort '<approved-effort>' \
  --permission '<approved-permission>' --json \
  > '<project>/.agent-taskgraph/queue/inbox/<task-id>/runtime-evidence.json'
```

## 会话与消息

- 同一模块连续工作优先使用 HAPI 的真实 resume 能力；并行任务、失败重试和独立 reviewer 新开隔离会话。
- 宿主暴露 `inspect_peer` / `ping_peer`（或等价工具）时优先使用宿主工具；shell 命令只作为已验证的 fallback。工具名以当前环境实际列表为准。
- 聊天只作为控制通道。Goal、冻结规格、图节点、验收和长期状态仍必须落盘。
- `active/idle`、runner 存活或聊天里的“完成”都不是验收证据；仍需 legal terminal、revision、测试证据和独立 reviewer。

## 监督与清理

- 使用当前版本真实提供的 wait/observe 能力或 HAPI 日志作为观察信号；队列目录和 ledger 仍是动态事实源。
- 只终止本批次明确拥有的会话或进程。runner、hub 和其他用户会话不属于某个 Goal，不能在任务收尾时顺带停止。
- HAPI 诊断输出可能包含本机设置或凭据材料。不要把完整 `hapi doctor`、settings、环境变量或日志直接写入仓库、Goal、ledger、报告或公开 Issue；只摘录脱敏后的必要状态。
- 创建、续接或停止失败时保留失败证据，按 fallback 降级；不得把历史会话或已退出状态描述为仍在运行。
