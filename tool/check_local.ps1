param(
    [string]$AndroidDevice = '',
    [string]$CredentialFile = ''
)
$ErrorActionPreference = 'Stop'
function Invoke-CheckedFlutter {
    param([string[]]$FlutterArguments)
    & flutter @FlutterArguments
    if ($LASTEXITCODE -ne 0) { throw "Flutter check failed: $($FlutterArguments[0])" }
}
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    Invoke-CheckedFlutter -FlutterArguments @('pub', 'get', '--enforce-lockfile')
    & dart format --output=none --set-exit-if-changed lib test integration_test
    if ($LASTEXITCODE -ne 0) { throw 'Dart formatting check failed' }
    Invoke-CheckedFlutter -FlutterArguments @('analyze', '--no-pub')
    # Build the native library before the unit suite, so libmpv tests run.
    Invoke-CheckedFlutter -FlutterArguments @('build', 'windows', '--debug', '--no-pub')
    Invoke-CheckedFlutter -FlutterArguments @('test', '--no-pub')
    Invoke-CheckedFlutter -FlutterArguments @('test', 'integration_test/desktop_test.dart', '-d', 'windows', '--no-pub')
    Invoke-CheckedFlutter -FlutterArguments @('test', 'integration_test/webdav_test.dart', '-d', 'windows', '--no-pub')
    Invoke-CheckedFlutter -FlutterArguments @('test', 'integration_test/media_assets_test.dart', '-d', 'windows', '--no-pub')
    Invoke-CheckedFlutter -FlutterArguments @('test', 'integration_test/webdav_tags_test.dart', '-d', 'windows', '--no-pub')
    Invoke-CheckedFlutter -FlutterArguments @('test', 'integration_test/large_library_test.dart', '-d', 'windows', '--no-pub')
    if ($AndroidDevice) {
        Invoke-CheckedFlutter -FlutterArguments @('test', 'integration_test/desktop_test.dart', '-d', $AndroidDevice, '--no-pub')
        Invoke-CheckedFlutter -FlutterArguments @('test', 'integration_test/webdav_test.dart', '-d', $AndroidDevice, '--no-pub')
        Invoke-CheckedFlutter -FlutterArguments @('test', 'integration_test/media_assets_test.dart', '-d', $AndroidDevice, '--no-pub')
        Invoke-CheckedFlutter -FlutterArguments @('test', 'integration_test/webdav_tags_test.dart', '-d', $AndroidDevice, '--no-pub')
        Invoke-CheckedFlutter -FlutterArguments @('test', 'integration_test/sync_foreground_test.dart', '-d', $AndroidDevice, '--no-pub')
        Invoke-CheckedFlutter -FlutterArguments @('test', 'integration_test/large_library_test.dart', '-d', $AndroidDevice, '--no-pub')
    }
    # Distribute optimized main-entrypoint builds after testing.
    & (Join-Path $PSScriptRoot 'build_review.ps1') -CredentialFile $CredentialFile
} finally {
    Pop-Location
}
