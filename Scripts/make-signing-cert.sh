#!/bin/bash
# 创建一次性的本地代码签名证书「Chronicle Local Signing」。
#
# 为什么需要它：ad-hoc 签名（codesign -s -）每次构建的 cdhash 都不同，
# macOS 把这个 cdhash 当作应用身份，所以每次更新后辅助功能 / 屏幕录制 /
# 自动化权限都会被当成新应用，需要重新授权。换成固定证书签名后，
# 系统识别到的是「同一个开发者签的同一个 Bundle ID」，权限得以保留。
#
# 只需要跑一次：./Scripts/make-signing-cert.sh
set -euo pipefail

IDENTITY="Chronicle Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "已存在签名身份：$IDENTITY"
    exit 0
fi

echo "==> 生成自签名证书"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
    -subj "/CN=$IDENTITY/O=Chronicle/C=CN" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "subjectKeyIdentifier=hash" 2>/dev/null

openssl pkcs12 -export -legacy -out "$TMP/identity.p12" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$IDENTITY" -passout pass:chronicle 2>/dev/null \
  || openssl pkcs12 -export -out "$TMP/identity.p12" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$IDENTITY" -passout pass:chronicle

echo "==> 导入登录钥匙串（需要你输入一次登录密码）"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P chronicle \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "==> 信任这张证书用于代码签名（需要你确认一次）"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "==> 允许 codesign 使用这把私钥（需要你输入一次登录密码）"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$KEYCHAIN" >/dev/null 2>&1 || \
    echo "   （跳过：可在弹出的钥匙串提示里点「始终允许」）"

echo
security find-identity -v -p codesigning | grep "$IDENTITY" || {
    echo "证书已导入但未生效，请打开「钥匙串访问」确认 $IDENTITY 被信任为代码签名证书。"
    exit 1
}
echo "完成：之后每次构建都会用 $IDENTITY 签名，权限不再重置。"
