#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/test.sh
bash scripts/build.sh
codesign --verify --deep --strict 'build/GitHub PR.app'
python3 scripts/check-metadata.py 'build/GitHub PR.app'
echo 'Swift checks and native bundle verification passed. Notification Center UI must also be verified on the installed app.'
