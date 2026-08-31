# Development Team Example

本示例展示一个小型跨模块功能如何从组队运行到完成。它说明协议形态，不要求每个项目使用相同角色或 Task 数量。

## 场景

为一个已有 Web 应用增加“异步导出报告”功能：后端创建导出任务，前端展示进度和下载入口，并补齐集成测试。

## 1. Forming：建立 Charter

```text
Team ID: export-report
Outcome: 用户可以创建报告导出任务、查看进度并下载完成文件。
Non-goals: 本批次不增加导出模板编辑器，不改权限模型。
Topology: hub-and-spoke
Native runtime: Codex subagents / Claude subagents
Lead: 当前主会话
Integrator: Lead
Definition of done:
  - API、UI 和集成测试通过
  - 并行修改无文件所有权冲突
  - Reviewer 没有未解决的阻断问题
Human Gates: 数据迁移和生产发布不在本批次执行
```

## 2. Forming：选择 Roles

| Member | Role | Responsibility | Writes |
|---|---|---|---|
| Lead | Lead / Integrator | API 合同、任务关系、集成和最终验收 | 集成时按需 |
| Member A | Backend Builder | 导出任务 API 和后台状态流转 | `server/export/`, `server/routes/export.*` |
| Member B | Frontend Builder | 导出入口、进度和下载 UI | `web/features/export/` |
| Member C | Reviewer | 只读审查 API/UI 契约、错误处理和测试 | none |

Lead 包含在默认 2-4 个 active Members 中。Reviewer 因为功能跨前后端且涉及异步状态而创建；普通单模块改动可以省略。

## 3. Briefing：建立 Task Graph

| Task | Owner | Status | Needs | Produces / Consumer | Writes | Acceptance |
|---|---|---|---|---|---|---|
| `T1-contract` | Lead | active | none | API contract / T2、T3 | docs or no code | 状态、错误和响应字段明确 |
| `T2-backend` | Member A | pending | T1 | API implementation / T4、Integrator | backend paths | 后端定向测试通过 |
| `T3-frontend` | Member B | pending | T1 | UI implementation / T4、Integrator | frontend paths | UI 测试和类型检查通过 |
| `T4-review` | Member C | pending | T2, T3 | Review / T2、T3、Integrator | none | 返回 PASS 或具体修正证据 |
| `T5-integrate` | Lead | pending | T2, T3, T4 | Integrated feature / user | integration scope | 团队级测试和构建通过 |

`T2` 和 `T3` 在 `T1` Handoff 后并行。`T4` 等两个实现 Handoffs；`T5` 消费全部结果。

## 4. Briefing：派发一个 Task

给 Backend Builder 的任务可以是：

```text
Role：Backend Builder
Task：T2-backend
Goal：实现异步报告导出 API 和状态流转。
Read：
  - server/export/
  - server/routes/
  - tests/export/
  - T1-contract Handoff
Writes：
  - server/export/
  - server/routes/export.*
  - tests/export/
Does not own：前端目录、数据库迁移、生产配置。
Needs：T1-contract
Produces for：T4-review、T5-integrate
Acceptance：运行后端导出定向测试；覆盖成功、失败和重复查询状态。
完成时发送 HANDOFF；阻塞时发送 BLOCKED。
```

## 5. Executing：协作事件

### READY

```text
READY T2-backend
已读取 API contract，写入范围无冲突，定向测试命令可运行。
```

### BLOCKED

如果合同缺少失败状态：

```text
BLOCKED T3-frontend
阻塞：T1 没有定义导出失败时的错误字段。
已尝试：检查现有任务状态接口，没有可复用字段。
需要：Lead 决定统一使用 error.code + error.message，或提供其他合同。
影响：无法完成失败态 UI 和测试。
```

Lead 更新合同并把增量决定发送给受影响 Members，不重新粘贴全部历史。

### HANDOFF

```text
HANDOFF T2-backend
Result：API、后台任务状态和错误映射已完成，达到 Acceptance。
Changed：server/export/*, server/routes/export.*, tests/export/*
Verification：export route tests passed; export worker tests passed
Risks：大文件存储清理策略不属于本批次。
Downstream：前端轮询终态为 completed/failed；Reviewer 重点检查重复请求处理。
```

## 6. Reviewing

Reviewer 读取 Team Outcome、`T2`/`T3` Handoffs、实际 diff 和测试结果：

```text
REVIEW T4-review: CHANGES_REQUIRED
Evidence：前端在 failed 状态仍显示下载按钮，与 T1 contract 冲突。
Correction boundary：只修改 web/features/export/DownloadAction.* 并增加失败态测试。
```

Lead 把修正返回 Member B。Member B 修复并更新原 Handoff；Reviewer 复核后返回 `PASS`。

## 7. Integrating

Lead/Integrator：

1. 检查实际 diff 与各 Task Writes 是否一致。
2. 确认 `T2`、`T3` 的 Handoffs 已被 Review 和 Integration 消费。
3. 运行团队级测试、类型检查和构建。
4. 检查 Non-goals、Human Gates 和残余风险。
5. 结束不再需要的 Members。

## 8. Complete

最终报告只需说明：

```text
Outcome：异步报告导出已完成。
Integrated：后端 API、前端进度/下载 UI、集成测试。
Verification：后端测试、前端测试、类型检查和构建均通过。
Risks：大文件清理策略未包含在本批次，已记录为后续项。
Team：所有 Members 已完成或结束；Team phase = complete。
```

这个例子中的关键不是 Agent 数量，而是每个产出有 Owner、依赖有 Handoff、写入有边界、审查有证据、Team 有明确结束条件。
