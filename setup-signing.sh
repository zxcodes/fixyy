#!/bin/bash
# One-time: create a stable self-signed code-signing identity so the
# Accessibility grant survives rebuilds. Ad-hoc (`codesign -s -`) does not.
set -euo pipefail

KC="$HOME/Library/Keychains/fixyy-signing.keychain-db"
PW="fixyy-signing"
IDENTITY="Fixyy Self-Signed"

OPENSSL="/usr/bin/openssl"
BREW_SSL="$(brew --prefix 2>/dev/null)/bin/openssl"
[ -x "$BREW_SSL" ] && OPENSSL="$BREW_SSL"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cfg.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Fixyy Self-Signed
[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

echo "▶ Generating self-signed code-signing certificate…"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days 3650 -config "$WORK/cfg.cnf" -extensions v3 >/dev/null 2>&1

"$OPENSSL" pkcs12 -export -legacy -macalg SHA1 \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/fixyy.p12" -passout pass:"$PW" -name "$IDENTITY" >/dev/null 2>&1

echo "▶ Creating dedicated signing keychain…"
security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$PW" "$KC"
security set-keychain-settings "$KC"
security unlock-keychain -p "$PW" "$KC"

EXISTING=$(security list-keychains -d user | sed 's/[" ]//g')
# shellcheck disable=SC2086
security list-keychains -d user -s "$KC" $EXISTING

echo "▶ Importing identity and authorising codesign…"
security import "$WORK/fixyy.p12" -k "$KC" -P "$PW" -A -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KC" >/dev/null 2>&1

echo "✅ Identity available:"
security find-identity -p codesigning | grep -i "Fixyy" || security find-identity -p codesigning | tail -5
echo
echo "Rebuild with ./build.sh, then grant Accessibility to Fixyy."
