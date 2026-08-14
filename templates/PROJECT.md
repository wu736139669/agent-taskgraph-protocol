# 项目档案

> PMO 首次接入时填写。只保存稳定事实；任务细节放在 `tasks/`。

## 项目

- 一句话定位：
- 当前阶段：
- 仓库根：

## 代码与目录

| 范围 | 用途 |
|---|---|

## 构建与验收

| 用途 | 命令 |
|---|---|
| 快速检查 | |
| 单元/集成测试 | |
| 完整验收 | |

## 硬约束

- <AGENTS.md / CLAUDE.md / 项目规范中的关键规则>

## 团队默认值

| 配置 | 值 |
|---|---|
| 协议版本 | <从 Skill VERSION 读取> |
| 原生宿主 | <codex / claude-code> |
| 默认模式 | simple：小任务当前会话直接做；复杂任务 PMO + 原生多会话 |
| 团队运行形态 | <Claude: Agent Teams / Agent View background / subagent；Codex: Agent thread> |
| 默认可见方式 | <同一终端 Agent panel / background list；可见分屏需 Owner 明确要求> |
| 默认并发 | 2-3 个工作 Agent |
| 模型/推理 | 继承宿主；按任务复杂度推荐 |
| 权限 | <effective 模式；Claude worker 推荐 acceptEdits/auto，Codex worker 推荐 workspace-write+on-request> |
| Dangerous mode | <disabled / Owner 明确授权的范围；检测到父会话 Yolo/Full Access 时必须确认> |
| 工作区 | 读任务可共享；并行写任务用已验证 worktree 或不重叠路径 |
| HAPI | disabled；只有 Owner 明确要求跨机器控制时启用 |

## 共享写入与 Human Gates

- 共享/高冲突文件：
- 需要 Owner 决策：迁移 / 删除 / 权限扩大 / 合并 / 发布 / 其他
