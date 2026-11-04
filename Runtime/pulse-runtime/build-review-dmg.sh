#!/bin/bash
# Build a local, unsigned review image. The customer export requires Developer ID signing.
set -euo pipefail
if [[ ( $# != 2 && $# != 3 ) || -e "$2" ]]; then
  echo "Usage: build-review-dmg.sh /absolute/python-archive.tar.zst /new/output.dmg [signing-identity]" >&2
  exit 2
fi
here=$(cd "$(dirname "$0")" && pwd)
app_source="$here/../.."
stage=$(mktemp -d)
export BAMBOO_PULSE_BUILD_ROOT="${BAMBOO_PULSE_BUILD_ROOT:-$stage/build}"
"$app_source/script/build_and_run.sh" --live --release --build-only
mkdir "$stage/image"
app="$stage/image/Bamboo Pulse.app"
ditto "$BAMBOO_PULSE_BUILD_ROOT/Build/Products/Release/Bamboo Pulse.app" "$app"
python3 "$here/package.py" --python-archive "$1" --output "$app/Contents/Resources/PulseRuntime"
if [[ $# == 3 ]]; then
  python3 "$here/sign_review.py" "$app" "$3"
fi
ln -s /Applications "$stage/image/Applications"
hdiutil create -volname "Bamboo Pulse Review" -srcfolder "$stage/image" -format UDZO -o "$2"
hdiutil verify "$2"
shasum -a 256 "$2"
