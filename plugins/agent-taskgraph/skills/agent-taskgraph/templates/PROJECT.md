# 项目档案

> 项目级恒定信息。所有 worker 与专家开工前的"先读"文件。**由 PMO 分析项目后自动填写**（项目接入流程，见 SKILL.md 第 0 节），Owner 只需确认，无需手写。PMO 维护，项目级变更时更新。

## 是什么

（项目一句话定位、当前阶段）

## 技术栈与目录结构

（语言/框架/关键目录的用途——让任何新会话 30 秒理解代码在哪）

## 长期角色策略

（PMO 根据模块边界建立 `.agent-taskgraph/ROLES.md` 与 `roles/<role-id>/ROLE.md`。稳定模块职责使用 persistent；一次性探索或独立 reviewer 使用 task-scoped。角色是长期职责，Goal 是单次授权；每次 worker Role→Session 绑定使用当前任务的 `dispatch.md` 和新 Identity ACK。）

## 硬性规范（不可违反）

- （如：提交格式、日志埋点、tsc 检查、禁止内购/联网……——PR review 会检查的项）

## 需求与执行授权策略

| 配置 | 项目选择 |
|---|---|
| Agent TaskGraph 协议版本 | <从 Skill 根目录 VERSION 读取> |
| Source baseline | <READY: git root + HEAD + branch/upstream + clean/dirty ownership / BLOCKED: 原因> |
| 单任务快速路径 | <允许 / 一律先确认> |
| 复杂任务规格冻结 | 默认必须由用户确认；例外：<无 / 条件> |
| 自主创建可见会话 | <已授权 / 每批次确认 / 未授权> |
| 派发预览授权 | <每批次确认（默认） / 已预授权的精确条件> |
| 编制变更授权 | <每次确认（默认） / 精确预授权条件；新增成本、权限或可见性变化始终重新确认> |
| 默认 Human Gates | <依赖安装 / 迁移 / 删除 / 权限 / 合并 / 发布等> |
| 已启用可选适配器 | <无（公开默认） / hapi / 其他名称> |
| Runtime 证据策略 | spawn 后、首条 bootstrap 前验证 session/cwd/flavor/model/effort/permission；随后核对 Role/Team/Goal/Context Identity ACK；不匹配保持 inbox 并 fallback |
| 上下文模式 | <lean（默认） / balanced / deep>；只影响读取广度，不降低验收标准 |
| Context 必读项上限 | <默认 8；超过必须在 context.md 写 Budget exception，必要时拆 Goal> |

## Execution profile（派发硬门）

> PMO 先探测真实运行能力，再用一张普通语言选择表让 Owner **整体确认一次**。`PENDING`、旧项目里的分散配置或聊天中的口头推测都不能授权 spawn。运行时、机器、flavor、权限、可见性或 fallback 改变时，先把 status 改回 `PENDING`，展示 diff，重新确认后再派发。

| Execution profile | Confirmed value |
|---|---|
| Execution profile status | <PENDING / CONFIRMED> |
| Execution profile confirmed by/at | <Owner / ISO-8601 时间 / 适用批次或项目范围> |
| Execution runtime | <hapi / claude-native / codex-native / 当前宿主真实 runtime ID> |
| Execution control | <宿主原生工具 / 可见终端 / HAPI spawn 工具 / scripts/hapi-hub-session.py> |
| Execution machine | <local: host=... / HAPI: id=...; name=...; host=...；不得只写“本机”> |
| Execution flavor | <claude / codex> |
| Model selection policy | <adaptive-batch（推荐） / fixed / per-worker> |
| Fixed model/effort | <adaptive/per-worker 写 none；fixed 写 model=<id>; effort=<level>> |
| Model catalog evidence | <runtime + machine ID + 探测时间 + 脱敏结果路径/命令摘要> |
| Execution permission | <该 runtime 的准确 mode；default 也必须由 Owner 明确确认> |
| Permission scope | <runtime-only / all-approved-runtimes；后者允许 fallback 映射同等级权限> |
| Execution visibility | <visible / headless> |
| Execution fallback | <none / 准确 runtime + flavor + machine + permission 映射及触发条件> |

`adaptive-batch` 表示 AI 根据 Goal 复杂度从已探测目录推荐模型与 effort，并在每批派发预览中一次展示、一次确认；不是让 AI 静默决定。`per-worker` 才逐个询问。`fixed` 对所有 worker 使用同一明确组合。无论哪种策略，`default`、`auto`、`pending` 或 `待确认` 都不能写进某个 Goal 的 model/effort，也不能生成 `VERIFIED`。

## 共享文件锁

（多 worker 并行时的必查清单：导航注册 / package.json / 全局样式 / 路由表等——谁要改必须 PMO 批准）

## 岗位工作区映射

| 岗位 | 负责模块/目录 | 常用验收命令 |
|---|---|---|
| <岗位名，按项目需要定义> | <模块/目录> | <验收命令> |

## 专家岗配置（可选，按项目需要定义）

（本项目可能需要哪些专家岗、各自产出什么规格。例：产品架构师 → frozen spec；技术架构师 → 技术方案；美术指导 → 美术规范。没有就写"无"）

## 项目 Profile（可选）

（发布平台、游戏引擎、合规、数据库迁移等领域专属收口规则的路径。通用 Skill 不写死项目专属字段；无则写“无”。）

## 本机环境（PMO 项目接入时自动探查记录，每台机器记自己的）

| 能力 | 状态 | 说明 |
|---|---|---|
| Git/worktree | <✅/❌> | 记录 repo root、HEAD、branch/upstream、clean/dirty ownership；B/C/D 无 READY baseline 时禁止派发 |
| 可选 runtime adapter | <未探测 / 名称 + ✅/❌> | 只探测 Owner 选择或允许评估的 adapter；安装成功不等于已启用，也不等于控制面支持 spawn |
| HAPI Hub 控制面 | <未探测 / READY / 不可用> | 使用 `scripts/hapi-hub-session.py probe`；记录脱敏 machine/host 和能力，不记录 token/settings |
| Runtime 配置验证 | <验证器/线程设置/日志证据路径> | 请求参数不算证据；必须能证明配置在 task-bearing bootstrap 前生效 |
| claude CLI 登录 | ✅/❌ | 原生 `claude` / `claude --bg` / `claude agents` / `claude -p` 是否可跑 |
| codex 登录 | ✅/❌ | 原生 `codex` / `codex exec` / `codex resume` 是否可跑 |
| 开新会话可用路径 | <按探查结果填：Claude native / Codex native / 原生 thread / 已启用 adapter / 子 agent> | 供 Reviewer/worker 真实创建时选用；不得列入未启用或未验证的路径 |
| Owner 可见性偏好 | <✅ 全可见 / 仅在编辑器面板 / 无头日志即可> | Owner 是否要求所有会话可见、可接管；记录实际 runtime，不虚构可见会话 |
| macOS 可见终端模式 | <启用 / 禁用 / 每批次确认> | 启用时用 `scripts/open-worker-terminal.sh` 为 worker/reviewer 打开独立 Terminal.app 窗口 |
| codex 线程工具 | ✅/❌（create_thread / wait_threads / send_message_to_thread 等） | 工具真实存在时优先使用；否则用 `codex`/`codex exec` fallback |
| 监控机制登记 | wait 循环：间隔 <默认 600s，可调> / 状态 <运行中 / 已退出+原因>；外部守护：<LaunchAgent/tmux/cron 标识> | **开工必须进入 wait 循环并登记；写不出 = 未开工** |

## 归档约定

- STATUS.md 只含活跃任务（done 即移除，总览板永远小）
- 已完成任务按月移入 `archive/<YYYY-MM>/`（不压缩不索引，可 grep）
- 追溯 / 批次总结翻 archive；开工只读本项目热数据，历史不加载
