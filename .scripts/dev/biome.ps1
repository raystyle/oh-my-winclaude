#Requires -Version 5.1

<#
.SYNOPSIS
    Install Biome (JS/TS linter & formatter) for Claude Code via npm + shim exe.
.PARAMETER Command
    Action: check, install, update, uninstall, download.
.PARAMETER Version
    Reserved for future pinning.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Version', Justification = 'Reserved for future pinning')]
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("check", "download", "install", "update", "uninstall")]
    [string]$Command = "check",

    [Parameter(Position = 1)]
    [AllowEmptyString()]
    [string]$Version = ""
)

. "$PSScriptRoot\..\helpers.ps1"

Update-Environment

$ErrorActionPreference = "Stop"

$script:OhmyRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$NodeDir        = "$script:OhmyRoot\.envs\dev\node"
$NodeExe        = "$NodeDir\node.exe"
$NpmCmd         = "$NodeDir\npm.cmd"
$BiomePkgDir    = "$NodeDir\node_modules\@biomejs\biome"
$BiomeBinPath   = "$BiomePkgDir\bin\biome"
$ShimExePath    = "$NodeDir\biome.exe"
$ShimConfigPath = [System.IO.Path]::ChangeExtension($ShimExePath, ".shim")
$OmcExe         = Join-Path $script:OhmyRoot "omc.exe"

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-BiomeCheck {
    <#
    .SYNOPSIS
        Display Biome installation status.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- Biome ---" -ForegroundColor Cyan

    # Node.js
    if (Test-Path $NodeExe) {
        $nodeVer = (& $NodeExe --version 2>$null | Out-String).Trim()
        Write-Host "[OK] Node.js $nodeVer" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Node.js not found" -ForegroundColor Yellow
        Write-Host "  Run 'omc install node' first" -ForegroundColor DarkGray
        return
    }

    # npm
    if (Test-Path $NpmCmd) {
        $npmVer = (& $NpmCmd --version 2>$null | Out-String).Trim()
        Write-Host "[OK] npm $npmVer" -ForegroundColor Green
    } else {
        Write-Host "[WARN] npm not found" -ForegroundColor Yellow
        return
    }

    # biome package
    if (Test-Path $BiomeBinPath) {
        $biomeVer = (& $NodeExe $BiomeBinPath --version 2>$null | Out-String).Trim()
        Write-Host "[OK] biome $biomeVer" -ForegroundColor Green
    } else {
        Show-NotInstalled -Tool "biome"
        return
    }

    # shim exe
    if ((Test-Path $ShimExePath) -and (Test-Path $ShimConfigPath)) {
        Write-Host "[OK] Shim: $ShimExePath" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Shim not deployed" -ForegroundColor Cyan
        Write-Host "  Run 'omc install biome' to create shim" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# install
# ═══════════════════════════════════════════════════════════════════════════

function Install-BiomeShim {
    <#
    .SYNOPSIS
        Deploy shim exe by copying omc.exe and creating .shim config.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-Path $OmcExe)) {
        throw "omc.exe not found at $OmcExe — cannot create shim"
    }

    # Idempotent: skip if shim already points to correct target
    if ((Test-Path $ShimExePath) -and (Test-Path $ShimConfigPath)) {
        $existing = (Get-Content $ShimConfigPath -Raw -ErrorAction SilentlyContinue).Trim()
        if ($existing -match [regex]::Escape("path = $NodeExe") -and $existing -match [regex]::Escape("args = $BiomeBinPath")) {
            Show-AlreadyInstalled -Tool "shim: biome.exe" -Location $ShimExePath
            return
        }
    }

    # Copy omc.exe as shim binary
    Copy-Item -Path $OmcExe -Destination $ShimExePath -Force

    # Create .shim config
    $shimLines = @("path = $NodeExe", "args = $BiomeBinPath")
    Set-Content -Path $ShimConfigPath -Value ($shimLines -join "`n") -NoNewline -Encoding UTF8

    Show-InstallSuccess -Component "shim: biome.exe" -Location $ShimExePath
}

function Invoke-BiomeInstall {
    <#
    .SYNOPSIS
        Install Biome via npm and deploy shim exe.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # ---- 1. Guard: Node.js + npm ----
    if (-not (Test-Path $NodeExe)) {
        Write-Host "[ERROR] Node.js not found" -ForegroundColor Red
        Write-Host "  Run 'omc install node' first" -ForegroundColor DarkGray
        exit 1
    }
    if (-not (Test-Path $NpmCmd)) {
        Write-Host "[ERROR] npm not found" -ForegroundColor Red
        exit 1
    }

    # ---- 2. Guard: already installed ----
    if (Test-Path $BiomeBinPath) {
        $biomeVer = (& $NodeExe $BiomeBinPath --version 2>$null | Out-String).Trim()
        Show-AlreadyInstalled -Tool "biome" -Version $biomeVer
        Install-BiomeShim
        return
    }

    # ---- 3. Install via npm ----
    Show-Installing -Component "@biomejs/biome (npm)"

    & $NpmCmd install -g @biomejs/biome 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] npm install failed" -ForegroundColor Red
        exit 1
    }

    # ---- 4. Verify npm install ----
    if (-not (Test-Path $BiomeBinPath)) {
        Write-Host "[ERROR] @biomejs/biome not found after npm install" -ForegroundColor Red
        exit 1
    }

    $biomeVer = (& $NodeExe $BiomeBinPath --version 2>$null | Out-String).Trim()
    Write-Host "[OK] biome $biomeVer installed" -ForegroundColor Green

    # ---- 5. Deploy shim ----
    Install-BiomeShim

    # ---- 6. Summary ----
    Show-InstallComplete -Tool "Biome" -Version $biomeVer
}

# ═══════════════════════════════════════════════════════════════════════════
# update
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-BiomeUpdate {
    <#
    .SYNOPSIS
        Update Biome via npm and re-verify shim.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-Path $NpmCmd)) {
        Write-Host "[ERROR] npm not found" -ForegroundColor Red
        return
    }

    if (-not (Test-Path $BiomeBinPath)) {
        Write-Host "[INFO] biome not installed" -ForegroundColor Cyan
        Write-Host "  Run 'omc install biome' first" -ForegroundColor DarkGray
        return
    }

    Write-Host "[INFO] Updating @biomejs/biome..." -ForegroundColor Cyan
    & $NpmCmd update -g @biomejs/biome 2>&1 | Out-Null

    if (Test-Path $BiomeBinPath) {
        $biomeVer = (& $NodeExe $BiomeBinPath --version 2>$null | Out-String).Trim()
        Write-Host "[OK] biome $biomeVer" -ForegroundColor Green
    }

    # Re-deploy shim (idempotent)
    Install-BiomeShim
}

# ═══════════════════════════════════════════════════════════════════════════
# download — npm managed, no separate download
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-BiomeDownload {
    <#
    .SYNOPSIS
        Display download info; Biome is npm managed with no separate download.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host "[INFO] Biome uses 'npm install -g' -- no separate download." -ForegroundColor Cyan
}

# ═══════════════════════════════════════════════════════════════════════════
# uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-BiomeUninstall {
    <#
    .SYNOPSIS
        Uninstall Biome: remove shim, then npm uninstall.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Show-UninstallHeader -DisplayName "Biome"

    # ---- 1. Remove shim ----
    Remove-ShimExe -TargetExePath $ShimExePath

    # ---- 2. npm uninstall ----
    if (Test-Path $NpmCmd) {
        if (Test-Path $BiomePkgDir) {
            Write-Host "[INFO] Removing npm package..." -ForegroundColor Cyan
            & $NpmCmd uninstall -g @biomejs/biome 2>&1 | Out-Null
        } else {
            Write-Host "[INFO] npm package not found, skipping npm uninstall" -ForegroundColor Cyan
        }
    } else {
        Write-Host "[INFO] npm not found, skipping npm uninstall" -ForegroundColor Cyan
    }

    Show-UninstallComplete -Tool "Biome"
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch
# ═══════════════════════════════════════════════════════════════════════════

switch ($Command) {
    "check"     { Invoke-BiomeCheck }
    "download"  { Invoke-BiomeDownload }
    "install"   { Invoke-BiomeInstall }
    "update"    { Invoke-BiomeUpdate }
    "uninstall" { Invoke-BiomeUninstall }
}
