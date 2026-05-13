#Requires -Version 5.1

# nushell-evo tool definition - Nushell fork with MCP logging and browse plugin
return @{
    ToolName        = 'nushell'
    DisplayName     = 'nushell'
    ExeName         = 'nu.exe'
    Source          = 'github-release'
    Repo            = 'raystyle/nushell-evo-bin'
    TagPrefix       = 'v'
    ExtractType     = 'standalone'
    KeepFiles       = @(
        'less.exe'
        'nu_plugin_custom_values.exe'
        'nu_plugin_example.exe'
        'nu_plugin_formats.exe'
        'nu_plugin_gstat.exe'
        'nu_plugin_inc.exe'
        'nu_plugin_polars.exe'
        'nu_plugin_query.exe'
    )
    GetSetupDir     = { param($r) "$r\.config\nushell" }
    GetBinDir       = { param($r) "$r\.envs\tools\bin" }
    AssetNamePattern = '^nu-\d+\.\d+\.\d+-x86_64-pc-windows-msvc\.zip$'
    VersionCommand  = '--version'
    VersionPattern  = '(\d+\.\d+\.\d+(?:-evo)?)'
    PostInstall     = {
        param($ToolDef, $Version, $RootDir)
        $binDir = & $ToolDef.GetBinDir -r $RootDir
        $nuExe = Join-Path $binDir 'nu.exe'
        if (-not (Test-Path $nuExe)) { return }

        # Download nu_plugin_browse from separate repo
        $browsePluginRepo = 'raystyle/nu_plugin_bin'
        $browseVersion = $Version -replace '-evo$', ''
        $browseTag = "v$browseVersion"
        $browsePattern = 'nu_plugin_browse-.*-x86_64-pc-windows-msvc\.zip$'
        $browseExe = Join-Path $binDir 'nu_plugin_browse.exe'

        if (-not (Test-Path $browseExe)) {
            Write-Host "[INFO] Downloading nu_plugin_browse from $browsePluginRepo ..." -ForegroundColor Cyan
            try {
                $release = Get-GitHubRelease -Repo $browsePluginRepo -Tag $browseTag
                $asset = $release.assets | Where-Object { $_.name -match $browsePattern } | Select-Object -First 1
                if ($asset) {
                    $tempZip = Join-Path $env:TEMP "nu_plugin_browse-$Version.zip"
                    try {
                        Save-GitHubReleaseAsset -Repo $browsePluginRepo -Tag $browseTag -AssetPattern $asset.name -OutFile $tempZip
                    } catch {
                        Write-Host "[WARN] gh download failed, trying direct URL..." -ForegroundColor Yellow
                        Invoke-DownloadWithProgress -Url $asset.browser_download_url -OutFile $tempZip
                    }
                    $extractTemp = Join-Path $env:TEMP "nu_plugin_browse-extract"
                    if (Test-Path $extractTemp) { Remove-Item $extractTemp -Recurse -Force }
                    Expand-Archive -Path $tempZip -DestinationPath $extractTemp -Force
                    $extracted = Get-ChildItem -Path $extractTemp -Filter 'nu_plugin_browse.exe' -Recurse -File | Select-Object -First 1
                    if ($extracted) {
                        Copy-Item -Path $extracted.FullName -Destination $browseExe -Force
                        Write-Host "[OK] Installed: nu_plugin_browse.exe" -ForegroundColor Green
                    } else {
                        Write-Host "[WARN] nu_plugin_browse.exe not found in archive" -ForegroundColor Yellow
                    }
                    Remove-Item $extractTemp -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
                } else {
                    Write-Host "[WARN] nu_plugin_browse asset not found for tag $browseTag" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "[WARN] Failed to download nu_plugin_browse: $_" -ForegroundColor Yellow
            }
        }

        $nuConfigDir = Join-Path $env:APPDATA 'nushell'
        if (-not (Test-Path $nuConfigDir)) {
            New-Item -ItemType Directory -Path $nuConfigDir -Force | Out-Null
        }

        Get-ChildItem -Path $binDir -Filter 'nu_plugin_*.exe' | ForEach-Object {
            $pluginName = $_.Name
            Write-Host "[INFO] Registering plugin: $pluginName" -ForegroundColor DarkGray
            try {
                $pluginPath = $_.FullName
                $null = & $nuExe -c "plugin add `"$pluginPath`"" 2>&1
                Write-Host "[OK] Plugin registered: $pluginName" -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Failed to register plugin ${pluginName}: $_" -ForegroundColor Yellow
            }
        }
    }
    PreUninstall    = {
        param($ToolDef, $RootDir)
        $binDir = & $ToolDef.GetBinDir $RootDir

        Get-ChildItem -Path $binDir -Filter 'nu_plugin_*.exe' | ForEach-Object {
            try {
                Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                Write-Host "[OK] Removed: $($_.Name)" -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Remove failed: $($_.Name): $_" -ForegroundColor Yellow
            }
        }
    }
}
