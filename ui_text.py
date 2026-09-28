#!/usr/bin/env python3
"""ui_text.py —— UI 文案配置（ui_text.json）的加载器。

- Python 侧：import ui_text
              ui_text.get("report.title")
              ui_text.t("log.case_info", baseline=.., top=..)   # 等价于 fill(get(..), ..)
              ui_text.loc()                                    # 调用点 "文件:行号"
- Bash 侧：  eval "$(python3 ui_text.py --shell)"    # 得到 UI_<路径> 变量，如 UI_DEMO_HELP
             （bash 侧占位符替换用 run_demo.sh 里的 fill()）

文案全部集中在 ui_text.json；本文件只是加载器，一般无需改动。

啰嗦模式：环境变量 DEMO_VERBOSE=1（或脚本的 -v/--verbose）时，loc() 生效，
各脚本会在每条消息前附带其来源 file:line，便于定位是哪一行触发了输出。
"""

import json
import os
import re
import shlex
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PATH = os.environ.get("UI_TEXT_FILE", os.path.join(_HERE, "ui_text.json"))

# 啰嗦模式开关（供各脚本决定是否打印 file:line）
VERBOSE = os.environ.get("DEMO_VERBOSE", "0").strip().lower() not in ("", "0", "false", "no", "off")

_cache = None


def loc(depth: int = 2) -> str:
    """返回调用点的 "文件:行号"（啰嗦模式用）。

    depth 是从本函数往上跳的层数：0=loc 自己，1=loc 的直接调用者，2=再上一层……

    各脚本里的 _tag() 用的是 loc(3)：跳过 _tag 自己那层，也跳过 log()/fail()
    那层，正好落到真正发起这条日志的那一行。少跳一层就会永远指向 log() 内部，
    多跳一层就会指到调用者的调用者。
    """
    try:
        frame = sys._getframe(depth)
        return f"{os.path.basename(frame.f_code.co_filename)}:{frame.f_lineno}"
    except Exception:
        return "?"


def load(path: str = None) -> dict:
    """载入（并缓存）文案配置。"""
    global _cache
    if _cache is None:
        with open(path or DEFAULT_PATH, encoding="utf-8") as fh:
            _cache = json.load(fh)
    return _cache


def get(path: str, default: str = "") -> str:
    """按点分路径取文案，如 get("demo.interactive.banner")。"""
    node = load()
    for key in path.split("."):
        if not isinstance(node, dict) or key not in node:
            return default
        node = node[key]
    return node


def fill(template: str, **kw) -> str:
    """把模板中的 {name} 替换为对应值（未提供的占位符保持原样）。"""
    out = str(template)
    for key, val in kw.items():
        out = out.replace("{" + key + "}", str(val))
    return out


def t(path: str, **kw) -> str:
    """取文案并填充占位符：t("demo.case_info", baseline=..., top=..., outdir=...)"""
    return fill(get(path), **kw)


def _flatten(node: dict, prefix: str = ""):
    for key, val in node.items():
        name = f"{prefix}_{key}" if prefix else key
        if isinstance(val, dict):
            yield from _flatten(val, name)
        else:
            yield name, val


def _shell_name(path: str) -> str:
    return "UI_" + re.sub(r"\W", "_", path).upper()


def main():
    args = sys.argv[1:]
    if "--shell" in args:
        for path, val in _flatten(load()):
            print(f"{_shell_name(path)}={shlex.quote(str(val))}")
        return
    if "--get" in args:
        sys.stdout.write(str(get(args[args.index("--get") + 1])))
        return
    print("usage: ui_text.py --shell | --get <dotted.path>", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
