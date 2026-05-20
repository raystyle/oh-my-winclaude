# PowerShell Fundamentals

始终加载。PowerShell 语言级别的规则，适用于项目中所有 `.ps1` 文件。

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
