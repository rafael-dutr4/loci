// swift-tools-version: 6.2
import PackageDescription

// One target. Loci is a reader and a window: it reads the layout of the
// desktops from the system's own record of them, and draws it with my names on
// top. There is nothing here another program would want, so there is no library
// half.
let package = Package(
  name: "Loci",
  platforms: [.macOS("26.0")],
  targets: [
    .executableTarget(name: "Loci")
  ]
)
