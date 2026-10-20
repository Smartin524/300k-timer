#!/bin/bash
# Create a stable, self-signed code-signing identity for local builds.
# Ad-hoc signatures change on every build, so macOS forgets the Chrome automation
# permission; a fixed certificate keeps the app's identity the same across rebuilds.
# The identity lives in its own keychain under .signing/ (git-ignored). The login
# keychain, the keychain search list and system trust settings are left unchanged.
set -euo pipefail
cd "$(dirname "$0")/.."
dir="$PWD/.signing"
keychain="$dir/signing.keychain-db"
name="300k Timer Local Signing"
if [ -f "$keychain" ]; then
    echo "Signing identity already exists: $keychain"
    exit 0
fi
mkdir -p "$dir"
chmod 700 "$dir"
password="$(openssl rand -hex 24)"
(umask 077 && printf '%s' "$password" > "$dir/password")
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$name" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
# macOS `security` cannot read OpenSSL 3's default PKCS#12 encryption.
openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -name "$name" -out "$tmp/identity.p12" -passout "pass:$password"

# create-keychain appends to the user search list; restore it afterwards.
saved_list=()
while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    saved_list+=("${line//\"/}")
done < <(security list-keychains -d user)
security create-keychain -p "$password" "$keychain"
security list-keychains -d user -s "${saved_list[@]}"
security set-keychain-settings "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$tmp/identity.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
echo "Created signing identity \"$name\" in $keychain"
