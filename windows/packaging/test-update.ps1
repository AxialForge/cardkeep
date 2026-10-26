<#
Tests update.ps1 with stand-in programs, in a temporary folder (used by the release workflow
and fine to run by hand). It checks the two outcomes that matter:
  good    the new version starts and stays: it is in place, the old one is kept as .old
  broken  the new version stops with an error: the old one is put back and the marker is written
Exits 0 when both behave, 1 otherwise.
#>
param([string]$Script = (Join-Path $PSScriptRoot 'update.ps1'))

$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('ck_helper_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $root | Out-Null
$sys = Join-Path $env:SystemRoot 'System32'
$failures = @()

function Invoke-Scenario([string]$Name, [string]$NewProgram, [string]$ExpectVersion, [bool]$ExpectMarker, [int]$ExpectExit) {
  $dir = Join-Path $root $Name
  $inst = Join-Path $dir 'CardKeep'
  $stage = "$inst.new"
  New-Item -ItemType Directory $inst, $stage | Out-Null
  Copy-Item (Join-Path $sys 'hostname.exe') (Join-Path $inst 'CardKeep.exe')
  Set-Content (Join-Path $inst 'version.txt') 'old'
  Copy-Item $NewProgram (Join-Path $stage 'CardKeep.exe')
  Set-Content (Join-Path $stage 'version.txt') 'new'
  $log = Join-Path $dir 'update.log'
  $marker = Join-Path $dir 'rolled-back.txt'
  # 999999: a process id that does not exist, as if CardKeep had already closed.
  & powershell -NoProfile -ExecutionPolicy Bypass -File $Script -ProcessId 999999 `
    -InstallDir $inst -StagingDir $stage -LogFile $log -RolledBackMarker $marker -HealthSeconds 4
  $exit = $LASTEXITCODE
  $version = (Get-Content (Join-Path $inst 'version.txt')).Trim()
  $hasMarker = Test-Path $marker
  $hasOld = Test-Path "$inst.old"
  $hasFailed = Test-Path "$inst.failed"
  Write-Host ("{0}: exit {1}, version {2}, .old {3}, .failed {4}, marker {5}" -f $Name, $exit, $version, $hasOld, $hasFailed, $hasMarker)
  if ($exit -ne $ExpectExit) { $script:failures += "$Name exit code $exit, expected $ExpectExit" }
  if ($version -ne $ExpectVersion) { $script:failures += "$Name left version '$version', expected '$ExpectVersion'" }
  if ($hasMarker -ne $ExpectMarker) { $script:failures += "$Name marker $hasMarker, expected $ExpectMarker" }
  if ($ExpectVersion -eq 'new' -and -not $hasOld) { $script:failures += "$Name did not keep the old folder" }
  if ($ExpectVersion -eq 'old' -and -not $hasFailed) { $script:failures += "$Name did not set the failed folder aside" }
  if (Test-Path $log) { Get-Content $log | ForEach-Object { Write-Host "    $_" } }
}

# hostname.exe exits 0 at once (a program that runs and closes normally is fine);
# where.exe with no arguments exits 2 (a new version that crashes).
Invoke-Scenario 'good' (Join-Path $sys 'hostname.exe') 'new' $false 0
Invoke-Scenario 'broken' (Join-Path $sys 'where.exe') 'old' $true 2

Start-Sleep -Seconds 1
try { Remove-Item -Recurse -Force $root -ErrorAction Stop } catch { Write-Host "(left $root behind: $_)" }

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Host "FAIL: $_" }
  exit 1
}
Write-Host 'update.ps1 behaves.'
exit 0
