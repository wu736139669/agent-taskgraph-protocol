# Agent GEP-lite Plugin Package

GEP-lite（经验沉淀与复用）是 agent-taskgraph 的可选经验层插件。它把"派发 → 验收 → 归档"过程中已被验证的经验（Gene/Capsule）沉淀为本地资产，下一次任务开始前先召回、再注入、结束后回写 —— 让 Agent 团队"越用越强"，且全程纯本地、零新依赖、可审计。

> 设计出处：`docs/design.md`（原始任务简报，含 schema、验收标准与 v0 边界）。
> 完整接入手册：`references/gep-lite.md`（仓库根，含 SOP、经验→协议的自进化闭环、反模式清单）。

## 与 agent-taskgraph 的关系

| 层 | 谁负责 | 说明 |
|---|---|---|
| 编排层 | agent-taskgraph | 分诊 / 拆编 / 派发 / 三级验收 / 合并闸 |
| **经验层** | **agent-gep-lite** | 派发前查"有没有人干过"，验收后留"这次怎么干成（或怎么栽的）" |

两者正交：不开 GEP-lite 不影响 taskgraph 主流程；开了也只是在"派发"与"验收回写"两个点各插一下。

## 它对原流程有什么帮助

| 原来的情况 | 加入 GEP-lite 后 |
|---|---|
| 验收经验停留在 `queue/done/`，下次只能靠 Lead 记忆 | 经验落为可检索的 Gene/Capsule，并按信号词召回 |
| 派发时容易重复过去的冲突或漏验收 | 简报自动注入蒸馏后的策略要点和失败警告，不塞历史长文 |
| 失败任务只留下错误日志 | 失败也记录为 `kind: failure`，沉淀 1–3 条「避免」建议 |
| 经验是否真的被使用无法统计 | `lessons/ledger.json` 记录 `score` 与 `reuse_count` |

它不改变 taskgraph 的模式选择、Task contract、Review 或 Integration 规则；关闭插件时原流程照常运行。

## 包内容

| 路径 | 用途 |
|---|---|
| `skills/agent-gep-lite/SKILL.md` | 集成指南（如何接 taskgraph 主流程） |
| `skills/agent-gep-lite/scripts/lesson-recall.sh` | 召回：信号词命中×2 + score×5 + 时间新→旧，输出 ≤3 行的蒸馏摘要（幂等注入简报） |
| `skills/agent-gep-lite/scripts/lesson-record.sh` | 落库：验收通过/失败都沉淀，sha256 内容寻址幂等，`--reindex` 重建台账 |
| `skills/agent-gep-lite/lessons/` | 经验资产：`genes/`（怎么做）+ `capsules/`（已验证实例，含失败教训）+ `ledger.json`（索引） |
| `docs/design.md` | 设计文档（schema / 验收标准 / 明确不做清单） |

## 快速开始

```bash
# 仓库根（或插件安装目录）：
./plugins/agent-gep-lite/skills/agent-gep-lite/scripts/lesson-recall.sh "并行开发; 冲突面"
./plugins/agent-gep-lite/skills/agent-gep-lite/scripts/lesson-record.sh <task-brief.md> <验证输出> [--gene 名称]
```

脚本自带路径解析（以自身位置为基准），放到任何目录都能跑；全部 bash + grep + awk，无第三方依赖。
