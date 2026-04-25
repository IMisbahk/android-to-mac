import AppKit
import CoreVideo
import Metal
import MetalKit

/// Renders decoded CVPixelBuffers using Metal for low-latency display.
class VideoRenderer: NSView {
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var metalLayer: CAMetalLayer?
    private var pipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private var vertexBuffer: MTLBuffer?

    // Video dimensions from config
    private(set) var videoWidth: Int = 0
    private(set) var videoHeight: Int = 0

    // Latest frame for display
    private var latestPixelBuffer: CVPixelBuffer?
    private let frameLock = NSLock()

    // FPS tracking
    private var frameCount: Int = 0
    private var lastFPSTime: CFAbsoluteTime = 0
    private(set) var currentFPS: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMetal()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
    }

    override var wantsUpdateLayer: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = metalDevice
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer.displaySyncEnabled = true
        metalLayer = layer
        return layer
    }

    func configure(width: Int, height: Int) {
        videoWidth = width
        videoHeight = height
    }

    func displayFrame(_ pixelBuffer: CVPixelBuffer) {
        frameLock.lock()
        latestPixelBuffer = pixelBuffer
        frameLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.renderFrame()
        }
    }

    // MARK: - Metal Setup

    private func setupMetal() {
        wantsLayer = true

        guard let device = MTLCreateSystemDefaultDevice() else {
            Log.error("Metal not available")
            return
        }
        metalDevice = device
        commandQueue = device.makeCommandQueue()

        // Create texture cache
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        textureCache = cache

        // Create vertex buffer (full-screen quad)
        let vertices: [Float] = [
            -1, -1, 0, 1,
             1, -1, 1, 1,
            -1,  1, 0, 0,
             1,  1, 1, 0,
        ]
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.stride)

        // Create shader pipeline
        setupPipeline(device: device)
    }

    private func setupPipeline(device: MTLDevice) {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut vertexShader(uint vid [[vertex_id]],
                                       constant float4 *vertices [[buffer(0)]]) {
            VertexOut out;
            out.position = float4(vertices[vid].xy, 0, 1);
            out.texCoord = vertices[vid].zw;
            return out;
        }

        fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                        texture2d<float> tex [[texture(0)]]) {
            constexpr sampler s(filter::linear);
            return tex.sample(s, in.texCoord);
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunc = library.makeFunction(name: "vertexShader")
            let fragFunc = library.makeFunction(name: "fragmentShader")

            let pipelineDesc = MTLRenderPipelineDescriptor()
            pipelineDesc.vertexFunction = vertexFunc
            pipelineDesc.fragmentFunction = fragFunc
            pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            Log.error("Failed to create Metal pipeline: \(error)")
        }
    }

    // MARK: - Rendering

    private func renderFrame() {
        frameLock.lock()
        guard let pixelBuffer = latestPixelBuffer else {
            frameLock.unlock()
            return
        }
        frameLock.unlock()

        guard let metalLayer = metalLayer,
              let device = metalDevice,
              let commandQueue = commandQueue,
              let pipelineState = pipelineState,
              let textureCache = textureCache,
              let vertexBuffer = vertexBuffer else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Create Metal texture from pixel buffer
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTex = cvTexture else { return }
        guard let metalTexture = CVMetalTextureGetTexture(cvTex) else { return }

        // Update layer size
        metalLayer.drawableSize = CGSize(width: self.bounds.width * metalLayer.contentsScale,
                                          height: self.bounds.height * metalLayer.contentsScale)

        guard let drawable = metalLayer.nextDrawable() else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDesc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else { return }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(metalTexture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        // FPS tracking
        frameCount += 1
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastFPSTime >= 1.0 {
            currentFPS = Double(frameCount) / (now - lastFPSTime)
            frameCount = 0
            lastFPSTime = now
        }
    }
}
