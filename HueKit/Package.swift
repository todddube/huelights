// swift-tools-version: 6.0
//
// HueKit: the UI-free Hue bridge client (models, discovery, HTTPS, colour maths)
// shared by the HueBar app. Kept as its own package so it can be built and tested from
// the terminal without AppKit or SwiftUI.
//

import PackageDescription

let package = Package(
    name: "HueKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HueKit", targets: ["HueKit"]),
    ],
    targets: [
        .target(name: "HueKit"),
        .testTarget(name: "HueKitTests", dependencies: ["HueKit"]),
    ]
)
