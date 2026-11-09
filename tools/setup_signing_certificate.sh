#!/bin/bash
# Run once, from the repo root:  tools/setup_signing_certificate.sh
#
# Creates the self-signed certificate every release is signed with. Without an Apple Developer account this is what
# keeps updates working smoothly: macOS remembers Camera, Accessibility, and Input Monitoring, and the Keychain keeps
# Sesame's key, only for an app whose signature stays the same from version to version.
#
# The certificate and its password go to the repo's GitHub Actions secrets, with a backup copy in your login Keychain.
# Nothing is printed. Losing it isn't a disaster, but the next release would ask everyone for permissions again.
set -euo pipefail
cd "$(dirname "$0")/.."

REPOSITORY="sagarrokade006/sesame"
NAME="Sesame Code Signing"
OPENSSL=/usr/bin/openssl   # LibreSSL, whose .p12 files macOS's security tool can always read.

stop() { echo "Stopped: $1" >&2; exit 1; }

command -v gh >/dev/null || stop "GitHub CLI not found."
if gh secret list -R "$REPOSITORY" | grep -q '^SIGNING_CERTIFICATE_P12'; then
    stop "A signing certificate already exists. Replacing it would make the next update look like a different app."
fi
if security find-generic-password -s "$NAME" -a certificate >/dev/null 2>&1; then
    stop "A backup certificate is already in your Keychain. Restore the secrets from it instead of making a new one."
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/certificate.cnf" <<EOF
[req]
distinguished_name = name
x509_extensions = extensions
prompt = no
[name]
CN = $NAME
O = Sesame (github.com/$REPOSITORY)
[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

# Twenty years, so it outlives the app rather than forcing a new signature on everyone.
"$OPENSSL" req -x509 -newkey rsa:3072 -sha256 -nodes -days 7300 \
    -config "$WORK/certificate.cnf" -keyout "$WORK/key.pem" -out "$WORK/certificate.pem" 2>/dev/null
PASSWORD="$("$OPENSSL" rand -base64 32)"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/certificate.pem" -name "$NAME" \
    -out "$WORK/certificate.p12" -passout "pass:$PASSWORD"

# Proves the file imports and works as a signing identity before anything is saved.
security create-keychain -p check "$WORK/check.keychain-db"
security import "$WORK/certificate.p12" -k "$WORK/check.keychain-db" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
security find-identity -p codesigning "$WORK/check.keychain-db" | grep -q "$NAME" || stop "The certificate didn't import."
security delete-keychain "$WORK/check.keychain-db"

P12="$(base64 -i "$WORK/certificate.p12")"
security add-generic-password -s "$NAME" -a certificate -w "$P12"
security add-generic-password -s "$NAME" -a password -w "$PASSWORD"
printf '%s' "$P12" | gh secret set SIGNING_CERTIFICATE_P12 -R "$REPOSITORY"
printf '%s' "$PASSWORD" | gh secret set SIGNING_CERTIFICATE_PASSWORD -R "$REPOSITORY"

FINGERPRINT="$("$OPENSSL" x509 -in "$WORK/certificate.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
echo "Done. Releases will be signed by \"$NAME\" (SHA-256 $FINGERPRINT)."
echo "Backup: Keychain Access, login keychain, items named \"$NAME\"."
