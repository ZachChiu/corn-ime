#!/bin/bash
# 不用安裝，直接在終端機測試判斷邏輯
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc -O -module-name CornTest -target "$(uname -m)-apple-macos12.0" Sources/Engine/*.swift Tests/main.swift -o build/corntest
./build/corntest Resources
