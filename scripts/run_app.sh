#!/bin/bash
# 开发快循环：编译后直接运行裸二进制（终端可直接看 stderr 日志）
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
echo "==> 启动 Uncork（Ctrl+C 退出）"
exec .build/release/Uncork
