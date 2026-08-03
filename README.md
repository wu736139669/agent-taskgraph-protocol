# agent-queue

多 agent **团队协作编排**：一个秘书/PMO 会话指挥一支由独立 agent 组成的团队干活。模糊需求走"产品架构师 → 技术架构师 → 分岗 worker → reviewer"流水线，台账管理中间状态，可执行验收后归档，失败带日志重开新会话，合并前过 reviewer gate。

> 定位：**团队运营模型 + 流程定义 + 脚本**，不是某个项目的专属方案。任何电脑上任何 agent（Claude 或 Codex）读了 `SKILL.md` 就知道怎么运营这支团队。

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
5. **跟进**：**PMO 持续 watch 模式**——派发时登记日志路径，tail -f 所有活跃 worker 日志实时监听进展（HAPI `~/.hapi/logs/`、Codex rollout jsonl）；20 分钟静默告警判卡死；监视器断线回退台账检查；老板要进度直接给摘要，零打扰
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
