#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
app="$PWD/dist/300k Timer.app"
swift build -c "$configuration"
bin_dir="$(swift build -c "$configuration" --show-bin-path)"
# Recreate this generated bundle so removed resources cannot survive a rebuild.
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/300KTimer" "$app/Contents/MacOS/300KTimer"
cp Resources/Info.plist "$app/Contents/Info.plist"

swift scripts/make-icon.swift "$app/Contents/Resources"
cp "$app/Contents/Resources/AppIcon.icns" "$app/Contents/Resources/HourglassGreen.icns"
keychain="$PWD/.signing/signing.keychain-db"
if [ -n "${SIGNING_IDENTITY:-}" ]; then
    codesign --force --sign "$SIGNING_IDENTITY" "$app"
elif [ -f "$keychain" ]; then
    # A stable identity keeps macOS automation permission across rebuilds.
    security unlock-keychain -p "$(cat "$PWD/.signing/password")" "$keychain"
    codesign --force --sign "300k Timer Local Signing" --keychain "$keychain" "$app"
else
    echo "Signing ad hoc; run scripts/make-signing-identity.sh once for a stable signature." >&2
    codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
printf '\nBuilt: %s\n' "$app"
