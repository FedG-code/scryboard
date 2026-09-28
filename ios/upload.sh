#!/bin/zsh
# Archive and upload Scryboard to TestFlight without Xcode's account
# session, so it works with the Mac's screen locked (Apple ID sign-in
# needs an unlocked user session; an App Store Connect API key does not).
#
# Needs ios/Local.upload.env (gitignored) with:
#   ASC_KEY_ID=ABC123DEF4
#   ASC_ISSUER_ID=12345678-1234-1234-1234-123456789012
# and the key file at ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
# (or ASC_KEY_PATH in the env file pointing elsewhere). The .p8 is signing
# material: never in the repo. Key: App Store Connect › Users and Access ›
# Integrations › App Store Connect API › Team Keys, role **Admin**: the
# export signs with a cloud-managed distribution certificate, and only an
# Admin key may use those (an App Manager key archived fine and failed the
# export with "Cloud signing permission error" on 2026-09-28).
#
# Every run writes to a fresh directory under /tmp; nothing is deleted.
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f Local.upload.env ]]; then
  echo "ios/Local.upload.env is missing; see the comment at the top of $0" >&2
  exit 1
fi
source ./Local.upload.env
: "${ASC_KEY_ID:?ASC_KEY_ID missing from Local.upload.env}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID missing from Local.upload.env}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "API key not found at $ASC_KEY_PATH" >&2
  exit 1
fi

auth=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

run_dir="/tmp/scryboard-upload-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run_dir"
echo "Working in $run_dir"

xcodegen generate

xcodebuild archive \
  -project Scryboard.xcodeproj -scheme Scryboard -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$run_dir/Scryboard.xcarchive" \
  "${auth[@]}" \
  | tee "$run_dir/archive.log" | grep -E "error:|warning:|ARCHIVE" || true

if [[ ! -d "$run_dir/Scryboard.xcarchive" ]]; then
  echo "Archive failed; see $run_dir/archive.log" >&2
  exit 1
fi

xcodebuild -exportArchive \
  -archivePath "$run_dir/Scryboard.xcarchive" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "$run_dir/export" \
  "${auth[@]}" \
  | tee "$run_dir/export.log" | grep -E "error:|Upload|EXPORT" || true

if grep -q "EXPORT SUCCEEDED" "$run_dir/export.log"; then
  echo "Uploaded. Check the TestFlight tab in App Store Connect; the email is unreliable."
else
  echo "Export failed; see $run_dir/export.log" >&2
  exit 1
fi
