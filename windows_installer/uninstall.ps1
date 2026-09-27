<#
.SYNOPSIS
  Removes a Modlinq installation.

.DESCRIPTION
  Shipped next to modlinq.exe so a portable copy has a way out too: a running
  executable cannot delete its own folder, so the app copies this script to
  the temp folder, starts it detached and exits. The script waits for that
  process to go away and then removes what it was told to.

  Safe to run by hand. Without -WaitForPid it removes the folder it sits in.

  Mods installed into a game are NOT touched here, because this script does
  not know where the games are. Use "Uninstall Modlinq" inside the app for
  that, before uninstalling.

.PARAMETER WaitForPid
  Process to wait for before deleting anything.

.PARAMETER AppDir
  Installation folder. Defaults to the folder holding this script.

.PARAMETER RemoveAppData
  Also delete %APPDATA%\modlinq, including settings and logs.

.PARAMETER KeepLibrary
  With -RemoveAppData, leave the imported mod library in place.

.PARAMETER AppDataOnly
  Leave the install folder alone. Used by the Inno uninstaller, which removes
  those files itself and only wants the app data handled here.
#>
[CmdletBinding()]
param(
    [int]$WaitForPid = 0,
    [string]$AppDir = $PSScriptRoot,
    [switch]$RemoveAppData,
    [switch]$KeepLibrary,
    [switch]$AppDataOnly
)

$ErrorActionPreference = 'Stop'

function Wait-ForExit {
    param([int]$ProcessId)

    if ($ProcessId -le 0) { return }

    # 60 s is far longer than a Flutter window needs to close; past that
    # something is holding the process and deleting its folder would fail
    # anyway.
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 250
    }

    Write-Warning "process $ProcessId is still running, continuing anyway"
}

function Remove-TreeExcept {
    param([string]$Path, [string[]]$Keep = @())

    if (-not (Test-Path -LiteralPath $Path)) { return }

    if ($Keep.Count -eq 0) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        return
    }

    $keepFull = $Keep | ForEach-Object { [System.IO.Path]::GetFullPath($_) }
    Get-ChildItem -LiteralPath $Path -Force | ForEach-Object {
        $full = [System.IO.Path]::GetFullPath($_.FullName)
        if ($keepFull -contains $full) { return }
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Wait-ForExit -ProcessId $WaitForPid

if ($RemoveAppData) {
    $appData = Join-Path $env:APPDATA 'modlinq'
    $keep = @()
    if ($KeepLibrary) { $keep += (Join-Path $appData 'nte_mods') }
    Remove-TreeExcept -Path $appData -Keep $keep
    Write-Host "removed app data: $appData"
}

if ($AppDataOnly) {
    exit 0
}

Remove-TreeExcept -Path $AppDir
Write-Host "removed install folder: $AppDir"

if (Test-Path -LiteralPath $AppDir) {
    Write-Warning "some files in $AppDir could not be removed; delete the folder by hand"
}
