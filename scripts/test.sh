#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swiftc -swift-version 5 -target arm64-apple-macosx14.0 Sources/PRCore/*.swift Sources/PRGitHub/*.swift Tests/CheckSupport.swift Tests/PRCoreTests/*.swift Tests/PRGitHubTests/*.swift Tests/Runner.swift -o .build/checks/core-tests
.build/checks/core-tests
