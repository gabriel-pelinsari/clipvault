#!/usr/bin/env bash
# Creates a local, self-signed code signing identity ("ClipVault Local Signing")
# in the login keychain. Optional but recommended.
#
# Why: an ad hoc signature changes on every build, so after each update macOS
# asks again for Keychain access and forgets the Accessibility permission.
# Signing every build with the same certificate keeps the app's identity stable.
#
# The certificate is not added to any trust settings; it is only usable by
# /usr/bin/codesign on this Mac.
set -euo pipefail

NAME="ClipVault Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Identity \"$NAME\" already exists."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS="$(openssl rand -hex 16)"

openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

openssl pkcs12 -export -out "$WORK/identity.p12" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
  -passout "pass:$PASS"

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "Created code signing identity \"$NAME\"."
