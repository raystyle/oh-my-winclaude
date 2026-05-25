# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在本仓库中工作时提供指引。

## 项目概述

**Oh My WinClaude** 是 RAY 的私有 Claude Code 基础环境。它提供 `omc`，一个统一 CLI，用于安装、更新和版本锁定 CLI 工具（ripgrep、fzf、just、gh、duckdb 等）与开发运行时（Node.js、Rust、Jupyter、VS Build Tools 等），内置中国网络友好的下载回退机制（gh CLI 优先，直连 URL 回退）。

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
omc switch claude          # 切换 Claude Code 配置 Profile
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
    'mq', 'just', 'starship', 'rumdl', 'nushell', 'conclaude', 'bun',
    'typst'
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

## 工具一览

### 基础脚本（`$BaseScripts`）— `.scripts/base/*.ps1`

引导级工具，独立脚本，自行管理配置和缓存，通过 dot-source 调度。

- **uv** — Python 包管理器和 Python 版本管理
- **claude** — Claude Code CLI 安装器，含配置系统（详见 `.scripts/base/claude.ps1`）

### 基础工具（`$BaseTools`）— `.scripts/base/*.ps1`

数据驱动，通过 `core.ps1` 生命周期引擎调度，安装到 `.envs\base\bin`。

- **7z** — 7-Zip
- **git** — Git for Windows
- **gh** — GitHub CLI
- **aria2** — 多线程下载工具

### 工具定义（`$ToolDefs`）— `.scripts/tools/*.ps1`

数据驱动，通过 `core.ps1` 生命周期引擎调度，安装到 `.envs\tools\bin`。

- **ripgrep** — 快速搜索
- **jq** — JSON 处理器
- **yq** — YAML 处理器
- **fzf** — 模糊查找器
- **just** — 任务运行器
- **starship** — 跨 Shell 提示符
- **mq** — Markdown 命令行操作工具（主程序 + mq-lsp + mq-check）
- **rumdl** — Markdown lint/format 工具
- **nushell** — Nushell fork（nushell-evo），含 browse 插件
- **conclaude** — Claude Code 会话 guardrail 工具
- **bat** — cat 替代品（语法高亮）
- **ast-grep** — AST 结构化代码搜索（`sg` 别名）
- **bun** — JavaScript 运行时和包管理器
- **typst** — 基于标记的排版系统（raystyle/typst fork）

### 工具脚本（`$ToolScripts`）— `.scripts/tools/*.ps1`

独立脚本，自行管理生命周期。

- **duckdb** — DuckDB CLI

### 开发工具（`$DevTools`）— `.scripts/dev/*.ps1`

独立脚本，面向安装逻辑复杂的工具，通过 `Invoke-DevTool` 调度。

- **node** — Node.js
- **dotnet** — .NET SDK
- **rust** — Rust
- **font** — Nerd Font 安装器
- **pwsh** — PowerShell 7
- **pses** — PowerShellEditorServices
- **jupyter** — Jupyter
- **biome** — Biome JS/TS linter & formatter
- **tslsp** — TypeScript LSP
- **vsbuild** — VS Build Tools

### PS 模块（`$PsModules`）

通过本地离线仓库（`.cache/dev/LocalRepo/`）管理。

- **psanalyzer** — PSScriptAnalyzer
- **psfzf** — PSFzf
- **pester** — Pester

## 关键目录

- `.config/<tool>/config.json` — 各工具的配置和锁定文件
- `.config/claude/profiles/*.json` — Claude Code 配置 Profile
- `.config/omc/config.json` — omc 全局配置（prefix）
- `.cache/base/<tool>/` — 基础工具缓存
- `.cache/tools/<tool>/` — 工具缓存
- `.cache/tools/bun/install/` — Bun 全局包缓存
- `.cache/tools/bun/transpiler/` — Bun 转译器缓存
- `.cache/dev/<tool>/` — 开发工具缓存
- `.cache/dev/LocalRepo/` — 本地 PSRepository
- `.envs/base/bin/` — 引导可执行文件（7z、git、gh、aria2）
- `.envs/tools/bin/` — 工具可执行文件（rg、jq、fzf、bun 等）
- `.envs/tools/bun/` — Bun 全局安装目录
- `.envs/tools/bun/bin/` — Bun 全局包可执行文件
- `.envs/tools/duckdb/` — DuckDB 安装目录
- `.envs/dev/bin/` — 开发工具 shim 可执行文件
- `.envs/dev/<tool>/` — 开发工具安装目录

## 下载策略

所有下载路径实现回退：gh CLI（已认证、无限速）→ 直连 URL（`Invoke-WebRequest`）。

- 数据驱动工具：`Save-GitHubReleaseAsset` → `Invoke-WebRequest`；验证：`Test-GitHubAssetAttestation` → `Test-FileHash`
- 开发工具/基础脚本：使用 `helpers.ps1` 的 `Save-WithCache`
- 缓存：按工具存放在 `.cache/<category>/<tool>/`，SHA256 存入 `.config/<tool>/config.json`

## 添加工具

| 类型 | 步骤 |
|------|------|
| 数据驱动 | 1. 创建 `.scripts/tools/<name>.ps1`，返回工具定义哈希表 2. 在 `omc.ps1` 的 `$ToolDefs` 中添加 3. `GetBinDir` 返回 `.envs\tools\bin` |
| 独立脚本 | 1. 创建 `.scripts/tools/<name>.ps1`，含 `param()` 和命令处理 2. 在 `omc.ps1` 的 `$ToolScripts` 中添加 |
| 开发工具 | 1. 创建 `.scripts/dev/<name>.ps1`，含 check/install/update/uninstall/download 命令 2. 在 `omc.ps1` 的 `$DevTools` 中添加 |

## 知识库

| 需要做什么 | 阅读文档 |
|---|---|
| 添加数据驱动工具 | `.knowledge/Tool-Development/DataDriven-Tools.md` |
| 添加独立工具脚本 | `.knowledge/Tool-Development/Standalone-Tools.md` |
| PSScriptAnalyzer 规则 | `.knowledge/PSScriptAnalyzer/Rules/<RuleName>.md` |
| PSScriptAnalyzer cmdlet | `.knowledge/PSScriptAnalyzer/Cmdlets/` |
| PowerShell 编码规范 | `.knowledge/PowerShellPracticeAndStyle/` |
| Claude Code 源码 | `.knowledge/claude_source_code/` |

## 测试

Pester v5，PS 5.1 兼容。`tests/` 目录：`Unit/`（纯函数）、`Integration/`（Mock 隔离外部依赖）、`Helpers/TestHelpers.ps1`（共享设置）。

```powershell
Invoke-Pester -Path .\tests -Configuration .\tests\tests.psd1  # 全部
Invoke-Pester -Path .\tests\Unit                                 # 单元
Invoke-Pester -Path .\tests\Integration                          # 集成
```

## PSScriptAnalyzer

本项目使用 PSScriptAnalyzer 进行静态检查。`Show-*` 函数的 `Write-Host` 不触发 `PSAvoidUsingWriteHost`；`Invoke-*` 中的 `Write-Host` 是预期行为。

| 规则 | 级别 | 处理方式 |
|------|------|----------|
| `PSAvoidUsingWriteHost` | Warning | `Show-*` 豁免；`Invoke-*` 预期行为 |
| `PSProvideCommentHelp` | Info | 所有函数有 `.SYNOPSIS` |
| `PSUseApprovedVerbs` | Warning | 使用批准动词 |
| `PSAvoidUsingCmdletAliases` | Warning | 始终用完整 cmdlet 名称 |
| `PSAvoidUsingPositionalParameters` | Info | 3+ 参数用命名参数 |
| `PSUseShouldProcessForStateChangingFunctions` | Warning | `Set-*`/`Remove-*` 需要 |
| `PSAvoidEmptyCatchBlock` | Warning | 空 catch 中有 `Write-Error` 或 `throw` |
| `PSReviewUnusedParameter` | Warning | 移除未使用参数 |

---

# Rules

项目规则拆分至 `.claude/rules/`，由 Claude Code 自动加载。

| 文件 | 加载条件 | 内容 |
|------|----------|------|
| `powershell-fundamentals.md` | 始终 | R01 PS Return + R02 PS 5.1 兼容 |
| `coding-style.md` | 始终 | R07 编码规范 |
| `tool-lifecycle.md` | `.scripts/**/*.ps1` | R03 下载 + R04 工具生命周期 |
| `testing-pester.md` | `tests/**/*.ps1` | R05 Pester + R09 进程 |
| `profile-env.md` | `.scripts/**/*.ps1` | R06 Profile + R08 UI |
| `claude-config.md` | `claude.ps1` / settings | R10 Claude Code 配置 |
