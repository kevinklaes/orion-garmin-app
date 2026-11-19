#!/usr/bin/env bash
# Downloads the Connect IQ device definitions for every product in
# manifest.xml into ~/.Garmin/ConnectIQ/Devices, where monkeyc looks for them
# on Linux. Without them monkeyc fails with "Invalid device id specified"
# (and monkey.jungle's per-device qualifiers fail to parse).
#
# Unlike the SDK, device files are only served to a logged-in Garmin account
# that has accepted the Connect IQ SDK agreement, so this uses
# lindell/connect-iq-sdk-manager-cli (pinned + checksum-verified below) and
# needs, in the repo's Settings -> Secrets and variables -> Actions:
#
#   secret   GARMIN_USERNAME     Garmin account email (the one the SDK
#                                Manager desktop app signs in with)
#   secret   GARMIN_PASSWORD     its password. The account must not require
#                                MFA -- the CLI can't answer an MFA prompt.
#   variable CIQ_AGREEMENT_HASH  hash of the SDK agreement you accepted. Get
#                                it locally by running
#                                `connect-iq-sdk-manager agreement view`
#                                and reading to the end. When Garmin changes
#                                the agreement, this step fails until you
#                                re-read it and update the hash.
set -euo pipefail

cli_version="0.8.4"
cli_sha256="5d57b8f9cfcd02d3b3f48e19d6daca0480e4c6f627926f15d8617ef8a6f57e0b"

missing=()
[ -n "${GARMIN_USERNAME:-}" ] || missing+=("secret GARMIN_USERNAME")
[ -n "${GARMIN_PASSWORD:-}" ] || missing+=("secret GARMIN_PASSWORD")
[ -n "${CIQ_AGREEMENT_HASH:-}" ] || missing+=("variable CIQ_AGREEMENT_HASH")
if [ ${#missing[@]} -gt 0 ]; then
  list=$(IFS=,; echo "${missing[*]}")
  echo "::error title=Connect IQ device download not configured::Missing ${list//,/, }. Device definitions need a Garmin login -- see .github/scripts/download-devices.sh for what to set."
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tarball="connect-iq-sdk-manager-cli_${cli_version}_Linux_x86_64.tar.gz"
curl -fsSL -o "$tmp/$tarball" \
  "https://github.com/lindell/connect-iq-sdk-manager-cli/releases/download/v${cli_version}/${tarball}"
echo "$cli_sha256  $tmp/$tarball" | sha256sum -c -
tar -xzf "$tmp/$tarball" -C "$tmp" connect-iq-sdk-manager
cli="$tmp/connect-iq-sdk-manager"

"$cli" agreement accept --agreement-hash="$CIQ_AGREEMENT_HASH"
"$cli" login
"$cli" device download --manifest=manifest.xml

devices_dir="$HOME/.Garmin/ConnectIQ/Devices"
expected=$(grep -c '<iq:product id=' manifest.xml)
got=$(find "$devices_dir" -mindepth 1 -maxdepth 1 -type d | wc -l)
echo "Downloaded $got device definitions into $devices_dir (manifest lists $expected)."
if [ "$got" -lt "$expected" ]; then
  echo "::error::Only $got of $expected manifest devices were downloaded."
  exit 1
fi
