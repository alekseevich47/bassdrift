#!/usr/bin/env bash
# Generate a local Android *debug* keystore for CI / sideload testing.
# Standard Android debug credentials (NOT for Play Store / production).
set -euo pipefail

OUT="${1:-android/ci/bass-drift-debug.keystore}"
ALIAS="${DEBUG_KEYSTORE_ALIAS:-androiddebugkey}"
STOREPASS="${DEBUG_KEYSTORE_PASS:-android}"
KEYPASS="${DEBUG_KEY_PASS:-android}"
DNAME="${DEBUG_KEYSTORE_DNAME:-CN=Bass Drift Debug,O=Bass Drift,C=US}"

mkdir -p "$(dirname "$OUT")"

if [ -f "$OUT" ]; then
  echo "Debug keystore already exists: $OUT"
  exit 0
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool not found; ensure a JDK is installed." >&2
  exit 1
fi

keytool -genkeypair \
  -v \
  -keystore "$OUT" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass "$STOREPASS" \
  -keypass "$KEYPASS" \
  -dname "$DNAME"

echo "Created debug keystore: $OUT"
echo "Alias: $ALIAS (password is the standard Android debug password — CI only)."
