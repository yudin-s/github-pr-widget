#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -d "$HOME/Applications/Xcode.app/Contents/Developer" ] || [ -d /Applications/Xcode.app/Contents/Developer ] || xcrun --find appintentsmetadataprocessor >/dev/null 2>&1; then
  exec bash scripts/build-xcode.sh
fi
echo 'Warning: CLT preview build; widget buttons require full Xcode App Intents metadata.' >&2
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
APP="$PWD/build/GitHub PR.app"
EXT="$APP/Contents/PlugIns/PRWidget.appex"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS" "$EXT/Contents/Resources"
swiftc -swift-version 5 -parse-as-library -target arm64-apple-macosx14.0 -module-name GitHubPRWidget \
  Sources/PRCore/*.swift Sources/PRGitHub/*.swift Shared/*.swift App/*.swift \
  -o "$APP/Contents/MacOS/GitHubPRWidget"
swiftc -swift-version 5 -parse-as-library -target arm64-apple-macosx14.0 -module-name GitHubPRWidget \
  -application-extension -D WIDGET_EXTENSION Sources/PRCore/*.swift Shared/*.swift Widget/*.swift \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$EXT/Contents/MacOS/PRWidget"
python3 scripts/bundle.py "$APP"
codesign --force --sign - --entitlements Config/Widget.entitlements "$EXT"
codesign --force --sign - --entitlements Config/App.entitlements "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s\n' "$APP"
