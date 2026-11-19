#!/usr/bin/env bash
# Writes developer_key.der for monkeyc -y.
#
# With the GARMIN_DEVELOPER_KEY_BASE64 secret set (base64 of the same .der
# used for local builds, see docs/TESTING.md), builds are signed with the
# real key and the .iq artifact can be uploaded to the store. Without it --
# e.g. on fork PRs, which never see secrets -- this generates a throwaway
# key so CI still proves every device compiles; those artifacts are
# build-verification only and must not be published.
set -euo pipefail

if [ -n "${GARMIN_DEVELOPER_KEY_BASE64:-}" ]; then
  echo "$GARMIN_DEVELOPER_KEY_BASE64" | base64 -d > developer_key.der
else
  echo "::warning title=Unsigned build::GARMIN_DEVELOPER_KEY_BASE64 is not set -- signing with a throwaway key. Artifacts from this run are not publishable."
  openssl genrsa -out developer_key.pem 4096 2>/dev/null
  openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
  rm -f developer_key.pem
fi
