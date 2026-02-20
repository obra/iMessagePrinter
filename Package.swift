// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "iMessagePrinter",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "iMessagePrinter",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/iMessagePrinter"
        )
    ]
)
