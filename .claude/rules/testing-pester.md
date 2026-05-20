---
paths:
  - "tests/**/*.ps1"
  - "tests/**/*.psd1"
---

# Testing and Pester Rules

编辑 `tests/` 下的测试文件时加载。

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

## R09. PROCESS — 进程与系统

- **R09.1** `[PROCESS]` **`Uninstall-Module` 是移除 PSRepository 安装模块的正确方式。** 不要手动 `Remove-Item` 删除模块目录。
  - 修复：用 `Uninstall-Module -Force`。跨版本启动另一个 PS 可执行文件（`pwsh.exe`/`powershell.exe`）运行，用 `$LASTEXITCODE` 检查结果。
