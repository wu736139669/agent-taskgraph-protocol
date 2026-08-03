#!/bin/bash
# agent-queue 一键安装：Claude Code + Codex 双端软链
# 用法：git clone <repo> agent-queue && cd agent-queue && ./install.sh
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"

# Claude Code
mkdir -p ~/.claude/skills
ln -sfn "$SRC" ~/.claude/skills/agent-queue
echo "✅ Claude Code: ~/.claude/skills/agent-queue -> $SRC"

# Codex
mkdir -p ~/.codex/skills
ln -sfn "$SRC" ~/.codex/skills/agent-queue
echo "✅ Codex: ~/.codex/skills/agent-queue -> $SRC"

echo ""
echo "安装完成。新会话中触发关键词（派活 / 任务队列 / 多agent写代码 / 编排…）即可使用。"
echo "说明：改 $SRC 里的任何文件，双端即时生效（同一份软链源）。"
