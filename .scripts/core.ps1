#Requires -Version 5.1

# ── Generic Tool Management Library ──
# All lifecycle functions are parameterized by a tool definition hashtable.
# Dot-source helpers.ps1 for reusable utilities.

. "$PSScriptRoot\helpers.ps1"

# ═══════════════════════════════════════════════════════════════════════════
# Prefix Initialization (adaptive drive detection + config guard)
# ═══════════════════════════════════════════════════════════════════════════

function Initialize-ToolPrefix {
    <#
    .SYNOPSIS
        Resolve the root prefix for tool installation with adaptive drive detection.
    .DESCRIPTION
        1. If no stored config and no explicit prefix, detect available drives (D: → C: fallback)
        2. If stored config exists, use it (warn on mismatch with specified prefix)
        3. Save the resolved prefix to per-tool config
        4. Set $global:Tool_RootDir
    .PARAMETER ToolDef
        Tool definition hashtable.
    .PARAMETER DefaultPrefix
        Default prefix (e.g. "D:\ohmyclaude"). Drive component is auto-detected.
    .PARAMETER SpecifiedPrefix
        User-specified prefix via -Prefix parameter. Empty string means not specified.
    .OUTPUTS
        String - the resolved prefix.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef,

        [string]$DefaultPrefix = "D:\ohmyclaude",

        [string]$SpecifiedPrefix = ""
    )

    # ── 1. Adaptive drive detection for default prefix ──
    $defaultDrive = ($DefaultPrefix -split ':')[0] + ":"
    if (-not $SpecifiedPrefix) {
        if (-not (Test-Path "$defaultDrive\")) {
            $fallbackPrefix = "C:" + ($DefaultPrefix -split ':', 2)[1]
            Write-Host "[INFO] Drive $defaultDrive not available, defaulting to $fallbackPrefix" -ForegroundColor Cyan
            $DefaultPrefix = $fallbackPrefix
        }
    }

    $Prefix = if ($SpecifiedPrefix) { $SpecifiedPrefix } else { $DefaultPrefix }

    # Validate drive exists
    $prefixDrive = ($Prefix -split ':')[0] + ":"
    if (-not (Test-Path "$prefixDrive\")) {
        Write-Host "[WARN] Drive $prefixDrive does not exist, paths may not be writable" -ForegroundColor Yellow
    }

    # ── 2. Config guard: stored vs specified ──
    $config = Get-ToolConfig -ToolDef $ToolDef
    $storedPrefix = $config.prefix

    if ($storedPrefix) {
        if ($Prefix -ne $storedPrefix) {
            Write-Host "[WARN] Stored prefix for $($ToolDef.DisplayName): $storedPrefix" -ForegroundColor Yellow
            Write-Host "[WARN] New prefix: $Prefix" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Changing prefix means:" -ForegroundColor Red
            Write-Host "    - Old setups/envs will no longer be used" -ForegroundColor Red
            Write-Host "    - PATH entries will point to the new location" -ForegroundColor Red
            Write-Host "    - Old directories need manual cleanup" -ForegroundColor Red
            Write-Host ""
            $confirm = Read-Host "  Confirm switch? (y/N)"
            if ($confirm -eq 'y') {
                Set-ToolConfig -ToolDef $ToolDef -Prefix $Prefix
                Write-Host "[OK] Prefix updated to $Prefix" -ForegroundColor Green
            } else {
                Write-Host "[INFO] Cancelled, keeping $storedPrefix" -ForegroundColor Cyan
                $Prefix = $storedPrefix
            }
        }
    } else {
        Set-ToolConfig -ToolDef $ToolDef -Prefix $Prefix
        Write-Host "[OK] Prefix saved: $Prefix" -ForegroundColor Green
    }

    $global:Tool_RootDir = $Prefix

    # Ensure bin directories are in PATH for all tools
    foreach ($binSub in @('.envs\base\bin', '.envs\tools\bin', '.envs\dev\bin')) {
        $binDir = Join-Path $Prefix $binSub
        Add-UserPath -Dir $binDir
    }

    $Prefix
}

# ═══════════════════════════════════════════════════════════════════════════
# Config Management
# ═══════════════════════════════════════════════════════════════════════════

function ConvertTo-Hashtable {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(ValueFromPipeline)]
        [PSObject]$InputObject
    )
    process {
        $ht = @{}
        $InputObject.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
        $ht
    }
}

function Get-ToolConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef
    )
    $setupDir = & $ToolDef.GetSetupDir $global:Tool_RootDir
    $configPath = Join-Path $setupDir 'config.json'
    if (Test-Path $configPath) {
        try {
            $raw = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction Stop
            $ht = $raw | ConvertFrom-Json | ConvertTo-Hashtable
            # Backward compat: old field name cacheName -> asset
            if (-not $ht.asset -and $ht.cacheName) { $ht['asset'] = $ht.cacheName }
            return $ht
        } catch {}
    }
    @{}
}

function Set-ToolConfig {
    <#
    .SYNOPSIS
        Write tool configuration (prefix, lock, asset cache metadata).
    .PARAMETER AssetName
        Companion asset name (e.g. 'mq-lsp.exe'). Stored in assets[] array.
    .PARAMETER AssetSha256
        SHA256 hash for the companion asset.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef,

        [string]$Prefix,

        [string]$Lock,

        [string]$Asset,

        [string]$Sha256,

        [string]$AssetName,

        [string]$AssetSha256
    )
    $setupDir = & $ToolDef.GetSetupDir $global:Tool_RootDir
    $configPath = Join-Path $setupDir 'config.json'
    if (-not (Test-Path $setupDir)) {
        New-Item -ItemType Directory -Path $setupDir -Force | Out-Null
    }

    $config = @{}
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json | ConvertTo-Hashtable
        } catch {}
    }

    if ($PSBoundParameters.ContainsKey('Prefix'))   { $config['prefix']    = $Prefix }
    if ($PSBoundParameters.ContainsKey('Lock'))     {
        if ($Lock) { $config['lock'] = $Lock } else { $config.Remove('lock') }
    }
    if ($PSBoundParameters.ContainsKey('Asset')) {
        if ($Asset) { $config['asset'] = $Asset; $config.Remove('cacheName') } else { $config.Remove('asset') }
    }
    if ($PSBoundParameters.ContainsKey('Sha256')) {
        if ($Sha256) { $config['sha256'] = $Sha256 } else { $config.Remove('sha256') }
    }

    if ($PSBoundParameters.ContainsKey('AssetName') -and $AssetName) {
        if (-not $config.ContainsKey('assets')) { $config['assets'] = @() }
        $hash = if ($AssetSha256) { $AssetSha256 } else { '' }
        $found = $false
        for ($i = 0; $i -lt $config['assets'].Count; $i++) {
            if ($config['assets'][$i].name -eq $AssetName) {
                $config['assets'][$i] = @{ name = $AssetName; sha256 = $hash }
                $found = $true; break
            }
        }
        if (-not $found) { $config['assets'] += @(@{ name = $AssetName; sha256 = $hash }) }
    }

    $config | ConvertTo-Json -Depth 3 | Set-Content $configPath -Encoding UTF8 -Force
}

# ═══════════════════════════════════════════════════════════════════════════
# Cache Directory
# ═══════════════════════════════════════════════════════════════════════════

function Get-ToolCacheDir {
    <#
    .SYNOPSIS
        Compute the cache directory for a tool.
    .DESCRIPTION
        Returns .cache\<category>\<ToolName> relative to RootDir. Category
        defaults to 'tools'; tools with CacheCategory = 'base' go to .cache\base\.
        Used for downloaded archives, separate from config dir (.config\<ToolName>)
        returned by GetSetupDir.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef,

        [Parameter(Mandatory)]
        [string]$RootDir
    )
    $category = if ($ToolDef.CacheCategory) { $ToolDef.CacheCategory } else { 'tools' }
    Join-Path $RootDir ".cache\$category\$($ToolDef.ToolName)"
}

# ═══════════════════════════════════════════════════════════════════════════
# Tool Definition Import
# ═══════════════════════════════════════════════════════════════════════════

function Import-ToolDefinition {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ToolName
    )

    $defPath = "$PSScriptRoot\base\$ToolName.ps1"
    if (-not (Test-Path $defPath)) {
        $defPath = "$PSScriptRoot\tools\$ToolName.ps1"
    }
    if (-not (Test-Path $defPath)) {
        throw "Tool definition not found: $ToolName"
    }

    $def = & $defPath
    if (-not $def -or -not ($def -is [hashtable])) {
        throw "Tool definition for '$ToolName' must return a hashtable"
    }

    # Validate required fields
    $required = @('ToolName', 'ExeName', 'Source', 'ExtractType', 'GetSetupDir', 'GetBinDir')
    $missing = $required | Where-Object { -not $def.ContainsKey($_) }
    if ($missing) {
        throw "Tool definition '$ToolName' missing required fields: $($missing -join ', ')"
    }

    if (-not $def.DisplayName) { $def.DisplayName = $def.ToolName }

    # Validate: github-release tools need either GetArchiveName or Repo
    if ($def.Source -eq 'github-release') {
        if (-not $def.Repo) {
            throw "Tool definition '$ToolName' with Source='github-release' must define Repo"
        }
        # API asset discovery mode: no GetArchiveName -> resolved dynamically at download time
    }

    # Optional asset discovery fields with defaults
    if (-not $def.ContainsKey('AssetPlatform'))     { $def.AssetPlatform     = 'windows' }
    if (-not $def.ContainsKey('AssetArch'))          { $def.AssetArch         = 'x86_64' }
    if (-not $def.ContainsKey('AssetExtPreference')) { $def.AssetExtPreference = @('.zip', '.tar.gz', '.exe') }
    if (-not $def.ContainsKey('AssetNamePattern'))   { $def.AssetNamePattern   = $null }
    if (-not $def.ContainsKey('GetInstallDir'))       { $def.GetInstallDir      = $null }

    $def
}

# ═══════════════════════════════════════════════════════════════════════════
# Path Helpers
# ═══════════════════════════════════════════════════════════════════════════

function Get-ToolExePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef,

        [Parameter(Mandatory)]
        [string]$RootDir
    )
    $binDir = & $ToolDef.GetBinDir $RootDir
    Join-Path $binDir $ToolDef.ExeName
}

# ═══════════════════════════════════════════════════════════════════════════
# Version Detection
# ═══════════════════════════════════════════════════════════════════════════

function Get-ToolInstalledVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef
    )

    if (-not $ToolDef.VersionCommand) { return }

    $exePath = Get-ToolExePath -ToolDef $ToolDef -RootDir $global:Tool_RootDir
    if (-not (Test-Path $exePath)) { return }

    try {
        $output = (& $exePath $ToolDef.VersionCommand 2>$null) -join "`n"
        if ($output -and $ToolDef.VersionPattern -and $output -match $ToolDef.VersionPattern) {
            return $Matches[1]
        }
    } catch {}
}

# ═══════════════════════════════════════════════════════════════════════════
# Download URL Construction
# ═══════════════════════════════════════════════════════════════════════════

function Get-ToolDownloadUrl {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef,

        [Parameter(Mandatory)]
        [string]$Version,

        [string]$Tag = ''
    )

    $archiveName = & $ToolDef.GetArchiveName $Version

    switch ($ToolDef.Source) {
        'github-release' {
            $actualTag = if ($Tag) { $Tag } elseif ($ToolDef.TagPrefix) { "$($ToolDef.TagPrefix)$Version" } else { $Version }
            "https://github.com/$($ToolDef.Repo)/releases/download/$actualTag/$archiveName"
        }
        'direct-download' {
            if ($ToolDef.DownloadUrlTemplate) {
                return $ToolDef.DownloadUrlTemplate -f $Version, $archiveName
            }
            throw "Tool '$($ToolDef.ToolName)' has Source='direct-download' but no DownloadUrlTemplate"
        }
        default {
            throw "Unknown source type: $($ToolDef.Source)"
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Status Display
# ═══════════════════════════════════════════════════════════════════════════

function Show-JustStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef,

        [string]$Prefix = "",

        [string]$ConfigFile = ""
    )

    $exePath   = Get-ToolExePath -ToolDef $ToolDef -RootDir $Prefix
    $installed = Get-ToolInstalledVersion -ToolDef $ToolDef
    $locked    = Test-VersionLocked -ToolName $ToolDef.ToolName

    Write-Host "  just - orchestrator for the ohmyclaude toolchain" -ForegroundColor White
    Write-Host "  ==================================================" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Prefix  : $Prefix" -ForegroundColor Cyan
    Write-Host "  Config  : $ConfigFile" -ForegroundColor DarkGray
    if ($installed) {
        Write-Host "  Version : $installed  ($exePath)" -ForegroundColor Green
    } else {
        Write-Host "  Version : not installed" -ForegroundColor Yellow
    }
    if ($locked) {
        Write-Host "  Lock    : $locked" -ForegroundColor Magenta
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Lifecycle: check
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ToolCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef
    )

    $exePath   = Get-ToolExePath -ToolDef $ToolDef -RootDir $global:Tool_RootDir
    $installed = Get-ToolInstalledVersion -ToolDef $ToolDef
    $config    = Get-ToolConfig -ToolDef $ToolDef
    $lockVer   = $config.lock
    $cacheDir  = Get-ToolCacheDir -ToolDef $ToolDef -RootDir $global:Tool_RootDir
    $dn        = $ToolDef.DisplayName

    Write-Host ""
    Write-Host "--- $dn ---" -ForegroundColor Cyan

    # ── Install status ──
    $exeExists = Test-Path $exePath
    if ($installed) {
        Write-Host "[OK] Installed: $($ToolDef.DisplayName) $installed ($exePath)" -ForegroundColor Green
    } elseif ($exeExists) {
        Write-Host "[OK] Installed: $($ToolDef.DisplayName) ($exePath)" -ForegroundColor Green
    } else {
        Write-Host "[INFO] $($ToolDef.DisplayName) not installed" -ForegroundColor Cyan
    }

    # ── Lock status ──
    if ($lockVer) {
        if (($installed -and $installed -eq $lockVer) -or (-not $installed -and $exeExists)) {
            Write-Host "[OK] Locked: $lockVer (current)" -ForegroundColor Green
        } else {
            Write-Host "[LOCK] Locked: $lockVer" -ForegroundColor Magenta
        }
    } else {
        Write-Host "[INFO] No version lock" -ForegroundColor DarkGray
    }

    # ── Cache status ──
    if ($config.asset -and $config.sha256) {
        $cacheFile = Join-Path $cacheDir $config.asset
        if (Test-Path $cacheFile) {
            $actual = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash
            if ($actual -eq $config.sha256) {
                Write-Host "[CACHE] $($config.asset) (verified)" -ForegroundColor Green
            } else {
                Write-Host "[WARN] Hash mismatch: $($config.asset)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[CACHE] Missing: $($config.asset)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "[CACHE] No cache metadata" -ForegroundColor DarkGray
    }

    # ── Companion assets cache status ──
    if ($ToolDef.Assets -and $config.assets) {
        foreach ($cached in $config.assets) {
            $cacheFile = Join-Path $cacheDir $cached.name
            if (Test-Path $cacheFile) {
                $actual = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash
                if ($actual -eq $cached.sha256) {
                    Write-Host "[CACHE] $($cached.name) (verified)" -ForegroundColor Green
                } else {
                    Write-Host "[WARN] Hash mismatch: $($cached.name)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "[CACHE] Missing: $($cached.name)" -ForegroundColor DarkGray
            }
        }
    }

    # ── Companion assets bin status (only if main exe is installed) ──
    if ($ToolDef.Assets -and ($installed -or $exeExists)) {
        $binDir = & $ToolDef.GetBinDir $global:Tool_RootDir
        foreach ($asset in $ToolDef.Assets) {
            $assetPath = Join-Path $binDir $asset.Name
            if (Test-Path $assetPath) {
                Write-Host "[OK] $($asset.Name)" -ForegroundColor DarkGray
            } else {
                Write-Host "[WARN] $($asset.Name) not found in $binDir" -ForegroundColor Yellow
            }
        }
    }
}

function Show-ToolAssets {
    <#
    .SYNOPSIS
        Display companion asset status for tools with Assets.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef
    )
    if (-not $ToolDef.Assets) { return }
    $exePath = Get-ToolExePath -ToolDef $ToolDef -RootDir $global:Tool_RootDir
    if (-not (Test-Path $exePath)) { return }
    $binDir = & $ToolDef.GetBinDir $global:Tool_RootDir
    foreach ($asset in $ToolDef.Assets) {
        $assetPath = Join-Path $binDir $asset.Name
        if (Test-Path $assetPath) {
            Write-Host "[OK] $($asset.Name)" -ForegroundColor DarkGray
        } else {
            Write-Host "[WARN] $($asset.Name) not found" -ForegroundColor Yellow
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Lifecycle: download
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ToolDownload {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef,

        [Parameter(Mandatory)]
        [string]$Version,

        [string]$Tag = ''
    )

    # Resolve archive name and download URL
    $release = $null
    $asset   = $null

    if ($ToolDef.Source -eq 'github-release') {
        # ── Fetch release info for GitHub verification ──
        $tag = if ($Tag) { $Tag } elseif ($ToolDef.TagPrefix) { "$($ToolDef.TagPrefix)$Version" } else { $Version }
        try {
            $release = Get-GitHubRelease -Repo $ToolDef.Repo -Tag $tag
        } catch {
            if ($ToolDef.GetArchiveName) {
                Write-Host "[WARN] Cannot fetch release info, GitHub verification unavailable: $_" -ForegroundColor Yellow
            } else {
                throw "Cannot fetch release for asset discovery: $_"
            }
        }

        if ($ToolDef.GetArchiveName) {
            # ── Hardcoded archive name (backward compatible) ──
            $archiveName = & $ToolDef.GetArchiveName $Version
            $downloadUrl = Get-ToolDownloadUrl -ToolDef $ToolDef -Version $Version -Tag $tag
            if ($release) {
                $asset = $release.assets | Where-Object { $_.name -eq $archiveName } | Select-Object -First 1
            }
        } else {
            # ── API-based asset discovery ──
            if (-not $release) { throw "Release fetch failed, cannot discover asset" }
            $asset = Find-GitHubReleaseAsset `
                -Release $release `
                -Platform $ToolDef.AssetPlatform `
                -Arch $ToolDef.AssetArch `
                -ExtPreference $ToolDef.AssetExtPreference `
                -NamePattern $ToolDef.AssetNamePattern

            $archiveName = $asset.name
            $downloadUrl = $asset.browser_download_url
            Write-Host "[INFO] Discovered: $archiveName" -ForegroundColor DarkGray
        }
    }
    else {
        # ── Non-GitHub sources ──
        $archiveName = & $ToolDef.GetArchiveName $Version
        $downloadUrl = Get-ToolDownloadUrl -ToolDef $ToolDef -Version $Version
    }

    $cacheDir  = Get-ToolCacheDir -ToolDef $ToolDef -RootDir $global:Tool_RootDir
    $zipFile   = Join-Path $cacheDir $archiveName

    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    $dlConfig = Get-ToolConfig -ToolDef $ToolDef

    # ── Download companion assets (runs before main cache check so assets are fetched even on cache hit) ──
    if ($ToolDef.Assets -and $ToolDef.Source -eq 'github-release' -and $release) {
        foreach ($asset in $ToolDef.Assets) {
            $assetFile = Join-Path $cacheDir $asset.Name
            $cachedHash = $null
            if ($dlConfig.assets) {
                $entry = $dlConfig.assets | Where-Object { $_.name -eq $asset.Name } | Select-Object -First 1
                if ($entry) { $cachedHash = $entry.sha256 }
            }
            if ((Test-Path $assetFile) -and $cachedHash) {
                $actualHash = (Get-FileHash -Path $assetFile -Algorithm SHA256).Hash
                if ($actualHash -eq $cachedHash) { continue }
                Write-Host "[WARN] Asset hash mismatch, re-downloading: $($asset.Name)" -ForegroundColor Yellow
            }
            if ((Test-Path $assetFile) -and -not $cachedHash) { continue }
            $matchedAsset = $release.assets | Where-Object { $_.name -match $asset.Pattern } | Select-Object -First 1
            if (-not $matchedAsset) {
                Write-Host "[WARN] Asset not found in release: $($asset.Name) (pattern: $($asset.Pattern))" -ForegroundColor Yellow
                continue
            }
            Write-Host "[INFO] Downloading asset: $($asset.Name) ..." -ForegroundColor Cyan
            $dlOk = $false
            try {
                Save-GitHubReleaseAsset -Repo $ToolDef.Repo -Tag $tag -AssetPattern $matchedAsset.name -OutFile $assetFile
                $dlOk = $true
            } catch {
                Write-Host "[WARN] gh download unavailable, trying direct URL..." -ForegroundColor Yellow
            }
            if (-not $dlOk) {
                try {
                    Invoke-DownloadWithProgress -Url $matchedAsset.browser_download_url -OutFile $assetFile
                    $dlOk = $true
                } catch {
                    Write-Host "[ERROR] Asset download failed: $($asset.Name): $_" -ForegroundColor Red
                }
            }
            if ($dlOk) {
                $assetHash = (Get-FileHash -Path $assetFile -Algorithm SHA256).Hash
                Set-ToolConfig -ToolDef $ToolDef -AssetName $asset.Name -AssetSha256 $assetHash
                Write-Host "[OK] Asset downloaded: $($asset.Name)" -ForegroundColor Green
            }
        }
    }

    # Cache hit: verify against config hash
    if ($dlConfig.asset -eq $archiveName -and $dlConfig.sha256 -and (Test-Path $zipFile)) {
        $actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash
        if ($actualHash -eq $dlConfig.sha256) {
            $size = (Get-Item $zipFile).Length
            if ($size -ge 1MB) { $sizeStr = "{0:N1} MB" -f ($size / 1MB) } else { $sizeStr = "{0:N0} KB" -f ($size / 1KB) }
            Write-Host "[OK] Using cache: $archiveName ($sizeStr)" -ForegroundColor Green
            return $zipFile
        }
        Write-Host "[WARN] Cache hash mismatch, re-downloading" -ForegroundColor Yellow
    }

    if (Test-Path $zipFile) {
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    }

    # Run pre-download hook
    if ($ToolDef.PreDownload) { & $ToolDef.PreDownload -ToolDef $ToolDef -Version $Version }

    Write-Host "[INFO] Downloading $archiveName ..." -ForegroundColor Cyan

    $downloaded = $false

    if ($ToolDef.Source -eq 'github-release') {
        # ── Method 1: gh CLI (authenticated, no rate limit) ──
        try {
            Save-GitHubReleaseAsset -Repo $ToolDef.Repo -Tag $tag -AssetPattern $archiveName -OutFile $zipFile
            $downloaded = $true
        } catch {
            Write-Host "[WARN] gh download unavailable, trying direct URL..." -ForegroundColor Yellow
        }

        # ── Method 2: direct download ──
        if (-not $downloaded) {
            if (-not $downloadUrl) {
                $downloadUrl = "https://github.com/$($ToolDef.Repo)/releases/download/$tag/$archiveName"
            }
            try {
                Invoke-DownloadWithProgress -Url $downloadUrl -OutFile $zipFile
                $downloaded = $true
            } catch {
                Write-Host "[ERROR] Download failed: $_" -ForegroundColor Red
                exit 1
            }
        }
    } else {
        try {
            Invoke-DownloadWithProgress -Url $downloadUrl -OutFile $zipFile
        } catch {
            Write-Host "[ERROR] $_" -ForegroundColor Red
            exit 1
        }
    }

    $actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash

    $attestationOk = $false
    if ($ToolDef.Source -eq 'github-release') {
        $attestationOk = Test-GitHubAssetAttestation -Repo $ToolDef.Repo -Tag $tag -FilePath $zipFile
    }

    if (-not $attestationOk -and $release) {
        try {
            Test-FileHash -FilePath $zipFile -Release $release -AssetName $archiveName -Repo $ToolDef.Repo -Tag $tag | Out-Null
        } catch {
            Write-Host "[ERROR] GitHub digest verification failed: $_" -ForegroundColor Red
            exit 1
        }
    }

    # Cache the downloaded version as lock for future offline installs
    $cacheArgs = @{ ToolDef = $ToolDef; Lock = $Version; Asset = $archiveName; Sha256 = $actualHash }
    Set-ToolConfig @cacheArgs
    Show-LockWrite -Version $Version

    # Run post-download hook
    if ($ToolDef.PostDownload) { & $ToolDef.PostDownload -ToolDef $ToolDef -Version $Version -FilePath $zipFile }

    Write-Host "[OK] Downloaded: $zipFile" -ForegroundColor Green
    $zipFile
}

# ═══════════════════════════════════════════════════════════════════════════
# Lifecycle: install
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ToolInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef,

        [string]$Version,

        [switch]$Update,

        [switch]$Force
    )

    $config    = Get-ToolConfig -ToolDef $ToolDef
    $lockVer   = $config.lock
    $installed = Get-ToolInstalledVersion -ToolDef $ToolDef
    $exePath   = Get-ToolExePath -ToolDef $ToolDef -RootDir $global:Tool_RootDir
    $binDir    = & $ToolDef.GetBinDir $global:Tool_RootDir
    $installDir = if ($ToolDef.GetInstallDir) { & $ToolDef.GetInstallDir $global:Tool_RootDir } else { $binDir }
    $dn        = $ToolDef.DisplayName

    # ── Explicit version specified ──
    $latestTag = $null
    if ($Version) {
        if ($installed -eq $Version -and -not $Force) {
            Show-AlreadyInstalled -Tool $ToolDef.DisplayName -Version $installed -Location $exePath

            if (-not $lockVer) { Set-ToolConfig -ToolDef $ToolDef -Lock $installed }
            if ($ToolDef.PostInstall) {
                & $ToolDef.PostInstall -ToolDef $ToolDef -Version $installed -RootDir $global:Tool_RootDir
            }
            return
        }
        if ($installed) { Write-Host "[INFO] ${dn}: upgrading $installed -> $Version" -ForegroundColor Cyan }
    }
    # ── Update mode: fetch latest, upgrade if newer ──
    elseif ($Update) {
        Write-Host "[INFO] ${dn}: gh release view --repo $($ToolDef.Repo) --json tagName,assets" -ForegroundColor Cyan
        try {
            switch ($ToolDef.Source) {
                'github-release' {
                    $prefixPat = if ($ToolDef.TagPrefix) { "^$([regex]::Escape($ToolDef.TagPrefix))" } else { '^v' }
                    $latestInfo = Get-LatestGitHubVersion -Repo $ToolDef.Repo -PrefixPattern $prefixPat
                    $latestTag = $latestInfo.Tag
                    $Version = $latestInfo.Version
                }
                default { throw "Update not supported for source: $($ToolDef.Source)" }
            }
            Write-Host "[OK] ${dn}: latest is $Version" -ForegroundColor Green
        } catch {
            Write-Host "[ERROR] ${dn}: cannot get latest version: $_" -ForegroundColor Red
            return
        }

        if ($installed) {
            $cmp = Compare-SemanticVersion -Current $installed -Latest $Version
            if ($cmp -ge 0) {
                Show-AlreadyInstalled -Tool $ToolDef.DisplayName -Version $installed -Location $exePath
                if ($lockVer) {
                    if ($installed -eq $lockVer) {
                        Write-Host "[OK] Locked: $lockVer (current)" -ForegroundColor Green
                    } else {
                        Write-Host "[LOCK] Locked: $lockVer" -ForegroundColor Magenta
                    }
                }
                $cacheDir = Get-ToolCacheDir -ToolDef $ToolDef -RootDir $global:Tool_RootDir

                # Populate cache if archive is missing
                $needsCache = $true
                if ($config.asset -and $config.sha256) {
                    $zipFile = Join-Path $cacheDir $config.asset
                    if (Test-Path $zipFile) {
                        $verifyHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash
                        if ($verifyHash -eq $config.sha256) {
                            $needsCache = $false
                        }
                    }
                }

                if ($needsCache) {
                    try {
                        Invoke-ToolDownload -ToolDef $ToolDef -Version $installed | Out-Null
                    } catch {
                        Write-Host "[WARN] Cache download failed: $_" -ForegroundColor Yellow
                    }
                }
                Show-ToolAssets -ToolDef $ToolDef

                if (-not $lockVer) { Set-ToolConfig -ToolDef $ToolDef -Lock $installed }

                if ($ToolDef.PostInstall) {
                    & $ToolDef.PostInstall -ToolDef $ToolDef -Version $installed -RootDir $global:Tool_RootDir
                }
                return
            }
            # Newer version available -> interactive prompt
            Write-Host "[UPGRADE] ${dn}: $installed -> $Version" -ForegroundColor Cyan
            $response = Read-Host "  Upgrade? (Y/n)"
            if ($response -and $response -ne 'Y' -and $response -ne 'y') {
                Write-Host "[INFO] Skipped" -ForegroundColor DarkGray
                return
            }
        }
    }
    # ── No version specified, no update: use lock or fetch ──
    else {
        if ($installed) {
            # Already installed → skip (lock protected)
            $label = if ($lockVer) { "$($ToolDef.DisplayName) (locked)" } else { $ToolDef.DisplayName }
            $ver   = if ($lockVer) { $lockVer } else { $installed }
            Show-AlreadyInstalled -Tool $label -Version $ver -Location $exePath
            Show-ToolAssets -ToolDef $ToolDef

            if (-not $lockVer) { Set-ToolConfig -ToolDef $ToolDef -Lock $installed }

            if ($ToolDef.PostInstall) {
                & $ToolDef.PostInstall -ToolDef $ToolDef -Version $installed -RootDir $global:Tool_RootDir
            }
            return
        }

        # Not installed → use lock version if available
        if ($lockVer) {
            $Version = $lockVer
            Write-Host "[INFO] ${dn}: using locked version $Version" -ForegroundColor Cyan
        } else {
            Write-Host "[INFO] ${dn}: gh release view --repo $($ToolDef.Repo) --json tagName,assets" -ForegroundColor Cyan
            try {
                switch ($ToolDef.Source) {
                    'github-release' {
                        $prefixPat = if ($ToolDef.TagPrefix) { "^$([regex]::Escape($ToolDef.TagPrefix))" } else { '^v' }
                        $latestInfo = Get-LatestGitHubVersion -Repo $ToolDef.Repo -PrefixPattern $prefixPat
                        $latestTag = $latestInfo.Tag
                        $Version = $latestInfo.Version
                    }
                    default { throw "Auto-version detection not supported for source: $($ToolDef.Source)" }
                }
                Write-Host "[OK] ${dn}: latest is $Version" -ForegroundColor Green
            } catch {
                Write-Host "[ERROR] ${dn}: cannot get latest version: $_" -ForegroundColor Red
                Write-Host "       Specify version manually: omc $($ToolDef.ToolName) install -version '<version>'" -ForegroundColor DarkGray
                exit 1
            }
        }
    }

    Write-Host "[INFO] ${dn}: installing $Version" -ForegroundColor Cyan

    # PreInstall hook
    if ($ToolDef.PreInstall) {
        & $ToolDef.PreInstall -ToolDef $ToolDef -Version $Version -RootDir $global:Tool_RootDir
    }

    # Download
    $dlTag = if ($latestTag) { $latestTag } else { '' }
    $zipFile = Invoke-ToolDownload -ToolDef $ToolDef -Version $Version -Tag $dlTag

    # Ensure install dir
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }

    switch ($ToolDef.ExtractType) {
        'standalone' {
            $extractTemp = Join-Path $env:TEMP "ohmyclaude-extract-$($ToolDef.ToolName)"
            if (Test-Path $extractTemp) { Remove-Item $extractTemp -Recurse -Force }
            New-Item -ItemType Directory -Path $extractTemp -Force | Out-Null

            try {
                $assetFileName = Split-Path $zipFile -Leaf
                if ($assetFileName -match '\.zip$') {
                    Expand-Archive -Path $zipFile -DestinationPath $extractTemp -Force -ErrorAction Stop
                } elseif ($assetFileName -match '\.(tar\.gz|tgz|tar\.xz|tar\.bz2|tar)$') {
                    tar -xf $zipFile -C $extractTemp
                    if ($LASTEXITCODE -ne 0) { throw "tar exited with code $LASTEXITCODE" }
                } else {
                    Copy-Item -Path $zipFile -Destination (Join-Path $extractTemp $ToolDef.ExeName) -Force
                }

                $keepPatterns = @($ToolDef.ExeName)
                if ($ToolDef.KeepFiles) { $keepPatterns += $ToolDef.KeepFiles }

                $sourceDir = if ($ToolDef.ArchiveSubdir) { Join-Path $extractTemp $ToolDef.ArchiveSubdir } else { $extractTemp }
                if (-not (Test-Path $sourceDir)) {
                    Write-Host "[ERROR] Archive subdirectory not found: $($ToolDef.ArchiveSubdir)" -ForegroundColor Red
                    exit 1
                }

                $kept = 0
                $failed = 0
                Get-ChildItem -Path $sourceDir -Recurse -File | ForEach-Object {
                    if ($_.Name -in $keepPatterns) {
                        try {
                            Copy-Item -Path $_.FullName -Destination $binDir -Force -ErrorAction Stop
                            $kept++
                        } catch {
                            $failed++
                            Write-Host "[FAIL] $($_.Name): $_" -ForegroundColor Yellow
                        }
                    }
                }
                if ($kept -eq 0 -and $failed -eq 0) {
                    Write-Host "[WARN] No matching files from archive, copying all" -ForegroundColor Yellow
                    Copy-Item -Path "$sourceDir\*" -Destination $binDir -Recurse -Force
                } elseif ($failed -gt 0) {
                    Write-Host "[INFO] Extracted $kept file(s), $failed failed (file in use — close the process and re-run)" -ForegroundColor DarkGray
                } elseif ($kept -gt 0) {
                    Write-Host "[INFO] Extracted $kept file(s)" -ForegroundColor DarkGray
                }
            } finally {
                Remove-Item $extractTemp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        'zip' {
            try {
                Expand-Archive -Path $zipFile -DestinationPath $installDir -Force -ErrorAction Stop
                Write-Host "[INFO] Extracted all files" -ForegroundColor DarkGray
            } catch {
                Write-Host "[ERROR] Extraction failed: $_" -ForegroundColor Red
                exit 1
            }
        }
        'tar' {
            try {
                tar -xf $zipFile -C $installDir
                if ($LASTEXITCODE -ne 0) { throw "tar exited with code $LASTEXITCODE" }
                Write-Host "[INFO] Extracted all files" -ForegroundColor DarkGray
            } catch {
                Write-Host "[ERROR] tar extraction failed: $_" -ForegroundColor Red
                exit 1
            }
        }
        'none' {
            try {
                Copy-Item -Path $zipFile -Destination (Join-Path $binDir $ToolDef.ExeName) -Force
            } catch {
                Write-Host "[ERROR] Copy failed: $_" -ForegroundColor Red
                exit 1
            }
        }
        '7z-sfx' {
            $extractOk = $false
            $7z = Get-Command '7z' -ErrorAction SilentlyContinue
            if ($7z) {
                $null = & $7z.Source x $zipFile "-o$installDir" -y -bso0 2>&1
                $extractOk = $LASTEXITCODE -eq 0
            }
            if (-not $extractOk) {
                try {
                    $proc = Start-Process $zipFile -ArgumentList @("-o$installDir", '-y') -Wait -PassThru -NoNewWindow
                    $extractOk = $proc.ExitCode -eq 0
                } catch { $extractOk = $false }
            }
            if (-not $extractOk) {
                try {
                    $destDir = $installDir.TrimEnd('\')
                    $proc = Start-Process $zipFile -ArgumentList @('/S', "/D=$destDir") -Verb RunAs -Wait -PassThru
                    $extractOk = $proc.ExitCode -eq 0
                } catch {
                    Write-Host "[ERROR] Installer failed: $_" -ForegroundColor Red
                    $extractOk = $false
                }
            }
            if (-not $extractOk) {
                Write-Host "[ERROR] SFX extraction failed" -ForegroundColor Red
                exit 1
            }
        }
        default {
            Write-Host "[ERROR] Unknown ExtractType: $($ToolDef.ExtractType)" -ForegroundColor Red
            exit 1
        }
    }

    $exePath = Get-ToolExePath -ToolDef $ToolDef -RootDir $global:Tool_RootDir
    if (-not (Test-Path $exePath)) {
        Write-Host "[ERROR] Extraction did not produce: $exePath" -ForegroundColor Red
        if ($ToolDef.ArchiveSubdir) {
            Write-Host "       Check ArchiveSubdir: $($ToolDef.ArchiveSubdir)" -ForegroundColor DarkGray
        }
        exit 1
    }

    # Auto-lock after successful install
    Set-ToolConfig -ToolDef $ToolDef -Lock $Version
    Show-LockWrite -Version $Version

    # ── Copy companion assets from cache to bin ──
    if ($ToolDef.Assets) {
        $cacheDir = Get-ToolCacheDir -ToolDef $ToolDef -RootDir $global:Tool_RootDir
        foreach ($asset in $ToolDef.Assets) {
            $cachedAsset = Join-Path $cacheDir $asset.Name
            if (Test-Path $cachedAsset) {
                Copy-Item -Path $cachedAsset -Destination $binDir -Force
                Write-Host "[OK] Installed asset: $($asset.Name)" -ForegroundColor DarkGray
            } else {
                Write-Host "[WARN] Asset not cached: $($asset.Name)" -ForegroundColor Yellow
            }
        }
    }

    # PostInstall hook
    if ($ToolDef.PostInstall) {
        & $ToolDef.PostInstall -ToolDef $ToolDef -Version $Version -RootDir $global:Tool_RootDir
    }

    # Add bin directory to PATH for non-shared bin dirs
    $sharedBins = @(
        (Join-Path $global:Tool_RootDir '.envs\base\bin')
        (Join-Path $global:Tool_RootDir '.envs\tools\bin')
    )
    if ($binDir -notin $sharedBins) {
        Add-UserPath -Dir $binDir
    }

    Show-ToolAssets -ToolDef $ToolDef

    # Verify
    Update-Environment
    $binDir = & $ToolDef.GetBinDir $global:Tool_RootDir
    $normalized = $binDir.TrimEnd('\')
    if ($env:Path -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -eq $normalized }) {
        # already in session PATH
    } else {
        $env:Path = "$normalized;$env:Path"
    }
    $verifyVersion = Get-ToolInstalledVersion -ToolDef $ToolDef
    if ($verifyVersion) {
        Show-InstallComplete -Tool $ToolDef.DisplayName -Version $verifyVersion -NextSteps "Location: $exePath"
    } else {
        Show-InstallComplete -Tool $ToolDef.DisplayName -Version $Version -NextSteps "Location: $exePath`n  Restart terminal if the tool is not found."
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Lifecycle: get (download only, no install)
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ToolDownloadCmd {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef
    )

    $config  = Get-ToolConfig -ToolDef $ToolDef
    $lockVer = $config.lock
    $dn      = $ToolDef.DisplayName

    # Always fetch latest release
    Write-Host "[INFO] ${dn}: gh release view --repo $($ToolDef.Repo) --json tagName,assets" -ForegroundColor Cyan
    $prefixPat = if ($ToolDef.TagPrefix) { "^$([regex]::Escape($ToolDef.TagPrefix))" } else { '^v' }
    $latestInfo = Get-LatestGitHubVersion -Repo $ToolDef.Repo -PrefixPattern $prefixPat
    $ver   = $latestInfo.Version
    $dlTag = $latestInfo.Tag
    Write-Host "[OK] ${dn}: latest is $ver" -ForegroundColor Green

    # If lock exists and matches latest, check cache
    if ($lockVer -and $lockVer -eq $ver) {
        if ($config.asset -and $config.sha256) {
            $cacheDir = Get-ToolCacheDir -ToolDef $ToolDef -RootDir $global:Tool_RootDir
            $zipFile  = Join-Path $cacheDir $config.asset
            if (Test-Path $zipFile) {
                $actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash
                if ($actualHash -eq $config.sha256) {
                    $size = (Get-Item $zipFile).Length
                    if ($size -ge 1MB) { $sizeStr = "{0:N1} MB" -f ($size / 1MB) } else { $sizeStr = "{0:N0} KB" -f ($size / 1KB) }
                    Write-Host "[OK] ${dn}: cached ($ver, $sizeStr)" -ForegroundColor Green
                    Show-ToolAssets -ToolDef $ToolDef
                    return
                }
            }
        }
    }

    # Download latest (Invoke-ToolDownload handles cache hit and updates lock)
    Invoke-ToolDownload -ToolDef $ToolDef -Version $ver -Tag $dlTag | Out-Null
    Show-ToolAssets -ToolDef $ToolDef
}

# ═══════════════════════════════════════════════════════════════════════════
# Lifecycle: uninstall
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ToolUninstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef
    )

    $exePath = Get-ToolExePath -ToolDef $ToolDef -RootDir $global:Tool_RootDir
    if (-not (Test-Path $exePath)) {
        Write-Host "[INFO] $($ToolDef.DisplayName) not installed, nothing to uninstall" -ForegroundColor Cyan
        return
    }

    $version = Get-ToolInstalledVersion -ToolDef $ToolDef
    $label = if ($version) { "$($ToolDef.DisplayName) $version" } else { $ToolDef.DisplayName }

    Write-Host "[INFO] Uninstalling $label ..." -ForegroundColor Cyan

    # PreUninstall hook
    if ($ToolDef.PreUninstall) {
        & $ToolDef.PreUninstall -ToolDef $ToolDef -RootDir $global:Tool_RootDir
    }

    # Remove executable (or entire install directory for non-bin tools)
    $binDir = & $ToolDef.GetBinDir $global:Tool_RootDir
    if ($binDir -ne (Join-Path $global:Tool_RootDir '.envs\base\bin') -and
        $binDir -ne (Join-Path $global:Tool_RootDir '.envs\tools\bin')) {
        if (Test-Path $binDir) {
            try {
                Remove-Item $binDir -Recurse -Force -ErrorAction Stop
                Write-Host "[OK] Removed: $binDir" -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Remove failed: $_" -ForegroundColor Yellow
                Write-Host "       Manual removal: $binDir" -ForegroundColor DarkGray
            }
        }
    } else {
        if (Test-Path $exePath) {
            try {
                Remove-Item $exePath -Force -ErrorAction Stop
                Write-Host "[OK] Removed: $exePath" -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Remove failed: $_" -ForegroundColor Yellow
                Write-Host "       Manual removal: $exePath" -ForegroundColor DarkGray
            }
        }
    }

    # Remove companion assets (bin + cache)
    if ($ToolDef.Assets) {
        $binDir   = & $ToolDef.GetBinDir $global:Tool_RootDir
        $cacheDir = Get-ToolCacheDir -ToolDef $ToolDef -RootDir $global:Tool_RootDir
        foreach ($asset in $ToolDef.Assets) {
            foreach ($dir in @($binDir, $cacheDir)) {
                $assetPath = Join-Path $dir $asset.Name
                if (Test-Path $assetPath) {
                    try {
                        Remove-Item $assetPath -Force -ErrorAction Stop
                        Write-Host "[OK] Removed: $($asset.Name)" -ForegroundColor Green
                    } catch {
                        Write-Host "[WARN] Remove failed: $($asset.Name): $_" -ForegroundColor Yellow
                    }
                }
            }
        }
    }

    # PostUninstall hook
    if ($ToolDef.PostUninstall) {
        & $ToolDef.PostUninstall -ToolDef $ToolDef -RootDir $global:Tool_RootDir
    }

    Write-Host "[OK] $label uninstalled" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# Lifecycle: lock
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-ToolLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef,

        [string]$Version,

        [switch]$Remove
    )

    if ($Remove) {
        Set-VersionLock -ToolName $ToolDef.ToolName -Version ""
        Write-Host "[OK] $($ToolDef.DisplayName) version lock removed" -ForegroundColor Green
        return
    }

    if (-not $Version) {
        $Version = Get-ToolInstalledVersion -ToolDef $ToolDef
        if (-not $Version) {
            Write-Host "[ERROR] $($ToolDef.DisplayName) not installed, cannot auto-detect version" -ForegroundColor Red
            Write-Host "       Specify version: omc $($ToolDef.ToolName) lock -version '<version>'" -ForegroundColor DarkGray
            exit 1
        }
    }

    Set-VersionLock -ToolName $ToolDef.ToolName -Version $Version
    Write-Host "[OK] $($ToolDef.DisplayName) locked to version $Version" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# Lifecycle: help
# ═══════════════════════════════════════════════════════════════════════════

function Show-ToolHelp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ToolDef
    )

    $toolName  = $ToolDef.ToolName
    $display   = $ToolDef.DisplayName
    $configDir = & $ToolDef.GetSetupDir $global:Tool_RootDir
    $cacheDir  = Get-ToolCacheDir -ToolDef $ToolDef -RootDir $global:Tool_RootDir
    $binDir    = & $ToolDef.GetBinDir $global:Tool_RootDir

    Write-Host @"

  $display deployment tool (China-network friendly)

  Usage:
    omc $toolName [command]

  Commands:
    check        Show install status, lock, and cache (local only, no remote)
    get          Download to cache
    install      Install locked version (from cache if available, skip if installed)
    update       Check remote for new version and upgrade if available
    uninstall    Uninstall and clear lock
    lock         Lock to a specific version
    help         Show this help

  Config directory: $configDir
  Cache directory:  $cacheDir
  Install directory: $binDir

  Source: $($ToolDef.Source) | Repo: $($ToolDef.Repo)

"@ -ForegroundColor White
}
