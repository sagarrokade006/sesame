#!/bin/bash
# Publishes a release from this Mac, doing what .github/workflows/release.yml does on GitHub Actions: test, build,
# sign with the release certificate, sign the update, write the feed, and publish the DMG and feed to GitHub Releases.
#
# Usage, from the repo root, on main with everything pushed:  tools/release_local.sh
#
# It uses the two Keychain backups the setup scripts made ("Sesame Code Signing" and "Sesame update signing key"), so
# macOS may ask once to let `security` read each of them. The certificate must be trusted for code signing first; the
# script stops and prints the one command if it isn't.
set -euo pipefail
cd "$(dirname "$0")/.."

REPOSITORY="sagarrokade006/sesame"
CERTIFICATE_NAME="Sesame Code Signing"
WORK="$(mktemp -d)"
KEYCHAIN="$WORK/release.keychain-db"
ORIGINAL_KEYCHAINS="$(security list-keychains -d user | tr -d '"' | xargs)"

cleanup() {
    # Puts the keychain search list back exactly as it was, then removes the temporary keychain and files.
    # shellcheck disable=SC2086
    security list-keychains -d user -s $ORIGINAL_KEYCHAINS
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT
stop() { echo "Stopped: $1" >&2; exit 1; }
step() { printf '\n== %s\n' "$1"; }

step "Checking the repo"
[ "$(git branch --show-current)" = "main" ] || stop "Switch to main first."
[ -z "$(git status --porcelain)" ] || stop "Commit or stash your changes first, so the release matches what's on GitHub."
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || stop "Push main first (or pull), so the release matches GitHub."

BASE="$(grep -m1 'MARKETING_VERSION = ' Sesame.xcodeproj/project.pbxproj | sed -E 's/.*= ([0-9.]+);/\1/')"
BUILD="$(git rev-list --count HEAD)"
VERSION="$BASE.$BUILD"
if gh release view "v$VERSION" -R "$REPOSITORY" >/dev/null 2>&1; then
    stop "v$VERSION is already released. Commit and push a change to release again."
fi
echo "Releasing $VERSION ($BUILD) from $(git rev-parse --short HEAD)"

step "Loading the signing certificate"
P12="$(security find-generic-password -s "$CERTIFICATE_NAME" -a certificate -w)" || stop "No certificate backup. Run tools/setup_signing_certificate.sh."
P12_PASSWORD="$(security find-generic-password -s "$CERTIFICATE_NAME" -a password -w)"
printf '%s' "$P12" | base64 --decode > "$WORK/certificate.p12"
/usr/bin/openssl pkcs12 -in "$WORK/certificate.p12" -nokeys -passin "pass:$P12_PASSWORD" -out "$WORK/certificate.pem" 2>/dev/null
if ! security verify-cert -c "$WORK/certificate.pem" -p codeSign >/dev/null 2>&1; then
    FINGERPRINT="$(/usr/bin/openssl x509 -in "$WORK/certificate.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
    mkdir -p build
    cp "$WORK/certificate.pem" build/sesame-code-signing.pem
    cat >&2 <<EOF

macOS only signs with a certificate it trusts. Trust Sesame's, for code signing only, by running this once
(macOS asks for your password):

    security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db build/sesame-code-signing.pem

The certificate is "$CERTIFICATE_NAME", SHA-256 $FINGERPRINT.
Then run tools/release_local.sh again.
EOF
    exit 1
fi
KEYCHAIN_PASSWORD="$(uuidgen)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/certificate.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN" $ORIGINAL_KEYCHAINS
IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/1\)/ {print $2; exit}')"
[ -n "$IDENTITY" ] || stop "The certificate imported but isn't usable for signing."
rm "$WORK/certificate.p12"

step "Testing"
(cd Packages/SesameCore && swift test 2>&1 | tail -1)

step "Building"
SIGNING_IDENTITY="$IDENTITY" SIGNING_KEYCHAIN="$KEYCHAIN" tools/build_release.sh "$VERSION" "$BUILD" | grep -v "replacing existing signature"
APP="build/release/derived/Build/Products/Release/Sesame.app"
DMG="build/release/Sesame-$VERSION.dmg"
codesign -d -r- "$APP" 2>&1 | grep -qE 'certificate (leaf|root) = H' || stop "The app isn't signed with the certificate."

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
python3 tools/make_appcast.py "$VERSION" "$BUILD" "$SIGNATURE" "$(stat -f%z "$DMG")" build/release/appcast.xml

step "Publishing v$VERSION"
gh release create "v$VERSION" "$DMG" build/release/appcast.xml \
    -R "$REPOSITORY" \
    --target "$(git rev-parse HEAD)" \
    --title "Sesame $VERSION" \
    --generate-notes
echo "Published: https://github.com/$REPOSITORY/releases/tag/v$VERSION"
