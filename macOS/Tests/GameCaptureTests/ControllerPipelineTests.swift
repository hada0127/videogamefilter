import XCTest
import GameController
@testable import GameCapture

private final class RecordingControllerSession: ControllerSession, @unchecked Sendable {
    var onMessage: (@Sendable (String, String?) -> Void)?
    private let lock = NSLock()
    private var values: [ControllerInput] = []
    var onSend: ((ControllerInput) -> Void)?
    func send(_ value: ControllerInput) {
        lock.lock(); values.append(value); let callback = onSend; lock.unlock()
        callback?(value)
    }
    func stop() {}
    func drain() -> [ControllerInput] {
        lock.lock(); defer { lock.unlock() }
        let result = values; values.removeAll(); return result
    }
    func observe(_ callback: @escaping (ControllerInput) -> Void) {
        lock.lock(); onSend = callback; lock.unlock()
    }
}

final class ControllerPipelineTests: XCTestCase {
    @MainActor func testInstalledGameControllerHandlerSnapshotsBeforeLaterMutation() {
        let pipeline = ControllerInputPipeline(heartbeat: false)
        let controller = GCController.withExtendedGamepad()
        pipeline.select(controller, remote: false)
        pipeline.setApplicationActive(true)
        let session = RecordingControllerSession(); pipeline.setSession(session); _ = session.drain()
        let finished = DispatchSemaphore(value: 0)
        pipeline.queue.async {
            let pad = controller.extendedGamepad!
            // Synthetic profile setters do not emit hardware callbacks. Deliver
            // each event through the installed handler on its configured queue.
            pad.buttonA.setValue(1); pad.valueChangedHandler?(pad, pad.buttonA)
            pad.buttonA.setValue(0); pad.valueChangedHandler?(pad, pad.buttonA)
            finished.signal()
        }
        XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(session.drain(), [ControllerInput(buttons: ["A"]), .neutral])
        pipeline.setSession(nil)
    }

    @MainActor func testPressChordReleaseProgressWhileMainThreadIsBlocked() {
        XCTAssertTrue(Thread.isMainThread)
        let pipeline = ControllerInputPipeline(heartbeat: false)
        let pad = GCController.withExtendedGamepad()
        let generation = pipeline.select(pad, remote: false)
        XCTAssertTrue(pad.handlerQueue === pipeline.queue)
        pipeline.setApplicationActive(true)
        let session = RecordingControllerSession(); pipeline.setSession(session)
        _ = session.drain()
        let sequence = [ControllerInput(buttons: ["L"]), ControllerInput(buttons: ["L", "ZR"], lx: 1),
                        ControllerInput(buttons: ["ZR"], lx: 1), ControllerInput.neutral]
        let finished = DispatchSemaphore(value: 0)
        pipeline.queue.async {
            for value in sequence { pipeline.updateLocal(value, generation: generation) }
            finished.signal()
        }
        // Deliberately prevent any MainActor work from running until all edges arrive.
        XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(session.drain(), sequence)
        XCTAssertEqual(pipeline.metrics.forwardedChanges, sequence.count)
        pipeline.setSession(nil)
    }

    func testFocusSelectionAndDisconnectReleaseWithoutReplayingOldSource() {
        let pipeline = ControllerInputPipeline(heartbeat: false)
        let first = pipeline.select(GCController.withExtendedGamepad(), remote: false)
        pipeline.setApplicationActive(true)
        let session = RecordingControllerSession(); pipeline.setSession(session); _ = session.drain()
        pipeline.queue.sync { pipeline.updateLocal(ControllerInput(buttons: ["A"]), generation: first) }
        pipeline.setApplicationActive(false)
        XCTAssertEqual(session.drain(), [ControllerInput(buttons: ["A"]), .neutral])
        pipeline.queue.sync { pipeline.updateLocal(ControllerInput(buttons: ["B"]), generation: first) }
        XCTAssertTrue(session.drain().isEmpty)
        pipeline.setApplicationActive(true)
        let second = pipeline.select(GCController.withExtendedGamepad(), remote: false)
        _ = session.drain()
        pipeline.queue.sync {
            pipeline.updateLocal(ControllerInput(buttons: ["A"]), generation: first)
            pipeline.updateLocal(ControllerInput(buttons: ["B"]), generation: second)
        }
        XCTAssertEqual(session.drain(), [ControllerInput(buttons: ["B"])])
        pipeline.setSession(nil)
        XCTAssertEqual(session.drain(), [.neutral])
        pipeline.queue.sync { pipeline.updateLocal(ControllerInput(buttons: ["X"]), generation: second) }
        XCTAssertTrue(session.drain().isEmpty)
    }

    @MainActor func testRemoteBackgroundInputAndStaleReleaseDoNotNeedMainThread() {
        let pipeline = ControllerInputPipeline()
        let generation = pipeline.select(nil, remote: true)
        let session = RecordingControllerSession(); pipeline.setSession(session); _ = session.drain()
        let pressed = DispatchSemaphore(value: 0), released = DispatchSemaphore(value: 0)
        var sawPress = false
        session.observe { value in
            if value.buttons == ["A"] && !sawPress { sawPress = true; pressed.signal() }
            else if sawPress && value == .neutral { released.signal() }
        }
        let packet = MoonlightPacket(version: 1, id: 0, active: true, buttons: 0x1000,
                                     lt: 0, rt: 0, lx: 0, ly: 0, rx: 0, ry: 0)
        pipeline.receive(packet, generation: generation)
        XCTAssertEqual(pressed.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(released.wait(timeout: .now() + 2), .success)
        pipeline.setSession(nil)
    }

    @MainActor func testPulseReleasesAndAxesCoalesceWhileMainThreadIsBlocked() {
        let pipeline = ControllerInputPipeline()
        let generation = pipeline.select(GCController.withExtendedGamepad(), remote: false)
        pipeline.setApplicationActive(true)
        let session = RecordingControllerSession(); pipeline.setSession(session); _ = session.drain()
        let axisArrived = DispatchSemaphore(value: 0)
        session.observe { if $0.lx == 1 { axisArrived.signal() } }
        pipeline.queue.async {
            pipeline.updateLocal(ControllerInput(lx: 0.25), generation: generation)
            pipeline.updateLocal(ControllerInput(lx: 1), generation: generation)
        }
        XCTAssertEqual(axisArrived.wait(timeout: .now() + 2), .success)
        let released = DispatchSemaphore(value: 0)
        var sawPulse = false
        session.observe { value in
            if value.buttons == ["HOME", "L", "R"] { sawPulse = true }
            else if sawPulse && value.buttons.isEmpty { released.signal() }
        }
        pipeline.press(["HOME", "L", "R"])
        XCTAssertEqual(released.wait(timeout: .now() + 2), .success)
        pipeline.setSession(nil)
    }
}
