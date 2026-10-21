#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache build/previews
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swiftc -parse-as-library -target arm64-apple-macosx14.0 -D WIDGET_EXTENSION Sources/PRCore/*.swift Shared/*.swift Widget/LocalIntents.swift Widget/PRWidgetView.swift Tools/RenderWidget.swift -o .build/render-widget
# Only fictional fixtures are rendered. The personal application cache is never read.
.build/render-widget Examples/widget.json "$PWD/build/previews/widget.png"
.build/render-widget Examples/hidden.json "$PWD/build/previews/hidden.png"
