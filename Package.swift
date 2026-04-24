// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TesterBuddy",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "TesterBuddy", targets: ["TesterBuddy"])
    ],
    targets: [
        .target(
            name: "TesterBuddy",
            path: "Sources/TesterBuddy"
        )
    ]
)
