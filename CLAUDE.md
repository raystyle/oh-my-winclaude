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
- **bun** — JavaScript 运行时和包管理器

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

# RULES

以下规则按主题分组，每条包含编号、标签、规则描述、原因和修复方法。

## R01. PS_RETURN — PowerShell Return 流程控制

- **R01.1** `[PS_RETURN]` **裸值不是提前退出。** `$null`、`$true`、`$false` 及任何裸值语句不会提前返回，会继续执行后续语句并污染管道。
  - 原因：PowerShell 将裸值发送到管道，然后继续执行。
  - 修复：用裸 `return` 提前退出；输出最终值时让值自然落下，不用 `return` 关键字。

- **R01.2** `[PS_RETURN]` **条件分支中的值输出必须用 `return`。** `Get-*Lock`、`Test-*` 函数在条件分支中 `$cfg.lock`、`$zipFile` 等裸值不会提前退出。
  - 原因：同 R01.1，裸值在任意位置都不提前退出。
  - 修复：所有 early-return 一律用 `return $value`，hashtable 用 `return @{...}`。

- **R01.3** `[PS_RETURN]` **验证成功分支必须 `return $true`。** `Test-FileHash` 的 Method 1/2 成功分支发送 `$true` 但不 return，导致继续执行 fallback 路径。
  - 原因：裸 `$true` 不提前退出。
  - 修复：成功分支用 `return $true`。

- **R01.4** `[PS_RETURN]` **`$Matches[1]` 版本提取必须 `return`。** `if ($raw -match ...) { $Matches[1] }` 是裸值，在非函数末尾会污染输出。
  - 原因：裸值不提前退出，后续语句可能覆盖或追加。
  - 修复：统一用 `return $Matches[1]`。

- **R01.5** `[PS_RETURN]` **不要用 `return ,@($array)` 包装数组。** 逗号操作符创建多余的单元素数组包装，行为在不同上下文中不一致。
  - 原因：`,@($arr)` 创建 `System.Object[]` 包装。
  - 修复：直接输出 `[string[]]($arr)` 或 `$arr`。

- **R01.6** `[PS_RETURN]` **格式化/查找函数的分支结果必须 `return`。** `Get-ToolDownloadUrl` 的格式化分支发送字符串但不 return，后续代码继续执行。
  - 原因：裸值不提前退出。
  - 修复：格式化分支用 `return`。

## R02. PS51_COMPAT — PS 5.1 兼容性

- **R02.1** `[PS51_COMPAT]` **`Save-Package` 不保存 `.nupkg` 文件。** PS 5.1 中 `Save-Package -Source PSGallery` 保存展开的模块目录，不是 `.nupkg`。
  - 修复：用 `Invoke-WebRequest` 从 PSGallery API `/api/v2/package/<name>/<version>` 获取。

- **R02.2** `[PS51_COMPAT]` **`Register-PSRepository` 前必须预装 NuGet。** 否则触发交互式 `ShouldContinue`，非交互环境失败。
  - 修复：先运行 `Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force`。

- **R02.3** `[PS51_COMPAT]` **`Install-Module -Scope CurrentUser` 只装到当前 PS 版本路径。** PS 5.1 → `Documents\WindowsPowerShell\Modules\`，PS 7+ → `Documents\PowerShell\Modules\`。
  - 修复：跨版本需手动复制模块目录。

- **R02.4** `[PS51_COMPAT]` **`[string[]]` Mandatory 参数拒绝含空字符串的数组。** `Object[]`（来自 `-split` 或 `Get-Content`）末尾空字符串触发 `ParameterArgumentValidationErrorEmptyStringNotAllowed`。
  - 修复：用 `[object[]]` 替代 `[string[]]`，函数体内按字符串处理。

- **R02.5** `[PS51_COMPAT]` **`Invoke-WebRequest` 对 `application/octet-stream` 返回 `byte[]`。** PS 5.1 不自动解码为文本。
  - 修复：检查 `$response.Content -is [byte[]]`，手动用 `[System.Text.Encoding]::UTF8.GetString()` 解码。

- **R02.6** `[PS51_COMPAT]` **部分路径必需的参数不要加 `[Mandatory]`。** 如 `-Line` 在块模式 "remove" 中无关，但 `[Mandatory]` 强制传入，PS 5.1 拒绝空字符串。
  - 修复：移除 `[Mandatory]` 和 `[ValidateNotNullOrEmpty()]`，函数内运行时验证。

- **R02.7** `[PS51_COMPAT]` **集合类型参数接收 `Get-Content` 空结果会崩溃。** 文件不存在时 `Get-Content` 返回 `$null`，`@($null)` 变单元素数组；空文件 `@()` 为空数组，PS 5.1 `[Parameter(Mandatory)]` 的 `[string[]]` 拒绝。
  - 修复：移除集合参数的 `[Parameter(Mandatory)]`，函数内 `if (-not $lines) { return ,@() }` 前置守卫。

- **R02.8** `[PS51_COMPAT]` **Mandatory 字符串参数拒绝空字符串。** `Write-Log ""` 配合 `[Parameter(Mandatory)] [string]$Message` 在 PS 5.1 中崩溃。
  - 修复：输出空行用 `Write-Host ""`，Mandatory 字符串参数只用于实际消息。

- **R02.9** `[PS51_COMPAT]` **`Register-ObjectEvent` 异步事件跨 runspace 不可靠。** 事件回调在另一个 runspace 执行，变量赋值无法被主线程读到，导致死循环。
  - 修复：改用同步 `HttpWebRequest.GetResponseStream` + chunk 循环读取。

- **R02.10** `[PS51_COMPAT]` **原生命令 stderr 在 `$ErrorActionPreference = 'Stop'` 下直接 throw。** `2>$null` 只重定向 PS 错误流，不影响原生命令 stderr 触发的 `NativeCommandError`。
  - 修复：版本检测不依赖运行子进程，改用 `Test-Path` + lock 文件读取。

## R03. DOWNLOAD — 网络下载

- **R03.1** `[DOWNLOAD]` **`Save-GitHubReleaseAsset` 不能用于安装 gh 自身。** 该函数首行检查 gh CLI 可用性，形成循环依赖。
  - 修复：`Invoke-ToolDownload` 对 GitHub release 实现独立回退：gh CLI → direct URL。

- **R03.2** `[DOWNLOAD]` **gh CLI asset 字段名需手动映射。** `gh release view --json` 返回 `url` 和 `digest`，与 GitHub API 的 `browser_download_url` 不同。
  - 修复：`Get-GitHubRelease` 中映射 `$_.url` → `browser_download_url`，`$_.digest` → `digest`。

- **R03.3** `[DOWNLOAD]` **所有网络下载必须实现回退链。** 中国网络下 GitHub 直连经常超时。
  - 修复：下载链路统一为 gh CLI → direct URL（`Invoke-WebRequest`），包括 `PostInstall` 附加文件和 checksum 文件。

- **R03.4** `[DOWNLOAD]` **`AssetNamePattern` 不能跳过架构过滤。** 精确匹配快捷路径会忽略 platform/arch，可能下载 aarch64 包。
  - 修复：删除 NamePattern 提前返回，所有 assets 经 platform + arch 过滤后再叠加 NamePattern。

- **R03.5** `[DOWNLOAD]` **cache hit 不能跳过 companion assets。** 主文件命中缓存直接 return 导致 `ExtraFiles` 定义的附加文件不会被下载。
  - 修复：companion assets 下载移到主文件 cache hit 检查之前。

- **R03.6** `[DOWNLOAD]` **hosts 更新必须在 gh 安装之前。** gh 安装通过 direct URL 下载，hosts 更新配置的加速域名确保直连可用。
  - 修复：`omc init` 中 hosts 更新排在 gh 安装前。

## R04. TOOL_LIFECYCLE — 工具生命周期

- **R04.1** `[TOOL_LIFECYCLE]` **`Invoke-Batch` 必须包装 try/catch 防止单工具失败终止批次。** 部分脚本的 `[ValidateSet]` 不支持所有命令。
  - 修复：每个工具的分发包装在 `try/catch` 中。

- **R04.2** `[TOOL_LIFECYCLE]` **`$script:DevSetupRoot` 是缓存目录（`.cache\dev`），不是安装目录。** 安装目录是 `$script:OhmyRoot\.envs\dev\<tool>`。
  - 修复：解压目标使用 `$script:OhmyRoot\.envs\dev\<tool>` 而非 `$script:DevSetupRoot`。

- **R04.3** `[TOOL_LIFECYCLE]` **安装流程必须锁优先，避免不必要网络请求。** 有锁直接用（无网络），无锁才查 GitHub API。
  - 修复：`Invoke-ToolInstall` 和所有 dev tool 先查锁版本。

- **R04.4** `[TOOL_LIFECYCLE]` **验证函数返回值必须捕获，防止管道泄漏。** `Test-FileHash`、`Test-GitHubAssetAttestation` 返回 `$true` 到管道，不捕获会输出多余 "True"。
  - 修复：调用时用 `$null = Test-FileHash ...`。

- **R04.5** `[TOOL_LIFECYCLE]` **修改用户环境变量的命令必须先实际执行验证。** 语法错误（如 `$_.TrimEnd` 缺括号）会覆盖破坏用户环境变量。
  - 修复：给出的修复命令先用 PowerShell 实际执行确认。

- **R04.6** `[TOOL_LIFECYCLE]` **权限提升检查必须在提升调用之前。** 无条件提升导致每次弹 UAC。
  - 修复：将"是否已安装"检查（`Test-Path`、注册表查询）移到提升块上方；未安装提前返回。

- **R04.7** `[TOOL_LIFECYCLE]` **卸载函数必须检查工具是否已被移除。** 批量 `omc uninstall` 遍历所有工具，未安装时应提前退出。
  - 修复：安装目录和配置都不存在时输出 `[INFO] ... not installed` 并返回。

- **R04.8** `[TOOL_LIFECYCLE]` **`uv tool` 安装的依赖工具卸载必须在 uv/python 之前。** 先卸载 Python 会连带移除 uv，后续 `uv tool uninstall` 失败。
  - 修复：`omc.ps1` 卸载排序中 jupyter 排在 python 前；`Invoke-JupyterUninstall` 检查 `Get-Command uv.exe`。

- **R04.9** `[TOOL_LIFECYCLE]` **`update` 跳过已安装版本时仍应填充缓存。** 直接 return 不下载 zip，后续 `omc download` 因无缓存重新下载。
  - 修复：return 前检查缓存是否存在，缺则调用 `Invoke-ToolDownload`。

- **R04.10** `[TOOL_LIFECYCLE]` **调用 `core.ps1` 生命周期函数前必须加载 `core.ps1`。** 只 dot-source `helpers.ps1` 调用 `Import-ToolDefinition` 报错。
  - 修复：`Invoke-Init` 同时 dot-source `helpers.ps1` 和 `core.ps1`。

## R05. TESTING — 测试与 Pester

- **R05.1** `[TESTING]` **`$script:OhmyRoot` 在 dot-source 时固定，无法从外部覆盖。** helpers.ps1 的 `$script:` 作用域值不能被测试文件修改。
  - 修复：接受真实路径，使用唯一随机后缀的工具名 + `BeforeAll`/`AfterAll` 清理。

- **R05.2** `[TESTING]` **`TestDrive` 不能替代 `$script:OhmyRoot`。** 只有 `$global:Tool_RootDir` 可从外部重定向。
  - 修复：仅 `Invoke-ToolInstall`/`Invoke-ToolDownload` 等使用 `$global:Tool_RootDir` 的函数可通过赋值重定向。

- **R05.3** `[TESTING]` **PATH 操作测试直接使用注册表。** `Mock [Environment]::GetEnvironmentVariable` 在 PS 5.1 + Pester v5 上不可用。
  - 修复：`Add-UserPath`/`Remove-UserPath`/`Update-Environment` 测试在 `BeforeAll`/`AfterAll` 备份/恢复 User PATH。

- **R05.4** `[TESTING]` **Profile 测试使用真实路径 + 备份/恢复。** `Mock [Environment]::GetFolderPath` 在 PS 5.1 上不可靠。
  - 修复：读写真实 `Documents\WindowsPowerShell\` 和 `Documents\PowerShell\`，`BeforeAll` 备份、`AfterAll` 恢复。

- **R05.5** `[TESTING]` **`Should -Invoke` 对 dot-source 函数中的 cmdlet 不可见。** dot-source 加载到 `script:` 作用域，Mock 在 Pester 的 `SessionState` 作用域，跨作用域不可见。
  - 修复：用 `Test-Path` 验证文件系统状态替代 `Should -Invoke`。

- **R05.6** `[TESTING]` **`FailedCount` 可报告失败但无具体测试失败。** block 级别非终止错误（如被 `try/catch` 捕获的 `NativeCommandError`）递增计数但 `Tests[].Result` 均为 Passed。
  - 修复：不影响判断，忽略此计数 bug。

- **R05.7** `[TESTING]` **`Sort-Object` 脚本块中 `$_` 作用域 bug。** 多个属性排序时 `$_` 在后续属性中被管道最后一个对象覆盖。
  - 修复：用显式 `foreach` 循环构建排序列表。

- **R05.8** `[TESTING]` **`Test-FileHash` 的 `throw` 被外层 try/catch 吞没。** 外层 try/catch 捕获 SHA256 不匹配的 throw，使验证失败静默通过。
  - 修复：移除外层 try/catch，让验证失败直接传播。

## R06. PROFILE — Profile 与环境变量

- **R06.1** `[PROFILE]` **`PostInstall` 必须在所有 early return 路径调用。** `install` 同版本 early return 跳过 `PostInstall`，导致 `.bashrc`、profile 不写入。
  - 修复：所有 early return 前调用 `PostInstall`。

- **R06.2** `[PROFILE]` **首次设置 User 级 `PSModulePath` 必须包含 Documents 模块路径。** User 级 PSModulePath 为空时只追加 PSES 目录，PS5 丢失默认搜索路径。
  - 修复：`Add-PsesModulePath` 首次设置时同时加入 `Documents\WindowsPowerShell\Modules` 和 `Documents\PowerShell\Modules`。

- **R06.3** `[PROFILE]` **Profile 写入必须使用 BEGIN/END markers 实现幂等。** 简单文本匹配多次运行产生重复 block。
  - 修复：用 `# BEGIN ohmywinclaude: <tool>` / `# END ohmywinclaude: <tool>` markers，写入前先删除旧 block。

- **R06.4** `[PROFILE]` **PS 模块 profile block 必须有模块存在性守卫。** 直接 `Import-Module` 在未安装时报错。
  - 修复：用 `if (Get-Module <Name> -ListAvailable -ErrorAction SilentlyContinue)` 包裹。

- **R06.5** `[PROFILE]` **`Invoke-PSModuleInstall` 的 early return 路径必须配置 profile。** install 已安装和 update 已最新的 early return 跳过了 profile 配置。
  - 修复：提取 `Set-ProfileBlock` 函数，在所有 early return 路径调用。

- **R06.6** `[PROFILE]` **测试工具定义必须提供 `GetArchiveName` 或资产名包含 platform/arch 关键词。** `Invoke-ToolDownload` 无 `GetArchiveName` 时调用 `Find-GitHubReleaseAsset`，要求资产名含 `windows` 和 `x86_64`。
  - 修复：合成测试资产名包含平台/架构关键词，或设置 `GetArchiveName` 回调。

## R07. CODING — PowerShell 编码规范

编码规范详细文档见 `.knowledge/PowerShellPracticeAndStyle/`。以下是核心规则摘要。

### 函数结构

所有高级函数必须包含：注释帮助（`.SYNOPSIS`）+ `[CmdletBinding()]` + `param()` 块。返回对象时加 `[OutputType()]`。用 `return` 提前退出，输出最终值时让值自然落下。

### 核心风格

- **R07.1** `[CODING]` OTBS 大括号，4 空格缩进，115 字符行宽，不用 Tab
- **R07.2** `[CODING]` PascalCase 公共标识符，camelCase 私有变量
- **R07.3** `[CODING]` 始终用完整 cmdlet/参数名称（不用别名）
- **R07.4** `[CODING]` Verb-Noun 命名，使用 `Get-Verb` 批准动词
- **R07.5** `[CODING]` 用 `$PSScriptRoot` + `Join-Path` 拼接路径，不用相对路径或 `~`
- **R07.6** `[CODING]` `foreach()` 优于 `ForEach-Object`；splatting 优于反斜杠续行
- **R07.7** `[CODING]` `-ErrorAction Stop` + `try/catch` 处理错误，不用 `$?` 标志变量
- **R07.8** `[CODING]` 注释帮助英文注释解释*为什么*，而非*是什么*

### 文档引用

| 场景 | 文档 |
|------|------|
| 函数结构、参数验证 | `.knowledge/PowerShellPracticeAndStyle/Style-Guide/Function-Structure.md` |
| 格式化（缩进、大括号） | `.knowledge/PowerShellPracticeAndStyle/Style-Guide/Code-Layout-and-Formatting.md` |
| 命名约定 | `.knowledge/PowerShellPracticeAndStyle/Style-Guide/Naming-Conventions.md` |
| 错误处理 | `.knowledge/PowerShellPracticeAndStyle/Best-Practices/Error-Handling.md` |
| 输出与格式化 | `.knowledge/PowerShellPracticeAndStyle/Best-Practices/Output-and-Formatting.md` |
| 参数块 | `.knowledge/PowerShellPracticeAndStyle/Best-Practices/Writing-Parameter-Blocks.md` |

## R08. UI — WinForms GUI

- **R08.1** `[UI]` **PS 5.1 DataGridView 必须手动创建列再绑定。** 自动生成的列无法设置 `HeaderText`、`ReadOnly` 等属性。
  - 修复：先创建列对象，设置属性后逐个 `$grid.Columns.Add()`，再绑定 `DataSource`。

- **R08.2** `[UI]` **`AddRange()` 在 PS 5.1 中数组类型转换不可靠。** 需要显式转换 `[System.Windows.Forms.DataGridViewColumn[]]`。
  - 修复：用逐个 `Add()` 替代 `AddRange()`。

- **R08.3** `[UI]` **`Start-Process -Verb RunAs` 提升进程的输出对调用者不可见。** 提升后在独立窗口运行，退出时立即关闭。
  - 修复：提升脚本内用 `Start-Transcript -Path $logFile`，调用方 `-Wait` 后读 `$logFile`。

## R09. PROCESS — 进程与系统

- **R09.1** `[PROCESS]` **`Uninstall-Module` 是移除 PSRepository 安装模块的正确方式。** 不要手动 `Remove-Item` 删除模块目录。
  - 修复：用 `Uninstall-Module -Force`。跨版本启动另一个 PS 可执行文件（`pwsh.exe`/`powershell.exe`）运行，用 `$LASTEXITCODE` 检查结果。

## R10. CLAUDE_CONFIG — Claude Code 配置

Claude Code 配置系统（环境变量、settings.json、Profile）详见 `.scripts/base/claude.ps1`。Claude Code 源码见 `.knowledge/claude_source_code/`。

### 环境变量

Claude Code 通过 `claude.ps1` 的 `Set-DefaultConfig` 自动设置幂等环境变量（API_TIMEOUT_MS、DISABLE_*、BASH_*_TIMEOUT_MS、编码/区域等）。交互配置项（ANTHROPIC_AUTH_TOKEN、BASE_URL、模型名）通过 `omc setup claude` GUI 编辑器设置。所有环境变量存储在 User 级别。

### settings.json

`Set-ClaudeSettings` 幂等合并默认值到 `~/.claude/settings.json`：`permissions.allow/deny` 用 HashSet 去重合并，不覆盖用户手动添加的字段。

### Permission 规则格式

settings.json 中 `permissions.allow/deny` 使用以下格式：
- 精确匹配：`Bash(git status)` — 匹配完整命令
- 通配符：`Bash(git *)` — `*` 匹配任意字符，`\*` 匹配字面星号
- 工具级：`Read(*)` — 匹配该工具所有操作

### Profile 系统

Profile 存储在 `.config/claude/profiles/<Name>.json`，仅覆盖 Provider 相关配置（API 凭证、模型名、1M/thinking 开关）。通用配置不受 Profile 切换影响。

- `omc switch claude` — WinForms 对话框切换 Profile
- Active profile 标记在 `.config/claude/config.json` 的 `active_profile` 字段

### Hook 系统

Claude Code 支持 4 种 hook 类型：`command`（Shell 命令）、`prompt`（LLM 评估）、`http`（HTTP POST）、`agent`（智能体验证）。Hook 事件：`PreToolUse`、`PostToolUse`、`Stop`、`AssistantMessage`、`UserMessage` 等。配置在 settings.json 的 `hooks` 字段。

### MCP 服务器

配置在项目根目录 `.mcp.json` 的 `mcpServers` 字段，支持 `stdio`、`sse`、`http`、`ws` 传输类型。

### 插件系统

插件通过 marketplace 安装，marketplace 是 GitHub 仓库（如 `raystyle/plugins`）。插件包含 skills、hooks、agents、commands 等组件。启用状态存储在 settings.json 的 `enabledPlugins` 字段（格式：`"plugin-name@marketplace": true`）。

### Skills 系统

Skills 是用户可调用的提示模板，存储在 `.claude/skills/` 目录。frontmatter 字段：`description`、`model`、`effort`、`user-invocable`、`allowed-tools`、`hooks` 等。
