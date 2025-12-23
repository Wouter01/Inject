// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Inject",
    platforms: [
            .macOS(.v10_15),
            .iOS(.v12),
            .tvOS(.v13)
        ],
    products: [
        .library(
            name: "Inject",
            targets: ["Inject"]
        ),
    ],
    traits: [
        .trait(name: "HotReloadMacro"),
        .default(enabledTraits: []),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "601.0.0"..."602.0.0"),
    ],
    targets: [
        .target(
            name: "Inject",
            dependencies: [.targetItem(name: "HotReloadMacro", condition: .when(traits: ["HotReloadMacro"]))],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .macro(
            name: "HotReloadMacro",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax", condition: .when(traits: ["HotReloadMacro"])),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax", condition: .when(traits: ["HotReloadMacro"]))
            ],
        ),
    ]
)
