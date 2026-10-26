import Foundation
import Network
import CryptoKit
import Security

protocol ControllerSession: AnyObject {
    var onMessage: (@Sendable (String, String?) -> Void)? { get set }
    func send(_ value: ControllerInput)
    func stop()
}
extension SSHControllerBridge: ControllerSession {}

/// TLS authenticates and owns the session. Gameplay packets use UDP only.
final class PiControlBridge: ControllerSession, @unchecked Sendable {
    private let queue = DispatchQueue(label: "net.tarucy.controller.network", qos: .userInteractive)
    private let lock = NSLock()
    private var pending = ControllerTransitionBuffer()
    private var scheduled = false
    private var connection: NWConnection?
    private var udp: UDPControllerTransport?
    private var buffer = Data()
    private var timer: DispatchSourceTimer?
    private var active = false
    private var lastReply = ProcessInfo.processInfo.systemUptime
    private var startup = true
    private var host = ""
    private var device: PairedPi?
    var onMessage: (@Sendable (String, String?) -> Void)?

    func send(_ value: ControllerInput) {
        lock.lock()
        pending.append(value, at: ProcessInfo.processInfo.systemUptime)
        let enqueue = !scheduled; scheduled = true
        lock.unlock()
        if enqueue {
            queue.async { [self] in
                lock.lock(); scheduled = false; lock.unlock()
                flush()
            }
        }
    }
    func start(device: PairedPi, endpoint: DiscoveredPi, pair: Bool) {
        queue.async { [self] in
            guard connection == nil, let port = NWEndpoint.Port(rawValue: UInt16(exactly: endpoint.port) ?? 0), endpoint.port > 0 else { return }
            self.device = device; host = endpoint.host; active = true
            lastReply = ProcessInfo.processInfo.systemUptime
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
                let reference = sec_trust_copy_ref(trust).takeRetainedValue()
                guard let certificate = SecTrustGetCertificateAtIndex(reference, 0) else { complete(false); return }
                let der = SecCertificateCopyData(certificate) as Data
                let fingerprint = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
                complete(fingerprint == device.fingerprint)
            }, queue)
            let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
            let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: parameters)
            self.connection = connection
            connection.stateUpdateHandler = { [weak self] state in
                guard let self, self.active else { return }
                switch state {
                case .ready:
                    var request: [String: Any] = ["type": "authenticate", "client": device.client, "pair": pair]
                    if let token = PiKeychain.read(device.id + ".token") { request["token"] = token }
                    else if let pin = PiKeychain.read(device.id + ".pin") { request["pin"] = pin }
                    else { self.fail("저장된 등록 정보가 없습니다. SD 준비 정보를 다시 가져오세요."); return }
                    self.write(request); self.receive()
                case .failed(let error): self.fail("파이 연결 실패: \(error.localizedDescription)")
                case .waiting(let error): self.onMessage?("waiting", "파이 네트워크 연결을 기다리는 중입니다. \(error.localizedDescription)")
                default: break
                }
            }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: .seconds(1))
            timer.setEventHandler { [weak self] in
                guard let self, self.active else { return }
                if ProcessInfo.processInfo.systemUptime - self.lastReply > (self.startup ? 70 : 8) { self.fail("파이 응답이 없어 다시 연결합니다.") }
            }
            self.timer = timer; timer.resume()
            connection.start(queue: queue)
        }
    }
    private func write(_ value: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: value) else { return }
        data.append(10)
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error { self?.fail(error.localizedDescription) }
        })
    }
    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self, self.active else { return }
            if let data { self.parse(data) }
            guard self.active else { return }
            if let error { self.fail(error.localizedDescription) }
            else if complete { self.fail("파이 연결이 종료되어 다시 연결합니다.") }
            else { self.receive() }
        }
    }
    private func parse(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 65536 else { fail("파이 응답 형식 오류"); return }
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = message["type"] as? String else { fail("파이 응답 형식 오류"); return }
            lastReply = ProcessInfo.processInfo.systemUptime
            switch type {
            case "enrolled":
                guard let device, let token = message["token"] as? String,
                      token.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                      PiKeychain.save(token, account: device.id + ".token") else { fail("파이 연결 키를 키체인에 저장할 수 없습니다."); return }
                write(["type": "confirm"])
                PiKeychain.remove(device.id + ".pin")
                onMessage?("enrolled", nil)
            case "transport":
                guard udp == nil, let version = message["version"] as? Int, (1...2).contains(version),
                      let port = message["port"] as? Int, let encoded = message["key"] as? String,
                      let key = Data(base64Encoded: encoded) else { fail("UDP 연결 정보 오류"); return }
                do { udp = try UDPControllerTransport(host: host, port: port, key: key, version: version); flush() }
                catch { fail(error.localizedDescription); return }
            case "status":
                guard let state = message["state"] as? String else { continue }
                startup = state == "starting" || state == "waiting"
                onMessage?(state, message["backend"] as? String)
            case "error": fail(message["message"] as? String ?? "파이 연결 오류"); return
            default: fail("지원하지 않는 파이 응답입니다."); return
            }
        }
    }
    private func flush() {
        guard active, let udp else { return }
        lock.lock(); let values = pending.drain(at: ProcessInfo.processInfo.systemUptime); lock.unlock()
        for value in values {
            guard active else { break }
            do { try udp.send(value) } catch { fail(error.localizedDescription) }
        }
    }
    private func fail(_ message: String) {
        guard active else { return }
        onMessage?("error", message); finish()
    }
    private func finish() {
        active = false
        try? udp?.send(ControllerInput.neutral)
        udp = nil; timer?.cancel(); timer = nil
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        buffer = Data()
    }
    func stop() { queue.async { [self] in finish() } }
}

/// Preserve button edges during a burst; only redundant axis/heartbeat states coalesce.
/// Old backlogs collapse to their latest state instead of replaying delayed actions.
struct ControllerTransitionBuffer {
    private var items: [(ControllerInput, Double)] = []
    mutating func append(_ value: ControllerInput, at now: Double) {
        if let last = items.last, last.0.buttons == value.buttons { items.removeLast() }
        if items.count >= 32 { items.removeAll(keepingCapacity: true) }
        items.append((value, now))
    }
    mutating func drain(at now: Double) -> [ControllerInput] {
        defer { items.removeAll(keepingCapacity: true) }
        guard let last = items.last else { return [] }
        let recent = items.filter { now - $0.1 <= 0.1 }.map(\.0)
        return recent.isEmpty ? [last.0] : recent
    }
}
