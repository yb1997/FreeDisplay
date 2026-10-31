#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: ./scripts/release.sh v1.1.0}"
REPO="${RELEASE_REPO:-yb1997/FreeDisplay}"

# The tag must match the app's version, or the in-app update check misfires.
APP_VERSION=$(grep -E '^ *MARKETING_VERSION:' project.yml | sed -E 's/^[^:]*: *"?([0-9.]+)"?.*$/\1/')
if [ "v${APP_VERSION}" != "$VERSION" ]; then
  echo "ERROR: project.yml MARKETING_VERSION is ${APP_VERSION}, but the tag is ${VERSION}"
  exit 1
fi

# Release notes: the CHANGELOG section for this version only.
NOTES=$(mktemp)
awk -v v="## ${VERSION}" 'index($0, v) == 1 {p=1; next} /^## v/ && p {exit} p && $0 != "---"' CHANGELOG.md > "$NOTES"
if [ ! -s "$NOTES" ]; then
  echo "ERROR: no '## ${VERSION}' section in CHANGELOG.md"
  exit 1
fi

echo "=== Building Release ${VERSION} ==="
xcodegen generate
./scripts/build-dmg.sh

echo "=== Creating GitHub Release on ${REPO} ==="
gh release create "$VERSION" \
  --repo "$REPO" \
  --target main \
  --title "FreeDisplay ${VERSION}" \
  --notes-file "$NOTES" \
  FreeDisplay.dmg

rm -f "$NOTES"
echo "=== Release ${VERSION} published ==="
