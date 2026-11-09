#!/bin/bash
# Lets GitHub Actions sign releases the same way tools/release_local.sh does, with your Apple Development certificate.
# Only needed for releases built on GitHub; releasing from your Mac uses the certificate in your login keychain.
#
# 1. In Keychain Access, find "Apple Development: <you>" under My Certificates, right-click it, choose Export, and
#    save a .p12 file with a password.
# 2. Run, from the repo root:  tools/setup_ci_signing.sh path/to/certificate.p12
#
# The script checks the file holds an Apple Development certificate for team 3P6YJ2SJ4X, then stores it and its
# password as the repo's SIGNING_CERTIFICATE_P12 and SIGNING_CERTIFICATE_PASSWORD secrets. Delete the .p12 afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

REPOSITORY="sagarrokade006/sesame"
TEAM="3P6YJ2SJ4X"
stop() { echo "Stopped: $1" >&2; exit 1; }

P12="${1:-}"
[ -f "$P12" ] || stop "Pass the exported .p12 file."
read -r -s -p "Password for $(basename "$P12"): " PASSWORD
echo

WORK="$(mktemp -d)"
trap 'security delete-keychain "$WORK/check.keychain-db" 2>/dev/null || true; rm -rf "$WORK"' EXIT
security create-keychain -p check "$WORK/check.keychain-db"
security import "$P12" -k "$WORK/check.keychain-db" -P "$PASSWORD" >/dev/null || stop "Couldn't open the file with that password."
IDENTITY="$(security find-identity -v -p codesigning "$WORK/check.keychain-db" | grep "Apple Development" || true)"
[ -n "$IDENTITY" ] || stop "The file doesn't contain a valid Apple Development certificate."
security find-certificate -a -c "Apple Development" -p "$WORK/check.keychain-db" | /usr/bin/openssl x509 -noout -subject \
    | grep -q "OU=$TEAM" || stop "The certificate isn't for team $TEAM. Releases must all come from the same team."

base64 -i "$P12" | gh secret set SIGNING_CERTIFICATE_P12 -R "$REPOSITORY"
printf '%s' "$PASSWORD" | gh secret set SIGNING_CERTIFICATE_PASSWORD -R "$REPOSITORY"
echo "Done. GitHub Actions will sign releases as: $(echo "$IDENTITY" | sed -E 's/.*"(.*)".*/\1/')"
