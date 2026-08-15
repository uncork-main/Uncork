#!/bin/bash
# 一键发布：构建 → 打 DMG → 计算校验值 → 提交推送 → 创建 GitHub Release
# 用法: ./scripts/release.sh <版本号> [更新说明]
# 示例: ./scripts/release.sh v0.2.0 "修复了 XX 问题"
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?用法: ./scripts/release.sh <版本号> [更新说明]}"
NOTES="${2:-}"

# 标签统一带 v 前缀（v0.1.0、v0.1.1…）
TAG="$VERSION"
if [[ "$TAG" != v* ]]; then
  TAG="v$TAG"
fi

echo "==> 1/4 构建并打包 DMG"
./scripts/make_dmg.sh "$VERSION"

DMG="dist/Uncork-$VERSION.dmg"

echo "==> 2/4 计算校验值"
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "    SHA-256: $SHA"

echo "==> 3/4 提交并推送"
git add -A
git commit -m "发布 $VERSION" --allow-empty
git push

echo "==> 4/4 创建 GitHub Release"
if [ -n "$NOTES" ]; then
  UPDATE_SECTION="### 本次更新
$NOTES"
else
  UPDATE_SECTION=""
fi

cat > /tmp/uncork-release-notes.md <<EOF
## 开瓶器 Uncork $VERSION

类 CrossOver 的 macOS 应用：通过 Wine 兼容层在 Mac 上运行 Windows 程序。免费、开源、无广告。

$UPDATE_SECTION

### 📦 安装
1. 下载 DMG，双击挂载后把「开瓶器」拖入 Applications
2. 首次打开：**右键 → 打开**（自签名应用，未购买 Apple 公证，属正常提示）

### 🔐 校验
\`\`\`
SHA-256: $SHA
\`\`\`

### 📄 许可与声明
本项目 MIT（AI 辅助开发，人工审查）；Wine 引擎 LGPL 2.1+；DXMT MIT。
完整免责声明见 [DISCLAIMER.md](https://github.com/uncork-main/Uncork/blob/main/DISCLAIMER.md)。

### 🐛 反馈
问题与建议请提 [Issue](https://github.com/uncork-main/Uncork/issues)。
EOF

gh release create "$TAG" "$DMG" --title "开瓶器 Uncork $VERSION" --notes-file /tmp/uncork-release-notes.md

echo ""
echo "✅ 发布完成：https://github.com/uncork-main/Uncork/releases/tag/$TAG"
