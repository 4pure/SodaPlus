// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "SodaPlus",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "SodaPlus", targets: ["SodaPlus"])
  ],
  targets: [
    .executableTarget(
      name: "SodaPlus",
      path: "Sources/SodaPlus"
    )
  ]
)
