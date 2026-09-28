#!/usr/bin/env python3
"""tools.py —— 本机工具路径解析（tools.env > 环境变量 > 默认值）。

发布包里只带 tools.env.example；把实际路径填进同目录的 tools.env 即可。
用环境变量 TOOLS_ENV 可指向别的配置文件。
"""

import os

_HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_ENV = os.environ.get("TOOLS_ENV", os.path.join(_HERE, "tools.env"))


def load(path: str = None) -> dict:
    """解析 KEY=VALUE 形式的 tools.env（跳过注释/空行）。"""
    env = {}
    p = path or TOOLS_ENV
    if not os.path.isfile(p):
        return env
    with open(p, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            env[key.strip()] = val.strip()
    return env


def get(key: str, default: str = "") -> str:
    """tools.env 里有就优先用，否则回退到环境变量，再否则 default。"""
    val = load().get(key, "")
    if val:
        return val
    return os.environ.get(key, default)
