<#
CardKeep update helper (Windows).

CardKeep starts this itself, after it has downloaded, checked and unpacked an update.
It is not meant to be run by hand.

  -ProcessId        the running CardKeep to wait for
  -InstallDir       the folder CardKeep.exe runs from
  -StagingDir       the unpacked new version (beside InstallDir, on the same drive)
  -ExeName          CardKeep.exe
  -LogFile          where to write what happened
  -RolledBackMarker a file to create if the new version would not start

Steps: wait for CardKeep to close, then InstallDir becomes InstallDir.old and StagingDir
becomes InstallDir, then the new CardKeep starts. If it stops with an error within
HealthSeconds, the new folder is set aside as InstallDir.failed and the old one comes back.
The new CardKeep deletes InstallDir.old itself once it has been running for a while.
Contacts live in Documents, so none of this touches them.
#>
param(
  [Parameter(Mandatory = $true)][int]$ProcessId,
  [Parameter(Mandatory = $true)][string]$InstallDir,
  [Parameter(Mandatory = $true)][string]$StagingDir,
  [string]$ExeName = 'CardKeep.exe',
  [string]$LogFile = '',
  [string]$RolledBackMarker = '',
  [int]$HealthSeconds = 20
)

$ErrorActionPreference = 'Stop'
$InstallDir = $InstallDir.TrimEnd('\', '/')
$StagingDir = $StagingDir.TrimEnd('\', '/')
$OldDir = "$InstallDir.old"
$FailedDir = "$InstallDir.failed"

function Write-Log([string]$Message) {
  if (-not $LogFile) { return }
  try {
    $line = '{0:s}  {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $LogFile -Value $line
  } catch { }
}

# Folders are briefly held open by the shell or a virus scanner: try again for a while.
function Move-Folder([string]$From, [string]$To) {
  $last = $null
  for ($i = 0; $i -lt 40; $i++) {
    try {
      Move-Item -LiteralPath $From -Destination $To -ErrorAction Stop
      return
    } catch {
      $last = $_
      Start-Sleep -Milliseconds 500
    }
  }
  throw $last
}

function Start-CardKeep([string]$Dir) {
  Start-Process -FilePath (Join-Path $Dir $ExeName) -WorkingDirectory $Dir -PassThru
}

try {
  Write-Log "Update started. Waiting for CardKeep ($ProcessId) to close."
  try { Wait-Process -Id $ProcessId -Timeout 60 -ErrorAction Stop } catch { }
  if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) { throw 'CardKeep did not close.' }
  if (-not (Test-Path -LiteralPath (Join-Path $StagingDir $ExeName))) { throw 'The unpacked update is missing.' }

  if (Test-Path -LiteralPath $OldDir) { Remove-Item -LiteralPath $OldDir -Recurse -Force }
  Move-Folder $InstallDir $OldDir
  try {
    Move-Folder $StagingDir $InstallDir
  } catch {
    Write-Log "Could not put the new version in place: $_"
    Move-Folder $OldDir $InstallDir
    throw
  }
  Write-Log 'New version in place. The old one is kept as .old.'
} catch {
  # Nothing was changed (or it was put back): start the version that was running.
  Write-Log "Update not applied: $_"
  if (Test-Path -LiteralPath (Join-Path $InstallDir $ExeName)) { Start-CardKeep $InstallDir | Out-Null }
  exit 1
}

try {
  $proc = Start-CardKeep $InstallDir
  Write-Log 'Started the new version.'
  $deadline = (Get-Date).AddSeconds($HealthSeconds)
  while ((Get-Date) -lt $deadline -and -not $proc.HasExited) { Start-Sleep -Milliseconds 500 }
  # Closing normally is fine; stopping with an error means the new version is broken.
  if ($proc.HasExited -and $proc.ExitCode -ne 0) { throw "It stopped with exit code $($proc.ExitCode)." }
  Write-Log 'The new version is running.'
  exit 0
} catch {
  Write-Log "The new version did not start properly ($_). Putting the old version back."
  try {
    if (Test-Path -LiteralPath $FailedDir) { Remove-Item -LiteralPath $FailedDir -Recurse -Force }
    Move-Folder $InstallDir $FailedDir
    Move-Folder $OldDir $InstallDir
    if ($RolledBackMarker) { Set-Content -LiteralPath $RolledBackMarker -Value (Get-Date -Format s) }
    Start-CardKeep $InstallDir | Out-Null
    Write-Log 'The old version is back.'
  } catch {
    Write-Log "Could not put the old version back: $_"
  }
  exit 2
}
