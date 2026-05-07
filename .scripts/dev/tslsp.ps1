#Requires -Version 5.1

<#
.SYNOPSIS
    Install TypeScript LSP (typescript-language-server) for Claude Code via npm + shim exe.
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
$NodeDir       = "$script:OhmyRoot\.envs\dev\node"
$NodeExe       = "$NodeDir\node.exe"
$NpmCmd        = "$NodeDir\npm.cmd"
$TslspPkgDir   = "$NodeDir\node_modules\typescript-language-server"
$CliMjsPath    = "$TslspPkgDir\lib\cli.mjs"
$ShimExePath   = "$NodeDir\typescript-language-server.exe"
$ShimConfigPath = [System.IO.Path]::ChangeExtension($ShimExePath, ".shim")
$OmcExe        = Join-Path $script:OhmyRoot "omc.exe"

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-TslspCheck {
    <#
    .SYNOPSIS
        Display TypeScript LSP installation status.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- TypeScript LSP ---" -ForegroundColor Cyan

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

    # typescript-language-server package
    if (Test-Path $CliMjsPath) {
        $tslsVer = (& $NodeExe $CliMjsPath --version 2>$null | Out-String).Trim()
        Write-Host "[OK] typescript-language-server $tslsVer" -ForegroundColor Green
    } else {
        Show-NotInstalled -Tool "typescript-language-server"
        return
    }

    # shim exe
    if ((Test-Path $ShimExePath) -and (Test-Path $ShimConfigPath)) {
        Write-Host "[OK] Shim: $ShimExePath" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Shim not deployed" -ForegroundColor Cyan
        Write-Host "  Run 'omc install tslsp' to create shim" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# install
# ═══════════════════════════════════════════════════════════════════════════

function Install-TslspShim {
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
        if ($existing -match [regex]::Escape("path = $NodeExe")) {
            Show-AlreadyInstalled -Tool "shim: typescript-language-server.exe" -Location $ShimExePath
            return
        }
    }

    # Copy omc.exe as shim binary
    Copy-Item -Path $OmcExe -Destination $ShimExePath -Force

    # Create .shim config
    $shimLines = @("path = $NodeExe", "args = $CliMjsPath")
    Set-Content -Path $ShimConfigPath -Value ($shimLines -join "`n") -NoNewline -Encoding UTF8

    Show-InstallSuccess -Component "shim: typescript-language-server.exe" -Location $ShimExePath
}

function Invoke-TslspInstall {
    <#
    .SYNOPSIS
        Install typescript-language-server via npm and deploy shim exe.
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
    if (Test-Path $CliMjsPath) {
        $tslsVer = (& $NodeExe $CliMjsPath --version 2>$null | Out-String).Trim()
        Show-AlreadyInstalled -Tool "typescript-language-server" -Version $tslsVer
        # Still ensure shim is deployed
        Install-TslspShim
        return
    }

    # ---- 3. Install via npm ----
    Show-Installing -Component "typescript-language-server + typescript (npm)"

    & $NpmCmd install -g typescript-language-server typescript 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] npm install failed" -ForegroundColor Red
        exit 1
    }

    # ---- 4. Verify npm install ----
    if (-not (Test-Path $CliMjsPath)) {
        Write-Host "[ERROR] typescript-language-server not found after npm install" -ForegroundColor Red
        exit 1
    }

    $tslsVer = (& $NodeExe $CliMjsPath --version 2>$null | Out-String).Trim()
    Write-Host "[OK] typescript-language-server $tslsVer installed" -ForegroundColor Green

    # ---- 5. Deploy shim ----
    Install-TslspShim

    # ---- 6. Summary ----
    Show-InstallComplete -Tool "TypeScript LSP" -Version $tslsVer
}

# ═══════════════════════════════════════════════════════════════════════════
# update
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-TslspUpdate {
    <#
    .SYNOPSIS
        Update typescript-language-server via npm and re-verify shim.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-Path $NpmCmd)) {
        Write-Host "[ERROR] npm not found" -ForegroundColor Red
        return
    }

    if (-not (Test-Path $CliMjsPath)) {
        Write-Host "[INFO] typescript-language-server not installed" -ForegroundColor Cyan
        Write-Host "  Run 'omc install tslsp' first" -ForegroundColor DarkGray
        return
    }

    Write-Host "[INFO] Updating typescript-language-server..." -ForegroundColor Cyan
    & $NpmCmd update -g typescript-language-server typescript 2>&1 | Out-Null

    if (Test-Path $CliMjsPath) {
        $tslsVer = (& $NodeExe $CliMjsPath --version 2>$null | Out-String).Trim()
        Write-Host "[OK] typescript-language-server $tslsVer" -ForegroundColor Green
    }

    # Re-deploy shim (idempotent)
    Install-TslspShim
}

# ═══════════════════════════════════════════════════════════════════════════
# download — npm managed, no separate download
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-TslspDownload {
    <#
    .SYNOPSIS
        Display download info; TypeScript LSP is npm managed with no separate download.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host "[INFO] TypeScript LSP uses 'npm install -g' -- no separate download." -ForegroundColor Cyan
}

# ═══════════════════════════════════════════════════════════════════════════
# uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-TslspUninstall {
    <#
    .SYNOPSIS
        Uninstall TypeScript LSP: remove shim, then npm uninstall.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Show-UninstallHeader -DisplayName "TypeScript LSP"

    # ---- 1. Remove shim ----
    Remove-ShimExe -TargetExePath $ShimExePath

    # ---- 2. npm uninstall ----
    if (Test-Path $NpmCmd) {
        if (Test-Path $TslspPkgDir) {
            Write-Host "[INFO] Removing npm package..." -ForegroundColor Cyan
            & $NpmCmd uninstall -g typescript-language-server typescript 2>&1 | Out-Null
        } else {
            Write-Host "[INFO] npm package not found, skipping npm uninstall" -ForegroundColor Cyan
        }
    } else {
        Write-Host "[INFO] npm not found, skipping npm uninstall" -ForegroundColor Cyan
    }

    Show-UninstallComplete -Tool "TypeScript LSP"
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch
# ═══════════════════════════════════════════════════════════════════════════

switch ($Command) {
    "check"     { Invoke-TslspCheck }
    "download"  { Invoke-TslspDownload }
    "install"   { Invoke-TslspInstall }
    "update"    { Invoke-TslspUpdate }
    "uninstall" { Invoke-TslspUninstall }
}
