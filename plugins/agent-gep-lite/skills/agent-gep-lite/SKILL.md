---
name: agent-gep-lite
description: 经验沉淀与复用（GEP-lite）—— 派发前召回已验证的 Gene/Capsule 经验并注入任务简报；验收后把结果（含失败教训）沉淀为可复用资产。Triggers: 经验, 基因, 胶囊, 复用, recall, lesson, 自进化, 教训, 避免
---

# Agent GEP-lite 使用指南 —— 经验层接入

你是 taskgraph 编排的**经验扩展**，不改变 PMO/Worker/Reviewer 的职责：只在两个点插一条线 —— **派发前召回**、**验收后回写**。所有资产是纯本地文件（`lessons/`），经验库随仓库走（git 即同步）。

## 角色定位（与 taskgraph 的边界）

- **PMO 的输入增强**：召回结果只是 PMO 分诊/派发的**决策输入**（≤5 条、每条 ≤3 行），不是让 Worker 读一堆历史。
- **Reviewer 的验收副产品**：验收通过/失败都值得沉淀 —— 失败案例必须蒸馏成「避免:」短句，不堆长文（长文会稀释提示词）。

## 三个动作

### 1. 派发前召回（接第 7 节任务分配与派发）

```bash
L=plugins/agent-gep-lite/skills/agent-gep-lite/scripts/lesson-recall.sh
"$L" --bump --append queue/inbox/<task>.md "并行开发; 冲突面; 验收命令"
```

- `--append` 把「相关经验」段幂等写入简报（标记区间替换，重复跑不叠加）；
- 召回时见 2+ 条同场景 `failure` → 直接判"此块不可靠"，按第 7 节回退走单 agent 或澄清；
- 命中高 score 同场景 Capsule → 简报里注明"参考经验：…"，Worker 可先读该胶囊原文再动手。

### 2. 验收后回写（接第 9 节验收（三级闸））

```bash
"$L" --kind success --gene gene-accept-run-command  # 也可用 --help 看全参
```

以**闸结果为准**：通过 → `kind: success`；失败 → `kind: failure`（`strategy` 字段写「避免:」短句）。Reviewer 可以在验收汇报里附一句"已沉淀 capsule-xxxx"。

### 3. 台账维护

- `lessons/ledger.json` 是派生索引：`lesson-record.sh --reindex` 重建；
- `lesson-record.sh` 幂等（sha256 内容寻址），重复执行不产生重复条目；
- 经验库随 git 仓库走；换机器 = clone 即可继承全部经验。

## 经验资产字段（详见 `lessons/README.md`）

| 字段 | 含义 |
|---|---|
| `signals` | 触发场景标签（分号分隔），召回靠它匹配 |
| `strategy` | 策略要点；失败案例以「避免:」开头 |
| `verify` | 验收命令与关键输出（沉淀的依据） |
| `env` | 环境指纹（repo/branch/os/date），判断经验是否适用 |
| `score` | 0-1；失败案例低分，召回时权重自动降低 |

## 纪律

- 不把长文回执写进经验（教训 = 蒸馏 ≤3 行）；原文证据留在 `queue/done/` 与 git diff 里；
- 经验的**质量**取决于验收的严格程度 —— "说做完了"不算数（与 taskgraph 第 9 节一致）；
- 本插件不改 taskgraph 主流程：不开它，编排照常；开了它，只加"查"和"写"。
