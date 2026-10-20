# CardKeep emulator helper (Windows PowerShell 5.1).
#   . .\tool\emu.ps1            # load the functions
#   Start-Emu; Install-App; Seed-Demo; Launch-App; Shot "01_contacts"
#   Tap 540 1200; Swipe 540 2000 540 800; Txt "priya"; Key BACK
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$Adb = 'C:\Android\sdk\platform-tools\adb.exe'
$Pkg = 'com.axialforge.cardkeep'
$Emu = 'Pixel_10_Pro_XL_test'
$Shots = Join-Path $Root 'out\shots'

function Start-Emu {
  if (-not ((& $Adb devices) -match 'emulator-')) { flutter emulators --launch $Emu | Out-Null }
  & $Adb wait-for-device
  do { Start-Sleep 2 } until ((& $Adb shell getprop sys.boot_completed).Trim() -eq '1')
  & $Adb shell settings put secure stylus_handwriting_enabled 0
}

function Install-App {
  $env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:/tmpj'
  Push-Location $Root
  try { flutter build apk --debug --target-platform android-x64 | Select-Object -Last 1 } finally { Pop-Location }
  & $Adb install -r (Join-Path $Root 'build\app\outputs\flutter-apk\app-debug.apk') | Select-Object -Last 1
}

function Launch-App { & $Adb shell monkey -p $Pkg 1 | Out-Null; Start-Sleep 4 }

function Stop-App { & $Adb shell am force-stop $Pkg }

# Replaces the app database with the fictional demo set (debug builds only: needs run-as).
function Seed-Demo {
  $seed = Join-Path $env:TEMP 'cardkeep-seed.sqlite'
  Push-Location $Root
  try { $env:SEED_OUT = $seed; flutter test test/tool_seed_demo_test.dart | Select-Object -Last 1 } finally { Remove-Item Env:SEED_OUT; Pop-Location }
  Launch-App; Stop-App
  & $Adb push $seed /data/local/tmp/seed.sqlite | Out-Null
  & $Adb shell "run-as $Pkg sh -c 'rm -f app_flutter/card_organizer.sqlite*; cp /data/local/tmp/seed.sqlite app_flutter/card_organizer.sqlite'"
}

function Shot([string]$name) {
  New-Item -ItemType Directory -Force $Shots | Out-Null
  & $Adb shell screencap -p /sdcard/shot.png
  & $Adb pull /sdcard/shot.png (Join-Path $Shots "$name.png") | Out-Null
  Join-Path $Shots "$name.png"
}

function Tap([int]$x, [int]$y) { & $Adb shell input tap $x $y; Start-Sleep -Milliseconds 700 }
function Swipe([int]$x1, [int]$y1, [int]$x2, [int]$y2) { & $Adb shell input swipe $x1 $y1 $x2 $y2 300; Start-Sleep -Milliseconds 700 }
function Txt([string]$t) { & $Adb shell input text ($t -replace ' ', '%s'); Start-Sleep -Milliseconds 500 }
function Key([string]$k) { & $Adb shell input keyevent "KEYCODE_$k"; Start-Sleep -Milliseconds 600 }
function Font-Scale([double]$s) { & $Adb shell settings put system font_scale $s }
