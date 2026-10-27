$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    python tool/bootstrap_platforms.py
    if ($LASTEXITCODE -ne 0) { throw 'Native runner validation failed' }
    flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed' }
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Analysis failed' }
    flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
} finally { Pop-Location }
