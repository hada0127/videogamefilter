import XCTest
import AppKit
@testable import GameCapture

final class CapturePointerTests: XCTestCase {
    @MainActor func testRemoteClickAcceptsMovementAndFirstMouse() {
        let view = CapturePointerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var clicks = 0
        view.onClick = { clicks += 1 }
        func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                               windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
        view.mouseUp(with: event(.leftMouseUp, NSPoint(x: 20, y: 20)))
        XCTAssertEqual(clicks, 0)
        view.mouseDown(with: event(.leftMouseDown, NSPoint(x: 20, y: 20)))
        view.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 70, y: 70)))
        view.mouseUp(with: event(.leftMouseUp, NSPoint(x: 70, y: 70)))
        XCTAssertEqual(clicks, 1)
        view.mouseDown(with: event(.leftMouseDown, NSPoint(x: 20, y: 20)))
        view.mouseUp(with: event(.leftMouseUp, NSPoint(x: 500, y: 20)))
        XCTAssertEqual(clicks, 1)
    }
}
