#!/bin/bash
# 创建稳定的自签名代码签名证书（一次性设置）。
# 作用：TCC 文件夹访问授权绑定签名身份，ad-hoc 签名每次构建都变、
# 授权会反复失效；固定证书后授权一次、跨更新永久保持。
set -euo pipefail

CERT_NAME="Uncork Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "✅ 证书已存在：$CERT_NAME（无需重复创建）"
  exit 0
fi

cd "$(dirname "$0")/.."
mkdir -p build/signing

# 自签名证书必须带 codeSigning 扩展用途，否则 codesign 拒绝使用
cat > build/signing/codesign.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Uncork Signing
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "==> 生成自签名证书…"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout build/signing/uncork-signing.key \
  -out build/signing/uncork-signing.crt \
  -days 3650 -config build/signing/codesign.cnf 2>/dev/null

openssl pkcs12 -export \
  -out build/signing/uncork-signing.p12 \
  -inkey build/signing/uncork-signing.key \
  -in build/signing/uncork-signing.crt \
  -passout pass:uncork 2>/dev/null

echo "==> 导入钥匙串（授权 codesign 使用）…"
security import build/signing/uncork-signing.p12 \
  -k "$KEYCHAIN" -P uncork -T /usr/bin/codesign

echo "✅ 已创建签名证书：$CERT_NAME"
echo "   之后 build_app.sh 会自动用它签名，文件夹授权不再反复弹出。"
echo "   注意：私钥保存在 build/signing/（已加入 .gitignore 建议），换机器分发包仍自带该身份。"
