// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JarvisDashboard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "JarvisDashboard", targets: ["JarvisDashboard"])
    ],
    targets: [
        .executableTarget(
            name: "JarvisDashboard",
            path: "Sources/JarvisDashboard",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(
            name: "JarvisDashboardTests",
            dependencies: ["JarvisDashboard"],
            path: "Tests/JarvisDashboardTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
