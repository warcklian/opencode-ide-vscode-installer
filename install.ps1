#Requires -Version 5.1
<#
.SYNOPSIS
    Portable, adaptive, self-updating installer for the OpenCode CLI.

.DESCRIPTION
    Inspects the machine first (existing OpenCode, PATH, available tools), then
    resolves the latest OpenCode version live, downloads the right package for
    your platform from the npm registry, verifies its SHA-512 integrity and
    installs it. No version number or artifact URL is hardcoded, so it follows
    upstream even if the channel, npm scope or CDN changes.

    It works on a clean machine or on a machine that already has OpenCode /
    Node / npm and adapts accordingly. It asks before changing your PATH.

.PARAMETER Version
    Install a specific version (e.g. 2.0.26). Defaults to the latest available.

.PARAMETER InstallDir
    Installation folder. Defaults to %USERPROFILE%\.opencode\bin (Windows)
    or $HOME/.opencode/bin (macOS/Linux).

.PARAMETER CacheDir
    Package cache folder (useful for offline installs).

.PARAMETER Check
    Only check. Exit code 10 if an install/update is needed, 0 otherwise.

.PARAMETER Update
    Update only if a newer version than the installed one exists.

.PARAMETER DryRun
    Resolve and show the plan without downloading or installing anything.

.PARAMETER Offline
    Do not download: use only the package already present in the cache.

.PARAMETER NoPath
    Do not modify the PATH. Also answers "no" to the PATH prompt.

.PARAMETER Yes
    Assume "yes" to prompts (non-interactive). Adds to PATH without asking.

.PARAMETER NoOllama
    Skip automatic Ollama provider setup even if Ollama is detected.

.PARAMETER Force
    Reinstall even if the version already matches.

.PARAMETER Method
    Force the extraction method: 'tar' or 'built-in'.

.PARAMETER Json
    Machine-readable output (JSON). Implies non-interactive.

.EXAMPLE
    .\install.ps1
.EXAMPLE
    .\install.ps1 -Update
.EXAMPLE
    .\install.ps1 -Check -Json
.EXAMPLE
    .\install.ps1 -Version 2.0.26 -InstallDir C:\tools\opencode -Yes
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$InstallDir,
    [string]$CacheDir,
    [switch]$Force,
    [switch]$Check,
    [switch]$Update,
    [switch]$DryRun,
    [switch]$Offline,
    [switch]$NoPath,
    [switch]$Yes,
    [switch]$NoOllama,
    [ValidateSet('tar', 'built-in')][string]$Method,
    [switch]$Json,
    [switch]$Quiet,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Import-Module (Join-Path $PSScriptRoot 'lib\OpenCodeInstaller.psm1') -Force

function Show-OcHelp {
    Write-Host ''
    Write-OcMessage 'OpenCode Portable Installer' 'title'
    Write-Host '  Portable, adaptive installer/updater for the OpenCode CLI.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Usage: install.ps1 [options]'
    Write-Host ''
    Write-Host '  -Version <v>     Install a specific version (default: latest).'
    Write-Host '  -InstallDir <p>  Installation folder.'
    Write-Host '  -CacheDir <p>    Package cache folder.'
    Write-Host '  -Check           Only check (exit 10 = install/update needed).'
    Write-Host '  -Update          Update only if a newer version exists.'
    Write-Host '  -DryRun          Show the plan without installing.'
    Write-Host '  -Offline         Use only the local cache.'
    Write-Host '  -NoPath          Do not touch the PATH.'
    Write-Host '  -Yes             Assume yes to prompts (non-interactive).'
    Write-Host '  -NoOllama        Skip auto Ollama provider setup.'
    Write-Host '  -Force           Reinstall.'
    Write-Host '  -Method <m>      Force extraction: tar | built-in.'
    Write-Host '  -Json            JSON output.'
    Write-Host '  -Quiet           Minimal output.'
    Write-Host ''
}

function Invoke-OcAutoOllamaSetup {
    param($SystemInfo, [hashtable]$Settings)
    if ($NoOllama) { return $null }
    if (-not $SystemInfo -or -not $SystemInfo.Ollama) { return $null }
    $o = $SystemInfo.Ollama
    if (-not ($o.Found -or $o.Reachable)) { return $null }

    $log = { param($m) }
    if (-not $Quiet -and -not $Json) {
        $log = { param($m) Write-OcMessage ("  " + $m) 'dim' }
        Write-OcMessage '  Ollama detected: registering local models for Ctrl+X M ...' 'info'
    }
    try {
        # If the binary exists but the API is down, still register the endpoint.
        $writeAnyway = [bool]($o.Found -and -not $o.Reachable)
        $r = Install-OcOllamaIntegration -Settings $Settings -TimeoutSec 5 `
            -WriteEvenIfUnreachable:$writeAnyway -Log $log
        if (-not $Json -and -not $Quiet) {
            if ($r.ok -and $r.written) {
                Write-OcMessage ("  Ollama provider written: {0} ({1} model(s))" -f $r.configPath, $r.modelCount) 'ok'
                if ($r.modelCount -eq 0) {
                    Write-OcMessage '  No Ollama models pulled yet. Example: ollama pull qwen2.5-coder:7b' 'warn'
                }
            } elseif ($r.ok) {
                Write-OcMessage '  Ollama provider already configured (nothing new to write).' 'ok'
            } else {
                Write-OcMessage ("  Ollama auto-setup skipped: {0}" -f $r.error) 'warn'
                Write-OcMessage '  You can retry later with: .\setup-ollama.cmd' 'dim'
            }
        }
        return $r
    } catch {
        if (-not $Json -and -not $Quiet) {
            Write-OcMessage ("  Ollama auto-setup failed (OpenCode install is OK): {0}" -f $_.Exception.Message) 'warn'
        }
        return $null
    }
}

function Write-OcResult {
    param($Result)
    if ($Json) { $Result | ConvertTo-Json -Depth 8; return }
    if ($Quiet) { return }
    Write-Host ''
    Write-OcMessage 'OpenCode - summary' 'title'
    Write-Host ("  Action             : {0}" -f $Result.action) -ForegroundColor Gray
    Write-Host ("  Available version  : {0} (source: {1})" -f $Result.available, $Result.source) -ForegroundColor Gray
    Write-Host ("  Previous version   : {0}" -f $(if ($Result.previous) { $Result.previous } else { '(none)' })) -ForegroundColor Gray
    Write-Host ("  Installed version  : {0}" -f $(if ($Result.installed) { $Result.installed } else { '(unknown)' })) -ForegroundColor Gray
    Write-Host ("  Platform           : {0}" -f $Result.target) -ForegroundColor Gray
    Write-Host ("  Package            : {0}" -f $Result.package) -ForegroundColor Gray
    Write-Host ("  Install folder     : {0}" -f $Result.installDir) -ForegroundColor Gray
    Write-Host ("  PATH updated       : {0}" -f $Result.pathAdded) -ForegroundColor Gray
    Write-Host ''
}

if ($Help) { Show-OcHelp; exit 0 }

$settings = Get-OcSettings -Path (Join-Path $PSScriptRoot 'config\settings.json')
$dir = Get-OcInstallDir -Settings $settings -Override $InstallDir
$cache = Get-OcCacheDir -Settings $settings -Override $CacheDir
$os = Get-OcOS
$nonInteractive = $Json -or $Quiet -or (-not (Test-OcInteractive))

if (-not $Json -and -not $Quiet) {
    Write-Host ''
    Write-OcMessage 'OpenCode Portable Installer' 'title'
    Write-OcMessage ("  Toolkit v{0}" -f (Get-OcToolkitVersion)) 'dim'
}

# 1) System inspection (adaptive).
$info = Get-OcSystemInfo -Settings $settings -InstallDir $dir -CacheDir $cache
if (-not $Json -and -not $Quiet) {
    Write-Host ''
    foreach ($line in (Format-OcSystemInfo -Info $info)) {
        Write-Host $line -ForegroundColor DarkGray
    }
    if ($info.ExternalInstall) {
        Write-Host ''
        Write-OcMessage ("  Existing OpenCode detected on PATH: {0} (v{1})" -f $info.PathBinary, $info.PathVersion) 'warn'
    }
    Write-Host ''
}

# 2) Resolve latest version and package.
try {
    $plan = Resolve-OcPlan -Settings $settings -VersionOverride $Version
} catch {
    if ($Json) { [pscustomobject]@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Depth 6 }
    else { Write-OcMessage ("ERROR: {0}" -f $_.Exception.Message) 'error' }
    exit 1
}

$latest = $plan.Version
$installed = Get-OcInstalledVersion -InstallDir $dir -OS $os
$updateAvailable = $false
if ($installed) { $updateAvailable = ((Compare-OcVersion -Left $latest -Right $installed) -gt 0) }

if (-not $Json -and -not $Quiet) {
    Write-OcMessage ("  Available version: {0}  (source: {1})" -f $latest, $plan.Source) 'info'
    Write-OcMessage ("  Installed version: {0}" -f $(if ($installed) { $installed } else { '(none)' })) 'info'
    Write-OcMessage ("  Package          : {0}" -f $plan.Package.Name) 'info'
    Write-OcMessage ("  Tarball          : {0}" -f $plan.Package.Tarball) 'dim'
    Write-Host ''
}

# 3) Check-only mode.
if ($Check) {
    $needed = $updateAvailable -or (-not $installed)
    if ($Json) {
        [pscustomobject]@{
            ok = $true; installed = $installed; available = $latest; updateAvailable = $needed
            target = $plan.Platform.Target; package = $plan.Package.Name
            tarball = $plan.Package.Tarball; source = $plan.Source
            externalInstall = $info.ExternalInstall; externalPath = $info.PathBinary
        } | ConvertTo-Json -Depth 6
    } elseif (-not $Quiet) {
        if ($needed) { Write-OcMessage "  Update available: $(if ($installed) { $installed } else { '(none)' }) -> $latest" 'warn' }
        else { Write-OcMessage "  Already up to date ($latest)." 'ok' }
    }
    if ($needed) { exit 10 } else { exit 0 }
}

# 4) Dry run.
if ($DryRun) {
    if ($Json) {
        [pscustomobject]@{
            ok = $true; dryRun = $true; installed = $installed; available = $latest
            updateAvailable = $updateAvailable; target = $plan.Platform.Target
            package = $plan.Package.Name; tarball = $plan.Package.Tarball
            integrity = $plan.Package.Integrity; source = $plan.Source
            extractMethod = $info.ExtractMethod; installDir = $dir; cacheDir = $cache
            pathContainsInstallDir = $info.PathContainsInstallDir
        } | ConvertTo-Json -Depth 6
    } elseif (-not $Quiet) {
        Write-OcMessage '  [DryRun] Nothing was changed.' 'dim'
    }
    exit 0
}

# 5) Decide whether to install.
$shouldInstall = $true
if (-not $Force -and $installed) {
    if ((Compare-OcVersion -Left $latest -Right $installed) -le 0) { $shouldInstall = $false }
}
# If another OpenCode outside our managed dir is already current, do not create a duplicate.
$externalCurrent = $false
if ($info.ExternalInstall -and $info.PathVersion -and -not $Force) {
    if ((Compare-OcVersion -Left $info.PathVersion -Right $latest) -ge 0) { $externalCurrent = $true }
}
if ($externalCurrent -and -not $installed) { $shouldInstall = $false }

if (-not $shouldInstall) {
    $pathAdded = $false
    $needPath = -not (Test-OcPathContains -Dir $dir) -and (Test-Path (Join-Path $dir (Get-OcBinaryName -OS $os)))
    if ($needPath) { $pathAdded = (Resolve-OcPathConsent $dir $nonInteractive $Yes $NoPath) }
    if (-not $Json -and -not $Quiet) {
        if ($externalCurrent) {
            Write-OcMessage ("  OpenCode is already installed at {0} (v{1}). Nothing to do." -f $info.PathBinary, $info.PathVersion) 'ok'
        } else {
            Write-OcMessage ("  Already up to date ({0}). Not reinstalling." -f $installed) 'ok'
        }
    }
    $ollamaSetup = Invoke-OcAutoOllamaSetup -SystemInfo $info -Settings $settings
    Write-OcResult ([pscustomobject]@{
            ok = $true; action = 'up-to-date'; installed = $installed; previous = $installed; available = $latest
            target = $plan.Platform.Target; package = $plan.Package.Name; source = $plan.Source
            installDir = $dir; cacheDir = $cache; pathAdded = $pathAdded; pathWasPresent = $info.PathContainsInstallDir; updated = $false
            externalInstall = $info.ExternalInstall; externalPath = $info.PathBinary; externalVersion = $info.PathVersion
            ollamaSetup = $ollamaSetup
        })
    exit 0
}

# 6) Install / update.
$action = 'installed'
if ($installed) { $action = 'updated' }
try {
    if (-not $Json -and -not $Quiet) {
        Write-OcMessage ("  {0} OpenCode {1} into {2}" -f $(if ($installed) { 'Updating to' } else { 'Installing' }), $latest, $dir) 'info'
    }
    $log = { param($m) }
    if (-not $Quiet -and -not $Json) { $log = { param($m) Write-OcMessage ("  - " + $m) 'dim' } }
    $installResult = Install-OcBinary -Release $plan.Package -InstallDir $dir -CacheDir $cache -OS $os `
        -ExtractMethod $Method -Force:$Force -Offline:$Offline -Log $log
} catch {
    if ($Json) { [pscustomobject]@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Depth 6 }
    else { Write-OcMessage ("ERROR: {0}" -f $_.Exception.Message) 'error' }
    exit 1
}

# 7) PATH consent (only if needed).
$pathWasPresent = $info.PathContainsInstallDir
$pathAdded = $false
if (-not $pathWasPresent) {
    $pathAdded = Resolve-OcPathConsent $dir $nonInteractive $Yes $NoPath
}

$newVersion = Get-OcInstalledVersion -InstallDir $dir -OS $os

if (-not $Json -and -not $Quiet) {
    if ($newVersion) { Write-OcMessage ("  Verified: opencode {0}" -f $newVersion) 'ok' }
    else { Write-OcMessage '  Warning: could not verify the installed version.' 'warn' }
    if (-not $pathWasPresent -and -not $pathAdded) {
        Write-OcMessage ("  PATH not modified. Add it later with: -Yes  (folder: {0})" -f $dir) 'warn'
    } elseif ($pathAdded) {
        Write-OcMessage '  PATH updated. Restart your terminal to use "opencode".' 'info'
    }
    Write-OcMessage '  Done. Open the Cursor integrated terminal and run: opencode' 'info'
}

$ollamaSetup = Invoke-OcAutoOllamaSetup -SystemInfo $info -Settings $settings

Write-OcResult ([pscustomobject]@{
        ok = $true; action = $action; installed = $newVersion; previous = $installed; available = $latest
        target = $plan.Platform.Target; package = $plan.Package.Name
        tarball = $plan.Package.Tarball; integrity = $plan.Package.Integrity; source = $plan.Source
        extractMethod = $installResult.Method; installDir = $dir; cacheDir = $cache
        pathAdded = $pathAdded; pathWasPresent = $pathWasPresent; updated = $true
        externalInstall = $info.ExternalInstall; externalPath = $info.PathBinary; externalVersion = $info.PathVersion
        ollamaSetup = $ollamaSetup
    })
exit 0
