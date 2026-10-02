import XCTest
@testable import AnimaStudio
final class MonitorTests: XCTestCase {
    @MainActor func testStudioInclusionOnlyChangesOwnApp() {
        XCTAssertTrue(MonitorCapture.excludeApplication(pid: 42, ownPID: 42, includeStudio: false))
        XCTAssertFalse(MonitorCapture.excludeApplication(pid: 42, ownPID: 42, includeStudio: true))
        XCTAssertFalse(MonitorCapture.excludeApplication(pid: 7, ownPID: 42, includeStudio: false))
        XCTAssertFalse(MonitorCapture.excludeApplication(pid: 7, ownPID: 42, includeStudio: true))
    }
    @MainActor func testCaptureSizeIsBoundedAndEven() {
        for (w,h) in [(6016,3384),(1920,1080),(1512,982),(1080,1920),(1,1)] {
            let (x,y) = MonitorCapture.dimensions(width:w,height:h)
            XCTAssertLessThanOrEqual(x,1920); XCTAssertLessThanOrEqual(y,1080)
            XCTAssertGreaterThanOrEqual(x,2); XCTAssertGreaterThanOrEqual(y,2)
            XCTAssertEqual(x%2,0); XCTAssertEqual(y%2,0)
        }
    }
}
