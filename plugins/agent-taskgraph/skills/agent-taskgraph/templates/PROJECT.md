# 项目档案

> 项目级恒定信息。所有 worker 与专家开工前的"先读"文件。**由 PMO 分析项目后自动填写**（项目接入流程，见 SKILL.md 第 0 节），Owner 只需确认，无需手写。PMO 维护，项目级变更时更新。

## 是什么

（项目一句话定位、当前阶段）

## 技术栈与目录结构

（语言/框架/关键目录的用途——让任何新会话 30 秒理解代码在哪）

## 长期角色策略

（PMO 根据模块边界建立 `.agent-taskgraph/ROLES.md` 与 `roles/<role-id>/ROLE.md`。稳定模块职责使用 persistent；一次性探索或独立 reviewer 使用 task-scoped。角色是长期职责，Goal 是单次授权。）

## 硬性规范（不可违反）

- （如：提交格式、日志埋点、tsc 检查、禁止内购/联网……——PR review 会检查的项）

## 需求与执行授权策略

| 配置 | 项目选择 |
|---|---|
| Agent TaskGraph 协议版本 | <从 Skill 根目录 VERSION 读取> |
| Source baseline | <READY: git root + HEAD + branch/upstream + clean/dirty ownership / BLOCKED: 原因> |
| 单任务快速路径 | <允许 / 一律先确认> |
| 复杂任务规格冻结 | 默认必须由用户确认；例外：<无 / 条件> |
| Worker 权限 | <平台标准权限 / 当前项目明确授权 yolo> |
| Worker 默认模型/effort | <明确模型 + effort；不得只写“默认”或“待确认”> |
| 自主创建可见会话 | <已授权 / 每批次确认 / 未授权> |
| Worker 运行方式（Owner 语言） | <原生可见终端 / 宿主可见线程 / 已启用 adapter / 无头后台> |
| 模型选择策略 | <AI 推荐并在派发预览确认（推荐） / 每个 worker 确认 / 固定模型+effort> |
| 派发预览授权 | <每批次确认（默认） / 已预授权的精确条件> |
| 默认 Human Gates | <依赖安装 / 迁移 / 删除 / 权限 / 合并 / 发布等> |
| Runtime preference | <auto / claude-native / codex-native / adapter:<name>> |
| 原生运行时优先 | <是（公开默认） / 否> |
| 已启用可选适配器 | <无（公开默认） / hapi / 其他名称> |
| Runtime fallback 顺序 | <例如：claude-native → codex-native；不允许则写“无”> |
| Runtime 证据策略 | spawn 后、首条 Goal 前验证 session/cwd/flavor/model/effort/permission；不匹配保持 inbox 并 fallback |

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
| Runtime 配置验证 | <验证器/线程设置/日志证据路径> | 请求参数不算证据；必须能证明配置在第一条 Goal 前生效 |
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
