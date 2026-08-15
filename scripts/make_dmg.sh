#!/bin/bash
# 打包 .dmg：先构建 .app，再用 create-dmg 生成带背景图和 Applications 链接的安装盘
# 注意：卷名必须 ASCII（create-dmg 对非 ASCII 卷名有兼容坑）
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build_app.sh

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "==> 安装 create-dmg（Homebrew）…"
  brew install create-dmg
fi

if [ ! -f Resources/dmg-background.png ]; then
  echo "==> 生成 DMG 背景图"
  swift scripts/render_placeholder.swift dmg-bg
fi

rm -f dist/Uncork-0.1.0.dmg
create-dmg \
  --volname "Uncork" \
  --volicon build/AppIcon.icns \
  --window-size 640 400 \
  --icon "Uncork.app" 160 180 \
  --app-drop-link 420 180 \
  --background Resources/dmg-background.png \
  --hide-extension "Uncork.app" \
  dist/Uncork-0.1.0.dmg dist/

echo "==> 完成：dist/Uncork-0.1.0.dmg"
