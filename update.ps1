#Requires -Version 5.1
<#
.SYNOPSIS
    Update OpenCode to the latest available version.
.DESCRIPTION
    Thin wrapper over install.ps1 -Update. It does not reinstall when already
    up to date. Every option of install.ps1 is accepted.
.EXAMPLE
    .\update.ps1
.EXAMPLE
    .\update.ps1 -Yes
#>
param()

& (Join-Path $PSScriptRoot 'install.ps1') -Update @args
exit $LASTEXITCODE
