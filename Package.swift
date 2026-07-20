// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SpineImageReplacer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SpineImageReplacer", targets: ["SpineImageReplacer"])
    ],
    targets: [
        .executableTarget(
            name: "SpineImageReplacer",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
