import Foundation

/// Builds a hierarchical process tree from flat streams.
public enum ProcessGrouper {
    public static func buildTree(
        streams: [NetworkStream],
        options: MonitorViewOptions
    ) -> [ProcessFamilyNode] {
        var filtered = streams

        if options.hideSystem {
            filtered = filtered.filter { !ProcessIdentityResolver.isSystemProcess(path: $0.process.path) }
        }
        if options.activeOnly {
            filtered = filtered.filter { $0.rateTotal > 0 || $0.bytesTotal > 0 }
        }
        if !options.searchText.isEmpty {
            let q = options.searchText.lowercased()
            filtered = filtered.filter {
                $0.process.name.lowercased().contains(q)
                    || $0.process.familyName.lowercased().contains(q)
                    || $0.remoteHost.lowercased().contains(q)
                    || $0.remoteIP.lowercased().contains(q)
                    || $0.remoteDisplayName.lowercased().contains(q)
                    || ($0.process.bundleID?.lowercased().contains(q) ?? false)
            }
        }

        switch options.listMode {
        case .flat:
            return buildFlat(filtered, hideHelpers: options.hideHelpers)
        case .grouped:
            return buildGrouped(filtered, hideHelpers: options.hideHelpers)
        }
    }

    private static func buildFlat(_ streams: [NetworkStream], hideHelpers: Bool) -> [ProcessFamilyNode] {
        var byPID: [pid_t: [NetworkStream]] = [:]
        for s in streams {
            if hideHelpers && s.process.role == .helper { continue }
            byPID[s.process.pid, default: []].append(s)
        }
        return byPID.map { pid, list in
            let process = list[0].process
            let rateIn = list.reduce(Int64(0)) { $0 + $1.rateIn }
            let rateOut = list.reduce(Int64(0)) { $0 + $1.rateOut }
            let bytesIn = list.reduce(Int64(0)) { $0 + $1.bytesIn }
            let bytesOut = list.reduce(Int64(0)) { $0 + $1.bytesOut }
            let children = list
                .sorted { $0.rateTotal > $1.rateTotal }
                .prefix(40)
                .map { streamNode($0) }
            return ProcessFamilyNode(
                id: "proc-\(pid)",
                kind: .process,
                title: process.name,
                subtitle: process.familyName,
                rateIn: rateIn,
                rateOut: rateOut,
                bytesIn: bytesIn,
                bytesOut: bytesOut,
                connectionCount: list.count,
                children: Array(children),
                familyID: process.familyID,
                role: process.role,
                isAgent: process.role == .agent
            )
        }
        .sorted { $0.rateTotal > $1.rateTotal }
    }

    private static func buildGrouped(_ streams: [NetworkStream], hideHelpers: Bool) -> [ProcessFamilyNode] {
        var byFamily: [String: [NetworkStream]] = [:]
        for s in streams {
            byFamily[s.process.familyID, default: []].append(s)
        }

        return byFamily.map { familyID, list -> ProcessFamilyNode in
            let familyName = list.first?.process.familyName ?? familyID
            let isAgent = list.contains { $0.process.role == .agent }

            // Sites first — OS can't show browser tabs; remotes are the actionable breakdown.
            let siteChildren = hostNodes(from: list, familyID: familyID)

            // Role → PID hierarchy (helpers optionally collapsed).
            var byRole: [ProcessRole: [NetworkStream]] = [:]
            for s in list {
                if hideHelpers && s.process.role == .helper { continue }
                byRole[s.process.role, default: []].append(s)
            }

            let roleChildren: [ProcessFamilyNode] = byRole
                .map { role, roleStreams in
                    let rateIn = roleStreams.reduce(Int64(0)) { $0 + $1.rateIn }
                    let rateOut = roleStreams.reduce(Int64(0)) { $0 + $1.rateOut }
                    let bytesIn = roleStreams.reduce(Int64(0)) { $0 + $1.bytesIn }
                    let bytesOut = roleStreams.reduce(Int64(0)) { $0 + $1.bytesOut }

                    var byPID: [pid_t: [NetworkStream]] = [:]
                    for s in roleStreams { byPID[s.process.pid, default: []].append(s) }

                    let processChildren = byPID.map { pid, pidStreams -> ProcessFamilyNode in
                        let p = pidStreams[0].process
                        let pRateIn = pidStreams.reduce(Int64(0)) { $0 + $1.rateIn }
                        let pRateOut = pidStreams.reduce(Int64(0)) { $0 + $1.rateOut }
                        let streamChildren = pidStreams
                            .sorted { $0.rateTotal > $1.rateTotal }
                            .prefix(30)
                            .map { streamNode($0) }
                        return ProcessFamilyNode(
                            id: "\(familyID)-role-\(role.rawValue)-pid-\(pid)",
                            kind: .process,
                            title: p.name,
                            subtitle: "PID \(pid)",
                            rateIn: pRateIn,
                            rateOut: pRateOut,
                            bytesIn: pidStreams.reduce(0) { $0 + $1.bytesIn },
                            bytesOut: pidStreams.reduce(0) { $0 + $1.bytesOut },
                            connectionCount: pidStreams.count,
                            children: Array(streamChildren),
                            familyID: familyID,
                            role: role,
                            isAgent: role == .agent
                        )
                    }
                    .sorted { $0.rateTotal > $1.rateTotal }

                    return ProcessFamilyNode(
                        id: "\(familyID)-role-\(role.rawValue)",
                        kind: .roleGroup(role),
                        title: role.label,
                        subtitle: L10n.processCount(byPID.count),
                        rateIn: rateIn,
                        rateOut: rateOut,
                        bytesIn: bytesIn,
                        bytesOut: bytesOut,
                        connectionCount: roleStreams.count,
                        children: processChildren,
                        familyID: familyID,
                        role: role,
                        isAgent: role == .agent
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.role == .main { return true }
                    if rhs.role == .main { return false }
                    return lhs.rateTotal > rhs.rateTotal
                }

            // Family totals always include helpers so Chrome isn't "0 streams" while the map is busy.
            let rateIn = list.reduce(Int64(0)) { $0 + $1.rateIn }
            let rateOut = list.reduce(Int64(0)) { $0 + $1.rateOut }
            let helperCount = list.filter { $0.process.role == .helper }.count
            let subtitle: String
            if hideHelpers, helperCount > 0, helperCount == list.count {
                subtitle = L10n.streamsViaHelpers(list.count)
            } else if hideHelpers, helperCount > 0 {
                subtitle = L10n.streamsWithHelpers(list.count, helperCount)
            } else {
                subtitle = L10n.streamCount(list.count)
            }

            var children: [ProcessFamilyNode] = []
            if !siteChildren.isEmpty {
                children.append(ProcessFamilyNode(
                    id: "\(familyID)-sites",
                    kind: .sites,
                    title: L10n.sites,
                    subtitle: L10n.remoteCount(siteChildren.count),
                    rateIn: rateIn,
                    rateOut: rateOut,
                    bytesIn: list.reduce(0) { $0 + $1.bytesIn },
                    bytesOut: list.reduce(0) { $0 + $1.bytesOut },
                    connectionCount: list.count,
                    children: siteChildren,
                    familyID: familyID,
                    isAgent: isAgent
                ))
            }
            // When hideHelpers collapses everything into Sites, skip empty process roles.
            if !hideHelpers || !roleChildren.isEmpty {
                children.append(contentsOf: roleChildren)
            }

            return ProcessFamilyNode(
                id: "family-\(familyID)",
                kind: .family,
                title: familyName,
                subtitle: subtitle,
                rateIn: rateIn,
                rateOut: rateOut,
                bytesIn: list.reduce(0) { $0 + $1.bytesIn },
                bytesOut: list.reduce(0) { $0 + $1.bytesOut },
                connectionCount: list.count,
                children: children,
                familyID: familyID,
                isAgent: isAgent
            )
        }
        .sorted { $0.rateTotal > $1.rateTotal }
    }

    private static func hostNodes(from streams: [NetworkStream], familyID: String) -> [ProcessFamilyNode] {
        var byHost: [String: [NetworkStream]] = [:]
        for s in streams {
            let key = s.remoteKey
            guard !key.isEmpty else { continue }
            byHost[key, default: []].append(s)
        }

        return byHost.map { key, list in
            let sample = list.first
            let title = sample?.remoteDisplayName ?? key
            let rateIn = list.reduce(Int64(0)) { $0 + $1.rateIn }
            let rateOut = list.reduce(Int64(0)) { $0 + $1.rateOut }
            let geoHint = list.compactMap(\.geo?.displayLabel).first
            let orgHint = list.compactMap(\.geo?.org).first { !$0.isEmpty }
            let ipHint = sample?.remoteIP ?? ""
            let hasWebsiteName = sample?.resolvedHostnameForDisplay != nil
            let subtitleParts: [String] = {
                var parts: [String] = []
                if hasWebsiteName, !ipHint.isEmpty {
                    parts.append(ipHint)
                }
                if let geoHint { parts.append(geoHint) }
                else if !hasWebsiteName, let orgHint {
                    // CDN edges often have no PTR — org is the only human signal.
                    parts.append(orgHint)
                }
                if parts.isEmpty {
                    parts.append("\(list.count) connection\(list.count == 1 ? "" : "s")")
                }
                return parts
            }()
            let streamChildren = list
                .sorted { $0.rateTotal > $1.rateTotal }
                .prefix(40)
                .map { streamNode($0, preferHostInTitle: false) }
            return ProcessFamilyNode(
                id: "\(familyID)-host-\(key)",
                kind: .host,
                title: title,
                subtitle: subtitleParts.joined(separator: " · "),
                rateIn: rateIn,
                rateOut: rateOut,
                bytesIn: list.reduce(0) { $0 + $1.bytesIn },
                bytesOut: list.reduce(0) { $0 + $1.bytesOut },
                connectionCount: list.count,
                children: Array(streamChildren),
                familyID: familyID,
                hostKey: key
            )
        }
        .sorted { $0.rateTotal > $1.rateTotal }
        .prefix(40)
        .map { $0 }
    }

    private static func streamNode(_ s: NetworkStream, preferHostInTitle: Bool = true) -> ProcessFamilyNode {
        let host = s.remoteDisplayName
        let title: String
        let subtitle: String
        if preferHostInTitle {
            title = host
            if let geo = s.geo {
                subtitle = "\(geo.displayLabel) · \(s.protocolName.uppercased()) :\(s.remotePort)"
            } else {
                subtitle = "\(s.protocolName.uppercased()) :\(s.remotePort)"
            }
        } else {
            title = ":\(s.remotePort) · PID \(s.process.pid)"
            subtitle = "\(s.protocolName.uppercased()) · \(s.process.name)"
        }
        return ProcessFamilyNode(
            id: "stream-\(s.id)",
            kind: .stream,
            title: title,
            subtitle: subtitle,
            rateIn: s.rateIn,
            rateOut: s.rateOut,
            bytesIn: s.bytesIn,
            bytesOut: s.bytesOut,
            connectionCount: 1,
            children: [],
            streamID: s.id,
            familyID: s.process.familyID,
            hostKey: s.remoteKey,
            role: s.process.role,
            isAgent: s.process.role == .agent
        )
    }
}
