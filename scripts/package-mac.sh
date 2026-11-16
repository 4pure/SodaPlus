#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${1:-arm}"
APP_ONLY=0
for arg in "${@:2}"; do
  case "$arg" in
    --app-only) APP_ONLY=1 ;;
  esac
done

VERSION_FILE="$ROOT/Config/Version.xcconfig"
MARKETING_VERSION="$(awk -F' = ' '/^MARKETING_VERSION/{print $2}' "$VERSION_FILE" | tr -d '[:space:]')"
BUILD_NUMBER="$(awk -F' = ' '/^CURRENT_PROJECT_VERSION/{print $2}' "$VERSION_FILE" | tr -d '[:space:]')"

case "$ARCH" in
  arm|arm64) SWIFT_ARCH=arm64 ;;
  intel|x86_64) SWIFT_ARCH=x86_64 ;;
  universal|uni) SWIFT_ARCH=universal ;;
  *)
    echo "usage: $0 [arm|intel|universal] [--app-only]" >&2
    exit 2
    ;;
esac

STEPS=3
STEP=1
step() {
  echo
  echo "======== [$STEP/$STEPS] $1 ========"
  echo
  STEP=$((STEP + 1))
}

step "build rust bridge"
bash "$ROOT/scripts/build-bridge.sh"

step "swift build -c release"
cd "$ROOT"
if [[ "$SWIFT_ARCH" == "universal" ]]; then
  swift build -c release --arch arm64 --arch x86_64
else
  swift build -c release --arch "$SWIFT_ARCH"
fi

BIN="$(swift build -c release --show-bin-path)/SodaPlus"
BRIDGE="$ROOT/bridge/target/release/sodaplus-bridge"
OUT_DIR="$ROOT/installers"
APP="$OUT_DIR/SodaPlus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

step "assemble SodaPlus.app"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleExecutable</key>
  <string>SodaPlus</string>
  <key>CFBundleIdentifier</key>
  <string>org.sodaplus.SodaPlus</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>SodaPlus</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${MARKETING_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

cp "$BIN" "$APP/Contents/MacOS/SodaPlus"
cp "$BRIDGE" "$APP/Contents/MacOS/sodaplus-bridge"
chmod +x "$APP/Contents/MacOS/SodaPlus" "$APP/Contents/MacOS/sodaplus-bridge"
codesign --force --deep --sign - "$APP" >/dev/null

echo
echo "产物：$APP"
if [[ "$APP_ONLY" -eq 0 ]]; then
  echo "（未打 DMG；需要时可再加 dmg 步骤）"
fi
