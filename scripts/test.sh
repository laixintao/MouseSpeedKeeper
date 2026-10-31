#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -D TESTING -parse-as-library -module-cache-path "$PWD/.build/module-cache" \
  Sources/MouseSpeed.swift Tests/ScrollModeTests.swift -o .build/scroll-mode-tests
.build/scroll-mode-tests
