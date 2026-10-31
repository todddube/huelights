// swift-tools-version: 6.0
//
// HueBar: a macOS menu bar app for discovering, pairing with and controlling Philips Hue
// bridges and lights. This manifest lets the app build with `swift build`/`swift run` and
// `make app`; `HueBar.xcodeproj` (generated from project.yml) builds the same sources in
// Xcode. The bridge client lives in the local `HueKit` package.
//

import PackageDescription

let package = Package(
    name: "HueBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "HueKit"),
    ],
    targets: [
        .executableTarget(
            name: "HueBar",
            dependencies: ["HueKit"],
            path: "HueBar",
            exclude: ["Info.plist", "Assets.xcassets"]
        ),
        .testTarget(
            name: "HueBarTests",
            dependencies: ["HueBar"],
            path: "HueBarTests"
        ),
    ]
)
