id: gene-accept-run-command
type: gene
signals: 验收; 回归; 拒绝口头完成; 多agent; 检查产物
score: 1.0
reuse_count: 1
created_at: 2026-09-03T23:20:00+0800

# 验收 = 可运行命令 + 可检查产物
strategy: 简报写死验收命令与通过标准; worker 回传命令输出原文; manager 自己复跑一遍
preconditions: 任务能定义"命令+产出物"式验收; 验收标准写不清就不派发（先拆清楚）
validation: 验收命令 exit 0、产物存在、diff 摘要与简报预期的文件/行数一致
