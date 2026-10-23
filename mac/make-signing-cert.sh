#!/bin/sh
# One-time: creates the "PitchTap Self-Signed" code-signing certificate (valid 100 years), saves a
# password-protected .p12 backup, and imports it into the login keychain for build-app.sh.
# Keep the backup safe: a release signed with any other certificate can't auto-update existing users.
# Restore on a new Mac: security import <backup>.p12 -k login.keychain-db -T /usr/bin/codesign
set -e
NAME="PitchTap Self-Signed"
BACKUP_DIR="${BACKUP_DIR:-$HOME/Documents/pitchtap-signing}"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
P12="$BACKUP_DIR/pitchtap-self-signed.p12"

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
  echo "\"$NAME\" is already in the keychain; nothing to do." >&2
  exit 1
fi
[ -e "$P12" ] && { echo "$P12 already exists; move it first." >&2; exit 1; }

if [ -z "$P12_PASSWORD" ]; then
  printf "Password for the .p12 backup: "; stty -echo; read -r P12_PASSWORD; stty echo; echo
  printf "Again: "; stty -echo; read -r again; stty echo; echo
  [ "$P12_PASSWORD" = "$again" ] || { echo "Passwords don't match." >&2; exit 1; }
fi
[ -n "$P12_PASSWORD" ] || { echo "Empty password." >&2; exit 1; }

umask 077
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 36500 -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
# SHA1/3DES protection: the only kind macOS's `security import` reliably reads.
mkdir -p "$BACKUP_DIR"
P12_PASSWORD="$P12_PASSWORD" openssl pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 -passout env:P12_PASSWORD -out "$P12"
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null

security find-identity -p codesigning "$KEYCHAIN" | grep "\"$NAME\""
echo "Done. Backup: $P12 ($(openssl x509 -in "$WORK/cert.pem" -noout -enddate))"
echo "Copy the backup and its password somewhere safe (password manager, encrypted drive)."
