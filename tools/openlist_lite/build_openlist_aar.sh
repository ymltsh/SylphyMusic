#!/usr/bin/env bash
set -euo pipefail
# Pinned OpenList server AND frontend, arm64-v8a only. Requires git, Go >=1.26,
# gomobile, Android SDK/NDK, Java 17 and network access on the BUILD MACHINE.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION=v4.2.9
COMMIT=0497ee853853eff5fc0ada9f21684a990887de83
WORK="${OPENLIST_BUILD_DIR:-$ROOT/.private/openlist-native}"
if [[ -e "$WORK" ]]; then echo "Remove or change OPENLIST_BUILD_DIR first: $WORK" >&2; exit 1; fi
mkdir -p "$(dirname "$WORK")"
git clone --filter=blob:none https://github.com/OpenListTeam/OpenList.git "$WORK"
cd "$WORK"
git checkout --detach "$COMMIT"
[[ "$(git rev-parse HEAD)" == "$COMMIT" ]] || exit 2
# Web frontend isn't in the server source: embed its release distribution.
WEB_ARCHIVE="$WORK/frontend.tar.gz"
# Lite removes optional frontend assets but does NOT delete OpenList drivers.
# Set OPENLIST_FRONTEND_VARIANT=full if a particular UI action is missing.
VARIANT="${OPENLIST_FRONTEND_VARIANT:-lite}"
case "$VARIANT" in
  lite) WEB_ASSET="openlist-frontend-dist-lite-v4.2.9.tar.gz" ;;
  full) WEB_ASSET="openlist-frontend-dist-v4.2.9.tar.gz" ;;
  *) echo "OPENLIST_FRONTEND_VARIANT must be 'lite' or 'full'" >&2; exit 3 ;;
esac
echo "Using OpenList $VARIANT frontend: $WEB_ASSET"
curl -fL --retry 3 -o "$WEB_ARCHIVE" \
  "https://github.com/OpenListTeam/OpenList-Frontend/releases/download/$VERSION/$WEB_ASSET"
# Frontend archives may contain a top-level dist directory or dist contents.
mkdir -p "$WORK/frontend-extract"
tar -xzf "$WEB_ARCHIVE" -C "$WORK/frontend-extract"
FRONTEND="$WORK/frontend-extract/dist"
if [[ ! -f "$FRONTEND/index.html" ]]; then FRONTEND="$WORK/frontend-extract"; fi
[[ -f "$FRONTEND/index.html" ]] || { echo 'Frontend missing index.html' >&2; exit 3; }
rm -rf "$WORK/public/dist"
mkdir -p "$WORK/public/dist"
cp -a "$FRONTEND/." "$WORK/public/dist/"
mkdir -p "$WORK/openlistlib"
cp "$ROOT/tools/openlist_lite/bridge.go" "$WORK/openlistlib/bridge.go"
export CGO_ENABLED=1
# Pin gomobile and build tools in CI as appropriate for the Go toolchain.
command -v gomobile >/dev/null || { echo 'Install golang.org/x/mobile/cmd/gomobile' >&2; exit 4; }
go get -tool golang.org/x/mobile/cmd/gobind@v0.0.0-20261011034528-197770444867
gomobile init
gomobile bind -target=android/arm64 -androidapi 24 -trimpath \
  -ldflags="-s -w -X github.com/OpenListTeam/OpenList/v4/internal/conf.Version=$VERSION" \
  -o "$WORK/openlistlib.aar" ./openlistlib
mkdir -p "$ROOT/android/app/libs"
cp "$WORK/openlistlib.aar" "$ROOT/android/app/libs/openlistlib.aar"
echo "Built $ROOT/android/app/libs/openlistlib.aar"
