import Foundation
import Darwin

/// Local Sunshine bridge. No LAN listener: only this macOS user's private Unix socket.
struct MoonlightPacket: Codable {
    let version: Int
    let id: Int
    let active: Bool
    let buttons: UInt32
    let lt: Int
    let rt: Int
    let lx: Int
    let ly: Int
    let rx: Int
    let ry: Int
    var valid: Bool {
        version == 1 && (0..<16).contains(id) && (0...255).contains(lt) && (0...255).contains(rt) &&
        [lx, ly, rx, ry].allSatisfy { (-32768...32767).contains($0) }
    }
    func input(swap: Bool) -> ControllerInput {
        // Preserve Moonlight/GameController button identifiers, matching local pads.
        let flags: [(UInt32, String)] = [(1,"DPAD_UP"),(2,"DPAD_DOWN"),(4,"DPAD_LEFT"),(8,"DPAD_RIGHT"),
            (0x10,"PLUS"),(0x20,"MINUS"),(0x40,"L_STICK_PRESS"),(0x80,"R_STICK_PRESS"),
            (0x100,"L"),(0x200,"R"),(0x400,"HOME"),(0x200000,"CAPTURE")]
        var pressed = flags.filter { buttons & $0.0 != 0 }.map(\.1)
        pressed += ControllerInput.faceButtons(south: buttons & 0x1000 != 0, east: buttons & 0x2000 != 0,
            west: buttons & 0x4000 != 0, north: buttons & 0x8000 != 0, positional: swap)
        if lt > 30 { pressed.append("ZL") }; if rt > 30 { pressed.append("ZR") }
        func axis(_ v: Int) -> Float { ControllerInput.axis(Float(v) / (v < 0 ? 32768 : 32767)) }
        return ControllerInput(buttons: pressed.sorted(), lx: axis(lx), ly: axis(ly), rx: axis(rx), ry: axis(ry))
    }
}

struct MoonlightState {
    private var pads: [Int: (MoonlightPacket, Double)] = [:]
    mutating func accept(_ packet: MoonlightPacket, at now: Double) {
        guard packet.valid else { return }
        if packet.active { pads[packet.id] = (packet, now) } else { pads.removeValue(forKey: packet.id) }
    }
    mutating func current(at now: Double, swap: Bool) -> ControllerInput {
        pads = pads.filter { now - $0.value.1 < 0.35 }
        guard let id = pads.keys.min(), let p = pads[id]?.0 else { return .neutral }
        return p.input(swap: swap)
    }
}

final class MoonlightReceiver: @unchecked Sendable {
    static var socketPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/VideoGameFilter/moonlight.sock").path
    }
    private let queue = DispatchQueue(label: "net.tarucy.controller.moonlight", qos: .userInteractive)
    private var source: DispatchSourceRead?
    private var path: String?
    var onPacket: (@Sendable (MoonlightPacket) -> Void)?
    func start(path: String = MoonlightReceiver.socketPath) throws {
        guard source == nil else { return }
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & 0o077 == 0 else { throw CaptureFailure.message("문라이트 입력 폴더 권한을 확인하세요.") }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw CaptureFailure.message("문라이트 입력 경로가 너무 깁니다.") }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw CaptureFailure.message("문라이트 입력을 시작할 수 없습니다.") }
        var owned = false
        defer { if !owned { close(fd) } }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK); _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        // Reclaim only a dead socket owned by this user, never a live second instance.
        if lstat(path, &info) == 0 {
            guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else { throw CaptureFailure.message("문라이트 입력 경로가 이미 사용 중입니다.") }
            let result = withUnsafePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, length) } }
            guard result < 0 && errno == ECONNREFUSED else { throw CaptureFailure.message("다른 앱 인스턴스가 문라이트 입력을 사용 중입니다.") }
            guard unlink(path) == 0 else { throw CaptureFailure.message("이전 문라이트 입력 연결을 정리할 수 없습니다.") }
        }
        let result = withUnsafePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) } }
        guard result == 0 else { throw CaptureFailure.message("문라이트 입력 소켓을 열 수 없습니다.") }
        guard chmod(path, 0o600) == 0 else { unlink(path); throw CaptureFailure.message("문라이트 입력 권한을 설정할 수 없습니다.") }
        self.path = path
        let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let callback = onPacket
        let decoder = JSONDecoder()
        reader.setEventHandler {
            var bytes = [UInt8](repeating: 0, count: 2049)
            for _ in 0..<64 {
                let count = recv(fd, &bytes, bytes.count, 0)
                if count < 0 { break }
                guard count > 0, count <= 2048,
                      let packet = try? decoder.decode(MoonlightPacket.self, from: Data(bytes.prefix(count))), packet.valid else { continue }
                callback?(packet)
            }
        }
        reader.setCancelHandler { close(fd) }
        source = reader; owned = true; reader.resume()
    }
    func stop() {
        source?.cancel(); source = nil
        if let path { unlink(path); self.path = nil }
    }
    deinit { stop() }
}
