#!/usr/bin/env bash
# Downloads and extracts the Connect IQ SDK into ./ciq-sdk for CI builds.
#
# Garmin doesn't publish a stable, documented API for this -- the SDK
# Manager desktop app resolves download URLs from an internal manifest
# whose schema isn't guaranteed. Two ways to point this script at a build:
#
#   1. (Preferred, reliable) Set the repo variable CIQ_SDK_URL to a direct
#      .zip download link for CIQ_SDK_VERSION's Linux SDK build. Get this
#      once by installing the SDK Manager locally, downloading the target
#      version, and checking its own download logs/cache for the URL it
#      used (or inspect network traffic while it downloads).
#   2. (Fallback, unverified) This script tries Garmin's SDK Manager
#      manifest at the URL below and greps out a matching entry. This has
#      NOT been validated against GitHub's runners -- if it fails, the
#      error message below tells you to set CIQ_SDK_URL instead.
set -euo pipefail

mkdir -p ciq-sdk

if [ -n "${CIQ_SDK_URL:-}" ]; then
  url="$CIQ_SDK_URL"
else
  echo "CIQ_SDK_URL not set -- attempting to resolve version $CIQ_SDK_VERSION from Garmin's SDK manifest (unverified path, see script comments)."
  curl -sL "https://developer.garmin.com/downloads/connect-iq/sdk-manager/sdks.json" -o /tmp/sdks.json
  url=$(jq -r --arg v "$CIQ_SDK_VERSION" \
    '.[] | select(.version == $v and (.platform // "" | test("linux"; "i"))) | .url' \
    /tmp/sdks.json | head -1)
fi

if [ -z "${url:-}" ] || [ "$url" = "null" ]; then
  echo "ERROR: could not resolve a Connect IQ SDK $CIQ_SDK_VERSION download URL." >&2
  echo "Set the repo variable CIQ_SDK_URL to a direct .zip link (Settings -> Secrets and variables -> Actions -> Variables)." >&2
  exit 1
fi

echo "Downloading SDK from: $url"
curl -sL "$url" -o /tmp/ciq-sdk.zip
unzip -q /tmp/ciq-sdk.zip -d ciq-sdk
rm -f /tmp/ciq-sdk.zip

# The zip typically contains a single versioned top-level folder
# (e.g. connectiq-sdk-lin-9.2.0-<hash>/) -- flatten it so ciq-sdk/bin/
# is always the path callers use, regardless of that folder's exact name.
inner=$(find ciq-sdk -mindepth 1 -maxdepth 1 -type d | head -1)
if [ -n "$inner" ] && [ ! -d ciq-sdk/bin ]; then
  mv "$inner"/* ciq-sdk/
  rmdir "$inner"
fi

chmod +x ciq-sdk/bin/monkeyc ciq-sdk/bin/monkeydo 2>/dev/null || true
echo "SDK ready at ciq-sdk/"
