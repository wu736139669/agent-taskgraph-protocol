id: gene-conflict-map
type: gene
signals: 冲突面; 共享文件; 并行派发; package.json; 依赖; 路由; 迁移
score: 1.0
reuse_count: 0
created_at: 2026-09-03T23:20:00+0800

# 派发前先做冲突面分析
strategy: 列每条需求触碰的文件清单，标记共享面; 共享文件只追加不修改; 改动大有先后就改串行排队
preconditions: 多需求/大目标拆解阶段; 高频共享面必查（导航注册、依赖、全局样式、路由、数据库迁移、配置、API 网关）
validation: 每个 worktree 互不触碰共享文件; 合并时零冲突; 若合并冲突说明拆解阶段漏了冲突面分析
