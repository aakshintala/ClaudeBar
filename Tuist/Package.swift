// swift-tools-version: 6.0
import PackageDescription


#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    // Customize the product types for specific package product
    // Default is .staticFramework
    targetSettings: [
        "IssueReporting": ["SWIFT_PACKAGE_NAME": "xctest-dynamic-overlay"],
        "IssueReportingPackageSupport": ["SWIFT_PACKAGE_NAME": "xctest-dynamic-overlay"],
    ]
)
#endif

let package = Package(
    name: "ClaudeBar",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/Kolos65/Mockable.git", from: "0.5.0"),
        // Exposes MenuBarExtra's underlying NSStatusItem so the menu-bar label
        // can be driven imperatively (AppKit), surviving the SwiftUI label
        // freeze after system sleep (issue #192).
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.3.0"),
    ]
)
