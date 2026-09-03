#!/usr/bin/env bash
# lesson-record.sh —— 把一次"跑完验收"的结果沉淀为经验 Capsule（案例），并重建经验台账。
#
# 用法:
#   scripts/lesson-record.sh <brief.md> <验证输出文件|-> [gene-id] [选项]
#     scripts/lesson-record.sh queue/done/task.md - gene-xxx --kind success
#     cat verify.log | scripts/lesson-record.sh queue/done/task.md -
#     scripts/lesson-record.sh --reindex        # 只重建 lessons/ledger.json（全量扫描，不加新条目）
#
# 选项:
#   --gene <gene-id>     关联 Gene（也可作为第 3 个位置参数传入；不关联传 none）
#   --kind <success|failure>   验收结果；缺省从验证输出自动识别（PASS/通过 => success，FAIL/失败 => failure），识别不了报错
#   --signals "词1; 词2"  信号词；缺省取简报标题
#   --summary "<一句话>"  capsule 摘要；缺省取简报「目标」段第一句
#   --strategy "<要点>"   成功=怎么做；失败=避免建议（1-3 条短句）
#   --diff "<摘要>"       diff 摘要（files=...; +n/-m）；缺省自动跑 `git diff --stat HEAD`
#   --source-task "<路径>" 来源任务；缺省取简报路径
#   --score <0-1>         经验分；缺省 success=1.0 / failure=0.2
#
# 幂等与原子:
#   id = sha256(内容字段) 前 12 位；同一输入重复执行 → 相同 id → 已存在则跳过写入（不重复计数）。
#   env 里的 date、score/reuse_count/created_at 不参与哈希（跨天重跑同输入仍同 id）。
#   全部写入为 临时文件 + mv（原子）；ledger.json 永远是派生索引，可 --reindex 重建。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LESSONS="$ROOT/lessons"
GENES_DIR="$LESSONS/genes"
CAPS_DIR="$LESSONS/capsules"
LEDGER="$LESSONS/ledger.json"

die() { echo "error: $*" >&2; exit 1; }

usage() { sed -n '2,4p;6,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

sha256() {  # 内容寻址（macOS shasum / Linux sha256sum / openssl 兜底）
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  else openssl dgst -sha256 | awk '{print $NF}'
  fi
}

val() {  # 提取文件里 `key: 值` 字段（只认行首 key:）
  awk -v p="$1" 'index($0, p": ")==1 {print substr($0, length(p)+3); exit}' "$2"
}

# ---------- 参数 ----------
MODE=record
BRIEF=""; VERIFY=""; KIND=""; GENE="none"; SIGNALS=""; SUMMARY=""; STRATEGY=""
DIFF=""; SOURCE_TASK=""; SCORE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --reindex) MODE=reindex; shift ;;
    --gene|--kind|--signals|--summary|--strategy|--diff|--source-task|--score)
      [ $# -ge 2 ] || die "选项 $1 缺少参数"
      KEY="${1#--}"; VALUE="$2"
      case "$KEY" in
        gene) GENE="$VALUE" ;; kind) KIND="$VALUE" ;; signals) SIGNALS="$VALUE" ;;
        summary) SUMMARY="$VALUE" ;; strategy) STRATEGY="$VALUE" ;; diff) DIFF="$VALUE" ;;
        source-task) SOURCE_TASK="$VALUE" ;; score) SCORE="$VALUE" ;;
      esac
      shift 2 ;;
    -h|--help) usage ;;
    -)
      if [ -z "$BRIEF" ]; then BRIEF="$1"; elif [ -z "$VERIFY" ]; then VERIFY="$1"; else die "多余参数: $1"; fi
      shift ;;
    -*) die "未知选项: $1" ;;
    *)
      if [ -z "$BRIEF" ]; then
        BRIEF="$1"
      elif [ -z "$VERIFY" ]; then
        VERIFY="$1"
      elif [ "$GENE" = "none" ]; then
        GENE="$1"
      else
        die "多余参数: $1"
      fi
      shift ;;
  esac
done

# ---------- ledger 重建（权威源 = genes/ + capsules/ 的 .md） ----------
rebuild_ledger() {
  mkdir -p "$LESSONS"
  local tmp list="" f line id type kind signals score reuse created updated
  tmp="$(mktemp "$LESSONS/.ledger.XXXXXX")" || die "无法创建临时文件"
  for f in "$GENES_DIR"/*.md "$CAPS_DIR"/*.md; do
    [ -f "$f" ] || continue
    id="$(val id "$f")"; type="$(val type "$f")"; kind="$(val kind "$f")"
    signals="$(val signals "$f")"; score="$(val score "$f")"
    reuse="$(val reuse_count "$f")"; created="$(val created_at "$f")"
    [ -n "$id" ] || die "缺 id 字段: $f"
    [ -n "$score" ] || score=0.5; [ -n "$reuse" ] || reuse=0; [ -n "$created" ] || created="1970-01-01T00:00:00+0000"
    # 值去引号（JSON 安全）；kind 仅 capsule 有
    signals="$(printf '%s' "$signals" | sed 's/["\\]//g')"
    id="$(printf '%s' "$id" | sed 's/["\\]//g')"
    if [ "$type" = "capsule" ]; then
      line="{\"id\": \"$id\", \"type\": \"capsule\", \"kind\": \"$kind\", \"signals\": \"$signals\", \"score\": $score, \"reuse_count\": $reuse, \"created_at\": \"$created\"}"
    else
      line="{\"id\": \"$id\", \"type\": \"$type\", \"signals\": \"$signals\", \"score\": $score, \"reuse_count\": $reuse, \"created_at\": \"$created\"}"
    fi
    list="$list$created	$line
"
  done
  updated="$(printf '%s' "$list" | awk -F'\t' 'NF && $1>m{m=$1} END{print m}')"
  [ -n "$updated" ] || updated="1970-01-01T00:00:00+0000"
  {
    echo "{"
    echo "  \"version\": 1,"
    # 取最新资产创建时间，确保相同资产反复 --reindex 时字节级幂等。
    echo "  \"updated_at\": \"$updated\","
    echo "  \"note\": \"派生索引：权威源是 lessons/genes/ 与 lessons/capsules/ 下的 .md；可运行 scripts/lesson-record.sh --reindex 重建。\","
    echo "  \"entries\": ["
    if [ -n "$list" ]; then
      printf '%s' "$list" | sort -k1,1r | awk -F'\t' '{print $2}' | \
        awk 'NR>1{printf ",\n"} {printf "    %s", $0}'
      echo ""
    fi
    echo "  ]"
    echo "}"
  } > "$tmp"
  mv -f "$tmp" "$LEDGER"
}

if [ "$MODE" = reindex ]; then
  rebuild_ledger
  echo "ledger 已重建: $LEDGER"
  exit 0
fi

[ -n "$BRIEF" ] || die "缺少简报路径（用法: lesson-record.sh <brief.md> <验证输出文件|->）"
[ -f "$BRIEF" ] || die "简报不存在: $BRIEF"
[ -n "$VERIFY" ] || die "缺少验证输出（文件路径或 - 表示 stdin）"

# ---------- 输入读取 ----------
if [ "$VERIFY" = "-" ]; then
  VERIFY_TEXT="$(cat)"
else
  [ -f "$VERIFY" ] || die "验证输出文件不存在: $VERIFY"
  VERIFY_TEXT="$(cat "$VERIFY")"
fi

# ---------- 判定 kind ----------
if [ -z "$KIND" ]; then
  if printf '%s' "$VERIFY_TEXT" | grep -qi 'PASS\|通过\|成功'; then KIND=success
  elif printf '%s' "$VERIFY_TEXT" | grep -qi 'FAIL\|失败\|不通过'; then KIND=failure
  else die "无法从验证输出判定通过/失败，请显式传 --kind success|failure"
  fi
fi
KIND="$(printf '%s' "$KIND" | tr '[:upper:]' '[:lower:]')"
[ "$KIND" = "success" ] || [ "$KIND" = "failure" ] || die "--kind 只接受 success / failure"

# ---------- 字段默认值 ----------
TITLE="$(head -1 "$BRIEF" | sed 's/^#\+ *//;s/^任务：//;s/^任务://')"
[ -n "$SIGNALS" ] || SIGNALS="$TITLE"
[ -n "$SOURCE_TASK" ] || SOURCE_TASK="$BRIEF"
[ -n "$SUMMARY" ] || SUMMARY="$(awk '/^## 目标/{f=1;next} /^## /{f=0} f && NF {print; exit}' "$BRIEF" | cut -c1-120)"
[ -n "$SUMMARY" ] || SUMMARY="$(printf '%s' "$VERIFY_TEXT" | head -1 | cut -c1-120)"
[ -n "$SUMMARY" ] || SUMMARY="$TITLE"
[ -n "$SCORE" ] || { [ "$KIND" = success ] && SCORE=1.0 || SCORE=0.2; }
awk -v s="$SCORE" 'BEGIN { exit !(s ~ /^[0-9]+([.][0-9]+)?$/ && s >= 0 && s <= 1) }' || \
  die "--score 必须是 0 到 1 之间的数字"

if [ "$KIND" = "failure" ] && [ -z "$STRATEGY" ]; then
  die "failure Capsule 必须用 --strategy 写 1-3 条避免建议（蒸馏短句，不要粘贴日志）"
fi

if [ "$GENE" != "none" ]; then
  [ -f "$GENES_DIR/$GENE.md" ] || die "Gene 不存在: lessons/genes/$GENE.md（请先沉淀 Gene，或传 --gene none）"
fi

# diff 摘要：显式传参 > git 统计 > 占位
if [ -z "$DIFF" ]; then
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    DIFF="$(git -C "$ROOT" diff --stat HEAD 2>/dev/null | tail -1 | sed 's/^ *//;s/ *$//')" || true
  fi
  [ -n "$DIFF" ] || DIFF="未记录"
fi

# ---------- 组装与内容寻址 ----------
REPO="$(basename "$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$ROOT")")"
BRANCH="$(git -C "$ROOT" branch --show-current 2>/dev/null || printf 'none')"
ENV_ID="repo=$REPO; branch=$BRANCH; os=$(uname -s)"          # 参与哈希的稳定指纹
ENV_LINE="$ENV_ID; date=$(date '+%Y-%m-%d')"                  # 记录用完整指纹
VERIFY_COND="$(printf '%s' "$VERIFY_TEXT" | awk 'NF{n++; if(n<=3) print substr($0,1,120)}')"

PAYLOAD="$(printf 'type=capsule\nkind=%s\ngene=%s\nsignals=%s\nsummary=%s\nstrategy=%s\ndiff=%s\nsource=%s\nenv=%s\nverify=%s\n' \
  "$KIND" "$GENE" "$SIGNALS" "$SUMMARY" "$STRATEGY" "$DIFF" "$SOURCE_TASK" "$ENV_ID" "$VERIFY_COND")"
ID="$(printf '%s' "$PAYLOAD" | sha256 | cut -c1-12)"
FILE="$CAPS_DIR/capsule-$ID.md"

mkdir -p "$CAPS_DIR"

# ---------- 幂等写 ----------
if [ -f "$FILE" ]; then
  echo "已存在（幂等跳过）: $FILE"
  rebuild_ledger
  exit 0
fi

TMP="$(mktemp "$CAPS_DIR/.capsule.XXXXXX")" || die "无法创建临时文件"
{
  echo "# Capsule $ID"
  echo "id: capsule-$ID"
  echo "type: capsule"
  echo "kind: $KIND"
  echo "gene: $GENE"
  echo "signals: $SIGNALS"
  echo "env: $ENV_LINE"
  echo "diff: $DIFF"
  echo "result: $([ "$KIND" = success ] && echo 通过 || echo 失败)"
  echo "summary: $SUMMARY"
  if [ -n "$STRATEGY" ]; then echo "strategy: $STRATEGY"; fi
  printf '%s\n' "$VERIFY_COND" | sed 's/^/verify: /'
  echo "source_task: $SOURCE_TASK"
  echo "score: $SCORE"
  echo "reuse_count: 0"
  echo "created_at: $(date '+%Y-%m-%dT%H:%M:%S%z')"
} > "$TMP"
mv -f "$TMP" "$FILE"

rebuild_ledger
echo "已沉淀: $FILE"
echo "  信号: $SIGNALS"
echo "  结果: $KIND / score $SCORE / gene $GENE"
