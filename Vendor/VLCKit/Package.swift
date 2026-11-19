// swift-tools-version: 5.7
// Copyright (c) 2026 DouDuo contributors (https://github.com/81199000/DouDuo)
// License: MIT — see Licenses/DouDuo-MIT.txt.
// Copied verbatim from DouDuo Vendor/VLCKit/Package.swift.
// The binary itself (MobileVLCKit, VideoLAN) is LGPL-2.1-or-later — see THIRD_PARTY_NOTICES.md.
import PackageDescription

// VLCKit（MobileVLCKit 3.6.0，来自 tylerjonesio/vlckit-spm）。
// 二进制太大（约 1GB）不进 git：首次编译前跑 `./scripts/fetch-vlckit.sh` 下载到本目录。
let package = Package(
    name: "VLCKit",
    platforms: [.iOS(.v11)],
    products: [.library(name: "VLCKitSPM", targets: ["VLCKitSPM"])],
    targets: [
        .binaryTarget(name: "VLCKit-all", path: "VLCKit-all.xcframework"),
        .target(
            name: "VLCKitSPM",
            dependencies: [.target(name: "VLCKit-all")],
            linkerSettings: [
                .linkedFramework("QuartzCore"), .linkedFramework("CoreText"), .linkedFramework("AVFoundation"),
                .linkedFramework("Security"), .linkedFramework("CFNetwork"), .linkedFramework("AudioToolbox"),
                .linkedFramework("OpenGLES"), .linkedFramework("CoreGraphics"), .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"), .linkedLibrary("c++"), .linkedLibrary("xml2"), .linkedLibrary("z"),
                .linkedLibrary("bz2"), .linkedLibrary("iconv"),
            ]),
    ]
)
