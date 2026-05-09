# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在本仓库中工作时提供指引。

## 项目概述

**Oh My Claude** 是一个为 Claude Code 构建和管理开发与智能体操作环境的工具集。它提供 `omc`，一个统一 CLI，用于安装、更新和版本锁定 CLI 工具（ripgrep、fzf、just、gh、duckdb 等）与开发运行时（Node.js、Rust、Jupyter、VS Build Tools 等），内置中国网络友好的下载回退机制（gh CLI 优先，直连 URL 回退）。

主入口 `omc` 是编译的 Rust 二进制（`omc.exe`），配合 PowerShell 包装器（`.scripts/omc.ps1`）。执行流程：`omc.exe` -> `omc.shim` -> `powershell.exe -NoLogo -NoProfile -File .scripts\omc.ps1`。

## 命令

```powershell
omc                        # 显示帮助和状态（默认）
omc init                   # 首次引导（prefix、PATH、hosts）
omc check [工具|分组]       # 显示安装状态、锁定版本、缓存
omc install [工具|分组]     # 安装锁定版本（已安装则跳过）
omc update [工具|分组]      # 获取最新版并升级
omc uninstall [工具|分组]   # 卸载工具（保留锁定和缓存）
omc download <工具> <版本>  # 下载指定版本到缓存
omc lock <工具> [版本]      # 查看/锁定版本
omc setup claude           # 配置 Claude Code（GUI 编辑器）
omc help                   # 显示用法

分组：base、tool、dev
```

运行 `omc`（无参数）或 `omc help` 查看所有已注册工具。

## 架构

```
omc.exe                  # Rust 二进制（薄包装）
omc.shim                 # Shim 配置 -> powershell.exe -File .scripts/omc.ps1
.scripts/
  omc.ps1                # 统一入口，工具注册，调度分发
  init.ps1               # 首次引导（设置执行策略，运行 omc init）
  helpers.ps1            # 共享工具函数：Save-WithCache, Save-GitHubReleaseAsset,
                         #   Get-GitHubRelease, Test-FileHash, Install-ShimExe, PATH 管理
  core.ps1               # 数据驱动工具的生命周期引擎（$BaseTools + $ToolDefs）
  base/                  # 基础脚本（uv.ps1, claude.ps1）+ 基础工具定义（7z.ps1, git.ps1, gh.ps1）
  tools/                 # 数据驱动哈希表（$ToolDefs）+ 独立脚本（$ToolScripts）
  dev/                   # 开发工具安装器 + PS 模块管理
                         #   工具库：profile-line.ps1, psmodule.ps1（库文件，非工具）
                         #   profile-line.ps1 支持 BEGIN/END ohmywinclaude markers 幂等写入
```

## 工具注册表

`.scripts/omc.ps1` 中所有已注册工具：

```powershell
$BaseScripts = @('uv', 'claude')           # 独立引导脚本

$BaseTools = @('7z', 'git', 'gh', 'aria2')    # 数据驱动，.envs\base\bin

$ToolDefs = @(                               # 数据驱动，.envs\tools\bin
    'ripgrep', 'jq', 'yq', 'fzf',
    'mq', 'just', 'starship', 'rumdl', 'nushell', 'conclaude', 'bun'
)

$ToolScripts = @('duckdb')                  # 独立脚本

$Tools = $ToolDefs + $ToolScripts           # 合并用于显示/分组

$DevTools = @{                               # 独立脚本
    dotnet  = 'dotnet.ps1'
    node    = 'node.ps1'
    rust    = 'rust.ps1'
    font    = 'font.ps1'
    pwsh    = 'powershell.ps1'
    pses    = 'pses.ps1'
    jupyter = 'jupyter.ps1'
    biome   = 'biome.ps1'
    tslsp   = 'tslsp.ps1'
    vsbuild = 'vsbuildtools.ps1'
}

$PsModules = @{                               # 通过 psanalyzer.ps1 管理
    psanalyzer = 'PSScriptAnalyzer'
    psfzf      = 'PSFzf'
    pester     = 'Pester'
}
```

## 工具分类

### 基础脚本（`$BaseScripts`）— `.scripts/base/*.ps1`

omc 在引导早期依赖的引导级工具。独立脚本，自行管理配置和缓存，通过 dot-source 调度。

- **uv** — Python 包管理器和 Python 版本管理，默认安装 Python + ruff + ty，并将 Python Scripts 目录加入 PATH
- **claude** — Claude Code CLI 安装器（通过 uv 从 Python 包提取），含配置系统（`omc setup claude` 打开 WinForms GUI 编辑器）

#### Claude Code 配置系统

`claude.ps1` 内置配置系统，管理 Claude Code 运行所需的环境变量。配置分为两类：

**幂等环境变量**（`install`/`update`/`setup` 时自动设置，无需交互）：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `API_TIMEOUT_MS` | `3000000` | API 请求超时 |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1` | 禁用非必要网络流量 |
| `ENABLE_LSP_TOOL` | `1` | 启用 LSP 代码智能 |
| `CLAUDE_CODE_USE_POWERSHELL_TOOL` | `1` | Windows 上使用 PowerShell |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `1` | 启用实验性 Agent Teams |
| `CLAUDE_CODE_GIT_BASH_PATH` | (动态) | Git Bash 路径 |
| `BASH_DEFAULT_TIMEOUT_MS` | `300000` | Bash 默认超时 |
| `BASH_MAX_TIMEOUT_MS` | `600000` | Bash 最大超时 |
| `DISABLE_TELEMETRY` | `1` | 禁用遥测 |
| `DISABLE_AUTOUPDATER` | `1` | 禁用自动更新 |
| `DISABLE_AUTO_COMPACT` | `1` | 禁用自动上下文压缩 |
| `DISABLE_FEEDBACK_SURVEY` | `1` | 禁用反馈调查 |
| `CLAUDE_CODE_DISABLE_1M_CONTEXT` | `1` | 禁用 1M 上下文窗口 |
| `MCP_TIMEOUT` | `60000` | MCP 服务器超时 |
| `PYTHONUTF8` | `1` | Python UTF-8 模式 |
| `PYTHONIOENCODING` | `utf-8` | Python 编码 |
| `LANG` | `en_US.UTF-8` | 区域设置 |
| `LC_ALL` | `en_US.UTF-8` | 区域覆盖 |

**交互配置项**（通过 `omc setup claude` 的 GUI 编辑器修改）：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ANTHROPIC_AUTH_TOKEN` | (必填) | API 认证令牌 |
| `ANTHROPIC_BASE_URL` | `https://open.bigmodel.cn/api/anthropic` | API 基础 URL |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `glm-4.5-air` | Haiku 模型 |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `glm-5-turbo` | Sonnet 模型 |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `glm-5.1` | Opus 模型 |

配置存储在用户环境变量（`[Environment]::SetEnvironmentVariable(..., "User")`）中。`omc setup claude` 流程：已配置时提供 (K)eep / (R)eplace 选项，未配置时直接打开 GUI 编辑器。

**settings.json 配置**（`install`/`update`/`setup` 时自动设置，幂等合并到 `~/.claude/settings.json`）：

| 设置项 | 默认值 | 说明 |
|--------|--------|------|
| `showThinkingSummaries` | `true` | 显示 thinking 摘要 |
| `viewMode` | `verbose` | 详细输出模式 |
| `alwaysThinkingEnabled` | `true` | 始终启用思考模式 |
| `effortLevel` | `high` | 推理努力级别 |
| `autoMemoryEnabled` | `true` | 自动记忆功能 |

`Set-ClaudeSettings` 函数读取现有 settings.json，合并默认值，不覆盖用户手动添加的其他字段。

### 基础工具（`$BaseTools`）— `.scripts/base/*.ps1`

数据驱动工具，返回哈希表。通过 `Invoke-BaseTool` -> `Import-ToolDefinition` -> `core.ps1` 生命周期引擎调度。安装到 `.envs\base\bin`。

- **7z** — 7-Zip（`ExtractType = '7z-sfx'`，`CacheCategory = 'base'`）
- **git** — Git for Windows（`ExtractType = '7z-sfx'`，`GetArchiveName` 硬编码归档名，PostInstall 写入 `.bashrc`（BEGIN/END markers 幂等））
- **gh** — GitHub CLI（`CacheCategory = 'base'`）
- **aria2** — 多线程下载工具（`ExtractType = 'standalone'`，`CacheCategory = 'base'`，`TagPrefix = 'release-'`）

### 工具定义（`$ToolDefs`）— `.scripts/tools/*.ps1`

数据驱动工具，返回哈希表。与 `$BaseTools` 使用相同的生命周期引擎，但安装到 `.envs\tools\bin`。每个文件返回工具定义：

```powershell
# 示例：.scripts/tools/just.ps1
return @{
    ToolName       = 'just'
    ExeName        = 'just.exe'
    Source         = 'github-release'
    Repo           = 'casey/just'
    GetArchiveName = { param($v) "just-$v-x86_64-pc-windows-msvc.zip" }
    ExtractType    = 'standalone'
    GetSetupDir    = { param($r) "$r\.config\just" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = '--version'
    VersionPattern = '(\d+\.\d+\.\d+)'
}
```

必填字段：`ToolName`、`ExeName`、`Source`、`ExtractType`、`GetSetupDir`、`GetBinDir`。可选：`GetArchiveName`（省略则通过 `AssetNamePattern`/`AssetPlatform`/`AssetArch` 自动发现）、`Repo`、`PostInstall`、`PreUninstall`、`ExtraFiles`、`TagPrefix`、`CacheCategory`、`DisplayName`、`GetInstallDir` 等。

- **ripgrep** — 快速搜索（`rg.exe`）
- **jq** — JSON 处理器
- **yq** — YAML 处理器
- **fzf** — 模糊查找器
- **just** — 任务运行器
- **starship** — 跨 Shell 提示符（含 `PostInstall` 写入 profile）
- **mq** — 基于 mq lang 的 Markdown 命令行操作工具（主程序 + mq-lsp + mq-check，通过 `ExtraFiles`）
- **rumdl** — Markdown lint/format 工具
- **nushell** — Nushell fork（nushell-evo），含 MCP 日志和 browse 插件（`KeepFiles` 提取 `nu_plugin_*.exe`，`PostInstall` 注册插件，`PreUninstall` 清理插件）
- **conclaude** — Claude Code 会话 guardrail 工具，通过 hook 系统 enforce linting、测试、格式化及文件保护规则
- **bun** — JavaScript 运行时、打包器、测试运行器和包管理器（`TagPrefix = 'bun-v'`，`GetArchiveName` 固定 `bun-windows-x64.zip`，`PostInstall` 设置 `BUN_INSTALL`/`BUN_INSTALL_CACHE_DIR`/`BUN_RUNTIME_TRANSPILER_CACHE_PATH` 环境变量并将 `$BUN_INSTALL\bin` 加入 PATH，`PostUninstall` 清理环境变量、缓存和安装目录）

### 工具脚本（`$ToolScripts`）— `.scripts/tools/*.ps1`

独立脚本，自行定义 `param()` 块和命令处理（check/install/update/uninstall/download）。非数据驱动——自行管理生命周期。

- **duckdb** — DuckDB CLI（安装到 `.envs\tools\duckdb/`，自有版本锁定，`ext` 子命令管理扩展）

### 开发工具（`$DevTools`）— `.scripts/dev/*.ps1`

独立脚本，面向安装逻辑复杂的工具，自行处理命令分发。通过 `Invoke-DevTool` 调度。

- **node** — Node.js（USTC 镜像下载，版本锁定）
- **dotnet** — .NET SDK（aria2c 多线程下载官方 SDK zip，缓存到 `.cache/dev/dotnet/`，版本锁优先，默认 Channel LTS）
- **rust** — Rust（通过 rustup，rsproxy.cn 镜像）
- **font** — Nerd Font 安装器（注册表方式，VSCode 配置）
- **pwsh** — PowerShell 7（GitHub Releases，MSI，attestation 验证）
- **pses** — PowerShellEditorServices（GitHub Releases，zip 解压，注册 PSModulePath（含 Documents 路径保护））
- **jupyter** — Jupyter（通过 `uv tool install`）
- **biome** — Biome JS/TS linter & formatter（通过 `npm install -g` 安装 `@biomejs/biome`，复制 omc.exe 创建 shim exe）
- **tslsp** — TypeScript LSP（通过 `npm install -g` 安装 typescript-language-server + typescript，复制 omc.exe 创建 shim exe 指向 `node.exe cli.mjs`）
- **vsbuild** — VS Build Tools（离线布局，管理员提升）

### PS 模块（`$PsModules`）

通过 `psanalyzer.ps1` 使用 `Register-PSRepository` + `Install-Module` 从本地离线仓库（`.cache/dev/LocalRepo/`）管理的 PowerShell 模块。

- **psanalyzer** — PSScriptAnalyzer
- **psfzf** — PSFzf（含 PowerShell profile 块，模块存在性守卫）
- **pester** — Pester（测试框架）

### 关键目录

- `.config/<tool>/config.json` — 各工具的配置和锁定文件（所有工具：base、tools、dev）
- `.config/omc/config.json` — omc 全局配置（prefix）
- `.config/` — dotfile 配置（starship.toml、psmux）
- `.cache/base/<tool>/` — 基础工具缓存（gh、git、hosts、uv、claude）
- `.cache/tools/<tool>/` — 工具缓存（ripgrep、jq、fzf、mq 等）
- `.cache/dev/<tool>/` — 开发工具缓存（node、git、duckdb、dotnet、rustup、pwsh、pses 等）
- `.cache/dev/LocalRepo/` — 本地 PSRepository（`Install-Module` 用的 `.nupkg` 文件）
- `.envs/base/bin/` — 引导可执行文件（7z.exe、git.exe、gh.exe、aria2c.exe）
- `.envs/tools/bin/` — 工具可执行文件（rg.exe、jq.exe、fzf.exe、bun.exe 等）
- `.envs/tools/bun/` — Bun 全局安装目录（`BUN_INSTALL`，通过 bun install -g 安装的包）
- `.envs/tools/bun/bin/` — Bun 全局包可执行文件（加入 PATH）
- `.cache/tools/bun/install/` — Bun 全局包缓存（`BUN_INSTALL_CACHE_DIR`）
- `.cache/tools/bun/transpiler/` — Bun 转译器缓存（`BUN_RUNTIME_TRANSPILER_CACHE_PATH`）
- `.envs/tools/duckdb/` — DuckDB 安装目录
- `.envs/dev/bin/` — 开发工具 shim 可执行文件（加入用户 PATH）
- `.envs/dev/<tool>/` — 开发工具安装目录（node/、git/、duckdb/、dotnet/、.rustup/、pses/ 等）

### 下载策略

数据驱动工具使用 `core.ps1` 生命周期：
- 下载链：`Save-GitHubReleaseAsset`（gh CLI）-> `Invoke-WebRequest`（直连 URL）
- 验证：`Test-GitHubAssetAttestation`（加密签名）-> `Test-FileHash`（SHA256，通过 GitHub digest 或 checksums.txt）
- 缓存：按工具存放在 `.cache/<category>/<tool>/`，SHA256 存入 `.config/<tool>/config.json`

开发工具和基础脚本使用 `helpers.ps1` 中的 `Save-WithCache`（支持 gh CLI GitHub release 下载和直连 URL 下载，带本地缓存）。

为适应中国网络环境，所有下载路径实现回退：gh CLI（已认证、无限速）-> 直连 URL。

### 添加新的数据驱动工具

1. 创建 `.scripts/tools/<name>.ps1`，返回工具定义哈希表
2. 在 `omc.ps1` 的 `$ToolDefs` 数组中添加工具名
3. 设置 `GetBinDir` 返回 `.envs\tools\bin`；仅基础层工具（`$BaseTools` 中的）设置 `CacheCategory = 'base'`

### 添加新的独立工具脚本

1. 创建 `.scripts/tools/<name>.ps1`，包含 `param()` 和命令处理（check/install/update/uninstall/download）
2. 在 `omc.ps1` 的 `$ToolScripts` 数组中添加工具名

### 添加新的开发工具

1. 创建 `.scripts/dev/<name>.ps1`，包含 check/install/update/uninstall/download 命令
2. 在 `omc.ps1` 的 `$DevTools` 哈希表中添加条目

## 知识库

| 需要做什么 | 阅读文档 |
|---|---|
| 添加数据驱动工具（哈希表定义，core.ps1 生命周期） | `.knowledge/Tool-Development/DataDriven-Tools.md` |
| 添加独立工具脚本（自有 param/dispatch/lock） | `.knowledge/Tool-Development/Standalone-Tools.md` |
| 查询 PSScriptAnalyzer 规则定义和参数用法 | `.knowledge/PSScriptAnalyzer/Rules/<RuleName>.md` |
| 查询 PSScriptAnalyzer cmdlet 用法 | `.knowledge/PSScriptAnalyzer/Cmdlets/` |

## 代码质量 — PSScriptAnalyzer

本项目使用 PSScriptAnalyzer 进行静态检查。规则文档位于 `.knowledge/PSScriptAnalyzer/`。

### 运行分析

```powershell
# 分析单个文件
Invoke-ScriptAnalyzer -Path .scripts\tools\just.ps1

# 分析整个目录（递归）
Invoke-ScriptAnalyzer -Path .scripts -Recurse -ReportSummary

# 只看 Error 级别
Invoke-ScriptAnalyzer -Path .scripts -Severity Error -Recurse

# 排除特定规则
Invoke-ScriptAnalyzer -Path .scripts -Recurse -ExcludeRule PSAvoidUsingWriteHost

# 自动修复可修复的问题（先备份！）
Invoke-ScriptAnalyzer -Path .scripts -Recurse -Fix

# 查看所有可用规则
Get-ScriptAnalyzerRule
```

### 格式化

```powershell
# 格式化脚本文本（返回格式化后的字符串）
$code = Get-Content -Path .scripts\tools\just.ps1 -Raw
Invoke-Formatter -ScriptDefinition $code
```

### 项目规则适用说明

本项目代码大量使用 `Write-Host` 输出带颜色的状态信息。PSScriptAnalyzer 的 `PSAvoidUsingWriteHost` 规则（默认启用，Warning 级别）**不会**对使用 `Show-*` 动词的函数触发，因此所有 `Show-*` 函数可安全使用 `Write-Host`。`Invoke-*` 函数（如 `Invoke-ToolInstall`）中的 `Write-Host` 会触发该规则，这是本项目的预期行为——工具安装脚本面向终端用户而非管道消费。

### 与本项目相关的关键规则

| 规则 | 级别 | 项目处理方式 |
|------|------|-------------|
| `PSAvoidUsingWriteHost` | Warning | `Show-*` 函数自动豁免；`Invoke-*` 中的 `Write-Host` 是预期行为 |
| `PSProvideCommentHelp` | Information | 已遵循：所有函数都有 `.SYNOPSIS` 注释帮助 |
| `PSUseApprovedVerbs` | Warning | 已遵循：使用 Get/Set/New/Show/Invoke/Test 等批准动词 |
| `PSAvoidUsingCmdletAliases` | Warning | 已遵循：始终使用完整 cmdlet 名称 |
| `PSAvoidUsingPositionalParameters` | Information | 3+ 参数时必须使用命名参数 |
| `PSUseShouldProcessForStateChangingFunctions` | Warning | `Set-*`/`Remove-*` 函数需要 `SupportsShouldProcess`（工具脚本的 `Invoke-*` 不触发） |
| `PSAvoidEmptyCatchBlock` | Warning | 空 `catch` 块中应有 `Write-Error` 或 `throw` |
| `PSReviewUnusedParameter` | Warning | 未使用的参数应移除（可配置 `CommandsToTraverse` 扩展作用域检查） |
| `PSUseConsistentIndentation` | Warning | 默认未启用；项目已通过 Style Guide 约定 4 空格缩进 |
| `PSUseConsistentWhitespace` | Warning | 默认未启用；可配置 `CheckOperator`/`CheckPipe`/`CheckSeparator` 等 |

## PowerShell 编码规范

本项目 PowerShell 代码遵循 `.knowledge/PowerShellPracticeAndStyle/`。所有现有函数已符合以下规范。添加**新**函数或修改现有函数时，**必须先完整阅读引用的源文档**再编写代码。

### 函数结构（每个函数必须包含三要素）

```powershell
function Get-Something {
    <#
    .SYNOPSIS
        一行描述函数的功能。
    #>
    [CmdletBinding()]
    [OutputType([string])]  # 仅向管道输出对象的函数需要；Show-*/Invoke-* 等只用 Write-Host 的可省略
    param(
        [Parameter(Mandatory)]
        [string]$ParamName
    )
    # 提前退出：用裸 `return`，不要用 `$null` 作为语句
    if (-not (Test-Path $ParamName)) { return }

    # 函数体 — 直接输出对象，不要用 `return` 关键字
    $result
}
```

| 需要做什么 | 先阅读文档 |
|---|---|
| 编写新函数/脚本、调整函数结构、添加参数验证 | `Style-Guide/Function-Structure.md` |
| 格式化代码（缩进、换行、大括号、空行） | `Style-Guide/Code-Layout-and-Formatting.md` |
| 命名函数/参数、处理文件路径引用 | `Style-Guide/Naming-Conventions.md` |
| 编写注释或注释帮助 | `Style-Guide/Documentation-and-Comments.md` |
| 重构长行、处理反斜杠续行、提高可读性 | `Style-Guide/Readability.md` |
| 设计模块架构、拆分工具和控制器 | `Best-Practices/Building-Reusable-Tools.md` |
| 使用 `Write-*` 输出、格式化自定义对象、`[OutputType()]` | `Best-Practices/Output-and-Formatting.md` |
| 编写 `try/catch`、设置 `$ErrorActionPreference`、处理异常 | `Best-Practices/Error-Handling.md` |
| 优化循环/管道/文件读取 | `Best-Practices/Performance.md` |
| 处理凭据、密码、`SecureString`、敏感数据 | `Best-Practices/Security.md` |
| 编写 `param()` 块、`[Parameter()]` 属性、管道绑定 | `Best-Practices/Writing-Parameter-Blocks.md` |
| 调用 .NET API、`Add-Type`、模块依赖管理 | `Best-Practices/Language-Interop-and-.NET.md` |
| 创建/更新模块清单（.psd1）、版本管理、打包 | `Best-Practices/Metadata-Versioning-and-Packaging.md` |

所有文档根目录：`.knowledge/PowerShellPracticeAndStyle/`。

### 核心风格规则（摘要）

- **OTBS 大括号风格**，4 空格缩进，115 字符行宽限制，不用 Tab
- PascalCase 用于公共标识符，camelCase 用于私有变量
- 始终使用完整 cmdlet/参数名称（不用 `gps` 等别名）
- 所有高级函数必须有 `[CmdletBinding()]` + `param()` 块；返回对象时加 `[OutputType()]`
- Verb-Noun 命名（`Get-Verb` 使用批准动词）；**不要**用 `return` 关键字输出对象；**用 `return` 提前退出**（如 `if (-not $x) { return }`）
- 用 `$PSScriptRoot` + `Join-Path` 拼接路径，不用相对路径或 `~`
- `foreach()` 优于 `ForEach-Object`；splatting 优于反斜杠续行
- 工具（原始数据）/ 控制器（格式化）分离
- `-ErrorAction Stop` + `try/catch` 处理错误；不用 `$?` 标志变量
- 所有函数使用注释帮助（`.SYNOPSIS`、`.PARAMETER`、`.EXAMPLE`）；英文注释解释*为什么*，而非*是什么*

### 测试

本项目使用 Pester v5 进行测试，PS 5.1 兼容。测试位于 `tests/` 目录。

```powershell
# 运行全部测试
Invoke-Pester -Path .\tests -Configuration .\tests\tests.psd1

# 只运行单元测试
Invoke-Pester -Path .\tests\Unit

# 只运行集成测试
Invoke-Pester -Path .\tests\Integration

# 运行单个文件
Invoke-Pester -Path .\tests\Unit\Compare-SemanticVersion.Tests.ps1

# 带代码覆盖率
Invoke-Pester -Path .\tests -CodeCoverage .scripts\helpers.ps1,.scripts\core.ps1
```

#### 目录结构

```
tests/
    tests.psd1                          # Pester 配置
    Helpers/
        TestHelpers.ps1                 # 共享 BeforeAll 设置、合成工具定义、Mock 工厂
    Unit/                               # 纯函数单元测试（无外部依赖）
        Compare-SemanticVersion.Tests.ps1
        ConvertTo-Hashtable.Tests.ps1
        Convert-PSGalleryEntry.Tests.ps1
        Test-VersionLocked.Tests.ps1
        Set-VersionLock.Tests.ps1
        Test-UpgradeRequired.Tests.ps1
        Get-ToolConfig.Tests.ps1
        Set-ToolConfig.Tests.ps1
        Get-ToolCacheDir.Tests.ps1
        Get-ToolExePath.Tests.ps1
        Import-ToolDefinition.Tests.ps1
        Find-GitHubReleaseAsset.Tests.ps1
        Get-ToolDownloadUrl.Tests.ps1
        Get-LatestGitHubVersion.Tests.ps1
        Test-FileHash.Tests.ps1
        Backup-ToolVersion.Tests.ps1
        Restore-ToolVersion.Tests.ps1
        Profile-Line.Tests.ps1
        Get-PSModuleLock.Tests.ps1
        Set-PSModuleLock.Tests.ps1
        Test-PSModuleValid.Tests.ps1
        Get-PSModuleVersionInstalled.Tests.ps1
        Get-PSModulePaths.Tests.ps1
    Integration/                        # 集成测试（Mock 隔离外部依赖）
        Update-Environment.Tests.ps1
        Add-UserPath.Tests.ps1
        Remove-UserPath.Tests.ps1
        Initialize-ToolPrefix.Tests.ps1
        Invoke-ToolCheck.Tests.ps1
        Invoke-ToolDownload.Tests.ps1
        Invoke-ToolInstall.Tests.ps1
        Invoke-ToolUninstall.Tests.ps1
        Invoke-ToolLock.Tests.ps1
        Invoke-ToolDownloadCmd.Tests.ps1
        Invoke-PSModuleDownload.Tests.ps1
        Invoke-PSModuleInstall.Tests.ps1
        Invoke-PSModuleUninstall.Tests.ps1
```

#### 测试关键约束

- **`$script:OhmyRoot` 在 dot-source 时固定。** helpers.ps1 加载时设置 `$script:OhmyRoot`，函数内部始终读取 helpers.ps1 自身 `$script:` 作用域的值，无法从外部测试文件覆盖。解决方案：接受真实路径，使用唯一随机后缀的工具名和 `BeforeAll`/`AfterAll` 清理。
- **`TestDrive` 不能替代 `$script:OhmyRoot`。** core.ps1 和 helpers.ps1 中的函数引用 `$script:OhmyRoot`（来自 helpers.ps1 的 `$script:` 作用域），而非 `$global:Tool_RootDir`。只有需要 `$global:Tool_RootDir` 的地方（如 `Invoke-ToolInstall`、`Invoke-ToolDownload`）可通过赋值 `$global:Tool_RootDir` 重定向。
- **Profile 测试使用真实路径 + 备份/恢复。** `Mock [Environment]::GetFolderPath` 在 PS 5.1 上不可靠。Profile-Line 测试读写真实 `Documents\WindowsPowerShell\` 和 `Documents\PowerShell\` 目录，在 `BeforeAll` 备份、`AfterAll` 恢复。
- **PATH 操作测试直接使用注册表。** `Mock [Environment]::GetEnvironmentVariable` 在 PS 5.1 + Pester v5 上不可用（详见经验教训）。`Add-UserPath`/`Remove-UserPath`/`Update-Environment` 的测试在 `BeforeAll`/`AfterAll` 中备份/恢复 User PATH。
- **`Should -Invoke` 对 dot-source 函数中的 cmdlet 不可见。** 在 `BeforeAll` 中 `Mock Remove-Item`，但 `Invoke-ToolUninstall` 通过 dot-source 作用域调用 `Remove-Item`，Pester 找不到 mock。解决方案：用 `Test-Path` 验证实际文件系统状态替代 `Should -Invoke`。

### 经验教训

#### `return` 与流程控制

- **`$null` 作为语句不会提前返回。** `{ $null }` 在 `if` 块中会向管道发送 `$null` 并且**继续执行后续语句**。这会导致隐蔽的 bug：（1）提前退出条件静默失败；（2）尾部的 `$null` 污染函数返回值，将干净的字符串变成含 `$null` 的数组；（3）下游调用者将结果传给 `[string]` 类型参数时触发 `ParameterBindingArgumentTransformationException`。修复：用裸 `return` 提前退出。此规则同样适用于 `{ $false }`、`{ $true }` 以及任何用作实际返回的裸值语句。
- **函数中间的裸 `$true`/`$false`/值也不会提前返回。** 同样的规则适用于所有位置：配置读取中的 `$cfg.lock`、缓存命中后的 `$zipFile`——这些都不会导致提前退出。函数会继续执行所有后续语句。提前退出必须用：`return $cfg.lock`、`return $zipFile`、`return`。输出函数最终值时：让值作为最后一条语句自然落下（不用 `return` 关键字）。模式：`Get-*Lock` / `Test-*` 函数在条件分支中必须用 `return`，不能用裸值。
- **`Test-FileHash` 验证成功后必须 `return`，否则继续执行后续方法和 fallback。** Method 1（GitHub digest）和 Method 2（checksums.txt）的成功分支都用 `$true` 发送到管道但不 `return`，导致执行继续到 Method 2 和 fallback 的 `[WARN] No digest from GitHub API` 警告。修复：成功分支用 `return $true`。
- **`Test-VersionLocked` / `Get-UpdateRequirement` 的提前返回必须用 `return`。** `Get-UpdateRequirement` 中版本锁定和 Force 模式的 hashtable 用裸值发送但不 `return`，后续 `Compare-SemanticVersion` 会覆盖结果或追加多余输出。修复：所有分支的 early-return 一律用 `return @{...}`。
- **版本提取函数 `$Matches[1]` 必须用 `return`。** `Get-ToolInstalledVersion`、`Get-NodeVersion`、`Get-DuckdbVersion`、`Get-RustVersion` 等函数中 `if ($raw -match ...) { $Matches[1] }` 是裸值发送。在非函数末尾（如后有 `$null` 或 `throw`）会导致输出被污染或错误抛出。修复：统一用 `return $Matches[1]`。
- **`return ,@($array)` 会多余包装。** 逗号操作符 `,@($arr)` 创建单元素数组包装 `$arr`。虽然 PowerShell 通常会解包，但行为在不同上下文（交互式 vs `-File` 执行）中不一致。修复：不要用 `return` 发送对象（按风格指南）；直接输出：`[string[]]($arr)` 或 `$arr`。

#### PS 5.1 兼容性

- **`Save-Package` 不保存 `.nupkg` 文件。** PS 5.1 中 `Save-Package -Source PSGallery` 保存的是展开的模块目录，不是 `.nupkg` 文件。`Register-PSRepository` 需要文件夹中有 `.nupkg` 文件。改用 `Invoke-WebRequest` / `WebClient.DownloadFile` 从 PSGallery API（`/api/v2/package/<name>/<version>`）获取实际的 `.nupkg` 文件。
- **PS 5.1 `Register-PSRepository` 需要 NuGet 提供程序。** 全新 PS 5.1 上 `Register-PSRepository` 会触发 NuGet 二进制安装并弹出交互式 `ShouldContinue` 提示，在非交互环境中会失败。预装：`Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force`。
- **`Install-Module -Scope CurrentUser` 只安装到当前 PS 版本路径。** PS 5.1 → `Documents\WindowsPowerShell\Modules\`，PS 7+ → `Documents\PowerShell\Modules\`。跨版本安装需要将模块目录复制到另一个版本的路径。
- **PS 5.1 `[string[]]` Mandatory 参数拒绝尾部带空字符串的 `Object[]`。** 当 `System.Object[]` 数组（如来自 `-split` 或 `Get-Content`）最后一个元素是空字符串时，PS 5.1 参数绑定会抛出 `ParameterArgumentValidationErrorEmptyStringNotAllowed`。修复：用 `[object[]]` 替代 `[string[]]` 作为参数类型；函数体内已通过 `.Trim()` 和 `-eq` 将元素按字符串处理。
- **PS 5.1 `Invoke-WebRequest` 对 `application/octet-stream` 返回 `byte[]`。** 与 PS 7+ 不同，PS 5.1 不会自动将 `application/octet-stream` 响应解码为文本。修复：检查 `$response.Content -is [byte[]]`，手动用 `[System.Text.Encoding]::UTF8.GetString($response.Content)` 解码。
- **`[ValidateNotNullOrEmpty()]` 加在仅在部分路径必需的 `[string[]]` Mandatory 参数上会阻塞合法调用。** 如果参数只在某些代码路径需要（如 `-Line` 在 "add" 和非块模式中需要，但在块模式 "remove" 中无关），设为 `[Parameter(Mandatory)]` 会强制所有调用者传入——而 PS 5.1 拒绝 `[string[]]` Mandatory 参数接收空字符串。修复：从 param 块移除 `[Mandatory]` 和 `[ValidateNotNullOrEmpty()]`，在函数内部对实际需要的场景做运行时验证。
- **PS 5.1 `[Parameter(Mandatory)]` 加在 `[string[]]` 上会拒绝 `Get-Content` 返回的空数组。** 当 profile 文件不存在时 `Get-Content` 返回 `$null`，`@($null)` 变成单元素数组；文件存在但为空时 `Get-Content` 返回 `$null`，`@()` 包装为空数组。PS 5.1 `[Parameter(Mandatory)]` 的 `[string[]]` 拒绝空数组并抛出 `ParameterArgumentValidationErrorEmptyStringNotAllowed`。脚本内部调用的函数也会触发——错误堆栈可能误导性地指向外部调用位置。修复：从可能接收空数组的集合类型参数移除 `[Parameter(Mandatory)]`；在函数内添加 `if (-not $lines) { return ,@() }` 作为前置守卫。
- **`Write-Log ""` 配合 `[Parameter(Mandatory)] [string]$Message` 在 PS 5.1 中崩溃。** PS 5.1 的 `[Parameter(Mandatory)]` 在 `[string]` 上拒绝空字符串。修复：用 `Write-Host ""` 输出空行；`Write-Log`（或任何含 Mandatory 字符串参数的函数）只用于实际消息。

#### 下载与网络

- **`Save-GitHubReleaseAsset` 要求 gh CLI 可用，不能用于安装 gh 自身。** 该函数首行检查 `Test-GhAuthenticated`，gh 不存在时直接 throw。安装 gh 时会形成循环依赖。修复：`Invoke-ToolDownload` 对 GitHub release 下载实现回退：gh CLI → direct URL。`PostInstall` 中下载附加文件同理。
- **gh CLI 的 asset 字段名与 GitHub API 不同。** `gh release view --json tagName,assets` 返回 `url`（浏览器下载链接）和 `digest`（`sha256:...`），而 GitHub REST API 返回 `browser_download_url` 和无 digest 字段。`Get-GitHubRelease` 从 gh CLI 构建 release 对象时必须映射：`$_.url` → `browser_download_url`，`$_.digest` → `digest`。否则下游 `Test-FileHash` 的 Method 1（digest 验证）和 Method 2（checksum 文件下载）都会因字段缺失而跳过。
- **所有网络下载必须实现回退链。** 中国网络环境下 GitHub 直连经常超时。下载链路统一为：gh CLI（已认证、无限速）→ direct URL（`Invoke-WebRequest`）。`Invoke-ToolDownload`、`PostInstall` 附加文件下载、`Test-FileHash` checksum 文件下载均需遵守此模式。
- **`AssetNamePattern` 不能跳过架构过滤。** `Find-GitHubReleaseAsset` 在设置 `NamePattern` 时会先尝试精确匹配并跳过 platform/arch 过滤（`-Select-Object -First 1`）。GitHub API 返回的 assets 顺序不确定（如 ripgrep 的 aarch64 排在 x86_64 前面），导致在 x86_64 机器上下载了 aarch64 包。修复：删除 NamePattern 的提前返回快捷路径，让所有 assets 都经过 platform + arch 过滤后再叠加 NamePattern 过滤（已有此逻辑）。
- **`Invoke-ToolDownload` 的 cache hit 提前返回会跳过 companion assets 下载。** 主文件命中缓存后直接 `return $zipFile`，导致 `Assets` 中定义的附加文件（如 mq-lsp.exe、mq-check.exe）永远不会被下载。修复：将 companion assets 下载逻辑移到主文件 cache hit 检查之前，使其在 cache hit 和 cache miss 两条路径上都能执行。
- **`Register-ObjectEvent` 异步事件在 PS 5.1 中作用域隔离，不可靠。** `WebClient.DownloadFileAsync` + `Register-ObjectEvent` 的 `DownloadFileCompleted` 事件回调在另一个 runspace 中执行，`$script:completed = $true` 赋值无法被主线程的轮询循环读到，导致 `while (-not $completed)` 死循环。修复：改用同步 `HttpWebRequest.GetResponseStream` + 64KB chunk 循环读取，在同一线程内更新进度，避免跨 runspace 变量同步问题。
- **hosts 更新必须在 gh 安装之前执行。** gh 安装通过 direct URL 下载 GitHub release，中国网络下直连 GitHub 经常超时。hosts 更新配置了加速域名解析，放在 gh 安装前可确保直连下载可用。

#### 工具生命周期

- **`Invoke-Batch` 必须防范不支持的命令。** `omc download`/`omc update` 批量运行所有开发工具时，部分脚本的 `[ValidateSet]` 可能不支持所有命令。将每个工具的分发包装在 `try/catch` 中，避免一个工具的验证错误终止整个批次。
- **`$script:DevSetupRoot` 是缓存目录，不是安装目录。** `DevSetupRoot` = `.cache\dev`，用于 `Save-WithCache` 的缓存。安装目录是 `$script:OhmyRoot\.envs\dev\<tool>`。参考 node.ps1 的 `$NodeDir = "$script:OhmyRoot\.envs\dev\node"`。混淆两者会导致文件解压到缓存目录而非安装目录。
- **安装流程必须锁优先，避免不必要的网络请求。** `omc install` 未安装时应先查锁版本：有锁直接用（无网络调用），无锁才去 GitHub API 抓最新版。已安装时幂等返回。所有 dev tool（node/rust/font/pwsh/pses）和 `core.ps1` 的 `Invoke-ToolInstall` 已遵循此模式。
- **`Test-FileHash` 和 `Test-GitHubAssetAttestation` 返回值泄漏到管道。** 验证成功时返回 `$true` 到管道，不捕获会在终端输出多余的 "True"。修复：调用时用 `$null = Test-FileHash ...` 捕获返回值，除非需要检查结果。
- **修改用户环境变量的命令必须先实际执行验证。** 涉及 `[Environment]::SetEnvironmentVariable` 的手动修复命令（如 PSModulePath 清理），给出前必须用 PowerShell 实际执行确认。语法错误（如 `$_ -TrimEnd` 缺少点号 `.TrimEnd()`）会导致用户环境变量被覆盖破坏。
- **权限提升检查必须在提升调用之前。** 当卸载函数需要管理员权限（如 `Start-Process -Verb RunAs`）时，必须在提升**之前**检查是否有实际已安装的内容。前置检查（注册表查询、`Test-Path`）通常不需要管理员权限。无条件提升会导致每次运行都弹 UAC。修复：将"是否已安装"检查移到提升块上方；未安装时提前返回。
- **卸载函数必须检查工具是否已被移除。** 批量 `omc uninstall` 遍历所有工具。每个卸载函数应在安装目录和配置文件都不存在时提前退出并输出 `[INFO] ... not installed, nothing to uninstall`。没有此检查时，批量操作会在每次调用时重新执行完整卸载流程（移除环境变量、PATH 条目等）。
- **`uv tool` 安装的依赖工具卸载顺序必须在 uv/python 之前。** 通过 `uv tool install` 安装的工具（如 jupyter-core）依赖 `uv` 命令。批量卸载时，如果先卸载 Python（会连带移除 uv），后续的 `uv tool uninstall` 将找不到 uv。修复：在 `omc.ps1` 的卸载排序列表中，将 jupyter 排在 python 之前；同时 `Invoke-JupyterUninstall` 已做 `Get-Command uv.exe` 的守卫检查，uv 不存在时跳过。
- **`update` 跳过已安装版本时仍应填充下载缓存。** `Invoke-ToolInstall -Update` 发现 installed == latest 后直接 return，不下载 zip 到 `.cache/`。后续 `omc download` 因无缓存而重新下载。修复：return 前检查缓存是否存在，缺则调用 `Invoke-ToolDownload` 填充。
- **调用 `core.ps1` 生命周期函数前必须加载 `core.ps1`。** `Invoke-Init` 只 dot-source 了 `helpers.ps1`，调用 `Invoke-BaseTool`（内部依赖 `Import-ToolDefinition`）时报 `Tool definition not found`。修复：`Invoke-Init` 中同时 dot-source `helpers.ps1` 和 `core.ps1`。
- **PS 5.1 原生命令的 stderr 在 `$ErrorActionPreference = 'Stop'` 下直接 throw，`2>$null` 无法抑制。** DuckDB 等命令将 `-- Loading resources from ~/.duckdbrc` 输出到 stderr，PS 5.1 将其包装为 `NativeCommandError` 并在 `Stop` 模式下抛出异常。`2>$null` 只重定向 PowerShell 错误流（stream 2），不影响原生命令 stderr 触发的 `NativeCommandError`。修复：版本检测不要依赖运行子进程，改用 `Test-Path` + lock 文件读取版本。

#### 进程与系统

- **`Start-Process -Verb RunAs` 提升的进程输出对调用者不可见。** 提升后的进程在独立窗口中运行，退出时立即关闭。在提升脚本内部使用 `Start-Transcript -Path $logFile`，调用方在 `-Wait` 后读取 `$logFile` 以获取错误信息。
- **`Uninstall-Module` 是移除 PSRepository 安装模块的正确方式。** 通过 `Install-Module` 从本地 PSRepository 安装的模块应使用 `Uninstall-Module` 卸载，而非手动 `Remove-Item` 删除模块目录。跨版本安装的模块（复制到另一个 PS 版本路径），需启动另一个 PS 可执行文件（`pwsh.exe` / `powershell.exe`）运行 `Uninstall-Module`。修复：用 `Uninstall-Module -Force` 替代 `Remove-Item -Recurse` 目录删除，用 `$LASTEXITCODE` 检查跨版本结果。
- **PS 5.1 下 DataGridView 必须手动创建列再设置 `AutoGenerateColumns = $false`。** `PSCustomObject` 或 `DataTable` 绑定 `DataSource` 后自动生成的列在 PS 5.1 中无法设置 `HeaderText`、`ReadOnly` 等属性（报"找不到属性"错误）。修复：先创建 `DataGridViewTextBoxColumn` 对象，设置好所有属性后通过 `$grid.Columns.Add()` 逐个添加，再绑定 `DataSource`。`AddRange()` 需要显式转换 `[System.Windows.Forms.DataGridViewColumn[]]`，但 PS 5.1 对数组类型的转换不可靠，改用逐个 `Add()` 更安全。

#### 测试与 Pester

- **Pester v5 `Mock` 无法拦截 .NET 静态方法（PS 5.1）。** `Mock [Environment]::GetEnvironmentVariable` 抛出 `CommandNotFoundException: Could not find Command`。这是 PS 5.1 + Pester v5 的已知限制。解决方案：对 PATH 操作的测试（`Add-UserPath`、`Remove-UserPath`、`Update-Environment`）使用真实注册表操作，在 `BeforeAll`/`AfterAll` 中备份/恢复 User PATH。
- **`Should -Invoke` 对 dot-source 作用域中的 cmdlet 不可见。** 生产函数通过 dot-source 加载到测试文件的 `script:` 作用域，而 `Mock` 定义在 Pester 的 `SessionState` 作用域。`Should -Invoke` 搜索 mock 时找不到跨作用域的定义。解决方案：用 `Test-Path` 验证实际文件系统状态替代 `Should -Invoke`，或移除对早期返回路径的 `Should -Invoke ... -Times 0` 断言。
- **Pester v5 `FailedCount` 可报告 1 失败但无具体测试失败。** 这是 Pester v5 的计数 bug——当 block 级别有非终止错误（如被 `try/catch` 捕获的 `NativeCommandError`）时，`FailedCount` 递增但所有 `Tests[].Result` 均为 `Passed`。不影响实际测试结果判断。
- **`Find-GitHubReleaseAsset` 的 `Sort-Object` 中 `$_` 作用域 bug。** 使用 `Sort-Object { ... $_.name ... }, 'name'` 时，`$_` 在第二个属性中被管道的最后一个对象覆盖，而非当前排序对象。修复：改用显式 `foreach` 循环构建排序列表，或在 `Sort-Object` 的 `Property` 脚本块中避免引用多个属性。
- **`Test-FileHash` 的 `throw` 被外层 `try/catch` 吞没。** 外层包裹的 `try/catch` 捕获了 SHA256 不匹配时的 `throw`，使验证失败静默通过。修复：移除外层 `try/catch`，让验证失败直接传播。
- **`Get-ToolDownloadUrl` 的 `direct-download` 格式化结果泄漏。** 当 `Format` 未提供时，函数将格式字符串发送到管道但不 `return`，后续代码继续执行。修复：格式化分支使用 `return`。

#### Profile 与环境变量

- **`PostInstall` 必须在所有 early return 路径调用。** `core.ps1` 的 `Invoke-ToolInstall` 中，`install` 同版本 early return（第 741 行）跳过了 `PostInstall`，导致 `.bashrc`、profile 等配置不写入。修复：在所有 early return 前调用 `PostInstall`。`update` 已最新路径已有此逻辑。
- **`Add-PsesModulePath` 首次设置 User 级 `PSModulePath` 时必须包含 Documents 模块路径。** User 级 `PSModulePath` 原本为空时，只追加 PSES 目录会导致 PS5 丢失默认的 `Documents\WindowsPowerShell\Modules` 搜索路径（PS5 不从 SystemDefault 追加）。修复：`Add-PsesModulePath` 首次设置时同时加入 `Documents\WindowsPowerShell\Modules` 和 `Documents\PowerShell\Modules`。
- **Profile 写入必须使用 BEGIN/END markers 实现幂等。** `git.ps1` 的 `.bashrc` 写入用简单文本匹配（`PYTHONIOENCODING=utf-8`），多次运行产生重复 block。修复：改用 `# BEGIN ohmywinclaude: git` / `# END ohmywinclaude: git` markers，写入前先删除旧 block 和 legacy 残留，确保只有一个干净的 block。
- **PS 模块 profile block 必须有模块存在性守卫。** PSFzf 的 profile block 直接 `Import-Module PSFzf`，在 PS5 未安装模块时报错。修复：用 `if (Get-Module PSFzf -ListAvailable -ErrorAction SilentlyContinue)` 包裹。
- **`Invoke-PSModuleInstall` 的 early return 路径必须配置 profile。** install 已安装和 update 已最新的 early return 跳过了 profile 配置步骤。修复：提取 `Set-ProfileBlock` 函数，在所有 early return 路径调用。
- **测试工具定义必须提供 `GetArchiveName` 或匹配 platform/arch 的资产名。** `Invoke-ToolDownload` 在无 `GetArchiveName` 时调用 `Find-GitHubReleaseAsset`，要求资产名包含平台（`windows`）和架构（`x86_64`）关键词。测试中创建合成资产时，要么在工具定义中设置 `GetArchiveName` 回调，要么在资产名中包含平台/架构关键词。
