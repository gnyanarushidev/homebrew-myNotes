#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}"
build_root="$project_root/build"

xcodebuild \
  -project "$project_root/MyNotes.xcodeproj" \
  -scheme "MyNotes macOS" \
  -configuration Debug \
  -derivedDataPath "$build_root" \
  CODE_SIGNING_ALLOWED=NO \
  build

open "$build_root/Build/Products/Debug/MyNotes macOS.app"
