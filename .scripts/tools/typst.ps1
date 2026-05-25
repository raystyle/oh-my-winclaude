#Requires -Version 5.1

# typst tool definition
return @{
    ToolName       = 'typst'
    DisplayName    = 'typst'
    ExeName        = 'typst.exe'
    Source         = 'github-release'
    Repo           = 'raystyle/typst'
    TagPrefix      = 'v'
    ExtractType    = 'none'
    GetSetupDir    = { param($r) "$r\.config\typst" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = '--version'
    VersionPattern = 'typst\s+(\d+\.\d+\.\d+[\w.-]*)'
    GetArchiveName = { param($v) "typst.exe" }
}
