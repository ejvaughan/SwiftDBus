// swift-tools-version:3.1

import PackageDescription

let package = Package(
    name: "SwiftDbus",
    dependencies: [
        .Package(url: "../Clibdbus", majorVersion: 1)
    ]
)
