#!/usr/bin/env python3
"""
equiv_agent.py —— LLM 辅助的等价性验证（★ 学生可修改）

思路：不再依赖 yosys 形式化（miter+sat 对 $mul 等复杂单元不可靠），
改为**仿真对比**：
  1) 用 yosys 提取顶层端口（名字/方向/位宽），先做结构一致性检查；
  2) 取一个"激励 testbench"（三选一：预置 tb 文件 / LLM 生成 / 内置确定性激励），
     它只驱动顶层端口并 dump 波形；
  3) 把同一份 testbench 分别与 gold / opt 两版 RTL 一起用 iverilog 仿真（两版模块名相同，
     分开编译互不冲突），各产生一份 VCD 波形；
  4) 在 Python 里逐时刻比对输出端口的波形：完全一致 -> PASS，否则 FAIL 并报首次差异。

testbench 来源优先级：`--tb-file`（预置） > `--no-llm`（内置） > LLM（默认）；
任何一级编译/仿真失败或未 dump 出输出端口，都会自动降级到下一级（最终兜底=内置激励）。

用法：
  python3 equiv_agent.py --gold base.v --opt optimized.v --top opt_top \
      --outdir work/equiv [--tb-file case/rtl/stim_opt_top.v] [--no-llm] [--prompt ...]

退出码：0=等价(PASS)，2=不等价(FAIL)，3=无法判定(ERROR)。
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

# 复用 llm_agent.py 的配置解析与 call_llm 调用（学生改 LLM 相关只需看 llm_agent.py）
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from llm_agent import resolve_config, call_llm  # noqa: E402
import ui_text as ui  # noqa: E402
import tools  # noqa: E402

_EP = ui.get("prefix.equiv")          # [equiv]
_EEP = ui.get("prefix.equiv_err")     # [equiv][ERROR]


def _tag() -> str:
    """啰嗦模式下返回调用点 "文件:行号 > "，否则空串。

    loc(3)：跳过 _tag 和 log()/fail() 两层，落到真正发起日志的那一行。
    """
    return f"{ui.loc(3)} > " if ui.VERBOSE else ""


def log(msg: str, **kw) -> None:
    print(f"{_EP} {_tag()}{ui.fill(msg, **kw)}", file=sys.stderr)


def fail(msg: str, **kw) -> None:
    print(f"{_EEP} {_tag()}{ui.fill(msg, **kw)}", file=sys.stderr)
    sys.exit(3)


# 本机工具路径：tools.env > 环境变量（未配置时在 main 里报错提示）
YOSYS_BIN = tools.get("YOSYS_BIN")
IVERILOG_BIN = tools.get("IVERILOG_BIN", "iverilog")
VVP_BIN = tools.get("VVP_BIN", "vvp")

# 仿真步数与随机种子（固定，保证可复现）
AUTO_STIM_STEPS = 300
AUTO_STIM_SEED = 0xDEADBEEF


# ---------------------------------------------------------------------------
# 1) 端口提取与结构检查
# ---------------------------------------------------------------------------
def yosys_ports(rtl: str, top: str, yosys_bin: str = YOSYS_BIN) -> dict:
    """用 yosys write_json 提取顶层端口 -> {name: (direction, width)}。"""
    with tempfile.TemporaryDirectory() as td:
        jf = os.path.join(td, "netlist.json")
        script = (
            f"read_verilog -sv {rtl}; hierarchy -top {top}; proc; "
            f"write_json {jf}"
        )
        p = subprocess.run([yosys_bin, "-q", "-p", script],
                           capture_output=True, text=True)
        if p.returncode != 0 or not os.path.isfile(jf):
            fail(ui.get("equiv.err_yosys_ports"), err=p.stderr[-400:])
        data = json.load(open(jf, encoding="utf-8"))
    mod = data.get("modules", {}).get(top)
    if not mod:
        fail(ui.get("equiv.err_no_top"), top=top)
    ports = {}
    for name, info in mod.get("ports", {}).items():
        ports[name] = (info["direction"], len(info["bits"]))
    return ports


def check_ports(gold: dict, opt: dict) -> list:
    """返回结构不一致的描述列表（空表示一致）。"""
    problems = []
    if set(gold) != set(opt):
        only_g = sorted(set(gold) - set(opt))
        only_o = sorted(set(opt) - set(gold))
        if only_g:
            problems.append(ui.fill(ui.get("equiv.port_missing"), names=only_g))
        if only_o:
            problems.append(ui.fill(ui.get("equiv.port_extra"), names=only_o))
    for name in sorted(set(gold) & set(opt)):
        gd, gw = gold[name]
        od, ow = opt[name]
        if gd != od:
            problems.append(ui.fill(ui.get("equiv.port_dir"), name=name, gold=gd, opt=od))
        if gw != ow:
            problems.append(ui.fill(ui.get("equiv.port_width"), name=name, gold=gw, opt=ow))
    return problems


# ---------------------------------------------------------------------------
# 2) 预置 testbench 载入 + 仿真
# ---------------------------------------------------------------------------
def load_preset_tb(path: str) -> str:
    """载入预置激励 testbench，替换占位符。

    兼容两种写法：
      - 平铺占位符 `__VCD__` / `__SEED__`（与 case/bench/tb/stim_*.v 一致）
      - 直接用宏 `` `VCD_PATH ``（本 agent 的写法）
    """
    text = open(path, encoding="utf-8").read()
    text = text.replace('"__VCD__"', "`VCD_PATH")
    text = text.replace("__VCD__", "`VCD_PATH")
    text = text.replace("__SEED__", f"32'h{AUTO_STIM_SEED:08X}")
    return text


def extract_code_block(text: str) -> str:
    blocks = re.findall(r"```(?:verilog|systemverilog|v)?\s*\n(.*?)```", text, re.S)
    return (blocks[-1] if blocks else text).strip()


def run_sim(tb: str, rtl: str, vcd: str, workdir: str, label: str):
    """编译并运行一组 (tb + rtl)，返回 (ok, vcd路径, 日志)。"""
    vvp = os.path.join(workdir, f"sim_{label}.vvp")
    inc = os.path.join(workdir, f"inc_{label}.log")
    cmd_cc = [IVERILOG_BIN, "-g2012", f"-DVCD_PATH=\"{vcd}\"", "-o", vvp, tb, rtl]
    p1 = subprocess.run(cmd_cc, capture_output=True, text=True)
    log = p1.stdout + p1.stderr
    if p1.returncode != 0:
        return False, vcd, ui.fill(ui.get("equiv.err_compile"), log=log[-600:])
    p2 = subprocess.run([VVP_BIN, vvp], capture_output=True, text=True, cwd=workdir)
    log += p2.stdout + p2.stderr
    # 把编译/仿真日志落盘，便于排查
    open(inc, "w", encoding="utf-8").write(log)
    if p2.returncode != 0:
        return False, vcd, ui.fill(ui.get("equiv.err_vvp"), log=log[-600:])
    if not os.path.isfile(vcd):
        return False, vcd, ui.get("equiv.err_no_vcd")
    return True, vcd, log


# ---------------------------------------------------------------------------
# 3) VCD 解析与波形比对
# ---------------------------------------------------------------------------
def parse_vcd(path: str) -> dict:
    """解析 VCD，返回 {signal_name: [(time, normalized_value), ...]}。

    优先采用 dut 作用域内的信号；若 testbench 把实例起了不含 "dut" 的名字，
    则退化为接受全部信号（按名字合并）。
    """
    decl = {}         # code -> (name, width, in_dut)
    events = {}       # code -> [(t, val)]
    scope = []
    t = 0
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            if line.startswith("$scope"):
                parts = line.split()
                scope.append(parts[2] if len(parts) > 2 else "")
            elif line.startswith("$upscope"):
                if scope:
                    scope.pop()
            elif line.startswith("$var"):
                parts = line.split()
                # $var <type> <width> <code> <ref> [$end]
                if len(parts) >= 5:
                    in_dut = bool(scope) and "dut" in scope[-1].lower()
                    decl.setdefault(parts[3], (parts[4], int(parts[2]), in_dut))
            elif line.startswith("$enddefinitions"):
                pass
            elif line.startswith("#"):
                try:
                    t = int(line[1:])
                except ValueError:
                    pass
            else:
                c = line[0]
                if c in "bB":
                    sp = line.find(" ")
                    if sp > 0:
                        code = line[sp + 1:].strip()
                        events.setdefault(code, []).append((t, _norm(line[1:sp], None)))
                elif c in "01xzXZ":
                    code = line[1:].strip()
                    events.setdefault(code, []).append((t, _norm(c, None)))
    out, fallback = {}, {}
    for code, (name, _w, in_dut) in decl.items():
        if code in events:
            (out if in_dut else fallback).setdefault(name, events[code])
    for name, ev in fallback.items():
        out.setdefault(name, ev)
    return out


def _norm(val: str, meta) -> str:
    """把 VCD 值归一化（去掉二进制前导零），便于跨仿真比较。"""
    v = val.lower()
    if len(v) == 1 and v in "01xz":
        return v
    bits = v[1:] if v[:1] == "b" else v
    return bits.lstrip("0") or "0"


def compare_vcd(gold: dict, opt: dict, out_names: list):
    """按输出端口逐时刻比对波形，返回 (pass, 详情)。"""
    details = []
    ok = True
    for name in out_names:
        ge = gold.get(name)
        oe = opt.get(name)
        if ge is None or oe is None:
            ok = False
            details.append(ui.fill(ui.get("equiv.detail_missing"), name=name,
                                   g=ui.get("equiv.has") if ge else ui.get("equiv.none"),
                                   o=ui.get("equiv.has") if oe else ui.get("equiv.none")))
            continue
        if ge == oe:
            details.append(ui.fill(ui.get("equiv.detail_match"), name=name, n=len(ge)))
            continue
        ok = False
        # 找首个差异时刻
        for i in range(max(len(ge), len(oe))):
            g = ge[i] if i < len(ge) else None
            o = oe[i] if i < len(oe) else None
            if g != o:
                details.append(ui.fill(ui.get("equiv.detail_diff"), name=name,
                                       t=g[0] if g else (o[0] if o else "?"), g=g, o=o))
                break
    return ok, details


# ---------------------------------------------------------------------------
# 4) 内置确定性激励 testbench（LLM 失败时的降级路径）
# ---------------------------------------------------------------------------
def gen_auto_tb(ports: dict, top: str) -> str:
    """内置确定性激励：组合逻辑随机遍历；带 clk 则产生时钟、可选复位。"""
    ins = [(n, w) for n, (d, w) in ports.items() if d in ("input", "inout")]
    outs = [n for n, (d, _w) in ports.items() if d in ("output", "inout")]
    if not outs:
        fail(ui.get("equiv.err_no_output"))
    clk = next((n for n, _w in ins if n.lower() in ("clk", "clock")), None)
    rst = [n for n, _w in ins if n.lower().startswith(("rst", "reset"))]

    L = ["`timescale 1ps/1ps", "module tb;"]
    for n, w in ins:
        L.append(f"  reg [{w-1}:0] {n};")
    for n in outs:
        L.append(f"  wire [{ports[n][1]-1}:0] _o_{n};")
    conn = ", ".join([f".{n}({n})" for n, _w in ins] +
                     [f".{n}(_o_{n})" for n in outs])
    L.append(f"  {top} dut_i({conn});")
    L.append("  integer k; reg [31:0] rnd;")
    L.append("  initial begin")
    L.append("    $dumpfile(`VCD_PATH);")
    L.append(f"    rnd = 32'h{AUTO_STIM_SEED:08X};")
    for n, _w in ins:
        if n != clk:
            L.append(f"    {n} = 0;")
    for n in rst:
        L.append(f"    {n} = 1;")
    # 先复位/稳定，再开始记录波形（避免复位期间的 x/毛刺造成误判）
    L.append("    #20;")
    for n in rst:
        L.append(f"    {n} = 0;")
    L.append("    $dumpvars(1, dut_i);")
    L.append(f"    for (k = 0; k < {AUTO_STIM_STEPS}; k = k + 1) begin")
    for n, w in ins:
        if n == clk or n in rst:
            continue
        L.append("      rnd = (rnd * 1103515245 + 12345) & 32'hFFFFFFFF;")
        L.append(f"      {n} = rnd[{w-1}:0];")
    L.append("      #10;")
    L.append("    end")
    L.append("    $finish;")
    L.append("  end")
    if clk:
        L.append(f"  always #5 {clk} = ~{clk};")
    L.append("endmodule")
    return "\n".join(L)


# ---------------------------------------------------------------------------
# 5) LLM 生成激励 testbench
# ---------------------------------------------------------------------------
def build_equiv_prompt(template: str, top: str, ports: dict,
                       gold_src: str, opt_src: str) -> str:
    plist = "\n".join(
        f"- {n}: {d}, width={w}" for n, (d, w) in sorted(ports.items())
    )
    rep = {
        "{{TOP}}": top,
        "{{PORTS}}": plist,
        "{{GOLD_RTL}}": gold_src,
        "{{OPT_RTL}}": opt_src,
    }
    for k, v in rep.items():
        template = template.replace(k, v)
    return template


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=ui.get("equiv.cli.description"))
    ap.add_argument("--gold", required=True, help=ui.get("equiv.cli.gold"))
    ap.add_argument("--opt", required=True, help=ui.get("equiv.cli.opt"))
    ap.add_argument("--top", required=True, help=ui.get("equiv.cli.top"))
    ap.add_argument("--outdir", required=True, help=ui.get("equiv.cli.outdir"))
    ap.add_argument("--prompt", default="prompts/equiv_tb.md", help=ui.get("equiv.cli.prompt"))
    ap.add_argument("--env-file", default=".env")
    ap.add_argument("--raw", help=ui.get("equiv.cli.raw"))
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--no-llm", action="store_true", help=ui.get("equiv.cli.no_llm"))
    ap.add_argument("--tb-file", help=ui.get("equiv.cli.tb_file"))
    args = ap.parse_args()
    args.outdir = os.path.abspath(args.outdir)

    if not YOSYS_BIN:
        fail(ui.get("tools.unset"), key="YOSYS_BIN")

    os.makedirs(args.outdir, exist_ok=True)
    gold_src = open(args.gold, encoding="utf-8").read()
    opt_src = open(args.opt, encoding="utf-8").read()

    # --- (1) 结构一致性 ---
    gp = yosys_ports(args.gold, args.top)
    op = yosys_ports(args.opt, args.top)
    problems = check_ports(gp, op)
    if problems:
        log(ui.get("equiv.struct_mismatch"))
        for x in problems:
            print("  - " + x, file=sys.stderr)
        open(os.path.join(args.outdir, "equiv.log"), "w", encoding="utf-8").write(
            ui.get("equiv.struct_check_failed") + "\n" + "\n".join(problems) + "\n")
        sys.exit(3)
    log(ui.get("equiv.struct_ok"), n=len(gp))
    out_names = [n for n, (d, _w) in gp.items() if d in ("output", "inout")]

    def attempt(tb: str, tag: str):
        tbf = os.path.join(args.outdir, f"tb_{tag}.v")
        open(tbf, "w", encoding="utf-8").write(tb + "\n")
        vcd_g = os.path.join(args.outdir, f"gold_{tag}.vcd")
        vcd_o = os.path.join(args.outdir, f"opt_{tag}.vcd")
        okg, _, lg = run_sim(tbf, args.gold, vcd_g, args.outdir, f"gold_{tag}")
        oko, _, lo = run_sim(tbf, args.opt, vcd_o, args.outdir, f"opt_{tag}")
        if not okg or not oko:
            return None, None, f"gold: {lg if not okg else 'ok'}\nopt: {lo if not oko else 'ok'}"
        return parse_vcd(vcd_g), parse_vcd(vcd_o), "ok"

    # --- (2) 激励 testbench 候选：预置文件 > LLM > 内置确定性激励 ---
    candidates = []            # [(来源标签, tb 文本或 None=内置)]
    if args.tb_file:
        candidates.append(("file", load_preset_tb(args.tb_file)))
    elif not args.no_llm:
        try:
            cfg = resolve_config(args.env_file)
            cfg["timeout"] = args.timeout
            log(ui.get("equiv.llm_call"), model=cfg["model"] or "-")
            template = open(args.prompt, encoding="utf-8").read()
            prompt = build_equiv_prompt(template, args.top, gp, gold_src, opt_src)
            response = call_llm(prompt, cfg)
            if args.raw:
                open(args.raw, "w", encoding="utf-8").write(response)
            candidates.append(("llm", extract_code_block(response)))
        except SystemExit as e:
            log(ui.get("equiv.llm_fail"), err=e)
        except Exception as e:  # noqa: BLE001
            log(ui.get("equiv.llm_exc"), err=e)
    candidates.append(("auto", None))   # 兜底

    # --- (3) 依次尝试，直到某个 testbench 能产出可比较的输出波形 ---
    gv, ov, tb_source, err = None, None, "auto", "无可用 testbench"
    for tag, tb in candidates:
        tb = tb if tb is not None else gen_auto_tb(gp, args.top)
        # LLM 的杂散代码块可能不含 tb；预置/内置一般没问题
        if "module " not in tb:
            err = ui.fill(ui.get("equiv.no_module"), tag=tag)
            log(ui.get("equiv.try_next"), err=err)
            continue
        gv, ov, err = attempt(tb, tag)
        if gv is None:
            log(ui.get("equiv.sim_fail"), tag=tag, err=err)
            gv = None
            continue
        missing = [n for n in out_names if n not in gv or n not in ov]
        if missing:
            log(ui.get("equiv.missing_ports"), tag=tag, ports=missing)
            gv = None
            continue
        tb_source = tag
        break
    if gv is None:
        log(ui.get("equiv.all_failed"), err=err)
        open(os.path.join(args.outdir, "equiv.log"), "w", encoding="utf-8").write(err + "\n")
        sys.exit(3)

    # --- (4) 波形比对 ---
    ok, details = compare_vcd(gv, ov, out_names)
    verdict = "PASS" if ok else "FAIL"
    report = [
        ui.get("equiv.report_title"),
        f"",
        ui.fill(ui.get("equiv.report_top"), top=args.top, nport=len(gp), outs=out_names),
        ui.fill(ui.get("equiv.report_source"), src=tb_source),
        ui.fill(ui.get("equiv.report_verdict"), verdict=verdict),
        f"",
        ui.get("equiv.report_section"),
    ] + [f"- {d}" for d in details]
    open(os.path.join(args.outdir, "equiv.log"), "w", encoding="utf-8").write(
        "\n".join(report) + "\n")
    print("\n".join(report))
    sys.exit(0 if ok else 2)


if __name__ == "__main__":
    main()
