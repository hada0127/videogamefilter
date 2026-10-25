import SwiftUI
import MetalKit
import MetalPerformanceShaders
import CoreImage
import IOKit.graphics

/// One retained frame, one GPU submission at a time; slow rendering drops frames.
final class VideoRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let brightPipeline: MTLRenderPipelineState
    private var videoBlur: MPSImageGaussianBlur?
    private var videoBlurSigma: Float = 0
    private var softenedTexture: MTLTexture?
    private var brightTexture: MTLTexture?
    private var bloomTexture: MTLTexture?
    private var blur: MPSImageGaussianBlur?
    private var blurSigma: Float = 0
    private let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let context: CIContext
    private let lock = NSLock()
    private let inFlight = DispatchSemaphore(value: 1)
    private var latest: CVPixelBuffer?
    private var redrawPending = false
    private var enabled = false
    private var displayKey: String?
    private var nativeSize: CGSize?
    private var sourceTexture: MTLTexture?
    weak var view: MTKView?
    var settings = EffectSettings()
    var onError: ((String) -> Void)?

    init(shaderBundle: Bundle = .module) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw CaptureFailure.message("이 Mac에서 Metal 효과를 시작할 수 없습니다.") }
        self.device = device; commandQueue = queue
        context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        do {
            guard let url = shaderBundle.url(forResource: "CRT.metal", withExtension: "txt") else { throw CaptureFailure.message("CRT 셰이더 리소스가 없습니다.") }
            let library = try device.makeLibrary(source: String(contentsOf: url), options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "screenVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "screenFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            descriptor.fragmentFunction = library.makeFunction(name: "brightFragment")
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float
            brightPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch { throw CaptureFailure.message("CRT 셰이더를 준비할 수 없습니다: \(error.localizedDescription)") }
        super.init()
    }
    func setEnabled(_ value: Bool) {
        lock.lock(); enabled = value
        if !value { latest = nil }
        lock.unlock()
    }
    func submit(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        guard enabled else { lock.unlock(); return }
        latest = pixelBuffer
        let schedule = !redrawPending
        redrawPending = true
        lock.unlock()
        if schedule {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock(); self.redrawPending = false; self.lock.unlock()
                self.view?.setNeedsDisplay(self.view?.bounds ?? .zero)
            }
        }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay(view.bounds) }
    func draw(in view: MTKView) {
        lock.lock(); let pixelBuffer = enabled ? latest : nil; lock.unlock()
        guard let pixelBuffer, inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = view.currentDrawable, let command = commandQueue.makeCommandBuffer() else { inFlight.signal(); return }
        do { try encodeFrame(pixelBuffer, into: drawable.texture, settings: settings, command: command, displayTransform: displayTransform(for: view)) }
        catch { inFlight.signal(); onError?(error.localizedDescription); return }
        command.present(drawable)
        command.addCompletedHandler { [self, pixelBuffer] buffer in
            _ = pixelBuffer
            inFlight.signal()
            if buffer.status == .error { onError?(buffer.error?.localizedDescription ?? "GPU 효과 처리에 실패했습니다.") }
        }
        command.commit()
    }
    private func displayTransform(for view: MTKView) -> SIMD4<Float> {
        guard let window = view.window, let screen = window.screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let mode = CGDisplayCopyDisplayMode(number.uint32Value), view.drawableSize.width > 0, view.drawableSize.height > 0 else { return SIMD4(1, 1, 0, 0) }
        let key = "\(number.uint32Value):\(mode.ioDisplayModeID)"
        if displayKey != key {
            displayKey = key
            let modes = CGDisplayCopyAllDisplayModes(number.uint32Value, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
            let native = modes.first { $0.ioFlags & UInt32(kDisplayModeNativeFlag) != 0 }
            nativeSize = native.map { CGSize(width: $0.pixelWidth, height: $0.pixelHeight) }
        }
        guard let nativeSize, screen.frame.width > 0, screen.frame.height > 0 else { return SIMD4(1, 1, 0, 0) }
        let pointScale = CGSize(width: nativeSize.width / screen.frame.width, height: nativeSize.height / screen.frame.height)
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        return SIMD4(Float(view.bounds.width * pointScale.width / view.drawableSize.width),
                     Float(view.bounds.height * pointScale.height / view.drawableSize.height),
                     Float((rect.minX - screen.frame.minX) * pointScale.width),
                     Float((screen.frame.maxY - rect.maxY) * pointScale.height))
    }
    // Shared by live preview and off-screen GPU regression tests.
    func encodeFrame(_ pixelBuffer: CVPixelBuffer, into destination: MTLTexture, settings: EffectSettings, command: MTLCommandBuffer, displayTransform: SIMD4<Float> = SIMD4(1, 1, 0, 0)) throws {
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        if sourceTexture?.width != width || sourceTexture?.height != height {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            d.usage = [.shaderRead, .shaderWrite, .renderTarget]
            sourceTexture = device.makeTexture(descriptor: d)
        }
        guard let texture = sourceTexture else { throw CaptureFailure.message("효과용 GPU 메모리를 할당할 수 없습니다.") }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        context.render(image, to: texture, commandBuffer: command, bounds: image.extent, colorSpace: outputColorSpace)
        let s = settings.normalized
        if s.antiAliasing > 0 {
            if softenedTexture?.width != width || softenedTexture?.height != height {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
                d.usage = [.shaderRead, .shaderWrite]
                softenedTexture = device.makeTexture(descriptor: d)
            }
            guard let softenedTexture else { throw CaptureFailure.message("영상 안티앨리어싱용 GPU 메모리를 할당할 수 없습니다.") }
            let sigma = Float(0.5 + 3.5 * s.antiAliasing)
            if videoBlur == nil || sigma != videoBlurSigma {
                videoBlurSigma = sigma
                videoBlur = MPSImageGaussianBlur(device: device, sigma: sigma)
                videoBlur?.edgeMode = .clamp
            }
            videoBlur?.encode(commandBuffer: command, sourceTexture: texture, destinationTexture: softenedTexture)
        }
        if s.crt && s.glow > 0 {
            let bw = (width + 1) / 2, bh = (height + 1) / 2
            if brightTexture?.width != bw || brightTexture?.height != bh {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: bw, height: bh, mipmapped: false)
                d.usage = [.renderTarget, .shaderRead, .shaderWrite]
                brightTexture = device.makeTexture(descriptor: d)
                bloomTexture = device.makeTexture(descriptor: d)
            }
            guard let brightTexture, let bloomTexture else { throw CaptureFailure.message("빛 번짐용 GPU 메모리를 할당할 수 없습니다.") }
            let brightPass = MTLRenderPassDescriptor()
            brightPass.colorAttachments[0].texture = brightTexture
            brightPass.colorAttachments[0].loadAction = .dontCare
            brightPass.colorAttachments[0].storeAction = .store
            guard let brightEncoder = command.makeRenderCommandEncoder(descriptor: brightPass) else { throw CaptureFailure.message("빛 번짐을 추출할 수 없습니다.") }
            brightEncoder.setRenderPipelineState(brightPipeline)
            brightEncoder.setFragmentTexture(texture, index: 0)
            brightEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            brightEncoder.endEncoding()
            let fit = min(Float(destination.width)/Float(width), Float(destination.height)/Float(height))
            // Radius is ~3 sigma in final display pixels; half-resolution blur.
            let sigma = max(0.1, Float(s.glowRadius) / (3 * 2 * fit * max(0.01, displayTransform.y)))
            if blur == nil || sigma != blurSigma {
                blurSigma = sigma
                blur = MPSImageGaussianBlur(device: device, sigma: sigma)
                blur?.edgeMode = .zero
            }
            blur?.encode(commandBuffer: command, sourceTexture: brightTexture, destinationTexture: bloomTexture)
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw CaptureFailure.message("효과 렌더링을 시작할 수 없습니다.") }
        let uniforms: [SIMD4<Float>] = [
            SIMD4(Float(width), Float(height), Float(destination.width), Float(destination.height)),
            SIMD4(s.crt ? 1 : 0, Float(s.curvature), Float(s.glow), Float(s.vignette)),
            SIMD4(Float(s.mask), s.sharp ? 1 : 0, Float(s.verticalWidth), Float(s.verticalGap)),
            SIMD4(Float(s.horizontal), Float(s.vertical), Float(s.horizontalWidth), Float(s.horizontalGap)),
            displayTransform,
            SIMD4(Float(s.antiAliasing), 0, 0, 0)
        ]
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(s.crt && s.glow > 0 ? bloomTexture : texture, index: 1)
        encoder.setFragmentTexture(s.antiAliasing > 0 ? softenedTexture : texture, index: 2)
        uniforms.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

}

struct ShaderPreview: NSViewRepresentable {
    let renderer: VideoRenderer
    let settings: EffectSettings
    let enabled: Bool
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.isPaused = true; view.enableSetNeedsDisplay = true
        view.framebufferOnly = true
        view.delegate = renderer; renderer.view = view
        return view
    }
    func updateNSView(_ nsView: MTKView, context: Context) {
        renderer.settings = settings
        renderer.setEnabled(enabled)
        nsView.isHidden = !enabled
        if enabled { nsView.setNeedsDisplay(nsView.bounds) }
    }
}
