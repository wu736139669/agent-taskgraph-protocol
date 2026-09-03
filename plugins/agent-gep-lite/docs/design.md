# 任务：给 agent-queue 加 GEP-lite（经验沉淀与复用）

> 背景：agent-queue 已经解决了"拆 → 派 → 验 → 归"，但**归档到 `queue/done/` 的验收经验没有被再利用**。本任务补上最后一块：把每次验收结果沉淀为可复用的"经验资产"，下次分诊/派发时自动召回、注入、复用。

## 目标（一句话）

让 agent-queue "越用越强"：**验收过的经验（含踩坑教训）被结构化存下来，新任务开始时先查、再注入、结束后回写**，并且全程可审计、纯本地、零新依赖。

## 设计要点（GEP-lite，参考 EvoMap GEP 的最小可用版本）

### 1. 经验资产：两类 + 一条台账

- **Gene（策略）**：可复用的"怎么做"模板 —— signals（触发场景标签）、strategy（步骤要点）、preconditions（适用前提）、validation（怎么验）。
- **Capsule（案例）**：一次**已验证**的具体修复实例 —— 引用 Gene、触发信号、环境指纹（git branch / 日期 / 作业系统）、实际 diff 摘要（改哪些文件、几行）、验收结果（通过/失败 + 关键输出）、source_task（哪个任务）。
- **台账 `lessons/ledger.json`**：所有经验的索引（id、signals、类型、score、reuse_count、created_at），供统计与召回排序。

### 2. 三个动作（对应现有流程，只加不改）

| 时机 | 动作 | 落点 |
|---|---|---|
| **派发前（分诊第 0 步之后）** | `scripts/lesson-recall.sh "<任务信号词>"` —— 按信号词命中 + 成功率加权 + 最近优先召回 top-N 条 | 把召回经验写成 task-brief 的「相关经验」段：只给**蒸馏过的警告/策略要点**，**不给长文**（长文经验会稀释提示词，参考论文结论） |
| **验收通过并归档时** | `scripts/lesson-record.sh <brief> <验证输出> [gene]` —— 生成 Capsule（id = sha256 内容寻址，稳定可校验），同步更新 ledger | `lessons/capsules/` + `lessons/genes/` |
| **验收失败时** | 同样 record，但类型标 `failure`，strategy 字段写"**避免建议**"（1-3 条短句，蒸馏而非原文堆砌） | 同上，score 记失败原因 |

### 3. 分诊规则更新（SKILL.md 第 0 步）

- 新增子步骤：**先 recall 再分诊** —— 若召回经验里存在 `score>=高水位` 的同场景 Capsule，分诊结论可直接参考"上回这么干成功了"；若召回里出现 2+ 条同场景 failure，**直接判定"此块不可靠，自己干"**（这是对现有"拆不动就自己做"原则的经验化升级）。

### 4. 明确不做（v0 边界）

- ❌ 不做 embedding / 向量库 / 服务端（纯 `grep + sort + jq(可选)`）
- ❌ 不做跨机器同步（先用 git 随仓库走，未来再说）
- ❌ 不改动现有 分诊/派发/验收 逻辑本身，只插入"查询/注入/回写"三个钩子点
- ❌ 不引入任何新依赖（shell 即可）

## 交付物清单

1. `lessons/README.md` —— 经验资产 Schema 说明 + 目录约定 + 迁移说明
2. `lessons/genes/`、`lessons/capsules/`、`lessons/ledger.json`（含示例条目 2 条，用历史 `queue/done/` 里的真实任务造）
3. `scripts/lesson-recall.sh` —— 召回（信号词命中 + score 加权 + 最近优先，输出 top-N 的"蒸馏摘要"）
4. `scripts/lesson-record.sh` —— 落库（内容寻址 id、更新 ledger、原子写）
5. `SKILL.md` 更新：
   - 第 0 步分诊：新增"先 recall"子步骤与判定规则
   - 第 3 步派发：brief 增加「相关经验」段（注入召回摘要）
   - 第 4 步验收：通过/失败都回写 lesson
   - 新增「第 6 节：经验沉淀与复用（GEP-lite）」说明整体机制
6. （可选，工作量小则并入）`queue/ledger.json` 统计口径：任务轮次、通过率、经验复用次数、按领域分组 —— 与 `lessons/ledger.json` 分离，前者是任务台账，后者是经验台账

## 验收标准（做给自己看）

1. 用 `queue/done/` 里的 2 个历史任务造出 2 条经验（1 成功 + 1 失败），`lesson-record.sh` 可重复执行且 id 稳定（幂等）
2. 拿一条新任务简报跑 `lesson-recall.sh`，能命中上述经验并输出 ≤5 条的蒸馏摘要（每条 ≤3 行）
3. 手动在 SKILL.md 走一遍"存 → 查 → 注入"流程，确认与现有分诊/派发/验收不冲突
4. `ledger.json` 里每条的 `reuse_count` 有初始值，并说明后续在哪自增（v0 可手工/脚本）

## 约束

- **若目录还不是 git 仓库（README 承诺是，需核查）：先 `git init` 并提交现状基线，再开工；完成后提交全部改动**
- 新增文件 ≤ 10 个；保持 SKILL.md "manager 不写代码"的精神：召回结果是 **manager 的决策输入**，不是让 worker 读一堆历史
- 所有脚本可重复执行、失败可重试（与 agent-queue 的原则一致）
- 中文注释 + 中文 README，风格与现有仓库一致
