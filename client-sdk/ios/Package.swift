// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WebRTCKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "WebRTCKit",
            targets: ["WebRTCKit"]),
    ],
    dependencies: [
        // WebRTC dependency (will be provided via xcframework)
        // Firebase dependencies
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "11.0.0"),
    ],
    targets: [
        .target(
            name: "WebRTCKit",
            dependencies: [
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
            ],
            path: ".",
            exclude: ["WebRTCKitTests"],
            sources: [
                "WebRTCKit/Data",
                "WebRTCKit/Domain",
                "WebRTCKit/Presentation",
                "WebRTCKit/WebRTC",
                "WebRTCKit/DI"
            ],
            resources: [
                .process("Resources")
            ],
            cSettings: [
                .headerSearchPath("WebRTC.xcframework/ios-x86_64-simulator/WebRTC.framework/Headers"),
                .headerSearchPath("WebRTC.xcframework/ios-arm64/WebRTC.framework/Headers"),
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("GLKit"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("VideoToolbox"),
            ]
        ),
        .testTarget(
            name: "WebRTCKitTests",
            dependencies: ["WebRTCKit"],
            path: "WebRTCKitTests"
        ),
    ]
)
