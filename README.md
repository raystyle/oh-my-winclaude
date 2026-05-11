# Oh My Claude

为 Claude Code 构建和管理开发与智能体操作环境的工具集。通过 `omc` CLI 统一安装、更新和版本锁定 CLI 工具与开发运行时，内置中国网络友好的下载回退机制。

## 快速开始

```powershell
# 1. 克隆仓库
git clone <repo-url> D:\ohmyclaude
cd D:\ohmyclaude

# 2. 首次引导（设置 PATH、prefix、GitHub hosts 加速）
.\.scripts\init.ps1

# 3. 安装所有工具
.\omc.exe install
```

安装完成后，所有工具的可执行文件已加入用户 PATH。重启终端或打开新的 PowerShell 窗口即可使用。

## 前置要求

- Windows 10/11
- PowerShell 5.1（系统自带）
- 网络连接（GitHub，支持通过 hosts 配置国内加速）

## 命令

```powershell
omc                        # 显示帮助和状态
omc init                   # 首次引导（prefix、PATH、hosts）
omc check [工具|分组]       # 显示安装状态、锁定版本、缓存
omc install [工具|分组]     # 安装锁定版本（已安装则跳过）
omc update [工具|分组]      # 获取最新版并升级
omc uninstall [工具|分组]   # 卸载工具（保留锁定和缓存）
omc download <工具> <版本>  # 下载指定版本到缓存（不安装）
omc lock <工具> [版本]      # 查看/锁定版本
omc setup claude           # 配置 Claude Code（GUI 编辑器）
omc switch claude          # 切换 Claude Code 配置 Profile
omc hack claude            # 插件市场管理器（GUI）
omc help                   # 显示用法
```

**分组：** `base`、`tool`、`dev`

## 工具注册表

### 基础脚本（Base Scripts）

omc 依赖的引导级工具，独立脚本，通过 dot-source 调度。

| 工具 | 说明 |
|------|------|
| uv | Python 包管理器和 Python 版本管理 |
| claude | Claude Code CLI（通过 uv 安装，`omc setup claude` 配置，`omc switch claude` 切换 Profile，`omc hack claude` 插件市场） |

### 基础工具（Base Tools）

数据驱动工具，安装到 `.envs\base\bin`。

| 工具 | 说明 |
|------|------|
| 7z | 7-Zip 压缩工具 |
| git | Git for Windows（便携版） |
| gh | GitHub CLI |
| aria2 | 多线程下载工具 |

### 工具（Tools）

数据驱动工具和独立脚本，安装到 `.envs\tools\bin`。

| 工具 | 说明 |
|------|------|
| ripgrep | 快速递归搜索（`rg`） |
| jq | JSON 处理器 |
| yq | YAML 处理器 |
| fzf | 模糊查找器 |
| just | 任务运行器 |
| starship | 跨 Shell 提示符 |
| mq | 基于 mq lang 的 Markdown 命令行操作工具（主程序 + mq-lsp + mq-check） |
| rumdl | Markdown lint/format 工具 |
| nushell | Nushell fork（nushell-evo），含 MCP 日志和 browse 插件 |
| conclaude | Claude Code 会话 guardrail 工具，通过 hook 系统 enforce linting、测试、格式化及文件保护规则 |
| bun | JavaScript 运行时、打包器、测试运行器和包管理器（npmmirror 镜像源） |
| duckdb | DuckDB CLI（独立脚本） |

### 开发工具（Dev Tools）

非标准安装流程的独立脚本。

| 工具 | 说明 |
|------|------|
| node | Node.js（USTC 镜像） |
| dotnet | .NET SDK（aria2c 多线程下载，默认 LTS） |
| rust | Rust（rustup，rsproxy.cn 镜像） |
| font | Nerd Font 安装器（0xProto） |
| pwsh | PowerShell 7（GitHub Releases） |
| pses | PowerShellEditorServices（GitHub Releases） |
| jupyter | Jupyter（通过 `uv tool install`） |
| biome | Biome JS/TS linter & formatter（npm + shim exe） |
| tslsp | TypeScript LSP（npm + shim exe） |
| vsbuild | VS Build Tools（离线布局） |

### PS 模块（PS Modules）

从本地离线仓库管理的 PowerShell 模块。

| 模块 | 说明 |
|------|------|
| PSScriptAnalyzer | PowerShell 代码检查 |
| PSFzf | PowerShell fzf 集成 |
| Pester | 测试框架 |

## 目录结构

```
ohmyclaude/
├── omc.exe                  # 入口（编译的 Rust 二进制）
├── omc.shim                 # Shim 配置 -> powershell.exe -File .scripts/omc.ps1
├── CLAUDE.md                # 项目文档（Claude Code 指引）
├── README.md
├── .gitignore
├── .scripts/
│   ├── omc.ps1              # 统一入口，工具注册，调度分发
│   ├── init.ps1             # 首次引导
│   ├── helpers.ps1          # 共享工具函数（下载、哈希、PATH、shim）
│   ├── core.ps1             # 数据驱动工具的生命周期引擎
│   ├── base/                # 基础脚本（uv.ps1, claude.ps1）+ 基础工具定义
│   ├── tools/               # 数据驱动工具定义（$ToolDefs）+ 独立脚本
│   └── dev/                 # 开发工具安装器 + PS 模块管理（profile-line.ps1, psmodule.ps1）
├── tests/
│   ├── tests.psd1           # Pester 配置
│   ├── Helpers/             # 共享测试基础设施
│   ├── Unit/                # 单元测试（135 tests）
│   └── Integration/         # 集成测试（41 tests）
├── .config/
│   └── starship/
│       └── starship.toml    # 预置的 starship 提示符配置
├── .knowledge/              # PowerShell 编码风格参考和工具开发指南
└── (运行时自动生成)
    ├── .envs/               # 已安装的二进制和运行时
    ├── .cache/              # 下载缓存
    └── .config/*/config.json  # 各工具的锁定/版本配置（自动生成）
```

## 常用工作流

```powershell
# 查看安装状态和锁定版本
omc check

# 安装所有工具（base + tool + dev）
omc install

# 按分组安装
omc install base
omc install tool
omc install dev

# 更新所有工具到最新版
omc update

# 更新单个工具
omc update ripgrep

# 锁定工具到指定版本
omc lock ripgrep 15.0.0

# 下载指定版本到缓存（不安装）
omc download ripgrep 14.1.0

# 卸载工具（锁定和缓存保留）
omc uninstall duckdb

# 配置 Claude Code（打开 GUI 编辑器）
omc setup claude

# 切换 Claude Code 配置 Profile（GLM / DeepSeek 等）
omc switch claude
```

## Claude Code 配置 Profile

支持多个 API 提供商配置的一键切换。内置 GLM 和 DeepSeek 两个预设 Profile，也可通过 `omc setup claude` 保存自定义 Profile。

| Profile | 模型 | 1M 上下文 | Thinking |
|---------|------|-----------|----------|
| GLM | glm-4.5-air / glm-5-turbo / glm-5.1 | 禁用 | 禁用 |
| DeepSeek | deepseek-v4-flash / deepseek-v4-pro[1m] | 启用 | 启用 |

```powershell
# 交互式切换 Profile（WinForms 对话框）
omc switch claude

# 配置后保存为新 Profile
omc setup claude
```

Profile 存储在 `.config/claude/profiles/` 目录。切换仅覆盖 Provider 相关配置（API 凭证、模型、1M/thinking 开关），通用偏好（viewMode、permissions、telemetry 等）不受影响。

## 添加新工具

### 数据驱动工具（简单 GitHub Release）

1. 创建 `.scripts/tools/<name>.ps1`，返回工具定义哈希表：

```powershell
return @{
    ToolName       = 'mytool'
    ExeName        = 'mytool.exe'
    Source         = 'github-release'
    Repo           = 'owner/mytool'
    GetArchiveName = { param($v) "mytool-$v-x86_64-windows.zip" }
    ExtractType    = 'standalone'
    GetSetupDir    = { param($r) "$r\.config\mytool" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = '--version'
    VersionPattern = '(\d+\.\d+\.\d+)'
}
```

2. 在 `.scripts/omc.ps1` 的 `$ToolDefs` 数组中添加 `'mytool'`。

### 独立工具脚本（自定义逻辑）

1. 创建 `.scripts/tools/<name>.ps1`，包含 `param()` 和命令处理（check/install/update/uninstall/download）。
2. 在 `.scripts/omc.ps1` 的 `$ToolScripts` 数组中添加 `'mytool'`。

### 开发工具

1. 创建 `.scripts/dev/<name>.ps1`，包含 check/install/update/uninstall/download 命令。
2. 在 `.scripts/omc.ps1` 的 `$DevTools` 哈希表中添加条目。

## 下载策略

所有下载遵循回退链以适应中国网络环境：

1. **gh CLI**（已认证，无限速）— `Save-GitHubReleaseAsset`
2. **直连 URL** — `Invoke-WebRequest`

验证链：GitHub attestation（加密签名）→ SHA256 digest → checksums.txt 回退。

## 配置文件

各工具的配置文件位于 `.config/<tool>/config.json`，在安装时**自动生成**，存储：

- `prefix` — 项目根路径
- `lock` — 锁定版本
- `sha256` — 校验哈希
- `asset` — 缓存归档文件名

唯一预置的配置是 `.config/starship/starship.toml`，在 starship 安装时复制到 `~/.config/starship.toml`。

## 测试

项目使用 Pester v5 进行测试（PS 5.1 兼容），覆盖 `helpers.ps1` 和 `core.ps1` 中的所有函数。

```powershell
# 运行全部测试
Invoke-Pester -Path .\tests

# 只运行单元测试
Invoke-Pester -Path .\tests\Unit

# 带代码覆盖率
Invoke-Pester -Path .\tests -CodeCoverage .scripts\helpers.ps1,.scripts\core.ps1
```

| 类型 | 数量 | 说明 |
|------|------|------|
| Unit | 135 | 纯函数、配置读写、验证过滤、文件操作 |
| Integration | 41 | 生命周期、下载、安装、卸载、模块管理 |

测试不依赖真实网络或安装——所有外部依赖通过 Mock 隔离。

## 许可证

MIT
