// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TodusAuth",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "TodusAuth", targets: ["TodusAuth"]),
    ],
    targets: [
        .target(name: "TodusAuth"),
    ]
)
