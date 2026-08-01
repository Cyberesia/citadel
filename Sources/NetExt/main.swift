import Foundation
import NetworkExtension

/// Citadel network system extension process entry point.
///
/// NetworkExtension loads `FilterDataProvider` from Info.plist; this bootstrap
/// only starts extension mode and keeps the process alive on the main run loop.
enum CitadelNetworkExtensionEntry {
    static func run() -> Never {
        autoreleasepool {
            NEProvider.startSystemExtensionMode()
        }
        dispatchMain()
    }
}

CitadelNetworkExtensionEntry.run()
