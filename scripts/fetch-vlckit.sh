#!/bin/sh
# Copyright (c) 2026 DouDuo contributors (https://github.com/81199000/DouDuo)
# License: MIT — see Licenses/DouDuo-MIT.txt.
# Copied verbatim from DouDuo scripts/fetch-vlckit.sh.
# 下载 VLCKit 二进制（MobileVLCKit 3.6.0，约 1GB，解压后放到 Vendor/VLCKit/）
set -e
cd "$(dirname "$0")/../Vendor/VLCKit"
[ -d VLCKit-all.xcframework ] && { echo "已存在 VLCKit-all.xcframework"; exit 0; }
URL=https://github.com/tylerjonesio/vlckit-spm/releases/download/3.6.0/VLCKit-all.xcframework.zip
SUM=5da4747e001900bbb4153f58db2be4695096c9c2350aea00376ad67b39c053f6
curl -L --fail -o vlckit.zip "$URL"
echo "$SUM  vlckit.zip" | shasum -a 256 -c -
unzip -q vlckit.zip && rm vlckit.zip
echo "✅ VLCKit 就绪"
