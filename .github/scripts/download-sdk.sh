#!/usr/bin/env bash
# Downloads and extracts the Connect IQ SDK into ./ciq-sdk for CI builds.
#
# The SDK itself needs no Garmin login. Its download URL is resolved from
# the same public manifest the SDK Manager uses:
#
#   https://developer.garmin.com/downloads/connect-iq/sdks/sdks.json
#
# Each entry looks like {"version": "9.2.0", "linux": "connectiq-sdk-lin-
# 9.2.0-<date>-<hash>.zip", ...}; the zip lives next to the manifest under
# .../connect-iq/sdks/<filename>. Setting the repo variable CIQ_SDK_URL to a
# direct .zip link skips the manifest lookup entirely.
#
# Note the SDK zip does NOT include device definitions -- see
# download-devices.sh for those.
set -euo pipefail

: "${CIQ_SDK_VERSION:?CIQ_SDK_VERSION must be set}"

sdks_base="https://developer.garmin.com/downloads/connect-iq/sdks"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p ciq-sdk

if [ -n "${CIQ_SDK_URL:-}" ]; then
  url="$CIQ_SDK_URL"
else
  echo "Resolving Connect IQ SDK $CIQ_SDK_VERSION from $sdks_base/sdks.json"
  if ! curl -fsSL "$sdks_base/sdks.json" -o "$tmp/sdks.json"; then
    echo "ERROR: could not fetch $sdks_base/sdks.json." >&2
    exit 1
  fi
  if ! jq -e 'type == "array"' "$tmp/sdks.json" >/dev/null 2>&1; then
    echo "ERROR: $sdks_base/sdks.json is not a JSON array -- Garmin may have moved it. First 200 bytes:" >&2
    head -c 200 "$tmp/sdks.json" >&2
    echo >&2
    echo "Set the repo variable CIQ_SDK_URL to a direct .zip link to bypass the manifest." >&2
    exit 1
  fi
  file=$(jq -r --arg v "$CIQ_SDK_VERSION" \
    'first(.[] | select(.version == $v) | .linux // empty)' "$tmp/sdks.json")
  if [ -z "$file" ]; then
    echo "ERROR: no Linux build of Connect IQ SDK $CIQ_SDK_VERSION in $sdks_base/sdks.json." >&2
    echo "Available versions: $(jq -r '[.[].version] | join(", ")' "$tmp/sdks.json")" >&2
    exit 1
  fi
  url="$sdks_base/$file"
fi

echo "Downloading SDK from: $url"
curl -fsSL "$url" -o "$tmp/ciq-sdk.zip"
if ! unzip -tq "$tmp/ciq-sdk.zip" >/dev/null; then
  echo "ERROR: $url did not return a valid zip." >&2
  exit 1
fi
unzip -q "$tmp/ciq-sdk.zip" -d ciq-sdk

# Current SDK zips put bin/ at the root, but older ones wrapped everything in
# a single versioned folder (e.g. connectiq-sdk-lin-9.2.0-<hash>/) -- flatten
# that so ciq-sdk/bin/ is always the path callers use.
if [ ! -d ciq-sdk/bin ]; then
  inner=$(find ciq-sdk -mindepth 1 -maxdepth 1 -type d | head -1)
  if [ -n "$inner" ]; then
    mv "$inner"/* ciq-sdk/
    rmdir "$inner"
  fi
fi

chmod +x ciq-sdk/bin/monkeyc ciq-sdk/bin/monkeydo 2>/dev/null || true
if [ ! -f ciq-sdk/bin/monkeyc ]; then
  echo "ERROR: ciq-sdk/bin/monkeyc missing after extracting $url." >&2
  exit 1
fi
echo "SDK ready at ciq-sdk/ ($(cat ciq-sdk/bin/version.txt 2>/dev/null || echo unknown version))"
