#Requires -Version 5.1

<#
.SYNOPSIS
    Manage Claude Code installation via claude-agent-sdk.
.PARAMETER Command
    Action: check, download, install, update, uninstall, setup.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("check", "download", "install", "update", "uninstall", "setup", "hack")]
    [string]$Command = "check",

    [switch]$Force
)

. "$PSScriptRoot\..\helpers.ps1"

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

# ── Resolve ohmyclaude root from script location ──
$script:OhmyRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# ── Constants ──
$UvExe           = Join-Path $script:OhmyRoot '.envs\base\bin\uv.exe'
$CacheDir        = Join-Path $script:OhmyRoot '.cache\base\claude'
$BinDir          = "$env:USERPROFILE\.local\bin"
$TargetExe       = "$BinDir\claude.exe"
$script:ClaudeLockPath = Join-Path $script:OhmyRoot '.config\claude\config.json'
$SdkPackage      = 'claude-agent-sdk'

function Get-ClaudeExeVersion {
    <#
    .SYNOPSIS
        Get the Claude Code version string from a given executable path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) { return }
    try {
        $output = & $Path --version 2>&1 | Out-String
        if ($output -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
    } catch {}
}

function Get-InstalledVersion {
    <#
    .SYNOPSIS
        Get the currently installed Claude Code version string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Get-ClaudeExeVersion -Path $TargetExe
}

function Get-ClaudeLock {
    <#
    .SYNOPSIS
        Read the locked Claude Code and SDK versions from config.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if (-not (Test-Path $script:ClaudeLockPath)) { return }
    try {
        $cfg = Get-Content $script:ClaudeLockPath -Raw -ErrorAction SilentlyContinue |
            ConvertFrom-Json
        if ($cfg.lock) {
            return @{
                Lock          = $cfg.lock
                ClaudeVersion = if ($cfg.claude_version) { $cfg.claude_version } else { $cfg.lock }
                SdkVersion    = $cfg.sdk_version
                SHA256        = $cfg.sha256
            }
        }
    } catch {}
}

function Set-ClaudeLock {
    <#
    .SYNOPSIS
        Write the locked Claude Code version, SDK version, and SHA256 to config.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$ClaudeVersion,

        [Parameter(Mandatory)]
        [string]$SdkVersion,

        [string]$SHA256
    )

    $dir = Split-Path $script:ClaudeLockPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $noBom = New-Object System.Text.UTF8Encoding $false
    $lockStr = "$ClaudeVersion/$SdkVersion"
    $json = @{
        lock           = $lockStr
        claude_version = $ClaudeVersion
        sdk_version    = $SdkVersion
        sha256         = $SHA256
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText($script:ClaudeLockPath, $json.Trim(), $noBom)
}

function Get-SdkLatestVersion {
    <#
    .SYNOPSIS
        Query PyPI for the latest claude-agent-sdk version.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-Path $UvExe)) { return }

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $UvExe run python -m pip index versions $SdkPackage 2>$null | Out-String
    $ErrorActionPreference = $prevEAP

    if ($output -match "$SdkPackage\s*\((\d+\.\d+\.\d+)\)") { return $Matches[1] }
}

function Remove-ClaudeLock {
    <#
    .SYNOPSIS
        Delete the Claude Code lock config file.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (Test-Path $script:ClaudeLockPath) {
        Remove-Item $script:ClaudeLockPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-ClaudeExtract {
    <#
    .SYNOPSIS
        Extract claude.exe from claude-agent-sdk via uv run --with.
    .PARAMETER Destination
        Target file path for the extracted claude.exe.
    .PARAMETER SdkVersion
        Specific SDK version to use. If omitted, uses latest.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Destination,

        [string]$SdkVersion
    )

    if (-not (Test-Path $UvExe)) {
        Write-Host "[ERROR] uv not found at $UvExe - run 'omc install uv' first" -ForegroundColor Red
        exit 1
    }

    $destDir = Split-Path $Destination -Parent
    if ($destDir -and -not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $pyScript = @"
import claude_agent_sdk, shutil, os, sys
src = os.path.join(os.path.dirname(claude_agent_sdk.__file__), '_bundled', 'claude.exe')
if not os.path.isfile(src):
    print(f'[ERROR] claude.exe not found in sdk: {src}')
    sys.exit(1)
dst = os.environ.get('CLAUDE_TARGET_EXE', 'claude.exe')
os.makedirs(os.path.dirname(dst) or '.', exist_ok=True)
shutil.copy2(src, dst)
size_mb = os.path.getsize(dst) // (1024*1024)
print(f'Extracted: {dst} ({size_mb} MB)')
"@

    $withSpec = if ($SdkVersion) { "$SdkPackage==$SdkVersion" } else { $SdkPackage }
    $sdkLabel = if ($SdkVersion) { "$SdkPackage $SdkVersion" } else { "$SdkPackage (latest)" }
    Write-Host "[INFO] Extracting claude.exe via $sdkLabel ..." -ForegroundColor Cyan

    $env:CLAUDE_TARGET_EXE = $Destination
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $UvExe run --with $withSpec python -c $pyScript 2>$null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP

    if ($exitCode -ne 0) {
        Write-Host "[ERROR] claude.exe is in use - close Claude Code and try again" -ForegroundColor Red
        exit 1
    }

    if (-not (Test-Path $Destination)) {
        Write-Host "[ERROR] claude.exe not found at $Destination after extraction" -ForegroundColor Red
        exit 1
    }

    # Clean up temporary uv cache
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $UvExe cache prune 2>$null
    $ErrorActionPreference = $prevEAP
}

# ═══════════════════════════════════════════════════════════════════════════
# Configuration System
# ═══════════════════════════════════════════════════════════════════════════

$script:ClaudeDefaultBaseUrl = "https://open.bigmodel.cn/api/anthropic"
$script:ClaudeJsonPath = Join-Path $env:USERPROFILE ".claude.json"

$script:ConfigItems = @{
    # ── API ──
    API_TIMEOUT_MS = @{
        Default = "3000000"
        Description = "API request timeout (ms)"
        Type = "env"
    }
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = @{
        Default = "1"
        Description = "Disable telemetry and non-essential traffic"
        Type = "env"
    }
    ENABLE_LSP_TOOL = @{
        Default = "1"
        Description = "Enable LSP-based code intelligence"
        Type = "env"
    }
    CLAUDE_CODE_USE_POWERSHELL_TOOL = @{
        Default = "1"
        Description = "Use PowerShell as the shell tool on Windows"
        Type = "env"
    }
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = @{
        Default = "1"
        Description = "Enable experimental agent teams"
        Type = "env"
    }
    CLAUDE_CODE_GIT_BASH_PATH = @{
        Default = { Join-Path $script:OhmyRoot ".envs\base\git\bin\bash.exe" }
        Description = "Path to Git Bash executable"
        Type = "env"
        Dynamic = $true
    }
    # ── Bash timeouts (aligned with API_TIMEOUT_MS) ──
    BASH_DEFAULT_TIMEOUT_MS = @{
        Default = "300000"
        Description = "Default Bash command timeout (ms)"
        Type = "env"
    }
    BASH_MAX_TIMEOUT_MS = @{
        Default = "600000"
        Description = "Maximum Bash command timeout (ms)"
        Type = "env"
    }
    # ── Disable flags ──
    DISABLE_TELEMETRY = @{
        Default = "1"
        Description = "Disable telemetry"
        Type = "env"
    }
    DISABLE_AUTOUPDATER = @{
        Default = "1"
        Description = "Disable auto-updater"
        Type = "env"
    }
    DISABLE_AUTO_COMPACT = @{
        Default = "1"
        Description = "Disable automatic context compaction"
        Type = "env"
    }
    DISABLE_FEEDBACK_SURVEY = @{
        Default = "1"
        Description = "Disable feedback survey prompts"
        Type = "env"
    }
    CLAUDE_CODE_DISABLE_1M_CONTEXT = @{
        Default = "1"
        Description = "Disable 1M context window (unsupported by GLM)"
        Type = "env"
    }
    MCP_TIMEOUT = @{
        Default = "60000"
        Description = "MCP server communication timeout (ms)"
        Type = "env"
    }
    # ── Python encoding ──
    PYTHONUTF8 = @{
        Default = "1"
        Description = "Force Python UTF-8 mode"
        Type = "env"
    }
    PYTHONIOENCODING = @{
        Default = "utf-8"
        Description = "Python stdin/stdout/stderr encoding"
        Type = "env"
    }
    # ── Locale ──
    LANG = @{
        Default = "en_US.UTF-8"
        Description = "Locale setting"
        Type = "env"
    }
    LC_ALL = @{
        Default = "en_US.UTF-8"
        Description = "Locale override"
        Type = "env"
    }
    # ── API credentials ──
    ANTHROPIC_AUTH_TOKEN = @{
        Default = ""
        Description = "API authentication token"
        Type = "api"
        Required = $true
        Sensitive = $true
    }
    ANTHROPIC_BASE_URL = @{
        Default = $script:ClaudeDefaultBaseUrl
        Description = "API base URL"
        Type = "api"
        Required = $true
    }
    # ── Default models ──
    ANTHROPIC_DEFAULT_HAIKU_MODEL = @{
        Default = "glm-4.5-air"
        Description = "Default Haiku model"
        Type = "model"
    }
    ANTHROPIC_DEFAULT_SONNET_MODEL = @{
        Default = "glm-5-turbo"
        Description = "Default Sonnet model"
        Type = "model"
    }
    ANTHROPIC_DEFAULT_OPUS_MODEL = @{
        Default = "glm-5.1"
        Description = "Default Opus model"
        Type = "model"
    }
}

function Get-ConfigValue {
    <#
    .SYNOPSIS
        Get current value of a configuration item
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $item = $script:ConfigItems[$Name]
    if (-not $item) { $null; return }

    $current = [Environment]::GetEnvironmentVariable($Name, "User")

    if ($current) {
        @{
            Name = $Name
            Value = $current
            IsSet = $true
            Source = "env"
        }
    } else {
        @{
            Name = $Name
            Value = $null
            IsSet = $false
            Source = "default"
        }
    }
}

function Show-ConfigItemStatus {
    <#
    .SYNOPSIS
        Display status of a single config item
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $item = $script:ConfigItems[$Name]
    if (-not $item) { return }

    $config = Get-ConfigValue -Name $Name
    $defaultValue = if ($item.Dynamic) { & $item.Default } else { $item.Default }

    if ($config.IsSet) {
        $displayValue = if ($item.Sensitive) {
            if ($config.Value.Length -gt 8) {
                $config.Value.Substring(0, 8) + "..." + $config.Value.Substring($config.Value.Length - 4)
            } else {
                "***"
            }
        } else {
            $config.Value
        }
        Write-Host "  [OK] $Name = $displayValue" -ForegroundColor Green
    } else {
        $defaultDisplay = if ($defaultValue) { $defaultValue } else { "(not set)" }
        Write-Host "  [INFO] $Name = (not set, default: $defaultDisplay)" -ForegroundColor Yellow
    }
}

function Show-ConfigStatus {
    <#
    .SYNOPSIS
        Display status of all configuration items
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- Claude Code Configuration ---" -ForegroundColor Cyan

    # Environment config
    Write-Host "`n  Environment:" -ForegroundColor Cyan
    foreach ($key in $script:ConfigItems.Keys) {
        if ($script:ConfigItems[$key].Type -eq "env") {
            Show-ConfigItemStatus -Name $key
        }
    }

    # API config
    Write-Host "`n  API Credentials:" -ForegroundColor Cyan
    foreach ($key in $script:ConfigItems.Keys) {
        if ($script:ConfigItems[$key].Type -eq "api") {
            Show-ConfigItemStatus -Name $key
        }
    }

    # Model config
    Write-Host "`n  Default Models:" -ForegroundColor Cyan
    foreach ($key in $script:ConfigItems.Keys) {
        if ($script:ConfigItems[$key].Type -eq "model") {
            Show-ConfigItemStatus -Name $key
        }
    }

    # Onboarding
    $onboarded = $false
    if (Test-Path $script:ClaudeJsonPath) {
        try {
            $claudeJson = Get-Content $script:ClaudeJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($claudeJson.hasCompletedOnboarding -eq $true) { $onboarded = $true }
        } catch {}
    }
    Write-Host "`n  Onboarding:" -ForegroundColor Cyan
    if ($onboarded) {
        Write-Host "  [OK] Completed" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] Not completed" -ForegroundColor Yellow
    }

    # settings.json
    Write-Host "`n  Settings (settings.json):" -ForegroundColor Cyan
    if (Test-Path $script:ClaudeSettingsPath) {
        try {
            $s = Get-Content $script:ClaudeSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $simpleKeys = @('showThinkingSummaries', 'viewMode', 'alwaysThinkingEnabled',
                            'effortLevel', 'autoMemoryEnabled')
            foreach ($sk in $simpleKeys) {
                $val = $s.PSObject.Properties | Where-Object { $_.Name -eq $sk }
                if ($null -ne $val -and $null -ne $val.Value) {
                    Write-Host "  [OK] $sk = $($val.Value)" -ForegroundColor Green
                } else {
                    Write-Host "  [INFO] $sk = (not set)" -ForegroundColor Yellow
                }
            }
            if ($s.permissions) {
                $allowCount = @($s.permissions.allow).Count
                $denyCount = @($s.permissions.deny).Count
                Write-Host "  [OK] permissions.allow: $allowCount rule(s)" -ForegroundColor Green
                Write-Host "  [OK] permissions.deny:  $denyCount rule(s)" -ForegroundColor Green
            } else {
                Write-Host "  [INFO] permissions = (not set)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [WARN] Could not read settings.json" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [INFO] settings.json not found" -ForegroundColor Yellow
    }
}

function Set-ConfigItem {
    <#
    .SYNOPSIS
        Set a configuration item value
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Value
    )

    $item = $script:ConfigItems[$Name]
    if (-not $item) {
        Write-Host "[WARN] Unknown config item: $Name" -ForegroundColor Yellow
        return
    }

    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Item -Path "env:$Name" -Value $Value

    $displayValue = if ($item.Sensitive) { "***" } else { $Value }
    Write-Host "  [OK] $Name = $displayValue" -ForegroundColor Green

    $true
}

$script:ClaudeSettingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'

$script:ClaudeSettingsDefaults = [ordered]@{
    showThinkingSummaries  = $true
    viewMode               = 'verbose'
    alwaysThinkingEnabled  = $true
    effortLevel            = 'high'
    autoMemoryEnabled      = $true
    permissions            = [ordered]@{
        allow = [string[]]@(
            'Read(*)'
            'Write(*)'
            'Grep(*)'
            'Glob(*)'
            'Edit(*)'
            'Bash(git *)'
            'Bash(ls *)'
            'Bash(powershell *)'
            'Bash(pwsh *)'
            'Bash(omc *)'
            'Bash(rustfmt *)'
            'Bash(cargo *)'
        )
        deny = [string[]]@(
            'Read(./.env)'
            'Read(./.env.*)'
            'Read(./secrets/**)'
            'Read(**/*.key)'
            'Read(**/*.pem)'
            'Bash(rm -rf /*)'
            'Bash(curl *)'
            'Bash(wget *)'
        )
    }
}

function Set-ClaudeSettings {
    <#
    .SYNOPSIS
        Apply default settings to ~/.claude/settings.json (idempotent merge).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $settingsDir = Split-Path $script:ClaudeSettingsPath -Parent
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    $settings = [ordered]@{}
    if (Test-Path $script:ClaudeSettingsPath) {
        try {
            $existing = Get-Content $script:ClaudeSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $existing.PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value }
        } catch {}
    }

    $changed = $false
    foreach ($entry in $script:ClaudeSettingsDefaults.GetEnumerator()) {
        $key = $entry.Key
        $val = $entry.Value

        if ($val -is [System.Collections.IDictionary]) {
            $sub = $settings[$key]
            if ($null -eq $sub) {
                $settings[$key] = $val
                $changed = $true
                continue
            }
            if ($sub -is [System.Collections.IDictionary]) {
                foreach ($subEntry in $val.GetEnumerator()) {
                    $subKey = $subEntry.Key
                    $subVal = $subEntry.Value
                    if ($subVal -is [string[]] -or $subVal -is [array]) {
                        $existing = @()
                        if ($sub.Contains($subKey)) {
                            $existing = @($sub[$subKey])
                        }
                        $merged = [System.Collections.Generic.HashSet[string]]::new(
                            [StringComparer]::OrdinalIgnoreCase
                        )
                        $merged.UnionWith([string[]]$existing)
                        $before = $merged.Count
                        $merged.UnionWith([string[]]$subVal)
                        if ($merged.Count -ne $before) {
                            $sub[$subKey] = [string[]]@($merged)
                            $changed = $true
                        }
                    } else {
                        if (-not $sub.Contains($subKey) -or $sub[$subKey] -ne $subVal) {
                            $sub[$subKey] = $subVal
                            $changed = $true
                        }
                    }
                }
            }
            continue
        }

        if (-not $settings.Contains($key) -or $settings[$key] -ne $val) {
            $settings[$key] = $val
            $changed = $true
        }
    }

    if ($changed) {
        $noBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($script:ClaudeSettingsPath, ($settings | ConvertTo-Json -Depth 5), $noBom)
        Write-Host "  [OK] settings.json updated" -ForegroundColor Green
    } else {
        Write-Host "  [OK] settings.json up to date" -ForegroundColor DarkGray
    }
}

function Set-DefaultConfig {
    <#
    .SYNOPSIS
        Apply default values to all config items
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host "[INFO] Applying default configuration..." -ForegroundColor Cyan

    $changed = $false

    foreach ($key in $script:ConfigItems.Keys) {
        $item = $script:ConfigItems[$key]
        if ($item.Required -and -not $item.Default) { continue }

        $current = [Environment]::GetEnvironmentVariable($key, "User")
        $defaultValue = if ($item.Dynamic) { & $item.Default } else { $item.Default }

        if (-not $defaultValue) { continue }

        if ($current -ne $defaultValue) {
            [Environment]::SetEnvironmentVariable($key, $defaultValue, "User")
            Set-Item -Path "env:$key" -Value $defaultValue
            Write-Host "  [OK] $key = $defaultValue" -ForegroundColor Green
            $changed = $true
        } else {
            Write-Host "  [OK] $key = $defaultValue" -ForegroundColor DarkGray
        }
    }

    # Onboarding
    $onboarded = $false
    if (Test-Path $script:ClaudeJsonPath) {
        try {
            $claudeJson = Get-Content $script:ClaudeJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($claudeJson.hasCompletedOnboarding -eq $true) { $onboarded = $true }
        } catch {}
    }
    if (-not $onboarded) {
        $claudeConfig = @{}
        if (Test-Path $script:ClaudeJsonPath) {
            try {
                $existing = Get-Content $script:ClaudeJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $existing.PSObject.Properties | ForEach-Object { $claudeConfig[$_.Name] = $_.Value }
            } catch {}
        }
        $claudeConfig['hasCompletedOnboarding'] = $true
        $noBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($script:ClaudeJsonPath, ($claudeConfig | ConvertTo-Json), $noBom)
        Write-Host "  [OK] Onboarding: hasCompletedOnboarding = true" -ForegroundColor Green
        $changed = $true
    } else {
        Write-Host "  [OK] Onboarding: completed" -ForegroundColor DarkGray
    }

    if (-not $changed) {
        Write-Host "  [OK] All defaults up to date" -ForegroundColor Green
    }

    Set-ClaudeSettings
}

function Read-CustomConfig {
    <#
    .SYNOPSIS
        Open a GUI dialog to edit Claude Code interactive configuration.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $interactiveKeys = @(
        'ANTHROPIC_AUTH_TOKEN'
        'ANTHROPIC_BASE_URL'
        'ANTHROPIC_DEFAULT_HAIKU_MODEL'
        'ANTHROPIC_DEFAULT_SONNET_MODEL'
        'ANTHROPIC_DEFAULT_OPUS_MODEL'
    )

    $table = New-Object System.Data.DataTable
    $null = $table.Columns.Add("Variable")
    $null = $table.Columns.Add("Value")
    $null = $table.Columns.Add("Description")

    foreach ($key in $interactiveKeys) {
        $item = $script:ConfigItems[$key]
        $current = [Environment]::GetEnvironmentVariable($key, "User")
        if (-not $current) {
            $current = if ($item.Dynamic) { & $item.Default } else { $item.Default }
        }
        $row = $table.NewRow()
        $row["Variable"] = $key
        $row["Value"] = $current
        $row["Description"] = $item.Description
        $table.Rows.Add($row) | Out-Null
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Claude Code Configuration"
    $form.ClientSize = New-Object System.Drawing.Size(720, 300)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = "Fill"
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.MultiSelect = $false
    $grid.SelectionMode = "CellSelect"
    $grid.RowHeadersVisible = $false
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.BorderStyle = "None"
    $grid.CellBorderStyle = "SingleHorizontal"
    $grid.GridColor = [System.Drawing.Color]::LightGray
    $grid.AutoGenerateColumns = $false

    $colVar = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colVar.HeaderText = "Variable"
    $colVar.ReadOnly = $true
    $colVar.Width = 260
    $colVar.DataPropertyName = "Variable"
    $colVar.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Gray

    $colVal = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colVal.HeaderText = "Value"
    $colVal.Width = 300
    $colVal.DataPropertyName = "Value"

    $colDesc = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colDesc.HeaderText = "Description"
    $colDesc.ReadOnly = $true
    $colDesc.AutoSizeMode = "Fill"
    $colDesc.DataPropertyName = "Description"
    $colDesc.DefaultCellStyle.ForeColor = [System.Drawing.Color]::DarkGray

    $grid.Columns.Clear()
    $grid.Columns.Add($colVar)
    $grid.Columns.Add($colVal)
    $grid.Columns.Add($colDesc)
    $grid.DataSource = $table

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Bottom"
    $panel.Height = 50

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Size = New-Object System.Drawing.Size(100, 32)
    $btnCancel.Location = New-Object System.Drawing.Point(500, 8)
    $btnCancel.DialogResult = "Cancel"

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save"
    $btnSave.Size = New-Object System.Drawing.Size(100, 32)
    $btnSave.Location = New-Object System.Drawing.Point(610, 8)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(200, 230, 200)
    $btnSave.DialogResult = "OK"

    $panel.Controls.AddRange(@($btnCancel, $btnSave))
    $form.Controls.Add($panel)
    $form.Controls.Add($grid)

    $form.AcceptButton = $btnSave
    $form.CancelButton = $btnCancel

    $result = $form.ShowDialog()

    if ($result -ne "OK") { return $false }

    $grid.EndEdit()

    $tokenValue = $grid.Rows[0].Cells[1].Value
    if (-not $tokenValue -or [string]::IsNullOrWhiteSpace($tokenValue.ToString())) {
        [System.Windows.Forms.MessageBox]::Show(
            "API Key cannot be empty.", "Validation Error",
            "OK", "Error")
        return $false
    }

    for ($i = 0; $i -lt $interactiveKeys.Count; $i++) {
        $name = $interactiveKeys[$i]
        $value = $grid.Rows[$i].Cells[1].Value.ToString()
        Set-ConfigItem -Name $name -Value $value
    }

    return $true
}

function Invoke-ClaudeConfig {
    <#
    .SYNOPSIS
        Unified configuration handler for install/update/setup

    .PARAMETER Scope
        Configuration scope:
        - "install": Silent, apply defaults if not configured
        - "update": Check and apply defaults, no interaction
        - "setup": Interactive, offer configuration options

    .PARAMETER Force
        Force reconfiguration even if already set
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("install", "update", "setup")]
        [string]$Scope,

        [switch]$Force
    )

    Write-Host ""
    Write-Host "--- Claude Code Configuration ($Scope) ---" -ForegroundColor Cyan

    # Check existing configuration (only interactive items; env vars are idempotent)
    $hasApiConfig = [Environment]::GetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", "User") -and
                    [Environment]::GetEnvironmentVariable("ANTHROPIC_BASE_URL", "User")
    $hasModelConfig = [Environment]::GetEnvironmentVariable("ANTHROPIC_DEFAULT_HAIKU_MODEL", "User") -and
                      [Environment]::GetEnvironmentVariable("ANTHROPIC_DEFAULT_SONNET_MODEL", "User") -and
                      [Environment]::GetEnvironmentVariable("ANTHROPIC_DEFAULT_OPUS_MODEL", "User")

    $isFullyConfigured = $hasApiConfig -and $hasModelConfig

    # Env vars are always idempotent — apply defaults silently
    Set-DefaultConfig

    # Handle based on scope
    switch ($Scope) {
        "install" {
            if (-not $isFullyConfigured -or $Force) {
                Write-Host "[INFO] Configuration applied (env vars set to defaults)" -ForegroundColor Cyan
            } else {
                Write-Host "[OK] Configuration already present" -ForegroundColor Green
            }
        }

        "update" {
            Write-Host "[INFO] Configuration checked (env vars up to date)" -ForegroundColor Cyan
        }

        "setup" {
            Show-ConfigStatus

            if ($isFullyConfigured -and -not $Force) {
                Write-Host "`n[INFO] Configuration already present" -ForegroundColor Cyan
                $response = Read-Host "  Options: (K)eep / (R)eplace (default: K)"

                if ($response -in 'R', 'r') {
                    Write-Host "[INFO] Opening configuration editor..." -ForegroundColor Cyan
                    $success = Read-CustomConfig
                    if ($success) {
                        Write-Host "[OK] Configuration updated" -ForegroundColor Green
                        Show-ConfigStatus
                    }
                } else {
                    Write-Host "[INFO] Keeping existing configuration" -ForegroundColor Green
                }
                return
            }

            Write-Host "`n[INFO] Opening configuration editor..." -ForegroundColor Cyan
            $success = Read-CustomConfig
            if ($success) {
                Write-Host "[OK] Configuration saved" -ForegroundColor Green
                Show-ConfigStatus
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ClaudeCheck {
    <#
    .SYNOPSIS
        Display Claude Code installation and configuration status.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- Claude Code ---" -ForegroundColor Cyan

    $installed = Get-InstalledVersion
    $binFound = Test-Path $TargetExe

    if ($binFound -and $installed) {
        Write-Host "[OK] Installed: Claude Code $installed" -ForegroundColor Green
    } elseif ($binFound) {
        Write-Host "[OK] Installed (version unknown)" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Claude Code not installed" -ForegroundColor Cyan
        Write-Host "  Run 'omc install claude' to install" -ForegroundColor DarkGray
    }
    if ($binFound) {
        Write-Host "  Location: $TargetExe" -ForegroundColor DarkGray
    }

    # PATH check
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -split ';' -contains $BinDir) {
        Write-Host "  PATH:      $BinDir" -ForegroundColor DarkGray
    } else {
        Write-Host "  PATH:      not set" -ForegroundColor DarkGray
    }

    # uv check
    if (Test-Path $UvExe) {
        Write-Host "  uv:        $UvExe" -ForegroundColor DarkGray
    } else {
        Write-Host "  uv:        not installed (required for install/update)" -ForegroundColor Yellow
    }

    # Lock status
    $lock = Get-ClaudeLock
    if ($lock) {
        if ($installed -and $installed -eq $lock.ClaudeVersion) {
            Write-Host "  Lock:      $($lock.Lock) (current)" -ForegroundColor Green
        } else {
            Write-Host "  Lock:      $($lock.Lock)" -ForegroundColor Magenta
        }
        if ($lock.SdkVersion) {
            Write-Host "  SDK:       $($lock.SdkVersion)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  Lock:      none" -ForegroundColor DarkGray
    }

    Show-ConfigStatus
}

# ═══════════════════════════════════════════════════════════════════════════
# download — cache the Claude Code binary as Claude-<version>.exe
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ClaudeDownload {
    <#
    .SYNOPSIS
        Download Claude Code binary to cache via claude-agent-sdk extraction.
        Cache file named Claude-<version>.exe. Lock stores claude/sdk version pair.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-Path $CacheDir)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    }

    $lock = Get-ClaudeLock

    # If locked (with SDK version), check cache first
    if ($lock -and $lock.SdkVersion) {
        $cacheFile = Join-Path $CacheDir "Claude-$($lock.ClaudeVersion).exe"
        if ((Test-Path $cacheFile) -and $lock.SHA256) {
            $actualHash = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash.ToLower()
            if ($actualHash -eq $lock.SHA256) {
                $size = (Get-Item $cacheFile).Length
                $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
                Write-Host "[OK] Claude Code $($lock.Lock) cached: $sizeStr" -ForegroundColor Green
                return
            }
            Write-Host "[WARN] Cache hash mismatch, re-extracting" -ForegroundColor Yellow
        }

        # Re-extract with locked SDK version
        $tempFile = Join-Path $CacheDir "claude-temp-$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"
        try {
            Invoke-ClaudeExtract -Destination $tempFile -SdkVersion $lock.SdkVersion

            $claudeVersion = Get-ClaudeExeVersion -Path $tempFile
            if (-not $claudeVersion) {
                Write-Host "[ERROR] Could not determine version from extracted binary" -ForegroundColor Red
                return
            }

            $cacheFile = Join-Path $CacheDir "Claude-$claudeVersion.exe"
            Copy-Item -Path $tempFile -Destination $cacheFile -Force

            $hash = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash.ToLower()
            Set-ClaudeLock -ClaudeVersion $claudeVersion -SdkVersion $lock.SdkVersion -SHA256 $hash
            Show-LockWrite -Version "$claudeVersion/$($lock.SdkVersion)"

            $size = (Get-Item $cacheFile).Length
            $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
            Write-Host "[OK] Cached: Claude-$claudeVersion.exe ($sizeStr)" -ForegroundColor Green
        } finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        }
        return
    }

    # No lock — query latest SDK and extract
    Write-Host "[INFO] Querying latest $SdkPackage version ..." -ForegroundColor Cyan
    $sdkVersion = Get-SdkLatestVersion
    if (-not $sdkVersion) {
        Write-Host "[ERROR] Could not determine latest SDK version" -ForegroundColor Red
        return
    }
    Write-Host "[INFO] Latest SDK: $sdkVersion" -ForegroundColor Cyan

    $tempFile = Join-Path $CacheDir "claude-temp-$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"
    try {
        Invoke-ClaudeExtract -Destination $tempFile -SdkVersion $sdkVersion

        $claudeVersion = Get-ClaudeExeVersion -Path $tempFile
        if (-not $claudeVersion) {
            Write-Host "[ERROR] Could not determine version from extracted binary" -ForegroundColor Red
            return
        }

        $cacheFile = Join-Path $CacheDir "Claude-$claudeVersion.exe"
        Copy-Item -Path $tempFile -Destination $cacheFile -Force

        $hash = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash.ToLower()
        Set-ClaudeLock -ClaudeVersion $claudeVersion -SdkVersion $sdkVersion -SHA256 $hash
        Show-LockWrite -Version "$claudeVersion/$sdkVersion"

        $size = (Get-Item $cacheFile).Length
        $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
        Write-Host "[OK] Cached: Claude-$claudeVersion.exe ($sizeStr)" -ForegroundColor Green
    } finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# install — download to cache, then copy to bin
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ClaudeInstall {
    <#
    .SYNOPSIS
        Install Claude Code by extracting from claude-agent-sdk to cache, then copying to bin.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # ── 1. Check existing ──
    $installedVersion = Get-InstalledVersion
    $lock = Get-ClaudeLock

    if ($installedVersion) {
        if ($lock -and $installedVersion -eq $lock.ClaudeVersion) {
            Write-Host "[OK] Claude Code $installedVersion already installed (locked: $($lock.Lock))" -ForegroundColor Green
            return
        }
        # Installed but lock mismatch — repair lock
        $hash = (Get-FileHash -Path $TargetExe -Algorithm SHA256).Hash.ToLower()
        $sdkVersion = if ($lock) { $lock.SdkVersion } else { Get-SdkLatestVersion }
        if ($sdkVersion) {
            Set-ClaudeLock -ClaudeVersion $installedVersion -SdkVersion $sdkVersion -SHA256 $hash
            Write-Host "[OK] Lock repaired: $installedVersion/$sdkVersion" -ForegroundColor Green
        }
        Write-Host "[OK] Claude Code $installedVersion already installed" -ForegroundColor Green
        return
    }

    # ── 2. Download to cache ──
    Write-Host "[INFO] Installing Claude Code ..." -ForegroundColor Cyan
    Invoke-ClaudeDownload

    # ── 3. Copy from cache to bin ──
    $lock = Get-ClaudeLock
    if (-not $lock) {
        Write-Host "[ERROR] Download failed — no lock file created" -ForegroundColor Red
        return
    }

    $cacheFile = Join-Path $CacheDir "Claude-$($lock.ClaudeVersion).exe"
    if (-not (Test-Path $cacheFile)) {
        Write-Host "[ERROR] Cache file not found: $cacheFile" -ForegroundColor Red
        return
    }

    if (-not (Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    }

    Copy-Item -Path $cacheFile -Destination $TargetExe -Force
    Add-UserPath -Dir $BinDir

    # ── 4. Verify ──
    $currentPath = $env:Path -split ';'
    if ($BinDir -notin $currentPath) {
        $env:Path = "$BinDir;$env:PATH"
    }

    $verifyVersion = Get-InstalledVersion
    if ($verifyVersion) {
        Show-InstallComplete -Tool "Claude Code" -Version "$verifyVersion/$($lock.SdkVersion)"
    } else {
        Write-Host "[OK] Claude Code installed" -ForegroundColor Green
        Write-Host "  Location: $TargetExe" -ForegroundColor DarkGray
        Write-Host "  Restart terminal if 'claude' command is not found" -ForegroundColor DarkGray
    }

    # ── 5. Configuration ──
    Invoke-ClaudeConfig -Scope "install"

    $hasCreds = [Environment]::GetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", "User") -and
                 [Environment]::GetEnvironmentVariable("ANTHROPIC_BASE_URL", "User")
    if (-not $hasCreds) {
        Write-Host "`n[INFO] API credentials not configured" -ForegroundColor Cyan
        Write-Host "  Run 'omc setup claude' to configure" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# update — check SDK version, extract if newer, prompt upgrade
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ClaudeUpdate {
    <#
    .SYNOPSIS
        Check for new claude-agent-sdk version and upgrade Claude Code if available.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $installedVersion = Get-InstalledVersion

    if (-not $installedVersion) {
        Invoke-ClaudeInstall
        return
    }

    $lock = Get-ClaudeLock
    Write-Host "[INFO] Claude Code: $installedVersion" -ForegroundColor Cyan
    if ($lock) {
        Write-Host "[INFO] SDK: $($lock.SdkVersion)" -ForegroundColor DarkGray
    }

    # Query latest SDK version
    Write-Host "[INFO] Querying latest $SdkPackage version ..." -ForegroundColor Cyan
    $latestSdk = Get-SdkLatestVersion
    if (-not $latestSdk) {
        Write-Host "[WARN] Could not determine latest SDK version — skipping update check" -ForegroundColor Yellow
        return
    }

    $lockedSdk = if ($lock) { $lock.SdkVersion } else { $null }

    if (-not $lockedSdk) {
        $hash = (Get-FileHash -Path $TargetExe -Algorithm SHA256).Hash.ToLower()
        Set-ClaudeLock -ClaudeVersion $installedVersion -SdkVersion $latestSdk -SHA256 $hash
        Write-Host "[OK] Already installed: Claude Code $installedVersion" -ForegroundColor Green
        Write-Host "[OK] Lock restored: $installedVersion/$latestSdk" -ForegroundColor Green
        return
    }

    if ($latestSdk -eq $lockedSdk) {
        Write-Host "[OK] Already up to date: $($lock.Lock)" -ForegroundColor Green
        return
    }

    Write-Host "[UPGRADE] SDK: $lockedSdk -> $latestSdk" -ForegroundColor Cyan

    # Extract latest
    if (-not (Test-Path $CacheDir)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    }

    $tempFile = Join-Path $CacheDir "claude-new-$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"
    try {
        Invoke-ClaudeExtract -Destination $tempFile -SdkVersion $latestSdk

        $newClaudeVersion = Get-ClaudeExeVersion -Path $tempFile
        if (-not $newClaudeVersion) {
            Write-Host "[ERROR] Could not determine version from extracted binary" -ForegroundColor Red
            return
        }

        # Cache the new version
        $newCacheFile = Join-Path $CacheDir "Claude-$newClaudeVersion.exe"
        Copy-Item -Path $tempFile -Destination $newCacheFile -Force
        $hash = (Get-FileHash -Path $newCacheFile -Algorithm SHA256).Hash.ToLower()
        Set-ClaudeLock -ClaudeVersion $newClaudeVersion -SdkVersion $latestSdk -SHA256 $hash

        if ($newClaudeVersion -eq $installedVersion) {
            Write-Host "[OK] Claude Code $newClaudeVersion unchanged (SDK updated to $latestSdk)" -ForegroundColor Green
            Write-Host "[OK] Lock updated: $newClaudeVersion/$latestSdk" -ForegroundColor Green
            return
        }

        Write-Host "[UPGRADE] Claude Code: $installedVersion -> $newClaudeVersion" -ForegroundColor Cyan
        $response = Read-Host "  Upgrade? (Y/n)"
        if ($response -and $response -ne 'Y' -and $response -ne 'y') {
            Write-Host "[INFO] Skipped (new version cached: Claude-$newClaudeVersion.exe)" -ForegroundColor DarkGray
            return
        }

        Copy-Item -Path $tempFile -Destination $TargetExe -Force
        Write-Host "[OK] Updated: $installedVersion -> $newClaudeVersion" -ForegroundColor Green
        Write-Host "[OK] Locked: $newClaudeVersion/$latestSdk" -ForegroundColor Green
    } finally {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    Invoke-ClaudeConfig -Scope "update"
}

# ═══════════════════════════════════════════════════════════════════════════
# uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ClaudeUninstall {
    <#
    .SYNOPSIS
        Uninstall Claude Code by removing the binary from the bin directory.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-Path $TargetExe)) {
        Write-Host "[INFO] Claude Code not installed" -ForegroundColor Cyan
        return
    }

    $version = Get-InstalledVersion
    $label = if ($version) { "Claude Code $version" } else { "Claude Code" }

    Write-Host "[INFO] Uninstalling $label ..." -ForegroundColor Cyan

    try {
        Remove-Item $TargetExe -Force -ErrorAction Stop
        Write-Host "[OK] Removed: $TargetExe" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Could not remove: $_" -ForegroundColor Yellow
    }

    Write-Host "[OK] $label uninstalled" -ForegroundColor Green

    Write-Host "[INFO] Lock and download cache preserved:" -ForegroundColor DarkGray
    Write-Host "  Lock:  $script:ClaudeLockPath" -ForegroundColor DarkGray
    Write-Host "  Cache: $CacheDir" -ForegroundColor DarkGray
    Write-Host "  Config: $script:ClaudeJsonPath" -ForegroundColor DarkGray
}

# ═══════════════════════════════════════════════════════════════════════════
# hack — GUI Plugin Marketplace Manager
# ═══════════════════════════════════════════════════════════════════════════

function Get-ClaudeCliPath {
    <#
    .SYNOPSIS
        Resolve the path to claude.exe.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (Test-Path $TargetExe) { return $TargetExe }

    $found = Get-Command claude.exe -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
}

function Invoke-ClaudePluginCmd {
    <#
    .SYNOPSIS
        Run a claude plugin subcommand and return parsed JSON output.
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $claudeExe = Get-ClaudeCliPath
    if (-not $claudeExe) {
        throw "claude.exe not found — run 'omc install claude' first"
    }

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $claudeExe @Arguments 2>$null | Out-String
    $ErrorActionPreference = $prevEAP

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] claude exited with code $LASTEXITCODE" -ForegroundColor Yellow
    }

    $output = $output.Trim()
    if (-not $output) { return }

    $jsonStart = -1
    foreach ($c in '[{') {
        $idx = $output.IndexOf($c)
        if ($idx -ge 0 -and ($jsonStart -lt 0 -or $idx -lt $jsonStart)) {
            $jsonStart = $idx
        }
    }
    if ($jsonStart -lt 0) { return }
    if ($jsonStart -gt 0) { $output = $output.Substring($jsonStart) }
    if (-not $output) { return }

    try {
        return $output | ConvertFrom-Json
    } catch {
        Write-Host "[WARN] Could not parse JSON: $_" -ForegroundColor Yellow
    }
}

function Get-MarketplaceList {
    <#
    .SYNOPSIS
        Get registered marketplaces from the filesystem.
    #>
    [CmdletBinding()]
    [OutputType([PSObject[]])]
    param()

    $mpDir = Join-Path $env:USERPROFILE '.claude\plugins\marketplaces'
    $mps = @()

    if (-not (Test-Path $mpDir)) { return $mps }

    foreach ($dir in (Get-ChildItem -Path $mpDir -Directory -ErrorAction SilentlyContinue)) {
        $manifestPath = Join-Path $dir.FullName '.claude-plugin\marketplace.json'
        if (-not (Test-Path $manifestPath)) { continue }

        try {
            $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $repo = ""
            if ($manifest.repository -match 'github\.com/([^/]+/[^/"]+)') {
                $repo = $Matches[1]
            }
            $mps += [PSCustomObject]@{
                name            = $manifest.name
                source          = "github"
                repo            = $repo
                installLocation = $dir.FullName
            }
        } catch {}
    }

    return $mps
}

function Get-AvailablePlugins {
    <#
    .SYNOPSIS
        Get all available plugins from marketplace manifests, check installed/enabled from JSON files.
    #>
    [CmdletBinding()]
    [OutputType([PSObject[]])]
    param()

    $claudeDir = Join-Path $env:USERPROFILE '.claude'
    $mpDir = Join-Path $claudeDir 'plugins\marketplaces'
    $plugins = @()

    if (-not (Test-Path $mpDir)) { return $plugins }

    $installedIds = @{}
    $installedPath = Join-Path $claudeDir 'plugins\installed_plugins.json'
    if (Test-Path $installedPath) {
        try {
            $instJson = Get-Content $installedPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($instJson.plugins) {
                $instJson.plugins.PSObject.Properties | ForEach-Object {
                    $installedIds[$_.Name] = $true
                }
            }
        } catch {}
    }

    $enabledMap = @{}
    $settingsPath = Join-Path $claudeDir 'settings.json'
    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($settings.enabledPlugins) {
                $settings.enabledPlugins.PSObject.Properties | ForEach-Object {
                    $enabledMap[$_.Name] = [bool]$_.Value
                }
            }
        } catch {}
    }

    foreach ($dir in (Get-ChildItem -Path $mpDir -Directory -ErrorAction SilentlyContinue)) {
        $manifestPath = Join-Path $dir.FullName '.claude-plugin\marketplace.json'
        if (-not (Test-Path $manifestPath)) { continue }

        try {
            $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $mpName = $manifest.name
            if (-not $manifest.plugins) { continue }

            foreach ($p in $manifest.plugins) {
                $pluginId = "$($p.name)@$mpName"
                $plugins += [PSCustomObject]@{
                    id          = $pluginId
                    version     = $p.version
                    description = $p.description
                    installed   = [bool]$installedIds[$pluginId]
                    enabled     = if ($enabledMap.ContainsKey($pluginId)) { [bool]$enabledMap[$pluginId] } else { $false }
                }
            }
        } catch {}
    }

    return $plugins
}

function Show-InputDialog {
    <#
    .SYNOPSIS
        Show a generic input dialog and return the user input, or $null on cancel.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Label,

        [string]$DefaultValue = ''
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.ClientSize = New-Object System.Drawing.Size(400, 150)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Label
    $lbl.Location = New-Object System.Drawing.Point(12, 15)
    $lbl.AutoSize = $true

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Text = $DefaultValue
    $txt.Location = New-Object System.Drawing.Point(12, 40)
    $txt.Size = New-Object System.Drawing.Size(370, 24)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Bottom"
    $panel.Height = 45

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "OK"
    $btnOk.Size = New-Object System.Drawing.Size(90, 30)
    $btnOk.Location = New-Object System.Drawing.Point(210, 6)
    $btnOk.DialogResult = "OK"

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Size = New-Object System.Drawing.Size(90, 30)
    $btnCancel.Location = New-Object System.Drawing.Point(305, 6)
    $btnCancel.DialogResult = "Cancel"

    $panel.Controls.AddRange(@($btnOk, $btnCancel))
    $form.Controls.Add($panel)
    $form.Controls.Add($lbl)
    $form.Controls.Add($txt)
    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel

    if ($form.ShowDialog() -ne "OK") { return }

    $input = $txt.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($input)) { return }
    return $input
}

function Show-PluginManagerDialog {
    <#
    .SYNOPSIS
        Display the WinForms Plugin Marketplace Manager GUI.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Claude Plugin Manager"
    $form.ClientSize = New-Object System.Drawing.Size(900, 600)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = "Fill"
    $tabControl.Location = New-Object System.Drawing.Point(0, 0)

    # ── Tab 1: Marketplaces ──

    $tabMp = New-Object System.Windows.Forms.TabPage
    $tabMp.Text = "Marketplaces"
    $tabMp.UseVisualStyleBackColor = $true

    $gridMp = New-Object System.Windows.Forms.DataGridView
    $gridMp.Dock = "Fill"
    $gridMp.AllowUserToAddRows = $false
    $gridMp.AllowUserToDeleteRows = $false
    $gridMp.MultiSelect = $false
    $gridMp.SelectionMode = "FullRowSelect"
    $gridMp.RowHeadersVisible = $false
    $gridMp.BackgroundColor = [System.Drawing.Color]::White
    $gridMp.BorderStyle = "None"
    $gridMp.CellBorderStyle = "SingleHorizontal"
    $gridMp.GridColor = [System.Drawing.Color]::LightGray
    $gridMp.AutoGenerateColumns = $false
    $gridMp.ReadOnly = $true

    $colMpName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colMpName.HeaderText = "Name"
    $colMpName.Width = 120
    $colMpName.DataPropertyName = "name"
    $null = $gridMp.Columns.Add($colMpName)

    $colMpSource = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colMpSource.HeaderText = "Source"
    $colMpSource.Width = 80
    $colMpSource.DataPropertyName = "source"
    $null = $gridMp.Columns.Add($colMpSource)

    $colMpRepo = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colMpRepo.HeaderText = "Repo"
    $colMpRepo.Width = 250
    $colMpRepo.DataPropertyName = "repo"
    $null = $gridMp.Columns.Add($colMpRepo)

    $colMpUpdated = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colMpUpdated.HeaderText = "Last Updated"
    $colMpUpdated.AutoSizeMode = "Fill"
    $colMpUpdated.DataPropertyName = "lastUpdated"
    $null = $gridMp.Columns.Add($colMpUpdated)

    $btnPanelMp = New-Object System.Windows.Forms.Panel
    $btnPanelMp.Dock = "Bottom"
    $btnPanelMp.Height = 45

    $btnMpAdd = New-Object System.Windows.Forms.Button
    $btnMpAdd.Text = "Add Marketplace"
    $btnMpAdd.Size = New-Object System.Drawing.Size(140, 30)
    $btnMpAdd.Location = New-Object System.Drawing.Point(10, 7)

    $btnMpUpdateAll = New-Object System.Windows.Forms.Button
    $btnMpUpdateAll.Text = "Update All"
    $btnMpUpdateAll.Size = New-Object System.Drawing.Size(100, 30)
    $btnMpUpdateAll.Location = New-Object System.Drawing.Point(160, 7)

    $btnMpRemove = New-Object System.Windows.Forms.Button
    $btnMpRemove.Text = "Remove Selected"
    $btnMpRemove.Size = New-Object System.Drawing.Size(130, 30)
    $btnMpRemove.Location = New-Object System.Drawing.Point(270, 7)

    $btnPanelMp.Controls.AddRange(@($btnMpAdd, $btnMpUpdateAll, $btnMpRemove))
    $tabMp.Controls.Add($gridMp)
    $tabMp.Controls.Add($btnPanelMp)

    # ── Tab 2: Plugins ──

    $tabPl = New-Object System.Windows.Forms.TabPage
    $tabPl.Text = "Plugins"
    $tabPl.UseVisualStyleBackColor = $true

    $gridPl = New-Object System.Windows.Forms.DataGridView
    $gridPl.Dock = "Fill"
    $gridPl.AllowUserToAddRows = $false
    $gridPl.AllowUserToDeleteRows = $false
    $gridPl.MultiSelect = $false
    $gridPl.SelectionMode = "FullRowSelect"
    $gridPl.RowHeadersVisible = $false
    $gridPl.BackgroundColor = [System.Drawing.Color]::White
    $gridPl.BorderStyle = "None"
    $gridPl.CellBorderStyle = "SingleHorizontal"
    $gridPl.GridColor = [System.Drawing.Color]::LightGray
    $gridPl.AutoGenerateColumns = $false

    $colPlId = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colPlId.HeaderText = "Plugin ID"
    $colPlId.Width = 200
    $colPlId.ReadOnly = $true
    $colPlId.DataPropertyName = "id"
    $null = $gridPl.Columns.Add($colPlId)

    $colPlVer = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colPlVer.HeaderText = "Version"
    $colPlVer.Width = 70
    $colPlVer.ReadOnly = $true
    $colPlVer.DataPropertyName = "version"
    $null = $gridPl.Columns.Add($colPlVer)

    $colPlInstalled = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $colPlInstalled.HeaderText = "Installed"
    $colPlInstalled.Width = 70
    $colPlInstalled.ReadOnly = $true
    $colPlInstalled.DataPropertyName = "installed"
    $null = $gridPl.Columns.Add($colPlInstalled)

    $colPlEnabled = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $colPlEnabled.HeaderText = "Enabled"
    $colPlEnabled.Width = 65
    $colPlEnabled.ReadOnly = $true
    $colPlEnabled.DataPropertyName = "enabled"
    $null = $gridPl.Columns.Add($colPlEnabled)

    $colPlDesc = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colPlDesc.HeaderText = "Description"
    $colPlDesc.AutoSizeMode = "Fill"
    $colPlDesc.ReadOnly = $true
    $colPlDesc.DataPropertyName = "description"
    $null = $gridPl.Columns.Add($colPlDesc)

    $btnPanelPl = New-Object System.Windows.Forms.Panel
    $btnPanelPl.Dock = "Bottom"
    $btnPanelPl.Height = 45

    $btnPlInstall = New-Object System.Windows.Forms.Button
    $btnPlInstall.Text = "Install"
    $btnPlInstall.Size = New-Object System.Drawing.Size(90, 30)
    $btnPlInstall.Location = New-Object System.Drawing.Point(10, 7)

    $btnPlUninstall = New-Object System.Windows.Forms.Button
    $btnPlUninstall.Text = "Uninstall"
    $btnPlUninstall.Size = New-Object System.Drawing.Size(100, 30)
    $btnPlUninstall.Location = New-Object System.Drawing.Point(110, 7)

    $btnPlEnable = New-Object System.Windows.Forms.Button
    $btnPlEnable.Text = "Enable"
    $btnPlEnable.Size = New-Object System.Drawing.Size(80, 30)
    $btnPlEnable.Location = New-Object System.Drawing.Point(220, 7)

    $btnPlDisable = New-Object System.Windows.Forms.Button
    $btnPlDisable.Text = "Disable"
    $btnPlDisable.Size = New-Object System.Drawing.Size(80, 30)
    $btnPlDisable.Location = New-Object System.Drawing.Point(310, 7)

    $btnPanelPl.Controls.AddRange(@($btnPlInstall, $btnPlUninstall, $btnPlEnable, $btnPlDisable))
    $tabPl.Controls.Add($gridPl)
    $tabPl.Controls.Add($btnPanelPl)

    $tabControl.TabPages.Add($tabMp)
    $tabControl.TabPages.Add($tabPl)
    $form.Controls.Add($tabControl)

    # ── Status bar ──

    $statusBar = New-Object System.Windows.Forms.StatusStrip
    $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusLabel.Text = "Ready"
    $null = $statusBar.Items.Add($statusLabel)
    $form.Controls.Add($statusBar)

    # ── Refresh helpers ──

    function Refresh-Marketplaces {
        $statusLabel.Text = "Loading marketplaces..."
        $form.Refresh()

        $mps = Get-MarketplaceList
        $table = New-Object System.Data.DataTable
        $null = $table.Columns.Add("name")
        $null = $table.Columns.Add("source")
        $null = $table.Columns.Add("repo")
        $null = $table.Columns.Add("lastUpdated")

        foreach ($mp in $mps) {
            $manifestPath = Join-Path $mp.installLocation '.claude-plugin\marketplace.json'
            $lastUpdated = ""
            if (Test-Path $manifestPath) {
                try {
                    $fi = Get-Item $manifestPath
                    $lastUpdated = $fi.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                } catch {}
            }
            $row = $table.NewRow()
            $row["name"] = $mp.name
            $row["source"] = $mp.source
            $row["repo"] = $mp.repo
            $row["lastUpdated"] = $lastUpdated
            $table.Rows.Add($row) | Out-Null
        }

        $gridMp.DataSource = $table
        $statusLabel.Text = "$($mps.Count) marketplace(s)"
    }

    function Refresh-Plugins {
        $statusLabel.Text = "Loading plugins..."
        $form.Refresh()

        $plugins = Get-AvailablePlugins
        $table = New-Object System.Data.DataTable
        $null = $table.Columns.Add("id")
        $null = $table.Columns.Add("version")
        $null = $table.Columns.Add("installed", [bool])
        $null = $table.Columns.Add("enabled", [bool])
        $null = $table.Columns.Add("description")

        foreach ($p in $plugins) {
            $row = $table.NewRow()
            $row["id"] = $p.id
            $row["version"] = $p.version
            $row["installed"] = [bool]$p.installed
            $row["enabled"] = [bool]$p.enabled
            $row["description"] = $p.description
            $table.Rows.Add($row) | Out-Null
        }

        $gridPl.DataSource = $table
        $instCount = ($plugins | Where-Object { $_.installed }).Count
        $statusLabel.Text = "$instCount/$($plugins.Count) plugin(s) installed"
    }

    # ── Event handlers ──

    $tabControl.add_SelectedIndexChanged({
        if ($tabControl.SelectedIndex -eq 0) { Refresh-Marketplaces }
        else { Refresh-Plugins }
    })

    $btnMpAdd.add_Click({
        $repo = Show-InputDialog -Title "Add Marketplace" -Label "GitHub repo (e.g. owner/repo):" -DefaultValue "raystyle/Marketplaces"
        if (-not $repo) { return }

        $statusLabel.Text = "Adding marketplace $repo ..."
        $form.Refresh()
        $claudeExe = Get-ClaudeCliPath
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $claudeExe plugin marketplace add $repo 2>$null | Out-Null
        $ErrorActionPreference = $prevEAP
        Refresh-Marketplaces
    })

    $btnMpUpdateAll.add_Click({
        $mps = Get-MarketplaceList
        if ($mps.Count -eq 0) { return }

        $claudeExe = Get-ClaudeCliPath
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        foreach ($mp in $mps) {
            $statusLabel.Text = "Updating $($mp.name)..."
            $form.Refresh()
            & $claudeExe plugin marketplace update $mp.name 2>$null | Out-Null
        }
        $ErrorActionPreference = $prevEAP
        Refresh-Marketplaces
    })

    $gridMp.add_CellDoubleClick({
        param($sender, $e)
        if ($e.RowIndex -lt 0) { return }
        $name = $gridMp.Rows[$e.RowIndex].Cells[0].Value
        if (-not $name) { return }

        $statusLabel.Text = "Updating $name..."
        $form.Refresh()
        $claudeExe = Get-ClaudeCliPath
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $claudeExe plugin marketplace update $name 2>$null | Out-Null
        $ErrorActionPreference = $prevEAP
        Refresh-Marketplaces
    })

    $btnMpRemove.add_Click({
        if ($gridMp.SelectedRows.Count -eq 0) { return }
        $name = $gridMp.SelectedRows[0].Cells[0].Value
        if (-not $name) { return }

        $result = [System.Windows.Forms.MessageBox]::Show(
            "Remove marketplace '$name'?", "Confirm",
            "OKCancel", "Warning")
        if ($result -ne "OK") { return }

        $statusLabel.Text = "Removing $name..."
        $form.Refresh()
        $claudeExe = Get-ClaudeCliPath
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $claudeExe plugin marketplace remove $name 2>$null | Out-Null
        $ErrorActionPreference = $prevEAP
        Refresh-Marketplaces
    })

    $gridPl.add_CellDoubleClick({
        param($sender, $e)
        if ($e.RowIndex -lt 0) { return }
        $btnPlInstall.PerformClick()
    })

    $btnPlInstall.add_Click({
        if ($gridPl.SelectedRows.Count -eq 0) { return }
        $id = $gridPl.SelectedRows[0].Cells[0].Value
        $installed = $gridPl.SelectedRows[0].Cells[2].Value
        if (-not $id -or $installed) { return }

        $statusLabel.Text = "Installing $id ..."
        $form.Refresh()
        $claudeExe = Get-ClaudeCliPath
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $claudeExe plugin install $id 2>$null | Out-Null
        $ErrorActionPreference = $prevEAP
        Refresh-Plugins
    })

    $btnPlUninstall.add_Click({
        if ($gridPl.SelectedRows.Count -eq 0) { return }
        $id = $gridPl.SelectedRows[0].Cells[0].Value
        $installed = $gridPl.SelectedRows[0].Cells[2].Value
        if (-not $id -or -not $installed) { return }

        $result = [System.Windows.Forms.MessageBox]::Show(
            "Uninstall plugin '$id'?", "Confirm",
            "OKCancel", "Warning")
        if ($result -ne "OK") { return }

        $statusLabel.Text = "Uninstalling $id ..."
        $form.Refresh()
        $claudeExe = Get-ClaudeCliPath
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $claudeExe plugin uninstall $id 2>$null | Out-Null
        $ErrorActionPreference = $prevEAP
        Refresh-Plugins
    })

    $btnPlEnable.add_Click({
        if ($gridPl.SelectedRows.Count -eq 0) { return }
        $id = $gridPl.SelectedRows[0].Cells[0].Value
        $installed = $gridPl.SelectedRows[0].Cells[2].Value
        if (-not $id -or -not $installed) { return }

        $statusLabel.Text = "Enabling $id ..."
        $form.Refresh()
        $claudeExe = Get-ClaudeCliPath
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $claudeExe plugin enable $id 2>$null | Out-Null
        $ErrorActionPreference = $prevEAP
        Refresh-Plugins
    })

    $btnPlDisable.add_Click({
        if ($gridPl.SelectedRows.Count -eq 0) { return }
        $id = $gridPl.SelectedRows[0].Cells[0].Value
        $installed = $gridPl.SelectedRows[0].Cells[2].Value
        if (-not $id -or -not $installed) { return }

        $statusLabel.Text = "Disabling $id ..."
        $form.Refresh()
        $claudeExe = Get-ClaudeCliPath
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $claudeExe plugin disable $id 2>$null | Out-Null
        $ErrorActionPreference = $prevEAP
        Refresh-Plugins
    })

    # ── Initial load ──

    Refresh-Marketplaces
    Refresh-Plugins
    [void]$form.ShowDialog()
}

function Invoke-ClaudeHack {
    <#
    .SYNOPSIS
        Open the Plugin Marketplace Manager GUI.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $claudeExe = Get-ClaudeCliPath
    if (-not $claudeExe) {
        Write-Host "[ERROR] claude.exe not found — run 'omc install claude' first" -ForegroundColor Red
        return
    }

    $baseBin = Join-Path $script:OhmyRoot '.envs\base\bin'
    $gitCmd = Join-Path $script:OhmyRoot '.envs\base\git\cmd'
    if ($env:Path -notlike "*$baseBin*") { $env:Path = "$baseBin;$env:Path" }
    if ($env:Path -notlike "*$gitCmd*") { $env:Path = "$gitCmd;$env:Path" }

    $BuiltInMarketplaces = @('raystyle/Marketplaces', 'jarrodwatts/claude-hud')

    Write-Host "[INFO] Checking marketplaces..." -ForegroundColor Cyan

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $claudeExe plugin marketplace list --json 2>$null | Out-String
    $ErrorActionPreference = $prevEAP

    foreach ($repo in $BuiltInMarketplaces) {
        $escaped = [regex]::Escape($repo)
        if ($output -match "`"repo`"\s*:\s*`"$escaped`"") { continue }

        Write-Host "[INFO] Adding built-in marketplace $repo ..." -ForegroundColor Cyan
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $claudeExe plugin marketplace add $repo 2>$null | Out-Null
        $ErrorActionPreference = $prevEAP
    }

    Write-Host "[INFO] Updating marketplaces..." -ForegroundColor Cyan
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $claudeExe plugin marketplace list --json 2>$null | Out-String
    $ErrorActionPreference = $prevEAP

    $mpNames = [regex]::Matches($output, '"name"\s*:\s*"([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value }
    foreach ($mpName in $mpNames) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $claudeExe plugin marketplace update $mpName 2>$null | Out-Null
        $ErrorActionPreference = $prevEAP
    }

    Write-Host "[OK] Opening Plugin Manager..." -ForegroundColor Green

    Show-PluginManagerDialog
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch
# ═══════════════════════════════════════════════════════════════════════════

switch ($Command) {
    "check"     { Invoke-ClaudeCheck }
    "download"  { Invoke-ClaudeDownload }
    "install"   { Invoke-ClaudeInstall }
    "update"    { Invoke-ClaudeUpdate }
    "uninstall" { Invoke-ClaudeUninstall }
    "setup"     { Invoke-ClaudeConfig -Scope "setup" -Force:$Force }
    "hack"      { Invoke-ClaudeHack }
}
