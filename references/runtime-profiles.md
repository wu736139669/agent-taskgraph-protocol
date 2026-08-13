# Runtime Execution Profiles

在首次项目接入、Owner 改变运行方式，或 runtime/machine/model/permission/visibility/fallback 任一项变化时读取本文件。

## 目标

把分散在聊天、PROJECT、派发表和会话设置里的运行参数收敛成一个可审计合同：

1. `PROJECT.md` 的 Execution profile 定义 Owner 已批准的边界。
2. 每批派发预览为具体 Goal 选择明确 model/effort。
3. runtime evidence 证明会话实际配置与前两者一致。
4. monitoring profile 把 wait、observe 和 targets 绑定到同一个 runtime/control。

这些合同不一致时停止派发，不能用逐次点击权限、事后改设置、复制旧证据或切换不兼容 wait 工具继续。

## 一次确认协议

PMO 先只读探测，再用一张短表让 Owner 一次确认以下内容：

| Owner 看到的选择 | 内部记录 |
|---|---|
| 在哪里运行、是否可见（独立确认，不能从其他行推断） | Runtime choice confirmed by/at + runtime/control/machine/flavor/visibility |
| 模型由 AI 按任务推荐、固定，还是逐个选择 | model selection policy |
| 标准询问、自动接受编辑，还是 yolo | exact permission + scope |
| 首选路径失败怎么办 | exact fallback |
| 怎样等待、检查哪些会话 | monitoring wait primitive + observe primitive + target evidence |

不要逐项连续追问，也不要让普通用户输入 adapter ID、machine UUID 或 CLI flags。AI 只展示探测后真实存在的选项，并把普通语言选择映射为准确字段。runtime 必须由 Owner 明确选择；模型、effort、权限或 yolo 的确认不能代替 runtime 选择。PROJECT 的 Preferred runtime 只改变推荐顺序。推荐默认是 `adaptive-batch + 每批一次确认`；只有 Owner 明确选择 `per-worker` 才逐个确认模型。

标准权限会在工具、命令或写入时继续弹窗，确认页必须直说这个结果。Owner 若明确希望批次内不再逐次点击，可选择当前项目 yolo；同时保留依赖安装、迁移、删除、权限扩大、合并和发布等 Human Gates。

## 能力与目录探测

先确定 runtime 和准确执行机器，再读该机器的能力：

- HAPI：先用 `scripts/hapi-hub-session.py machines` 获取在线候选；Owner 选择后执行 `probe --machine-id <id>`，随后执行 `catalog --machine-id <id> --flavor <claude|codex>`。saved machine ID 过期不能成为静默换机器的理由。
- Codex/HAPI：使用 runner 动态返回的 model ID 与每个模型的 `supportedReasoningEfforts`；没有 effort 列表就不能声称某个 effort 已被证明可用。
- Claude/HAPI：使用 HAPI Claude presets 与 `/api/claude/custom-models` 的并集；effort 只使用 helper 报告的值。
- 原生 runtime：优先使用宿主/CLI 的真实模型目录能力。若无法发现目录，只能复用已观察到的明确模型组合，或让 Owner 明确指定并在 spawn 后验证；不得编造可用列表。

模型 ID 必须原样传递。方括号属于 ID，例如 `deepseek-v4-flash[1m]`；缺少右括号、shell 展开后的值或 UI 标签都不是同一个模型。

## 监控配置

PMO 宿主与 worker runtime 是两件事。监控配置以 worker/control 为准：

| runtime/control | Wait | Observe |
|---|---|---|
| native `spawn_agent` | `wait_agent` | agent tree + ledger/log |
| native thread | `wait_threads` | list/read thread + ledger |
| HAPI | HAPI event；周期兜底用 timer-cell + `functions.wait(real cell_id)` | `inspect_peer`/session metadata/log + ledger |
| CLI/Terminal | owned timer/process wait | PID/log + ledger |

`wait_agent` 不认识独立 HAPI peer，`wait_threads` 不认识 HAPI session ID。`functions.wait` 不能独立创建 timer，只能恢复刚由本会话启动并返回真实 `cell_id` 的 timer/observe cell。误路由时保留同一 runtime，修复 monitoring profile；不能为了得到某种 UI 卡片静默换工具。

## 模型策略

- `adaptive-batch`（推荐）：AI 按 Goal 风险和复杂度推荐，Owner 在整批预览中确认一次。机械任务可用较轻模型/低 effort，架构、复杂调试和 reviewer 使用更强模型/高 effort。
- `fixed`：PROJECT 记录一个明确 `model=<id>; effort=<level>`；每个 Goal 必须一致。
- `per-worker`：Owner 逐个选择。仅在成本控制或人工调度确有需要时使用。

所有策略都要求具体 Goal 写明确 model/effort。`default`、`auto`、`pending`、`待确认` 不是明确值。目录在预览后变化时，展示差异并重新确认受影响行；禁止静默回退。

## 权限映射

PROJECT 记录 runtime 的准确 mode，不只写“标准”或“yolo”：

- Claude 常见值：`default`、`acceptEdits`、`plan`、`bypassPermissions`。
- Codex 常见值：`default`、`read-only`、`safe-yolo`、`yolo`。
- HAPI helper 接受 `yolo` 作为用户友好别名，并按 flavor 映射为实际 mode；evidence 必须记录实际值。

`Permission scope=runtime-only` 时，切换 fallback 前重新确认权限。`all-approved-runtimes` 只允许映射同等级已批准策略，不允许扩大权限或取消 Human Gates。

## 派发与变更

派发前顺序固定：

1. Execution profile 为 `CONFIRMED`。
2. `Runtime choice confirmed by/at` 明确记录 Owner 选择与适用范围。
3. 生成一张包含所有 worker/reviewer 明确 model/effort/permission 的批次预览。
4. Owner 一次批准该批；预授权批次仍展示表。
5. 结构化生成 inbox 任务并运行 `validate-state.py --phase pre-dispatch`。
6. spawn 或 reuse 前重新读取目录并校验参数。
7. 实际会话配置匹配后写当前 Goal 专属 evidence，才发送 Goal。

runtime、control、machine、flavor、permission、scope、visibility 或 fallback 变化时，将 profile 改回 `PENDING`，展示旧值/新值/影响，重新确认。模型目录内容变化只重审受影响的派发行；model selection policy 变化则重审整个 profile。
