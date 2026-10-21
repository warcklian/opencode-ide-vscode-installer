# OpenCodeInstaller.psm1
# Core logic for the portable, self-updating OpenCode installer.
# Compatible with Windows PowerShell 5.1+ and PowerShell 7+ (Windows/macOS/Linux).
#
# Self-update principle: it NEVER hardcodes a version number or an artifact URL.
# The version is resolved live and the tarball URL is read from the npm registry
# itself (dist.tarball), so if upstream changes channel, npm scope or CDN, this
# installer follows it.
#
# Adaptive principle: it inspects the machine first (existing OpenCode, PATH,
# available tools), decides the safest installation method and only asks for the
# permissions it needs (for example, adding itself to PATH).

# --- Toolkit metadata --------------------------------------------------------

$script:ToolkitVersion = '0.0.0'
$script:ToolkitName = 'opencode-ide-vscode-installer'

$toolkitVersionFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'version.json'
if (Test-Path $toolkitVersionFile) {
  try {
    $meta = Get-Content -Raw -Path $toolkitVersionFile | ConvertFrom-Json
    if ($meta.version) { $script:ToolkitVersion = "$($meta.version)" }
  } catch { }
}

# --- Default settings --------------------------------------------------------

$script:DefaultSettings = @{
  channel       = 'latest'
  pinnedVersion = ''
  installDir    = ''
  cacheDir      = ''
  sources       = @{
    # Official endpoint used by the OpenCode installer to resolve the latest version.
    updateApi    = 'https://opencode.ai/update/api/latest/cli/npm'
    # npm registry: provides version+scope and, per package, dist.tarball + dist.integrity.
    npmRegistry  = 'https://registry.npmjs.org'
    scope        = '@opencode'
    legacyScope  = '@opencode-ai'
    # Third fallback source (version number only).
    githubLatest = 'https://api.github.com/repos/anomalyco/opencode/releases/latest'
  }
  selfUpdate    = @{
    enabled     = $false
    manifestUrl = ''
    repo        = ''
    ref         = 'main'
  }
}

# --- Internal helpers --------------------------------------------------------

function Invoke-OcLog {
  param($Log, [string]$Message)
  if ($Log) { & $Log $Message } else { Write-Host $Message }
}

function ConvertTo-OcHashtable {
  param($Object)
  if ($null -eq $Object) { return $null }
  if ($Object -is [System.Collections.IDictionary]) {
    $h = @{}
    foreach ($k in $Object.Keys) { $h[$k] = ConvertTo-OcHashtable $Object[$k] }
    return $h
  }
  if ($Object -is [System.Management.Automation.PSCustomObject]) {
    $h = @{}
    foreach ($p in $Object.PSObject.Properties) { $h[$p.Name] = ConvertTo-OcHashtable $p.Value }
    return $h
  }
  if ($Object -is [System.Collections.IEnumerable] -and $Object -isnot [string]) {
    return @($Object | ForEach-Object { ConvertTo-OcHashtable $_ })
  }
  return $Object
}

function Merge-OcHashtable {
  param([hashtable]$Base, [hashtable]$Override)
  $out = @{}
  foreach ($k in $Base.Keys) { $out[$k] = $Base[$k] }
  foreach ($k in $Override.Keys) {
    if ($out.ContainsKey($k) -and $out[$k] -is [hashtable] -and $Override[$k] -is [hashtable]) {
      $out[$k] = Merge-OcHashtable -Base $out[$k] -Override $Override[$k]
    } else {
      $out[$k] = $Override[$k]
    }
  }
  return $out
}

function ConvertTo-OcPlainPath {
  param([string]$Path)
  if (-not $Path) { return '' }
  return $Path.TrimEnd('\', '/')
}

# --- Messaging ---------------------------------------------------------------

function Write-OcMessage {
  param([string]$Message, [ValidateSet('info', 'ok', 'warn', 'error', 'dim', 'title')][string]$Level = 'info')
  $color = 'Gray'
  switch ($Level) {
    'ok'    { $color = 'Green' }
    'warn'  { $color = 'Yellow' }
    'error' { $color = 'Red' }
    'dim'   { $color = 'DarkGray' }
    'title' { $color = 'Cyan' }
  }
  Write-Host $Message -ForegroundColor $color
}

# --- Configuration -----------------------------------------------------------

function Get-OcSettings {
  param([string]$Path)
  $defaults = ConvertTo-OcHashtable $script:DefaultSettings
  if ($Path -and (Test-Path $Path)) {
    try {
      $user = ConvertTo-OcHashtable (Get-Content -Raw -Path $Path | ConvertFrom-Json)
      return (Merge-OcHashtable -Base $defaults -Override $user)
    } catch {
      Write-OcMessage "Warning: could not read configuration '$Path' ($($_.Exception.Message)). Using defaults." 'warn'
    }
  }
  return $defaults
}

function Get-OcToolkitVersion { return $script:ToolkitVersion }
function Get-OcToolkitName { return $script:ToolkitName }

# --- Tool / environment detection -------------------------------------------

function Get-OcCommandPath {
  param([Parameter(Mandatory)][string]$Name)
  $c = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  return $null
}

function Test-OcCommand {
  param([Parameter(Mandatory)][string]$Name)
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-OcInteractive {
  try {
    if ([Console]::IsInputRedirected) { return $false }
    if (-not [Environment]::UserInteractive) { return $false }
    return $true
  } catch { return $false }
}

function Read-OcYesNo {
  param(
    [Parameter(Mandatory)][string]$Question,
    [bool]$Default = $true,
    [switch]$ForceYes,
    [switch]$ForceNo
  )
  if ($ForceNo) { return $false }
  if ($ForceYes) { return $true }
  if (-not (Test-OcInteractive)) { return $Default }
  $hint = ' [Y/n] '
  if (-not $Default) { $hint = ' [y/N] ' }
  while ($true) {
    $ans = Read-Host ($Question + $hint)
    if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
    switch ($ans.Trim().ToLowerInvariant()) {
      'y' { return $true }
      'yes' { return $true }
      'n' { return $false }
      'no' { return $false }
      default { Write-OcMessage 'Please answer "y" or "n".' 'warn' }
    }
  }
}

# --- Platform detection ------------------------------------------------------

function Get-OcOS {
  if ($env:OS -eq 'Windows_NT') { return 'windows' }
  try {
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) { return 'darwin' }
  } catch { }
  return 'linux'
}

function Get-OcArch {
  $pa = "$env:PROCESSOR_ARCHITECTURE"
  $pae = "$env:PROCESSOR_ARCHITEW6432"
  if ($pa -match 'ARM64' -or $pae -match 'ARM64') { return 'arm64' }
  if ($pa -match 'ARM' -or $pae -match 'ARM') { return 'arm' }
  try {
    $rt = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if ("$rt" -match 'Arm64') { return 'arm64' }
  } catch { }
  return 'x64'
}

function Test-OcAvx2 {
  param([string]$OS = (Get-OcOS))
  switch ($OS) {
    'windows' {
      try {
        if (-not ([System.Management.Automation.PSTypeName]'OcNative.Kernel32').Type) {
          Add-Type -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(int ProcessorFeature);' -Name Kernel32 -Namespace OcNative -ErrorAction SilentlyContinue | Out-Null
        }
        return [bool][OcNative.Kernel32]::IsProcessorFeaturePresent(40)
      } catch { return $false }
    }
    'darwin' {
      try { return ("$(& sysctl -n hw.optional.avx2_0 2>$null)".Trim() -eq '1') } catch { return $false }
    }
    'linux' {
      try {
        if (Test-Path '/proc/cpuinfo') {
          return [bool](Select-String -Path '/proc/cpuinfo' -Pattern '\bavx2\b' -Quiet)
        }
      } catch { }
      return $false
    }
    default { return $false }
  }
}

function Test-OcMusl {
  try { if (Test-Path '/etc/alpine-release') { return $true } } catch { }
  try {
    $out = & ldd --version 2>&1
    if (("$out") -match 'musl') { return $true }
  } catch { }
  return $false
}

function Get-OcPlatform {
  param(
    [string]$OS,
    [string]$Arch,
    [Nullable[bool]]$Baseline,
    [Nullable[bool]]$Musl
  )
  if (-not $OS) { $OS = Get-OcOS }
  if (-not $Arch) { $Arch = Get-OcArch }
  $OS = $OS.ToLowerInvariant()
  $Arch = $Arch.ToLowerInvariant()

  if ($Arch -eq 'aarch64') { $Arch = 'arm64' }
  if ($Arch -eq 'amd64') { $Arch = 'x64' }
  if ($Arch -eq 'x86_64') { $Arch = 'x64' }

  $isMusl = $false
  if ($null -ne $Musl) { $isMusl = [bool]$Musl } elseif ($OS -eq 'linux') { $isMusl = Test-OcMusl }

  $isBaseline = $false
  if ($Arch -eq 'x64') {
    if ($null -ne $Baseline) { $isBaseline = [bool]$Baseline } else { $isBaseline = -not (Test-OcAvx2 -OS $OS) }
  }

  $target = "$OS-$Arch"
  if ($isBaseline) { $target += '-baseline' }
  if ($isMusl) { $target += '-musl' }

  return [pscustomobject]@{
    OS       = $OS
    Arch     = $Arch
    Target   = $target
    Baseline = $isBaseline
    Musl     = $isMusl
  }
}

function Get-OcBinaryName {
  param([string]$OS = (Get-OcOS))
  if ($OS -eq 'windows') { return 'opencode.exe' }
  return 'opencode'
}

# --- Version comparison ------------------------------------------------------

function ConvertTo-OcVersionTuple {
  param([string]$Version)
  $v = "$Version".Trim()
  if ($v.StartsWith('v') -or $v.StartsWith('V')) { $v = $v.Substring(1) }
  $pre = ''
  $dash = $v.IndexOf('-')
  if ($dash -ge 0) {
    $pre = $v.Substring($dash + 1)
    $v = $v.Substring(0, $dash)
  }
  $plus = $pre.IndexOf('+')
  if ($plus -ge 0) { $pre = $pre.Substring(0, $plus) }
  $nums = @(0, 0, 0)
  $parts = @($v.Split('.'))
  for ($i = 0; $i -lt 3; $i++) {
    if ($i -lt $parts.Count) {
      $n = 0
      [void][int]::TryParse(($parts[$i] -replace '[^0-9].*$', ''), [ref]$n)
      $nums[$i] = $n
    }
  }
  return [pscustomobject]@{ Nums = $nums; Pre = $pre }
}

function Compare-OcVersion {
  param([Parameter(Mandatory)][string]$Left, [Parameter(Mandatory)][string]$Right)
  $a = ConvertTo-OcVersionTuple -Version $Left
  $b = ConvertTo-OcVersionTuple -Version $Right
  for ($i = 0; $i -lt 3; $i++) {
    if ($a.Nums[$i] -lt $b.Nums[$i]) { return -1 }
    if ($a.Nums[$i] -gt $b.Nums[$i]) { return 1 }
  }
  if ($a.Pre -eq $b.Pre) { return 0 }
  if ($a.Pre -eq '') { return 1 }
  if ($b.Pre -eq '') { return -1 }
  $c = [string]::CompareOrdinal($a.Pre, $b.Pre)
  if ($c -lt 0) { return -1 }
  if ($c -gt 0) { return 1 }
  return 0
}

# --- HTTP --------------------------------------------------------------------

function Invoke-OcRequest {
  param(
    [Parameter(Mandatory)][string]$Uri,
    [int]$Retries = 3,
    [int]$TimeoutSec = 90,
    [switch]$AllowNotFound
  )
  $ProgressPreference = 'SilentlyContinue'
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
  $ua = "$script:ToolkitName/$script:ToolkitVersion"
  for ($i = 1; $i -le $Retries; $i++) {
    try {
      $resp = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec $TimeoutSec -UserAgent $ua
      return $resp.Content
    } catch {
      $status = $null
      try { $status = [int]$_.Exception.Response.StatusCode } catch { }
      if ($status -eq 404) {
        if ($AllowNotFound) { return $null }
        throw
      }
      if ($i -eq $Retries) { throw }
      Start-Sleep -Seconds (2 * $i)
    }
  }
}

# --- Response parsers (string -> object; unit-testable) ----------------------

function ConvertFrom-OcUpdateApiResponse {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)
  $j = $Json | ConvertFrom-Json
  $pkg = ''
  if ($j.PSObject.Properties['metadata'] -and $j.metadata -and $j.metadata.PSObject.Properties['package']) {
    $pkg = "$($j.metadata.package)"
  }
  return [pscustomobject]@{ Version = "$($j.version)"; Package = $pkg; Source = 'update-api' }
}

function ConvertFrom-OcNpmLatestResponse {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)
  $j = $Json | ConvertFrom-Json
  $name = ''
  if ($j.PSObject.Properties['name']) { $name = "$($j.name)" }
  return [pscustomobject]@{ Version = "$($j.version)"; Package = $name; Source = 'npm' }
}

function ConvertFrom-OcGithubReleaseResponse {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)
  $j = $Json | ConvertFrom-Json
  $tag = ''
  if ($j.PSObject.Properties['tag_name']) { $tag = "$($j.tag_name)" }
  elseif ($j.PSObject.Properties['name']) { $tag = "$($j.name)" }
  if ($tag.StartsWith('v') -or $tag.StartsWith('V')) { $tag = $tag.Substring(1) }
  return [pscustomobject]@{ Version = $tag; Package = ''; Source = 'github' }
}

function ConvertFrom-OcRegistryDocument {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)
  $j = $Json | ConvertFrom-Json
  $tarball = ''
  $integrity = ''
  if ($j.PSObject.Properties['dist'] -and $j.dist) {
    if ($j.dist.PSObject.Properties['tarball']) { $tarball = "$($j.dist.tarball)" }
    if ($j.dist.PSObject.Properties['integrity']) { $integrity = "$($j.dist.integrity)" }
  }
  return [pscustomobject]@{ Name = "$($j.name)"; Version = "$($j.version)"; Tarball = $tarball; Integrity = $integrity }
}

# --- Latest version resolution ----------------------------------------------

function Get-OcLatestInfo {
  param([hashtable]$Settings)
  if (-not $Settings) { $Settings = ConvertTo-OcHashtable $script:DefaultSettings }
  $errors = @()

  if ($Settings.sources.updateApi) {
    try {
      $content = Invoke-OcRequest -Uri $Settings.sources.updateApi
      $r = ConvertFrom-OcUpdateApiResponse -Json $content
      if ($r.Version) { return $r }
      $errors += 'update-api: response without a version'
    } catch { $errors += "update-api: $($_.Exception.Message)" }
  }

  $npmLatest = ($Settings.sources.npmRegistry.TrimEnd('/')) + '/' + [uri]::EscapeDataString("$($Settings.sources.scope)/cli") + '/latest'
  try {
    $content = Invoke-OcRequest -Uri $npmLatest
    $r = ConvertFrom-OcNpmLatestResponse -Json $content
    if ($r.Version) { return $r }
    $errors += 'npm: response without a version'
  } catch { $errors += "npm: $($_.Exception.Message)" }

  if ($Settings.sources.githubLatest) {
    try {
      $content = Invoke-OcRequest -Uri $Settings.sources.githubLatest
      $r = ConvertFrom-OcGithubReleaseResponse -Json $content
      if ($r.Version) { return $r }
      $errors += 'github: response without a version'
    } catch { $errors += "github: $($_.Exception.Message)" }
  }

  throw "Could not resolve the latest OpenCode version. Attempts -> $($errors -join ' | ')"
}

# --- Package/tarball resolution ---------------------------------------------

function Resolve-OcPackage {
  param(
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$Target,
    [hashtable]$Settings
  )
  if (-not $Settings) { $Settings = ConvertTo-OcHashtable $script:DefaultSettings }
  $registry = $Settings.sources.npmRegistry.TrimEnd('/')
  $candidates = @(
    ("$($Settings.sources.scope)/cli-$Target"),
    ("$($Settings.sources.legacyScope)/cli-$Target")
  ) | Select-Object -Unique

  $tried = @()
  foreach ($name in $candidates) {
    $encoded = [uri]::EscapeDataString($name)
    $url = "$registry/$encoded/$Version"
    $tried += $name
    try {
      $content = Invoke-OcRequest -Uri $url -AllowNotFound
      if (-not $content) { continue }
      $doc = ConvertFrom-OcRegistryDocument -Json $content
      if ($doc.Tarball) {
        return [pscustomobject]@{
          Name      = $name
          Version   = $Version
          Target    = $Target
          Tarball   = $doc.Tarball
          Integrity = $doc.Integrity
        }
      }
    } catch {
      Write-OcMessage "Warning: failed to query '$url' ($($_.Exception.Message))" 'warn'
    }
  }
  throw "No package available for target '$Target' version '$Version'. Tried: $($tried -join ', ')"
}

function Resolve-OcPlan {
  param([hashtable]$Settings, [string]$VersionOverride)
  if (-not $Settings) { $Settings = ConvertTo-OcHashtable $script:DefaultSettings }
  $platform = Get-OcPlatform

  $version = $VersionOverride
  if (-not $version -and $Settings.pinnedVersion) { $version = "$($Settings.pinnedVersion)" }

  $info = $null
  if (-not $version) {
    $info = Get-OcLatestInfo -Settings $Settings
    $version = $info.Version
  }

  $source = 'pinned'
  if ($info) { $source = $info.Source }

  $pkg = Resolve-OcPackage -Version $version -Target $platform.Target -Settings $Settings

  return [pscustomobject]@{
    Version  = $version
    Platform = $platform
    Package  = $pkg
    Source   = $source
  }
}

# --- Integrity and download --------------------------------------------------

function Test-OcIntegrity {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Integrity
  )
  if (-not $Integrity) { return $true }
  if ($Integrity -notmatch '^(sha512|sha384|sha256|sha1)-(.+)$') {
    Write-OcMessage "Warning: unrecognized integrity format ('$Integrity'); skipping verification." 'warn'
    return $true
  }
  $algo = $Matches[1].ToUpperInvariant()
  $expected = $Matches[2]
  $hasher = [System.Security.Cryptography.HashAlgorithm]::Create($algo)
  $stream = [System.IO.File]::OpenRead($Path)
  try {
    $hash = $hasher.ComputeHash($stream)
  } finally {
    $stream.Dispose(); $hasher.Dispose()
  }
  $actual = [Convert]::ToBase64String($hash)
  return ($actual -eq $expected)
}

function Get-OcDownload {
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$OutFile,
    [string]$Integrity,
    [int]$Retries = 3
  )
  $ProgressPreference = 'SilentlyContinue'
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
  $dir = Split-Path -Parent $OutFile
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $ua = "$script:ToolkitName/$script:ToolkitVersion"
  for ($i = 1; $i -le $Retries; $i++) {
    try {
      if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
      Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 600 -UserAgent $ua
      if ($Integrity) {
        if (-not (Test-OcIntegrity -Path $OutFile -Integrity $Integrity)) {
          throw "Integrity verification failed for $OutFile"
        }
      }
      return $OutFile
    } catch {
      if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
      if ($i -eq $Retries) { throw }
      Start-Sleep -Seconds (2 * $i)
    }
  }
}

# --- Extraction (no external dependency required) ----------------------------

function Resolve-OcExtractMethod {
  # Prefer the system 'tar'; otherwise use the built-in .NET gzip+tar reader.
  if (Test-OcCommand 'tar') { return 'tar' }
  return 'built-in'
}

function Expand-OcTarballManaged {
  # Pure .NET gzip + tar reader. Used when the system 'tar' is unavailable.
  param(
    [Parameter(Mandatory)][string]$Tarball,
    [Parameter(Mandatory)][string]$Destination
  )
  Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue | Out-Null
  if (-not (Test-Path $Destination)) { New-Item -ItemType Directory -Force -Path $Destination | Out-Null }

  $inStream = [System.IO.File]::OpenRead($Tarball)
  try {
    $gzip = New-Object System.IO.Compression.GZipStream($inStream, [System.IO.Compression.CompressionMode]::Decompress)
    try {
      $tarStream = New-Object System.IO.MemoryStream
      try { $gzip.CopyTo($tarStream); $data = $tarStream.ToArray() }
      finally { $tarStream.Dispose() }
    } finally { $gzip.Dispose() }
  } finally { $inStream.Dispose() }

  $offset = 0
  $len = $data.Length
  while (($offset + 512) -le $len) {
    $isZero = $true
    for ($i = 0; $i -lt 512; $i++) { if ($data[$offset + $i] -ne 0) { $isZero = $false; break } }
    if ($isZero) { break }

    $name = [System.Text.Encoding]::ASCII.GetString($data, $offset, 100).TrimEnd([char]0)
    $prefix = [System.Text.Encoding]::ASCII.GetString($data, $offset + 345, 155).TrimEnd([char]0)
    if ($prefix) { $name = "$prefix/$name" }

    $sizeStr = ([System.Text.Encoding]::ASCII.GetString($data, $offset + 124, 12)).Trim([char]0, [char]32)
    $size = 0
    if ($sizeStr) { try { $size = [Convert]::ToInt64($sizeStr, 8) } catch { $size = 0 } }
    $type = [char]$data[$offset + 156]
    $offset += 512

    if (($type -eq '0' -or [int]$type -eq 0) -and $size -ge 0) {
      $outPath = Join-Path $Destination ($name -replace '/', [System.IO.Path]::DirectorySeparatorChar)
      $outDir = Split-Path -Parent $outPath
      if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
      if ($size -gt 0) {
        $bytes = New-Object byte[] $size
        [Array]::Copy($data, $offset, $bytes, 0, $size)
        [System.IO.File]::WriteAllBytes($outPath, $bytes)
      } else {
        [System.IO.File]::WriteAllBytes($outPath, (New-Object byte[] 0))
      }
    }
    $offset += ([math]::Ceiling($size / 512.0) * 512)
  }
}

function Expand-OcTarball {
  # Returns the method actually used: 'tar' or 'built-in'.
  param(
    [Parameter(Mandatory)][string]$Tarball,
    [Parameter(Mandatory)][string]$Destination,
    [string]$Method
  )
  if (-not (Test-Path $Destination)) { New-Item -ItemType Directory -Force -Path $Destination | Out-Null }
  if (-not $Method) { $Method = Resolve-OcExtractMethod }

  if ($Method -eq 'tar') {
    $tar = Get-Command tar -ErrorAction SilentlyContinue
    if ($tar) {
      & $tar.Source -xzf $Tarball -C $Destination | Out-Null
      if ($LASTEXITCODE -eq 0) { return 'tar' }
      Write-OcMessage 'tar failed; falling back to the built-in extractor.' 'warn'
    }
  }
  Expand-OcTarballManaged -Tarball $Tarball -Destination $Destination
  return 'built-in'
}

# --- Default paths -----------------------------------------------------------

function Get-OcInstallDir {
  param([hashtable]$Settings, [string]$Override)
  if ($Override) { return $Override }
  if ($Settings -and $Settings.installDir) { return "$($Settings.installDir)" }
  if ((Get-OcOS) -eq 'windows') { return (Join-Path $env:USERPROFILE '.opencode\bin') }
  return (Join-Path $HOME '.opencode/bin')
}

function Get-OcCacheDir {
  param([hashtable]$Settings, [string]$Override)
  if ($Override) { return $Override }
  if ($Settings -and $Settings.cacheDir) { return "$($Settings.cacheDir)" }
  if ((Get-OcOS) -eq 'windows') {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path $env:USERPROFILE 'AppData\Local' }
    return (Join-Path $base "$script:ToolkitName\cache")
  }
  $base = $env:XDG_CACHE_HOME
  if (-not $base) { $base = Join-Path $HOME '.cache' }
  return (Join-Path $base $script:ToolkitName)
}

# --- PATH management ---------------------------------------------------------

function Test-OcPathContains {
  param([Parameter(Mandatory)][string]$Dir)
  $target = ConvertTo-OcPlainPath $Dir
  $sep = [System.IO.Path]::PathSeparator
  foreach ($p in @($env:Path -split [regex]::Escape($sep))) {
    if ($p -and (ConvertTo-OcPlainPath $p) -ieq $target) { return $true }
  }
  if ((Get-OcOS) -eq 'windows') {
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($user) {
      foreach ($p in @($user -split ';')) {
        if ($p -and (ConvertTo-OcPlainPath $p) -ieq $target) { return $true }
      }
    }
  }
  return $false
}

function Add-OcUserPath {
  # Adds Dir to the user PATH. Returns $true if it changed something.
  param([Parameter(Mandatory)][string]$Dir)
  $target = ConvertTo-OcPlainPath $Dir

  if ((Get-OcOS) -eq 'windows') {
    $cur = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $cur) { $cur = '' }
    $parts = @($cur -split ';' | Where-Object { $_ -ne '' })
    $added = $false
    $present = $false
    foreach ($p in $parts) { if ((ConvertTo-OcPlainPath $p) -ieq $target) { $present = $true } }
    if (-not $present) {
      $parts += $Dir
      [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
      $added = $true
    }
    if (($env:Path -split ';') -notcontains $Dir) { $env:Path = "$env:Path;$Dir" }
    return $added
  }

  # macOS / Linux: append to the shell profile, guarded against duplicates.
  $shell = "$env:SHELL"
  $rc = Join-Path $HOME '.profile'
  if ($shell -match 'zsh') { $rc = Join-Path $HOME '.zshrc' }
  elseif ($shell -match 'bash') { $rc = Join-Path $HOME '.bashrc' }
  if (Test-Path $rc) {
    $content = Get-Content -Raw -Path $rc
    if ($content -and $content.Contains($Dir)) { return $false }
  }
  $line1 = '# opencode'
  $line2 = 'export PATH="' + $Dir + ':$PATH"'
  Add-Content -Path $rc -Value ("`n" + $line1 + "`n" + $line2)
  return $true
}

function Resolve-OcPathConsent {
  # Decides whether to add Dir to PATH and, if so, does it.
  # Returns $true only when the PATH was actually changed.
  param(
    [Parameter(Mandatory)][string]$Dir,
    [bool]$NonInteractive = $false,
    [bool]$AssumeYes = $false,
    [bool]$Decline = $false
  )
  if ($Decline) { return $false }

  $consent = $false
  if ($AssumeYes) {
    $consent = $true
  } elseif ($NonInteractive) {
    # Safe default: never modify the PATH without explicit consent.
    $consent = $false
  } else {
    $consent = Read-OcYesNo -Question "Add OpenCode to your user PATH ($Dir)?" -Default $true
  }
  if (-not $consent) { return $false }
  return [bool](Add-OcUserPath -Dir $Dir)
}

# --- Installed state ---------------------------------------------------------

function Get-OcVersionFromExe {
  param([Parameter(Mandatory)][string]$Exe)
  if (-not (Test-Path $Exe)) { return $null }
  try {
    $out = & $Exe --version 2>$null
    $text = (($out | Out-String).Trim())
    if (-not $text) { return $null }
    $token = ($text -split '\s+')[-1]
    if ($token -match '^v?\d') { return ($token -replace '^[vV]', '') }
    if ($text -match '(\d+\.\d+\.\d+[^\s]*)') { return $Matches[1] }
    return $text
  } catch { return $null }
}

function Get-OcInstalledVersion {
  param(
    [Parameter(Mandatory)][string]$InstallDir,
    [string]$OS = (Get-OcOS)
  )
  return (Get-OcVersionFromExe -Exe (Join-Path $InstallDir (Get-OcBinaryName -OS $OS)))
}

function Get-OcSystemInfo {
  param([hashtable]$Settings, [string]$InstallDir, [string]$CacheDir)
  if (-not $Settings) { $Settings = ConvertTo-OcHashtable $script:DefaultSettings }
  $platform = Get-OcPlatform
  $dir = Get-OcInstallDir -Settings $Settings -Override $InstallDir
  $cache = Get-OcCacheDir -Settings $Settings -Override $CacheDir

  $tools = [ordered]@{}
  foreach ($name in @('tar', 'curl', 'git', 'node', 'npm', 'bun', 'pnpm', 'yarn')) {
    $tools[$name] = Get-OcCommandPath $name
  }

  $managedExe = Join-Path $dir (Get-OcBinaryName -OS $platform.OS)
  $managedVersion = $null
  if (Test-Path $managedExe) { $managedVersion = Get-OcVersionFromExe -Exe $managedExe }

  $pathExe = $null
  $cmd = Get-Command 'opencode' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { $pathExe = $cmd.Source }
  $pathVersion = $null
  if ($pathExe) { $pathVersion = Get-OcVersionFromExe -Exe $pathExe }

  $externalInstall = $false
  if ($pathExe) {
    $sameDir = $false
    try { $sameDir = ((ConvertTo-OcPlainPath (Split-Path -Parent $pathExe)) -ieq (ConvertTo-OcPlainPath $dir)) } catch { }
    if (-not $sameDir) { $externalInstall = $true }
  }

  return [pscustomobject]@{
    OS                    = $platform.OS
    Arch                  = $platform.Arch
    Target                = $platform.Target
    Baseline              = $platform.Baseline
    Musl                  = $platform.Musl
    PowerShell            = $PSVersionTable.PSVersion.ToString()
    Interactive           = (Test-OcInteractive)
    Tools                 = $tools
    ExtractMethod         = (Resolve-OcExtractMethod)
    InstallDir            = $dir
    CacheDir              = $cache
    ManagedBinary         = $managedExe
    ManagedVersion        = $managedVersion
    PathBinary            = $pathExe
    PathVersion           = $pathVersion
    ExternalInstall       = $externalInstall
    PathContainsInstallDir = (Test-OcPathContains -Dir $dir)
  }
}

function Format-OcSystemInfo {
  param([Parameter(Mandatory)]$Info)
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('System check')
  $lines.Add(("  Platform            : {0} / {1}  -> target {2}" -f $Info.OS, $Info.Arch, $Info.Target))
  $lines.Add(("  PowerShell          : {0}" -f $Info.PowerShell))
  $lines.Add(("  Extraction method   : {0}" -f $Info.ExtractMethod))
  foreach ($k in $Info.Tools.Keys) {
    $val = $Info.Tools[$k]
    if ($val) { $lines.Add(("  {0,-19} : {1}" -f $k, $val)) }
    else { $lines.Add(("  {0,-19} : (not found)" -f $k)) }
  }
  if ($Info.ManagedVersion) { $lines.Add(("  OpenCode (managed)  : {0} (v{1})" -f $Info.ManagedBinary, $Info.ManagedVersion)) }
  elseif (Test-Path $Info.ManagedBinary) { $lines.Add(("  OpenCode (managed)  : present at {0}" -f $Info.ManagedBinary)) }
  else { $lines.Add('  OpenCode (managed)  : not installed') }
  if ($Info.PathBinary) { $lines.Add(("  OpenCode (on PATH)  : {0} (v{1})" -f $Info.PathBinary, $Info.PathVersion)) }
  else { $lines.Add('  OpenCode (on PATH)  : not found') }
  $lines.Add(("  Install dir on PATH : {0}" -f $Info.PathContainsInstallDir))
  $lines.Add(("  Install dir         : {0}" -f $Info.InstallDir))
  return $lines.ToArray()
}

# --- Install / uninstall -----------------------------------------------------

function New-OcShim {
  param([Parameter(Mandatory)][string]$InstallDir, [string]$OS = (Get-OcOS))
  if ($OS -eq 'windows') {
    $cmd = Join-Path $InstallDir 'opencode2.cmd'
    $content = "@echo off`r`n`"%~dp0opencode.exe`" %*`r`nexit /b %errorlevel%`r`n"
    Set-Content -Path $cmd -Value $content -Encoding ASCII -NoNewline
  } else {
    $sh = Join-Path $InstallDir 'opencode2'
    $content = "#!/bin/sh`nexec `"`$(dirname `"`$0`")/opencode`" `"`$@`"`n"
    Set-Content -Path $sh -Value $content -Encoding ASCII -NoNewline
    try { & chmod 755 $sh } catch { }
  }
}

function Install-OcBinary {
  param(
    [Parameter(Mandatory)]$Release,
    [Parameter(Mandatory)][string]$InstallDir,
    [Parameter(Mandatory)][string]$CacheDir,
    [string]$OS = (Get-OcOS),
    [string]$ExtractMethod,
    [switch]$Force,
    [switch]$Offline,
    [scriptblock]$Log
  )
  if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null }
  if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null }

  $fileName = Split-Path -Leaf $Release.Tarball
  $cacheFile = Join-Path $CacheDir $fileName

  $needDownload = $true
  if ((Test-Path $cacheFile) -and -not $Force) {
    if (-not $Release.Integrity) { $needDownload = $false }
    elseif (Test-OcIntegrity -Path $cacheFile -Integrity $Release.Integrity) { $needDownload = $false }
  }

  if ($needDownload) {
    if ($Offline) { throw "Offline mode: package is not in cache ($cacheFile)." }
    Invoke-OcLog $Log "Downloading $($Release.Tarball)"
    Get-OcDownload -Url $Release.Tarball -OutFile $cacheFile -Integrity $Release.Integrity | Out-Null
  } else {
    Invoke-OcLog $Log "Using verified cached package: $cacheFile"
  }

  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('oc_extract_' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    $usedMethod = Expand-OcTarball -Tarball $cacheFile -Destination $tmp -Method $ExtractMethod
    Invoke-OcLog $Log "Extracted with: $usedMethod"

    $binName = Get-OcBinaryName -OS $OS
    $srcBin = Join-Path $tmp ('package/bin/' + $binName)
    if (-not (Test-Path $srcBin)) {
      $found = Get-ChildItem -Path $tmp -Recurse -Filter $binName -File -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($found) { $srcBin = $found.FullName } else { throw "Could not find '$binName' inside the downloaded package." }
    }

    $dest = Join-Path $InstallDir $binName
    Copy-Item -Path $srcBin -Destination $dest -Force
    if ($OS -ne 'windows') { try { & chmod 755 $dest } catch { } }
    New-OcShim -InstallDir $InstallDir -OS $OS
    Invoke-OcLog $Log "Installed binary at $dest"
    return [pscustomobject]@{ Path = $dest; Method = $usedMethod }
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
}

function Remove-OcInstall {
  param(
    [Parameter(Mandatory)][string]$InstallDir,
    [switch]$RemovePath,
    [switch]$Purge
  )
  $removed = @()
  foreach ($f in @('opencode.exe', 'opencode2.cmd', 'opencode', 'opencode2')) {
    $p = Join-Path $InstallDir $f
    if (Test-Path $p) { Remove-Item $p -Force; $removed += $p }
  }
  if ($RemovePath -and (Get-OcOS) -eq 'windows') {
    $cur = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($cur) {
      $target = ConvertTo-OcPlainPath $InstallDir
      $parts = @($cur -split ';' | Where-Object { $_ -ne '' -and ((ConvertTo-OcPlainPath $_) -ine $target) })
      [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
    }
  }
  if ($Purge -and (Test-Path $InstallDir)) {
    $left = @(Get-ChildItem -Path $InstallDir -Force -ErrorAction SilentlyContinue)
    if ($left.Count -eq 0) { Remove-Item $InstallDir -Force -ErrorAction SilentlyContinue }
  }
  return $removed
}

# --- Toolkit self-update -----------------------------------------------------

function Test-OcToolkitUpdate {
  param([hashtable]$Settings)
  if (-not $Settings) { $Settings = ConvertTo-OcHashtable $script:DefaultSettings }
  if (-not $Settings.selfUpdate.enabled -or -not $Settings.selfUpdate.manifestUrl) {
    return [pscustomobject]@{
      Supported = $false; Current = $script:ToolkitVersion; Latest = $null
      UpdateAvailable = $false; Reason = 'toolkit self-update is not configured'
    }
  }
  try {
    $content = Invoke-OcRequest -Uri $Settings.selfUpdate.manifestUrl
    $m = $content | ConvertFrom-Json
    $latest = "$($m.version)"
    $avail = ((Compare-OcVersion -Left $latest -Right $script:ToolkitVersion) -gt 0)
    return [pscustomobject]@{
      Supported = $true; Current = $script:ToolkitVersion; Latest = $latest
      UpdateAvailable = $avail; Reason = ''
    }
  } catch {
    return [pscustomobject]@{
      Supported = $true; Current = $script:ToolkitVersion; Latest = $null
      UpdateAvailable = $false; Reason = $_.Exception.Message
    }
  }
}

Export-ModuleMember -Function `
  Write-OcMessage, Get-OcSettings, Get-OcToolkitVersion, Get-OcToolkitName, `
  Get-OcCommandPath, Test-OcCommand, Test-OcInteractive, Read-OcYesNo, `
  Get-OcOS, Get-OcArch, Get-OcPlatform, Get-OcBinaryName, `
  Test-OcAvx2, Test-OcMusl, Test-OcIntegrity, Compare-OcVersion, `
  ConvertFrom-OcUpdateApiResponse, ConvertFrom-OcNpmLatestResponse, `
  ConvertFrom-OcGithubReleaseResponse, ConvertFrom-OcRegistryDocument, `
  Get-OcLatestInfo, Resolve-OcPackage, Resolve-OcPlan, `
  Invoke-OcRequest, Get-OcDownload, Resolve-OcExtractMethod, `
  Expand-OcTarballManaged, Expand-OcTarball, `
  Get-OcInstallDir, Get-OcCacheDir, Get-OcVersionFromExe, Get-OcInstalledVersion, `
  Get-OcSystemInfo, Format-OcSystemInfo, Test-OcPathContains, Add-OcUserPath, `
  Resolve-OcPathConsent, Install-OcBinary, Remove-OcInstall, Test-OcToolkitUpdate
