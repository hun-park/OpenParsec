#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then
  echo "An iOS SDK and Xcode on macOS are required to build this app." >&2
  exit 1
fi
xcodebuild -version
git submodule update --init --recursive
mkdir -p build
xcodebuild archive \
  -project OpenParsec.xcodeproj -scheme OpenParsec \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -configuration Release -archivePath "$PWD/build/OpenParsec.xcarchive" \
  CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
package_dir="$(mktemp -d "$PWD/build/package.XXXXXX")"
mkdir -p "$package_dir/Payload"
cp -R build/OpenParsec.xcarchive/Products/Applications/OpenParsec.app "$package_dir/Payload/"
ipa="$PWD/build/OpenParsec-iPhone.ipa"
if [[ -e "$ipa" ]]; then
  echo "Output already exists: $ipa. Move it before rebuilding." >&2
  exit 1
fi
(cd "$package_dir" && /usr/bin/zip -qry "$ipa" Payload)
echo "Unsigned IPA ready for Sideloadly: $ipa"
