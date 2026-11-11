# Capture a single playback stall without launching the app or clearing logcat.
# Usage: pwsh -File tool/capture_playback_stall.ps1 -Package com.ymltsh.sylphymusic
param(
    [string]$Package = 'com.ymltsh.sylphymusic',
    [int]$IntervalSeconds = 2
)
$ErrorActionPreference = 'Stop'
if ($IntervalSeconds -lt 1 -or $IntervalSeconds -gt 10) { throw 'IntervalSeconds must be 1..10' }
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) { throw 'adb was not found in PATH' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$root = Join-Path '.private' "playback-stall-$stamp"
New-Item -Path $root -ItemType Directory -Force | Out-Null
function Capture([string]$name, [string[]]$arguments) {
    # These raw Android snapshots can contain media/device/private metadata.
    & adb @arguments 2>&1 | Out-File -LiteralPath (Join-Path $root "$name.txt") -Encoding utf8
}
Capture 'device' @('shell', 'getprop', 'ro.build.version.release')
Capture 'services-before' @('shell', 'dumpsys', 'activity', 'services', $Package)
Capture 'audio-before' @('shell', 'dumpsys', 'audio')
Capture 'flinger-before' @('shell', 'dumpsys', 'media.audio_flinger')
Capture 'power-before' @('shell', 'dumpsys', 'power')
Start-Sleep -Seconds $IntervalSeconds
Capture 'services-after' @('shell', 'dumpsys', 'activity', 'services', $Package)
Capture 'audio-after' @('shell', 'dumpsys', 'audio')
Capture 'flinger-after' @('shell', 'dumpsys', 'media.audio_flinger')
Capture 'power-after' @('shell', 'dumpsys', 'power')
Capture 'media-session' @('shell', 'dumpsys', 'media_session')
Capture 'logcat' @('logcat', '-d', '-v', 'threadtime', '-b', 'main', '-b', 'system', '-b', 'events')
Write-Host "Saved private capture in $root. Review and redact before sharing."
