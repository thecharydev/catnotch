#!/bin/sh
# Builds native/mac/build/DeskNotchHelper.app (universal, ad hoc signed).
set -e
cd "$(dirname "$0")/../native/mac"
APP=build/DeskNotchHelper.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" build/tmp
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13.0" main.swift -o "build/tmp/helper-$arch"
done
lipo -create build/tmp/helper-arm64 build/tmp/helper-x86_64 -output "$APP/Contents/MacOS/DeskNotchHelper"
cp Info.plist "$APP/Contents/Info.plist"
rm -rf build/tmp
codesign --force --sign - "$APP"

# MediaRemote adapter: the perl script plus its universal framework.
MR=native/mac/mediaremote-adapter
cd ../..
cmake -S "$MR" -B "$MR/build" -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 >/dev/null
cmake --build "$MR/build" >/dev/null
mkdir -p native/mac/build/mediaremote
cp "$MR/bin/mediaremote-adapter.pl" native/mac/build/mediaremote/
cp -R "$MR/build/MediaRemoteAdapter.framework" native/mac/build/mediaremote/
rm -rf "$MR/build"
