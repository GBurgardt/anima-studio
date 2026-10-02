import XCTest
@testable import AnimaStudio
final class SettingsTests: XCTestCase {
    func testValidationAndShellQuoting() throws {
        var c = ConnectionSettings(host: "studio-server", node: "/usr/local/bin/node", controller: "/Users/test/My Studio/controller.mjs", recordings: "/Users/test/Movies", lightHost: "")
        XCTAssertNoThrow(try c.validate())
        c.host = "-oProxyCommand=bad"
        XCTAssertThrowsError(try c.validate())
        XCTAssertEqual(ConnectionSettings.quote("a'b"), "'a'\\''b'")
    }
}
