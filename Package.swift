// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FMRadio",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FMRadio", targets: ["FMRadio"])
    ],
    targets: [
        // IOUSBHost 컨트롤 전송용 얇은 Objective-C 래퍼 (Swift import 이름 불확실성 회피)
        .target(
            name: "CBesUSB",
            path: "Sources/CBesUSB",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("IOUSBHost"),
            ]
        ),
        .executableTarget(
            name: "FMRadio",
            dependencies: ["CBesUSB"],
            path: "Sources/FMRadio"
        ),
    ]
)
