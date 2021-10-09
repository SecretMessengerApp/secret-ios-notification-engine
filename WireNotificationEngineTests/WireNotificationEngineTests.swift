

import XCTest
import WireDataModel
import WireTesting
@testable import WireNotificationEngine

class WireNotificationEngineTests: ZMTBaseTest {
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testExample() {
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertTrue(true)
    }
}
