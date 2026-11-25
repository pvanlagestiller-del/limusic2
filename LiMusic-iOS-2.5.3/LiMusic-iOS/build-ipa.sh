#!/bin/bash
# Baut eine unsignierte LiMusic.ipa für SideStore (SideStore signiert beim Installieren selbst).
# Voraussetzung: macOS mit Xcode 15 oder neuer.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
xcodebuild \
  -project LiMusic.xcodeproj \
  -scheme LiMusic \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP="build/dd/Build/Products/Release-iphoneos/LiMusic.app"
mkdir -p build/Payload
cp -R "$APP" build/Payload/
(cd build && zip -qry LiMusic.ipa Payload)

echo
echo "Fertig: $(pwd)/build/LiMusic.ipa"
echo "Diese Datei per AirDrop/Dateien aufs iPhone und in SideStore öffnen."
