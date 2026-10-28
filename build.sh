#!/bin/sh
# Builds a Release ThReader.app into ./build. Pass --install to copy it to /Applications.
set -e
cd "$(dirname "$0")"
xcodebuild -scheme ThReader -configuration Release -derivedDataPath build/dd -quiet build $XCODEFLAGS  # e.g. XCODEFLAGS=CODE_SIGN_IDENTITY=- in CI
rm -rf build/ThReader.app
cp -R build/dd/Build/Products/Release/ThReader.app build/
if [ "$1" = "--install" ]; then
  rm -rf /Applications/ThReader.app
  cp -R build/ThReader.app /Applications/
  echo /Applications/ThReader.app
else
  echo "$PWD/build/ThReader.app"
fi
