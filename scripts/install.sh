#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$HOME/Applications/GitHub PR.app"
if pgrep -x GitHubPRWidget >/dev/null; then
  echo 'Завершите GitHub PR через меню приложения перед обновлением.' >&2
  exit 1
fi
if [ -e "$APP" ]; then
  identifier=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")
  if [ "$identifier" != local.GitHubPRWidget ]; then
    echo 'В папке установки находится другое приложение. Оно не будет заменено.' >&2
    exit 1
  fi
fi
codesign --verify --deep --strict 'build/GitHub PR.app'
mkdir -p "$HOME/Applications"
ditto 'build/GitHub PR.app' "$APP"
codesign --verify --deep --strict "$APP"
pluginkit -a "$APP/Contents/PlugIns/PRWidget.appex"
printf 'Installed: %s\n' "$APP"
