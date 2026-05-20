#Requires -Version 5.1

# bat tool definition
return @{
    ToolName       = 'bat'
    DisplayName    = 'bat'
    ExeName        = 'bat.exe'
    Source         = 'github-release'
    Repo           = 'sharkdp/bat'
    ExtractType    = 'standalone'
    GetSetupDir    = { param($r) "$r\.config\bat" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = '--version'
    VersionPattern = 'bat\s+(\d+\.\d+\.\d+)'
}
