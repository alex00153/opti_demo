#!/usr/bin/env bash
#
# opti_demo —— LLM 辅助 RTL 优化的最小闭环（headless 版）
#
# 闭环流程：
#   1) 基线评分：yosys 综合 -> abc+liberty 映射 -> 面积(µm²) 与逻辑深度(ltp)
#   2) LLM 生成：调用 llm_agent.py（学生可修改）生成优化后 RTL
#   3) 等价性验证：equiv_agent.py（激励 testbench -> iverilog 仿真 -> VCD 波形比对）
#   4) 优化评分：对优化后 RTL 重跑 (1)
#   5) 汇总报告：<outdir>/report.md
#
# 用法：./run_demo.sh --help
#   （面向用户的文案集中在 ui_text.json；本机工具路径集中在 tools.env）
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---- 载入 UI 文案（ui_text.json -> UI_* 变量）-------------------------------
eval "$(python3 "$SCRIPT_DIR/ui_text.py" --shell)"

fill() {  # $1=模板，其余 k=v -> 用值替换模板中的 {k}
  local s="$1"; shift
  local kv key val
  for kv in "$@"; do
    key="${kv%%=*}"; val="${kv#*=}"
    s="${s//\{$key\}/$val}"
  done
  printf '%s' "$s"
}

VERBOSE="${DEMO_VERBOSE:-0}"

log() {  # 啰嗦模式(-v)下附带消息来源 file:line，便于定位是哪一行触发的输出
  if [ "$VERBOSE" = "1" ]; then
    printf '%s %s:%s > %s\n' "$UI_PREFIX_DEMO" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$*"
  else
    printf '%s %s\n' "$UI_PREFIX_DEMO" "$*"
  fi
}
err() {
  if [ "$VERBOSE" = "1" ]; then
    printf '%s %s:%s > %s\n' "$UI_PREFIX_DEMO_ERR" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$*" >&2
  else
    printf '%s %s\n' "$UI_PREFIX_DEMO_ERR" "$*" >&2
  fi
}

# ---- 本机工具路径：tools.env > 环境变量 -------------------------------------
TOOLS_ENV_FILE="$SCRIPT_DIR/tools.env"
tools_get() {  # $1=键 -> 回显值（tools.env 优先，其次同名环境变量），找不到则空
  local key="$1" val=""
  if [ -f "$TOOLS_ENV_FILE" ]; then
    val="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$TOOLS_ENV_FILE" \
           | tail -1 | sed 's/[[:space:]]*$//')"
  fi
  [ -n "$val" ] || val="${!key:-}"
  printf '%s' "$val"
}
YOSYS_BIN="$(tools_get YOSYS_BIN)"
LIB_FILE="$(tools_get LIB_FILE)"
IVERILOG_BIN="$(tools_get IVERILOG_BIN)"; IVERILOG_BIN="${IVERILOG_BIN:-iverilog}"
VVP_BIN="$(tools_get VVP_BIN)"; VVP_BIN="${VVP_BIN:-vvp}"
export IVERILOG_BIN VVP_BIN

PROMPT_FILE="$SCRIPT_DIR/prompts/rtl_optimize.md"
BASELINE="$SCRIPT_DIR/case/rtl/opt_top.v"
TOP=""
OUTDIR=""
EQUIV_ENABLE="${EQUIV_ENABLE:-1}"   # 1=做等价性验证；0=跳过
EQUIV_TB="${EQUIV_TB:-file}"        # file=预置 tb；llm=LLM 写；auto=内置确定性激励
TB_FILE=""

ARGC=$#
while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) BASELINE="$2"; shift 2 ;;
    --top)      TOP="$2"; shift 2 ;;
    --outdir)   OUTDIR="$2"; shift 2 ;;
    --no-equiv) EQUIV_ENABLE=0; shift ;;
    --equiv-tb) EQUIV_TB="$2"; shift 2 ;;
    --tb-file)  TB_FILE="$2"; shift 2 ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help)  printf '%s\n' "$UI_DEMO_HELP"; exit 0 ;;
    *) printf '%s\n' "$(fill "$UI_DEMO_UNKNOWN_ARG" "arg=$1")" >&2; exit 1 ;;
  esac
done
export DEMO_VERBOSE="$VERBOSE"

# ---------------------------------------------------------------------------
# 交互式"配置选择"：不带任何参数时进入；一路回车 = opt_top + 预置 tb 跑完整流程
# ---------------------------------------------------------------------------
prompt_choice() {  # $1=提示 $2=默认值 -> 回显用户输入或默认值
  local ans
  printf '%s [%s]: ' "$1" "$2" >&2
  read -r ans || ans=""
  if [ -n "$ans" ]; then printf '%s' "$ans"; else printf '%s' "$2"; fi
}

interactive_config() {
  local RTL_DIR="$SCRIPT_DIR/case"
  echo "$UI_DEMO_INTERACTIVE_BANNER"
  echo "$UI_DEMO_INTERACTIVE_HINT"
  echo
  echo "$UI_DEMO_INTERACTIVE_CASE_MENU"
  local idx; idx="$(prompt_choice "$UI_DEMO_INTERACTIVE_CHOICE_PROMPT" "1")"
  case "$idx" in
    1) BASELINE="$RTL_DIR/rtl/opt_top.v" ;;
    2) BASELINE="$RTL_DIR/bench/popcount3/popcount3_v1_behavioral.v" ;;
    3) BASELINE="$RTL_DIR/bench/addsubz/addsubz_v1_behavioral.v" ;;
    4) BASELINE="$RTL_DIR/bench/mult8/mult8_v1_behavioral.v" ;;
    5) BASELINE="$RTL_DIR/bench/mux2to1v/mux2to1v_v1_ternary.v" ;;
    6) BASELINE="$RTL_DIR/bench/mac8/mac8_v1_parallel_behavioral.v" ;;
    7) BASELINE="$RTL_DIR/bench/gcd/gcd_v1.v" ;;
    8) printf '%s' "$UI_DEMO_INTERACTIVE_CASE_PATH_PROMPT" >&2; read -r BASELINE ;;
    *) printf '%s\n' "$(fill "$UI_DEMO_INVALID_CHOICE" "choice=$idx")" >&2; exit 1 ;;
  esac
  echo
  echo "$UI_DEMO_INTERACTIVE_TB_MENU"
  local m; m="$(prompt_choice "$UI_DEMO_INTERACTIVE_CHOICE_PROMPT" "1")"
  case "$m" in 1) EQUIV_TB="file" ;; 2) EQUIV_TB="llm" ;; 3) EQUIV_TB="auto" ;; *) printf '%s\n' "$(fill "$UI_DEMO_INVALID_CHOICE" "choice=$m")" >&2; exit 1 ;; esac
  echo
  echo "$UI_DEMO_INTERACTIVE_EQUIV_MENU"
  local e; e="$(prompt_choice "$UI_DEMO_INTERACTIVE_CHOICE_PROMPT" "1")"
  if [ "$e" = "2" ]; then EQUIV_ENABLE=0; else EQUIV_ENABLE=1; fi
  echo
  TOP="$(prompt_choice "$UI_DEMO_INTERACTIVE_TOP_PROMPT" "")"
  OUTDIR="$(prompt_choice "$UI_DEMO_INTERACTIVE_OUTDIR_PROMPT" "$SCRIPT_DIR/out/$(basename "$(dirname "$BASELINE")")")"
  echo "$UI_DEMO_INTERACTIVE_FOOTER"
  echo
}

if [ "$ARGC" -eq 0 ]; then
  interactive_config
fi

case "$EQUIV_TB" in file|llm|auto) ;; *) printf '%s\n' "$(fill "$UI_DEMO_INVALID_EQUIV_TB" "value=$EQUIV_TB")" >&2; exit 1 ;; esac

[ -f "$BASELINE" ] || { BASELINE="$SCRIPT_DIR/$BASELINE"; }
[ -f "$BASELINE" ] || { printf '%s\n' "$(fill "$UI_DEMO_BASELINE_MISSING" "path=$BASELINE")" >&2; exit 1; }
BASELINE="$(cd "$(dirname "$BASELINE")" && pwd)/$(basename "$BASELINE")"

# 自动探测顶层模块（取文件内第一个 module 名）
[ -n "$TOP" ] || TOP="$(grep -m1 -oE '^[[:space:]]*module[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$BASELINE" | awk '{print $2}')"
[ -n "$TOP" ] || { printf '%s\n' "$UI_DEMO_TOP_AUTODETECT_FAILED" >&2; exit 1; }

# 输出目录默认按 case 名（基线所在目录名）
[ -n "$OUTDIR" ] || OUTDIR="$SCRIPT_DIR/out/$(basename "$(dirname "$BASELINE")")"
WORK_DIR="$SCRIPT_DIR/work/$(basename "$OUTDIR")"
mkdir -p "$OUTDIR" "$WORK_DIR"

resolve_tb_file() {  # $1=基线RTL(绝对) $2=顶层名 -> 回显预置 tb 路径，找不到则空
  local base="$1" top="$2" d n c
  d="$(dirname "$base")"; n="$(basename "$base")"; n="${n%.*}"
  for c in "$d/stim_$n.v" "$d/stim_$top.v" "$SCRIPT_DIR/case/bench/tb/stim_$(basename "$d").v"; do
    if [ -f "$c" ]; then printf '%s' "$c"; return 0; fi
  done
  printf ''
}

# file 模式：解析该 case 的预置激励 testbench；找不到则降级 auto
if [ "$EQUIV_ENABLE" = "1" ] && [ "$EQUIV_TB" = "file" ] && [ -z "$TB_FILE" ]; then
  TB_FILE="$(resolve_tb_file "$BASELINE" "$TOP")"
  if [ -z "$TB_FILE" ]; then
    log "$UI_DEMO_TB_DEGRADE_AUTO"
    EQUIV_TB="auto"
  else
    log "$(fill "$UI_DEMO_TB_PRESET" "path=$TB_FILE")"
  fi
fi

[ -n "$YOSYS_BIN" ] || { err "$(fill "$UI_TOOLS_UNSET" "key=YOSYS_BIN")"; exit 1; }
[ -x "$YOSYS_BIN" ] || { err "$(fill "$UI_DEMO_YOSYS_MISSING" "path=$YOSYS_BIN")"; exit 1; }
[ -n "$LIB_FILE" ]  || { err "$(fill "$UI_TOOLS_UNSET" "key=LIB_FILE")"; exit 1; }
[ -f "$LIB_FILE" ]  || { err "$(fill "$UI_DEMO_LIBERTY_MISSING" "path=$LIB_FILE")"; exit 1; }
[ -f "$PROMPT_FILE" ] || { err "$(fill "$UI_DEMO_PROMPT_MISSING" "path=$PROMPT_FILE")"; exit 1; }
command -v "$IVERILOG_BIN" >/dev/null || { err "$UI_DEMO_IVERILOG_MISSING"; exit 1; }

# 自定义后端（LLM_BACKEND=custom）没实现时的退出码，与 llm_agent.py 保持一致
LLM_NOT_IMPLEMENTED_EXIT="$(python3 -c 'import llm_agent; print(llm_agent.NOT_IMPLEMENTED_EXIT)' 2>/dev/null || echo 10)"

log "$(fill "$UI_DEMO_TOOLS_INFO" "yosys=$YOSYS_BIN" "liberty=$LIB_FILE")"
log "$(fill "$UI_DEMO_CASE_INFO" "baseline=$BASELINE" "top=$TOP" "outdir=$OUTDIR")"

gen_ys() {  # $1 = verilog 文件 -> 输出 yosys 脚本
  printf 'read_verilog -sv %s; read_liberty -lib %s; hierarchy -top %s; proc; opt; techmap; opt; abc -liberty %s; stat -liberty %s; ltp' \
    "$1" "$LIB_FILE" "$TOP" "$LIB_FILE" "$LIB_FILE"
}
extract_area()  { grep -oE "Chip area for module '[^']*': [0-9.]+" "$1" | tail -1 | grep -oE '[0-9.]+$' || true; }
extract_depth() { grep -oE '\(length=[0-9]+\)' "$1" | tail -1 | grep -oE '[0-9]+' || true; }

score_design() {  # $1=verilog文件 $2=标签 -> 回显 "面积 深度"
  local f="$1"
  local tag="$2"
  local log="$WORK_DIR/score_${tag}.log"
  if ! "$YOSYS_BIN" -p "$(gen_ys "$f")" > "$log" 2>&1; then
    err "$(fill "$UI_DEMO_YOSYS_FAIL" "tag=$tag" "log=$log")"; return 1
  fi
  printf '%s %s\n' "$(extract_area "$log")" "$(extract_depth "$log")"
}

# ---- 1. 基线评分 ---------------------------------------------------------
log "$(fill "$UI_DEMO_STEP" "n=1" "total=5" "title=$UI_DEMO_STEP1_TITLE")"
read -r BASE_AREA BASE_DEPTH < <(score_design "$BASELINE" baseline)
log "$(fill "$UI_DEMO_BASELINE_RESULT" "area=$BASE_AREA" "depth=$BASE_DEPTH")"

# ---- 2. LLM 生成优化 RTL（调用 llm_agent.py）-----------------------------
OPTIMIZED="$OUTDIR/optimized.v"
LLM_RESPONSE="$OUTDIR/llm_response.md"
log "$(fill "$UI_DEMO_STEP" "n=2" "total=5" "title=$UI_DEMO_STEP2_TITLE")"
LLM_RC=0
python3 "$SCRIPT_DIR/llm_agent.py" \
  --baseline "$BASELINE" --prompt "$PROMPT_FILE" \
  --top "$TOP" --out "$OPTIMIZED" --raw "$LLM_RESPONSE" \
  --env-file "$SCRIPT_DIR/.env" || LLM_RC=$?
# 自定义后端未实现：配置已就绪，就此收尾
if [ "$LLM_RC" = "$LLM_NOT_IMPLEMENTED_EXIT" ]; then
  log "$UI_DEMO_LLM_NOT_IMPLEMENTED"
  exit 0
fi
[ "$LLM_RC" -eq 0 ] || exit "$LLM_RC"

# ---- 3. 等价性验证（可开关；testbench 可由 LLM 或内置激励生成）--------------
# 逻辑已剥离到 equiv_agent.py：激励 tb 来源三选一，逐时刻比对 VCD 波形。
log "$(fill "$UI_DEMO_STEP" "n=3" "total=5" "title=$UI_DEMO_STEP3_TITLE")"
if [ "$EQUIV_ENABLE" = "1" ]; then
  TB_ARGS=()
  if [ "$EQUIV_TB" = "auto" ]; then TB_ARGS+=(--no-llm); fi
  if [ "$EQUIV_TB" = "file" ]; then TB_ARGS+=(--tb-file "$TB_FILE"); fi
  EQUIV="FAIL"
  if python3 "$SCRIPT_DIR/equiv_agent.py" \
       --gold "$BASELINE" --opt "$OPTIMIZED" --top "$TOP" \
       --outdir "$WORK_DIR/equiv" --prompt "$SCRIPT_DIR/prompts/equiv_tb.md" \
       --raw "$OUTDIR/equiv_tb_response.md" --env-file "$SCRIPT_DIR/.env" \
       ${TB_ARGS[@]+"${TB_ARGS[@]}"}; then
    EQUIV="PASS"
  fi
  log "$(fill "$UI_DEMO_EQUIV_RESULT" "verdict=$EQUIV" "src=$EQUIV_TB")"
else
  EQUIV="SKIP"
  log "$UI_DEMO_EQUIV_DISABLED"
fi

# ---- 4. 优化评分 ---------------------------------------------------------
log "$(fill "$UI_DEMO_STEP" "n=4" "total=5" "title=$UI_DEMO_STEP4_TITLE")"
read -r OPT_AREA OPT_DEPTH < <(score_design "$OPTIMIZED" optimized)
log "$(fill "$UI_DEMO_OPT_RESULT" "area=$OPT_AREA" "depth=$OPT_DEPTH")"

# ---- 5. 汇总报告 ---------------------------------------------------------
log "$(fill "$UI_DEMO_STEP" "n=5" "total=5" "title=$UI_DEMO_STEP5_TITLE")"
REPORT="$OUTDIR/report.md"
python3 - "$REPORT" "$BASELINE" "$TOP" "$BASE_AREA" "$BASE_DEPTH" \
          "$OPT_AREA" "$OPT_DEPTH" "$EQUIV" "$LLM_RESPONSE" "$WORK_DIR/equiv/equiv.log" \
          "$EQUIV_TB" <<'PY'
import sys, datetime
import ui_text as ui

(out, baseline, top, ba, bd, oa, od, equiv, resp, eqlog) = sys.argv[1:11]

def fnum(x):
    try: return float(x)
    except: return None

def delta(b, o):
    b, o = fnum(b), fnum(o)
    if b is None or o is None or b == 0: return "n/a"
    return f"{(o - b) / b * 100:+.1f}%"

ba_f, oa_f, bd_f, od_f = fnum(ba), fnum(oa), fnum(bd), fnum(od)
area_ok = ba_f is not None and oa_f is not None and oa_f < ba_f
depth_ok = bd_f is not None and od_f is not None and od_f <= bd_f
accepted = (equiv == "PASS" and area_ok and depth_ok)

L = []
L.append(ui.get("report.title") + "\n")
L.append(ui.fill(ui.get("report.generated_at"), ts=f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S}") + "  ")
L.append(ui.fill(ui.get("report.baseline_line"), baseline=baseline, top=top) + "\n")
L.append(ui.get("report.section_scores") + "\n")
L.append(ui.get("report.table_header"))
L.append(ui.get("report.table_sep"))
L.append(ui.fill(ui.get("report.row_area"), base=ba, opt=oa, delta=delta(ba, oa)))
L.append(ui.fill(ui.get("report.row_depth"), base=bd, opt=od, delta=delta(bd, od)))
L.append(ui.fill(ui.get("report.row_equiv"), equiv=equiv) + "\n")
L.append(ui.get("report.section_conclusion") + "\n")
if equiv == "SKIP":
    L.append(ui.get("report.skip_warning"))
    L.append(ui.fill(ui.get("report.skip_state"),
                     area_state=ui.get("report.area_down") if area_ok else ui.get("report.area_not_down"),
                     depth_state=ui.get("report.depth_ok") if depth_ok else ui.get("report.depth_bad")))
elif accepted:
    L.append(ui.get("report.accept"))
else:
    r = []
    if equiv != "PASS": r.append(ui.get("report.reason_equiv"))
    if not area_ok: r.append(ui.get("report.reason_area"))
    if not depth_ok: r.append(ui.get("report.reason_depth"))
    L.append(ui.get("report.reject_prefix") + ui.get("report.reject_sep").join(r) + ui.get("report.reject_suffix"))
L.append(ui.get("report.note_ltp"))
if equiv != "SKIP":
    # 实际使用的 tb 来源以 equiv_agent 的日志为准（llm/file 可能已降级为 auto）
    src_used = sys.argv[11]
    token = ui.get("equiv.source_token")
    try:
        for ln in open(eqlog, encoding="utf-8"):
            if token in ln:
                src_used = ln.split(token)[1].split()[0]
                break
    except Exception:
        pass
    L.append(ui.fill(ui.get("report.equiv_note"), src=src_used, eqlog=eqlog))
L.append("\n" + ui.fill(ui.get("report.raw_note"), resp=resp) + "\n")
open(out, 'w', encoding='utf-8').write("\n".join(L))
print("\n".join(L))
PY

log "$(fill "$UI_DEMO_REPORT_WRITTEN" "path=$REPORT")"
log "$(fill "$UI_DEMO_DONE" "report=$REPORT")"
[ "$EQUIV" = "SKIP" ] || log "$(fill "$UI_DEMO_TIPS_EQLOG" "eqlog=$WORK_DIR/equiv/equiv.log")"
log "$UI_DEMO_TIPS"
[ "$EQUIV" = "PASS" ] || [ "$EQUIV" = "SKIP" ] || { err "$UI_DEMO_EQUIV_REJECT"; exit 4; }
