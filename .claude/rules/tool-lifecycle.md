---
paths:
  - ".scripts/**/*.ps1"
---

# Tool Lifecycle and Download Rules

编辑 `.scripts/` 下的工具脚本时加载。

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
  - 修复：companion assets 下载移到主文件缓存检查之前。

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
