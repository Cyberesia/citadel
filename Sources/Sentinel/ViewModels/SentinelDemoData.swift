import Foundation

enum SentinelDemoData {
    @MainActor
    static func load(into vm: SentinelViewModel) {
        let now = Date()
        let cursorFamily = "com.todesktop.230313mzl4w4u92"
        let coworkFamily = "coworkcore"

        func identity(
            pid: pid_t,
            name: String,
            familyID: String,
            familyName: String,
            role: ProcessRole,
            path: String = ""
        ) -> ProcessIdentity {
            ProcessIdentity(
                pid: pid,
                name: name,
                path: path,
                bundleID: familyID.contains(".") ? familyID : nil,
                familyID: familyID,
                familyName: familyName,
                role: role
            )
        }

        let destinations: [(String, String, Double, Double, String)] = [
            ("142.250.185.78", "Ashburn, United States", 39.04, -77.49, "US"),
            ("104.16.132.229", "San Francisco, United States", 37.77, -122.42, "US"),
            ("52.95.110.1", "Dublin, Ireland", 53.35, -6.26, "IE"),
            ("13.107.42.16", "Amsterdam, Netherlands", 52.37, 4.90, "NL"),
            ("151.101.1.140", "Frankfurt, Germany", 50.11, 8.68, "DE"),
            ("18.66.122.89", "Seattle, United States", 47.61, -122.33, "US"),
            ("35.186.224.25", "Tokyo, Japan", 35.68, 139.69, "JP"),
            ("104.244.42.65", "Toronto, Canada", 43.65, -79.38, "CA"),
        ]

        var streams: [NetworkStream] = []

        // Cursor main + helpers (noise scenario)
        let cursorMain = identity(pid: 41001, name: "Cursor", familyID: cursorFamily, familyName: "Cursor", role: .main,
                                  path: "/Applications/Cursor.app/Contents/MacOS/Cursor")
        streams.append(makeStream(cursorMain, destinations[0], rateIn: 12_000, rateOut: 4_000, now: now))
        streams.append(makeStream(cursorMain, destinations[1], rateIn: 8_000, rateOut: 2_000, now: now))

        for i in 0..<6 {
            let helper = identity(
                pid: pid_t(41100 + i),
                name: "Cursor Helper",
                familyID: cursorFamily,
                familyName: "Cursor",
                role: .helper,
                path: "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper.app/Contents/MacOS/Cursor Helper"
            )
            let dest = destinations[i % destinations.count]
            streams.append(makeStream(helper, dest, rateIn: Int64(5_000 + i * 800), rateOut: Int64(1_000 + i * 200), now: now))
        }

        // Cowork agent
        let agent = identity(pid: 42001, name: "coworkcore", familyID: coworkFamily, familyName: "Cowork", role: .agent,
                             path: "/Applications/Citadel.app/Contents/MacOS/coworkcore-bundled")
        streams.append(makeStream(agent, destinations[2], rateIn: 28_000, rateOut: 11_000, now: now))
        streams.append(makeStream(agent, destinations[4], rateIn: 9_000, rateOut: 3_000, now: now))

        // Safari
        let safari = identity(pid: 43001, name: "Safari", familyID: "com.apple.Safari", familyName: "Safari", role: .main,
                              path: "/Applications/Safari.app/Contents/MacOS/Safari")
        streams.append(makeStream(safari, destinations[3], rateIn: 15_000, rateOut: 2_500, now: now))
        streams.append(makeStream(safari, destinations[6], rateIn: 6_000, rateOut: 900, now: now))

        // Slack
        let slack = identity(pid: 44001, name: "Slack", familyID: "com.tinyspeck.slackmacgap", familyName: "Slack", role: .main)
        streams.append(makeStream(slack, destinations[5], rateIn: 4_500, rateOut: 1_200, now: now))
        let slackHelper = identity(pid: 44002, name: "Slack Helper", familyID: "com.tinyspeck.slackmacgap", familyName: "Slack", role: .helper)
        streams.append(makeStream(slackHelper, destinations[7], rateIn: 2_200, rateOut: 600, now: now))

        // Google Chrome — helpers carry the sockets; Sites should still show remotes
        let chromeFamily = "com.google.Chrome"
        let chromePath =
            "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/120.0.0/Helpers/Google Chrome Helper (Network).app/Contents/MacOS/Google Chrome Helper"
        let chromeSites: [(String, String, String, Double, Double, String)] = [
            ("142.250.185.78", "www.youtube.com", "Mountain View, United States", 37.39, -122.08, "US"),
            ("142.250.74.110", "mail.google.com", "Mountain View, United States", 37.39, -122.08, "US"),
            ("104.16.132.229", "cdnjs.cloudflare.com", "San Francisco, United States", 37.77, -122.42, "US"),
            ("151.101.1.140", "www.reddit.com", "Frankfurt, Germany", 50.11, 8.68, "DE"),
            ("13.107.42.16", "login.microsoftonline.com", "Amsterdam, Netherlands", 52.37, 4.90, "NL"),
        ]
        for (i, site) in chromeSites.enumerated() {
            let helper = identity(
                pid: pid_t(45010 + i),
                name: "Google Chrome Helper",
                familyID: chromeFamily,
                familyName: "Google Chrome",
                role: i == 0 ? .network : .helper,
                path: chromePath
            )
            streams.append(makeStream(
                helper,
                (site.0, site.2, site.3, site.4, site.5),
                host: site.1,
                rateIn: Int64(40_000 + i * 12_000),
                rateOut: Int64(8_000 + i * 2_000),
                now: now
            ))
        }

        vm.applyDemoStreams(streams, rateIn: 95_000, rateOut: 28_000)
        vm.mapOrigin = SentinelGeoPoint(latitude: 45.50, longitude: -73.57)
        vm.machineSparkline = (0..<40).map { _ in Int64.random(in: 40_000...140_000) }
    }

    private static func makeStream(
        _ process: ProcessIdentity,
        _ dest: (String, String, Double, Double, String),
        host: String? = nil,
        rateIn: Int64,
        rateOut: Int64,
        now: Date
    ) -> NetworkStream {
        let (ip, label, lat, lon, code) = dest
        let parts = label.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let city = parts.first.map { String($0) }
        let country = parts.count > 1 ? String(parts[1]) : nil
        return NetworkStream(
            id: NetworkStream.makeID(pid: process.pid, remoteIP: ip, remotePort: 443, proto: "tcp"),
            process: process,
            remoteHost: host ?? ip,
            remoteIP: ip,
            remotePort: 443,
            protocolName: "tcp",
            bytesIn: rateIn * 60,
            bytesOut: rateOut * 60,
            rateIn: rateIn,
            rateOut: rateOut,
            status: .established,
            geo: SentinelGeoLocation(
                ip: ip,
                country: country,
                countryCode: code,
                city: city,
                latitude: lat,
                longitude: lon
            ),
            firstSeen: now.addingTimeInterval(-120),
            lastSeen: now
        )
    }
}
