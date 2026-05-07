#Requires -Version 5.1
<#
.SYNOPSIS
    omc - ohmyclaude tool manager.
.DESCRIPTION
    Unified entry point. Manages base scripts (uv), base tools (gh,
    ripgrep, jq, etc.), dev tools (node, rust, etc.), and PS modules.

    omc init                  -> setup PATH, prefix, and hosts
    omc                       -> check all (default)
    omc check                 -> check all
    omc check <tool>          -> check <tool>
    omc install               -> install all
    omc install <tool>        -> install <tool>
    omc update                -> update all
    omc update <tool>         -> update <tool>
    omc uninstall             -> uninstall all
    omc uninstall <tool>      -> uninstall <tool>
    omc download <tool> <ver> -> download specific version
    omc lock <tool>           -> show/lock tool version
    omc sync <dest>           -> sync project to destination (exclude .envs)
    omc help                  -> show usage
#>

param()

$ErrorActionPreference = 'Stop'

# ── Paths ──

$Root       = Split-Path $PSScriptRoot -Parent
$ScriptsDir = $PSScriptRoot
$BaseDir   = Join-Path $ScriptsDir 'base'
$ToolsDir  = Join-Path $ScriptsDir 'tools'
$DevDir    = Join-Path $ScriptsDir 'dev'

# ── Config ──

$OmcConfigFile = Join-Path $Root '.config\omc\config.json'

function Get-OmcConfig {
    <#
    .SYNOPSIS
        Read the omc configuration from JSON file.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    if (Test-Path $OmcConfigFile) {
        try {
            Get-Content $OmcConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json | ConvertTo-Hashtable
        } catch {}
    }
    @{}
}

function Set-OmcConfig {
    <#
    .SYNOPSIS
        Write the omc configuration to JSON file.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    $configDir = Split-Path $OmcConfigFile -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    $noBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($OmcConfigFile, ($Config | ConvertTo-Json -Depth 3), $noBom)
}

# ── Tool registry ──

$BaseScripts = @('uv', 'claude')

$BaseTools = @(
    'gh'
    '7z'
    'git'
    'aria2'
)

$ToolDefs = @(
    'ripgrep'
    'jq'
    'yq'
    'fzf'
    'mq'
    'just'
    'starship'
    'rumdl'
    'nushell'
    'conclaude'
)

$ToolScripts = @(
    'duckdb'
)

$Tools = $ToolDefs + $ToolScripts

$DevTools = @{
    dotnet      = 'dotnet.ps1'
    node        = 'node.ps1'
    rust        = 'rust.ps1'
    font        = 'font.ps1'
    pwsh        = 'powershell.ps1'
    pses        = 'pses.ps1'
    jupyter     = 'jupyter.ps1'
    tslsp       = 'tslsp.ps1'
    vsbuild     = 'vsbuildtools.ps1'
}

$PsModules = @{
    psanalyzer = 'PSScriptAnalyzer'
    psfzf      = 'PSFzf'
    pester     = 'Pester'
}

# ── Display ──

function Show-Help {
    <#
    .SYNOPSIS
        Display omc usage information.
    #>
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host '  omc - OhMyClaude Tool Manager' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  USAGE:' -ForegroundColor Yellow
    Write-Host '    omc <command> [tool] [args]' -ForegroundColor White
    Write-Host ''
    Write-Host '  COMMANDS:' -ForegroundColor Yellow
    Write-Host '    omc                  show help and status' -ForegroundColor DarkGray
    Write-Host '    omc check [tool]     check tool(s) or group' -ForegroundColor DarkGray
    Write-Host '    omc install [tool]   install tool(s) or group' -ForegroundColor DarkGray
    Write-Host '    omc update [tool]    update tool(s) or group' -ForegroundColor DarkGray
    Write-Host '    omc uninstall [tool] uninstall tool(s) or group' -ForegroundColor DarkGray
    Write-Host '    omc download <tool> <version>' -ForegroundColor DarkGray
    Write-Host '    omc lock <tool>      show/lock version' -ForegroundColor DarkGray
    Write-Host '    omc sync <dest>      sync project to destination' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  GROUPS:' -ForegroundColor Yellow
    Write-Host "    base                 $($BaseScripts + $BaseTools -join ', ')" -ForegroundColor DarkGray
    Write-Host "    tool                 $($Tools -join ', ')" -ForegroundColor DarkGray
    Write-Host "    dev                  $(($DevTools.Keys | Sort-Object) -join ', '), $(($PsModules.Keys | Sort-Object) -join ', ')" -ForegroundColor DarkGray
    Write-Host ''
}

function Show-UnknownTool {
    <#
    .SYNOPSIS
        Display error for unknown tool name.
    #>
    [CmdletBinding()]
    param(
        [string]$Name
    )
    Write-Host "  Unknown tool: $Name" -ForegroundColor Red
    Write-Host ''
    Write-Host '  Available:' -ForegroundColor Yellow
    $BaseScripts + $BaseTools + $Tools + $DevTools.Keys + $PsModules.Keys | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    Write-Host ''
}

# ── Init ──

function Invoke-Init {
    <#
    .SYNOPSIS
        First-run initialization: bootstrap paths, prefix, and hosts.
    #>
    [CmdletBinding()]
    param()

    # ── Load helpers and core (provides Add-UserPath, Import-ToolDefinition, etc.) ──
    . "$ScriptsDir\helpers.ps1"
    . "$ScriptsDir\core.ps1"
    $global:Tool_RootDir = $Root

    # ── Base layer: PATH ──
    Write-Host ''
    Write-Host '--- init ---' -ForegroundColor Cyan

    $baseBin  = Join-Path $Root '.envs\base\bin'
    $base7z   = Join-Path $Root '.envs\base\7z'
    $toolsBin = Join-Path $Root '.envs\tools\bin'
    $devBin   = Join-Path $Root '.envs\dev\bin'

    foreach ($dir in @($Root, $baseBin, $base7z, $toolsBin, $devBin)) {
        Add-UserPath -Dir $dir
        $normalized = $dir.TrimEnd('\')
        if ($env:Path -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -eq $normalized }) {
            # already present
        } else {
            $env:Path = "$normalized;$env:Path"
        }
    }

    # ── Prefix ──
    $config = Get-OmcConfig
    if (-not $config.prefix) {
        $config['prefix'] = $Root
        Set-OmcConfig -Config $config
    }
    Write-Host "[OK] Prefix: $Root" -ForegroundColor Green

    # ── Hosts (requires elevation) ──
    Write-Host ''
    Write-Host '--- hosts ---' -ForegroundColor Cyan

    $HostsUrl    = 'https://raw.hellogithub.com/hosts'
    $HostsFile   = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $MarkerBegin = '# GitHub520 Host Start'
    $MarkerEnd   = '# GitHub520 Host End'
    $HostsCfgPath = Join-Path $Root '.config\hosts\config.json'
    $HostsBakDir  = Join-Path $Root '.cache\base\hosts'
    $NoBom       = New-Object System.Text.UTF8Encoding $false

    # Generate elevated script for hosts update
    $elevatedScript = Join-Path $env:TEMP 'omc-hosts-update.ps1'
    $elevatedScriptContent = @'
$ErrorActionPreference = 'Stop'
$HostsUrl    = '{HOSTS_URL}'
$HostsFile   = '{HOSTS_FILE}'
$MarkerBegin = '{MARKER_BEGIN}'
$MarkerEnd   = '{MARKER_END}'
$HostsCfgPath = '{HOSTS_CFG}'
$HostsBakDir  = '{HOSTS_BAK}'
$NoBom       = New-Object System.Text.UTF8Encoding $false

function Read-HostsConfig {
    if (Test-Path $HostsCfgPath) {
        try {
            $j = Get-Content $HostsCfgPath -Raw -ErrorAction Stop | ConvertFrom-Json
            $ht = @{}; $j.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }; $ht
        } catch { @{} }
    } else { @{} }
}

function Write-HostsConfig {
    param([hashtable]$Config)
    $dir = Split-Path $HostsCfgPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($HostsCfgPath, ($Config | ConvertTo-Json -Depth 3), $NoBom)
}

function Get-HostsLines {
    if (-not (Test-Path $HostsFile)) { return @() }
    try {
        $raw = [System.IO.File]::ReadAllText($HostsFile, [System.Text.Encoding]::UTF8)
        [string[]]($raw -split "`r?`n")
    } catch { [string[]](Get-Content $HostsFile -Encoding Default -ErrorAction Stop) }
}

function Get-ExistingEntries {
    $lines = Get-HostsLines
    if (-not $lines) { return @() }
    $inBlock = $false; $entries = @()
    foreach ($l in $lines) {
        if ($l.Trim() -eq $MarkerBegin) { $inBlock = $true; continue }
        if ($l.Trim() -eq $MarkerEnd) { break }
        if ($inBlock -and $l -match '^\s*\d+\.\d+\.\d+\.\d+') { $entries += $l.Trim() }
    }
    [string[]]$entries
}

Start-Transcript -Path '{LOG_FILE}' -Force 6>$null

Write-Host ''
Write-Host '=== Update GitHub Hosts ===' -ForegroundColor Cyan
Write-Host '[INFO] Downloading GitHub hosts...' -ForegroundColor Cyan

try {
    $response = Invoke-WebRequest -Uri $HostsUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
} catch {
    Write-Host '[WARN] Download failed, retrying...' -ForegroundColor Yellow
    try {
        $response = Invoke-WebRequest -Uri $HostsUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
    } catch {
        Write-Host "[ERROR] Download failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
$rawText = if ($response.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($response.Content) } else { $response.Content }
$newHostsContent = ($rawText -split "`r?`n")
Write-Host '[OK] Downloaded' -ForegroundColor Green

$newEntries = @($newHostsContent | Where-Object { $_ -match '^\s*\d+\.\d+\.\d+\.\d+' -and $_ -notmatch '^#\s*GitHub520' } | ForEach-Object { $_.Trim() })
if ($newEntries.Count -eq 0) { Write-Host '[ERROR] No valid host entries found' -ForegroundColor Red; exit 1 }
Write-Host "[INFO] Parsed $($newEntries.Count) host entries" -ForegroundColor DarkGray

$existingEntries = Get-ExistingEntries
if ($existingEntries.Count -eq $newEntries.Count) {
    $differs = $false
    for ($i = 0; $i -lt $newEntries.Count; $i++) { if ($newEntries[$i] -ne $existingEntries[$i]) { $differs = $true; break } }
    if (-not $differs) {
        Write-Host '[OK] Hosts are up-to-date, no changes needed' -ForegroundColor Green
        $cfg = Read-HostsConfig; $cfg['lastCheck'] = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); $cfg['entryCount'] = $newEntries.Count; Write-HostsConfig -Config $cfg
        exit 0
    }
}

# Backup
if (-not (Test-Path $HostsBakDir)) { New-Item -ItemType Directory -Path $HostsBakDir -Force | Out-Null }
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupFile = Join-Path $HostsBakDir "hosts-$ts.bak"
Copy-Item $HostsFile $backupFile -Force
Get-ChildItem $HostsBakDir -Filter 'hosts-*.bak' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 | Remove-Item -Force -ErrorAction SilentlyContinue
Write-Host "[OK] Backup: $backupFile" -ForegroundColor Green

# Remove old block and merge
$lines = Get-HostsLines
$result = @(); $inBlock = $false
foreach ($l in $lines) {
    if (-not $inBlock -and $l.Trim() -eq $MarkerBegin) { $inBlock = $true; continue }
    if ($inBlock) { if ($l.Trim() -eq $MarkerEnd) { $inBlock = $false }; continue }
    $result += $l
}
$merged = @($result)
if ($merged.Count -gt 0 -and $merged[-1].Trim() -ne '') { $merged += '' }
$merged += $MarkerBegin; $merged += $newEntries; $merged += $MarkerEnd

try {
    [System.IO.File]::WriteAllLines($HostsFile, [string[]]$merged, $NoBom)
    Write-Host "[OK] Updated $HostsFile" -ForegroundColor Green
} catch { Write-Host "[ERROR] Failed to write hosts file: $_" -ForegroundColor Red; exit 1 }

try { ipconfig /flushdns *> $null; Write-Host '[OK] DNS cache flushed' -ForegroundColor Green } catch { Write-Host "[WARN] DNS flush failed: $_" -ForegroundColor Yellow }

$cfg = Read-HostsConfig
$cfg['lastUpdate'] = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$cfg['lastCheck'] = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$cfg['entryCount'] = $newEntries.Count
Write-HostsConfig -Config $cfg
Write-Host "[OK] GitHub hosts updated ($($newEntries.Count) entries)" -ForegroundColor Green

Stop-Transcript 6>$null
'@
    $logFile = Join-Path $env:TEMP 'omc-hosts-update.log'
    Remove-Item $logFile -Force -ErrorAction SilentlyContinue
    $elevatedScriptContent = $elevatedScriptContent.
        Replace('{HOSTS_URL}', $HostsUrl).
        Replace('{HOSTS_FILE}', $HostsFile).
        Replace('{MARKER_BEGIN}', $MarkerBegin).
        Replace('{MARKER_END}', $MarkerEnd).
        Replace('{HOSTS_CFG}', $HostsCfgPath).
        Replace('{HOSTS_BAK}', $HostsBakDir).
        Replace('{LOG_FILE}', $logFile)
    $noBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($elevatedScript, $elevatedScriptContent, $noBom)

    $shell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
    Start-Process $shell -Verb RunAs -ArgumentList @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $elevatedScript
    ) -Wait -PassThru
    if (Test-Path $logFile) {
        Get-Content $logFile -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '^\s*\[(OK|WARN|ERROR|INFO)\]' } |
            ForEach-Object { Write-Host $_ }
    }
    Remove-Item $logFile -Force -ErrorAction SilentlyContinue
    Remove-Item $elevatedScript -Force -ErrorAction SilentlyContinue

    # ── gh CLI ──
    Write-Host ''
    Write-Host '--- gh ---' -ForegroundColor Cyan

    $ghExe = Get-Command gh.exe -ErrorAction SilentlyContinue
    if ($ghExe) {
        try {
            $ghVer = (& $ghExe.Source --version 2>$null) -join ''
            if ($ghVer -match '(\d+\.\d+\.\d+)') { $ghVer = $Matches[1] }
        } catch { $ghVer = '' }
        Write-Host "[OK] gh $ghVer" -ForegroundColor Green
    } else {
        Write-Host '[INFO] gh not found, installing...' -ForegroundColor Cyan
        Invoke-BaseTool -Tool 'gh' -Cmd 'install'
    }

    Write-Host ''
    Write-Host '[OK] omc initialized. Run "omc install" to install tools.' -ForegroundColor Green
    Write-Host ''
}

# ── Base tool dispatcher (core.ps1 lifecycle) ──

function Invoke-BaseTool {
    <#
    .SYNOPSIS
        Dispatch a command to a base tool via core.ps1 lifecycle.
    #>
    [CmdletBinding()]
    param(
        [string]$Tool,
        [string]$Cmd = 'install',
        [string]$ExtraArgs = ''
    )

    $toolDef = $null
    try { $toolDef = Import-ToolDefinition -ToolName $Tool } catch { }
    if (-not $toolDef) {
        # Fallback: standalone script in dev/
        $scriptPath = Join-Path $DevDir "$Tool.ps1"
        if (Test-Path $scriptPath) {
            Invoke-DevTool -Script "$Tool.ps1" -Cmd $Cmd -ExtraArgs $ExtraArgs
            return
        }
        Write-Host "[ERROR] Tool definition not found: $Tool" -ForegroundColor Red
        exit 1
    }
    Initialize-ToolPrefix -ToolDef $toolDef -DefaultPrefix $Root | Out-Null

    switch ($Cmd) {
        'check'     { Invoke-ToolCheck -ToolDef $toolDef }
        'download'  {
            if ($ExtraArgs) {
                Invoke-ToolDownload -ToolDef $toolDef -Version $ExtraArgs
            } else {
                Invoke-ToolDownloadCmd -ToolDef $toolDef
            }
        }
        'install'   { Invoke-ToolInstall -ToolDef $toolDef -Update:$false }
        'update'    { Invoke-ToolInstall -ToolDef $toolDef -Update:$true }
        'uninstall' { Invoke-ToolUninstall -ToolDef $toolDef }
        'lock'      { Invoke-ToolLock -ToolDef $toolDef }
        'help'      { Show-ToolHelp -ToolDef $toolDef }
        default {
            Write-Host "[ERROR] Unknown command '$Cmd' for $Tool" -ForegroundColor Red
            exit 1
        }
    }
}

# ── Dev tool dispatcher ──

function Invoke-DevTool {
    <#
    .SYNOPSIS
        Dispatch a command to a dev tool script.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Script,

        [Parameter(Mandatory)]
        [string]$Cmd,

        [string]$ExtraArgs = ''
    )
    $path = Join-Path $DevDir $Script
    if ($ExtraArgs) {
        & $path $Cmd $ExtraArgs
    } else {
        & $path $Cmd
    }
}

function Invoke-PsModule {
    <#
    .SYNOPSIS
        Dispatch a command to a PowerShell module via psanalyzer.ps1.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Module,

        [Parameter(Mandatory)]
        [string]$Cmd
    )
    & (Join-Path $DevDir 'psanalyzer.ps1') $Cmd -Module $Module
}

# ── Batch operations ──

function Invoke-Batch {
    <#
    .SYNOPSIS
        Run a command across all registered tools.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Cmd
    )

    # Base scripts + tools — skip during batch uninstall
    if ($Cmd -ne 'uninstall') {
        Write-Host ''
        # Explicit order: gh -> git -> uv -> claude -> 7z
        $baseInstallOrder = @('gh', 'git') + $BaseScripts + @('7z', 'aria2')
        foreach ($tool in $baseInstallOrder) {
            if ($BaseTools -contains $tool) {
                try {
                    switch ($Cmd) {
                        'check'     { Invoke-BaseTool $tool 'check' }
                        'download'  { Invoke-BaseTool $tool 'download' }
                        'install'   { Invoke-BaseTool $tool 'install' }
                        'update'    { Invoke-BaseTool $tool 'update' }
                    }
                } catch {
                    Write-Host "[WARN] ${tool}: $_" -ForegroundColor DarkGray
                }
            } elseif ($BaseScripts -contains $tool) {
                $scriptPath = Join-Path $BaseDir "$tool.ps1"
                if (Test-Path $scriptPath) {
                    try {
                        switch ($Cmd) {
                            'check'     { & $scriptPath check }
                            'download'  { & $scriptPath download }
                            'install'   { & $scriptPath install }
                            'update'    { & $scriptPath update }
                        }
                    } catch {
                        Write-Host "[WARN] ${tool}: command '$Cmd' not supported" -ForegroundColor DarkGray
                    }
                }
            }
        }
    }

    # Tools
    Write-Host ''
    foreach ($tool in $ToolDefs) {
        try {
            switch ($Cmd) {
                'check'     { Invoke-BaseTool $tool 'check' }
                'download'  { Invoke-BaseTool $tool 'download' }
                'install'   { Invoke-BaseTool $tool 'install' }
                'update'    { Invoke-BaseTool $tool 'update' }
                'uninstall' { Invoke-BaseTool $tool 'uninstall' }
            }
        } catch {
            Write-Host "[WARN] ${tool}: $_" -ForegroundColor DarkGray
        }
    }
    foreach ($tool in $ToolScripts) {
        $toolScript = Join-Path $ToolsDir "$tool.ps1"
        try {
            switch ($Cmd) {
                'check'     { & $toolScript check }
                'download'  { & $toolScript download }
                'install'   { & $toolScript install }
                'update'    { & $toolScript update }
                'uninstall' { & $toolScript uninstall }
            }
        } catch {
            Write-Host "[WARN] ${tool}: $_" -ForegroundColor DarkGray
        }
    }

    # Dev tools + PS modules
    Write-Host ''
    foreach ($entry in $DevTools.GetEnumerator() | Sort-Object { @('dotnet','node','rust','font','pwsh','pses','vsbuild','jupyter').IndexOf($_.Key) }) {
        $path = Join-Path $DevDir $entry.Value
        try {
            switch ($Cmd) {
                'check'     { & $path check }
                'download'  { & $path download }
                'install'   { & $path install }
                'update'    { & $path update }
                'uninstall' { & $path uninstall }
            }
        } catch {
            Write-Host "[WARN] $($entry.Key): command '$Cmd' not supported" -ForegroundColor DarkGray
        }
    }
    foreach ($entry in $PsModules.GetEnumerator()) {
        $psPath = Join-Path $DevDir 'psanalyzer.ps1'
        switch ($Cmd) {
            'check'     { & $psPath check -Module $entry.Value }
            'download'  { & $psPath download -Module $entry.Value }
            'install'   { & $psPath install -Module $entry.Value }
            'update'    { & $psPath update -Module $entry.Value }
            'uninstall' { & $psPath uninstall -Module $entry.Value }
        }
    }
}

# ── Sync ──

function Invoke-Sync {
    <#
    .SYNOPSIS
        Copy the ohmyclaude project to a destination, excluding .envs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Destination
    )

    $destDir = Join-Path (Resolve-Path -Path $Destination -ErrorAction Stop) 'ohmyclaude'
    Write-Host ''
    Write-Host "  Source:      $Root" -ForegroundColor DarkGray
    Write-Host "  Destination: $destDir" -ForegroundColor DarkGray
    Write-Host "  Excluded:    .envs" -ForegroundColor DarkGray
    Write-Host ''

    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $robocopyArgs = @(
        $Root
        $destDir
        '/E'
        '/XD'
        '.envs'
        '/NJH'
        '/NJS'
        '/NDL'
        '/NFL'
        '/NP'
    )
    & robocopy @robocopyArgs

    # robocopy exit codes: 0-7 are success (0=nothing copied, 1=copied ok)
    if ($LASTEXITCODE -le 7) {
        Write-Host ''
        Write-Host '  [OK] Sync complete.' -ForegroundColor Green
    } else {
        Write-Host ''
        Write-Host "  [ERROR] robocopy failed (exit code $LASTEXITCODE)." -ForegroundColor Red
        exit 1
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Route
# ═══════════════════════════════════════════════════════════════════════════

$cmd   = if ($args.Count -gt 0) { $args[0] } else { '' }
$tool  = if ($args.Count -gt 1) { $args[1] } else { '' }
$extra = if ($args.Count -gt 2) { $args[2..($args.Count - 1)] -join ' ' } else { '' }

$AllToolNames = @($BaseScripts) + @($BaseTools) + @($Tools) + @($DevTools.Keys) + @($PsModules.Keys) + @('base', 'tool', 'dev')
$KnownCmds = @('init', 'help', 'check', 'install', 'update', 'uninstall', 'download', 'lock', 'setup', 'sync', 'hack')

$GroupNames = @('base', 'tool', 'dev')

# ── init ──

if ($cmd -eq 'init') {
    Invoke-Init
    return
}

# ── sync ──

if ($cmd -eq 'sync') {
    if (-not $tool) {
        Write-Host '  Usage: omc sync <dest>' -ForegroundColor Red
        Write-Host '  Example: omc sync e:/' -ForegroundColor DarkGray
        exit 1
    }
    Invoke-Sync -Destination $tool
    return
}

# All other commands need helpers.ps1 + core.ps1
. "$ScriptsDir\helpers.ps1"
. "$ScriptsDir\core.ps1"
$global:Tool_RootDir = $Root

# No args -> show help
if (-not $cmd) {
    Show-Help
    return
}

if ($cmd -eq 'help') {
    Show-Help
    return
}

# Old syntax swap: omc <tool> <cmd> -> omc <cmd> <tool>
if ($AllToolNames -contains $cmd -and $tool -and ($KnownCmds -notcontains $tool)) {
    Write-Host "[INFO] Did you mean: omc $tool $cmd ?" -ForegroundColor Cyan
    $realCmd = $tool
    $tool    = $cmd
    $cmd     = $realCmd
    $extra   = ''
}

if ($KnownCmds -notcontains $cmd) {
    Show-UnknownTool -Name $cmd
    exit 1
}

# Batch: no tool specified
if (-not $tool) {
    Invoke-Batch $cmd
    return
}

# Group dispatch: base / tool / dev
if ($GroupNames -contains $tool) {
    Write-Host ''
    Write-Host "--- $tool ---" -ForegroundColor Cyan
    if ($tool -eq 'base') {
        # Ensure base bin dirs are in current process PATH
        foreach ($d in @($baseBin, "$script:Root\.envs\base\git\cmd")) {
            if ($env:Path -notlike "*$d*") { $env:Path = "$d;$env:Path" }
        }
        # Explicit order: gh -> git -> uv -> claude -> 7z
        $baseOrder = @('gh', 'git') + $BaseScripts + @('7z')
        foreach ($name in $baseOrder) {
            try {
                if ($BaseTools -contains $name) {
                    switch ($cmd) {
                        'check'     { Invoke-BaseTool $name 'check' }
                        'download'  { Invoke-BaseTool $name 'download' }
                        'install'   { Invoke-BaseTool $name 'install' }
                        'update'    { Invoke-BaseTool $name 'update' }
                        'uninstall' { Invoke-BaseTool $name 'uninstall' }
                    }
                } elseif ($BaseScripts -contains $name) {
                    $scriptPath = Join-Path $BaseDir "$name.ps1"
                    if (Test-Path $scriptPath) {
                        switch ($cmd) {
                            'check'     { & $scriptPath check }
                            'download'  { & $scriptPath download }
                            'install'   { & $scriptPath install }
                            'update'    { & $scriptPath update }
                            'uninstall' { & $scriptPath uninstall }
                        }
                    }
                }
            } catch {
                Write-Host "[WARN] ${name}: $_" -ForegroundColor DarkGray
            }
        }
    }
    elseif ($tool -eq 'tool') {
        foreach ($t in $ToolDefs) {
            try {
                switch ($cmd) {
                    'check'     { Invoke-BaseTool $t 'check' }
                    'download'  { Invoke-BaseTool $t 'download' }
                    'install'   { Invoke-BaseTool $t 'install' }
                    'update'    { Invoke-BaseTool $t 'update' }
                    'uninstall' { Invoke-BaseTool $t 'uninstall' }
                }
            } catch {
                Write-Host "[WARN] ${t}: $_" -ForegroundColor DarkGray
            }
        }
        foreach ($t in $ToolScripts) {
            $toolScript = Join-Path $ToolsDir "$t.ps1"
            try {
                switch ($cmd) {
                    'check'     { & $toolScript check }
                    'download'  { & $toolScript download }
                    'install'   { & $toolScript install }
                    'update'    { & $toolScript update }
                    'uninstall' { & $toolScript uninstall }
                }
            } catch {
                Write-Host "[WARN] ${t}: $_" -ForegroundColor DarkGray
            }
        }
    }
    elseif ($tool -eq 'dev') {
        foreach ($entry in $DevTools.GetEnumerator() | Sort-Object { @('dotnet','node','rust','font','pwsh','pses','vsbuild','jupyter').IndexOf($_.Key) }) {
            $path = Join-Path $DevDir $entry.Value
            try {
                switch ($cmd) {
                    'check'     { & $path check }
                    'download'  { & $path download }
                    'install'   { & $path install }
                    'update'    { & $path update }
                    'uninstall' { & $path uninstall }
                }
            } catch {
                Write-Host "[WARN] $($entry.Key): command '$cmd' not supported" -ForegroundColor DarkGray
            }
        }
        foreach ($entry in $PsModules.GetEnumerator()) {
            $psPath = Join-Path $DevDir 'psanalyzer.ps1'
            switch ($cmd) {
                'check'     { & $psPath check -Module $entry.Value }
                'download'  { & $psPath download -Module $entry.Value }
                'install'   { & $psPath install -Module $entry.Value }
                'update'    { & $psPath update -Module $entry.Value }
                'uninstall' { & $psPath uninstall -Module $entry.Value }
            }
        }
    }
    return
}

# Per-tool dispatch
if ($BaseScripts -contains $tool) {
    $scriptPath = Join-Path $BaseDir "$tool.ps1"
    if (Test-Path $scriptPath) {
        switch ($cmd) {
            'check'     { & $scriptPath check }
            'init'      { & $scriptPath init }
            'install'   { & $scriptPath install }
            'download'  { & $scriptPath download }
            'update'    { & $scriptPath update }
            'uninstall' { & $scriptPath uninstall }
            'setup'     { & $scriptPath setup }
            'hack'      { & $scriptPath hack }
            default     { Write-Host "[ERROR] Unknown command '$cmd' for $tool" -ForegroundColor Red; exit 1 }
        }
    } else {
        Invoke-BaseTool -Tool $tool -Cmd $cmd -ExtraArgs $extra
    }
}
elseif ($BaseTools -contains $tool) {
    Invoke-BaseTool -Tool $tool -Cmd $cmd -ExtraArgs $extra
}
elseif ($ToolDefs -contains $tool) {
    Invoke-BaseTool -Tool $tool -Cmd $cmd -ExtraArgs $extra
}
elseif ($ToolScripts -contains $tool) {
    $toolScript = Join-Path $ToolsDir "$tool.ps1"
    if ($extra) {
        & $toolScript $cmd $extra
    } elseif ($cmd -eq 'default') {
        & $toolScript
    } else {
        switch ($cmd) {
            'check'     { & $toolScript check }
            'download'  { & $toolScript download }
            'install'   { & $toolScript install }
            'update'    { & $toolScript update }
            'uninstall' { & $toolScript uninstall }
            default     { & $toolScript $cmd }
        }
    }
}
elseif ($DevTools.ContainsKey($tool)) {
    Invoke-DevTool -Script $DevTools[$tool] -Cmd $cmd -ExtraArgs $extra
}
elseif ($PsModules.ContainsKey($tool)) {
    Invoke-PsModule -Module $PsModules[$tool] -Cmd $cmd
}
else {
    Show-UnknownTool -Name $tool
    exit 1
}
