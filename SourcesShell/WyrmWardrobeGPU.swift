import Metal
import QuartzCore
import SwiftUI
import UIKit

/// Wyrm skins in the wardrobe on the GPU (OM, 2026-10-29). Every frame the chooser asked
/// CoreGraphics for thousands of clipped gradient triangles per Wyrm skin row, so the infinite
/// list crawled and then stood still. Android draws the same native mesh with
/// `Canvas.drawVertices`; this is that: one Metal pass of vertex-coloured triangles (colours
/// interpolated per vertex exactly as the arena's ImGui does), 4x MSAA, at the screen's own
/// scale, so the skins stay sharp. The view sits under the SwiftUI Canvas, which keeps
/// drawing the bead snakes, eyes, tags and the divider above it.
final class WyrmWardrobeGPU {
    static let device = MTLCreateSystemDefaultDevice()
    private static let pipeline: MTLRenderPipelineState? = {
        guard let device else { return nil }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct Out { float4 position [[position]]; float4 colour; };
        vertex Out wyrm_mesh_vertex(const device float* v [[buffer(0)]], constant float2& size [[buffer(1)]],
                                    uint id [[vertex_id]]) {
            Out o;
            float x = v[id * 6], y = v[id * 6 + 1];
            o.position = float4(x / size.x * 2.0 - 1.0, 1.0 - y / size.y * 2.0, 0.0, 1.0);
            o.colour = float4(v[id * 6 + 2], v[id * 6 + 3], v[id * 6 + 4], v[id * 6 + 5]);
            return o;
        }
        fragment float4 wyrm_mesh_fragment(Out i [[stage_in]]) { return float4(i.colour.rgb * i.colour.a, i.colour.a); }
        """
        guard let library = try? device.makeLibrary(source: source, options: nil) else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "wyrm_mesh_vertex")
        d.fragmentFunction = library.makeFunction(name: "wyrm_mesh_fragment")
        d.rasterSampleCount = 4
        let c = d.colorAttachments[0]!
        c.pixelFormat = .bgra8Unorm
        c.isBlendingEnabled = true
        c.rgbBlendOperation = .add; c.alphaBlendOperation = .add
        c.sourceRGBBlendFactor = .one; c.sourceAlphaBlendFactor = .one
        c.destinationRGBBlendFactor = .oneMinusSourceAlpha; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: d)
    }()
    private static let queue = device?.makeCommandQueue()
    static var available: Bool { pipeline != nil && queue != nil }

    weak var view: WyrmWardrobeGPUView?
    /// x, y (canvas points), r, g, b, a per vertex; filled by the Canvas pass, drawn after it.
    private(set) var vertices: [Float] = []
    private(set) var indices: [UInt32] = []
    private var size = CGSize.zero
    private var scheduled = false
    private var shownSomething = false
    private var msaa: MTLTexture?

    init() { vertices.reserveCapacity(60_000); indices.reserveCapacity(60_000) }

    func begin(_ size: CGSize) { vertices.removeAll(keepingCapacity: true); indices.removeAll(keepingCapacity: true); self.size = size }

    /// One native mesh (WyrmSkinMesh's buffers) with a row's opacity.
    func append(xy: UnsafeBufferPointer<Float>, argb: UnsafeBufferPointer<UInt32>, vertexCount: Int,
                idx: UnsafeBufferPointer<UInt16>, indexCount: Int, opacity: Double) {
        guard vertexCount > 0, indexCount >= 3 else { return }
        let base = UInt32(vertices.count / 6), alpha = Float(min(max(opacity, 0), 1))
        for i in 0..<vertexCount {
            let c = argb[i]
            vertices.append(xy[2 * i]); vertices.append(xy[2 * i + 1])
            vertices.append(Float((c >> 16) & 255) / 255); vertices.append(Float((c >> 8) & 255) / 255)
            vertices.append(Float(c & 255) / 255); vertices.append(Float((c >> 24) & 255) / 255 * alpha)
        }
        var t = 0
        while t + 2 < indexCount {
            let a = Int(idx[t]), b = Int(idx[t + 1]), c = Int(idx[t + 2]); t += 3
            guard a < vertexCount, b < vertexCount, c < vertexCount else { continue }
            indices.append(base + UInt32(a)); indices.append(base + UInt32(b)); indices.append(base + UInt32(c))
        }
    }

    /// Called at the end of the Canvas pass: the GPU draws right after this SwiftUI commit.
    func finish() {
        guard !scheduled, !indices.isEmpty || shownSomething else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in self?.render() }
    }

    private func render() {
        scheduled = false
        guard let view, let layer = view.layer as? CAMetalLayer, let device = Self.device,
              let pipeline = Self.pipeline, let queue = Self.queue else { return }
        let bounds = view.bounds.size
        guard bounds.width > 1, bounds.height > 1 else { return }
        let scale = view.window?.screen.scale ?? UIScreen.main.scale
        let pixels = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        if layer.drawableSize != pixels { layer.drawableSize = pixels }
        if msaa?.width != Int(pixels.width) || msaa?.height != Int(pixels.height) {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(pixels.width),
                                                             height: Int(pixels.height), mipmapped: false)
            d.textureType = .type2DMultisample; d.sampleCount = 4; d.usage = .renderTarget; d.storageMode = .private
            msaa = device.makeTexture(descriptor: d)
        }
        guard let msaa, let drawable = layer.nextDrawable(), let commands = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaa
        pass.colorAttachments[0].resolveTexture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .multisampleResolve
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        if !indices.isEmpty,
           let vb = vertices.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }),
           let ib = indices.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) {
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(vb, offset: 0, index: 0)
            // The Canvas's coordinate space is the view's own bounds.
            var canvas = SIMD2<Float>(Float(size.width > 0 ? size.width : bounds.width),
                                      Float(size.height > 0 ? size.height : bounds.height))
            encoder.setVertexBytes(&canvas, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: indices.count, indexType: .uint32,
                                          indexBuffer: ib, indexBufferOffset: 0)
        }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
        shownSomething = !indices.isEmpty
    }
}

final class WyrmWardrobeGPUView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false
        if let layer = layer as? CAMetalLayer {
            layer.device = WyrmWardrobeGPU.device
            layer.pixelFormat = .bgra8Unorm
            layer.isOpaque = false
            layer.framebufferOnly = true
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            layer.contentsScale = UIScreen.main.scale
        }
    }
    required init?(coder: NSCoder) { return nil }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let screen = window?.screen { layer.contentsScale = screen.scale }
    }
}

struct WyrmWardrobeGPULayer: UIViewRepresentable {
    let gpu: WyrmWardrobeGPU
    func makeUIView(context: Context) -> WyrmWardrobeGPUView {
        let view = WyrmWardrobeGPUView(frame: .zero); gpu.view = view; return view
    }
    func updateUIView(_ view: WyrmWardrobeGPUView, context: Context) { gpu.view = view }
}
