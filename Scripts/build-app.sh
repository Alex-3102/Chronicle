#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Chronicle

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/Chronicle"
APP="$ROOT/build/Chronicle.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH" "$APP/Contents/MacOS/Chronicle"
chmod +x "$APP/Contents/MacOS/Chronicle"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
fi

printf 'APPL????' > "$APP/Contents/PkgInfo"

# 优先用固定的本地证书签名：ad-hoc 签名每次 cdhash 都变，系统会当成新应用，
# 导致辅助功能 / 屏幕录制 / 自动化权限每次更新后都要重新授权。
IDENTITY="Chronicle Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --deep --sign "$IDENTITY" "$APP" >/dev/null 2>&1 || true
    echo "Signed with: $IDENTITY"
else
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
    echo "Signed with: ad-hoc（运行 Scripts/make-signing-cert.sh 可固定签名身份）"
fi

echo "Built: $APP"
