#!/bin/bash
# watch-worker.sh <日志路径> — 挂持续监视器，实时流式输出 worker 进展
#
# 用法:
#   ./watch-worker.sh ~/.codex/sessions/2026/08/03/rollout-xxx.jsonl   # Codex worker
#   ./watch-worker.sh ~/.hapi/logs/<session>.log                       # HAPI worker
#
# 事件流格式:
#   📥 USER   用户/系统输入
#   🤖 AGENT  agent 实质产出
#   🛠 CALL   工具调用（进展信号）
#   🏁 END    任务终态（task_complete / task_failed）
#   ❌ ERROR  错误事件
#   📄        原始文本行（非 JSON 日志）
#
# 注意:
#   - 静默（无事件流出）才是卡死信号，不是"没有 wait"
#   - 判断异常前先 tail -60 <日志> 查上下文，不要凭事件名下结论
#   - 经验：Codex 的 wait 带 cell_id/yield_time_ms 是 notebook 分片执行（正常）

LOG="${1:?用法: watch-worker.sh <日志路径>}"
[ -f "$LOG" ] || { echo "❌ 日志不存在: $LOG"; exit 1; }

echo "👁 watch: $LOG"
echo "   （Ctrl-C 停止；静默即卡死信号；异常先 tail -60 查上下文；tail -F 自动重连轮转）"

tail -F "$LOG" | python3 -u -c "
import json, sys
ext = sys.argv[1].rsplit('.', 1)[-1]
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    if ext != 'jsonl':
        # HAPI 等文本日志：整行输出
        print('📄', line[:150])
        continue
    # Codex rollout jsonl
    try:
        o = json.loads(line)
    except Exception:
        continue
    t = o.get('type', '')
    p = o.get('payload', {})
    if t == 'event_msg':
        pt = p.get('type', '')
        if pt == 'user_message':
            print('📥 USER:', str(p.get('message', ''))[:100].replace(chr(10), ' '))
        elif pt in ('task_complete', 'task_failed'):
            print('🏁 END:', pt.upper())
        elif 'error' in pt.lower():
            print('❌ ERROR:', pt)
    elif t == 'response_item' and p.get('type') == 'agent_message':
        print('🤖 AGENT:', str(p.get('content', ''))[:120].replace(chr(10), ' '))
    elif t == 'response_item' and p.get('type') == 'function_call':
        name = p.get('name') or (p.get('function', {}) or {}).get('name', '?')
        print('🛠 CALL:', name)
" "$LOG"
