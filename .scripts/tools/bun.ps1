#Requires -Version 5.1

# bun - JavaScript runtime, bundler, test runner, and package manager (oven-sh/bun)
return @{
    ToolName       = 'bun'
    DisplayName    = 'bun'
    ExeName        = 'bun.exe'
    Source         = 'github-release'
    Repo           = 'oven-sh/bun'
    TagPrefix      = 'bun-v'
    GetArchiveName = { param($v) "bun-windows-x64.zip" }
    ExtractType    = 'standalone'
    GetSetupDir    = { param($r) "$r\.config\bun" }
    GetBinDir      = { param($r) "$r\.envs\tools\bin" }
    VersionCommand = '--version'
    VersionPattern = '(\d+\.\d+\.\d+)'
    PostInstall    = {
        param($ToolDef, $Version, $RootDir)

        $bunInstall    = Join-Path $RootDir '.envs\tools\bun'
        $bunCacheDir   = Join-Path $RootDir '.cache\tools\bun\install'
        $bunBinDir     = Join-Path $bunInstall 'bin'
        $bunTranspiler = Join-Path $RootDir '.cache\tools\bun\transpiler'

        foreach ($dir in @($bunInstall, $bunCacheDir, $bunBinDir, $bunTranspiler)) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }

        $envVars = [ordered]@{
            BUN_INSTALL                    = $bunInstall
            BUN_INSTALL_CACHE_DIR          = $bunCacheDir
            BUN_RUNTIME_TRANSPILER_CACHE_PATH = $bunTranspiler
        }
        foreach ($entry in $envVars.GetEnumerator()) {
            $current = [Environment]::GetEnvironmentVariable($entry.Key, 'User')
            if ($current -ne $entry.Value) {
                [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'User')
                Set-Item -Path "env:$($entry.Key)" -Value $entry.Value
                Write-Host "[OK] $($entry.Key) = $($entry.Value)" -ForegroundColor Green
            }
        }

        Add-UserPath -Dir $bunBinDir

        # Write global bunfig.toml with npmmirror registry
        $bunfigPath = Join-Path $env:USERPROFILE '.bunfig.toml'
        $bunfigContent = @'
[install]
registry = "https://registry.npmmirror.com"
'@
        $writeBunfig = $true
        if (Test-Path $bunfigPath) {
            $existing = Get-Content $bunfigPath -Raw -ErrorAction SilentlyContinue
            if ($existing -and $existing -match 'registry\s*=\s*"https://registry\.npmmirror\.com"') {
                $writeBunfig = $false
            }
        }
        if ($writeBunfig) {
            $noBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($bunfigPath, $bunfigContent, $noBom)
            Write-Host "[OK] ~/.bunfig.toml: registry = npmmirror" -ForegroundColor Green
        } else {
            Write-Host "[OK] ~/.bunfig.toml: already configured" -ForegroundColor DarkGray
        }
    }
    PostUninstall  = {
        param($ToolDef, $RootDir)

        $bunInstall = Join-Path $RootDir '.envs\tools\bun'
        $bunBinDir  = Join-Path $bunInstall 'bin'

        foreach ($var in @('BUN_INSTALL', 'BUN_INSTALL_CACHE_DIR', 'BUN_RUNTIME_TRANSPILER_CACHE_PATH')) {
            [Environment]::SetEnvironmentVariable($var, $null, 'User')
            Set-Item -Path "env:$var" -Value $null
        }
        Write-Host '[OK] Bun environment variables removed' -ForegroundColor Green

        Remove-UserPath -Dir $bunBinDir

        $bunCache = Join-Path $RootDir '.cache\tools\bun'
        if (Test-Path $bunCache) {
            Remove-Item $bunCache -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Removed: $bunCache" -ForegroundColor Green
        }
        if (Test-Path $bunInstall) {
            Remove-Item $bunInstall -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Removed: $bunInstall" -ForegroundColor Green
        }

        $bunfigPath = Join-Path $env:USERPROFILE '.bunfig.toml'
        if (Test-Path $bunfigPath) {
            Remove-Item $bunfigPath -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Removed: $bunfigPath" -ForegroundColor Green
        }
    }
}
