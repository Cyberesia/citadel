import SwiftUI

struct FortressInspector: View {
    @ObservedObject var vm: FortressViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let stream = selectedStream {
                    streamDetail(stream)
                    firewallActions(stream)
                    MetricSparkline(values: vm.sparkline(forStream: stream.id), tint: PrismTheme.accent)
                        .padding(.vertical, 4)
                } else {
                    overview
                }
            }
            .padding(14)
        }
    }

    private var selectedStream: NetworkStream? {
        if case .stream(let id) = vm.focus {
            return vm.stream(for: id)
        }
        if let id = vm.selectedStreamID {
            return vm.stream(for: id)
        }
        return nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedStream == nil ? L10n.summary : L10n.stream)
                .font(.ps(18, weight: .bold))
                .foregroundStyle(PrismTheme.textPrimary)
            Text(subtitle)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textTertiary)
        }
    }

    private var subtitle: String {
        switch vm.focus {
        case .all:
            return L10n.t(
                "\(vm.streams.count) streams · \(vm.tree.count) apps",
                "\(vm.streams.count) flux · \(vm.tree.count) apps"
            )
        case .family(let id):
            let name = vm.streams.first { $0.process.familyID == id }?.process.familyName ?? id
            return L10n.t("Focused on \(name)", "Focus sur \(name)")
        case .role(_, let role):
            return L10n.t("Role: \(role.label)", "Rôle : \(role.label)")
        case .host(_, let hostKey):
            return L10n.t("Site: \(hostKey)", "Site : \(hostKey)")
        case .stream:
            return L10n.t("Connection detail", "Détail de la connexion")
        }
    }

    @ViewBuilder
    private func streamDetail(_ stream: NetworkStream) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow(L10n.process, stream.process.name)
            detailRow(L10n.family, stream.process.familyName)
            detailRow(L10n.role, stream.process.role.label)
            detailRow("PID", "\(stream.process.pid)")
            if let bid = stream.process.bundleID {
                detailRow("Bundle", bid)
            }
            detailRow(L10n.signing, signingLabel(stream.process))
            if let team = stream.process.codeTeamID, !team.isEmpty {
                detailRow(L10n.teamID, team)
            }
            if !stream.process.path.isEmpty {
                detailRow(L10n.pathLabel, stream.process.path)
            }
            Divider().opacity(0.3)
            detailRow(L10n.remote, stream.remoteDisplayName)
            if stream.remoteDisplayName != stream.remoteIP {
                detailRow("IP", stream.remoteIP)
            }
            if stream.remoteHostFull != stream.remoteDisplayName,
               stream.remoteHostFull != stream.remoteIP {
                detailRow(L10n.host, stream.remoteHostFull)
            }
            detailRow(L10n.port, "\(stream.remotePort)")
            detailRow(L10n.protocolLabel, stream.protocolName.uppercased())
            detailRow(L10n.status, stream.status.rawValue)
            detailRow(L10n.rateDown, FortressFormat.bytesPerSec(stream.rateIn))
            detailRow(L10n.rateUp, FortressFormat.bytesPerSec(stream.rateOut))
            if let geo = stream.geo {
                detailRow(L10n.location, geo.displayLabel)
            }
        }
        .padding(10)
        .background(PrismTheme.surface.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func firewallActions(_ stream: NetworkStream) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.firewall)
                .font(.ps(11, weight: .semibold))
                .foregroundStyle(PrismTheme.textTertiary)

            HStack(spacing: 8) {
                PrismActionChip(title: L10n.allow1h, systemImage: "checkmark", kind: .allow, emphasized: true) {
                    vm.allowStream(stream, remember: false)
                }
                PrismActionChip(title: L10n.deny1h, systemImage: "xmark", kind: .deny, emphasized: true) {
                    vm.denyStream(stream, remember: false)
                }
            }
            HStack(spacing: 8) {
                PrismActionChip(title: L10n.rememberAllowShort, kind: .allow) {
                    vm.allowStream(stream, remember: true)
                }
                PrismActionChip(title: L10n.rememberDenyShort, kind: .deny) {
                    vm.denyStream(stream, remember: true)
                }
            }

            if !vm.helperConnected && !vm.isDemoMode {
                Text(L10n.helperRememberOffline)
                    .font(.ps(10))
                    .foregroundStyle(PrismTheme.textTertiary)
            }

            Button {
                vm.copyDetails(for: stream)
            } label: {
                Label(L10n.copyDetails, systemImage: "doc.on.doc")
                    .font(.ps(11, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(PrismTheme.textSecondary)
                    .background(PrismTheme.surface.opacity(0.35))
                    .overlay {
                        Capsule().strokeBorder(PrismTheme.borderSubtle, lineWidth: 1)
                    }
                    .clipShape(Capsule())
            }
            .buttonStyle(PrismHandButtonStyle())
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ratePill(FortressFormat.bytesPerSec(vm.currentIn), L10n.trafficDown, PrismTheme.trafficDown.opacity(0.35))
                ratePill(FortressFormat.bytesPerSec(vm.currentOut), L10n.trafficUp, PrismTheme.trafficUp.opacity(0.35))
            }

            if !vm.machineSparkline.isEmpty {
                MetricSparkline(values: vm.machineSparkline)
            }

            rollupSection(L10n.destinations, items: vm.topDestinations) { rollup in
                vm.setFocus(.stream(id: rollup.id))
            }

            if showsAppsRollup {
                rollupSection(L10n.topApps, items: vm.topFamilies) { rollup in
                    vm.setFocus(.family(rollup.id))
                }
            }

            rollupSection(sitesSectionTitle, items: vm.topDomains) { rollup in
                focusHost(rollup.id)
            }

            rollupSection(L10n.topCountries, items: vm.topCountries) { _ in }
        }
    }

    private var showsAppsRollup: Bool {
        if case .all = vm.focus { return true }
        return false
    }

    private var sitesSectionTitle: String {
        switch vm.focus {
        case .family, .host, .role:
            return L10n.sites
        default:
            return L10n.topSites
        }
    }

    private func focusHost(_ hostKey: String) {
        switch vm.focus {
        case .family(let id), .role(let id, _), .host(let id, _):
            vm.setFocus(.host(familyID: id, hostKey: hostKey))
        case .stream(let id):
            if let stream = vm.stream(for: id) {
                vm.setFocus(.host(familyID: stream.process.familyID, hostKey: hostKey))
            }
        case .all:
            // Global: jump to first family that has this host, else keep listing.
            if let stream = vm.streams.first(where: { $0.remoteKey == hostKey }) {
                vm.setFocus(.host(familyID: stream.process.familyID, hostKey: hostKey))
            }
        }
    }

    private func rollupSection(
        _ title: String,
        items: [FortressRollup],
        onSelect: @escaping (FortressRollup) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.ps(11, weight: .semibold))
                .foregroundStyle(PrismTheme.textTertiary)
            if items.isEmpty {
                Text(L10n.noDataYet)
                    .font(.ps(11))
                    .foregroundStyle(PrismTheme.textTertiary)
            } else {
                ForEach(items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        HStack(spacing: 8) {
                            Text(item.label)
                                .font(.ps(11))
                                .foregroundStyle(PrismTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if item.connectionCount > 1 {
                                Text("\(item.connectionCount)")
                                    .font(.ps(10, weight: .semibold))
                                    .foregroundStyle(PrismTheme.textTertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(PrismTheme.surface.opacity(0.5))
                                    .clipShape(Capsule())
                            }
                            Text(item.rateTotal > 0
                                 ? FortressFormat.bytesPerSec(item.rateTotal)
                                 : FortressFormat.bytes(item.bytesTotal))
                                .font(.ps(10, weight: .semibold))
                                .foregroundStyle(PrismTheme.textSecondary)
                                .monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PrismHandButtonStyle())
                }
            }
        }
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.ps(10))
                .foregroundStyle(PrismTheme.textTertiary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textPrimary)
                .textSelection(.enabled)
        }
    }

    private func signingLabel(_ process: ProcessIdentity) -> String {
        switch process.signingStatus {
        case .signedValid: return L10n.signedValid
        case .signedInvalid: return L10n.signedInvalid
        case .unsigned: return L10n.unsignedBinary
        case .unknown: return L10n.signingUnknown
        }
    }

    private func ratePill(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.ps(16, weight: .bold)).foregroundStyle(.white)
            Text(label).font(.ps(10)).foregroundStyle(PrismTheme.textSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
