[English](README.md) | 中文

# agent-queue

多 agent **团队协作编排**：一个秘书/PMO 会话指挥一支由独立 agent 组成的团队干活。模糊需求走"产品架构师 → 技术架构师 → 分岗 worker → reviewer"流水线，台账管理中间状态，可执行验收后归档，失败带日志重开新会话，合并前过 reviewer gate。

> 定位：**团队运营模型 + 流程定义 + 脚本**，不是某个项目的专属方案。任何电脑上任何 agent（Claude 或 Codex）读了 `SKILL.md` 就知道怎么运营这支团队。

## 使用方法

**触发**：在 Claude Code 或 Codex 会话里说"用 agent-queue 派活"（或触发关键词：派活 / 任务队列 / 多agent写代码 / 编排），当前会话的 agent 就变身秘书/PMO，按 SKILL.md 运营这支团队。

**你（老板）只需要做三件事**：
1. **给需求**——一句话也行，模糊也行（模糊会触发 PMO 自动装配产品架构师加工成 PRD）
2. **确认 PROJECT.md**——PMO 第一次接手项目时自动分析生成（技术栈/岗位/规范），你点头即可，不用自己写
3. **终审**——视觉 / 产品 / 发布这类机器审不了的决策，永远留给你

**三个典型场景**：
| 你说 | PMO 会怎么走 |
|---|---|
| "帮我在 book-reader 里加个年份筛选" | 分诊 → 判定单任务 → 直接做或派一个 worker → 验收汇报 |
| "这周 5 个需求一起派了" | 冲突面分析 → 并行/串行分组 → 多个 worker 同时开工 |
| "把 5 个游戏完善到能上架" | 拆解 → 装配专家（产品/技术架构）→ 流水线执行 → 阶段验收 |

## 效果

| 你的诉求 | 这套体系怎么给 |
|---|---|
| 不用盯每个 agent 会话 | PMO 是唯一接口，主动看进展（日志+台账），只在完成/卡住/要决策时找你 |
| 并行开发不互相踩脚 | 一任务一 worktree（独立目录+独立分支），互不干扰 |
| 不被权限弹窗打断 | worker 一律 `--yolo`，安全靠结构（Goal Frozen + worktree 隔离 + reviewer 闸） |
| 不信"说做完了" | 三级验收：worker 自验 → reviewer 审 → 你终审，命令输出才算数 |
| 不无缘无故换会话 | 落盘是常态（台账/决策记录），换会话只在隔离/故障/你要求时发生 |
| 换会话不丢记忆 | durable 文件是事实源（SESSION_CONTINUITY 理念），不靠聊天记忆 |
| 团队越干越懂项目 | 决策记录 + 角色记忆持续沉淀 |
| 不担心 worker 卡死没人管 | PMO 主动检查日志静默 + 等待状态有归属，僵局一眼可见 |

## 团队结构（详见 SKILL.md 第 0 节）

| 角色 | 形态 | 干什么 |
|---|---|---|
| 秘书/PMO | 常驻，唯一对外接口 | 分诊 → 装配团队 → 拆/编 → 派 → 跟 → 验 → 归 → 报（不写代码） |
| 专家岗（按需装配） | 角色由项目定义 | 模糊输入 → 可执行规格（如 PRD/技术方案/美术指导/数值…） |
| Worker（分岗） | 独立会话 ×N | 按 Goal 执行（岗位由项目定义） |
| Reviewer | 验收时启用 | 审 diff + 重跑验收命令 |

专家岗是**机制不是角色**：具体专家由 PMO 按项目定义（可写进 PROJECT.md），SKILL.md 里列的角色只是示例，**勿当固定编制**。小任务只走"PMO + worker"，复杂任务才装配专家（触发判断见 SKILL.md 第 2 节）。

## 目录结构

```
agent-queue/
├── SKILL.md                # ★ 技能定义（团队运营模型完整版）
├── README.md
├── templates/
│   ├── PROJECT.md          # 项目档案（恒定信息，worker 先读）
│   ├── STATUS.md           # 任务总览板（每次状态变化刷新）
│   ├── DECISIONS.md        # 决策记录（追加式团队记忆）
│   ├── goal.md             # ★ Goal 派发模板（Legal terminal 二元终态/证据链/Frozen/Estimate）
│   ├── ledger.md           # 台账记录格式（状态流，只有 PMO 能改）
│   └── report.md           # 完成汇报格式（一页纸）
├── queue/                  # 台账状态机（文件系统即记忆）
│   ├── inbox/              # 待分配
│   ├── active/             # 执行中
│   ├── review/             # 验收中
│   ├── done/               # 验收通过
│   └── failed/             # 失败待定夺
│   └── <每任务一个目录：brief.md + ledger.md + report.md>
└── workers/
    ├── watch-worker.sh     # ★ 持续监视器：tail worker 日志流式输出进展（PMO watch 模式）
    ├── dispatch.sh         # TODO: 轮询 inbox → 派发 → 归档
    └── run-worker.sh       # TODO: spawn 一个 worker（hapi / claude -p / codex exec）
```

## 工作流（详见 SKILL.md）

1. **分诊**（30 秒）：形态（单任务/大目标/多需求/混合）+ 两个敏感度（模糊度→产品架构师、架构敏感度→技术架构师）
2. **装配团队**：按需启用专家岗，产出物不合格退回重写
3. **拆/编**：拆解四维度（模块/流水线/角色/风险）或编排（冲突面分析 + 分组排期）
4. **分配派发**：相关性 → 职责匹配 → 负载均衡；一任务一 Goal 一 worktree（Goal = 二元终态判定 + 证据链 + Frozen + Estimate，格式 `templates/goal.md`）；worker 默认独立可见会话（HAPI）且 `--yolo` 权限，相关任务复用会话（`hapi resume`），失败重试才新开；工具/模型/思考等级老板在场先询问，不在则由 PMO 按任务复杂度定
5. **跟进**：**PMO 原生监控**——agent 用自身能力（Codex automation / wait 循环、Claude 后台任务）周期性读 worker 日志尾部对比进展（HAPI `~/.hapi/logs/`、Codex rollout jsonl）；静默即卡死信号；不造外部进程（实时性要求高时才可选挂 `workers/watch-worker.sh` 事件流）；老板要进度直接给摘要，零打扰
6. **验收**：三级闸——worker 自验（命令输出）→ reviewer 独立审 → 老板终审（视觉/产品/发布）
7. **重试**：带错误日志重开新会话，最多 3 次
8. **合并闸**：按依赖顺序合并，每条合完跑回归，合并前 reviewer 审 diff

## 汇报（三级，不刷屏）

- 完成汇报（每任务验收后，`templates/report.md`）→ 异常汇报（失败/要决策，立即报带方案）→ 批次总结（一批收尾，表格）

## 原则（从实战踩坑里来的）

- 验收 = 可运行的命令 + 可检查的产物，"agent 说做完了"不算数；**数据级一致优先于字节级**
- 小任务不编排（编排本身有成本）；PMO 永远不写代码
- worker 不临场改方案，发现问题上报 PMO；专家产出物不合格退回重写
- 一任务一 worktree；台账在文件系统，只有 PMO 能改状态
- 失败 = 带错误日志重开新会话，不是 PMO 现场修
- **PMO 主动看进展是第一道防线**：PMO 定期主动检查 worker 日志 + 台账（不依赖通知），发现完成/静默/等待即主动推进；worker 完成必报（Goal 报告协议，ping PMO，不通知 = 未完成）只是事件加速器；等待状态写明归属；老板看 STATUS 是最后兜底——三层防线防"worker 等 PMO、PMO 发呆"的僵局
- 冲突由 PMO 派发前分析解决，不在 worker 间现场解决
- 自动 merge 前保留 reviewer gate

## 安装（跨电脑/给别人用）

**clone + 一条命令**：

```bash
git clone <仓库地址> agent-queue && cd agent-queue && ./install.sh
```

`install.sh` 自动建双端软链（Claude Code `~/.claude/skills/agent-queue` + Codex `~/.codex/skills/agent-queue`），指向同一源目录——改一处，双端生效。

> 注意：分发的是**运营模型**（模板 + 规则 + 空队列），实例数据（任务归档）留在各项目自己的 `.agent-queue/` 里，不随 skill 分发。

## 待办

- [ ] `workers/dispatch.sh` + `run-worker.sh` 执行脚本（轮询 inbox → 建 worktree → spawn worker → 验收 → 归档）
- [ ] git init + 推 GitHub（跨电脑分发前提，用户决定稍后推）
- [ ] 用独立 HAPI 会话派一轮真实任务（下一轮试验）
- [ ] ledger.json 化：记录轮次、通过率、token 成本，评估 PMO 的拆分质量
