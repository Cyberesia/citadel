import Foundation

/// Polls macOS networking tools and publishes live connection + throughput events.
final class NetMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.citadel.firewall.netmon", qos: .utility)
    private var connectionTimer: DispatchSourceTimer?
    private var nettopProcess: Process?
    private let trafficSampler = NettopRateSampler()

    var onConnections: (([Connection]) -> Void)?
    var onSample: ((TrafficSample) -> Void)?
    var onProcessTraffic: (([ProcessTrafficSample]) -> Void)?

    func start() {
        stop()
        wireSamplerCallbacks()
        startConnectionPolling()
        startNettopStream()
    }

    func stop() {
        connectionTimer?.cancel()
        connectionTimer = nil

        nettopProcess?.terminate()
        nettopProcess = nil
    }

    // MARK: - Setup

    private func wireSamplerCallbacks() {
        trafficSampler.onAggregateSample = { [weak self] sample in
            self?.onSample?(sample)
        }
        trafficSampler.onProcessSamples = { [weak self] samples in
            self?.onProcessTraffic?(samples)
        }
    }

    // MARK: - Connection polling

    private func startConnectionPolling() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            let connections = LsofSocketScanner.scanConnections()
            self?.onConnections?(connections)
        }
        timer.resume()
        connectionTimer = timer
    }

    // MARK: - Throughput stream

    private func startNettopStream() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-x", "-L", "0", "-J", "bytes_in,bytes_out", "-s", "1"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            CitadelLog.error(CitadelLog.netmon, "nettop launch failed: \(error.localizedDescription)")
            return
        }

        nettopProcess = process
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.trafficSampler.ingest(chunk: text)
        }
    }
}
