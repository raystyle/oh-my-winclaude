# PowerShell Coding Style

始终加载。适用于项目中所有 `.ps1` 文件。

## 函数结构

所有高级函数必须包含：注释帮助（`.SYNOPSIS`）+ `[CmdletBinding()]` + `param()` 块。返回对象时加 `[OutputType()]`。用 `return` 提前退出，输出最终值时让值自然落下。

## R07. CODING — 核心风格

- **R07.1** `[CODING]` OTBS 大括号，4 空格缩进，115 字符行宽，不用 Tab
- **R07.2** `[CODING]` PascalCase 公共标识符，camelCase 私有变量
- **R07.3** `[CODING]` 始终用完整 cmdlet/参数名称（不用别名）
- **R07.4** `[CODING]` Verb-Noun 命名，使用 `Get-Verb` 批准动词
- **R07.5** `[CODING]` 用 `$PSScriptRoot` + `Join-Path` 拼接路径，不用相对路径或 `~`
- **R07.6** `[CODING]` `foreach()` 优于 `ForEach-Object`；splatting 优于反斜杠续行
- **R07.7** `[CODING]` `-ErrorAction Stop` + `try/catch` 处理错误，不用 `$?` 标志变量
- **R07.8** `[CODING]` 注释帮助英文注释解释*为什么*，而非*是什么*

## 文档引用

| 场景 | 文档 |
|------|------|
| 函数结构、参数验证 | `.knowledge/PowerShellPracticeAndStyle/Style-Guide/Function-Structure.md` |
| 格式化（缩进、大括号） | `.knowledge/PowerShellPracticeAndStyle/Style-Guide/Code-Layout-and-Formatting.md` |
| 命名约定 | `.knowledge/PowerShellPracticeAndStyle/Style-Guide/Naming-Conventions.md` |
| 错误处理 | `.knowledge/PowerShellPracticeAndStyle/Best-Practices/Error-Handling.md` |
| 输出与格式化 | `.knowledge/PowerShellPracticeAndStyle/Best-Practices/Output-and-Formatting.md` |
| 参数块 | `.knowledge/PowerShellPracticeAndStyle/Best-Practices/Writing-Parameter-Blocks.md` |
