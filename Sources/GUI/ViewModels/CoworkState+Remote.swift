import Foundation
import Darwin

// MARK: - WebUI remote access + chat platform bridges (plan Phase 6)

extension CoworkState {
    private static let remoteUsernameKey = "citadel.cowork.remote.username"
    private static let remotePasswordKey = "citadel.cowork.remote.password"

    var remoteUsername: String? { UserDefaults.standard.string(forKey: Self.remoteUsernameKey) }
    var remotePassword: String? { UserDefaults.standard.string(forKey: Self.remotePasswordKey) }

    /// Enables LAN access: provisions credentials while still in local mode,
    /// then restarts the backend bound to 0.0.0.0 with authentication on.
    func enableRemoteAccess() async {
        guard let client else { return }
        isRemoteBusy = true
        defer { isRemoteBusy = false }
        do {
            // Credentials can only be rotated in local mode.
            let password = try await client.webuiResetPassword().newPassword
            let username = try await client.webuiChangeUsername(remoteUsername ?? "citadel")
            UserDefaults.standard.set(username, forKey: Self.remoteUsernameKey)
            UserDefaults.standard.set(password, forKey: Self.remotePasswordKey)

            await lifecycle.restart(remote: true)
            guard lifecycle.status == .running, let port = lifecycle.port else {
                statusMessage = lifecycle.lastError ?? L10n.remoteEnableFailed
                return
            }
            // Published port mirrors update async; talk to the fresh port directly.
            let freshClient = CoworkCoreClient(port: port)
            try await freshClient.login(username: username, password: password)
            remoteAccessEnabled = true
            await refreshQRToken()
            await bootstrap()
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
            await disableRemoteAccess()
        }
    }

    /// Returns the backend to loopback-only, unauthenticated local mode.
    func disableRemoteAccess() async {
        isRemoteBusy = true
        defer { isRemoteBusy = false }
        remoteAccessEnabled = false
        remoteQRToken = nil
        await lifecycle.restart(remote: false)
        if lifecycle.status == .running {
            await bootstrap()
        }
    }

    func refreshQRToken() async {
        guard let client, remoteAccessEnabled else { return }
        remoteQRToken = try? await client.webuiGenerateQRToken().token
    }

    /// Primary LAN IPv4 of this Mac, for the remote-access URL.
    var lanAddress: String? {
        var address: String?
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let flags = Int32(current.pointee.ifa_flags)
            if let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET),
               (flags & IFF_LOOPBACK) == 0,
               (flags & IFF_UP) != 0 {
                let name = String(cString: current.pointee.ifa_name)
                if name.hasPrefix("en") {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: host)
                        break
                    }
                }
            }
            pointer = current.pointee.ifa_next
        }
        return address
    }

    var remoteAccessURL: String? {
        guard remoteAccessEnabled, let port = lifecycle.port, let ip = lanAddress else { return nil }
        return "http://\(ip):\(port)"
    }

    // MARK: - Channel bridges (Telegram & co)

    func refreshChannels() async {
        guard let client else { return }
        do {
            channelPlugins = try await client.listChannelPlugins()
            channelPairings = (try? await client.listChannelPairings()) ?? []
            channelUsers = (try? await client.listChannelUsers()) ?? []
        } catch {
            channelPlugins = []
        }
    }

    func testChannelToken(pluginID: String, token: String) async -> String? {
        guard let client else { return nil }
        do {
            let result = try await client.testChannelPlugin(pluginID: pluginID, token: token)
            if result.success == true {
                return result.botUsername
            }
            statusMessage = result.error ?? L10n.channelTestFailed
            return nil
        } catch {
            statusMessage = L10n.localizeError(error.localizedDescription)
            return nil
        }
    }

    func enableChannel(pluginID: String, token: String) async {
        guard let client else { return }
        do {
            try await client.enableChannelPlugin(pluginID: pluginID, config: ["token": token])
            await refreshChannels()
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    func disableChannel(pluginID: String) async {
        guard let client else { return }
        do {
            try await client.disableChannelPlugin(pluginID: pluginID)
            await refreshChannels()
        } catch { statusMessage = L10n.localizeError(error.localizedDescription) }
    }

    func approvePairing(code: String) async {
        guard let client else { return }
        try? await client.approveChannelPairing(code: code)
        await refreshChannels()
    }

    func rejectPairing(code: String) async {
        guard let client else { return }
        try? await client.rejectChannelPairing(code: code)
        await refreshChannels()
    }

    func revokeChannelUser(id: String) async {
        guard let client else { return }
        try? await client.revokeChannelUser(userID: id)
        await refreshChannels()
    }
}
