// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lada",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Lada", targets: ["Lada"])
    ],
    targets: [
        .executableTarget(
            name: "Lada",
            path: "Lada",
            exclude: [
                "Tests",
                "Resources/Info.plist",
                "Resources/Lada.entitlements",
                "Resources/AppIcon.icns"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "LadaTests",
            dependencies: ["Lada"],
            path: "Lada/Tests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
