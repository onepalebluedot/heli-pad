#!/bin/bash
# Archives the HeliPad scheme and uploads it to App Store Connect, where it
# reaches the TestFlight "Family" group once Apple finishes processing.
# Signs with the Apple account signed into Xcode (Settings > Accounts).
set -euo pipefail
cd "$(dirname "$0")/.."

# Apple rejects an upload that reuses a build number, so each run stamps one
# from the clock instead of relying on CURRENT_PROJECT_VERSION being bumped by
# hand. YYYYMMDD.HHMM, with the leading zero stripped from HHMM so both parts
# stay plain integers; the project file is left untouched.
build_number="$(date +%Y%m%d).$((10#$(date +%H%M)))"

if [[ -n "$(git status --porcelain -- HeliPad AssistantLab)" ]]; then
  echo "warning: uploading uncommitted changes; this build won't match any commit" >&2
fi

work_dir="build/testflight/$build_number"
mkdir -p "$work_dir"

echo "Archiving HeliPad build $build_number ($(git rev-parse --short HEAD))"
xcodebuild -project HeliPad/HeliPad.xcodeproj -scheme HeliPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$work_dir/HeliPad.xcarchive" \
  -allowProvisioningUpdates -quiet \
  CURRENT_PROJECT_VERSION="$build_number" archive

echo "Uploading to App Store Connect"
xcodebuild -exportArchive \
  -archivePath "$work_dir/HeliPad.xcarchive" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$work_dir/export" \
  -allowProvisioningUpdates

echo "Uploaded build $build_number. Apple processes it for 10-30 minutes before it appears in TestFlight."
