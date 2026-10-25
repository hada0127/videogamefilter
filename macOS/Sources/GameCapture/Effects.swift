import Foundation
import Combine

struct EffectSettings: Codable, Equatable {
    var horizontal: Double = 0
    var vertical: Double = 0
    var crt = false
    var curvature: Double = 0.12
    var glow: Double = 0.18
    var vignette: Double = 0.25
    var mask: Double = 0.15
    var sharp = false
    var horizontalWidth: Double = 2
    var horizontalGap: Double = 2
    var verticalWidth: Double = 2
    var verticalGap: Double = 2
    var glowRadius: Double = 18
    var antiAliasing: Double = 0
    enum CodingKeys: String, CodingKey { case horizontal, vertical, crt, curvature, glow, vignette, mask, sharp, horizontalWidth, horizontalGap, verticalWidth, verticalGap, glowRadius, antiAliasing }
    // Owner-approved CRT settings, captured for the native 0.3.0 release.
    static let defaultCRT = EffectSettings(horizontal: 0.20, vertical: 0.02, crt: true,
        curvature: 0, glow: 0.25, vignette: 0.46, mask: 0.38, sharp: true,
        horizontalWidth: 4, horizontalGap: 4, verticalWidth: 4, verticalGap: 4,
        glowRadius: 10, antiAliasing: 0.41)
    var normalized: EffectSettings {
        var copy = self
        func bound(_ v: Double, _ upper: Double) -> Double { v.isFinite ? min(upper, max(0, v)) : 0 }
        copy.horizontal = bound(horizontal, 0.5); copy.vertical = bound(vertical, 0.5)
        copy.curvature = bound(curvature, 0.3); copy.glow = bound(glow, 0.5)
        copy.vignette = bound(vignette, 0.7); copy.mask = bound(mask, 0.5)
        func pixels(_ v: Double) -> Double { v.isFinite ? min(16, max(1, v.rounded())) : 2 }
        copy.horizontalWidth = pixels(horizontalWidth); copy.horizontalGap = pixels(horizontalGap)
        copy.verticalWidth = pixels(verticalWidth); copy.verticalGap = pixels(verticalGap)
        copy.glowRadius = glowRadius.isFinite ? min(48, max(2, glowRadius)) : 18
        copy.antiAliasing = bound(antiAliasing, 1)
        return copy
    }
}
struct EffectPreset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var settings: EffectSettings
    init(id: UUID = UUID(), name: String, settings: EffectSettings) { self.id = id; self.name = name; self.settings = settings.normalized }
}

@MainActor final class EffectsStore: ObservableObject {
    @Published var settings: EffectSettings { didSet { persist() } }
    @Published private(set) var presets: [EffectPreset]
    @Published var selectedID: UUID? { didSet { defaults.set(selectedID?.uuidString, forKey: "effects.selected.v1") } }
    private let defaults: UserDefaults
    static let builtins: [EffectPreset] = [
        EffectPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "원본", settings: EffectSettings()),
        EffectPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "가로 스캔라인 25%", settings: EffectSettings(horizontal: 0.25)),
        EffectPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "그리드 27%", settings: EffectSettings(horizontal: 0.27, vertical: 0.27, sharp: true)),
        EffectPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "CRT · 기본", settings: .defaultCRT),
        EffectPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "CRT · 선명하게", settings: EffectSettings(horizontal: 0.15, crt: true, curvature: 0.06, glow: 0.06, vignette: 0.15, mask: 0.1, sharp: true))
    ]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "effects.settings.v1"), let loaded = try? JSONDecoder().decode(EffectSettings.self, from: data) { settings = loaded.normalized }
        else if defaults.object(forKey: "horizontalEffectPercent") != nil || defaults.object(forKey: "verticalEffectPercent") != nil { settings = EffectSettings(horizontal: defaults.double(forKey: "horizontalEffectPercent") / 100, vertical: defaults.double(forKey: "verticalEffectPercent") / 100).normalized }
        else { settings = .defaultCRT }
        if let data = defaults.data(forKey: "effects.presets.v1"), let loaded = try? JSONDecoder().decode([EffectPreset].self, from: data) {
            var ids = Set<UUID>()
            presets = loaded.filter { item in ids.insert(item.id).inserted && !Self.builtins.contains(where: { $0.id == item.id }) }.map { EffectPreset(id: $0.id, name: $0.name, settings: $0.settings) }
        } else { presets = [] }
        if defaults.data(forKey: "effects.settings.v1") == nil && settings == .defaultCRT {
            selectedID = Self.builtins[3].id
            defaults.set(selectedID?.uuidString, forKey: "effects.selected.v1")
        }
        if let raw = defaults.string(forKey: "effects.selected.v1"), let id = UUID(uuidString: raw), (Self.builtins + presets).contains(where: { $0.id == id }) { selectedID = id }
    }
    var allPresets: [EffectPreset] { Self.builtins + presets }
    var selectedIsCustom: Bool { presets.contains { $0.id == selectedID } }
    var modified: Bool { allPresets.first { $0.id == selectedID }?.settings != settings.normalized }
    func apply(_ id: UUID) {
        guard let preset = allPresets.first(where: { $0.id == id }) else { return }
        selectedID = id; settings = preset.settings
    }
    @discardableResult func save(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 60 else { return false }
        let preset = EffectPreset(name: trimmed, settings: settings)
        presets.append(preset); selectedID = preset.id; persist(); return true
    }
    func updateSelected() {
        guard let i = presets.firstIndex(where: { $0.id == selectedID }) else { return }
        presets[i].settings = settings.normalized; persist()
    }
    func deleteSelected() {
        guard selectedIsCustom else { return }
        presets.removeAll { $0.id == selectedID }; selectedID = nil; persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(settings.normalized) { defaults.set(data, forKey: "effects.settings.v1") }
        if let data = try? JSONEncoder().encode(presets) { defaults.set(data, forKey: "effects.presets.v1") }
    }
}

// Missing fields retain defaults so app updates preserve existing user presets.
extension EffectSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        horizontal = try c.decodeIfPresent(Double.self, forKey: .horizontal) ?? horizontal
        vertical = try c.decodeIfPresent(Double.self, forKey: .vertical) ?? vertical
        crt = try c.decodeIfPresent(Bool.self, forKey: .crt) ?? crt
        curvature = try c.decodeIfPresent(Double.self, forKey: .curvature) ?? curvature
        glow = try c.decodeIfPresent(Double.self, forKey: .glow) ?? glow
        glowRadius = try c.decodeIfPresent(Double.self, forKey: .glowRadius) ?? glowRadius
        antiAliasing = try c.decodeIfPresent(Double.self, forKey: .antiAliasing) ?? antiAliasing
        vignette = try c.decodeIfPresent(Double.self, forKey: .vignette) ?? vignette
        mask = try c.decodeIfPresent(Double.self, forKey: .mask) ?? mask
        sharp = try c.decodeIfPresent(Bool.self, forKey: .sharp) ?? sharp
        horizontalWidth = try c.decodeIfPresent(Double.self, forKey: .horizontalWidth) ?? horizontalWidth
        horizontalGap = try c.decodeIfPresent(Double.self, forKey: .horizontalGap) ?? horizontalGap
        verticalWidth = try c.decodeIfPresent(Double.self, forKey: .verticalWidth) ?? verticalWidth
        verticalGap = try c.decodeIfPresent(Double.self, forKey: .verticalGap) ?? verticalGap
    }
}
