#!/bin/bash
set -euo pipefail

# Usage: ./release.sh <version> "<release notes>"
# e.g.   ./release.sh 1.0 "Initial public release"
VERSION="${1:?Usage: ./release.sh <version> \"<release notes>\"}"
NOTES="${2:?Please provide release notes as the second argument}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="OpenFlowVoice"
SCHEME="OpenFlowVoice"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
ARCHIVE_PATH="/tmp/${APP_NAME}-${VERSION}.xcarchive"
DMG_PATH="/tmp/${DMG_NAME}"
APPCAST="$SCRIPT_DIR/docs/appcast.xml"
BUILD_NUM=$(date +%Y%m%d%H%M)
PBXPROJ="$SCRIPT_DIR/OpenFlowVoice.xcodeproj/project.pbxproj"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  OpenFlow Voice release v${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Preflight ────────────────────────────────────────────────────────────────

echo "→ Checking dependencies..."
command -v gh >/dev/null || { echo "Error: gh not found. brew install gh"; exit 1; }
command -v create-dmg >/dev/null || { echo "Error: create-dmg not found. brew install create-dmg"; exit 1; }

SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/sparkle/*" 2>/dev/null | head -1)
[ -z "$SIGN_UPDATE" ] && { echo "Error: sign_update not found. Open project in Xcode to resolve packages."; exit 1; }
echo "  sign_update: $SIGN_UPDATE"

git -C "$SCRIPT_DIR" status --short | grep -q '^[MADRC]' && {
    echo "Error: Staged changes exist. Commit or stash first."; exit 1; }

# ── Version bump ─────────────────────────────────────────────────────────────

echo "→ Bumping version to ${VERSION} (build ${BUILD_NUM})..."
python3 - "$PBXPROJ" "$VERSION" "$BUILD_NUM" <<'PYEOF'
import sys, re
path, version, build = sys.argv[1:]
c = open(path).read()
c = re.sub(r'(MARKETING_VERSION = )\S+;', rf'\g<1>{version};', c)
c = re.sub(r'(CURRENT_PROJECT_VERSION = )\S+;', rf'\g<1>{build};', c)
open(path, 'w').write(c)
print(f"  MARKETING_VERSION={version}  CURRENT_PROJECT_VERSION={build}")
PYEOF

git -C "$SCRIPT_DIR" add "OpenFlowVoice.xcodeproj/project.pbxproj"
git -C "$SCRIPT_DIR" commit -m "Bump version to ${VERSION}"

# ── Archive ───────────────────────────────────────────────────────────────────

echo "→ Archiving..."
xcodebuild archive \
    -project "$SCRIPT_DIR/OpenFlowVoice.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    SKIP_INSTALL=NO \
    2>&1 | grep -E "^(error:|warning: .*error|Build succeeded|ARCHIVE)" || true

APP_PATH=$(find "$ARCHIVE_PATH/Products" -name "*.app" -maxdepth 3 | head -1)
[ -z "$APP_PATH" ] && { echo "Error: No .app in archive."; exit 1; }
echo "  App: $APP_PATH"

# ── DMG ───────────────────────────────────────────────────────────────────────

echo "→ Creating DMG..."
rm -f "$DMG_PATH"
STAGING="/tmp/${APP_NAME}-staging-$$"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"

create-dmg \
    --volname "OpenFlow Voice" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "${APP_NAME}.app" 180 185 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 480 185 \
    --no-internet-enable \
    "$DMG_PATH" "$STAGING/" 2>&1 | grep -v "^$" || true

rm -rf "$STAGING"
echo "  Created: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"

# ── Sign ──────────────────────────────────────────────────────────────────────

echo "→ Signing with Sparkle..."
SIGN_OUT=$("$SIGN_UPDATE" "$DMG_PATH" 2>&1)
ED_SIG=$(echo "$SIGN_OUT" | grep -oE 'edSignature="[^"]+"' | head -1 | cut -d'"' -f2)
FILE_LEN=$(echo "$SIGN_OUT" | grep -oE 'length="[0-9]+"' | head -1 | cut -d'"' -f2)
[ -z "$ED_SIG" ] || [ -z "$FILE_LEN" ] && {
    echo "Error: Could not parse Sparkle signature:"; echo "$SIGN_OUT"; exit 1; }
echo "  edSignature: ${ED_SIG:0:20}...  length: $FILE_LEN"

# ── Appcast ───────────────────────────────────────────────────────────────────

echo "→ Updating appcast.xml..."
RELEASE_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/Hitjack007/OpenFlow-Voice/releases/download/v${VERSION}/${DMG_NAME}"

python3 - "$APPCAST" "$VERSION" "$BUILD_NUM" "$RELEASE_DATE" "$DOWNLOAD_URL" "$ED_SIG" "$FILE_LEN" <<'PYEOF'
import sys
path, version, build, date, url, sig, length = sys.argv[1:]
item = (
    f"\n    <item>\n"
    f"      <title>Version {version}</title>\n"
    f"      <pubDate>{date}</pubDate>\n"
    f"      <sparkle:version>{build}</sparkle:version>\n"
    f"      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
    f"      <enclosure\n"
    f"        url=\"{url}\"\n"
    f"        sparkle:edSignature=\"{sig}\"\n"
    f"        length=\"{length}\"\n"
    f"        type=\"application/octet-stream\"/>\n"
    f"    </item>"
)
c = open(path).read()
c = c.replace('  </channel>', item + '\n\n  </channel>', 1)
open(path, 'w').write(c)
print(f"  Added v{version} to appcast")
PYEOF

# ── GitHub release ─────────────────────────────────────────────────────────

echo "→ Creating GitHub release v${VERSION}..."
gh release create "v${VERSION}" "$DMG_PATH" \
    --title "OpenFlow Voice v${VERSION}" \
    --notes "$NOTES"

# ── Push ──────────────────────────────────────────────────────────────────────

echo "→ Pushing appcast..."
git -C "$SCRIPT_DIR" add docs/appcast.xml
git -C "$SCRIPT_DIR" commit -m "Release v${VERSION}"
git -C "$SCRIPT_DIR" push

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  v${VERSION} shipped!"
echo "  Appcast live at: https://hitjack007.github.io/OpenFlow-Voice/appcast.xml"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
