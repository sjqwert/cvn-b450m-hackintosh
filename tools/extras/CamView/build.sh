#!/bin/bash
# 编译并打包为 摄像头预览.app
set -e
cd "$(dirname "$0")"
APP="../摄像头预览.app"

clang -fobjc-arc -O2 -Wno-deprecated-declarations \
  -o CamView.bin CamView.m \
  -framework Cocoa -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework QuartzCore

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp CamView.bin "$APP/Contents/MacOS/CamView"
chmod +x "$APP/Contents/MacOS/CamView"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  (ad-hoc 签名跳过)"
echo "✅ 已生成: $(cd .. && pwd)/摄像头预览.app"
