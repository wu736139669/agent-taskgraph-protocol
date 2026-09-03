# Capsule capsule-03c6cd42e12c
id: capsule-03c6cd42e12c
type: capsule
kind: failure
gene: gene-conflict-map
signals: 冲突面; 共享文件; 并行派发; 依赖; package.json
env: repo=agent-queue; branch=main; os=Darwin; date=2026-09-03
diff: files=package.json; 冲突: content conflict
result: 失败
summary: 两条需求都改 package.json，未做冲突面分析直接并行派发，merge 冲突手动解决 40 分钟，验收失败
strategy: 派发前必列触碰文件清单; 共享文件改动大就改串行; 同组共享文件只追加不修改
verify: == git merge feature-a
verify: CONFLICT (content): Merge conflict in package.json
verify: error: 合并冲突需手动解决，耗时 40 分钟
source_task: queue/done/hist-conflict-na-dispatch.md
score: 0.2
reuse_count: 0
created_at: 2026-09-03T23:38:03+0800
