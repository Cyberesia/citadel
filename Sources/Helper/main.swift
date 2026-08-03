import Foundation

enum CitadelHelperEntry {
    static func run() -> Never {
        CitadelLog.info(CitadelLog.helper, "CitadelHelper starting v\(AppConstants.version) pid=\(getpid())")

        let listener = NSXPCListener(machServiceName: AppConstants.xpcMachServiceName)
        do {
            let service = try HelperService(listener: listener)
            service.start()
        } catch {
            CitadelLog.error(CitadelLog.helper, "service init failed: \(error)")
            exit(1)
        }

        dispatchMain()
    }
}

CitadelHelperEntry.run()
