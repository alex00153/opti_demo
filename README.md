# opti_demo

把一段 Verilog 交给 LLM 优化，并用开源 EDA 工具链自动判定该优化是否可被接受。

```
[1] 基线评分    yosys 综合 -> abc 映射到工艺库 -> 提取面积(µm²) + 逻辑深度(ltp)
[2] LLM 生成    调 llm_agent.py，生成优化后的 RTL
[3] 等价性验证  激励 testbench -> iverilog 仿真 -> VCD 波形逐时刻比对 (PASS 才能进入后续)
[4] 优化评分    对优化后 RTL 重跑 [1]
[5] 汇总报告    输出接受/拒绝结论至 <outdir>/report.md
```

---

## 依赖要求

| 依赖项 | 说明 | 是否必需 |
|---|---|---|
| **Linux (x86_64)** | 运行环境（Ubuntu / Debian 等） | 必需 |
| **yosys** | 综合与面积/深度评分工具 | 必需 |
| **iverilog + vvp** | 等价性验证的仿真器 | 必需 |
| **标准单元库 (.lib)** | abc 映射的目标工艺库（如 Nangate45） | 必需 |
| **Python 3.8+** | 调度脚本（**仅使用标准库，无需 pip 安装任何包**） | 必需 |
| **LLM 服务** | 用于生成优化代码（默认支持 Claude CLI，亦可自定义） | 必需 |

---

## 快速上手（推荐）

通过支持 Shell 执行与文件读写的 Agent 工具，可以全自动完成依赖探测、路径配置与首跑测试。

### 步骤 1：安装你喜欢的 Agent 工具

以 **Claude Code** 为例（任意具备命令执行能力的 Agent 均可，如 Cursor、Cline 等）：

```bash
# 官方安装脚本（推荐）
curl -fsSL https://claude.ai/install.sh | bash

# 或通过 npm 安装（需 Node.js 22+，切勿加 sudo）
npm install -g @anthropic-ai/claude-code
```

配置模型访问密钥（以兼容端点为例，可在 `~/.bashrc` 中导出）：
```bash
export ANTHROPIC_BASE_URL="https://你的端点地址"
export ANTHROPIC_AUTH_TOKEN="sk-你的token"
export ANTHROPIC_MODEL="你的模型名"
```

### 步骤 2：让 Agent 自动部署

在本项目根目录下启动 Agent，并输入：

> **“根据readme.md，帮我部署这个demo”**

Agent 会自动执行：
1. 检查本机 `yosys`、`iverilog`、`python3` 等工具链；
2. 定位或引导下载 Nangate45 标准单元库；
3. 生成本机路径配置文件 `tools.env`；
4. 跑一遍测试用例验证闭环。

**验收标准**：看到类似下表的最终输出即代表环境部署成功：
```
| 指标           | 基线     | 优化后   | 变化     |
| 面积 (µm²)    | 764.218  | 403.256  | -47.2%   |
| 逻辑深度 (ltp) | 19       | 18       | -5.3%    |
| 等价性         | —        | —        | PASS     |
结论：[PASS] 接受：功能等价，面积下降，逻辑深度未恶化
```

---

## 运行方式

### 交互模式（推荐）
```bash
./run_demo.sh
```
按提示选择预置用例（一路直接按回车即以默认案例 `opt_top.v` 运行全流程）。

### 命令行模式
```bash
# 运行指定 RTL 用例
./run_demo.sh --baseline case/bench/mult8/mult8_v1_behavioral.v

# 仅调试用：跳过等价性验证
./run_demo.sh --no-equiv
```

**产物查看**：
- `out/<case>/report.md`：综合与等价性验收报告。
- `out/<case>/optimized.v`：LLM 生成的优化 RTL。
- `work/<case>/equiv/equiv.log`：波形比对细节日志。

---

## 接入自定义模型

demo 默认通过 `claude` CLI 驱动。若想换用任意 OpenAI 兼容模型（DeepSeek、Qwen、本地 Ollama 等），仅需两步：

1. 编辑或创建 `.env`：
   ```bash
   LLM_BACKEND=custom
   LLM_BASE_URL=https://api.deepseek.com
   LLM_API_KEY=sk-xxxx
   LLM_MODEL=deepseek-chat
   ```
2. 在 `llm_agent.py` 的 `call_llm_custom()` 中填入网络请求（内置了免 `pip` 安装的标准库实现）：
   ```python
   def call_llm_custom(prompt: str, cfg: dict) -> str:
       import urllib.request, json
       req = urllib.request.Request(
           cfg["base"].rstrip("/") + "/chat/completions",
           data=json.dumps({
               "model": cfg["model"],
               "messages": [{"role": "user", "content": prompt}],
           }).encode("utf-8"),
           headers={"Authorization": f"Bearer {cfg['key']}", "Content-Type": "application/json"},
       )
       with urllib.request.urlopen(req, timeout=cfg["timeout"]) as resp:
           return json.load(resp)["choices"][0]["message"]["content"]
   ```

---

## 附录 A：手动部署指南（不使用 Agent）

如果不使用 Agent，请按以下步骤手动配置环境：

### 1. 安装基础工具链
在 Debian / Ubuntu 下运行：
```bash
sudo apt update
sudo apt install -y yosys iverilog python3 wget

# 验证安装
yosys -V && iverilog -V && python3 --version
```

### 2. 获取 Nangate45 开源标准单元库
```bash
mkdir -p ~/edatools && cd ~/edatools
wget https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/raw/master/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
```

### 3. 配置 `tools.env`
回到项目根目录，从模板复制并修改配置文件：
```bash
cp tools.env.example tools.env
```
编辑 `tools.env`，填入绝对路径：
```bash
YOSYS_BIN=/usr/bin/yosys
LIB_FILE=/home/<你的用户名>/edatools/NangateOpenCellLibrary_typical.lib
```

### 4. 验证工具链连通性
测试 Yosys 与工艺库能否正常工作：
```bash
YOSYS_BIN=$(sed -n 's/^YOSYS_BIN=//p' tools.env)
LIB_FILE=$(sed -n 's/^LIB_FILE=//p' tools.env)

"$YOSYS_BIN" -p "read_verilog -sv case/rtl/opt_top.v; \
                read_liberty -lib $LIB_FILE; \
                hierarchy -top opt_top; proc; opt; techmap; opt; \
                abc -liberty $LIB_FILE; stat -liberty $LIB_FILE; ltp" 2>&1 \
  | grep -E "Chip area|Longest topological path"
```
若正常打印出 `Chip area` 与 `Longest topological path`，即可运行 `./run_demo.sh`。

---

## 附录 B：常见参数与环境变量

| 参数 / 变量 | 说明 | 默认值 |
|---|---|---|
| `--baseline <file>` | 基线 RTL 路径 | `case/rtl/opt_top.v` |
| `--top <name>` | 顶层模块名 | 自动探测 |
| `--outdir <dir>` | 产物输出路径 | `out/<case_name>` |
| `--equiv-tb <mode>` | 激励源：`file` (预置) / `llm` (LLM生成) / `auto` (自动伪随机) | `file` |
| `--no-equiv` | 跳过等价性检查（仅调试综合时使用） | 关闭 |
| `LLM_BACKEND` | 模型后端：`claude-cli` 或 `custom` | `claude-cli` |
