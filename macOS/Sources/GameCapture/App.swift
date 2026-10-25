import SwiftUI
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct GameCaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var capture = CaptureModel()
    var body: some Scene {
        Window("Video Game Filter", id: "capture") {
            CaptureView(model: capture).frame(minWidth: 560, minHeight: 460)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("캡처") {
                Button(capture.running ? "중지" : "시작") { capture.running ? capture.stop() : capture.start() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(capture.busy || (!capture.running && (capture.videoID.isEmpty || capture.modeID < 0)))
                Button(capture.controlsVisible ? "설정 숨기기" : "설정 보기") { capture.controlsVisible.toggle() }
                    .keyboardShortcut(",", modifiers: .command)
                Menu("캡처 형식") {
                    Picker("캡처 형식", selection: Binding(get: { capture.modeID }, set: { capture.changeMode(to: $0) })) {
                        ForEach(capture.modes) { Text($0.label).tag($0.id) }
                    }
                }.disabled(capture.busy || capture.modes.isEmpty)
                Divider()
                Button(capture.muted ? "음소거 해제" : "음소거") { capture.muted.toggle() }.keyboardShortcut("m", modifiers: [.command, .shift])
                Menu("음량") {
                    ForEach([0, 25, 50, 75, 100], id: \.self) { value in
                        Button("\(value)%") { capture.volume = Double(value) / 100 }
                    }
                }
                Button("전체 화면") { NSApp.keyWindow?.toggleFullScreen(nil) }.keyboardShortcut("f", modifiers: [.command, .control])
                Divider()
                Text(capture.measured.isEmpty ? "프레임 수신 대기 중" : capture.measured)
            }
        }
    }
}

struct CaptureView: View {
    @ObservedObject var model: CaptureModel
    @StateObject private var effects = EffectsStore()
    @State private var cursorTask: Task<Void, Never>?
    @State private var showSave = false
    @State private var showDelete = false
    @State private var presetName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var useShader: Bool { (effects.settings.antiAliasing > 0 || effects.settings.crt || effects.settings.sharp || effects.settings.horizontal > 0 || effects.settings.vertical > 0) && model.renderer != nil && model.rendererError == nil }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black
                Preview(session: model.engine.session).opacity(model.hasFrames && !useShader ? 1 : 0)
                if let renderer = model.renderer {
                    ShaderPreview(renderer: renderer, settings: effects.settings, enabled: model.running && useShader)
                        .opacity(model.hasFrames && useShader ? 1 : 0)
                }
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { NSCursor.setHiddenUntilMouseMoves(false); model.controlsVisible.toggle() }
                    .onContinuousHover { phase in
                        cursorTask?.cancel()
                        if case .active = phase {
                            cursorTask = Task { @MainActor in
                                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                                guard !Task.isCancelled, NSApp.isActive, model.hasFrames else { return }
                                NSCursor.setHiddenUntilMouseMoves(true)
                            }
                        } else { NSCursor.setHiddenUntilMouseMoves(false) }
                    }
                if !model.hasFrames {
                    VStack(spacing: 12) {
                        Text(model.videos.isEmpty ? "캡처카드를 연결하세요" : model.status).multilineTextAlignment(.center).foregroundStyle(.white)
                        if model.busy { ProgressView().colorScheme(.dark) }
                        else if !model.videos.isEmpty { Button("시작 / 다시 시도") { model.start() }.buttonStyle(.borderedProminent) }
                    }.padding(24).frame(maxWidth: 450).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ScrollView {
                    VStack(spacing: 12) {
                        row("Video") {
                            ClassicPicker(title: "Video", selection: Binding(get: { model.videoID }, set: { model.changeVideo(to: $0) }),
                                          options: [("", "Select device")] + model.videos.map { ($0.uniqueID, $0.localizedName) }, enabled: !model.busy)
                        }
                        row("Audio") {
                            ClassicPicker(title: "Audio", selection: Binding(get: { model.audioID }, set: { model.changeAudio(to: $0) }),
                                          options: [("", "None")] + model.audios.map { ($0.uniqueID, $0.localizedName) }, enabled: !model.busy)
                        }
                        row("Resolution") {
                            ClassicPicker(title: "해상도 / 프레임률", selection: Binding(get: { model.modeID }, set: { model.changeMode(to: $0) }),
                                          options: [(-1, "Select format")] + model.modes.map { ($0.id, $0.label) }, enabled: !model.busy)
                        }
                        if !model.measured.isEmpty {
                            Text(model.measured).font(AppFonts.font(11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        Divider()
                        Group {
                        row("Preset") {
                            ClassicPicker(title: "이펙트 프리셋", selection: Binding(get: { effects.selectedID?.uuidString ?? "" }, set: { if let id = UUID(uuidString: $0) { effects.apply(id) } else { effects.selectedID = nil } }),
                                          options: [("", "직접 설정")] + effects.allPresets.map { ($0.id.uuidString, $0.name) }, enabled: true)
                        }
                        HStack(spacing: 8) {
                            if effects.selectedID != nil && effects.modified { Text("수정됨").font(AppFonts.font(11)).foregroundStyle(.secondary) }
                            Spacer()
                            Button("새 프리셋 저장") { presetName = ""; showSave = true }
                            Button("덮어쓰기") { effects.updateSelected() }.disabled(!effects.selectedIsCustom || !effects.modified)
                            Button("삭제") { showDelete = true }.disabled(!effects.selectedIsCustom)
                        }.font(AppFonts.font(12))
                        amount("Horizontal Effect", value: $effects.settings.horizontal, limit: 0.5)
                        pixels("가로 두께", value: $effects.settings.horizontalWidth)
                        pixels("가로 간격", value: $effects.settings.horizontalGap)
                        amount("Vertical Effect", value: $effects.settings.vertical, limit: 0.5)
                        pixels("세로 두께", value: $effects.settings.verticalWidth)
                        pixels("세로 간격", value: $effects.settings.verticalGap)
                        HStack {
                            Toggle("CRT 효과", isOn: $effects.settings.crt)
                            Spacer()
                            Toggle("선명한 확대", isOn: $effects.settings.sharp)
                                .help("Sharp-Shimmerless 기반 확대 필터. 캡처 영상보다 크게 표시할 때 적용되며, CRT 곡면에서는 기본 보간을 사용합니다.")
                        }.toggleStyle(.checkbox).disabled(model.renderer == nil)
                        amount("영상 안티앨리어싱", value: $effects.settings.antiAliasing, limit: 1)
                            .help("게임 영상 전체를 부드럽게 처리합니다. 강도가 높을수록 미세한 무늬와 글자도 부드러워지며, 스캔라인과 RGB 마스크는 그대로 유지합니다.")
                        if effects.settings.crt {
                            amount("화면 곡률", value: $effects.settings.curvature, limit: 0.3)
                            amount("빛 번짐 강도", value: $effects.settings.glow, limit: 0.5)
                            row("빛 번짐 반경") {
                                HStack(spacing: 8) {
                                    Slider(value: $effects.settings.glowRadius, in: 2...48, step: 1).accessibilityLabel("빛 번짐 반경")
                                    Text("\(Int(effects.settings.glowRadius)) px").monospacedDigit().frame(width: 44, alignment: .trailing)
                                }
                            }.help("밝은 영역 주변으로 퍼지는 범위입니다. 출력 화면 픽셀 기준이며, 블러의 약 3σ 반경입니다.")
                            amount("가장자리 음영", value: $effects.settings.vignette, limit: 0.7)
                            amount("RGB 마스크", value: $effects.settings.mask, limit: 0.5)
                        }
                        }.disabled(model.renderer == nil)
                        if let error = model.rendererError { Text(error).foregroundStyle(.red).font(AppFonts.font(12)) }
                    }.padding(20)
                }
                .frame(width: min(540, geometry.size.width - 32))
                .frame(height: min(effects.settings.crt ? 736 : 558, geometry.size.height - 64))
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                .environment(\.colorScheme, .light).foregroundStyle(.black)
                .padding(.bottom, 32)
                .offset(y: model.controlsVisible ? 0 : geometry.size.height)
                .disabled(!model.controlsVisible)
                .allowsHitTesting(model.controlsVisible).accessibilityHidden(!model.controlsVisible)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: model.controlsVisible)
            }.clipped()
        }
        .font(AppFonts.font(14))
        .task { model.start() }
        .onChange(of: effects.settings) { _, _ in if model.renderer != nil { model.rendererError = nil } }
        .onDisappear { cursorTask?.cancel(); NSCursor.setHiddenUntilMouseMoves(false) }
        .alert("사용자 프리셋 저장", isPresented: $showSave) {
            TextField("프리셋 이름 (최대 60자)", text: $presetName)
            Button("취소", role: .cancel) {}
            Button("저장") { _ = effects.save(name: presetName) }
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || presetName.trimmingCharacters(in: .whitespacesAndNewlines).count > 60)
        } message: { Text("스캔라인과 CRT 설정을 이 Mac에 저장합니다.") }
        .confirmationDialog("선택한 사용자 프리셋을 삭제할까요?", isPresented: $showDelete) {
            Button("삭제", role: .destructive) { effects.deleteSelected() }
        }
    }
    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 138, alignment: .leading)
            content().frame(maxWidth: .infinity).frame(height: 26)
        }
    }
    private func pixels(_ title: String, value: Binding<Double>) -> some View {
        row(title) {
            HStack(spacing: 8) {
                Slider(value: value, in: 1...16, step: 1).accessibilityLabel(title)
                Text("\(Int(value.wrappedValue)) px").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        }.help("출력 픽셀 기준입니다. 두께는 어두운 줄의 폭, 간격은 줄 사이 빈 공간이며 입력 해상도와 창 크기에 관계없이 유지됩니다.")
    }
    private func amount(_ title: String, value: Binding<Double>, limit: Double) -> some View {
        row(title) {
            HStack(spacing: 8) {
                Slider(value: value, in: 0...limit, step: 0.01).accessibilityLabel(title)
                Text(value.wrappedValue == 0 ? "None" : "\(Int((value.wrappedValue * 100).rounded()))%")
                    .monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        }
    }
}

struct ClassicPicker<Value: Hashable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]
    let enabled: Bool
    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: ClassicPicker
        var rendered: [(Value, String)] = []
        init(_ parent: ClassicPicker) { self.parent = parent }
        @objc func selectItem(_ sender: NSPopUpButton) {
            guard let value = sender.selectedItem?.representedObject as? Value,
                  parent.options.contains(where: { $0.0 == value }) else { return }
            parent.selection = value
            syncChecks(sender.menu)
        }
        func menuWillOpen(_ menu: NSMenu) { syncChecks(menu) }
        func syncChecks(_ menu: NSMenu?) {
            for item in menu?.items ?? [] {
                item.state = (item.representedObject as? Value) == parent.selection ? .on : .off
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let view = NSPopUpButton(frame: .zero, pullsDown: false)
        view.target = context.coordinator; view.action = #selector(Coordinator.selectItem(_:))
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateNSView(_ view: NSPopUpButton, context: Context) {
        configure(view, coordinator: context.coordinator)
    }
    // Shared with AppKit regression tests, including menu reopening.
    func configure(_ view: NSPopUpButton, coordinator: Coordinator) {
        coordinator.parent = self
        view.menu?.delegate = coordinator
        if !coordinator.rendered.elementsEqual(options, by: { $0.0 == $1.0 && $0.1 == $1.1 }) {
            view.removeAllItems()
            for (value, text) in options {
                // NSPopUpButton.addItem(withTitle:) merges duplicate titles.
                // Direct menu items preserve distinct preset IDs with equal names.
                let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                item.representedObject = value
                item.attributedTitle = NSAttributedString(string: text, attributes: [.font: AppFonts.native(14)])
                view.menu?.addItem(item)
            }
            coordinator.rendered = options
        }
        view.font = AppFonts.native(14)
        view.isEnabled = enabled
        view.setAccessibilityLabel(title)
        let index = options.firstIndex { $0.0 == selection } ?? -1
        if view.indexOfSelectedItem != index { view.selectItem(at: index) }
        coordinator.syncChecks(view.menu)
        view.toolTip = options.first { $0.0 == selection }?.1
    }
}

final class PreviewView: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        preview.videoGravity = .resizeAspect
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        preview.frame = bounds
        CATransaction.commit()
    }
}
struct Preview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView(frame: .zero); view.preview.session = session; return view
    }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
}
