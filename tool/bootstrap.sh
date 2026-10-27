#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 tool/bootstrap_platforms.py
flutter pub get --enforce-lockfile
flutter analyze
flutter test
