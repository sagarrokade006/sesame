#!/bin/bash
# Builds Sesame.app and packages it as a DMG in build/release.
#
# Usage: tools/build_release.sh <version> <build number>
#
# Optional environment:
#   DEVELOPER_ID_IDENTITY                      Signs with this certificate instead of ad-hoc signing.
#   APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID  With a certificate, also notarizes the DMG.
set -euo pipefail

VERSION="$1"
BUILD="$2"
cd "$(dirname "$0")/.."

OUTPUT="build/release"
DERIVED="build/derived"
DMG="$OUTPUT/Sesame-$VERSION.dmg"
IDENTITY="${DEVELOPER_ID_IDENTITY:--}"

if [ "$IDENTITY" = "-" ]; then
    HARDENED=NO
    SIGN_OPTIONS=()
else
    HARDENED=YES
    SIGN_OPTIONS=(--options runtime --timestamp)
fi

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"

xcodebuild \
    -project Sesame.xcodeproj \
    -scheme Sesame \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    CODE_SIGN_ENTITLEMENTS=Config/Sesame-Distribution.entitlements \
    ENABLE_HARDENED_RUNTIME="$HARDENED" \
    build | tail -3

APP="$DERIVED/Build/Products/Release/Sesame.app"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"

sign() {
    codesign --force --sign "$IDENTITY" ${SIGN_OPTIONS[@]+"${SIGN_OPTIONS[@]}"} "$@"
}

# Nested code has to be signed before whatever contains it.
sign "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign "$SPARKLE/Updater.app"
sign "$SPARKLE/Autoupdate"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --entitlements Config/Sesame-Distribution.entitlements "$APP"
codesign --verify --deep --strict "$APP"

STAGE="$OUTPUT/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Sesame" -srcfolder "$STAGE" -format UDZO -ov "$DMG"
rm -rf "$STAGE"

if [ "$IDENTITY" != "-" ]; then
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
