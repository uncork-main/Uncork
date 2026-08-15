#!/bin/bash
# 构建并组装 Uncork.app：swift build → .app bundle → ad-hoc 签名 → 校验
# 注意：任何代码/图标改动后都必须重跑本脚本（Apple Silicon 上未签名的 app 会 Killed:9）
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Uncork"
BUNDLE_ID="com.uncork.app"
VERSION="${1:-0.1.0}"   # 可用参数覆盖：./scripts/build_app.sh 0.2.0

echo "==> 1/5 编译（优先通用二进制，无 Xcode 时回退 arm64）"
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
  BIN_PATH=".build/apple/Products/Release/$APP_NAME"
else
  echo "    （本机无 Xcode/xcbuild，回退单架构）"
  swift build -c release
  BIN_PATH=".build/release/$APP_NAME"
fi

echo "==> 2/5 图标（不存在则生成占位图标）"
if [ ! -f build/AppIcon.icns ]; then
  ./scripts/gen_icon.sh
fi

echo "==> 3/5 组装 $APP_NAME.app"
rm -rf "dist/$APP_NAME.app"
mkdir -p "dist/$APP_NAME.app/Contents/MacOS" "dist/$APP_NAME.app/Contents/Resources"
cp "$BIN_PATH" "dist/$APP_NAME.app/Contents/MacOS/$APP_NAME"
cp build/AppIcon.icns "dist/$APP_NAME.app/Contents/Resources/AppIcon.icns"
if [ -f Resources/LICENSE-LGPL.txt ]; then
  cp Resources/LICENSE-LGPL.txt "dist/$APP_NAME.app/Contents/Resources/"
fi

cat > "dist/$APP_NAME.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>开瓶器</string>
    <key>CFBundleDisplayName</key><string>开瓶器 Uncork</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "dist/$APP_NAME.app/Contents/PkgInfo"

echo "==> 4/5 签名（有稳定证书则优先，保证 TCC 授权跨更新保持）"
if security find-certificate -c "Uncork Signing" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
  codesign --force --deep --sign "Uncork Signing" "dist/$APP_NAME.app"
else
  echo "    （无稳定证书，用 ad-hoc——文件夹授权会在每次更新后失效，可运行 scripts/setup_signing_cert.sh 一次性解决）"
  codesign --force --deep --sign - "dist/$APP_NAME.app"
fi
codesign --verify --deep --strict "dist/$APP_NAME.app"

echo "==> 5/5 完成：dist/$APP_NAME.app"
