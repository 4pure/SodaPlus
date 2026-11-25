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

STEPS=4
STEP=1
step() {
  echo
  echo "======== [$STEP/$STEPS] $1 ========"
  echo
  STEP=$((STEP + 1))
}

print_build_result() {
  local out_dir="$1"
  local artifact="$2"
  echo
  echo "产物目录：${out_dir}"
  echo "可执行文件：${artifact}"
  echo
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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
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

ICON_DIR="$ROOT/Sources/SodaPlus/Resources"
cp "$ICON_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ICON_DIR/TrayIcon-16.png" "$APP/Contents/Resources/TrayIcon-16.png"
cp "$ICON_DIR/TrayIcon-32.png" "$APP/Contents/Resources/TrayIcon-32.png"

cp "$BIN" "$APP/Contents/MacOS/SodaPlus"
cp "$BRIDGE" "$APP/Contents/MacOS/sodaplus-bridge"
BIN_DIR="$(dirname "$BIN")"
RESOURCE_BUNDLE="$BIN_DIR/SodaPlus_SodaPlus.bundle"
# SPM Bundle.module 在 .app 内只查 Bundle.main.resourceURL（Contents/Resources），
# 不要放到 Contents/MacOS，否则启动即 fatalError: unable to find bundle named SodaPlus_SodaPlus。
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  rm -rf "$APP/Contents/Resources/SodaPlus_SodaPlus.bundle"
  cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/SodaPlus_SodaPlus.bundle"
fi
chmod +x "$APP/Contents/MacOS/SodaPlus" "$APP/Contents/MacOS/sodaplus-bridge"

step "codesign SodaPlus.app"
codesign --force --deep --sign - "$APP" >/dev/null

print_build_result "$OUT_DIR" "$APP"
if [[ "$APP_ONLY" -eq 0 ]]; then
  echo "（未打 DMG；需要时可再加 dmg 步骤）"
fi
