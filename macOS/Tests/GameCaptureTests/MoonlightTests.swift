import XCTest
import Darwin
@testable import GameCapture

final class MoonlightTests: XCTestCase {
    func packet(id: Int = 0, active: Bool = true, buttons: UInt32 = 0, lx: Int = 0) -> MoonlightPacket {
        MoonlightPacket(version: 1, id: id, active: active, buttons: buttons, lt: 255, rt: 0, lx: lx, ly: 0, rx: 0, ry: 0)
    }
    func testSameButtonMappingAsLocalControllerAndAxes() {
        let p = packet(buttons: 0x1000 | 0x200 | 0x40, lx: -32768)
        XCTAssertEqual(p.input(swap: false).buttons, ["A","L_STICK_PRESS","R","ZL"])
        XCTAssertEqual(p.input(swap: true).buttons, ["B","L_STICK_PRESS","R","ZL"])
        XCTAssertEqual(p.input(swap: false).lx, -1)
        XCTAssertFalse(packet(id: 16).valid)
        XCTAssertFalse(packet(lx: 32768).valid)
    }
    func testPhysicalHomeAndStartSelectRemainIndependent() {
        XCTAssertEqual(packet(buttons: 0x400 | 0x1000).input(swap: false).buttons, ["A", "HOME", "ZL"])
        XCTAssertEqual(packet(buttons: 0x30).input(swap: false).buttons, ["MINUS", "PLUS", "ZL"])
    }
    func testNativeBinaryWireLayoutAndAuthentication() {
        let value = ControllerInput(buttons: ["A", "B"], lx: -1, ly: 1)
        let payload = UDPControllerTransport.binaryInputPayload(value)
        XCTAssertEqual(Array(payload), [86,71,70,50,3,0,0,0,0,128,255,127,0,0,0,0])
        let data = UDPControllerTransport.packet(payload: payload, sequence: 42, key: Data(repeating: 107, count: 32))
        XCTAssertEqual(data.count, 56)
        XCTAssertEqual(data.prefix(8), Data([0,0,0,0,0,0,0,42]))
    }
    func testNetworkBurstKeepsButtonEdgesButCoalescesAxes() {
        var q = ControllerTransitionBuffer()
        let a = packet(buttons: 0x1000).input(swap: false)
        let ax = packet(buttons: 0x1000, lx: 32767).input(swap: false)
        let ab = packet(buttons: 0x3000).input(swap: false)
        q.append(a, at: 1); q.append(ax, at: 1.001); q.append(ab, at: 1.002)
        q.append(.neutral, at: 1.003)
        XCTAssertEqual(q.drain(at: 1.01), [ax, ab, .neutral])
        XCTAssertTrue(q.drain(at: 1.02).isEmpty)
        q.append(a, at: 2); q.append(.neutral, at: 2.01)
        XCTAssertEqual(q.drain(at: 2.5), [.neutral])
    }
    func testReleaseStaleAndMultiplePads() {
        var state = MoonlightState()
        state.accept(packet(id: 1, buttons: 0x1000), at: 1)
        state.accept(packet(id: 0, buttons: 0x2000), at: 1)
        XCTAssertTrue(state.current(at: 1.1, swap: false).buttons.contains("B"))
        state.accept(packet(id: 0, active: false), at: 1.2)
        XCTAssertTrue(state.current(at: 1.2, swap: false).buttons.contains("A"))
        XCTAssertEqual(state.current(at: 1.36, swap: false), .neutral)
        state.accept(packet(id: -1), at: 2)
        XCTAssertEqual(state.current(at: 2, swap: false), .neutral)
    }
    func testPrivateSocketDeliveryAndExclusiveOwnership() throws {
        let directory = "/tmp/vgf-test-" + UUID().uuidString
        let path = directory + "/input.sock"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let receiver = MoonlightReceiver()
        let received = expectation(description: "real Unix datagram received")
        receiver.onPacket = { packet in XCTAssertEqual(packet.buttons, 0x1000); received.fulfill() }
        try receiver.start(path: path)
        defer { receiver.stop() }
        let second = MoonlightReceiver()
        XCTAssertThrowsError(try second.start(path: path))
        var info = stat(); XCTAssertEqual(lstat(path, &info), 0); XCTAssertEqual(info.st_mode & 0o777, 0o600)
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0); defer { close(fd) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let data = try JSONEncoder().encode(packet(buttons: 0x1000))
        let sent = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            } }
        }
        XCTAssertEqual(sent, data.count)
        wait(for: [received], timeout: 2)
        receiver.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        try second.start(path: path); second.stop()
    }
}
