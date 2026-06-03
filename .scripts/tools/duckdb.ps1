#Requires -Version 5.1

<#
.SYNOPSIS
    Manage DuckDB CLI installation from GitHub releases.
.DESCRIPTION
    Supports: check, install, update, uninstall, download, ext (extension management).
.PARAMETER Command
    Action: check, install, update, uninstall, download, ext.
.PARAMETER ExtCommand
    Extension sub-command: check, install (used with Command = 'ext').
.PARAMETER Extensions
    Extensions to install (used with ext install). Default: shellfs, httpfs.
.PARAMETER Version
    Specific version to install (default: latest).
.PARAMETER Force
    Skip upgrade confirmation / overwrite existing extension files.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("check", "install", "update", "uninstall", "download", "ext")]
    [string]$Command = "check",

    [Parameter(Position = 1)]
    [string]$ExtCommand = "",

    [string[]]$Extensions = @("shellfs", "httpfs"),

    [AllowEmptyString()]
    [string]$Version = "",

    [switch]$Force
)

. "$PSScriptRoot\..\helpers.ps1"

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = "Stop"

$script:OhmyRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$Repo             = "duckdb/duckdb"
$ArchiveName      = "duckdb_cli-windows-amd64.zip"
$EnvBin           = "$script:OhmyRoot\.envs\tools\bin"
$DuckdbExe        = "$EnvBin\duckdb.exe"
$DuckdbConfigFile = Join-Path $script:OhmyRoot ".config\duckdb\config.json"
$DuckdbRcFile     = Join-Path $env:USERPROFILE ".duckdbrc"
$NoBom            = New-Object System.Text.UTF8Encoding $false

# ═══════════════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════════════

function Get-DuckdbLock {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if (-not (Test-Path $DuckdbConfigFile)) { return }
    try {
        $cfg = Get-Content $DuckdbConfigFile -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($cfg.lock) { return $cfg.lock }
    } catch {}
}

function Set-DuckdbLock {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )
    $dir = Split-Path $DuckdbConfigFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = @{ lock = $Version } | ConvertTo-Json
    [System.IO.File]::WriteAllText($DuckdbConfigFile, $json.Trim(), $NoBom)
}

function Get-InstalledDuckdbVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if (-not (Test-Path $DuckdbExe)) { return }
    $lock = Get-DuckdbLock
    if ($lock) { return $lock }
}

function Get-LatestDuckdbVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    try {
        $release = Get-GitHubRelease -Repo $Repo
        if ($release.tag_name -match 'v(\d+\.\d+\.\d+)') { return $Matches[1] }
        throw "Cannot parse version from tag: $($release.tag_name)"
    } catch {
        throw "Failed to fetch latest DuckDB version: $_"
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Extension helpers
# ═══════════════════════════════════════════════════════════════════════════

$extPlatform     = "windows_amd64"
$extDir          = Join-Path $script:OhmyRoot ".cache\tools\duckdb-extension"
$extCommunityExts = @("shellfs")

function Get-DuckdbExeFromPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    (Get-Command duckdb -ErrorAction SilentlyContinue).Source
}

function Resolve-DuckdbVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $duckdbExe = Get-DuckdbExeFromPath
    if ($duckdbExe) {
        try {
            $raw = & $duckdbExe -c "SELECT version();" 2>$null | Out-String
            if ($raw -match 'v(\d+\.\d+\.\d+)') { return "v$($Matches[1])" }
        } catch {}
    }
    if (Test-Path $DuckdbConfigFile) {
        try {
            $cfg = Get-Content $DuckdbConfigFile -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
            if ($cfg.lock) { return "v$($cfg.lock)" }
        } catch {}
    }
}

function Get-ExtDirs {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $duckdbVersion = Resolve-DuckdbVersion
    $versionDir = if ($duckdbVersion) { Join-Path $extDir "$duckdbVersion\$extPlatform" } else { $null }
    return @{
        extDir        = $extDir
        versionDir    = $versionDir
        duckdbVersion = $duckdbVersion
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════
# duckdbrc
# ═══════════════════════════════════════════════════════════════════════════

function Set-DuckdbRc {
    <#
    .SYNOPSIS
        Ensure ~/.duckdbrc contains SET extension_directory for ohmyclaude (no BOM).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()
    $extDirForward = $extDir -replace '\\', '/'
    $targetLine = "SET extension_directory='$extDirForward';"
    $rcNoBom = New-Object System.Text.UTF8Encoding $false

    $lines = @()
    if ((Test-Path $DuckdbRcFile)) {
        $raw = [System.IO.File]::ReadAllText($DuckdbRcFile)
        $lines = ($raw -split "`n") | Where-Object { $_ -notmatch '^\s*SET\s+extension_directory' }
    }

    $lines += $targetLine
    [System.IO.File]::WriteAllText($DuckdbRcFile, ($lines -join "`n"), $rcNoBom)
    Write-Host "[OK] Updated $DuckdbRcFile" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-DuckdbCheck {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- DuckDB ---" -ForegroundColor Cyan

    $installed = Get-InstalledDuckdbVersion

    if ($installed) {
        Write-Host "[OK] Installed: DuckDB $installed ($DuckdbExe)" -ForegroundColor Green
    } else {
        Write-Host "[INFO] DuckDB not installed" -ForegroundColor Cyan
        Write-Host "  Expected: $DuckdbExe" -ForegroundColor DarkGray
    }

    # Lock
    $lock = Get-DuckdbLock
    if ($lock) {
        if ($installed -and $installed -eq $lock) {
            Write-Host "[OK] Locked: $lock (current)" -ForegroundColor Green
        } else {
            Write-Host "[LOCK] Locked: $lock" -ForegroundColor Magenta
        }
    } else {
        Write-Host "[INFO] No version lock" -ForegroundColor DarkGray
    }

    # Cache
    $cacheDir = Join-Path "$script:OhmyRoot\.cache\tools" "duckdb"
    if (Test-Path $cacheDir) {
        $cached = Get-ChildItem -Path $cacheDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -ne '.sha256' } |
            Sort-Object LastWriteTime -Descending
        if ($cached) {
            $names = ($cached | ForEach-Object { $_.Name }) -join ', '
            Write-Host "[CACHE] $cacheDir" -ForegroundColor DarkGray
            Write-Host "        $names" -ForegroundColor DarkGray
        } else {
            Write-Host "[CACHE] No cached downloads in $cacheDir" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "[CACHE] No cache directory" -ForegroundColor DarkGray
    }

    # PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -split ';' -contains $EnvBin) {
        Write-Host "[OK] PATH: $EnvBin" -ForegroundColor DarkGray
    } else {
        Write-Host "[INFO] PATH: not set" -ForegroundColor DarkGray
    }

    # Extensions (only if DuckDB is installed)
    if ($installed) {
        $dirs = Get-ExtDirs
        if ($dirs.versionDir -and (Test-Path $dirs.versionDir)) {
            $extFiles = Get-ChildItem -Path $dirs.versionDir -Filter "*.duckdb_extension" -ErrorAction SilentlyContinue
            if ($extFiles) {
                $extNames = ($extFiles | ForEach-Object { $_.BaseName }) -join ', '
                Write-Host "[OK] Extensions ($($dirs.duckdbVersion)): $extNames" -ForegroundColor DarkGray
                Write-Host "        $($dirs.versionDir)" -ForegroundColor DarkGray
            } else {
                Write-Host "[INFO] No extensions installed" -ForegroundColor DarkGray
                Write-Host "        $($dirs.versionDir)" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "[INFO] No extensions installed" -ForegroundColor DarkGray
            if ($dirs.extDir) {
                Write-Host "        $($dirs.extDir)" -ForegroundColor DarkGray
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# download
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-DuckdbDownload {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $lockVer = Get-DuckdbLock
    if ($lockVer) {
        $Version = $lockVer
    } else {
        try {
            $Version = Get-LatestDuckdbVersion
            Write-Host "[OK] DuckDB latest: $Version" -ForegroundColor Green
        } catch {
            Write-Host "[WARN] Cannot fetch latest version: $_" -ForegroundColor Yellow
            return
        }
    }

    $tag       = "v$Version"
    $cacheDir  = Join-Path "$script:OhmyRoot\.cache\tools" "duckdb"
    $cacheFile = Join-Path $cacheDir $ArchiveName
    $hashFile  = "$cacheFile.sha256"

    # Cache hit
    if ((Test-Path $cacheFile) -and (Test-Path $hashFile)) {
        $expectedHash = (Get-Content $hashFile -Raw).Trim()
        $actualHash   = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash
        if ($actualHash -eq $expectedHash) {
            $size = (Get-Item $cacheFile).Length
            $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
            Write-Host "[OK] DuckDB v$Version cached: $sizeStr" -ForegroundColor Green
            Write-Host "      $cacheFile" -ForegroundColor DarkGray
            return
        }
        Write-Host "[WARN] Cache hash mismatch, re-downloading" -ForegroundColor Yellow
        Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
        Remove-Item $hashFile -Force -ErrorAction SilentlyContinue
    }

    # Fetch release info for verification
    Write-Host "[INFO] Fetching release info for duckdb/duckdb..." -ForegroundColor Cyan
    try {
        $release = Get-GitHubRelease -Repo $Repo -Tag $tag
    } catch {
        Write-Host "[WARN] Cannot fetch release info: $_" -ForegroundColor Yellow
    }

    # Find download URL
    $downloadUrl = $null
    if ($release) {
        $asset = $release.assets | Where-Object { $_.name -eq $ArchiveName } | Select-Object -First 1
        if ($asset) { $downloadUrl = $asset.browser_download_url }
    }
    if (-not $downloadUrl) {
        $downloadUrl = "https://github.com/$Repo/releases/download/$tag/$ArchiveName"
    }

    $zipFile = "$env:TEMP\$ArchiveName"

    Write-Host "[INFO] Downloading DuckDB v$Version ..." -ForegroundColor Cyan

    try {
        Save-GitHubReleaseAsset -Repo $Repo -Tag $tag -AssetPattern $ArchiveName -OutFile $zipFile
    } catch {
        Write-Host "[ERROR] Download failed: $_" -ForegroundColor Red
        exit 1
    }

    # SHA256
    $actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    Set-Content -Path $hashFile -Value $actualHash -NoNewline -Encoding UTF8

    # Cross-verify with GitHub digest
    if ($release) {
        try {
            Test-FileHash -FilePath $zipFile -Release $release -AssetName $ArchiveName -Repo $Repo -Tag $tag | Out-Null
        } catch {
            Write-Host "[WARN] GitHub digest verification failed: $_" -ForegroundColor Yellow
        }
    }

    # Cache
    Copy-Item -Path $zipFile -Destination $cacheFile -Force
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

    $size = (Get-Item $cacheFile).Length
    $sizeStr = if ($size -ge 1MB) { "{0:N1} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }
    Write-Host "[OK] DuckDB v$Version downloaded and cached: $sizeStr" -ForegroundColor Green
    Write-Host "      $cacheFile" -ForegroundColor DarkGray

    # Lock
    Set-DuckdbLock -Version $Version
    Show-LockWrite -Version $Version
}

# ═══════════════════════════════════════════════════════════════════════════
# install
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-DuckdbInstall {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $installed = Get-InstalledDuckdbVersion

    # Determine version
    if ($Version) {
        $targetVer = $Version
    } else {
        $lockVer = Get-DuckdbLock
        if ($lockVer) {
            $targetVer = $lockVer
        } else {
            try {
                $targetVer = Get-LatestDuckdbVersion
                Write-Host "[OK] DuckDB latest: $targetVer" -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Cannot fetch latest version: $_" -ForegroundColor Yellow
                return
            }
        }
    }

    # Idempotent check
    if ($installed -and $installed -eq $targetVer -and -not $Force) {
        Show-AlreadyInstalled -Tool "DuckDB" -Version $installed -Location $DuckdbExe
        if (-not (Get-DuckdbLock)) { Set-DuckdbLock -Version $installed }
        Invoke-DuckdbExtInstall
        return
    }
    if ($installed) {
        Write-Host "[UPGRADE] DuckDB $installed -> $targetVer" -ForegroundColor Cyan
    }

    # Download if needed
    Set-DuckdbLock -Version $targetVer
    Invoke-DuckdbDownload

    # Extract
    $cacheDir  = Join-Path "$script:OhmyRoot\.cache\tools" "duckdb"
    $cacheFile = Join-Path $cacheDir $ArchiveName
    $zipFile   = "$env:TEMP\$ArchiveName"

    if (-not (Test-Path $cacheFile)) {
        Write-Host "[ERROR] Cache not found: $cacheFile" -ForegroundColor Red
        exit 1
    }

    Write-Host "[INFO] Installing DuckDB $targetVer ..." -ForegroundColor Cyan
    Copy-Item -Path $cacheFile -Destination $zipFile -Force

    $extractTemp = Join-Path $env:TEMP "ohmyclaude-extract-duckdb"
    if (Test-Path $extractTemp) { Remove-Item $extractTemp -Recurse -Force }
    New-Item -ItemType Directory -Path $extractTemp -Force | Out-Null

    try {
        Expand-Archive -Path $zipFile -DestinationPath $extractTemp -Force -ErrorAction Stop
        if (-not (Test-Path $EnvBin)) { New-Item -ItemType Directory -Path $EnvBin -Force | Out-Null }
        Copy-Item -Path "$extractTemp\duckdb.exe" -Destination $DuckdbExe -Force
        Write-Host "[OK] Installed to $DuckdbExe" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Install failed: $_" -ForegroundColor Red
        exit 1
    } finally {
        Remove-Item $extractTemp -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    }

    # Verify
    Update-Environment
    $normalized = $EnvBin.TrimEnd('\')
    if ($env:Path -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -eq $normalized }) {
        # already in session PATH
    } else {
        $env:Path = "$normalized;$env:Path"
    }
    $verifyVer = Get-InstalledDuckdbVersion
    if ($verifyVer) {
        Show-InstallComplete -Tool "DuckDB" -Version $verifyVer
    } else {
        Write-Host "[OK] DuckDB installed" -ForegroundColor Green
        Write-Host "  Location: $DuckdbExe" -ForegroundColor DarkGray
    }

    Set-DuckdbLock -Version $targetVer
    Show-LockWrite -Version $targetVer

    # Install extensions
    Invoke-DuckdbExtInstall
}

# ═══════════════════════════════════════════════════════════════════════════
# update
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-DuckdbUpdate {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $installed = Get-InstalledDuckdbVersion
    $installed = if ($installed) { $installed } else { "not installed" }

    Write-Host "[INFO] DuckDB: $installed" -ForegroundColor Cyan

    try {
        $latest = Get-LatestDuckdbVersion
        Write-Host "[OK] Latest: $latest" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Cannot check latest version: $_" -ForegroundColor Yellow
        return
    }

    if (-not $installed -or $installed -eq "not installed") {
        Write-Host "[INFO] Not installed, installing $latest ..." -ForegroundColor Cyan
        Invoke-DuckdbInstall
        return
    }

    if (-not (Get-DuckdbLock)) { Set-DuckdbLock -Version $installed }

    $cmp = Compare-SemanticVersion -Current $installed -Latest $latest
    if ($cmp -ge 0) {
        Show-AlreadyInstalled -Tool "DuckDB" -Version $installed
        return
    }

    Write-Host "[UPGRADE] $installed -> $latest" -ForegroundColor Cyan
    $response = Read-Host "  Upgrade? (Y/n)"
    if ($response -and $response -ne 'Y' -and $response -ne 'y') {
        Write-Host "[INFO] Skipped" -ForegroundColor DarkGray
        return
    }

    Invoke-DuckdbInstall
}

# ═══════════════════════════════════════════════════════════════════════════
# uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-DuckdbUninstall {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-Path $DuckdbExe) -and -not (Test-Path $DuckdbConfigFile)) {
        Write-Host '[INFO] DuckDB not installed, nothing to uninstall' -ForegroundColor Cyan
        return
    }

    Write-Host "[INFO] Uninstalling DuckDB ..." -ForegroundColor Cyan

    if (Test-Path $DuckdbExe) {
        try {
            Remove-Item $DuckdbExe -Force -ErrorAction Stop
            Write-Host "[OK] Removed: $DuckdbExe" -ForegroundColor Green
        } catch {
            Write-Host "[WARN] Could not remove $DuckdbExe : $_" -ForegroundColor Yellow
        }
    }

    if (Test-Path $DuckdbConfigFile) {
        Remove-Item $DuckdbConfigFile -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Removed version lock" -ForegroundColor Green
    }

    if (Test-Path $extDir) {
        try {
            Remove-Item $extDir -Recurse -Force -ErrorAction Stop
            Write-Host "[OK] Removed extensions: $extDir" -ForegroundColor Green
        } catch {
            Write-Host "[WARN] Could not remove extensions: $_" -ForegroundColor Yellow
        }
    }

    Write-Host "[OK] DuckDB uninstalled" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# ext check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-DuckdbExtCheck {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "--- DuckDB Extensions ---" -ForegroundColor Cyan

    $dirs = Get-ExtDirs

    if (-not $dirs.duckdbVersion) {
        Write-Host "[INFO] DuckDB not installed, cannot check extensions" -ForegroundColor Yellow
        return
    }

    Write-Host "[INFO] DuckDB version: $($dirs.duckdbVersion), platform: $extPlatform" -ForegroundColor Cyan
    Write-Host "[INFO] Extension dir: $($dirs.extDir)" -ForegroundColor DarkGray

    # Installed extensions
    if ($dirs.versionDir -and (Test-Path $dirs.versionDir)) {
        $installed = Get-ChildItem -Path $dirs.versionDir -Filter "*.duckdb_extension" -ErrorAction SilentlyContinue
        if ($installed) {
            foreach ($f in $installed) {
                $sizeMB = [Math]::Round((Get-Item $f.FullName).Length / 1MB, 1)
                Write-Host "[OK] $($f.BaseName) ($sizeMB MB)" -ForegroundColor Green
            }
        } else {
            Write-Host "[INFO] No extensions installed" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "[INFO] No extensions installed" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# ext install
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-DuckdbExtInstall {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $duckdbExe = Get-DuckdbExeFromPath
    if (-not $duckdbExe) {
        Write-Host "[ERROR] duckdb is not installed" -ForegroundColor Red
        Write-Host "       Run 'omc install duckdb' first" -ForegroundColor DarkGray
        exit 1
    }

    $dirs = Get-ExtDirs
    if (-not $dirs.duckdbVersion) {
        Write-Host "[ERROR] Cannot determine DuckDB version" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "--- DuckDB Extensions ---" -ForegroundColor Cyan
    Write-Host "[INFO] DuckDB version: $($dirs.duckdbVersion), platform: $extPlatform" -ForegroundColor Cyan
    Write-Host "[INFO] Extension dir: $($dirs.extDir)" -ForegroundColor DarkGray

    if (-not (Test-Path $dirs.versionDir)) {
        New-Item -ItemType Directory -Path $dirs.versionDir -Force | Out-Null
    }

    $downloadedExtensions = @()

    foreach ($ext in $Extensions) {
        $extFile   = "$ext.duckdb_extension"
        $cachedFile = Join-Path $dirs.versionDir $extFile
        $hashFile   = "$cachedFile.sha256"

        # Already cached with valid hash?
        if ((Test-Path $cachedFile) -and (Test-Path $hashFile) -and -not $Force) {
            $expectedHash = (Get-Content $hashFile -Raw).Trim()
            $sha256 = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider
            $bytes = [System.IO.File]::ReadAllBytes($cachedFile)
            $actualHash = ($sha256.ComputeHash($bytes) | ForEach-Object { $_.ToString('X2') }) -join ''
            if ($actualHash -eq $expectedHash) {
                $sizeMB = [Math]::Round((Get-Item $cachedFile).Length / 1MB, 1)
                Write-Host "[OK] $ext already installed and verified ($sizeMB MB)" -ForegroundColor Green
                $downloadedExtensions += @{ name = $ext; hash = $actualHash }
                continue
            } else {
                Write-Host "[WARN] $ext hash mismatch, re-downloading" -ForegroundColor Yellow
                Remove-Item $cachedFile -Force -ErrorAction SilentlyContinue
                Remove-Item $hashFile -Force -ErrorAction SilentlyContinue
            }
        }

        # Download via DuckDB CLI FORCE INSTALL
        Write-Host "[INFO] Downloading $ext..." -ForegroundColor Cyan

        # extension_directory must be set for both code paths; computing it
        # only inside the community branch left it empty for built-in extensions.
        $extDirSql = $dirs.extDir -replace '\\', '/'
        if ($ext -in $extCommunityExts) {
            $sql = "SET extension_directory='$extDirSql'; FORCE INSTALL $ext FROM community;"
        } else {
            $sql = "SET extension_directory='$extDirSql'; FORCE INSTALL $ext;"
        }

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        $result = & $duckdbExe -c $sql 2>&1 | Out-String
        $ErrorActionPreference = $prevEAP

        if (Test-Path $cachedFile) {
            $sha256 = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider
            $bytes = [System.IO.File]::ReadAllBytes($cachedFile)
            $hash = ($sha256.ComputeHash($bytes) | ForEach-Object { $_.ToString('X2') }) -join ''
            Set-Content -Path $hashFile -Value $hash -NoNewline -Encoding UTF8
            $sizeMB = [Math]::Round((Get-Item $cachedFile).Length / 1MB, 1)
            Write-Host "[OK] $ext installed ($sizeMB MB, SHA256: $($hash.Substring(0,16))...)" -ForegroundColor Green
            $downloadedExtensions += @{ name = $ext; hash = $hash }
        } elseif ($result -match '(?:builtin|already exist|already loaded|already installed)') {
            Write-Host "[OK] $ext is bundled with DuckDB" -ForegroundColor Green
            $downloadedExtensions += @{ name = $ext; hash = "" }
        } else {
            Write-Host "[ERROR] Failed to download ${ext}" -ForegroundColor Red
            $errLine = ($result -split "`n" | Where-Object { $_ -match 'error|fail|could not' } | Select-Object -First 1).Trim()
            if ($errLine) {
                Write-Host "       $errLine" -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ""
    Write-Host "[OK] DuckDB extensions: $($downloadedExtensions.Count)/$($Extensions.Count) installed" -ForegroundColor Green

    Set-DuckdbRc
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch
# ═══════════════════════════════════════════════════════════════════════════

switch ($Command) {
    "check"     { Invoke-DuckdbCheck }
    "download"  { Invoke-DuckdbDownload }
    "install"   { Invoke-DuckdbInstall }
    "update"    { Invoke-DuckdbUpdate }
    "uninstall" { Invoke-DuckdbUninstall }
    "ext" {
        switch ($ExtCommand) {
            "check"   { Invoke-DuckdbExtCheck }
            "install" { Invoke-DuckdbExtInstall }
            default {
                Write-Host "Usage: omc duckdb ext [check|install]" -ForegroundColor DarkGray
            }
        }
    }
}
