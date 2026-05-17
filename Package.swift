// swift-tools-version: 5.10
import PackageDescription

var products: [Product] = [
    .library(name: "DexCleanerCore", targets: ["DexCleanerCore"])
]

var targets: [Target] = [
    .target(
        name: "DexCleanerCore",
        path: "Sources/DexCleanerCore",
        resources: [
            .process("Resources")
        ]
    ),
    .testTarget(
        name: "DexCleanerTests",
        dependencies: ["DexCleanerCore"],
        path: "Tests/DexCleanerTests"
    )
]

#if os(macOS)
products.append(.executable(name: "DexCleaner", targets: ["DexCleaner"]))
targets.append(
    .executableTarget(
        name: "DexCleaner",
        dependencies: ["DexCleanerCore"],
        path: "Sources/DexCleaner"
    )
)
#endif

let package = Package(
    name: "DexCleaner",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
