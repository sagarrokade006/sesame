#!/bin/bash
# Proves an update works end to end without publishing anything: builds an old and a new copy of Sesame under a test
# bundle ID, serves the new one from localhost with its own throwaway signing key, and checks that the old copy finds
# it, verifies it, and installs it. Your installed Sesame and the real update key are never touched.
#
# Usage: tools/test_update.sh
# Signs with SIGNING_IDENTITY, default "Apple Development". Leaves its files in build/update-test.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.sagarrokade.sesame.updatetest"
PORT=8765
ROOT="$PWD/build/update-test"
SERVE="$ROOT/serve"
export SIGNING_IDENTITY="${SIGNING_IDENTITY:-Apple Development}"

step() { printf '\n== %s\n' "$1"; }
fail() { printf 'FAILED: %s\n' "$1" >&2; exit 1; }
app_version() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }
logs_since() {
    /usr/bin/log show --start "$1" --style compact \
        --predicate 'subsystem == "com.sagarrokade.sesame" AND category == "updates"' 2>/dev/null | grep -v '^Timestamp' || true
}
quit_test_app() {
    osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do pgrep -f "$ROOT/install/Sesame.app" >/dev/null || return 0; sleep 0.5; done
    pkill -f "$ROOT/install/Sesame.app" || true
}
wait_for_log() {
    local since="$1" pattern="$2" seconds="$3"
    for _ in $(seq 1 "$seconds"); do
        logs_since "$since" | grep -q "$pattern" && return 0
        sleep 1
    done
    return 1
}

rm -rf "$ROOT"
mkdir -p "$SERVE" "$ROOT/install"
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true

step "Making a throwaway update key"
KEYS="$(swift -e 'import CryptoKit; let key = Curve25519.Signing.PrivateKey(); print(key.rawRepresentation.base64EncodedString()); print(key.publicKey.rawRepresentation.base64EncodedString())')"
PRIVATE_KEY="$(echo "$KEYS" | sed -n 1p)"
PUBLIC_KEY="$(echo "$KEYS" | sed -n 2p)"

export BUNDLE_ID PUBLIC_ED_KEY="$PUBLIC_KEY" FEED_URL="http://127.0.0.1:$PORT/appcast.xml" ALLOWS_AUTOMATIC_UPDATES=1

step "Building old 0.1.0 (1) and new 0.2.0 (2)"
OUTPUT="$ROOT/old" tools/build_release.sh 0.1.0 1 | tail -2
OUTPUT="$ROOT/new" tools/build_release.sh 0.2.0 2 | tail -2
cp "$ROOT/new/Sesame-0.2.0.dmg" "$SERVE/"

step "Signing the update and writing the feed"
SIGNATURE="$(swift -e "
import CryptoKit
import Foundation
let key = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: \"$PRIVATE_KEY\")!)
let file = FileManager.default.contents(atPath: \"$SERVE/Sesame-0.2.0.dmg\")!
print(try! key.signature(for: file).base64EncodedString())")"
swift tools/verify_update_signature.swift "$SERVE/Sesame-0.2.0.dmg" "$SIGNATURE" "$ROOT/new/Info.plist"
DOWNLOAD_URL="http://127.0.0.1:$PORT/Sesame-0.2.0.dmg" python3 tools/make_appcast.py \
    0.2.0 2 "$SIGNATURE" "$(stat -f%z "$SERVE/Sesame-0.2.0.dmg")" "$SERVE/appcast.xml"

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$SERVE" >"$ROOT/server.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; quit_test_app' EXIT
sleep 1
curl -fsS "http://127.0.0.1:$PORT/appcast.xml" >/dev/null || fail "the feed isn't being served"

step "Installing old 0.1.0"
ditto "$ROOT/old/derived/Build/Products/Release/Sesame.app" "$ROOT/install/Sesame.app"
[ "$(app_version "$ROOT/install/Sesame.app" CFBundleShortVersionString)" = "0.1.0" ] || fail "old copy isn't 0.1.0"

step "1/2  A scheduled check finds 0.2.0 and notifies"
defaults write "$BUNDLE_ID" SUEnableAutomaticChecks -bool true
defaults write "$BUNDLE_ID" SUHasLaunchedBefore -bool true
defaults write "$BUNDLE_ID" SULastCheckTime -date "2000-01-01 00:00:00 +0000"
START="$(date '+%Y-%m-%d %H:%M:%S')"
# In the background, like a daily check while you're using another app.
open -g "$ROOT/install/Sesame.app"
wait_for_log "$START" "found 0.2.0" 60 || { logs_since "$START"; fail "the old copy didn't find the update"; }
echo "found the update"
wait_for_log "$START" "notified about 0.2.0\|notifications not allowed\|asking for notification permission" 30 \
    || { logs_since "$START"; fail "no notification was attempted"; }
if logs_since "$START" | grep -q "notified about 0.2.0"; then
    echo "notification posted"
elif logs_since "$START" | grep -q "asking for notification permission"; then
    echo "notification permission prompt shown (the test app is new to macOS)"
else
    echo "notification skipped: notifications are off for the test app"
fi
quit_test_app

step "2/2  The update downloads, is verified, and installs"
defaults write "$BUNDLE_ID" SUAutomaticallyUpdate -bool true
defaults write "$BUNDLE_ID" SULastCheckTime -date "2000-01-01 00:00:00 +0000"
START="$(date '+%Y-%m-%d %H:%M:%S')"
open -g "$ROOT/install/Sesame.app"
wait_for_log "$START" "found 0.2.0" 60 || { logs_since "$START"; fail "the second check didn't find the update"; }
# Sparkle downloads and checks the update in the background, then installs it when the app quits.
for _ in $(seq 1 60); do
    grep -q "GET /Sesame-0.2.0.dmg" "$ROOT/server.log" && break
    sleep 1
done
grep -q "GET /Sesame-0.2.0.dmg" "$ROOT/server.log" || fail "the update was never downloaded"
sleep 5
quit_test_app
for _ in $(seq 1 60); do
    [ "$(app_version "$ROOT/install/Sesame.app" CFBundleShortVersionString 2>/dev/null)" = "0.2.0" ] && break
    sleep 1
done
VERSION="$(app_version "$ROOT/install/Sesame.app" CFBundleShortVersionString)"
[ "$VERSION" = "0.2.0" ] || { logs_since "$START"; fail "still $VERSION after quitting"; }
codesign --verify --deep --strict "$ROOT/install/Sesame.app" || fail "the installed update's signature is broken"
echo "installed copy is now $VERSION ($(app_version "$ROOT/install/Sesame.app" CFBundleVersion)), signature intact"

defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
printf '\nUpdate test passed.\n'
