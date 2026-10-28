param(
    [string[]]$CredentialFile = @(),
    [string]$ReleaseVersion = ''
)
$ErrorActionPreference = 'Stop'
$taskHadSigningFlag = Test-Path Env:SYLPHY_INTERNAL_DEBUG_SIGNING
$taskOldSigningFlag = $env:SYLPHY_INTERNAL_DEBUG_SIGNING
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    # Explicit internal signing keeps the optimized APK installable over this
    # machine's debug APK. A configured production signing key takes precedence.
    $env:SYLPHY_INTERNAL_DEBUG_SIGNING = '1'
    $taskBuildDefines = @()
    if ($ReleaseVersion) {
        $taskBuildDefines += "--dart-define=SYLPHY_RELEASE_VERSION=$ReleaseVersion"
    }
    # Do not use --no-pub here: Flutter must regenerate release registrants
    # without dev-only integration_test plugins after native test runs.
    & flutter build apk --release --split-per-abi @taskBuildDefines
    if ($LASTEXITCODE -ne 0) { throw 'Android optimized build failed' }
    & flutter build windows --release @taskBuildDefines
    if ($LASTEXITCODE -ne 0) { throw 'Windows optimized build failed' }
    $taskPackageArgs = @('tool/package_review.py', '--mode', 'optimized')
    foreach ($taskCredential in $CredentialFile) {
        if ($taskCredential) { $taskPackageArgs += @('--credentials-file', $taskCredential) }
    }
    & python @taskPackageArgs
    if ($LASTEXITCODE -ne 0) { throw 'Internal package check failed' }
} finally {
    if ($taskHadSigningFlag) { $env:SYLPHY_INTERNAL_DEBUG_SIGNING = $taskOldSigningFlag }
    else { Remove-Item Env:SYLPHY_INTERNAL_DEBUG_SIGNING -ErrorAction SilentlyContinue }
    Pop-Location
}
