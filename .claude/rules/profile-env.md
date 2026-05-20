---
paths:
  - ".scripts/**/*.ps1"
---

# Profile, Environment, and UI Rules

编辑 `.scripts/` 下的脚本时加载。

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

## R08. UI — WinForms GUI

- **R08.1** `[UI]` **PS 5.1 DataGridView 必须手动创建列再绑定。** 自动生成的列无法设置 `HeaderText`、`ReadOnly` 等属性。
  - 修复：先创建列对象，设置属性后逐个 `$grid.Columns.Add()`，再绑定 `DataSource`。

- **R08.2** `[UI]` **`AddRange()` 在 PS 5.1 中数组类型转换不可靠。** 需要显式转换 `[System.Windows.Forms.DataGridViewColumn[]]`。
  - 修复：用逐个 `Add()` 替代 `AddRange()`。

- **R08.3** `[UI]` **`Start-Process -Verb RunAs` 提升进程的输出对调用者不可见。** 提升后在独立窗口运行，退出时立即关闭。
  - 修复：提升脚本内用 `Start-Transcript -Path $logFile`，调用方 `-Wait` 后读 `$logFile`。
