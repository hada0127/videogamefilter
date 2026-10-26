import Foundation
import GameController
import OSLog

/// GameController callbacks, remote packets and heartbeats share this queue.
/// Rendering and SwiftUI may stall the main thread without delaying gameplay.
final class ControllerInputPipeline: @unchecked Sendable {
    let queue = DispatchQueue(label: "net.tarucy.controller.input", qos: .userInteractive)
    private var controller: GCController?
    private var remote = false
    private var source = UUID()
    private var local = ControllerInput.neutral
    private var moonlight = MoonlightState()
    private var active = false
    private var positional = false
    private var session: ControllerSession?
    private var pulse: (buttons: [String], until: Double)?
    private var lastSent: ControllerInput?
    private var lastSendTime = 0.0
    private var axisWork: DispatchWorkItem?
    private var timer: DispatchSourceTimer?
    private let displayLock = NSLock()
    private var displayed = ControllerInput.neutral
    struct Metrics { var forwardedChanges = 0; var maxForwardDelayMS = 0.0 }
    private var measurements = Metrics()
    private var receivedAt: Double?
    private var lastMetricsLog = 0.0
    private let logger = Logger(subsystem: "net.tarucy.videogamefilter.native", category: "ControllerInput")

    var metrics: Metrics {
        displayLock.lock(); defer { displayLock.unlock() }
        return measurements
    }

    var displayValue: ControllerInput {
        displayLock.lock(); defer { displayLock.unlock() }
        return displayed
    }

    init(heartbeat: Bool = true) {
        if heartbeat {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.tick(heartbeat: true) }
            self.timer = timer; timer.resume()
        }
    }
    deinit { timer?.cancel(); axisWork?.cancel() }

    @discardableResult
    func select(_ selected: GCController?, remote: Bool, reset: Bool = false) -> UUID {
        queue.sync {
            guard reset || controller !== selected || self.remote != remote else { return source }
            controller?.extendedGamepad?.valueChangedHandler = nil
            source = UUID(); controller = selected; self.remote = remote
            local = .neutral; moonlight = MoonlightState(); pulse = nil
            axisWork?.cancel(); axisWork = nil; lastSent = nil; receivedAt = nil
            session?.send(.neutral)
            if let selected, let pad = selected.extendedGamepad {
                // The profile is mutable only on handlerQueue. Snapshot it here,
                // before another event can overwrite a short press/release edge.
                selected.handlerQueue = queue
                let generation = source
                pad.valueChangedHandler = { [weak self] pad, _ in
                    let received = ProcessInfo.processInfo.systemUptime
                    self?.updateLocal(ControllerInput.read(pad, positional: false), generation: generation, received: received)
                }
                local = ControllerInput.read(pad, positional: false)
            }
            tick()
            return source
        }
    }

    func updateLocal(_ value: ControllerInput, generation: UUID, received: Double = ProcessInfo.processInfo.systemUptime) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !remote, source == generation else { return }
        if local != value { receivedAt = received }
        local = value; tick()
    }

    func receive(_ packet: MoonlightPacket, generation: UUID) {
        // Timestamp before dispatch so waiting packets cannot refresh stale input.
        let received = ProcessInfo.processInfo.systemUptime
        queue.async { [weak self] in
            guard let self, self.remote, self.source == generation else { return }
            let previous = self.moonlight.current(at: received, swap: self.positional)
            self.moonlight.accept(packet, at: received)
            if self.moonlight.current(at: received, swap: self.positional) != previous { self.receivedAt = received }
            self.tick()
        }
    }

    func setApplicationActive(_ value: Bool) {
        queue.sync {
            active = value; receivedAt = nil
            if !value { pulse = nil; local = .neutral }
            else if let pad = controller?.extendedGamepad { local = ControllerInput.read(pad, positional: false) }
            tick(heartbeat: true)
        }
    }
    func setPositional(_ value: Bool) {
        queue.sync { positional = value; receivedAt = nil; tick() }
    }
    func setSession(_ value: ControllerSession?) {
        queue.sync {
            session?.send(.neutral)
            session = value; lastSent = nil; pulse = nil; receivedAt = nil
            axisWork?.cancel(); axisWork = nil
            value?.send(.neutral)
            tick()
        }
    }
    func press(_ buttons: [String]) {
        queue.sync {
            pulse = (buttons, ProcessInfo.processInfo.systemUptime + 0.15); receivedAt = nil
            tick()
        }
    }

    private func tick(heartbeat: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        var value = remote ? moonlight.current(at: now, swap: positional) : (active ? local : .neutral)
        if !remote && positional {
            value.buttons = value.buttons.map { ["A": "B", "B": "A", "X": "Y", "Y": "X"][$0] ?? $0 }
        }
        if let pulse {
            if active && pulse.until > now { value.buttons = Array(Set(value.buttons + pulse.buttons)) }
            else { self.pulse = nil }
        }
        value.buttons.sort()
        displayLock.lock(); displayed = value; displayLock.unlock()
        guard let session, heartbeat || lastSent != value else { return }
        if !heartbeat && lastSent?.buttons == value.buttons && now - lastSendTime < 0.008 {
            if axisWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    self?.axisWork = nil; self?.tick()
                }
                axisWork = work
                queue.asyncAfter(deadline: .now() + (0.008 - (now - lastSendTime)), execute: work)
            }
            return
        }
        let changed = lastSent != value
        lastSent = value; lastSendTime = now
        session.send(value)
        if changed, let receivedAt {
            let forwarded = ProcessInfo.processInfo.systemUptime
            displayLock.lock()
            measurements.forwardedChanges += 1
            measurements.maxForwardDelayMS = max(measurements.maxForwardDelayMS, (forwarded - receivedAt) * 1000)
            let summary = measurements
            displayLock.unlock()
            self.receivedAt = nil
            if forwarded - lastMetricsLog >= 5 {
                lastMetricsLog = forwarded
                logger.info("Input forwarding: changes=\(summary.forwardedChanges), max_callback_to_enqueue_ms=\(summary.maxForwardDelayMS)")
            }
        }
    }
}
