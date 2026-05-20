#Requires -Version 5.1

# ast-grep tool definition
return @{
    ToolName       = 'ast-grep'
    DisplayName    = 'ast-grep'
    ExeName        = 'ast-grep.exe'
    Source         = 'github-release'
    Repo           = 'ast-grep/ast-grep'
    GetArchiveName = { param($v) "app-x86_64-pc-windows-msvc.zip" }
    ExtractType    = 'standalone'
    KeepFiles      = @('sg.exe')
    GetSetupDir    = { param($r) "$r\.config\ast-grep" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = '--version'
    VersionPattern = '(\d+\.\d+\.\d+)'
}
