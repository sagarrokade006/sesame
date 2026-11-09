#!/bin/bash
# Builds Sesame.app and packages it as a DMG in build/release.
#
# Usage: tools/build_release.sh <version> <build number>
#
# Signing, in order of preference:
#   DEVELOPER_ID_IDENTITY   An Apple Developer ID. Adds the hardened runtime, and with APPLE_ID, APPLE_APP_PASSWORD and
#                           APPLE_TEAM_ID also notarizes, so Gatekeeper opens it without a warning.
#   SIGNING_IDENTITY        Any other certificate, given by name or SHA-1, normally the free Apple Development one
#                           (see tools/release_local.sh). Every release must come from the same Apple team: macOS keeps
#                           Accessibility and Input Monitoring, and the Keychain keeps Sesame's key, only for an
#                           Apple-issued signature that stays the same from version to version.
#   neither                 Ad-hoc. Fine for trying a build, but each one looks like a different app to macOS.
#
# For testing updates locally (tools/test_update.sh):
#   BUNDLE_ID, FEED_URL, PUBLIC_ED_KEY   Replace the real values in the built app.
#   ALLOWS_AUTOMATIC_UPDATES=1           Lets the test turn on silent installs.
#   OUTPUT                               Where the DMG goes, instead of build/release.
set -euo pipefail

VERSION="$1"
BUILD="$2"
cd "$(dirname "$0")/.."

OUTPUT="${OUTPUT:-build/release}"
DERIVED="$OUTPUT/derived"
DMG="$OUTPUT/Sesame-$VERSION.dmg"

if [ -n "${DEVELOPER_ID_IDENTITY:-}" ]; then
    IDENTITY="$DEVELOPER_ID_IDENTITY"
    HARDENED=YES
    SIGN_OPTIONS=(--options runtime --timestamp)
else
    IDENTITY="${SIGNING_IDENTITY:--}"
    # The hardened runtime only matters for notarization, which needs a Developer ID.
    HARDENED=NO
    SIGN_OPTIONS=()
fi
KEYCHAIN_OPTIONS=()
if [ -n "${SIGNING_KEYCHAIN:-}" ]; then KEYCHAIN_OPTIONS=(--keychain "$SIGNING_KEYCHAIN"); fi

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"

PLIST="Config/Info.plist"
if [ -n "${FEED_URL:-}${PUBLIC_ED_KEY:-}${ALLOWS_AUTOMATIC_UPDATES:-}" ]; then
    PLIST="$OUTPUT/Info.plist"
    cp Config/Info.plist "$PLIST"
    [ -z "${FEED_URL:-}" ] || plutil -replace SUFeedURL -string "$FEED_URL" "$PLIST"
    [ -z "${PUBLIC_ED_KEY:-}" ] || plutil -replace SUPublicEDKey -string "$PUBLIC_ED_KEY" "$PLIST"
    [ -z "${ALLOWS_AUTOMATIC_UPDATES:-}" ] || plutil -replace SUAllowsAutomaticUpdates -bool true "$PLIST"
fi
BUNDLE_SETTINGS=()
if [ -n "${BUNDLE_ID:-}" ]; then BUNDLE_SETTINGS=(PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"); fi

xcodebuild \
    -project Sesame.xcodeproj \
    -scheme Sesame \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    INFOPLIST_FILE="$PLIST" \
    ${BUNDLE_SETTINGS[@]+"${BUNDLE_SETTINGS[@]}"} \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    CODE_SIGN_ENTITLEMENTS=Config/Sesame-Distribution.entitlements \
    ENABLE_HARDENED_RUNTIME="$HARDENED" \
    build > "$OUTPUT/xcodebuild.log" 2>&1 || { grep -E "error:" "$OUTPUT/xcodebuild.log" | head -20; exit 1; }
if grep -E "^/.*(error|warning):" "$OUTPUT/xcodebuild.log" | sort -u | grep .; then
    echo "The build has warnings. Fix them before releasing." >&2
    exit 1
fi

APP="$DERIVED/Build/Products/Release/Sesame.app"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"

sign() {
    codesign --force --sign "$IDENTITY" ${KEYCHAIN_OPTIONS[@]+"${KEYCHAIN_OPTIONS[@]}"} ${SIGN_OPTIONS[@]+"${SIGN_OPTIONS[@]}"} "$@"
}

# Nested code has to be signed before whatever contains it.
sign "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign "$SPARKLE/Updater.app"
sign "$SPARKLE/Autoupdate"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --entitlements Config/Sesame-Distribution.entitlements "$APP"
codesign --verify --deep --strict "$APP"
echo "Signed: $(codesign -d -r- "$APP" 2>&1 | grep designated)"

STAGE="$OUTPUT/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Sesame" -srcfolder "$STAGE" -format UDZO -ov "$DMG"
rm -rf "$STAGE"

if [ -n "${DEVELOPER_ID_IDENTITY:-}" ]; then
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
    if [ -n "${APPLE_ID:-}" ]; then
        xcrun notarytool submit "$DMG" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_APP_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait
        xcrun stapler staple "$DMG"
    fi
fi

echo "$DMG"
