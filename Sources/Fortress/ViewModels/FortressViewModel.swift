import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
final class FortressViewModel: ObservableObject {
    // MARK: - Published UI state

    @Published var focus: MonitorFocus = .all
    @Published var tree: [ProcessFamilyNode] = []
    @Published var streams: [NetworkStream] = []
    @Published var arcs: [FortressFlowArc] = []
    @Published var options = MonitorViewOptions.default
    @Published var mapProjection: FortressMapProjection = .globe
    @Published var mapOrigin = FortressGeoPoint.defaultOrigin
    @Published var currentIn: Int64 = 0
    @Published var currentOut: Int64 = 0
    @Published var machineSparkline: [Int64] = []
    @Published var topDomains: [FortressRollup] = []
    @Published var topCountries: [FortressRollup] = []
    @Published var topFamilies: [FortressRollup] = []
    @Published var topDestinations: [FortressRollup] = []
    @Published var isRunning = false
    @Published var isDemoMode = false
    @Published var helperConnected = false
    @Published var logs: [(Date, String, String)] = []
    @Published var selectedStreamID: String?
    @Published var suspectFindings: [SuspectFinding] = []

    let bridge = FortressFirewallBridge()
    private let hub = TrafficTelemetryHub()
    private let suspectEngine = SuspectEngine()
    private var eventTask: Task<Void, Never>?
    private var geoTask: Task<Void, Never>?
    private var originTask: Task<Void, Never>?
    private var bridgeCancellable: AnyCancellable?

    var pendingAlerts: [FortressAlert] { bridge.pendingAlerts }
    var mode: AppMode { bridge.mode }

    init() {
        bridge.viewModel = self
        bridgeCancellable = bridge.$connected
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.helperConnected = value
            }
        bridge.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bridgeSubscriptions)
        bridge.$rules
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bridgeSubscriptions)
    }

    private var bridgeSubscriptions = Set<AnyCancellable>()

    /// Wire firewall actions through AppState (SharedRuleBridge + helper).
    func bind(appState: AppState) {
        bridge.bind(to: appState)
        bridge.connect()
        helperConnected = appState.helperConnected
        appState.adoptFortressTelemetry()
        menubarSink = appState
    }

    private weak var menubarSink: AppState?

    /// Mirror Fortress rates + families into AppState for menubar / popover.
    private func publishMenubarTelemetry() {
        guard let sink = menubarSink else { return }
        var byFamily: [String: (name: String, rateIn: Int64, rateOut: Int64, bytesIn: Int64, bytesOut: Int64, count: Int, path: String, bundle: String?)] = [:]
        for s in streams {
            let key = s.process.familyID
            var entry = byFamily[key] ?? (
                s.process.familyName,
                0, 0, 0, 0, 0,
                s.process.path,
                s.process.bundleID
            )
            entry.rateIn += s.rateIn
            entry.rateOut += s.rateOut
            entry.bytesIn += s.bytesIn
            entry.bytesOut += s.bytesOut
            entry.count += 1
            byFamily[key] = entry
        }
        let processes: [AppState.ProcessStats] = byFamily.map { key, v in
            AppState.ProcessStats(
                id: key,
                name: v.name,
                bytesIn: v.bytesIn,
                bytesOut: v.bytesOut,
                bytesInRate: v.rateIn,
                bytesOutRate: v.rateOut,
                icon: AppIcon.resolve(bundleId: v.bundle, path: v.path, name: v.name),
                connectionCount: v.count
            )
        }
        .sorted { $0.rateTotal != $1.rateTotal ? $0.rateTotal > $1.rateTotal : $0.connectionCount > $1.connectionCount }
        .prefix(20)
        .map { $0 }

        sink.applyFortressTelemetry(
            rateIn: currentIn,
            rateOut: currentOut,
            processes: processes
        )
    }

    // MARK: - Lifecycle

    func onAppear() {
        bridge.connect()
        // Engine is started at app launch; only start here if still idle.
        if !isRunning, !isDemoMode {
            startEngine()
        }
    }

    func onDisappear() {
        // Keep telemetry running while the app is alive — Activity may be revisited.
    }

    func startEngine() {
        guard !isRunning, !isDemoMode else { return }
        isRunning = true
        hub.start()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.hub.events {
                guard !Task.isCancelled else { break }
                await self.handle(event)
            }
        }
        geoTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.enrichGeo()
                await self?.enrichHosts()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
        originTask = Task { [weak self] in
            if let loc = await GeoResolver.shared.lookupSelf(),
               let lat = loc.latitude, let lon = loc.longitude {
                await MainActor.run {
                    self?.mapOrigin = FortressGeoPoint(latitude: lat, longitude: lon)
                }
            }
        }
        rebuildPresentation()
    }

    func stopEngine() {
        isRunning = false
        eventTask?.cancel()
        eventTask = nil
        geoTask?.cancel()
        geoTask = nil
        originTask?.cancel()
        originTask = nil
        hub.stop()
    }

    func loadDemo() {
        stopEngine()
        isDemoMode = true
        FortressDemoData.load(into: self)
        rebuildPresentation()
    }

    /// Leave demo and resume live Fortress telemetry.
    func exitDemo() {
        guard isDemoMode else { return }
        isDemoMode = false
        streams = []
        arcs = []
        tree = []
        topDomains = []
        topCountries = []
        topFamilies = []
        topDestinations = []
        currentIn = 0
        currentOut = 0
        machineSparkline = []
        focus = .all
        selectedStreamID = nil
        startEngine()
    }

    // MARK: - Focus / options

    func setFocus(_ newFocus: MonitorFocus) {
        focus = newFocus
        if case .stream(let id) = newFocus {
            selectedStreamID = id
        } else {
            selectedStreamID = nil
        }
        rebuildRollups()
        rebuildArcs()
    }

    func popFocus() {
        switch focus {
        case .all:
            break
        case .family:
            focus = .all
        case .role(let familyID, _), .host(let familyID, _):
            focus = .family(familyID)
        case .stream(let id):
            if let stream = streams.first(where: { $0.id == id }) {
                focus = .host(familyID: stream.process.familyID, hostKey: stream.remoteKey)
            } else {
                focus = .all
            }
            selectedStreamID = nil
        }
        rebuildRollups()
        rebuildArcs()
    }

    func selectNode(_ node: ProcessFamilyNode) {
        switch node.kind {
        case .family, .sites:
            if let fid = node.familyID { setFocus(.family(fid)) }
        case .roleGroup(let role):
            if let fid = node.familyID { setFocus(.role(familyID: fid, role: role)) }
        case .process:
            if let fid = node.familyID { setFocus(.family(fid)) }
        case .host:
            if let fid = node.familyID, let host = node.hostKey {
                setFocus(.host(familyID: fid, hostKey: host))
            }
        case .stream:
            if let sid = node.streamID {
                selectedStreamID = sid
                setFocus(.stream(id: sid))
            }
        }
    }

    func updateOptions(_ mutate: (inout MonitorViewOptions) -> Void) {
        mutate(&options)
        rebuildTree()
    }

    // MARK: - Firewall actions

    func setMode(_ m: AppMode) { bridge.setMode(m) }

    func allowStream(_ stream: NetworkStream, remember: Bool) {
        bridge.allow(stream: stream, remember: remember)
        refreshSuspects()
    }

    func denyStream(_ stream: NetworkStream, remember: Bool) {
        bridge.deny(stream: stream, remember: remember)
        refreshSuspects()
    }

    func refreshSuspects() {
        suspectFindings = suspectEngine.evaluate(
            streams: streams,
            rules: bridge.rules,
            store: menubarSink?.store,
            blocklistDomains: []
        )
    }

    func allowSuspect(_ finding: SuspectFinding) {
        guard let stream = stream(for: finding.streamID) else { return }
        allowStream(stream, remember: true)
    }

    func denySuspect(_ finding: SuspectFinding) {
        guard let stream = stream(for: finding.streamID) else { return }
        denyStream(stream, remember: true)
    }

    func focusSuspect(_ finding: SuspectFinding) {
        selectedStreamID = finding.streamID
        setFocus(.stream(id: finding.streamID))
    }

    func resolveAlert(_ alert: FortressAlert, allow: Bool, remember: Bool) {
        bridge.resolveAlert(alert, allow: allow, remember: remember)
    }

    func appendLog(level: String, message: String) {
        logs.append((Date(), level, message))
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }

    func stream(for id: String) -> NetworkStream? {
        streams.first { $0.id == id } ?? hub.index.stream(id: id)
    }

    func sparkline(forFamily id: String) -> [Int64] {
        hub.index.sparkline(forFamily: id)
    }

    func sparkline(forStream id: String) -> [Int64] {
        hub.index.sparkline(forStream: id)
    }

    func copyDetails(for stream: NetworkStream) {
        let text = """
        Process: \(stream.process.name) (PID \(stream.process.pid))
        Family: \(stream.process.familyName)
        Bundle: \(stream.process.bundleID ?? "—")
        Path: \(stream.process.path)
        Remote: \(stream.remoteHost.isEmpty ? stream.remoteIP : stream.remoteHost):\(stream.remotePort)
        Protocol: \(stream.protocolName)
        Status: \(stream.status.rawValue)
        Rate: ↓\(FortressFormat.bytesPerSec(stream.rateIn)) ↑\(FortressFormat.bytesPerSec(stream.rateOut))
        Geo: \(stream.geo?.displayLabel ?? "—")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Events

    private func handle(_ event: TelemetryEvent) async {
        switch event {
        case .streamsChanged:
            rebuildPresentation()
        case .machineRate(let rate):
            currentIn = rate.bytesIn
            currentOut = rate.bytesOut
            machineSparkline = hub.index.machineSparklineValues()
            publishMenubarTelemetry()
        case .processRates:
            rebuildPresentation()
        }
    }

    private func enrichGeo() async {
        guard !isDemoMode else { return }
        let ips = Array(Set(hub.index.allStreams.map(\.remoteIP).filter { GeoResolver.isPublicIP($0) }))
        let resolved = await GeoResolver.shared.lookupBatch(ips)
        guard !resolved.isEmpty else { return }
        hub.applyGeo(resolved)
        // Promote PTR from geo into remoteHost even when system reverse-DNS failed.
        var fromReverse: [String: String] = [:]
        for (ip, geo) in resolved {
            if let reverse = geo.reverseHost, !reverse.isEmpty {
                fromReverse[ip] = reverse
            }
        }
        if !fromReverse.isEmpty {
            hub.applyRemoteHosts(fromReverse)
        }
        rebuildPresentation()
    }

    private func enrichHosts() async {
        guard !isDemoMode else { return }
        let publicIPs = Array(Set(hub.index.allStreams.compactMap { stream -> String? in
            let ip = stream.remoteIP
            guard GeoResolver.isPublicIP(ip) else { return nil }
            if !stream.remoteHost.isEmpty, !NetworkStream.looksLikeIP(stream.remoteHost) {
                return nil
            }
            return ip
        }))
        guard !publicIPs.isEmpty else { return }

        // Prefer real DNS query names (helper) over PTR.
        var merged = SharedDNSNameBridge.hosts(forIPs: publicIPs)
        let stillNeed = publicIPs.filter { merged[$0] == nil }
        let fromPTR = await RemoteHostResolver.shared.lookupBatch(stillNeed)
        for (ip, host) in fromPTR { merged[ip] = host }

        guard !merged.isEmpty else { return }
        hub.applyRemoteHosts(merged)
        rebuildPresentation()
    }

    func rebuildPresentation() {
        if !isDemoMode {
            streams = hub.index.allStreams
        }
        rebuildTree()
        rebuildRollups()
        rebuildArcs()
        publishMenubarTelemetry()
        refreshSuspects()
        persistHistorySnapshot()
    }

    private func persistHistorySnapshot() {
        guard let sink = menubarSink, !isDemoMode else { return }
        for stream in streams.prefix(40) {
            let c = Connection(
                pid: stream.process.pid,
                processName: stream.process.name,
                processPath: stream.process.path,
                processBundleId: stream.process.bundleID,
                codeTeamID: stream.process.codeTeamID,
                signingStatus: stream.process.signingStatus,
                remoteHost: stream.remoteHost,
                remoteIP: stream.remoteIP,
                remotePort: stream.remotePort,
                status: stream.status == .denied ? .denied : .established,
                protocolName: stream.protocolName,
                bytesIn: stream.bytesIn,
                bytesOut: stream.bytesOut,
                country: stream.geo?.country,
                countryCode: stream.geo?.countryCode,
                city: stream.geo?.city,
                firstSeen: stream.firstSeen,
                lastSeen: stream.lastSeen
            )
            sink.recordHistoryConnection(c)
        }
    }

    private func rebuildTree() {
        tree = ProcessGrouper.buildTree(streams: streams, options: options)
    }

    private func rebuildRollups() {
        var domains: [String: (rate: Int64, bytes: Int64, count: Int)] = [:]
        var countries: [String: (label: String, rate: Int64, bytes: Int64, count: Int)] = [:]
        var families: [String: (label: String, rate: Int64, bytes: Int64, count: Int)] = [:]
        var destinations: [String: (label: String, rate: Int64, bytes: Int64, count: Int, sampleID: String)] = [:]

        for s in focusedStreams() {
            let dom = s.remoteKey.isEmpty ? s.remoteDisplayName : s.remoteKey
            var d = domains[dom] ?? (0, 0, 0)
            d.rate += s.rateTotal
            d.bytes += s.bytesTotal
            d.count += 1
            domains[dom] = d

            if let geo = s.geo, let code = geo.countryCode {
                var c = countries[code] ?? (geo.country ?? code, 0, 0, 0)
                c.rate += s.rateTotal
                c.bytes += s.bytesTotal
                c.count += 1
                countries[code] = c
            }

            var f = families[s.process.familyID] ?? (s.process.familyName, 0, 0, 0)
            f.rate += s.rateTotal
            f.bytes += s.bytesTotal
            f.count += 1
            families[s.process.familyID] = f

            // Aggregate by city/country so Ashburn isn't listed 40 times.
            let destKey: String
            let destLabel: String
            if let geo = s.geo {
                destKey = geo.displayLabel
                destLabel = geo.displayLabel
            } else {
                destKey = s.remoteKey
                destLabel = s.remoteDisplayName
            }
            var dest = destinations[destKey] ?? (destLabel, 0, 0, 0, s.id)
            dest.rate += s.rateTotal
            dest.bytes += s.bytesTotal
            dest.count += 1
            destinations[destKey] = dest
        }

        topDomains = domains.map { key, value in
            let label = streams.first { $0.remoteKey == key }?.remoteDisplayName ?? key
            return FortressRollup(
                id: key,
                label: label,
                rateTotal: value.rate,
                bytesTotal: value.bytes,
                connectionCount: value.count
            )
        }.sorted { $0.rateTotal != $1.rateTotal ? $0.rateTotal > $1.rateTotal : $0.connectionCount > $1.connectionCount }
         .prefix(12).map { $0 }

        topCountries = countries.map {
            FortressRollup(id: $0.key, label: $0.value.label, rateTotal: $0.value.rate, bytesTotal: $0.value.bytes, connectionCount: $0.value.count)
        }.sorted { $0.connectionCount > $1.connectionCount }.prefix(8).map { $0 }

        topFamilies = families.map {
            FortressRollup(id: $0.key, label: $0.value.label, rateTotal: $0.value.rate, bytesTotal: $0.value.bytes, connectionCount: $0.value.count)
        }.sorted { $0.rateTotal > $1.rateTotal }.prefix(8).map { $0 }

        topDestinations = destinations.map {
            FortressRollup(
                id: $0.value.sampleID,
                label: $0.value.label,
                rateTotal: $0.value.rate,
                bytesTotal: $0.value.bytes,
                connectionCount: $0.value.count
            )
        }.sorted { $0.rateTotal > $1.rateTotal }.prefix(8).map { $0 }
    }

    func focusedStreams() -> [NetworkStream] {
        switch focus {
        case .all:
            return streams
        case .family(let id):
            return streams.filter { $0.process.familyID == id }
        case .role(let familyID, let role):
            return streams.filter { $0.process.familyID == familyID && $0.process.role == role }
        case .host(let familyID, let hostKey):
            return streams.filter { $0.process.familyID == familyID && $0.remoteKey == hostKey }
        case .stream(let id):
            return streams.filter { $0.id == id }
        }
    }

    private func rebuildArcs() {
        // Map needs lat/lon; private / VPN peers never geolocate. If the current
        // focus is only those, widen to family then all so the globe isn't blank.
        var source = focusedStreams()
        var built = FortressFlowArcBuilder.build(
            from: source,
            origin: mapOrigin,
            highlightStreamID: selectedStreamID
        )
        if built.isEmpty {
            switch focus {
            case .stream(let id):
                if let familyID = streams.first(where: { $0.id == id })?.process.familyID {
                    source = streams.filter { $0.process.familyID == familyID }
                    built = FortressFlowArcBuilder.build(
                        from: source,
                        origin: mapOrigin,
                        highlightStreamID: selectedStreamID
                    )
                }
            case .host(let familyID, _), .role(let familyID, _):
                source = streams.filter { $0.process.familyID == familyID }
                built = FortressFlowArcBuilder.build(
                    from: source,
                    origin: mapOrigin,
                    highlightStreamID: selectedStreamID
                )
            case .family, .all:
                break
            }
        }
        if built.isEmpty, focus != .all {
            built = FortressFlowArcBuilder.build(
                from: streams,
                origin: mapOrigin,
                highlightStreamID: selectedStreamID
            )
        }
        arcs = built
    }

    /// Inject demo streams without going through the hub.
    func applyDemoStreams(_ demo: [NetworkStream], rateIn: Int64, rateOut: Int64) {
        streams = demo
        currentIn = rateIn
        currentOut = rateOut
    }
}
