// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Irnoti",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "Irnoti", targets: ["Irnoti"]),
        .library(name: "IrnotiExtension", targets: ["IrnotiExtension"]),
    ],
    targets: [
        // No Firebase dependency: the app passes the FCM token in (see README), which keeps the SDK small.
        .target(name: "Irnoti", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .target(name: "IrnotiExtension", dependencies: ["Irnoti"]),
    ]
)
