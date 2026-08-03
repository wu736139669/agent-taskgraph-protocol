#!/bin/bash
# log-cleanup.sh — 会话日志卫生（防止 14GB+ 磁盘膨胀）
#
# 清理原则：已结束的会话日志按时间清理；活跃会话（正在写）的日志天然受 mtime 保护。
# 用法:
#   ./log-cleanup.sh            # dry-run：只预览将删什么，不删
#   ./log-cleanup.sh --apply    # 真正清理
#
# 策略:
#   Codex archived_sessions/  删除 >30 天的 rollout jsonl（已归档的旧会话）
#   Codex sessions/           删除 >14 天的 rollout jsonl（活跃会话 mtime 新，天然安全）
#   HAPI logs/                删除 >7 天的 *.log
# 注意: watch 中的日志如果已停止写入超过上述天数，也会被清——watch 到的终态后本就该归档

DRY=1
[ "$1" = "--apply" ] && DRY=0
ACT="删除"; [ $DRY -eq 1 ] && ACT="将删除(dry-run)"

codex_sessions="$HOME/.codex/sessions"
codex_archived="$HOME/.codex/archived_sessions"
hapi_logs="$HOME/.hapi/logs"

echo "== 日志卫生检查 =="
for dir in "$codex_sessions" "$codex_archived" "$hapi_logs"; do
  [ -d "$dir" ] && du -sh "$dir" 2>/dev/null | awk '{print "当前:", $1, $2}'
done

echo ""
echo "== Codex archived_sessions (>30天) =="
find "$codex_archived" -name "*.jsonl" -mtime +30 2>/dev/null | wc -l | xargs echo "  $ACT 文件数:"
if [ $DRY -eq 0 ]; then find "$codex_archived" -name "*.jsonl" -mtime +30 -delete 2>/dev/null; fi

echo "== Codex sessions (>14天) =="
find "$codex_sessions" -name "*.jsonl" -mtime +14 2>/dev/null | wc -l | xargs echo "  $ACT 文件数:"
if [ $DRY -eq 0 ]; then find "$codex_sessions" -name "*.jsonl" -mtime +14 -delete 2>/dev/null; fi

echo "== HAPI logs (>7天) =="
find "$hapi_logs" -name "*.log" -mtime +7 2>/dev/null | wc -l | xargs echo "  $ACT 文件数:"
if [ $DRY -eq 0 ]; then find "$hapi_logs" -name "*.log" -mtime +7 -delete 2>/dev/null; fi

echo ""
echo "清理完成" $( [ $DRY -eq 1 ] && echo "(dry-run，未删任何文件；确认后运行 ./log-cleanup.sh --apply)" )
