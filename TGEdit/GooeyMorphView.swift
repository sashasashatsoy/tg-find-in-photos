import UIKit
import MetalKit
import CoreImage

/// Native take on the "gooey text morphing" effect: outgoing fragments blur and fade out,
/// incoming fragments sharpen in, and an alpha threshold over both makes them melt into
/// each other like a liquid. Rendered with Core Image straight into a Metal drawable every
/// display frame (60/120 Hz), so it costs a couple of GPU passes per frame.
///
/// Differences from the web version, to make it calmer:
/// * per-word stagger (a soft wave instead of everything at once),
/// * eased progress and a capped blur radius,
/// * a soft threshold that is faded out at both ends, so the text starts and lands
///   with normal antialiasing and the hand-off to the static bitmap is invisible.
final class GooeyMorphView: MTKView {
    /// Where a fragment's rectangle lives: in the old layout (rides with its neighbours as they
    /// spring to new places), in the new layout (arrives with them), or fixed.
    enum Anchor {
        case old(CGPoint)
        case new(CGPoint)
        case fixed
    }

    struct Piece {
        let image: CIImage        // cropped from its source bitmap (CI pixel space)
        let sourceRect: CGRect    // the crop, in text coordinates (points, y down)
        let sourceHeight: CGFloat // height of the source bitmap in pixels
        let appearing: Bool
        let delay: TimeInterval
        let startRect: CGRect
        let startAnchor: Anchor
        let endRect: CGRect
        let endAnchor: Anchor
        /// Emoji are bitmaps in colour; they pop (scale + fade) on top of the liquid instead of melting.
        var isEmoji: Bool = false
    }

    private static let sharedDevice: MTLDevice? = MTLCreateSystemDefaultDevice()
    private static var sharedContext: CIContext? = {
        guard let device = sharedDevice else { return nil }
        return CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .name: "gooey"])
    }()
    private static let sharedQueue: MTLCommandQueue? = sharedDevice?.makeCommandQueue()

    static var isSupported: Bool { sharedDevice != nil }
    static let debugTiming = ProcessInfo.processInfo.environment["GOOEY_DEBUG"] != nil

    private let pieces: [Piece]
    private let region: CGRect
    private let spring: Spring
    private let pieceDuration: TimeInterval
    private let pixelScale: CGFloat
    private var startTime: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private(set) var totalDuration: TimeInterval = 0

    init(region: CGRect, pieces: [Piece], spring: Spring, pieceDuration: TimeInterval, scale: CGFloat) {
        self.pieces = pieces
        self.region = region
        self.spring = spring
        self.pieceDuration = pieceDuration
        self.pixelScale = scale
        super.init(frame: region, device: GooeyMorphView.sharedDevice)
        isUserInteractionEnabled = false
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        isOpaque = false
        layer.isOpaque = false
        backgroundColor = .clear
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        isPaused = true
        enableSetNeedsDisplay = false
        autoResizeDrawable = false
        presentsWithTransaction = true
        contentScaleFactor = scale
        drawableSize = CGSize(width: ceil(region.width * scale), height: ceil(region.height * scale))
        let maxDelay = pieces.map(\.delay).max() ?? 0
        totalDuration = maxDelay + pieceDuration
    }

    required init(coder: NSCoder) { fatalError() }

    func start() {
        startTime = CACurrentMediaTime()
        renderFrame(at: 0)
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    override func removeFromSuperview() {
        stop()
        super.removeFromSuperview()
    }

    fileprivate func tick() {
        let t = CACurrentMediaTime() - startTime
        let t0 = CACurrentMediaTime()
        renderFrame(at: t)
        if GooeyMorphView.debugTiming {
            print(String(format: "gooey t=%.3f render=%.1fms", t, (CACurrentMediaTime() - t0) * 1000))
        }
        if t > totalDuration + 0.05 { stop() }
    }

    // MARK: - Curves

    /// Analytic spring matching CASpringAnimation(perceptualDuration:bounce:), so fragments
    /// riding along with their neighbours move exactly like the Core Animation glyph layers.
    private func springProgress(_ t: TimeInterval) -> CGFloat {
        let omega = 2 * Double.pi / spring.duration
        let zeta = 1.0 - Double(spring.bounce)
        if t <= 0 { return 0 }
        if zeta >= 1 {
            return CGFloat(1 - exp(-omega * t) * (1 + omega * t))
        }
        let wd = omega * sqrt(1 - zeta * zeta)
        let envelope = exp(-zeta * omega * t)
        return CGFloat(1 - envelope * (cos(wd * t) + (zeta * omega / wd) * sin(wd * t)))
    }

    private static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func easeInOutSine(_ x: CGFloat) -> CGFloat {
        return (1 - cos(CGFloat.pi * min(max(x, 0), 1))) / 2
    }

    private func resolve(_ rect: CGRect, _ anchor: Anchor, spring sp: CGFloat) -> CGRect {
        switch anchor {
        case let .old(d): return rect.offsetBy(dx: d.x * sp, dy: d.y * sp)
        case let .new(d): return rect.offsetBy(dx: -d.x * (1 - sp), dy: -d.y * (1 - sp))
        case .fixed: return rect
        }
    }

    private static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        return CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
                      width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    // MARK: - Rendering

    /// Metaball ("liquid") rendering: every fragment is drawn into an additive density field,
    /// blurred by how "melted" it is and boosted so the blur keeps its mass; a steep alpha ramp
    /// then turns the field into solid ink. Old and new words travel towards each other while
    /// melting and solidifying, so they fuse into one drop that reshapes itself into the new text.
    private func renderFrame(at t: TimeInterval) {
        guard let context = GooeyMorphView.sharedContext,
              let queue = GooeyMorphView.sharedQueue,
              let drawable = currentDrawable,
              let commandBuffer = queue.makeCommandBuffer() else { return }

        let bounds = CGRect(origin: .zero, size: drawableSize)
        let sp = springProgress(t)
        var field = CIImage(color: .clear).cropped(to: bounds)
        let maxSigma: CGFloat = 2.1 // points
        var emojiLayer = CIImage(color: .clear).cropped(to: bounds)

        for piece in pieces {
            let p = min(max(CGFloat((t - piece.delay) / pieceDuration), 0), 1)
            let alpha: CGFloat
            let melt: CGFloat
            if piece.appearing {
                alpha = GooeyMorphView.smoothstep(0.2, 0.7, p)
                melt = 0.85 * (1 - GooeyMorphView.smoothstep(0.4, 1.0, p))
            } else {
                alpha = 1 - GooeyMorphView.smoothstep(0.25, 0.75, p)
                melt = 0.85 * GooeyMorphView.smoothstep(0.0, 0.5, p)
            }
            if alpha <= 0.002 { continue }

            let m = GooeyMorphView.easeInOutSine(p)
            let a = resolve(piece.startRect, piece.startAnchor, spring: sp)
            let b = resolve(piece.endRect, piece.endAnchor, spring: sp)
            var rect = GooeyMorphView.lerp(a, b, m)
            // A drop gathers itself while it travels.
            let squash = 1 - 0.18 * sin(CGFloat.pi * m)
            rect = rect.insetBy(dx: 0, dy: rect.height * (1 - squash) / 2)
            guard rect.width > 0.2, rect.height > 0.2 else { continue }

            let src = piece.sourceRect
            let srcX = src.minX * pixelScale
            let srcY = piece.sourceHeight - src.maxY * pixelScale
            let dstX = (rect.minX - region.minX) * pixelScale
            let dstY = (region.height - (rect.maxY - region.minY)) * pixelScale
            let transform = CGAffineTransform(translationX: -srcX, y: -srcY)
                .concatenating(CGAffineTransform(scaleX: rect.width / max(src.width, 0.01), y: rect.height / max(src.height, 0.01)))
                .concatenating(CGAffineTransform(translationX: dstX, y: dstY))
            var image = piece.image.transformed(by: transform)

            if piece.isEmoji {
                // Pop: shrink out / grow in around the centre, no blur.
                let life = piece.appearing ? GooeyMorphView.smoothstep(0.1, 0.75, p) : 1 - GooeyMorphView.smoothstep(0.0, 0.5, p)
                let scaleFactor = 0.35 + 0.65 * life + (piece.appearing ? 0.12 * sin(CGFloat.pi * life) : 0)
                let target = piece.appearing ? b : a
                let popRect = CGRect(x: target.midX - target.width * scaleFactor / 2, y: target.midY - target.height * scaleFactor / 2, width: target.width * scaleFactor, height: target.height * scaleFactor)
                let dX = (popRect.minX - region.minX) * pixelScale
                let dY = (region.height - (popRect.maxY - region.minY)) * pixelScale
                let popTransform = CGAffineTransform(translationX: -srcX, y: -srcY)
                    .concatenating(CGAffineTransform(scaleX: popRect.width / max(src.width, 0.01), y: popRect.height / max(src.height, 0.01)))
                    .concatenating(CGAffineTransform(translationX: dX, y: dY))
                let emoji = piece.image.transformed(by: popTransform).applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: life)
                ])
                emojiLayer = emoji.composited(over: emojiLayer)
                continue
            }

            let sigma = maxSigma * melt
            if sigma > 0.05 {
                image = image.applyingGaussianBlur(sigma: Double(sigma * pixelScale))
            }
            // Boost the density so a melted word stays a solid drop instead of a haze.
            let boost = 1 + 0.9 * melt
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha * boost)
            ])
            field = image.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: field])
        }

        // Steep ramp around 0.5: the density field becomes liquid ink with antialiased edges.
        let low: CGFloat = 0.5, high: CGFloat = 0.68
        let gain = 1 / (high - low)
        let ink = field
            .applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: gain),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: -low * gain)
            ])
            .applyingFilter("CIColorClamp")
        // Plain text at the very start and end, so the hand-off to crisp glyphs is invisible.
        let tt = CGFloat(t)
        let strength = GooeyMorphView.smoothstep(0.0, 0.05, tt) * (1 - GooeyMorphView.smoothstep(CGFloat(totalDuration) - 0.12, CGFloat(totalDuration), tt))
        let plain = field.applyingFilter("CIColorClamp")
        var output = strength >= 0.999 ? ink : plain.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: ink,
            kCIInputTimeKey: strength
        ])
        output = emojiLayer.composited(over: output)
        output = output.composited(over: CIImage(color: .clear).cropped(to: bounds)).cropped(to: bounds)

        context.render(output, to: drawable.texture, commandBuffer: commandBuffer, bounds: bounds, colorSpace: colorSpace)
        commandBuffer.commit()
        commandBuffer.waitUntilScheduled()
        drawable.present()
    }
}

/// Breaks the CADisplayLink → target retain cycle.
private final class DisplayLinkProxy: NSObject {
    weak var view: GooeyMorphView?
    init(_ view: GooeyMorphView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) {
        guard let view = view else { link.invalidate(); return }
        view.tick()
    }
}
