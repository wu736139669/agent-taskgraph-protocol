# Goal: <项目/模块> <一句话目标>

> Stage: <阶段标签>（如 T1 authoring checkpoint / C11E1 implementation）
> Started: <时间>
> Baseline: `<git hash>`（clean, HEAD == origin/main；无 git 先补基线再派发）
> Accepted 上一阶段: `<hash>`（上一个 goal 的验收 hash，证据链；首任务可省）
> Independent contract: `<CONTRACT 路径>`（复杂任务才需要独立合同，简单任务验收标准内嵌本文件）
> Legal terminal: **<项目> <目标> candidate ready** 或 **<项目> <目标> redesign required: <最早失败边界>**

## Objective

（一段话：只做一件事，做成的样子，精确无歧义。写不清 = 白干一轮）

## 分配记录

- 派给：<会话 ID / 岗位名>
- 分配理由：相关性（同模块历史） / 职责匹配（岗位） / 负载均衡
- 工作区：<worktree 路径>（分支：<branch>）

## Required State-Dependent Choice（如适用）

（必须依据状态做选择的决策点——表格式：继承状态 | 条件 | 该选什么。不适用则删本节）

## 验收标准（证据门）

- [ ] 验收命令（worker 必须跑并把输出贴回）：
- [ ] 产物路径 / diff 位置：
- [ ] 终态判定：满足全部证据门 → "candidate ready"；任一失败 → 指出最早失败边界

## Frozen（禁止触碰，明确列出）

- 不允许修改的文件/模块：
- 冻结范围（后续阶段/新系统/发布类）：

## Estimate

- 实现：Xh / 调试：Xh / 跑测证据：Xh / PMO 审查：30-60m / 硬上限：Xh / 置信度：低中高

## 完成时交付

- diff 位置 / PR 链接
- 验收命令输出（贴回）
- 残余风险
