#!/usr/bin/env bash
# lesson-recall.sh —— 分诊前召回经验：信号词命中 + score 加权 + 时间新→旧，输出 top-N 蒸馏摘要。
#
# 用法:
#   scripts/lesson-recall.sh "<信号词 或 分号分隔的短语>" [选项]
#     scripts/lesson-recall.sh "并行开发; 验收; 冲突面"
#     scripts/lesson-recall.sh "共享文件 package.json" -n 3 --append queue/inbox/new-task.md
#     scripts/lesson-recall.sh --append queue/inbox/new-task.md  # 从简报标题/目标推导查询词
#
# 选项:
#   -n <N>            召回条数，默认 5（上限 20）
#   --kind <capsule|gene|all>   只召 capsules / 只召 genes / 全部（默认 all，capsule 略优先）
#   --append <brief>  把「相关经验」段写入简报（可省略查询词；标记区间替换，幂等）
#   --bump            把被召回条目的 reuse_count +1（"经验被复用一次"的记账点）
#
# 排名: total = 信号词命中数×2 + score×5（capsule +0.1 微优先），同分按 created_at 新→旧。
# 输出: 每条 ≤3 行（1 行标题 + 2 行蒸馏要点），失败案例第 3 行前缀「避免:」。
# 纯本地：grep + awk + sort，零新依赖；所有改写（--bump/--append）都是临时文件 + mv 原子写。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GENES_DIR="$ROOT/lessons/genes"
CAPS_DIR="$ROOT/lessons/capsules"

die() { echo "error: $*" >&2; exit 1; }

val() { awk -v p="$1" 'index($0, p": ")==1 {print substr($0, length(p)+3); exit}' "$2"; }
shrink() { awk 'length>100 {print substr($0,1,100) "…"; exit} {print}'; }

# ---------- 参数 ----------
QUERY=""; N=5; KIND_FILTER=all; APPEND=""; BUMP=0
while [ $# -gt 0 ]; do
  case "$1" in
    -n) [ $# -ge 2 ] || die "-n 缺参数"; N="$2"; shift 2 ;;
    --kind) [ $# -ge 2 ] || die "--kind 缺参数"; KIND_FILTER="$2"; shift 2 ;;
    --append) [ $# -ge 2 ] || die "--append 缺参数"; APPEND="$2"; shift 2 ;;
    --bump) BUMP=1; shift ;;
    -h|--help) sed -n '2,4p;6,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "未知选项: $1" ;;
    *)
      if [ -z "$QUERY" ]; then QUERY="$1"; else die "多余参数: $1"; fi
      shift ;;
  esac
done

[ -z "$APPEND" ] || [ -f "$APPEND" ] || die "简报不存在: $APPEND"
if [ -z "$QUERY" ] && [ -n "$APPEND" ]; then
  # 便捷模式：派发时只给 --append，查询词由简报标题和目标首句推导。
  TITLE_QUERY="$(head -1 "$APPEND" | sed 's/^#\+ *//;s/^任务简报[：:] *//;s/^任务[：:] *//')"
  GOAL_QUERY="$(awk '/^## 目标/{f=1;next} /^## /{f=0} f && NF {print; exit}' "$APPEND" | cut -c1-120)"
  QUERY="$TITLE_QUERY; $GOAL_QUERY"
fi
[ -n "$(printf '%s' "$QUERY" | tr -d '[:space:];,，、；')" ] || \
  die "缺少信号词（可显式传 \"<信号词>\"，或配合 --append 从简报推导）"
case "$KIND_FILTER" in capsule|gene|all) ;; *) die "--kind 只接受 capsule/gene/all" ;; esac
case "$N" in ''|*[!0-9]*) die "-n 只接受 1-20 的整数" ;; esac
[ "$N" -ge 1 ] && [ "$N" -le 20 ] || die "-n 取值 1-20"
{ [ -d "$GENES_DIR" ] || [ -d "$CAPS_DIR" ]; } || die "lessons/ 还没有经验（先跑 lesson-record.sh 沉淀）"

# ---------- 信号词拆分（空格/分号/逗号/顿号，含中文标点） ----------
if command -v perl >/dev/null 2>&1; then
  WORDS_STR="$(printf '%s' "$QUERY" | perl -Mutf8 -CS -pe 's/[;，、；,]/ /g' | tr -s ' ' '\n' | sed '/^ *$/d')"
else  # 兜底：只拆 ASCII 分隔符
  WORDS_STR="$(printf '%s' "$QUERY" | tr ';,' '  ' | tr -s ' ' '\n' | sed '/^ *$/d')"
fi
WORDS=()
while IFS= read -r w; do WORDS+=("$w"); done <<<"$WORDS_STR"
[ ${#WORDS[@]} -gt 0 ] || die "信号词为空"

# ---------- 扫描打分 ----------
SORTED="$(mktemp "$ROOT/.recall.XXXXXX")" || die "无法创建临时文件"
OUTSEC="$(mktemp "$ROOT/.recall-sec.XXXXXX")" || die "无法创建临时文件"
trap 'rm -f "$SORTED" "$OUTSEC"' EXIT

# 把标记区间替换为指定文件内容；内容文件为空时只清除旧区间。
# 没有标记且内容非空时追加到简报末尾。所有写入都在同目录临时文件中完成再 mv。
write_brief_section() {
  local brief="$1" block="$2"
  awk -v S='<!-- lesson-recall:start -->' -v E='<!-- lesson-recall:end -->' -v B="$block" '
    $0 == S { inblock=1; found=1; next }
    $0 == E { inblock=0; next }
    !inblock { print }
    END {
      if (B != "") {
        while ((getline line < B) > 0) print line
        close(B)
      }
    }
  ' "$brief" > "$brief.tmp.$$" && mv -f "$brief.tmp.$$" "$brief"
}

for f in "$CAPS_DIR"/*.md "$GENES_DIR"/*.md; do
  [ -f "$f" ] || continue
  type="$(val type "$f")"
  case "$KIND_FILTER" in
    capsule) [ "$type" = capsule ] || continue ;;
    gene)    [ "$type" = gene ] || continue ;;
  esac
  hits=0
  for w in "${WORDS[@]}"; do
    if grep -qiF -- "$w" "$f"; then hits=$((hits+1)); fi
  done
  [ "$hits" -gt 0 ] || continue
  score="$(val score "$f")"; [ -n "$score" ] || score=0.5
  created="$(val created_at "$f")"; [ -n "$created" ] || created="1970-01-01T00:00:00+0000"
  kind="$(val kind "$f")"; id="$(val id "$f")"; [ -n "$id" ] || id="$(basename "$f" .md)"
  total="$(awk -v h="$hits" -v s="$score" -v t="$type" 'BEGIN{printf "%.4f", h*2 + s*5 + (t=="capsule"?0.1:0)}')"
  # 注意: kind 为空时用占位符 "-"，避免连续制表符被 IFS 折叠导致 read 错位
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$total" "$created" "$type" "${kind:--}" "$id" "$hits" "$score" "$f" >> "$SORTED"
done

MATCHED="$(wc -l < "$SORTED" | tr -d ' ')"
if [ "$MATCHED" = "0" ]; then
  echo "（无命中经验：${#WORDS[@]} 个信号词没有匹配到任何 Gene/Capsule）"
  echo "→ 说明: 本轮为首次跑这类活，正常分诊执行；结束后跑 lesson-record.sh 回写，下一次就有经验可用。"
  if [ -n "$APPEND" ]; then
    write_brief_section "$APPEND" ""
    echo "已清除简报中的旧「相关经验」段（无命中不注入）: $APPEND"
  fi
  exit 0
fi

# ---------- 组装蒸馏摘要（每条 ≤3 行；构建一次，供 stdout 与 --append 复用） ----------
# 注意: 标记线必须是整段的第一/最后一行，这样 --append 整段替换时头部说明也会一起换掉（幂等）
{
  echo "<!-- lesson-recall:start -->"
  echo "## 相关经验（lesson-recall 召回 top-$N / 共 $MATCHED 条；命中数×2 + score×5，时间新→旧）"
  echo "> 只读摘要：每条 ≤3 行。长文经验会稀释提示词，需要时再去看 lessons/ 原文。"
  LC_ALL=C sort -t$'\t' -k1,1nr -k2,2r "$SORTED" | awk -v n="$N" 'NR<=n' | while IFS=$'\t' read -r total created type kind id hits score f; do
    [ "$kind" = "-" ] && kind=""
    title="$(sed -n 's/^# *//p' "$f" | head -1)"
    [ -n "$title" ] || title="$(val summary "$f" | shrink)"
    [ -n "$title" ] || title="$id"
    sig="$(val signals "$f" | shrink)"
    strat="$(val strategy "$f" | shrink)"
    echo "- [$type${kind:+:$kind}] $id | 命中 $hits 词 / score $score / $title"
    echo "  信号: $sig"
    if [ -n "$strat" ]; then
      if [ "$kind" = "failure" ]; then echo "  避免: $strat"; else echo "  要点: $strat"; fi
    else
      echo "  要点: （该条未填 strategy → 看 lessons/ 原文）"
    fi
  done
  echo "<!-- lesson-recall:end -->"
} > "$OUTSEC"

cat "$OUTSEC"

# ---------- --bump: 被召回条目 reuse_count +1 ----------
if [ "$BUMP" = 1 ]; then
  LC_ALL=C sort -t$'\t' -k1,1nr -k2,2r "$SORTED" | awk -v n="$N" 'NR<=n' | cut -f8 | while IFS= read -r f; do
    awk '/^reuse_count:/ { split($0,a,/: /); $0 = "reuse_count: " (a[2]+1) } { print }' "$f" > "$f.bump.$$" && mv -f "$f.bump.$$" "$f"
  done
  # ledger 是派生索引；计数写回资产后立刻重建，避免索引与权威源不同步。
  "$ROOT/scripts/lesson-record.sh" --reindex >/dev/null
  echo "（--bump: 已把被召回的 top-$N 条 reuse_count 各 +1，并同步重建 ledger）"
fi

# ---------- --append: 注入简报（标记区间替换；没标记则末尾追加。幂等） ----------
if [ -n "$APPEND" ]; then
  write_brief_section "$APPEND" "$OUTSEC"
  echo "已注入「相关经验」段: ${APPEND}（重复执行会整段替换，不会叠加）"
fi
