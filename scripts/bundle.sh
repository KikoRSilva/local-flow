#!/usr/bin/env bash
# Builds LocalFlow.app into build/. Set SIGN_IDENTITY to a Developer ID / Apple
# Development identity so macOS keeps permissions across rebuilds (ad-hoc
# signatures change every build, so Accessibility must be re-granted).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/LocalFlow.app"
IDENTITY="${SIGN_IDENTITY:--}"

[ -f "$ROOT/vendor/whisper/lib/libwhisper.a" ] || "$ROOT/scripts/build-whisper.sh"
swift build -c release --package-path "$ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/LocalFlow" "$APP/Contents/MacOS/LocalFlow"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.kikorsilva.localflow</string>
  <key>CFBundleName</key><string>LocalFlow</string>
  <key>CFBundleDisplayName</key><string>LocalFlow</string>
  <key>CFBundleExecutable</key><string>LocalFlow</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>LocalFlow records your voice while you hold the dictation hotkey and transcribes it on this Mac.</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

codesign --force --options runtime --sign "$IDENTITY" \
  --entitlements /dev/stdin "$APP" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.device.audio-input</key><true/>
</dict></plist>
ENT
echo "Built $APP"
