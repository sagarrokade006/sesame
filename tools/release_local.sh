#!/bin/bash
# Publishes a release from this Mac, doing what .github/workflows/release.yml does on GitHub Actions: test, build,
# sign, sign the update, write the feed, and publish the DMG and feed to GitHub Releases.
#
# Usage, from the repo root, on main with everything pushed:  tools/release_local.sh
#
# Signs with the Apple Development certificate in your login keychain, the free one Xcode creates for your Apple ID.
# Because Apple issued it, macOS recognizes every release as the same app: Accessibility, Input Monitoring, and the
# Keychain item holding Sesame's key all carry over between updates. The update itself is signed with the key from
# swift tools/setup_update_key.swift, which macOS may ask once to let `security` read.
set -euo pipefail
cd "$(dirname "$0")/.."

REPOSITORY="sagarrokade006/sesame"
TEAM="3P6YJ2SJ4X"

stop() { echo "Stopped: $1" >&2; exit 1; }
step() { printf '\n== %s\n' "$1"; }

step "Checking the repo"
[ "$(git branch --show-current)" = "main" ] || stop "Switch to main first."
[ -z "$(git status --porcelain)" ] || stop "Commit or stash your changes first, so the release matches what's on GitHub."
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || stop "Push main first (or pull), so the release matches GitHub."
read -r VERSION BUILD < <(tools/next_version.sh)
echo "Releasing $VERSION ($BUILD) from $(git rev-parse --short HEAD)"
# Every release needs its notes: they show in the update window, in the app after updating, and on GitHub.
NOTES_MARKDOWN="$(python3 tools/changelog.py "$VERSION" markdown)" || exit 1
NOTES_HTML="$(python3 tools/changelog.py "$VERSION" html)"
printf '%s\n' "$NOTES_MARKDOWN"

step "Finding the signing certificate"
IDENTITY="$(security find-identity -v -p codesigning | grep "Apple Development" | grep -m1 -o '[0-9A-F]\{40\}' || true)"
[ -n "$IDENTITY" ] || stop "No Apple Development certificate. In Xcode, Settings > Accounts, add your Apple ID and choose Manage Certificates > +."
security find-identity -v -p codesigning | grep "$IDENTITY"

step "Testing"
(cd Packages/SesameCore && swift test 2>&1 | tail -1)

step "Building"
SIGNING_IDENTITY="$IDENTITY" tools/build_release.sh "$VERSION" "$BUILD" | grep -v "replacing existing signature"
APP="build/release/derived/Build/Products/Release/Sesame.app"
DMG="build/release/Sesame-$VERSION.dmg"
# Every release must carry an Apple-issued signature from the same team, or macOS treats the update as a different app.
codesign -d -r- "$APP" 2>&1 | grep -q 'anchor apple generic' || stop "The app isn't signed by an Apple-issued certificate."
[ "$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')" = "$TEAM" ] || stop "The app isn't signed by team $TEAM."

step "Signing the update and writing the feed"
UPDATE_KEY="$(security find-generic-password -s "Sesame update signing key" -a sesame -w)" || stop "No update key. Run swift tools/setup_update_key.swift."
SIGNATURE="$(UPDATE_KEY="$UPDATE_KEY" DMG="$DMG" swift -e '
import CryptoKit
import Foundation
let environment = ProcessInfo.processInfo.environment
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: environment["UPDATE_KEY"]!)!)
let file = try Data(contentsOf: URL(fileURLWithPath: environment["DMG"]!))
print(try key.signature(for: file).base64EncodedString())')"
unset UPDATE_KEY
swift tools/verify_update_signature.swift "$DMG" "$SIGNATURE"
NOTES_HTML="$NOTES_HTML" python3 tools/make_appcast.py "$VERSION" "$BUILD" "$SIGNATURE" "$(stat -f%z "$DMG")" build/release/appcast.xml

step "Publishing v$VERSION"
gh release create "v$VERSION" "$DMG" build/release/appcast.xml \
    -R "$REPOSITORY" \
    --target "$(git rev-parse HEAD)" \
    --title "Sesame $VERSION" \
    --notes "$NOTES_MARKDOWN"
echo "Published: https://github.com/$REPOSITORY/releases/tag/v$VERSION"
