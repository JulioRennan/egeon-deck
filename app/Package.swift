// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EgeonDeck",
    // v14 é o piso do WKWebsiteDataStore(forIdentifier:), que é o que dá perfis
    // de navegação isolados e persistentes ao nó `web`.
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "EgeonDeck",
            dependencies: ["SwiftTerm"]
        )
    ]
)
