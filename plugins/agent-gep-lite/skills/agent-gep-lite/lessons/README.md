# lessons/ —— 经验资产（GEP-lite）

把每次"跑完验收"的结果沉淀为可复用的经验：
**Gene（怎么做）→ Capsule（一次已验证的实例）→ ledger（索引）**，
供 manager 在下次**分诊前召回、派发时注入、验收后回写**。
纯本地、零新依赖、可随 git 仓库跨机器走。

## 一、目录约定

```
lessons/
├── README.md          # 本文件：Schema + 约定 + 迁移说明
├── ledger.json        # 经验索引（id/signals/类型/score/reuse_count/created_at）
├── genes/             # Gene：人工维护的策略模板（怎么做）
└── capsules/          # Capsule：lesson-record.sh 生成的已验证实例（一次真实验收）
```

- 文件格式：扁平 `key: value`（一行一个字段，值里用 `;` 分隔多个子项），**机器可 grep 可 awk 可排序**。
- `ledger.json` 是**派生索引**：权威源是 `genes/` 与 `capsules/` 下的 .md 文件本身。
  任何时候可 `scripts/lesson-record.sh --reindex` 重建（全量扫描、原子写）。

## 二、Schema

### Gene（策略，人工撰写）

| 字段 | 说明 | 示例 |
|---|---|---|
| `id` | `gene-<slug>`，人工可读稳定 id | `gene-accept-run-command` |
| `type` | 固定 `gene` | |
| `signals` | 触发场景标签，`;` 分隔 | `验收; 回归; 拒绝口头完成` |
| `strategy` | 怎么做：步骤要点（短句，蒸馏） | `简报写死验收命令; worker 回传输出原文` |
| `preconditions` | 适用前提 | `任务能定义命令+产出物式验收` |
| `validation` | 怎么验 | `验收命令 exit 0 且产物存在` |
| `score` | 经验分：由关联胶囊成功率推导（0-1），初始 1.0 | `1.0` |
| `reuse_count` | 被召回注入次数（`lesson-recall.sh --bump` 自增） | `0` |
| `created_at` | `YYYY-MM-DDTHH:MM:SS+0800` | |

正文用 `# 标题` + 字段行；recall 会读取标题与上述字段，不依赖字段顺序。

### Capsule（案例，脚本生成）

| 字段 | 说明 |
|---|---|
| `id` | `capsule-<sha256前12位>`，**内容寻址**：对"内容字段"（kind/gene/signals/summary/diff/source/env/verify 的稳定部分）取哈希；同一输入重跑 → 同 id（幂等） |
| `type` | 固定 `capsule` |
| `kind` | `success` / `failure` |
| `gene` | 关联的 Gene id（`none` 表示未关联，recall 时该条只有摘要无策略） |
| `signals` | 触发信号，`;` 分隔 |
| `env` | 环境指纹：`repo=...; branch=...; date=...; os=...`（date 不参与 id 哈希） |
| `diff` | diff 摘要：`files=...; +n/-m` |
| `result` | `通过` / `失败` |
| `strategy` | **success**：怎么做的蒸馏要点；**failure**：**避免建议**（1-3 条短句） |
| `summary` | 一句话结论 |
| `verify` | 关键验收输出（取前 3 行，每行 ≤120 字符） |
| `source_task` | 来源任务（简报路径或任务标识） |
| `score` | 默认 success=1.0 / failure=0.2（recall 排名加权用） |
| `reuse_count` | 被召回注入次数（`--bump` 自增） |
| `created_at` | 记录时间（不参与 id 哈希） |

### ledger.json（索引）

```json
{
  "version": 1,
  "updated_at": "...",
  "note": "派生索引；权威源是 lessons/genes 与 lessons/capsules 下的 .md；可用 lesson-record.sh --reindex 重建",
  "entries": [
    {"id": "capsule-xxxx", "type": "capsule", "kind": "failure", "signals": "...",
     "score": 0.2, "reuse_count": 0, "created_at": "..."}
  ]
}
```

`updated_at` 取所有资产中最新的 `created_at`（不是每次重建时的墙上时间），因此同一批资产反复
`--reindex` 会得到字节级相同的 JSON；`reuse_count` 更新仍会立即反映到 entries。

## 三、三个动作（对应现有流程，只加不改）

| 时机 | 命令 | 说明 |
|---|---|---|
| 分诊前（SKILL.md 第 0.5 步） | `scripts/lesson-recall.sh "<信号词>"` | 命中数×2 + score×5 加权，同分按时间新→旧，输出 top-N（默认 5）蒸馏摘要，每条 ≤3 行 |
| 派发时 | `scripts/lesson-recall.sh "<信号词>" --append <brief.md>` | 把「相关经验」段（标记区间）写进简报；可省略信号词并从标题/目标推导，幂等 |
| 验收通过→归档 | `scripts/lesson-record.sh <brief> <验证输出> [gene-id]` | 生成 Capsule，重建 ledger；Gene 也可用 `--gene <id>` 传入 |
| 验收失败→回退 | 同上加 `--kind failure`，`--strategy "<避免建议 1-3 条>"` | 失败也沉淀（避免建议） |
| 记账 | `scripts/lesson-recall.sh "<词>" --bump` | 确认采用召回经验时执行：top-N 的 `reuse_count` +1，并自动同步重建 ledger |

`--reindex` 仅重建 ledger，不新增 capsule；同一批资产反复执行内容不变。

## 四、迁移说明

- **基线**：`2806e6b baseline: agent-queue as-is before GEP-lite`（含 `tasks/gep-lite-skill-upgrade.md` 任务简报）。
- **示例条目来源**：本仓库 `queue/done/` 在 baseline 提交时**为空**（没有历史归档任务），
  因此 2 条示例经验按任务简报要求"用历史任务造"，**从 README「原则（从实战踩坑里来的）」与 SKILL.md「规则」蒸馏重建**，
  归档文件 `queue/done/hist-early-parallel-dispatch.md`（成功）与 `queue/done/hist-conflict-na-dispatch.md`（失败），
  每个文件头部都标注"历史重建"及出处。待真实任务开始归档后，按同样格式继续追加即可。
- **从旧仓库迁移**（如果别处已有 `queue/done/` 任务）：把每条已归档任务补一条 brief + 验证输出，
  跑一遍 `lesson-record.sh` 即可；Gene 按场景沉淀（建议先建 Gene 再 record，`--gene none` 也能存）。

## 五、纪律（和 SKILL.md 规则一致）

- 召回结果是 **manager 的决策输入**，不是让 worker 读历史长文；注入简报的永远是蒸馏摘要。
- 经验是"可验证的结论"（验收命令 + 关键输出），不是流水账；写不出验收标准的任务不派发也不沉淀。
- Capsule 内容是脚本生成的，**不要手改 id / score**；要校正就改对应字段重跑（新 id 幂等追加）。
