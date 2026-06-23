#Requires -Version 5.1

<#
.SYNOPSIS
    Manage VS Build Tools offline layout cache for installation.
.PARAMETER Command
    Action: check, download, update, install.
.PARAMETER Force
    Skip confirmation.
#>

[CmdletBinding()]
param(
    [ValidateSet("check", "download", "update", "install", "uninstall")]
    [string]$Command = "check",

    [switch]$Force
)

. "$PSScriptRoot\..\helpers.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$VSDir         = Split-Path $script:VSBuildTools_Bootstrapper -Parent
$Bootstrapper  = $script:VSBuildTools_Bootstrapper
$LayoutDir     = Join-Path $VSDir "VSLayout"
$CacheDir      = $script:VSBuildTools_CacheDir
$TimeoutMs     = 3600000

function Get-LayoutVersion {
    <#
    .SYNOPSIS
        Read the version of the VS Build Tools offline layout bootstrapper.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $layoutBs = Join-Path $LayoutDir "vs_buildtools.exe"
    if (-not (Test-Path $layoutBs)) { $null; return }
    try {
        $ver = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($layoutBs)
        "$($ver.FileMajorPart).$($ver.FileMinorPart).$($ver.FileBuildPart)"
    } catch { $null }
}

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-VSCheck {
    <#
    .SYNOPSIS
        Display VS Build Tools installation status, compiler, SDK, and layout cache info.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- VS Build Tools ---" -ForegroundColor Cyan

    $installRoot = $script:VSBuildTools_InstallPath

    # ── 1. vswhere detection ──
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $installPath = $null
    $installVersion = $null

    if (Test-Path $vswhere) {
        $installPath = & $vswhere -prerelease -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath 2>$null | Select-Object -First 1
        $installVersion = & $vswhere -prerelease -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationVersion 2>$null | Select-Object -First 1
    }

    # ── 2. Filesystem fallback ──
    if (-not $installPath) {
        $cl = Get-ChildItem "$installRoot\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($cl) { $installPath = $installRoot }
    }

    if ($installPath) {
        Write-Host "[OK] Installed" -ForegroundColor Green
        Write-Host "  Location:        $installPath" -ForegroundColor DarkGray
        if ($installVersion) {
            Write-Host "  Version:         $installVersion" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "[INFO] VS Build Tools not installed" -ForegroundColor Cyan
        Write-Host "  Run 'omc install vsbuild' to install" -ForegroundColor DarkGray
    }

    # ── 3. MSVC compiler ──
    if ($installPath) {
        $msvcDir = Get-ChildItem "$installPath\VC\Tools\MSVC" -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+' } |
            Select-Object -First 1
        if ($msvcDir) {
            Write-Host "  MSVC:            $($msvcDir.Name)" -ForegroundColor DarkGray
        } else {
            Write-Host "  MSVC:            not found" -ForegroundColor DarkGray
        }

        # ── 4. link.exe (linker) ──
        $linkExe = Get-ChildItem "$installPath\VC\Tools\MSVC" -Recurse -Filter "link.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -match 'Hostx64\\x64' } |
            Select-Object -First 1
        if ($linkExe) {
            Write-Host "  link.exe:        OK" -ForegroundColor DarkGray
        } else {
            Write-Host "  link.exe:        not found" -ForegroundColor DarkGray
        }
    }

    # ── 5. Windows SDK ──
    $kitsRoot = $null
    foreach ($reg in @(
        "HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
    )) {
        if (Test-Path $reg) {
            $obj = Get-ItemProperty $reg -ErrorAction SilentlyContinue
            if ($obj -and $obj.PSObject.Properties['KitsRoot10']) {
                $r = $obj.KitsRoot10
                if ($r -and (Test-Path $r)) { $kitsRoot = $r; break }
            }
        }
    }

    $sdkVersion = $null
    if ($kitsRoot -and (Test-Path "$kitsRoot\Include")) {
        $sdkDir = Get-ChildItem "$kitsRoot\Include" -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($sdkDir) { $sdkVersion = $sdkDir.Name }
    }
    if ($sdkVersion) {
        Write-Host "  Windows SDK:     $sdkVersion" -ForegroundColor DarkGray
    } else {
        Write-Host "  Windows SDK:     not found" -ForegroundColor DarkGray
    }

    # ── 6. COM DLL status (vswhere dependency) ──
    $comDll = Get-ChildItem "C:\ProgramData\Microsoft\VisualStudio\Setup" -Recurse -Filter "Microsoft.VisualStudio.Setup.Configuration.Native.dll" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if ($comDll) {
        Write-Host "  COM DLL:         OK" -ForegroundColor DarkGray
    } else {
        Write-Host "  COM DLL:         not found (vswhere may not work)" -ForegroundColor DarkGray
    }

    # ── 7. vswhere hint ──
    if (-not (Test-Path $vswhere)) {
        Write-Host "  vswhere:         not found" -ForegroundColor DarkGray
    } elseif (-not $installVersion) {
        Write-Host "  vswhere:         instance not registered" -ForegroundColor DarkGray
    }

    # ── 8. Disk usage ──
    if ($installPath -and (Test-Path $installPath)) {
        $size = (Get-ChildItem $installPath -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if ($size) {
            Write-Host "  Disk:            $([Math]::Round($size / 1GB, 2)) GB" -ForegroundColor DarkGray
        }
    }

    # ── 9. Layout cache summary ──
    $layoutBootstrapper = Join-Path $LayoutDir "vs_buildtools.exe"
    if (Test-Path $layoutBootstrapper) {
        $ver = Get-LayoutVersion
        Write-Host ""
        Write-Host "  Layout:          $LayoutDir" -ForegroundColor DarkGray
        Write-Host "  Layout version:  $ver" -ForegroundColor DarkGray
    } else {
        Write-Host ""
        Write-Host "  Layout:          not created (run 'omc download vsbuild')" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# download — create offline layout
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-VSDownload {
    <#
    .SYNOPSIS
        Create an offline layout of VS Build Tools for cached installation.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $layoutBootstrapper = Join-Path $LayoutDir "vs_buildtools.exe"

    if ((Test-Path $layoutBootstrapper) -and -not $Force) {
        Write-Host "[OK] VS Build Tools Layout already exists" -ForegroundColor Green
        Write-Host "      $LayoutDir  (use -Force to re-create)" -ForegroundColor DarkGray
        return
    }

    Write-Host ""
    Write-Host "--- VS Build Tools Layout ---" -ForegroundColor Cyan
    Write-Host ""

    # ── 1. Create directories ──
    Write-Host "[INFO] Creating directories..." -ForegroundColor Cyan
    $null = New-Item -Path $VSDir -ItemType Directory -Force
    $null = New-Item -Path $CacheDir -ItemType Directory -Force
    Write-Host "[OK] Directories created" -ForegroundColor Green

    # ── 2. Download bootstrapper ──
    Write-Host ""
    Write-Host "[INFO] Downloading VS Build Tools bootstrapper..." -ForegroundColor Cyan
    $bootstrapperUrl = "https://aka.ms/vs/17/release/vs_buildtools.exe"

    if (-not (Test-Path $Bootstrapper)) {
        Write-Host "  URL: $bootstrapperUrl" -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $bootstrapperUrl -OutFile $Bootstrapper -MaximumRedirection 5 -ErrorAction Stop
        Write-Host "[OK] Downloaded to $Bootstrapper" -ForegroundColor Green
    } else {
        Write-Host "[OK] Bootstrapper already exists: $Bootstrapper" -ForegroundColor Green
    }

    # ── 3. Create layout ──
    Write-Host ""
    Write-Host "[INFO] Creating offline layout..." -ForegroundColor Cyan
    Write-Host "  Layout: $LayoutDir" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[INFO] This will download ~3-5 GB and may take 10-30 minutes..." -ForegroundColor Yellow
    Write-Host ""

    $layoutArgs = @(
        "--layout", "VSLayout",
        "--lang", "en-US",
        "--add", "Microsoft.VisualStudio.Workload.VCTools",
        "--add", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "--add", "Microsoft.VisualStudio.Component.Windows11SDK.26100",
        "--includeRecommended",
        "--wait"
    )

    $proc = Start-Process -FilePath $Bootstrapper -ArgumentList $layoutArgs `
        -WorkingDirectory $VSDir -NoNewWindow -PassThru
    $null = $proc.Handle

    if (-not $proc.WaitForExit($TimeoutMs)) {
        try { $proc.Kill() } catch { }
        Write-Host "[ERROR] Layout creation timed out ($([Math]::Round($TimeoutMs / 60000)) min)" -ForegroundColor Red
        exit 1
    }

    switch ($proc.ExitCode) {
        0 {
            $ver = Get-LayoutVersion
            Write-Host ""
            Write-Host "[OK] Layout created successfully" -ForegroundColor Green
            Write-Host "  Location: $LayoutDir" -ForegroundColor DarkGray
            if ($ver) { Write-Host "  Version: $ver" -ForegroundColor DarkGray }
        }
        default {
            Write-Host ""
            Write-Host "[ERROR] Layout creation failed (exit code $($proc.ExitCode))" -ForegroundColor Red
            Write-Host "  Check logs: %TEMP%\dd_*.log" -ForegroundColor DarkGray
            exit 1
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# install — run setup from offline layout
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-VSInstall {
    <#
    .SYNOPSIS
        Install VS Build Tools from the offline layout with elevation.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $layoutBootstrapper = Join-Path $LayoutDir "vs_buildtools.exe"

    if (-not (Test-Path $layoutBootstrapper)) {
        Write-Host ""
        Write-Host "[INFO] Offline layout not found, downloading first..." -ForegroundColor Cyan
        Invoke-VSDownload
        if (-not (Test-Path $layoutBootstrapper)) {
            Write-Host "[ERROR] Layout download failed" -ForegroundColor Red
            exit 1
        }
    }

    # ── Elevate if not admin ──
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "[INFO] Elevating to admin for installation..." -ForegroundColor Yellow
        $argList = @(
            "-NoLogo", "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $PSCommandPath,
            "install"
        )
        if ($Force) { $argList += "-Force" }
        $proc = Start-Process powershell -Verb RunAs -ArgumentList $argList -Wait -PassThru
        exit $proc.ExitCode
    }

    Write-Host ""
    Write-Host "--- VS Build Tools Install ---" -ForegroundColor Cyan
    Write-Host ""

    # ── Resolve layout path as absolute ──
    $resolvedLayout = Resolve-Path $LayoutDir -ErrorAction Stop
    Write-Host "  Layout: $resolvedLayout" -ForegroundColor DarkGray
    Write-Host ""

    $installArgs = @(
        "--noWeb",
        "--installPath", $script:VSBuildTools_InstallPath,
        "--add", "Microsoft.VisualStudio.Workload.VCTools",
        "--add", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "--add", "Microsoft.VisualStudio.Component.Windows11SDK.26100",
        "--includeRecommended",
        "--quiet", "--norestart"
    )

    Write-Host "[INFO] Running installer (this may take 10-30 minutes)..." -ForegroundColor Cyan
    Write-Host "  Target: $script:VSBuildTools_InstallPath" -ForegroundColor DarkGray
    Write-Host ""

    $proc = Start-Process -FilePath $layoutBootstrapper -ArgumentList $installArgs `
        -NoNewWindow -PassThru
    $null = $proc.Handle

    if (-not $proc.WaitForExit($TimeoutMs)) {
        try { $proc.Kill() } catch { }
        Write-Host "[ERROR] Installation timed out ($([Math]::Round($TimeoutMs / 60000)) min)" -ForegroundColor Red
        exit 1
    }

    switch ($proc.ExitCode) {
        0 {
            Write-Host ""
            Write-Host "[OK] VS Build Tools installed successfully" -ForegroundColor Green
            Write-Host "  Location: $script:VSBuildTools_InstallPath" -ForegroundColor DarkGray
        }
        3010 {
            Write-Host ""
            Write-Host "[OK] VS Build Tools installed (restart required)" -ForegroundColor Green
            Write-Host "  Location: $script:VSBuildTools_InstallPath" -ForegroundColor DarkGray
            Write-Host "[INFO] Please restart your computer to finalize" -ForegroundColor Yellow
        }
        default {
            Write-Host ""
            Write-Host "[ERROR] Installation failed (exit code $($proc.ExitCode))" -ForegroundColor Red
            Write-Host "  Check logs: %TEMP%\dd_*.log" -ForegroundColor DarkGray
            exit 1
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-VSUninstall {
    <#
    .SYNOPSIS
        Uninstall VS Build Tools using InstallCleanup and remove residual directories.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $shell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
    $logFile = Join-Path $env:TEMP "vsbt_uninstall.log"

    $installDir = $script:VSBuildTools_InstallPath
    $cleanup = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\InstallCleanup.exe"
    if (-not (Test-Path $installDir) -and -not (Test-Path $cleanup)) {
        Write-Host '[INFO] VS Build Tools not installed, nothing to uninstall' -ForegroundColor Cyan
        return
    }

    # Helper: write to both console and log file (avoid transcript noise)
    function Write-Log {
        <#
        .SYNOPSIS
            Write a message to the uninstall log file and optionally to the console.
        #>
        [CmdletBinding()]
        [OutputType([void])]
        param(
            [Parameter(Mandatory)]
            [string]$Message,

            [string]$ForegroundColor
        )

        $Message | Out-File -FilePath $logFile -Append -Encoding UTF8
        if ($ForegroundColor) {
            Microsoft.PowerShell.Utility\Write-Host $Message -ForegroundColor $ForegroundColor
        } else {
            Microsoft.PowerShell.Utility\Write-Host $Message
        }
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "[INFO] Elevating to admin..." -ForegroundColor Yellow
        Remove-Item $logFile -Force -ErrorAction SilentlyContinue

        $argList = @(
            "-NoLogo", "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $PSCommandPath,
            "uninstall"
        )
        if ($Force) { $argList += "-Force" }
        $proc = Start-Process $shell -Verb RunAs -ArgumentList $argList -Wait -PassThru

        if (Test-Path $logFile) {
            Get-Content $logFile -ErrorAction SilentlyContinue
            Remove-Item $logFile -Force -ErrorAction SilentlyContinue
        }
        exit $proc.ExitCode
    }

    Remove-Item $logFile -Force -ErrorAction SilentlyContinue

    try {
        Write-Host ""
        Write-Log "=== Uninstall VS Build Tools ===" -ForegroundColor Cyan
        Write-Host ""

        # ── Step 1: InstallCleanup.exe -full ──
        if (Test-Path $cleanup) {
            Write-Log "[INFO] Running InstallCleanup.exe -full ..." -ForegroundColor Cyan
            $proc = Start-Process -FilePath $cleanup -ArgumentList "-full" -NoNewWindow -PassThru -Wait
            Write-Log "[OK] InstallCleanup completed (exit $($proc.ExitCode))" -ForegroundColor Green
        } else {
            Write-Log "[WARN] InstallCleanup.exe not found, skipping" -ForegroundColor Yellow
        }

        # ── Step 2: Remove install directory ──
        if (Test-Path $installDir) {
            Write-Log "[INFO] Removing $installDir ..." -ForegroundColor Cyan
            Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "[OK] Removed" -ForegroundColor Green
        }

        # ── Step 3: Remove shared directory ──
        $sharedDir = Join-Path $script:VSBuildTools_InstallPath "_shared"
        if (Test-Path $sharedDir) {
            Write-Log "[INFO] Removing $sharedDir ..." -ForegroundColor Cyan
            Remove-Item $sharedDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "[OK] Removed" -ForegroundColor Green
        }

        # ── Step 4: Remove _Instances ──
        $instancesDir = "C:\ProgramData\Microsoft\VisualStudio\Packages\_Instances"
        if (Test-Path $instancesDir) {
            Write-Log "[INFO] Removing _Instances ..." -ForegroundColor Cyan
            Remove-Item $instancesDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "[OK] Removed" -ForegroundColor Green
        }

        Write-Host ""
        Write-Log "[OK] VS Build Tools uninstall complete" -ForegroundColor Green
        Write-Log "  Layout preserved at: $LayoutDir" -ForegroundColor DarkGray

    } catch {
        Write-Log "  [ERROR] $_" -ForegroundColor Red
        exit 1
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch
# ═══════════════════════════════════════════════════════════════════════════

switch ($Command) {
    "check"    { Invoke-VSCheck }
    "download" { Invoke-VSDownload }
    "update"   { Invoke-VSDownload }
    "install"  { Invoke-VSInstall }
    "uninstall" { Invoke-VSUninstall }
}
