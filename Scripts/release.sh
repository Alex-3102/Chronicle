#!/bin/bash
# 打一个可直接分发的 DMG：自动升版本号、构建 .app、生成带安装指引的磁盘映像。
# 用法: ./Scripts/release.sh [版本号] [构建号]
#   例如: ./Scripts/release.sh 1.2 3
# 不传参数时沿用 Resources/Info.plist 里的版本号。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PLIST="$ROOT/Resources/Info.plist"
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")

VERSION="${1:-$CURRENT_VERSION}"
BUILD="${2:-$((CURRENT_BUILD))}"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"

echo "==> 版本 $VERSION ($BUILD)"

# 图标（缺失时重新生成）
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    echo "==> 生成应用图标"
    swift "$ROOT/Scripts/make-icon.swift" "$ROOT/Resources/AppIcon.icns"
fi

echo "==> 构建应用"
"$ROOT/Scripts/build-app.sh"

APP="$ROOT/build/Chronicle.app"
STAGE="$ROOT/build/dmg-stage"
DIST="$ROOT/dist"
TMP_DMG="$ROOT/build/Chronicle-rw.dmg"
FINAL="$DIST/Chronicle-$VERSION.dmg"
VOLUME="Chronicle $VERSION"
BG_PNG="$ROOT/build/dmg-background.png"

echo "==> 生成安装界面背景"
swift "$ROOT/Scripts/make-dmg-background.swift" "$VERSION" "$BG_PNG" "$ROOT/Resources/AppIcon.icns"

rm -rf "$STAGE"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/Chronicle.app"
ln -s /Applications "$STAGE/应用程序"
cp "$BG_PNG" "$STAGE/.background/background.png"

chflags hidden "$STAGE/.background"

echo "==> 创建磁盘映像"
rm -f "$TMP_DMG"
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -ov -fs HFS+ -format UDRW -quiet "$TMP_DMG"

MOUNT_POINT="/Volumes/$VOLUME"
hdiutil attach "$TMP_DMG" -noautoopen -quiet

# 用 Finder 摆放图标并设置背景；没有自动化权限时自动跳过，DMG 依然可用
osascript <<APPLESCRIPT >/dev/null 2>&1 || echo "   （跳过 Finder 布局设置：未授予自动化权限，DMG 依然可用）"
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 160, 904, 600}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 120
        set text size of viewOptions to 12
        set background picture of viewOptions to file ".background:background.png"
        set position of item "Chronicle.app" of container window to {172, 228}
        set position of item "应用程序" of container window to {492, 228}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true

mkdir -p "$DIST"
rm -f "$FINAL"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL" -quiet
rm -f "$TMP_DMG"
rm -rf "$STAGE"

echo "==> 完成: $FINAL"
ls -lh "$FINAL"
