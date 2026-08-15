#!/bin/bash
# 1024px PNG → AppIcon.icns（sips + iconutil，文件名必须精确匹配）
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Resources/AppIcon-1024.png"
if [ ! -f "$SRC" ]; then
  echo "==> 未找到 ${SRC}，生成占位图标"
  swift scripts/render_placeholder.swift icon
fi

WIDTH=$(sips -g pixelWidth "$SRC" | awk '/pixelWidth/{print $2}')
if [ "$WIDTH" != "1024" ]; then
  echo "错误：图标必须是 1024×1024（当前 ${WIDTH}）" >&2
  exit 1
fi

rm -rf build/AppIcon.iconset
mkdir -p build/AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$SRC" --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" "$SRC" --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
rm -rf build/AppIcon.iconset
echo "==> 生成 build/AppIcon.icns"
