#!/usr/bin/env bash
#
# E2E visual verification — build the app and render FAITHFUL PNGs of every surface
# (real .regularMaterial/blur via off-screen NSWindow + cacheDisplay), no GUI, no
# screen-recording permission. This is the loop that lets an agent see its own UI
# change instead of asking a human to eyeball it every time.
#
# Usage:   tools/snapshot.sh [output-dir]      # default: <repo>/.snapshots
# Then:    open the PNGs (or Read them) — dashboard/history/retro/settings, dark+light,
#          every theme. The Value card lives in the dashboard / theme renders.
#
# Mechanism: TokenMukbangApp's TMK_SNAPSHOT branch (App/TokenMukbang/TokenMukbangApp.swift)
# calls WindowSnapshot.renderAll(dir:) with PreviewData (App/TokenMukbang/PreviewRender.swift),
# then exits. Edit PreviewData to change what the fixtures show.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$REPO/.snapshots}"
DERIVED="$REPO/.build/snapshot-derived"

cd "$REPO/App" && xcodegen generate >/dev/null && cd "$REPO"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project App/TokenMukbang.xcodeproj -scheme TokenMukbang \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="$DERIVED/Build/Products/Debug/TokenMukbang.app/Contents/MacOS/TokenMukbang"
rm -rf "$OUT" && mkdir -p "$OUT"
TMK_SNAPSHOT="$OUT" "$APP"

echo "Rendered $(ls "$OUT" | wc -l | tr -d ' ') PNGs to: $OUT"
ls "$OUT"
