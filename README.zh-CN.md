![Agent TaskGraph](promo/agent-taskgraph-hero.svg)

[English](README.md) | [中文](README.zh-CN.md)

# Agent TaskGraph

**在 Codex 和 Claude Code 中建立有目标、角色、任务关系、协作协议和生命周期的原生 Agent Team。**

版本：[`v0.8.0-beta.19`](VERSION) | 许可证：[Apache-2.0](LICENSE)

Agent TaskGraph 让当前会话成为 Lead，根据工作选择 Solo、Delegation 或 Team，使用宿主原生 Agents 完成组队、派发、协作、审查和集成。它不运行外部调度服务。

## 60 秒开始

### 1. 安装

```bash
git clone https://github.com/wu736139669/agent-taskgraph-protocol.git
cd agent-taskgraph-protocol
./install.sh
./install.sh --status
```

同一个 Skill 会链接到：

- `~/.codex/skills/agent-taskgraph`
- `~/.claude/skills/agent-taskgraph`

### 2. 组一个开发团队

```text
使用 agent-taskgraph 组一个开发团队完成这个需求。
先理解项目，建立共同目标、角色、任务依赖、写入边界和完成条件，
然后用当前宿主的原生 Agents 执行、交接、审查和集成。
```

Lead 会输出类似：

```text
模式与拓扑：Team / hub-and-spoke
团队目标：...
成员：Lead/Integrator、Backend Builder、Frontend Builder、Reviewer
任务关系：T1 → T2/T3 → T4 Review → T5 Integration
完成条件：集成测试、构建和风险检查通过
```

用户调用 Skill 已经授权合理的内部组队；只有产品决策、权限扩大或外部副作用需要额外确认。

## 三种模式

| 模式 | 适用情况 | 运行方式 |
|---|---|---|
| **Solo** | 小修复、单模块、顺序工作 | 当前会话直接完成 |
| **Delegation** | 多个独立支线只需分别交给 Lead | Lead + 原生 Members |
| **Team** | 有共同目标、角色协作、任务依赖或跨模块集成 | Team Charter + Task Graph + 生命周期 |

### 不要为了形式组 Team

以下情况使用 Solo 或 Delegation：

- 工作无法拆出两个独立、可验收的产出
- 多个 Members 会同时修改同一批文件
- 协调成本高于实际工作
- 需求还不清楚，无法定义 Task Acceptance

## Team 的五个组成部分

1. **Outcome**：团队共同结果、Non-goals 和 Definition of done。
2. **Roles**：Lead、Integrator，以及当前 Tasks 需要的 Builders、Specialists 或 Reviewers。
3. **Task Graph**：Owner、Needs、Produces、Consumer、Writes、Acceptance。
4. **Collaboration**：`READY / BLOCKED / HANDOFF / REVIEW`。
5. **Lifecycle**：

```text
forming → briefing → executing → reviewing → integrating → complete/stopped
```

默认团队包含 Lead 在内共 2-4 个 active Members。没有真实 Task 就不创建对应 Member。

## 完整开发团队示例

[`references/development-team-example.md`](references/development-team-example.md) 展示一个异步报告导出功能如何运行：

```text
T1 API contract
 ├─ T2 Backend implementation
 └─ T3 Frontend implementation
       ↓
T4 Independent review
       ↓
T5 Integration and team acceptance
```

示例包含 Team Charter、Roster、Task Graph、派发合同、阻塞、Handoff、Review 和 Complete 报告。

## 原生运行时

### Codex

Codex Team 默认是 `hub-and-spoke`：当前主线程是 Lead，原生 subagents/agent threads 是 Members。Lead 通过 Task 合同、代码产物和 Handoffs 管理依赖，不假设 Members 能直接互相通信。

### Claude Code

- **Subagents**：用于 Lead 中心化 Team。
- **Agent Teams**：只有 Members 必须互相通信、认领共享任务或协作决策时使用。

逻辑 Team 不等同于 Claude Agent Teams。Agent Teams 不可用时，仍可用 subagents 建立中心化 Team。

## 写入、Git 和权限

- 并行写 Tasks 使用独立 worktree 或不重叠路径。
- 一个文件、生成物或迁移状态同一时刻只有一个 Owner。
- Members 默认不 commit、merge、rebase、打 Tag、推送或发布。
- Integrator 负责最终 diff、冲突处理和团队级验证。
- 多 Agent 不扩大当前会话的权限或外部操作授权。

## 可选的持久化状态

短 Team 直接使用宿主原生任务和消息。跨会话、依赖复杂或需要审计时运行：

```bash
./init.sh /path/to/project
```

```text
.agent-taskgraph/
├── PROJECT.md       # 稳定项目事实
├── TEAM.md          # Team Charter 和 Roster
├── PLAN.md          # Task Graph 和集成路径
├── STATUS.md        # 生命周期、进展和阻塞
├── DECISIONS.md     # 改变团队合同的决定
├── tasks/<id>.md    # 单个 Task 合同和 Handoff
└── archive/         # 已结束批次
```

模板使用稳定的英文字段名，字段值可以使用项目主要语言。持久化文件恢复团队事实，不是假定仍然在线的 Agent。

## 可选的 GEP-lite 经验层

`plugins/agent-gep-lite` 为现有 Team 流程增加一条本地、可选的经验闭环。它**不替换** Solo、Delegation、Team、Task 验收、Review 或集成，只增加两个小钩子：

- **派发前**：召回匹配的 Gene/Capsule，只把蒸馏后的警告或策略要点注入简报（最多 5 条，每条最多 3 行）。
- **验收后**：把成功和失败都记录下来，保留验收证据与失败的避免建议，让下一次相似任务先看到上下文，而不是重复踩同一个坑。

它对原流程的实际帮助是形成反馈闭环：`queue/` 继续记录当前任务，`lessons/` 额外保存可复用的“怎么做”和“不要怎么做”。全部内容是本地 Markdown/JSON，无外部服务、无新增依赖，并随仓库 Git 一起迁移。

对一个 Task contract 的快速用法：

```bash
L=plugins/agent-gep-lite/skills/agent-gep-lite/scripts
"$L/lesson-recall.sh" --append .agent-taskgraph/tasks/<id>.md "并行开发; 冲突面; 验收命令"
"$L/lesson-record.sh" .agent-taskgraph/tasks/<id>.md verify.out --kind success --gene gene-accept-run-command
```

详见 [`plugins/agent-gep-lite/README.md`](plugins/agent-gep-lite/README.md) 的插件说明，以及 [`references/gep-lite.md`](references/gep-lite.md) 的 SOP、决策升级规则和“经验→协议”闭环。

## 文档导航

| 文档 | 何时阅读 |
|---|---|
| [`SKILL.md`](SKILL.md) | Skill 入口、模式选择和不可违反的约束 |
| [`references/team-protocol.md`](references/team-protocol.md) | 实际进入 Team 模式时 |
| [`references/native-runtimes.md`](references/native-runtimes.md) | 准备创建或控制原生 Member 时 |
| [`references/development-team-example.md`](references/development-team-example.md) | 需要完整端到端示例时 |
| [`plugins/agent-gep-lite/README.md`](plugins/agent-gep-lite/README.md) | 使用可选经验层时 |
| [`references/gep-lite.md`](references/gep-lite.md) | 需要 GEP-lite SOP、边界和接入指导时 |
| [`templates/`](templates/) | 需要跨会话 Team 状态时 |

## 验证和更新

```bash
./tests/smoke.sh
python3 ./scripts/check-docs.py
./install.sh --check-update
```
