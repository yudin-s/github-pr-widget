// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "GitHubPRWidget", platforms: [.macOS(.v14)],
    products: [.library(name: "PRCore", targets: ["PRCore"]),
               .library(name: "PRGitHub", targets: ["PRGitHub"])],
    targets: [.target(name: "PRCore"), .target(name: "PRGitHub", dependencies: ["PRCore"])])
