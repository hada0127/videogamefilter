import XCTest
import CoreMedia
@testable import GameCapture
final class FrameDurationTests: XCTestCase {
    func testFixedRatesPreserveExactRationalDuration() {
        for value in [CMTime(value: 1, timescale: 60), CMTime(value: 1001, timescale: 60000), CMTime(value: 1, timescale: 30), CMTime(value: 1, timescale: 120)] {
            let result = VideoMode.preferredDuration(minimum: value, maximum: value)
            XCTAssertEqual(CMTimeCompare(result, value), 0)
            XCTAssertEqual(result.value, value.value)
            XCTAssertEqual(result.timescale, value.timescale)
        }
    }
    func testVariableRateChoosesSixtyWithinSupportedBounds() {
        let result = VideoMode.preferredDuration(minimum: CMTime(value: 1, timescale: 120), maximum: CMTime(value: 1, timescale: 24))
        XCTAssertEqual(CMTimeCompare(result, CMTime(value: 1, timescale: 60)), 0)
    }
    func testFloatingPointRoundingWouldViolateFixedSixtyRange() {
        let fixed = CMTime(value: 1, timescale: 60)
        let previous = CMTime(seconds: 1.0 / 60, preferredTimescale: 1_000_000)
        XCTAssertNotEqual(CMTimeCompare(fixed, previous), 0)
        XCTAssertEqual(CMTimeCompare(VideoMode.preferredDuration(minimum: fixed, maximum: fixed), fixed), 0)
    }
}

final class ModeSelectionTests: XCTestCase {
    func testSixtyIsPreferredEvenWhenHigherFixedRateIsFirst() {
        let modes = [120, 60, 30].enumerated().map { index, rate in
            VideoMode(id: index, formatIndex: 4, width: 1920, height: 1080, duration: CMTime(value: 1, timescale: Int32(rate)))
        }
        let unique = VideoMode.unique(modes)
        XCTAssertEqual(unique.count, 3)
        XCTAssertEqual(VideoMode.preferred(in: unique)?.fps, 60)
        XCTAssertEqual(VideoMode.preferred(in: unique)?.formatIndex, 4)
    }
    func testFractionalRatesRemainDistinctAndClearlyLabeled() {
        let a = VideoMode(id: 0, formatIndex: 0, width: 1920, height: 1080, duration: CMTime(value: 1, timescale: 60))
        let b = VideoMode(id: 1, formatIndex: 1, width: 1920, height: 1080, duration: CMTime(value: 1001, timescale: 60000))
        XCTAssertEqual(VideoMode.unique([a, b]).count, 2)
        XCTAssertNotEqual(a.label, b.label)
        XCTAssertTrue(b.label.contains("59.94"))
        XCTAssertEqual(VideoMode.preferred(in: [b, a])?.id, a.id)
    }
}
