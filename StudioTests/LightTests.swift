import XCTest
@testable import AnimaStudio
final class LightTests: XCTestCase {
    @MainActor func testBrightnessBounds() {
        XCTAssertEqual(KeyLightControl.brightness(-5), 0)
        XCTAssertEqual(KeyLightControl.brightness(105), 100)
        XCTAssertEqual(KeyLightControl.brightness(25), 25)
    }
    func testDecodeDeviceState() throws {
        let data = Data(#"{"numberOfLights":1,"lights":[{"on":1,"brightness":20,"temperature":230}]}"#.utf8)
        let value = try JSONDecoder().decode(KeyLightEnvelope.self, from: data)
        XCTAssertEqual(value.lights.first, KeyLightState(on: 1, brightness: 20, temperature: 230))
    }
}
