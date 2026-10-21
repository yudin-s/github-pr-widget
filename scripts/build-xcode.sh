#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ]; then
  if [ -d "$HOME/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="$HOME/Applications/Xcode.app/Contents/Developer"
  elif [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi
if ! xcrun --find appintentsmetadataprocessor >/dev/null 2>&1; then
  echo 'Для интерактивного виджета нужен полный Xcode с appintentsmetadataprocessor. Command Line Tools недостаточно.' >&2
  exit 1
fi
xcodebuild -project GitHubPRWidget.xcodeproj -scheme GitHubPRWidget -configuration Release \
  -derivedDataPath build/xcode CODE_SIGNING_ALLOWED=NO build
APP='build/xcode/Build/Products/Release/GitHub PR.app'
python3 scripts/check-metadata.py "$APP"
codesign --force --sign - --entitlements Config/Widget.entitlements "$APP/Contents/PlugIns/PRWidget.appex"
codesign --force --sign - --entitlements Config/App.entitlements "$APP"
codesign --verify --deep --strict "$APP"
ditto "$APP" 'build/GitHub PR.app'
echo 'Built with Xcode and App Intents metadata: build/GitHub PR.app'
