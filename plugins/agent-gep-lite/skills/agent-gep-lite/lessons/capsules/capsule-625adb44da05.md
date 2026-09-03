id: capsule-625adb44da05
type: capsule
kind: success
gene: gene-accept-run-command
signals: 并行开发; 验收; 文案替换; multi-agent
env: repo=agent-queue; branch=main; os=Darwin; date=2026-09-03
diff: files=src/home.html,src/about.html; +2/-0
result: 通过
summary: 首轮没写死验收命令，worker 口头完成但 2 页漏改；验收命令入简报补做后通过
strategy: 简报写死验收命令与通过标准; worker 回传命令输出原文; manager 自己复跑
verify: == 验收命令: grep -n "<新文案>" src/home.html src/about.html && git diff --stat HEAD
verify: src/home.html:12:新文案
verify: src/about.html:8:新文案
source_task: queue/done/hist-early-parallel-dispatch.md
score: 1.0
reuse_count: 1
created_at: 2026-09-03T23:38:03+0800
