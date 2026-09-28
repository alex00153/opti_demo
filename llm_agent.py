#!/usr/bin/env python3
"""
llm_agent.py —— LLM 生成优化 RTL 的入口（★ 学生主要修改这个文件）

职责（把原先 run_demo.sh 里的 "调用 LLM" 核心逻辑全部搬到这里）：
  1. 解析 LLM 配置：.env -> 环境变量 -> ~/.claude/settings.json
  2. 渲染 prompt 模板（把 {{RTL_SOURCE}} 替换为基线 RTL）
  3. 调用 LLM 得到优化 RTL 文本（按 LLM_BACKEND 分派，见下）
  4. 从响应中提取 ```verilog 代码块，写出到 --out

后端（LLM_BACKEND）：
  claude-cli（默认）  走本机 `claude -p` 无头模式，开箱可用
  custom              不内置任何客户端 —— 留给你自己实现

  demo 只在 claude-cli 这一个后端上给了可用实现，其它模型/厂商请走 custom，
  在 call_llm_custom() 里写你自己的调用（函数 docstring 给了标准库示例）。
  demo 的定位是"把闭环脚手架搭好"，"接哪个模型"是留给你的练习。

用法：
  python3 llm_agent.py \
      --baseline case/bench/mult8/mult8_v2_shiftadd_ripple.v \
      --prompt   prompts/rtl_optimize.md \
      --out      out/mult8/optimized.v \
      --raw      out/mult8/llm_response.md

学生可修改的入口：
  - build_prompt()      ：调整提示词与优化目标（面积/时序权衡等）
  - call_llm_custom()   ：接你自己的模型
  - extract_verilog()   ：适配不同的输出格式
"""

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import threading

import ui_text as ui

_EP = ui.get("prefix.llm")            # [llm_agent]
_EEP = ui.get("prefix.llm_err")       # [llm_agent][ERROR]


def _tag() -> str:
    """啰嗦模式下返回调用点 "文件:行号 > "，否则空串。

    loc(3)：跳过 _tag 和 log()/fail() 两层，落到真正发起日志的那一行。
    """
    return f"{ui.loc(3)} > " if ui.VERBOSE else ""


def log(msg: str, **kw) -> None:
    print(f"{_EP} {_tag()}{ui.fill(msg, **kw)}", file=sys.stderr)


def fail(msg: str, **kw) -> None:
    print(f"{_EEP} {_tag()}{ui.fill(msg, **kw)}", file=sys.stderr)
    sys.exit(1)


# ----------------------------------------------------------------------------
# 1) 配置解析：.env -> 环境变量 -> ~/.claude/settings.json
# ----------------------------------------------------------------------------
PLACEHOLDER_PATTERNS = (
    "your-api-key", "your_api_key", "placeholder",
    "changeme", "replace-me", "todo", "xxx",
)

# ---- 后端 ----------------------------------------------------------------
BACKEND_CLAUDE = "claude-cli"   # 默认：走本机 claude CLI，开箱可用
BACKEND_CUSTOM = "custom"       # 学生自己实现 call_llm_custom()
BACKENDS = (BACKEND_CLAUDE, BACKEND_CUSTOM)
DEFAULT_BACKEND = BACKEND_CLAUDE

# 自定义后端未实现时的退出码：run_demo.sh 认得它，会干净收尾
NOT_IMPLEMENTED_EXIT = 10


def is_placeholder(value: str) -> bool:
    if not value:
        return True
    low = value.lower()
    return any(p in low for p in PLACEHOLDER_PATTERNS)


def load_env_file(path: str) -> dict:
    """解析 KEY=VALUE 形式的 .env（跳过注释/空行）。"""
    env = {}
    if not os.path.isfile(path):
        return env
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\r\n")
            if not line or line.lstrip().startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            env[key.strip()] = val
    return env


def settings_env(key: str) -> str:
    """读取 ~/.claude/settings.json 中 env.<key>。"""
    path = os.path.expanduser("~/.claude/settings.json")
    try:
        with open(path, encoding="utf-8") as fh:
            return (json.load(fh).get("env", {}) or {}).get(key, "") or ""
    except Exception:
        return ""


def resolve_config(env_file: str, backend: str = "") -> dict:
    """解析 LLM 配置，返回 cfg dict（backend/key/base/model/key_source）。

    取值优先级（逐项独立判断）：.env > 环境变量 > ~/.claude/settings.json
    backend 参数非空时优先于以上三者（给 --backend 命令行开关用）。

    只有内置的 claude-cli 后端才强制要求 key/base 配齐；custom 后端下这几项
    只是"顺手解析出来的待填信息"，缺了也不报错 —— 你自己的实现想用什么就用什么。
    """
    dotenv = load_env_file(env_file)

    # --- backend ---
    backend = (backend or dotenv.get("LLM_BACKEND", "")
               or os.environ.get("LLM_BACKEND", "")
               or DEFAULT_BACKEND).strip() or DEFAULT_BACKEND
    if backend not in BACKENDS:
        fail(ui.get("llm.err_backend"), backend=backend, known="/".join(BACKENDS))

    # --- 凭据：.env 里叫 LLM_API_KEY；环境变量/settings 里叫 ANTHROPIC_AUTH_TOKEN ---
    key = dotenv.get("LLM_API_KEY", "")
    source = ui.get("llm.src_dotenv")
    if is_placeholder(key):
        key = os.environ.get("ANTHROPIC_AUTH_TOKEN", "")
        source = ui.get("llm.src_env")
    if is_placeholder(key):
        key = settings_env("ANTHROPIC_AUTH_TOKEN")
        source = ui.get("llm.src_settings")
    key = "" if is_placeholder(key) else key

    # --- base_url（claude CLI 会自行追加 /v1/messages，需去掉尾部 /v1）---
    base = (dotenv.get("LLM_BASE_URL", "")
            or os.environ.get("ANTHROPIC_BASE_URL", "")
            or settings_env("ANTHROPIC_BASE_URL"))
    base = ("" if is_placeholder(base) else base).rstrip("/")
    if base.endswith("/v1"):
        base = base[:-3]

    # --- model（留空 = 交给后端自己决定，claude CLI 会用自己的默认模型）---
    model = (dotenv.get("LLM_MODEL", "")
             or os.environ.get("ANTHROPIC_MODEL", "")
             or settings_env("ANTHROPIC_MODEL"))
    model = "" if is_placeholder(model) else model.strip()

    # 只有内置后端才强制校验，避免 custom 后端被"没配 key"挡住
    if backend == BACKEND_CLAUDE:
        if not key:
            fail(ui.get("llm.err_key"))
        if not base:
            fail(ui.get("llm.err_base_url"))

    return {"backend": backend, "key": key, "base": base,
            "model": model, "key_source": source}


# ============================================================================
# ★★★ 学生修改区 ★★★
#   build_prompt()        —— 调整提示词与优化目标
#   call_llm_custom()     —— 接你自己的模型（BACKEND_CUSTOM 时走这里）
#   extract_verilog()     —— 适配不同的输出格式
# ============================================================================

def build_prompt(template: str, rtl_source: str) -> str:
    """把基线 RTL 填入 prompt 模板。可在此追加/修改优化目标。"""
    if "{{RTL_SOURCE}}" not in template:
        fail(ui.get("llm.err_prompt_ph"))
    return template.replace("{{RTL_SOURCE}}", rtl_source)


def call_llm(prompt: str, cfg: dict) -> str:
    """按 cfg["backend"] 分派到具体实现。返回 LLM 的文本响应。"""
    if cfg.get("backend") == BACKEND_CUSTOM:
        return call_llm_custom(prompt, cfg)
    return call_llm_claude_cli(prompt, cfg)


def call_llm_claude_cli(prompt: str, cfg: dict) -> str:
    """
    内置实现：本机 `claude -p` 无头模式，并把 claude 的原始输出**逐行实时**
    回显到 stderr（`|` 前缀），便于观察进度。

    这是 demo 唯一开箱可用的后端。想换模型请走 BACKEND_CUSTOM。
    """
    env = os.environ.copy()
    # 若在 Claude Code 会话内运行，需剥离嵌套标记，否则 claude 拒绝启动
    for marker in ("CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT"):
        env.pop(marker, None)
    env["ANTHROPIC_AUTH_TOKEN"] = cfg["key"]
    env["ANTHROPIC_BASE_URL"] = cfg["base"]
    env["ANTHROPIC_MODEL"] = cfg["model"]

    cmd = [
        "claude", "-p", prompt,
        "--output-format", "text",
        "--tools", "",
        "--disable-slash-commands",
        "--no-session-persistence",
    ]
    if cfg.get("model"):
        cmd[3:3] = ["--model", cfg["model"]]   # 没配就让 claude 用自己的默认模型
    if ui.VERBOSE:
        log(ui.get("llm.cmd"), cmd=" ".join(shlex.quote(c) for c in cmd))
    log(ui.get("llm.stream_start"), model=cfg["model"])

    timeout = cfg.get("timeout", 300)
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, bufsize=1, env=env)
    except FileNotFoundError:
        fail(ui.get("llm.err_claude"))

    # 到点强杀，避免 claude 挂起时无限等待
    timed_out = {"hit": False}

    def _kill():
        timed_out["hit"] = True
        try:
            proc.kill()
        except Exception:  # noqa: BLE001
            pass

    timer = threading.Timer(timeout, _kill)
    timer.start()
    chunks = []
    try:
        for line in proc.stdout:          # 逐行实时回显 claude 原始输出
            sys.stderr.write(f"{_EP} | {line}")
            sys.stderr.flush()
            chunks.append(line)
    finally:
        timer.cancel()
    stderr = proc.stderr.read()
    proc.wait()

    if timed_out["hit"]:
        fail(ui.get("llm.err_timeout") + f" (>{timeout}s)")
    if proc.returncode != 0:
        fail(ui.get("llm.err_call_failed"), code=proc.returncode, stderr=stderr[:400])
    log(ui.get("llm.stream_end"), n=len(chunks))
    return "".join(chunks)


def call_llm_custom(prompt: str, cfg: dict) -> str:
    """★ 学生实现区：接你自己的模型（demo 不内置任何第三方客户端）。

    默认实现只打印一句提示就退出（退出码 NOT_IMPLEMENTED_EXIT），
    run_demo.sh 认得这个码，会干净收尾。

    换成你自己的实现时，删掉下面两行，返回 LLM 的文本响应即可 ——
    响应里要有 ```verilog 代码块，extract_verilog() 会去提取。

    用标准库发 HTTP 请求的例子（OpenAI 兼容端点，DeepSeek / 通义 / GLM /
    Kimi / Ollama / vLLM 都适用；纯标准库）：

        import urllib.request
        req = urllib.request.Request(
            cfg["base"].rstrip("/") + "/chat/completions",
            data=json.dumps({
                "model": cfg["model"],
                "messages": [{"role": "user", "content": prompt}],
            }).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {cfg['key']}",
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=cfg["timeout"]) as resp:
            return json.load(resp)["choices"][0]["message"]["content"]

    换成 Anthropic 消息格式的端点，就把 url 改成 cfg["base"] + "/v1/messages"、
    把 Authorization 换成 x-api-key、请求体换成
    {"model":.., "max_tokens":.., "messages":[..]}，
    再从返回值里取 content[0]["text"]。

    cfg 里已经解析好了 backend / key / base / model / timeout
    （取值优先级 .env > 环境变量 > ~/.claude/settings.json），直接用即可。
    """
    log(ui.get("llm.custom_stub"))
    sys.exit(NOT_IMPLEMENTED_EXIT)


def extract_verilog(text: str, top: str) -> str:
    """从 LLM 响应中提取 Verilog 源码（取最后一个代码块，缺省用全文）。"""
    blocks = re.findall(r"```(?:verilog|systemverilog|v)?\s*\n(.*?)```", text, re.S)
    src = (blocks[-1] if blocks else text).strip()
    if "module " not in src:
        fail(ui.get("llm.err_no_verilog"))
    if top and not re.search(r"\bmodule\s+" + re.escape(top) + r"\b", src):
        fail(ui.get("llm.err_top"), top=top)
    return src

# ============================================================================
# 学生修改区结束
# ============================================================================


def main():
    ap = argparse.ArgumentParser(description=ui.get("llm.cli.description"))
    ap.add_argument("--baseline", required=True, help=ui.get("llm.cli.baseline"))
    ap.add_argument("--prompt", required=True, help=ui.get("llm.cli.prompt"))
    ap.add_argument("--out", required=True, help=ui.get("llm.cli.out"))
    ap.add_argument("--raw", help=ui.get("llm.cli.raw"))
    ap.add_argument("--top", default="", help=ui.get("llm.cli.top"))
    ap.add_argument("--env-file", default=".env", help=ui.get("llm.cli.env_file"))
    ap.add_argument("--backend", default="", choices=["", BACKEND_CLAUDE, BACKEND_CUSTOM],
                    help=ui.get("llm.cli.backend"))
    ap.add_argument("--timeout", type=int, default=300, help=ui.get("llm.cli.timeout"))
    args = ap.parse_args()

    cfg = resolve_config(args.env_file, backend=args.backend)
    cfg["timeout"] = args.timeout

    masked = cfg["key"][:4] + "****" if cfg["key"] else ui.get("llm.key_unset")
    log(ui.get("llm.backend"), backend=cfg["backend"])
    log(ui.get("llm.endpoint"), base=cfg["base"] or "-",
        model=cfg["model"] or "-", key=masked, source=cfg["key_source"])

    rtl = open(args.baseline, encoding="utf-8").read()
    template = open(args.prompt, encoding="utf-8").read()
    prompt = build_prompt(template, rtl)
    response = call_llm(prompt, cfg)

    if args.raw:
        os.makedirs(os.path.dirname(os.path.abspath(args.raw)), exist_ok=True)
        open(args.raw, "w", encoding="utf-8").write(response)

    optimized = extract_verilog(response, args.top)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    open(args.out, "w", encoding="utf-8").write(optimized + "\n")
    log(ui.get("llm.written"), out=args.out)


if __name__ == "__main__":
    main()
