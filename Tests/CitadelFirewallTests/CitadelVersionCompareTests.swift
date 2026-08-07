import XCTest
@testable import Citadel

final class CitadelVersionCompareTests: XCTestCase {
    func testNormalizeStripsLeadingV() {
        XCTAssertEqual(CitadelVersionCompare.normalize("v0.1.1"), "0.1.1")
        XCTAssertEqual(CitadelVersionCompare.normalize("V1.0.0"), "1.0.0")
    }

    func testIsRemoteNewer() {
        XCTAssertTrue(CitadelVersionCompare.isRemoteNewer(remote: "0.1.2", local: "0.1.1"))
        XCTAssertTrue(CitadelVersionCompare.isRemoteNewer(remote: "v0.2.0", local: "0.1.9"))
        XCTAssertFalse(CitadelVersionCompare.isRemoteNewer(remote: "0.1.1", local: "0.1.1"))
        XCTAssertFalse(CitadelVersionCompare.isRemoteNewer(remote: "0.1.0", local: "0.1.1"))
    }

    func testComparePatchAndMajor() {
        XCTAssertEqual(CitadelVersionCompare.compare("1.0.0", "0.9.9"), .orderedDescending)
        XCTAssertEqual(CitadelVersionCompare.compare("0.1.10", "0.1.9"), .orderedDescending)
        XCTAssertEqual(CitadelVersionCompare.compare("0.1.0", "0.1.0"), .orderedSame)
    }
}
