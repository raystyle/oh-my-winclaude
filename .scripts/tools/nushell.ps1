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
        'nu_plugin_browse.exe'
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
    VersionPattern  = '(\d+\.\d+\.\d+)'
    PostInstall     = {
        param($ToolDef, $Version, $RootDir)
        $binDir = & $ToolDef.GetBinDir -r $RootDir
        $nuExe = Join-Path $binDir 'nu.exe'
        if (-not (Test-Path $nuExe)) { return }

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
