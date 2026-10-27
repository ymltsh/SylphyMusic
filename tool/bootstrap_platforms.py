#!/usr/bin/env python3
"""Validate committed native runners. Never regenerate customized platform code."""
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
required = ['android/app/src/main/AndroidManifest.xml', 'android/app/src/main/kotlin/music/sylphy/sylphy_music/MainActivity.kt',
            'windows/runner/desktop_integration.cpp', 'linux/runner/my_application.cc']
missing = [path for path in required if not (root / path).is_file()]
if missing:
    raise SystemExit('Restore missing tracked native files from Git: ' + ', '.join(missing))
flutter = shutil.which('flutter')
if not flutter:
    raise SystemExit('Install Flutter 3.47.8 stable and add its bin directory to PATH')
subprocess.run([flutter, '--version'], cwd=root, check=True)
print('Committed Android/Windows/Linux runners verified; native customizations preserved.')
