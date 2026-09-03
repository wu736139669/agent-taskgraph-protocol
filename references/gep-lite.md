# GEP-lite：经验层接入手册

仅在代理处理**可复用性高**的工作时读取。本文件说明经验层（[`plugins/agent-gep-lite`](../plugins/agent-gep-lite/)）如何与 Team 模式共存：它不改编排合同，只增加两个插桩点 —— **派发前召回**、**验收后回写**。

## 1. 术语

| 术语 | 定义 |
|---|---|
| 经验资产 | 一次被真实验收验证过的解决过程，落盘为本地 Markdown/JSON，随 git 仓库走 |
| Gene | 可复用策略模板：怎么做（signals / strategy / preconditions / validation） |
| Capsule | 一次已验证实例：对某个 Gene 的具体落地 + 环境指纹 + diff 摘要 + 验收结果 |
| 教训 | `kind: failure` 的 Capsule，`strategy` 字段必须以「避免:」短句开头（蒸馏 ≤3 行，不堆长文） |
| Ledger | `lessons/ledger.json` 派生索引：id / signals / type / score / reuse_count |

与编排层的关系：**编排层回答"这次谁做什么"（Charter/Task Graph）**；**经验层回答"这个坑之前踩过吗/上次这么干成没成"**。两者正交，不开经验层不影响任何流程。

## 2. 何时接入（模式判断）

| 模式 | 经验层 |
|---|---|
| Solo | 不开。手工活没有沉淀价值 |
| Delegation | 可选。只有支线任务与历史经验高度同构（如重复的"改埋点文案+验收"）才开 |
| Team | **建议开**。Team 才是"重复劳动"的高发区；且 Handler 多，教训不沉淀必重犯 |

信号词构造规则（召回质量 = 信号词质量）：`任务目标词 + 技术栈/模块词 + 风险词`（如 `"并行开发; 冲突面; package.json; 验收命令"`）。避免纯概念词（"优化"）——它命中不了具体经验。

## 3. 标准流程（SOP）

### 3.1 接入初始化（首次接手项目时，一次）
- 经验库随仓库 clone 自带；若缺失/迁移，跑 `scripts/lesson-record.sh --reindex` 重建 ledger。
- 首次无经验属正常：`lesson-recall.sh` 会明确提示"无命中，正常分诊"。

### 3.2 派发前召回（接 SKILL.md §4 派发与协作）
```bash
plugins/agent-gep-lite/skills/agent-gep-lite/scripts/lesson-recall.sh \
  --bump --append ".agent-taskgraph/tasks/<id>.md" "并行开发; 冲突面; 验收命令"
```
- `--append` 幂等注入「相关经验」段（标记区间替换）；`--bump` 记账 reuse_count。
- 注入内容**遵守自包含原则**：只放 ≤5 条、每条 ≤3 行的摘要，作为派发消息里的"稳定任务事实"之一；**绝不**把经验库全文塞给 Member。
- **决策升级**：召回见 2+ 条同场景 `failure` → 该块先按 §2/§4 回退（重拆、降级 Solo 或向 User 标记风险后再派发），不要明知会踩坑还硬派。

### 3.3 验收后回写（接 SKILL.md §6 验收、持久化与结束）
- 以**真实验收结论**为准（Member 自验 + Lead 复核；中高风险走独立 Reviewer）：
  - 通过 → `lesson-record.sh <task> <verify输出> --gene <gene>`（`kind: success`）
  - 失败 → 同样沉淀（`kind: failure`，`strategy` 写「避免:」短句，证据留在 diff/日志，不复制长文）
- 幂等：sha256 内容寻址，重复执行不产生重复条目；`--reindex` 随时可重建台账。

### 3.4 批次收口（接 SKILL.md §6 生命周期「complete」前后）
- 审计 ledger：`reuse_count` 高的 Gene 是"已证明有效的纪律"——**把它固化进协议**（见 §4）；
- 新增 `failure` ≥2 的场景，加进对应 Role 的验收检查单。

## 4. 经验 → 协议：自进化闭环（本手册的核心）

经验层的最终价值不是"多存点经验"，而是**让经验定期升级为合同**：

```
Capsule（一次已验证） → Gene（策略模板，reuse_count↑） → 协议（team-protocol.md / SKILL.md 检查单）
```

- 高复用 Gene → 在 `team-protocol.md` 或 SKILL.md 相应章节写明"默认这样做"（从"记得"变成"规则"）；
- 高频失败教训 → 升级为验收检查单/硬性 Human Gate；
- 每批次收口时做一次这样的"基因表达"，经验层才不会退化成只进不出的仓库。

## 5. 反模式（踩过即改）

| 反模式 | 正确做法 |
|---|---|
| 把完整长文经验当派发内容 | 只给蒸馏摘要（≤3 行），原文留在 lessons/ 供按需查阅 |
| 拿经验当验收 | 经验不是证据；验收仍以真实代码/diff/测试为准 |
| 信号词跨项目污染 | 信号词带域前缀（如 `moras/并行开发`），避免跨项目误命中 |
| 旧环境经验套新场景 | 核对 `env` 指纹（repo/branch/os/date）；差异大时只参考策略，不照抄验证 |
| 只存成功不存失败 | 失败的教训才是召回时最该先看到的（低分但高优先级提示） |

## 6. 边界与 FAQ

- **不开会怎样？** 无影响。插件是可选层，主流程零耦合。
- **经验存哪？** 纯本地文件（`lessons/`），git 即同步；换机器 clone 即继承。
- **隐私？** 不上传、无外部服务；经验与代码一起受仓库权限保护。
- **平台无关？** 脚本为 bash+grep+awk，Codex / Claude Code 均可直接调用。
