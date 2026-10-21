#Requires -Version 5.1
<#
.SYNOPSIS
    Toolkit self-update: update THIS installer folder from a Git repository.
.DESCRIPTION
    Checks (and optionally applies) a newer version of the toolkit itself,
    published on GitHub. Requires config/settings.json -> selfUpdate to be
    configured. It never overwrites config/settings.json or the cache.
.EXAMPLE
    .\update-toolkit.ps1 -Check
.EXAMPLE
    .\update-toolkit.ps1 -Apply
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Apply,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot 'lib\OpenCodeInstaller.psm1') -Force

$settings = Get-OcSettings -Path (Join-Path $PSScriptRoot 'config\settings.json')
$status = Test-OcToolkitUpdate -Settings $settings

if (-not $status.Supported) {
    if ($Json) { [pscustomobject]@{ ok = $true; supported = $false; current = $status.Current; reason = $status.Reason } | ConvertTo-Json -Depth 4 }
    else { Write-OcMessage ("Self-update is not configured. Current: v{0}" -f $status.Current) 'warn' }
    exit 0
}

if (-not $status.UpdateAvailable) {
    if ($Json) { [pscustomobject]@{ ok = $true; supported = $true; current = $status.Current; latest = $status.Latest; updateAvailable = $false } | ConvertTo-Json -Depth 4 }
    else { Write-OcMessage ("Toolkit is up to date (v{0})." -f $status.Current) 'ok' }
    exit 0
}

if (-not $Apply) {
    if ($Json) { [pscustomobject]@{ ok = $true; supported = $true; current = $status.Current; latest = $status.Latest; updateAvailable = $true } | ConvertTo-Json -Depth 4 }
    else { Write-OcMessage ("New toolkit version available: v{0} -> v{1}. Use -Apply to install it." -f $status.Current, $status.Latest) 'warn' }
    exit 10
}

# Apply: download the repository archive and overlay files (keeping config and cache).
$repo = "$($settings.selfUpdate.repo)".TrimEnd('/')
$ref = $settings.selfUpdate.ref
if (-not $repo) { throw "selfUpdate.repo is not configured in config/settings.json." }
$zipUrl = "$repo/archive/refs/heads/$ref.zip"

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('oc_toolkit_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$zip = Join-Path $tmp 'toolkit.zip'
try {
    Write-OcMessage ("Downloading toolkit v{0} from {1}" -f $status.Latest, $zipUrl) 'info'
    Get-OcDownload -Url $zipUrl -OutFile $zip | Out-Null
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $top = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
    if (-not $top) { throw "Could not extract the toolkit archive." }

    $preserve = @('config\settings.json')
    $root = $top.FullName
    $count = 0
    Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($root.Length).TrimStart('\', '/')
        if ($preserve -contains $rel) { return }
        $dest = Join-Path $PSScriptRoot $rel
        $destDir = Split-Path -Parent $dest
        if ($destDir -and -not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
        $count++
    }
    if ($Json) { [pscustomobject]@{ ok = $true; updated = $true; from = $status.Current; to = $status.Latest; files = $count } | ConvertTo-Json -Depth 4 }
    else {
        Write-OcMessage ("Toolkit updated to v{0} ({1} file(s))." -f $status.Latest, $count) 'ok'
        Write-OcMessage 'Run install.ps1 again to apply the changes.' 'dim'
    }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
exit 0
