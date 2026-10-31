#!/bin/bash
set -euo pipefail

# Configuration
APP_NAME="FreeDisplay"
SCHEME="FreeDisplay"
BUILD_DIR="$(pwd)/build"
DMG_NAME="${APP_NAME}.dmg"

echo "=== Building ${APP_NAME} Release ==="

# Clean and build Release (skip Xcode's codesign; we'll sign manually after stripping xattrs)
xcodebuild -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  clean build 2>&1 | tail -20

# Find the .app
APP_PATH="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: ${APP_NAME}.app not found in build output"
  exit 1
fi
echo "Found app: $APP_PATH"

# Strip extended attributes (resource forks, .DS_Store detritus) before signing
echo "=== Stripping extended attributes ==="
xattr -cr "$APP_PATH"

# Sign with a stable identity so users' Accessibility grant survives updates
# (an ad-hoc signature changes every build). Defaults to the local self-signed
# certificate described in the README; set SIGN_IDENTITY=- for ad-hoc.
SIGN_IDENTITY="${SIGN_IDENTITY:-FreeDisplay Local}"
echo "=== Signing with: ${SIGN_IDENTITY} ==="
codesign --force --deep --options runtime \
  --entitlements FreeDisplay/FreeDisplay.entitlements \
  --sign "$SIGN_IDENTITY" "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"

# Create staging directory for DMG
STAGING_DIR="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Create DMG
echo "=== Creating DMG ==="
DMG_OUTPUT="$(pwd)/${DMG_NAME}"
rm -f "$DMG_OUTPUT"
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$DMG_OUTPUT"

echo "=== Done ==="
echo "DMG: $DMG_OUTPUT"
ls -lh "$DMG_OUTPUT"
