#Requires -Version 5.1
<#
.SYNOPSIS
    Uninstall OpenCode from this machine (binary and, optionally, PATH and cache).
.DESCRIPTION
    It does not touch your OpenCode sessions or user configuration
    (~/.local/share, ~/.config, %APPDATA%). It only removes the binary installed
    by this toolkit.
.PARAMETER InstallDir
    Installation folder. Defaults to the same one used by install.ps1.
.PARAMETER RemovePath
    Remove the folder from the user PATH.
.PARAMETER Purge
    Also remove the installation folder (if empty) and the package cache.
.PARAMETER Json
    JSON output.
.EXAMPLE
    .\uninstall.ps1 -Purge -RemovePath
#>
[CmdletBinding()]
param(
    [string]$InstallDir,
    [switch]$RemovePath,
    [switch]$Purge,
    [switch]$Json,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\OpenCodeInstaller.psm1') -Force

if ($Help) {
    Write-Host ''
    Write-OcMessage 'OpenCode Portable - Uninstall' 'title'
    Write-Host '  Usage: uninstall.ps1 [-InstallDir <path>] [-RemovePath] [-Purge] [-Json]'
    Write-Host ''
    exit 0
}

$settings = Get-OcSettings -Path (Join-Path $PSScriptRoot 'config\settings.json')
$dir = Get-OcInstallDir -Settings $settings -Override $InstallDir

$removed = Remove-OcInstall -InstallDir $dir -RemovePath:$RemovePath -Purge:$Purge

if ($Purge) {
    $cache = Get-OcCacheDir -Settings $settings
    if (Test-Path $cache) { Remove-Item -Recurse -Force $cache -ErrorAction SilentlyContinue }
}

if ($Json) {
    [pscustomobject]@{
        ok = $true; removed = @($removed); installDir = $dir
        removePath = [bool]$RemovePath; purge = [bool]$Purge
    } | ConvertTo-Json -Depth 4
} else {
    Write-Host ''
    if ($removed.Count -gt 0) {
        Write-OcMessage ("OpenCode uninstalled ({0} file(s))." -f $removed.Count) 'ok'
        foreach ($f in $removed) { Write-OcMessage ("  - " + $f) 'dim' }
    } else {
        Write-OcMessage "Nothing to uninstall in $dir" 'warn'
    }
    if ($RemovePath) { Write-OcMessage 'User PATH updated.' 'dim' }
    Write-Host ''
}
exit 0
