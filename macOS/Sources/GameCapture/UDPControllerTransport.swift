import Foundation
import CryptoKit
import Darwin

/// Per-SSH-session authenticated datagrams: uint64 sequence, JSON state, SHA256 HMAC.
final class UDPControllerTransport {
    private var descriptor: Int32 = -1
    private let key: Data
    private var sequence: UInt64 = 0
    private let version: Int
    static func packet(payload: Data, sequence: UInt64, key: Data) -> Data {
        var number = sequence.bigEndian
        var data = withUnsafeBytes(of: &number) { Data($0) }
        data.append(payload)
        data.append(contentsOf: HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
        return data
    }
    init(host: String, port: Int, key: Data, version: Int = 1) throws {
        self.version = version
        guard (1...65535).contains(port), key.count == 32 else { throw NSError(domain: "UDP", code: 1, userInfo: [NSLocalizedDescriptionKey: "파이 UDP 연결 정보가 올바르지 않습니다."]) }
        self.key = key
        var hints = addrinfo()
        hints.ai_family = AF_INET; hints.ai_socktype = SOCK_DGRAM; hints.ai_protocol = IPPROTO_UDP
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0, let address = result else {
            throw NSError(domain: "UDP", code: 2, userInfo: [NSLocalizedDescriptionKey: "파이 IPv4 주소를 찾을 수 없습니다."])
        }
        defer { freeaddrinfo(address) }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw POSIXError(.ENOBUFS) }
        // Small interactive controller packets share Wi-Fi with streamed video.
        // Request responsive traffic treatment; unsupported QoS must not prevent play.
        var serviceType = Int32(NET_SERVICE_TYPE_RV)
        _ = setsockopt(fd, SOL_SOCKET, SO_NET_SERVICE_TYPE, &serviceType,
                       socklen_t(MemoryLayout.size(ofValue: serviceType)))
        guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1,
              Darwin.connect(fd, address.pointee.ai_addr, address.pointee.ai_addrlen) == 0 else {
            let code = errno; close(fd); throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        descriptor = fd
    }
    func send(_ value: ControllerInput) throws {
        try send(version == 2 ? Self.binaryInputPayload(value) : JSONEncoder().encode(value))
    }
    static func binaryInputPayload(_ value: ControllerInput) -> Data {
        let names = ["A","B","X","Y","L","R","ZL","ZR","PLUS","MINUS","HOME","CAPTURE","L_STICK_PRESS","R_STICK_PRESS","DPAD_UP","DPAD_DOWN","DPAD_LEFT","DPAD_RIGHT"]
        var flags: UInt32 = 0
        for (index, name) in names.enumerated() where value.buttons.contains(name) { flags |= 1 << index }
        var data = Data("VGF2".utf8)
        for offset in 0..<4 { data.append(UInt8(truncatingIfNeeded: flags >> (offset * 8))) }
        for raw in [value.lx, value.ly, value.rx, value.ry] {
            let axis = raw.isFinite ? min(1, max(-1, raw)) : 0
            let word = UInt16(bitPattern: Int16((axis * (axis < 0 ? 32768 : 32767)).rounded()))
            data.append(UInt8(truncatingIfNeeded: word)); data.append(UInt8(truncatingIfNeeded: word >> 8))
        }
        return data
    }
    func send(_ payload: Data) throws {
        guard descriptor >= 0, sequence < UInt64.max else { throw POSIXError(.EBADF) }
        sequence += 1
        let data = Self.packet(payload: payload, sequence: sequence, key: key)
        let count = data.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, $0.count, 0) }
        // Loss, route changes, ICMP and the local-network permission prompt are
        // transient. The next full state repairs loss; SSH/Pi own timeouts.
        if count < 0 && [EBADF, EINVAL, EMSGSIZE].contains(errno) {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
    deinit { if descriptor >= 0 { close(descriptor) } }
}
