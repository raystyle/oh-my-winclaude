#Requires -Version 5.1

<#
.SYNOPSIS
    Manage uv + Python dev environment.
.DESCRIPTION
    Part of base init layer. Independent of helpers.ps1/core.ps1.
    Installs uv from GitHub releases, uses uv to manage Python,
    configures pip and uv mirrors (aliyun). Hash and asset metadata
    stored in config JSON, not sidecar files.
.PARAMETER Command
    Action: check, download, init, install, update, uninstall.
.PARAMETER PythonVersion
    Python version to install. Default: 3.14.4
#>

[CmdletBinding()]
param(
    [ValidateSet('check', 'download', 'init', 'install', 'update', 'uninstall')]
    [string]$Command = 'check',

    [string]$PythonVersion = '3.14.4'
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\helpers.ps1"

$script:OhmyRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:BaseBin    = Join-Path $script:OhmyRoot '.envs\base\bin'
$script:CacheDir   = Join-Path $script:OhmyRoot '.cache\base\uv'
$script:ConfigPath = Join-Path $script:OhmyRoot '.config\uv\config.json'
$script:UTF8NoBOM = New-Object System.Text.UTF8Encoding $false

$uvExe       = Join-Path $script:BaseBin 'uv.exe'
$UvCacheDir  = Join-Path $script:OhmyRoot '.envs\base\uv-cache'
$UvPyDir     = Join-Path $script:OhmyRoot '.envs\base\uv-python'
$UvToolDir   = Join-Path $script:OhmyRoot '.envs\base\uv-tools'

$pipMirror   = "https://mirrors.aliyun.com/pypi/simple"
$uvMirrorUrl = "https://mirrors.aliyun.com/pypi/simple"

$UvRepo      = "astral-sh/uv"

$UvEnvVars = [ordered]@{
    'UV_CACHE_DIR'                = $UvCacheDir
    'UV_PYTHON_INSTALL_DIR'       = $UvPyDir
    'UV_PYTHON_BIN_DIR'           = $script:BaseBin
    'UV_PYTHON_INSTALL_MIRROR'    = 'https://mirror.nju.edu.cn/github-release/astral-sh/python-build-standalone/'
    'UV_TOOL_DIR'                 = $UvToolDir
    'UV_TOOL_BIN_DIR'             = $script:BaseBin
    'UV_INSTALL_DIR'              = $script:BaseBin
}

# ═══════════════════════════════════════════════════════════════════════════
# Config helpers
# ═══════════════════════════════════════════════════════════════════════════

function Get-UvConfig {
    <#
    .SYNOPSIS
        Read uv config from .config/uv.json.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if (Test-Path $script:ConfigPath) {
        try {
            $json = Get-Content $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $ht = @{}
            $json.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
            # Backward compat: old field names
            if (-not $ht.lock -and $ht.uv_version) { $ht['lock'] = $ht.uv_version }
            if (-not $ht.asset -and $ht.uv_asset) { $ht['asset'] = $ht.uv_asset }
            if (-not $ht.sha256 -and $ht.uv_sha256) { $ht['sha256'] = $ht.uv_sha256 }
            return $ht
        } catch { }
    }
    @{}
}

function Set-UvConfig {
    <#
    .SYNOPSIS
        Write uv config to .config/uv.json.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $configDir = Split-Path $script:ConfigPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($script:ConfigPath, ($Config | ConvertTo-Json -Depth 3), $script:UTF8NoBOM)
}

# ═══════════════════════════════════════════════════════════════════════════
# Embedded utilities (independent of helpers.ps1)
# ═══════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════
# UV env vars
# ═══════════════════════════════════════════════════════════════════════════

function Set-UvEnvVars {
    <#
    .SYNOPSIS
        Set all UV environment variables (user + process).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    foreach ($entry in $UvEnvVars.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'User')
        Set-Item -Path "env:$($entry.Key)" -Value $entry.Value
    }

    foreach ($dir in @($UvCacheDir, $UvPyDir, $UvToolDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

function Remove-UvEnvVars {
    <#
    .SYNOPSIS
        Remove all UV environment variables.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    foreach ($name in $UvEnvVars.Keys) {
        [Environment]::SetEnvironmentVariable($name, $null, 'User')
        Set-Item -Path "env:$name" -Value $null
        Write-Host "[OK] Removed $name" -ForegroundColor Green
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Python helpers
# ═══════════════════════════════════════════════════════════════════════════

function Get-PythonInstallDir {
    <#
    .SYNOPSIS
        Get the uv-managed Python installation directory using uv CLI.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $output = & $uvExe python list --only-installed 2>&1 | Out-String
    foreach ($line in $output -split "`n") {
        if ($line -match 'cpython-[\w.+-]+-windows-x86_64-none\s+\S+[\\/]uv-python[\\/](\S+)[\\/]python\.exe') {
            return (Join-Path $UvPyDir $Matches[1])
        }
    }
    return $null
}

function Install-PythonTools {
    <#
    .SYNOPSIS
        Add Python Scripts to PATH and install ruff + ty.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $pyDir = Get-PythonInstallDir
    if (-not $pyDir) { return }

    $scriptsDir = Join-Path $pyDir 'Scripts'
    Add-UserPath -Dir $scriptsDir

    $pythonExe = Join-Path $script:BaseBin 'python.exe'
    if (-not (Test-Path $pythonExe)) { return }

    foreach ($pkg in @('ruff', 'ty')) {
        & $pythonExe -m pip install $pkg --break-system-packages --quiet 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] $pkg installed" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Failed to install $pkg" -ForegroundColor Yellow
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# UV download
# ═══════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════
# UV download helpers
# ═══════════════════════════════════════════════════════════════════════════

function Get-UvReleaseInfo {
    <#
    .SYNOPSIS
        Fetch latest uv release info using shared helpers.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $release = Get-GitHubRelease -Repo $UvRepo
    $latestInfo = Get-LatestGitHubVersion -Repo $UvRepo -PrefixPattern '^v'
    $asset = Find-GitHubReleaseAsset -Release $release -Platform windows -Arch x86_64

    @{
        Version   = $latestInfo.Version
        Tag       = $latestInfo.Tag
        AssetName = $asset.name
        Release   = $release
    }
}

function Save-UvAsset {
    <#
    .SYNOPSIS
        Download uv asset with fallback: gh CLI -> direct URL.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$OutFile,

        [Parameter(Mandatory)]
        [string]$Tag,

        [Parameter(Mandatory)]
        [string]$AssetName
    )

    $downloaded = $false

    try {
        Save-GitHubReleaseAsset -Repo $UvRepo -Tag $Tag -AssetPattern $AssetName -OutFile $OutFile
        $downloaded = $true
    } catch {
        Write-Host "[WARN] gh download unavailable, trying direct URL..." -ForegroundColor Yellow
    }

    if (-not $downloaded) {
        $dlUrl = "https://github.com/$UvRepo/releases/download/$Tag/$AssetName"
        Invoke-WebRequest -Uri $dlUrl -OutFile $OutFile -MaximumRedirection 5 -ErrorAction Stop
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-UvCheck {
    <#
    .SYNOPSIS
        Display the current uv + Python dev environment status.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- uv ---" -ForegroundColor Cyan

    # uv
    $installedVer = $null
    if (Test-Path $uvExe) {
        $uvVer = & $uvExe --version 2>&1 | Out-String
        $installedVer = if ($uvVer -match '(\d+\.\d+\.\d+)') { $Matches[1] } else { $uvVer.Trim() }
        Write-Host "[OK] Installed: uv $installedVer ($uvExe)" -ForegroundColor Green
    } else {
        Write-Host "[INFO] uv not installed" -ForegroundColor Cyan
    }

    # Python (via uv)
    $pythonExe = Join-Path $script:BaseBin 'python.exe'
    if (Test-Path $pythonExe) {
        $pyVer = & $pythonExe --version 2>&1 | Out-String
        $pyVerStr = if ($pyVer -match '(\d+\.\d+\.\d+)') { $Matches[1] } else { $pyVer.Trim() }
        Write-Host "[OK] Python: $pyVerStr" -ForegroundColor Green
    }

    # Python tools (ruff, ty)
    $pyDir = Get-PythonInstallDir
    if ($pyDir) {
        foreach ($tool in @('ruff', 'ty')) {
            $exe = Join-Path $pyDir "Scripts\$tool.exe"
            if (Test-Path $exe) {
                Write-Host "[OK] $tool installed" -ForegroundColor Green
            }
        }
    }

    # Lock
    $cfg = Get-UvConfig
    if ($cfg.lock) {
        if ($installedVer -and $installedVer -eq $cfg.lock) {
            Write-Host "[OK] Locked: $($cfg.lock) (current)" -ForegroundColor Green
        } else {
            Write-Host "[LOCK] Locked: $($cfg.lock)" -ForegroundColor Magenta
        }
    } else {
        Write-Host "[INFO] No version lock" -ForegroundColor DarkGray
    }

    # Mirror status
    $pipConfigFile = "$env:APPDATA\pip\pip.ini"
    if (Test-Path $pipConfigFile) {
        $content = Get-Content -Path $pipConfigFile -Raw -ErrorAction SilentlyContinue
        if ($content -match 'index-url\s*=\s*(.+)') {
            Write-Host "  pip mirror: $($Matches[1].Trim())" -ForegroundColor DarkGray
        }
    }

    $uvConfigFile = "$env:APPDATA\uv\uv.toml"
    if (Test-Path $uvConfigFile) {
        $content = Get-Content -Path $uvConfigFile -Raw -ErrorAction SilentlyContinue
        if ($content -match 'index-url\s*=\s*(.+)') {
            Write-Host "  uv mirror: $($Matches[1].Trim())" -ForegroundColor DarkGray
        }
    }

    # Cache: verify against config hash
    if ($cfg.asset -and $cfg.sha256) {
        $cacheFile = Join-Path $script:CacheDir $cfg.asset
        if (Test-Path $cacheFile) {
            $actual = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash
            if ($actual -eq $cfg.sha256) {
                Write-Host "[CACHE] $($cfg.asset) (verified)" -ForegroundColor Green
            } else {
                Write-Host "[WARN] Hash mismatch: $($cfg.asset)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[CACHE] Missing: $($cfg.asset)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "[CACHE] No cache metadata" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# download
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-UvDownload {
    <#
    .SYNOPSIS
        Download uv zip to cache. Fetches latest, compares with lock.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # Fetch latest release
    Write-Host "[INFO] gh release view --repo $UvRepo --json tagName,assets" -ForegroundColor Cyan
    $info = Get-UvReleaseInfo
    $ver = $info.Version
    $assetName = $info.AssetName
    $tag = $info.Tag
    $release = $info.Release
    Write-Host "[OK] Latest version: $ver" -ForegroundColor Green

    if (-not (Test-Path $script:CacheDir)) {
        New-Item -ItemType Directory -Path $script:CacheDir -Force | Out-Null
    }

    $cfg = Get-UvConfig
    $lockVer = $cfg.lock

    # If lock exists and matches latest, check cache
    if ($lockVer -and $lockVer -eq $ver) {
        $cacheFile = Join-Path $script:CacheDir $assetName
        if ($cfg.asset -eq $assetName -and $cfg.sha256 -and (Test-Path $cacheFile)) {
            $actualHash = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash
            if ($actualHash -eq $cfg.sha256) {
                $size = (Get-Item $cacheFile).Length
                $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
                Write-Host "[OK] uv $ver cached: $sizeStr" -ForegroundColor Green
                return
            }
            Write-Host "[WARN] Cache hash mismatch, re-downloading" -ForegroundColor Yellow
        }
    }

    Write-Host "[INFO] Downloading uv $ver ..." -ForegroundColor Cyan

    $zipFile = Join-Path $env:TEMP $assetName
    Save-UvAsset -OutFile $zipFile -Tag $tag -AssetName $assetName

    # Hash verification
    try {
        Test-FileHash -FilePath $zipFile -Release $release -AssetName $assetName -Repo $UvRepo -Tag $tag | Out-Null
    } catch {
        Write-Host "[ERROR] Hash verification failed: $_" -ForegroundColor Red
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        return
    }

    # Save to cache and update config
    $actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash
    $cacheFile = Join-Path $script:CacheDir $assetName
    Copy-Item $zipFile $cacheFile -Force
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

    $cfg['lock'] = $ver
    $cfg['asset'] = $assetName
    $cfg['sha256'] = $actualHash
    Set-UvConfig -Config $cfg

    $size = (Get-Item $cacheFile).Length
    $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
    Write-Host "[OK] uv $ver downloaded and cached: $sizeStr" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# install
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-UvInstall {
    <#
    .SYNOPSIS
        Install uv from GitHub, then use uv to install Python with mirror configuration.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # ── 1. Set UV env vars ──
    Set-UvEnvVars
    Write-Host "[OK] UV environment variables configured" -ForegroundColor Green

    # ── 2. Check uv installation and lock ──
    $cfg     = Get-UvConfig
    $lockVer = $cfg.lock
    $installedVer = $null

    if (Test-Path $uvExe) {
        $uvVer = & $uvExe --version 2>&1 | Out-String
        $installedVer = if ($uvVer -match '(\d+\.\d+\.\d+)') { $Matches[1] } else { $uvVer.Trim() }
    }

    # Lock-gated install
    if ($installedVer) {
        if ($lockVer) {
            Write-Host "[OK] uv $installedVer already installed (locked)" -ForegroundColor Green
        } else {
            $cfg['lock'] = $installedVer
            if (-not $cfg.asset -or -not $cfg.sha256) {
                $cacheFiles = Get-ChildItem "$($script:CacheDir)\*.zip" -ErrorAction SilentlyContinue
                if ($cacheFiles) {
                    $latestCache = $cacheFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if (-not $cfg.asset) { $cfg['asset'] = $latestCache.Name }
                    if (-not $cfg.sha256) { $cfg['sha256'] = (Get-FileHash -Path $latestCache.FullName -Algorithm SHA256).Hash }
                }
            }
            Set-UvConfig -Config $cfg
            Write-Host "[OK] uv $installedVer already installed" -ForegroundColor Green
            Write-Host "[OK] Lock repaired: $installedVer" -ForegroundColor Green
        }
        Install-PythonTools
        return
    }

    # Not installed -> use lock version or fetch latest
    Write-Host "[INFO] gh release view --repo $UvRepo --json tagName,assets" -ForegroundColor Cyan
    $info = Get-UvReleaseInfo
    $assetName = $info.AssetName

    if ($lockVer) {
        $ver = $lockVer
        $tag = "v$ver"
        Write-Host "[INFO] Using locked version $ver" -ForegroundColor Cyan
    } else {
        $ver = $info.Version
        $tag = $info.Tag
        Write-Host "[OK] Latest version: $ver" -ForegroundColor Green
    }

    if (-not (Test-Path $script:CacheDir)) {
        New-Item -ItemType Directory -Path $script:CacheDir -Force | Out-Null
    }

    $cacheFile = Join-Path $script:CacheDir $assetName
    $zipFile   = Join-Path $env:TEMP $assetName

    # Download if not cached or hash mismatch
    $needDownload = $true
    if ($cfg.asset -eq $assetName -and $cfg.sha256 -and (Test-Path $cacheFile)) {
        $actualHash = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash
        if ($actualHash -eq $cfg.sha256) {
            Write-Host "[OK] Using cache: $assetName" -ForegroundColor Green
            Copy-Item $cacheFile $zipFile -Force
            $needDownload = $false
        }
    }

    if ($needDownload) {
        Write-Host "[INFO] Downloading $assetName ..." -ForegroundColor Cyan
        Save-UvAsset -OutFile $zipFile -Tag $tag -AssetName $assetName
        $actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash
        Copy-Item $zipFile $cacheFile -Force
        $cfg['lock'] = $ver
        $cfg['asset'] = $assetName
        $cfg['sha256'] = $actualHash
        Set-UvConfig -Config $cfg
    }

    # Extract uv.exe to .envs/base/bin/
    if (-not (Test-Path $script:BaseBin)) {
        New-Item -ItemType Directory -Path $script:BaseBin -Force | Out-Null
    }
    $tmpDir = Join-Path $env:TEMP "omc-uv-$(Get-Random)"
    try {
        Expand-Archive -Path $zipFile -DestinationPath $tmpDir -Force
        $srcExe = Get-ChildItem -Path $tmpDir -Filter 'uv.exe' -Recurse | Select-Object -First 1
        if (-not $srcExe) {
            throw "uv.exe not found in archive"
        }
        Copy-Item -Path $srcExe.FullName -Destination $uvExe -Force
        Write-Host "[OK] uv $ver installed" -ForegroundColor Green
    } finally {
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    }

    # ── 3. Add .envs/base/bin to PATH ──
    Add-UserPath -Dir $script:BaseBin

    # ── 4. Install Python via uv ──
    # Remove stale versioned shims to avoid "executable already exists" conflict
    Get-ChildItem $script:BaseBin -Filter 'python*.exe' | Where-Object {
        $_.Name -match '^python\d' -or $_.Name -match '^pythonw\d'
    } | Remove-Item -Force -ErrorAction SilentlyContinue
    $pythonExe = Join-Path $script:BaseBin 'python.exe'
    if (Test-Path $pythonExe) {
        $raw = & $pythonExe --version 2>&1 | Out-String
        if ($raw -match '(\d+\.\d+\.\d+)') {
            $installed = $Matches[1]
            if ($installed -eq $PythonVersion) {
                Write-Host "[OK] Python $PythonVersion already installed" -ForegroundColor Green
            } else {
                Write-Host "[UPGRADE] Python $installed -> $PythonVersion" -ForegroundColor Cyan
                & $uvExe python install "$PythonVersion" --default --preview-features python-install-default
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "[ERROR] uv python install failed" -ForegroundColor Red
                    exit 1
                }
                Write-Host "[OK] Python upgraded to $PythonVersion" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "[INFO] Installing Python $PythonVersion via uv..." -ForegroundColor Cyan
        & $uvExe python install "$PythonVersion" --default --preview-features python-install-default
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] uv python install failed" -ForegroundColor Red
            exit 1
        }
        Write-Host "[OK] Python $PythonVersion installed" -ForegroundColor Green
    }

    # ── 5. Install Python tools (ruff, ty) + add Scripts to PATH ──
    Install-PythonTools

    # ── 6. Configure pip mirror (aliyun) ──
    $pipConfigDir  = "$env:APPDATA\pip"
    $pipConfigFile = "$pipConfigDir\pip.ini"

    if (-not (Test-Path $pipConfigDir)) {
        New-Item -ItemType Directory -Path $pipConfigDir -Force | Out-Null
    }

    if ((Test-Path $pipConfigFile) -and -not ((Get-Content $pipConfigFile -Raw -ErrorAction SilentlyContinue) -match 'aliyun')) {
        $backupPath = "$pipConfigFile.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -Path $pipConfigFile -Destination $backupPath -Force
        Write-Host "[WARN] Existing pip.ini backed up to: $backupPath" -ForegroundColor Yellow
    }

    $pipConfig = @"
[global]
index-url = $pipMirror
trusted-host = mirrors.aliyun.com
"@
    [System.IO.File]::WriteAllText($pipConfigFile, $pipConfig.Trim(), $script:UTF8NoBOM)
    Write-Host "[OK] pip.ini written with aliyun mirror" -ForegroundColor Green

    # ── 7. Configure uv mirror (aliyun) ──
    $uvConfigDir  = "$env:APPDATA\uv"
    $uvConfigFile = "$uvConfigDir\uv.toml"

    if (-not (Test-Path $uvConfigDir)) {
        New-Item -ItemType Directory -Path $uvConfigDir -Force | Out-Null
    }

    if ((Test-Path $uvConfigFile) -and -not ((Get-Content $uvConfigFile -Raw -ErrorAction SilentlyContinue) -match 'aliyun')) {
        $backupPath = "$uvConfigFile.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -Path $uvConfigFile -Destination $backupPath -Force
        Write-Host "[WARN] Existing uv.toml backed up to: $backupPath" -ForegroundColor Yellow
    }

    $uvConfig = @"
[[index]]
url = "$uvMirrorUrl"
default = true
"@
    [System.IO.File]::WriteAllText($uvConfigFile, $uvConfig.Trim(), $script:UTF8NoBOM)
    Write-Host "[OK] uv.toml written with aliyun mirror" -ForegroundColor Green

    # ── 8. Write version lock ──
    $uvVer = & $uvExe --version 2>&1 | Out-String
    $uvVerStr = if ($uvVer -match '(\d+\.\d+\.\d+)') { $Matches[1] } else { "unknown" }
    $cfg = Get-UvConfig
    $cfg['lock'] = $uvVerStr
    Set-UvConfig -Config $cfg
    Show-LockWrite -Version "uv $uvVerStr"

    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host "  uv $uvVerStr + Python $PythonVersion installed" -ForegroundColor Green
    Write-Host "  pip mirror: $pipMirror" -ForegroundColor DarkGray
    Write-Host "  uv mirror : $uvMirrorUrl" -ForegroundColor DarkGray
    Write-Host "=============================================" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# update
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-UvUpdate {
    <#
    .SYNOPSIS
        Update uv by downloading latest from GitHub releases, then check Python.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-Path $uvExe)) {
        Write-Host "[INFO] uv not installed, running install..." -ForegroundColor Cyan
        Invoke-UvInstall
        return
    }

    # Check current version
    $raw = & $uvExe --version 2>&1 | Out-String
    $currentVer = if ($raw -match '(\d+\.\d+\.\d+)') { $Matches[1] } else { "unknown" }

    # Get latest version from GitHub
    Write-Host "[INFO] gh release view --repo $UvRepo --json tagName,assets" -ForegroundColor Cyan
    $info = Get-UvReleaseInfo
    $latestVer = $info.Version
    $assetName = $info.AssetName
    $tag = $info.Tag
    Write-Host "[OK] Latest version: $latestVer" -ForegroundColor Green

    if ($currentVer -eq $latestVer) {
        Write-Host "[OK] Already installed: uv $currentVer" -ForegroundColor Green
        $cfg = Get-UvConfig
        if (-not $cfg.lock) {
            $cfg['lock'] = $currentVer
            Set-UvConfig -Config $cfg
            Write-Host "[OK] Lock restored: $currentVer" -ForegroundColor Green
        }
    } else {
        Write-Host "[UPGRADE] uv $currentVer -> $latestVer" -ForegroundColor Cyan
        $response = Read-Host "  Upgrade? (Y/n)"
        if ($response -and $response -ne 'Y' -and $response -ne 'y') {
            Write-Host "[INFO] Skipped" -ForegroundColor DarkGray
            return
        }

        if (-not (Test-Path $script:CacheDir)) {
            New-Item -ItemType Directory -Path $script:CacheDir -Force | Out-Null
        }

        $zipFile   = Join-Path $env:TEMP $assetName
        $cacheFile = Join-Path $script:CacheDir $assetName

        Save-UvAsset -OutFile $zipFile -Tag $tag -AssetName $assetName

        # Extract and replace
        $tmpDir = Join-Path $env:TEMP "omc-uv-$(Get-Random)"
        try {
            Expand-Archive -Path $zipFile -DestinationPath $tmpDir -Force
            $srcExe = Get-ChildItem -Path $tmpDir -Filter 'uv.exe' -Recurse | Select-Object -First 1
            if (-not $srcExe) {
                throw "uv.exe not found in archive"
            }
            Copy-Item -Path $srcExe.FullName -Destination $uvExe -Force
            Write-Host "[OK] uv upgraded to $latestVer" -ForegroundColor Green
        } finally {
            Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Update cache and config
        $actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash
        if (Test-Path $cacheFile) { Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue }
        Copy-Item $zipFile $cacheFile -Force
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        $cfg = Get-UvConfig
        $cfg['lock'] = $latestVer
        $cfg['asset'] = $assetName
        $cfg['sha256'] = $actualHash
        Set-UvConfig -Config $cfg
    }

    # Ensure Python version matches
    # Remove stale versioned shims to avoid "executable already exists" conflict
    Get-ChildItem $script:BaseBin -Filter 'python*.exe' | Where-Object {
        $_.Name -match '^python\d' -or $_.Name -match '^pythonw\d'
    } | Remove-Item -Force -ErrorAction SilentlyContinue

    $pythonExe = Join-Path $script:BaseBin 'python.exe'
    if (Test-Path $pythonExe) {
        $pyRaw = & $pythonExe --version 2>&1 | Out-String
        if ($pyRaw -match '(\d+\.\d+\.\d+)') {
            if ($Matches[1] -eq $PythonVersion) {
                Write-Host "[OK] Python $PythonVersion up-to-date" -ForegroundColor Green
            } else {
                Write-Host "[INFO] Updating Python to $PythonVersion..." -ForegroundColor Cyan
                & $uvExe python install "$PythonVersion" --default --preview-features python-install-default
                Write-Host "[OK] Python updated" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "[INFO] Installing Python $PythonVersion..." -ForegroundColor Cyan
        & $uvExe python install "$PythonVersion" --default --preview-features python-install-default
        Write-Host "[OK] Python installed" -ForegroundColor Green
    }

    Install-PythonTools

    # Update lock
    $uvVer = & $uvExe --version 2>&1 | Out-String
    $uvVerStr = if ($uvVer -match '(\d+\.\d+\.\d+)') { $Matches[1] } else { "unknown" }
    $cfg = Get-UvConfig
    $cfg['lock'] = $uvVerStr
    Set-UvConfig -Config $cfg
    Write-Host "[OK] Updated: uv $uvVerStr" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-UvUninstall {
    <#
    .SYNOPSIS
        Remove uv binary, Python shims, and uv-managed directories. Preserve lock and download cache.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-Path $uvExe)) {
        Write-Host '[INFO] uv not installed, nothing to uninstall' -ForegroundColor Cyan
        return
    }

    Write-Host "[INFO] Uninstalling uv..." -ForegroundColor Cyan

    # Remove Python Scripts from PATH
    $pyDir = Get-PythonInstallDir
    if ($pyDir) {
        $scriptsDir = Join-Path $pyDir 'Scripts'
        Remove-UserPath -Dir $scriptsDir
    }

    # Remove uv-managed runtime directories
    $uvDirs = @($UvCacheDir, $UvPyDir, $UvToolDir)
    foreach ($dir in $uvDirs) {
        if (Test-Path $dir) {
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Removed: $dir" -ForegroundColor Green
        }
    }

    # Remove uv.exe from .envs/base/bin/
    Remove-Item $uvExe -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Removed uv.exe" -ForegroundColor Green

    # Remove uv-managed shims from .envs/base/bin/
    $shims = @('python.exe', 'python3.exe', 'pythonw.exe', 'pip.exe', 'pip3.exe')
    foreach ($shim in $shims) {
        $path = Join-Path $script:BaseBin $shim
        if (Test-Path $path) {
            Remove-Item $path -Force -ErrorAction SilentlyContinue
        }
    }

    # Remove versioned Python shims (e.g. python3.14.exe, python3.14t.exe, pythonw3.14.exe)
    Get-ChildItem $script:BaseBin -Filter 'python*.exe' | Where-Object {
        $_.Name -match '^python\d' -or $_.Name -match '^pythonw\d'
    } | Remove-Item -Force -ErrorAction SilentlyContinue

    # Remove UV env vars
    Remove-UvEnvVars

    # Remove pip config
    $pipConfig = "$env:APPDATA\pip\pip.ini"
    if (Test-Path $pipConfig) {
        Remove-Item $pipConfig -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Removed pip config" -ForegroundColor Green
    }

    # Remove uv config
    $uvConfig = "$env:APPDATA\uv\uv.toml"
    if (Test-Path $uvConfig) {
        Remove-Item $uvConfig -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Removed uv config" -ForegroundColor Green
    }

    # Migration cleanup: remove old dirs
    $oldPythonDir = Join-Path $script:OhmyRoot '.envs\base\Python'
    if (Test-Path $oldPythonDir) {
        Remove-Item $oldPythonDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Removed old: $oldPythonDir" -ForegroundColor Green
    }
    $oldUvDirs = @(
        (Join-Path $script:OhmyRoot '.envs\base\uv_tools')
        (Join-Path $script:OhmyRoot '.envs\base\uv_cache')
        (Join-Path $script:OhmyRoot '.envs\base\uv_python')
    )
    foreach ($dir in $oldUvDirs) {
        if (Test-Path $dir) {
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Removed old: $dir" -ForegroundColor Green
        }
    }

    Write-Host "[OK] uv uninstalled" -ForegroundColor Green
    Write-Host "[INFO] Lock and download cache preserved" -ForegroundColor DarkGray
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch
# ═══════════════════════════════════════════════════════════════════════════

switch ($Command) {
    'check'     { Invoke-UvCheck }
    'download'  { Invoke-UvDownload }
    'init'      { Invoke-UvInstall }
    'install'   { Invoke-UvInstall }
    'update'    { Invoke-UvUpdate }
    'uninstall' { Invoke-UvUninstall }
}
