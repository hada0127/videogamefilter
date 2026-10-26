import XCTest
import SwiftUI
import AppKit
import CoreText
import MetalKit
import CoreVideo
@testable import GameCapture

final class EffectsTests: XCTestCase {
    @MainActor func testUserPresetRoundTripUpdateAndDelete() async throws {
        let name = "GameCaptureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = EffectsStore(defaults: defaults)
        store.settings = EffectSettings(horizontal: 0.27, vertical: 0.19, crt: true, curvature: 0.08, horizontalWidth: 3, horizontalGap: 5, verticalWidth: 2, verticalGap: 7, glowRadius: 31, antiAliasing: 0.42)
        XCTAssertTrue(store.save(name: "  내 CRT  "))
        let id = try XCTUnwrap(store.selectedID)
        let expected = store.settings
        let restored = EffectsStore(defaults: defaults)
        XCTAssertEqual(restored.selectedID, id)
        XCTAssertEqual(restored.settings, expected)
        XCTAssertEqual(restored.presets.first?.name, "내 CRT")
        restored.settings.glow = 0.4
        XCTAssertTrue(restored.modified)
        restored.updateSelected()
        XCTAssertFalse(restored.modified)
        XCTAssertEqual(EffectsStore(defaults: defaults).presets.first?.settings.glow, 0.4)
        restored.deleteSelected()
        XCTAssertTrue(EffectsStore(defaults: defaults).presets.isEmpty)
        XCTAssertNil(EffectsStore(defaults: defaults).selectedID)
        restored.apply(EffectsStore.builtins[0].id)
        restored.deleteSelected()
        XCTAssertEqual(restored.allPresets.count, EffectsStore.builtins.count)
        XCTAssertFalse(restored.save(name: "   "))
        XCTAssertFalse(restored.save(name: String(repeating: "x", count: 61)))
    }
    @MainActor func testReleaseDefaultCRTAndExistingSettingsArePreserved() async throws {
        let name = "GameCaptureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = EffectsStore(defaults: defaults)
        let expected = EffectSettings(horizontal: 0.2, vertical: 0.02, crt: true, curvature: 0, glow: 0.25, vignette: 0.46, mask: 0.38, sharp: true, horizontalWidth: 4, horizontalGap: 4, verticalWidth: 4, verticalGap: 4, glowRadius: 10, antiAliasing: 0.41)
        XCTAssertEqual(store.settings, expected)
        XCTAssertEqual(EffectsStore.builtins[3].settings, expected)
        XCTAssertEqual(store.selectedID, EffectsStore.builtins[3].id)
        store.settings = EffectSettings(horizontal: 0.11, glowRadius: 33)
        XCTAssertEqual(EffectsStore(defaults: defaults).settings, store.settings)
        XCTAssertEqual(EffectsStore(defaults: defaults).selectedID, store.selectedID)
        defaults.removeObject(forKey: "effects.settings.v1")
        defaults.set(15, forKey: "horizontalEffectPercent")
        XCTAssertEqual(EffectsStore(defaults: defaults).settings.horizontal, 0.15)
    }
    @MainActor func testPresetMenuKeepsOneCheckAndDistinctDuplicateNames() async throws {
        var selected = "horizontal"
        let options = [("horizontal", "가로 스캔라인 25%"), ("grid", "그리드 27%"), ("a", "고전게임"), ("b", "고전게임")]
        let picker = ClassicPicker(title: "Preset", selection: Binding(get: { selected }, set: { selected = $0 }), options: options, enabled: true)
        let coordinator = picker.makeCoordinator()
        let view = TouchPopUpButton(frame: .zero, pullsDown: false)
        view.cell = TouchPopUpCell(textCell: "", pullsDown: false)
        XCTAssertGreaterThanOrEqual(view.intrinsicContentSize.height, 72)
        picker.configure(view, coordinator: coordinator)
        XCTAssertEqual(view.numberOfItems, 4)
        XCTAssertEqual(view.itemTitles.filter { $0 == "고전게임" }.count, 2)
        let menu = try XCTUnwrap(view.menu)
        // Reproduce the reported stale second check on an unselected builtin.
        menu.items[1].state = .on
        coordinator.menuWillOpen(menu)
        XCTAssertEqual(menu.items.filter { $0.state == .on }.count, 1)
        XCTAssertEqual(menu.items[0].state, .on)
        for i in [1, 3, 2, 0] {
            view.selectItem(at: i)
            coordinator.selectItem(view)
            picker.configure(view, coordinator: coordinator)
            coordinator.menuWillOpen(menu)
            XCTAssertEqual(selected, options[i].0)
            XCTAssertEqual(menu.items.filter { $0.state == .on }.count, 1)
            XCTAssertEqual(menu.items[i].state, .on)
        }
        selected = "grid" // programmatic restoration, not a menu click
        picker.configure(view, coordinator: coordinator)
        XCTAssertEqual(view.indexOfSelectedItem, 1)
        XCTAssertEqual(menu.items.filter { $0.state == .on }.count, 1)
    }
    @MainActor func testVerticalCRTMatchesDefaultWithSwappedScanlines() {
        var expected = EffectSettings.defaultCRT
        expected.horizontal = EffectSettings.defaultCRT.vertical
        expected.vertical = EffectSettings.defaultCRT.horizontal
        expected.horizontalWidth = EffectSettings.defaultCRT.verticalWidth
        expected.verticalWidth = EffectSettings.defaultCRT.horizontalWidth
        expected.horizontalGap = EffectSettings.defaultCRT.verticalGap
        expected.verticalGap = EffectSettings.defaultCRT.horizontalGap
        XCTAssertEqual(EffectSettings.verticalCRT, expected)
        XCTAssertEqual(EffectsStore.builtins.first { $0.name == "CRT · 기본 (세로)" }?.settings, expected)
        XCTAssertEqual(Set(EffectsStore.builtins.map(\.id)).count, EffectsStore.builtins.count)
    }
    func testExistingPresetsWithoutLineCountMigrate() throws {
        let json = #"{"horizontal":0.5,"vertical":0.2,"crt":true,"curvature":0.03,"glow":0.18,"vignette":0.25,"mask":0.15,"sharp":false}"#
        let value = try JSONDecoder().decode(EffectSettings.self, from: Data(json.utf8))
        XCTAssertEqual(value.horizontalWidth, 2)
        XCTAssertEqual(value.horizontal, 0.5)
        XCTAssertEqual(value.curvature, 0.03)
        XCTAssertEqual(value.glowRadius, 18)
        XCTAssertEqual(value.antiAliasing, 0)
    }
    func testInvalidEffectValuesAreClamped() {
        let value = EffectSettings(horizontal: .infinity, vertical: -1, curvature: 10, glow: 5, horizontalWidth: .nan).normalized
        XCTAssertEqual(value.horizontal, 0)
        XCTAssertEqual(value.vertical, 0)
        XCTAssertEqual(value.curvature, 0.3)
        XCTAssertEqual(value.glow, 0.5)
        XCTAssertEqual(value.horizontalWidth, 2)
    }
    func testHadaSansLoadsFromAppBundle() throws {
        let font = AppFonts.native(14)
        XCTAssertEqual(font.fontName, "HadaSans-Regular")
        let url = try XCTUnwrap(CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL)
        XCTAssertTrue(url.path.contains("GameCapture_GameCapture.bundle"), url.path)
    }

    private func render(_ settings: EffectSettings, width: Int = 64, height: Int = 64, solid: Bool = false, sourceSize: Int = 64, displayTransform: SIMD4<Float> = SIMD4(1, 1, 0, 0), spot: UInt8? = nil, diagonal: Bool = false, fineTexture: Bool = false) throws -> [UInt8] {
        let renderer = try VideoRenderer()
        let attrs = [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, sourceSize, sourceSize, kCVPixelFormatType_32BGRA, attrs, &buffer), kCVReturnSuccess)
        let pixel = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixel, [])
        let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        for y in 0..<sourceSize { for x in 0..<sourceSize {
            let i = y * stride + x * 4
            base[i] = solid || y >= sourceSize / 2 ? 255 : 0
            base[i+1] = solid ? 255 : 0
            base[i+2] = solid || y < sourceSize / 2 ? 255 : 0
            if let spot {
                let lit = x >= sourceSize*3/8 && x < sourceSize*5/8 && y >= sourceSize*3/8 && y < sourceSize*5/8
                for c in 0..<3 { base[i+c] = lit ? spot : 0 }
            }
            if diagonal { for c in 0..<3 { base[i+c] = x > y ? 255 : 0 } }
            if fineTexture { for c in 0..<3 { base[i+c] = (x+y)%2 == 0 ? 100 : 112 } }
            base[i+3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead]
        let texture = try XCTUnwrap(renderer.device.makeTexture(descriptor: descriptor))
        let queue = try XCTUnwrap(renderer.device.makeCommandQueue())
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        try renderer.encodeFrame(pixel, into: texture, settings: settings, command: command, displayTransform: displayTransform)
        command.commit(); command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed, command.error?.localizedDescription ?? "")
        var bytes = [UInt8](repeating: 0, count: width*height*4)
        bytes.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: width*4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
        return bytes
    }
    func testWholeVideoAAIsAdjustableAndLeavesCRTGridUnfiltered() throws {
        var settings = EffectSettings(horizontal: 0.5, vertical: 0.5, crt: true, curvature: 0, glow: 0, vignette: 0, mask: 0.15)
        let noAA = try render(settings, solid: true)
        settings.antiAliasing = 1
        XCTAssertEqual(noAA, try render(settings, solid: true), "AA must not soften the output CRT pattern")
        let original = try render(EffectSettings(), diagonal: true)
        let full = try render(EffectSettings(antiAliasing: 1), diagonal: true)
        let half = try render(EffectSettings(antiAliasing: 0.5), diagonal: true)
        XCTAssertNotEqual(original, full, "AA must change stair-stepped video edges")
        var blended = 0
        for i in stride(from: 0, to: full.count, by: 4) {
            XCTAssertGreaterThanOrEqual(Int(half[i]), min(Int(original[i]), Int(full[i])) - 1)
            XCTAssertLessThanOrEqual(Int(half[i]), max(Int(original[i]), Int(full[i])) + 1)
            if full[i] > 5 && full[i] < 250 { blended += 1 }
        }
        XCTAssertGreaterThan(blended, 20)
        let texture = try render(EffectSettings(antiAliasing: 1), fineTexture: true)
        let i = (32*64+32)*4
        XCTAssertGreaterThan(texture[i], 103, "Whole-image smoothing must affect low-contrast texture, not just selected edges")
        XCTAssertLessThan(texture[i+4], 109)
    }
    func testBloomSpreadsHighlightsAndSeparatesRadiusFromStrength() throws {
        var settings = EffectSettings(crt: true, curvature: 0, glow: 0, vignette: 0, mask: 0, glowRadius: 18)
        let off = try render(settings, spot: 255)
        settings.glow = 0.25
        let medium = try render(settings, spot: 255)
        settings.glow = 0.5
        let strong = try render(settings, spot: 255)
        let halo = (32*64+19)*4
        XCTAssertEqual(off[halo], 0)
        XCTAssertGreaterThan(medium[halo], 8, "Light must spread beyond the bright square")
        XCTAssertGreaterThan(strong[halo], medium[halo])
        settings.glowRadius = 4
        let narrow = try render(settings, spot: 255)
        XCTAssertLessThan(narrow[halo], medium[halo])
        settings.glowRadius = 18
        let dark = try render(settings, spot: 96)
        settings.glow = 0
        XCTAssertEqual(dark, try render(settings, spot: 96), "Dark input must not turn into a global haze")
        XCTAssertEqual(strong[(32*64+32)*4], off[(32*64+32)*4], "White core should remain white")
    }
    func testCRTAndSharpKeepTopAndBottomUpright() throws {
        for setting in [EffectSettings(crt: true, curvature: 0, glow: 0, vignette: 0, mask: 0), EffectSettings(sharp: true)] {
            let bytes = try render(setting)
            let top = (8*64+32)*4, bottom = (55*64+32)*4
            XCTAssertGreaterThan(bytes[top+2], 220, "Top must remain red")
            XCTAssertLessThan(bytes[top], 20)
            XCTAssertGreaterThan(bytes[bottom], 220, "Bottom must remain blue")
            XCTAssertLessThan(bytes[bottom+2], 20)
        }
    }

    func testMaskAndVerticalLinesKeepBalancedColorAndBrightnessAcrossSizes() throws {
        for size in [720, 960, 1200] {
            let bytes = try render(EffectSettings(horizontal: 0.5, vertical: 0.5, crt: true, curvature: 0, glow: 0, vignette: 0, mask: 0.3, horizontalWidth: Double(size / 240), horizontalGap: Double(size / 240), verticalWidth: Double(size / 240), verticalGap: Double(size / 240)), width: size, height: size, solid: true)
            let period = max(4, 2 * Int((Double(size) / 120 / 2).rounded()))
            var sums = [Double](repeating: 0, count: 3)
            for y in 0..<period { for x in 0..<(period * 3) { for c in 0..<3 { sums[c] += Double(bytes[(y*size+x)*4+c]) } } }
            let count = Double(period * period * 3)
            for c in 0..<3 { XCTAssertEqual(sums[c] / count, 255 * 0.75 * 0.75 * 0.8, accuracy: 1) }
        }
    }
    func testScaledDisplayIntegratesBandsInPhysicalPixelSpace() throws {
        let settings = EffectSettings(horizontal: 0.5, vertical: 0.25, horizontalWidth: 2, horizontalGap: 3, verticalWidth: 1, verticalGap: 6)
        let bytes = try render(settings, solid: true, displayTransform: SIMD4(0.75, 0.75, 0.25, 0.5))
        // Independent numerical integration, not the shader antiderivative.
        func coverage(_ center: Double, _ period: Int, _ width: Int) -> Double {
            var dark = 0
            for i in 0..<300 {
                let x = center - 0.375 + (Double(i)+0.5) * 0.75/300
                let phase = x - floor(x/Double(period))*Double(period)
                if phase < Double(width) { dark += 1 }
            }
            return Double(dark)/300
        }
        for y in 0..<64 { for x in 0..<64 {
            let h = coverage((Double(y)+0.5)*0.75+0.5, 5, 2)
            let v = coverage((Double(x)+0.5)*0.75+0.25, 7, 1)
            XCTAssertEqual(Double(bytes[(y*64+x)*4]), 255*(1-0.5*h)*(1-0.25*v), accuracy: 1)
        } }
    }
    func testFineMaskIsPixelIntegratedAndDoesNotMultiplyLinePattern() throws {
        for scale: Float in [1, 0.75, 2] {
            let settings = EffectSettings(horizontal: 0.5, vertical: 0.5, crt: true, curvature: 0, glow: 0, vignette: 0, mask: 0.5)
            let withMask = try render(settings, solid: true, displayTransform: SIMD4(scale, scale, 0, 0))
            var plain = settings; plain.mask = 0
            let withoutMask = try render(plain, solid: true, displayTransform: SIMD4(scale, scale, 0, 0))
            let fp = Double(scale)
            let omega = 2 * Double.pi / (3 * max(1, ceil(fp)))
            let sinc = sin(omega*fp/2)/(omega*fp/2)
            for x in 0..<64 {
                // B channel is the third phase; scanline mean is 0.75 squared.
                let phase = omega*(Double(x)+0.5)*fp - 4*Double.pi/3
                let expected = Double(withoutMask[x*4]) * (1-0.5*2/3) + 255*0.5*cos(phase)*sinc/3*0.75*0.75
                XCTAssertEqual(Double(withMask[x*4]), expected, accuracy: 1)
            }
        }
    }
    func testIndependentHorizontalAndVerticalThicknessAndGap() throws {
        let settings = EffectSettings(horizontal: 0.5, vertical: 0.25, horizontalWidth: 2, horizontalGap: 3, verticalWidth: 1, verticalGap: 6)
        let bytes = try render(settings, solid: true)
        for y in 0..<64 { for x in 0..<64 {
            let expected = 255.0 * (y % 5 < 2 ? 0.5 : 1) * (x % 7 < 1 ? 0.75 : 1)
            XCTAssertEqual(Double(bytes[(y*64+x)*4]), expected, accuracy: 1)
        } }
    }
    func testScanlinesAreVisibleAndPixelAlignedAtDifferentDrawableSizes() throws {
        for source in [64, 256, 1080] {
        for size in [64, 127, 256, 1024] {
            let bytes = try render(EffectSettings(horizontal: 0.5, vertical: 0, horizontalWidth: 3, horizontalGap: 3), width: size, height: size, solid: true, sourceSize: source)
            // Even periods have 50% duty cycle; six physical pixels regardless of input or output resolution.
            let dark = bytes[(0*size+size/2)*4], light = bytes[(3*size+size/2)*4]
            XCTAssertLessThan(dark, 180)
            XCTAssertGreaterThan(light, 240)
            XCTAssertEqual(bytes[(6*size+size/2)*4], dark, accuracy: 1)
        }
        }
    }
}
