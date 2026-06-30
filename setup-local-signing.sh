#!/usr/bin/env bash
# Create a stable self-signed code-signing identity for local VoiceInk builds.
# Signing with a STABLE identity (instead of ad-hoc) gives the app a constant
# TCC "designated requirement", so Accessibility/Microphone grants PERSIST across
# rebuilds — no more re-granting after every build.
#
# Uses a dedicated keychain with a known password + partition list so `codesign`
# never shows a GUI prompt. Idempotent: re-running recreates the identity.
set -euo pipefail

CERT_CN="VoiceInk Local Signing"
KEYCHAIN="$HOME/Library/Keychains/voiceink-local-signing.keychain-db"
KC_PASS="voiceink-local"
P12_PASS="VoiceInk"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo ">> generating self-signed code-signing cert"
cat > "$WORK/cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = VoiceInk Local Signing
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days 3650 -nodes -config "$WORK/cnf" >/dev/null 2>&1
# -legacy makes OpenSSL 3 write a PKCS#12 that macOS `security import` can read
LEGACY=""
openssl version 2>/dev/null | grep -q "OpenSSL 3" && LEGACY="-legacy"
openssl pkcs12 -export $LEGACY -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/id.p12" -passout "pass:$P12_PASS" -name "$CERT_CN" >/dev/null 2>&1

echo ">> (re)creating dedicated signing keychain"
security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"            # no auto-lock
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"

echo ">> importing identity"
security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$P12_PASS" -A \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo ">> allowing codesign to use the key without prompting"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null 2>&1

echo ">> adding keychain to the user search list"
EXISTING=$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')
# shellcheck disable=SC2086
security list-keychains -d user -s $EXISTING "$KEYCHAIN" >/dev/null

echo ">> available code-signing identities:"
security find-identity -v -p codesigning "$KEYCHAIN"
