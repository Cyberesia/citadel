import XCTest
@testable import Citadel

final class FirewallRuleEvaluatorTests: XCTestCase {
    private let evaluator = FirewallRuleEvaluator()

    private func connection(
        name: String = "App",
        path: String = "/Applications/App.app/Contents/MacOS/App",
        bundle: String? = "com.example.app",
        host: String = "example.com",
        ip: String = "1.2.3.4",
        port: Int = 443,
        direction: RuleDirection = .outgoing
    ) -> Connection {
        Connection(
            pid: 42,
            processName: name,
            processPath: path,
            processBundleId: bundle,
            remoteHost: host,
            remoteIP: ip,
            remotePort: port,
            direction: direction,
            status: .pending
        )
    }

    func testDefaultModes() {
        let c = connection()
        XCTAssertEqual(evaluator.decision(for: c, rules: [], defaultMode: .alert), .ask)
        XCTAssertEqual(evaluator.decision(for: c, rules: [], defaultMode: .silentAllow), .allow)
        XCTAssertEqual(evaluator.decision(for: c, rules: [], defaultMode: .silentDeny), .deny)
    }

    func testHigherPriorityWins() {
        let c = connection()
        let allow = Rule(remoteHost: "example.com", action: .allow, priority: 10)
        let deny = Rule(remoteHost: "example.com", action: .deny, priority: 100)
        XCTAssertEqual(evaluator.decision(for: c, rules: [allow, deny], defaultMode: .alert), .deny)
    }

    func testExpiredTemporaryIgnored() {
        let c = connection()
        let expired = Rule(
            remoteHost: "example.com",
            action: .deny,
            priority: 200,
            temporary: true,
            expiresAt: Date().addingTimeInterval(-60)
        )
        XCTAssertEqual(evaluator.decision(for: c, rules: [expired], defaultMode: .silentAllow), .allow)
    }

    func testNameOnlyProcessRule() {
        let agent = connection(name: "coworkcore", path: "", bundle: nil)
        let other = connection(name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari", bundle: "com.apple.Safari")
        let rule = Rule(processName: "coworkcore", action: .deny, scope: .process, priority: 50)
        XCTAssertTrue(evaluator.matches(rule: rule, connection: agent))
        XCTAssertFalse(evaluator.matches(rule: rule, connection: other))
    }

    func testBundleIdProcessRule() {
        let c = connection(bundle: "com.google.Chrome")
        let rule = Rule(processBundleId: "com.google.Chrome", action: .allow, scope: .process)
        XCTAssertTrue(evaluator.matches(rule: rule, connection: c))
        XCTAssertFalse(evaluator.matches(
            rule: Rule(processBundleId: "com.apple.Safari", action: .allow, scope: .process),
            connection: c
        ))
    }

    func testWildcardHost() {
        XCTAssertTrue(evaluator.hostMatches(pattern: "*.example.com", host: "a.example.com"))
        XCTAssertTrue(evaluator.hostMatches(pattern: "*.example.com", host: "example.com"))
        XCTAssertFalse(evaluator.hostMatches(pattern: "*.example.com", host: "evil.com"))
    }

    func testCIDR() {
        XCTAssertTrue(evaluator.ipMatches(pattern: "10.0.0.0/8", ip: "10.1.2.3"))
        XCTAssertFalse(evaluator.ipMatches(pattern: "10.0.0.0/8", ip: "11.0.0.1"))
    }
}
