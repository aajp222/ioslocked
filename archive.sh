#!/usr/bin/env bash
# Archive Locked and (optionally) upload it to App Store Connect for TestFlight.
#
#   ios/archive.sh                 # archive + export a signed .ipa
#   ios/archive.sh --upload        # ...and upload it
#
# Uploading needs an App Store Connect API key. Create one at
# App Store Connect › Users and Access › Integrations › App Store Connect API,
# download the .p8 once, then either put it in ~/.appstoreconnect/private_keys/
# (named AuthKey_<KEYID>.p8) or export the three variables below.
#
# The Key ID is already set below. You still need the Issuer ID once:
#   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# Each upload needs a build number App Store Connect hasn't seen. This script
# bumps it from the current time, so you never fight that error.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

build_number="$(date +%Y%m%d%H%M)"
archive="build/Locked.xcarchive"
export_dir="build/export"

echo "==> Regenerating the project"
xcodegen generate >/dev/null

echo "==> Archiving (Release, build $build_number)"
rm -rf "$archive" "$export_dir"
xcodebuild archive \
  -project Locked.xcodeproj \
  -scheme Locked \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$build_number" \
  | grep -E "error:|warning: [A-Z]|Signing Identity|BUILD" || true

if [ ! -d "$archive" ]; then
  echo "!! Archive failed — see the output above." >&2
  exit 1
fi

echo "==> Exporting a signed .ipa"
xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "$export_dir" \
  -allowProvisioningUpdates \
  | grep -E "error:|EXPORT" || true

ipa="$(find "$export_dir" -name '*.ipa' | head -1)"
if [ -z "$ipa" ]; then
  echo "!! No .ipa produced. Most likely cause: the Family Controls entitlement" >&2
  echo "   is still in the Release entitlements but not yet approved for" >&2
  echo "   distribution. See Locked/Locked-Distribution.entitlements." >&2
  exit 1
fi
echo "    $ipa"

if [ "${1:-}" != "--upload" ]; then
  echo
  echo "Done. To upload:  ios/archive.sh --upload"
  exit 0
fi

echo "==> Validating with App Store Connect"
# The key lives in ~/.appstoreconnect/private_keys/AuthKey_S5F9N4N895.p8
: "${ASC_KEY_ID:=S5F9N4N895}"

auth=()
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
  auth=(--apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID")
else
  echo "    (no ASC_KEY_ID/ASC_ISSUER_ID — xcrun will look for a key in"
  echo "     ~/.appstoreconnect/private_keys/ or prompt for an Apple ID)"
fi

xcrun altool --validate-app -f "$ipa" -t ios "${auth[@]}"
echo "==> Uploading"
xcrun altool --upload-app -f "$ipa" -t ios "${auth[@]}"

echo
echo "Uploaded build $build_number. It appears in TestFlight after Apple finishes"
echo "processing (usually 5-15 minutes), then you can add it to a tester group."
