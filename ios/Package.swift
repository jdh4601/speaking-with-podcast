// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PodcastStudyCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "PodcastStudyCore", targets: ["PodcastStudyCore"])],
    targets: [
        .target(name: "PodcastStudyCore", path: "PodcastStudy/Core"),
        .testTarget(name: "PodcastStudyCoreTests", dependencies: ["PodcastStudyCore"], path: "Tests/PodcastStudyCoreTests")
    ]
)
