// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Resonance",
  platforms: [
    .iOS(.v15), .tvOS(.v15), .macOS(.v12),
  ],
  products: [
    // Products define the executables and libraries a package produces, and make them visible to other packages.
    .library(
      name: "Resonance",
      targets: ["Resonance"])
  ],
  dependencies: [
    // Dependencies declare other packages that this package depends on.
    .package(url: "https://github.com/apple/swift-collections.git", .upToNextMajor(from: "1.0.0")),
    .package(url: "https://github.com/apple/swift-atomics.git", .upToNextMajor(from: "1.2.0")),
    .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0")
  ],
  targets: [
    // Targets are the basic building blocks of a package. A target can define a module or a test suite.
    // Targets can depend on other targets in this package, and on products in packages this package depends on.
    .target(
      name: "Resonance",
      dependencies: [
        .product(name: "Collections", package: "swift-collections"),
        .product(name: "Atomics", package: "swift-atomics"),
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
      ],
      path: "Source",
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "ResonanceTests",
      dependencies: ["Resonance"],
      path: "Tests"
    )
  ],
  swiftLanguageModes: [.v6]
)
