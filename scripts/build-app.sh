#!/usr/bin/env bash
# Build, bundle, and ad-hoc sign RuCode Chat without Xcode.
#
# This machine ships Command Line Tools only. Xcode's SwiftData macro plugin,
# actool, and PreviewsMacros are unavailable, so the app is built through
# SwiftPM from staged sources (SwiftData replaced by a JSON store, asset colors
# and previews compiled out). See Package.swift and scripts/stage-sources.py.
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RuCode Chat"
BUNDLE="$ROOT/dist/$APP_NAME.app"

# Git/SPM must not inherit a dead local proxy from the shell environment.
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*" >&2; }
die() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] ERROR $*" >&2; exit 1; }

cd "$ROOT"

log "Staging sources (previews stripped, iOS-only files skipped)"
python3 scripts/stage-sources.py

log "Patching dependency previews (Xcode-only macro)"
python3 scripts/patch-deps.py

log "Building release binary"
swift build -c release

BINARY="$(swift build -c release --show-bin-path)/RuCodeChat"
[ -x "$BINARY" ] || die "missing binary at $BINARY"

log "Assembling $APP_NAME.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/RuCodeChat"
cp scripts/AppInfo.plist "$BUNDLE/Contents/Info.plist"
cp assets/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
cp assets/logo.png "$BUNDLE/Contents/Resources/logo-nobg.png"

xattr -cr "$BUNDLE"
log "Signing (ad-hoc)"
codesign --force --deep --sign - "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"

log "Built $BUNDLE"
