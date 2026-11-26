#!/usr/bin/env bash
# macOS .app + DMG. Usage: bash scripts/package.sh [arm|intel|universal] [--app-only]
# 默认 universal；默认只打 DMG 到 installers/；--app-only：只发布 .app，不打 DMG
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_ONLY=0
ARCH="universal"
for arg in "$@"; do
  case "$arg" in
    --app-only) APP_ONLY=1 ;;
    arm | arm64 | intel | x86_64 | universal | uni) ARCH="$arg" ;;
    *)
      echo "usage: $0 [arm|intel|universal] [--app-only]" >&2
      exit 2
      ;;
  esac
done

VERSION_FILE="$ROOT/Config/Version.xcconfig"
MARKETING_VERSION="$(awk -F' = ' '/^MARKETING_VERSION/{print $2}' "$VERSION_FILE" | tr -d '[:space:]')"
BUILD_NUMBER="$(awk -F' = ' '/^CURRENT_PROJECT_VERSION/{print $2}' "$VERSION_FILE" | tr -d '[:space:]')"
PRODUCT="SodaPlus"

case "$ARCH" in
  arm | arm64)
    SWIFT_ARCH=arm64
    DMG_ARCH=aarch64
    ;;
  intel | x86_64)
    SWIFT_ARCH=x86_64
    DMG_ARCH=x64
    ;;
  universal | uni)
    SWIFT_ARCH=universal
    DMG_ARCH=universal
    ;;
esac

INSTALLERS_DIR="$ROOT/installers"
STAGE_DIR="$ROOT/build/macos"
APP="$STAGE_DIR/${PRODUCT}.app"

STEPS=4
if [[ "$APP_ONLY" -eq 0 ]]; then
  STEPS=5
fi
STEP=0

next_section() {
  STEP=$((STEP + 1))
  echo
  echo "======== [$STEP/$STEPS] $1 ========"
  echo
}

print_build_result() {
  local out_dir="$1"
  local artifact="$2"
  echo
  echo "产物目录：${out_dir}"
  echo "可执行文件：${artifact}"
  echo
}

next_section "build rust bridge"
bash "$ROOT/scripts/build-bridge.sh"

next_section "swift build -c release"
if [[ "$SWIFT_ARCH" == "universal" ]]; then
  swift build -c release --arch arm64 --arch x86_64
else
  swift build -c release --arch "$SWIFT_ARCH"
fi

BIN="$(swift build -c release --show-bin-path)/SodaPlus"
BRIDGE="$ROOT/bridge/target/release/sodaplus-bridge"

next_section "assemble ${PRODUCT}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

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

next_section "codesign ${PRODUCT}.app"
codesign --force --deep --sign - "$APP" >/dev/null

mkdir -p "$INSTALLERS_DIR"

if [[ "$APP_ONLY" -eq 1 ]]; then
  rm -rf "$INSTALLERS_DIR/${PRODUCT}.app"
  ditto "$APP" "$INSTALLERS_DIR/${PRODUCT}.app"
  print_build_result "$INSTALLERS_DIR" "$INSTALLERS_DIR/${PRODUCT}.app"
  exit 0
fi

next_section "hdiutil create DMG"
PUBLISHED="$INSTALLERS_DIR/${PRODUCT}_${MARKETING_VERSION}_${DMG_ARCH}.dmg"
rm -f "$PUBLISHED"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/${PRODUCT}.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
  -volname "$PRODUCT" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$PUBLISHED"
if [[ ! -f "$PUBLISHED" ]]; then
  echo "DMG not found: $PUBLISHED" >&2
  exit 1
fi
print_build_result "$INSTALLERS_DIR" "$PUBLISHED"
