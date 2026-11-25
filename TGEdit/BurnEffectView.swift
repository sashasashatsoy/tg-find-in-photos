import UIKit

/// "Burn away" deletion, modelled on a paper-burning reference:
/// * the bubble pre-heats — a warm halo blooms around it;
/// * a ragged, fractal fire front eats it diagonally from the bottom corner, leaving islands
///   that burn out a moment later; a thin orange-white rim leads a patchy brown scorch;
/// * embers are born exactly where material burns: round glowing motes of mixed size
///   (a few large bokeh-like ones) that twinkle and slowly settle downwards;
/// * the last piece goes out with a small flare.
///
/// The front is a threshold over a precomputed fBm field, evaluated per display frame on a
/// 2pt grid and upscaled linearly (a few thousand cells, well under 1 ms). Embers are plain
/// CALayers sharing one glow bitmap.
final class BurnEffectView: UIView {
    private let haloContainer = CALayer()
    private let maskedContainer = CALayer()
    private let contentLayer = CALayer()
    private let maskLayer = CALayer()
    private let scorchLayer = CALayer()
    private let rimLayer = CALayer()
    private let emberContainer = CALayer()
    private let duration: TimeInterval
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var lastTime: CFTimeInterval = 0
    private var completion: (() -> Void)?
    private var finished = false
    private var flared = false

    private let cell: CGFloat = 2.0
    private let gridWidth: Int
    private let gridHeight: Int
    private var field: [Float] = []
    private var blotch: [Float] = []
    private var burnt: [Bool] = []
    private var lastPoint = CGPoint.zero

    private struct Ember {
        let layer: CALayer
        var position: CGPoint
        var velocity: CGPoint
        let size: CGFloat
        let born: CFTimeInterval
        let life: CFTimeInterval
        let phase: Float
        let flicker: Float
    }
    private var embers: [Ember] = []
    private var generator = SeededGenerator(seed: UInt64.random(in: 1 ... 1_000_000))

    init(image: UIImage, frame: CGRect, duration: TimeInterval = 1.35) {
        self.duration = duration
        gridWidth = max(2, Int(ceil(frame.width / 2.0)))
        gridHeight = max(2, Int(ceil(frame.height / 2.0)))
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = false

        // Halo follows whatever is left of the bubble (shadow of the masked content).
        haloContainer.frame = bounds
        haloContainer.shadowColor = UIColor(red: 1.0, green: 0.45, blue: 0.08, alpha: 1).cgColor
        haloContainer.shadowRadius = 9
        haloContainer.shadowOpacity = 0
        haloContainer.shadowOffset = .zero
        layer.addSublayer(haloContainer)

        maskedContainer.frame = bounds
        haloContainer.addSublayer(maskedContainer)
        contentLayer.contents = image.cgImage
        contentLayer.contentsScale = image.scale
        contentLayer.frame = bounds
        maskedContainer.addSublayer(contentLayer)

        scorchLayer.frame = bounds
        scorchLayer.magnificationFilter = .linear
        maskedContainer.addSublayer(scorchLayer)

        maskLayer.frame = bounds
        maskLayer.magnificationFilter = .linear
        maskedContainer.mask = maskLayer

        rimLayer.frame = bounds
        rimLayer.magnificationFilter = .linear
        rimLayer.shadowColor = UIColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 1).cgColor
        rimLayer.shadowRadius = 3
        rimLayer.shadowOpacity = 1
        rimLayer.shadowOffset = .zero
        layer.addSublayer(rimLayer)

        emberContainer.frame = bounds
        layer.addSublayer(emberContainer)

        buildFields()
        burnt = [Bool](repeating: false, count: gridWidth * gridHeight)
        renderFrame(progress: -0.08, time: 0)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Fields

    private func buildFields() {
        var rng = generator
        func lattice(_ size: Int) -> [Float] {
            (0 ..< (size + 2) * (size + 2)).map { _ in Float.random(in: 0 ... 1, using: &rng) }
        }
        func sample(_ grid: [Float], _ size: Int, _ u: Float, _ v: Float) -> Float {
            let x = min(Float(size) - 0.001, max(0, u * Float(size)))
            let y = min(Float(size) - 0.001, max(0, v * Float(size)))
            let x0 = Int(x), y0 = Int(y)
            let fx = x - Float(x0), fy = y - Float(y0)
            let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
            let s = size + 2
            let a = grid[y0 * s + x0], b = grid[y0 * s + x0 + 1]
            let c = grid[(y0 + 1) * s + x0], d = grid[(y0 + 1) * s + x0 + 1]
            return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy
        }
        // Noise lives in square space so blotches stay round on wide bubbles.
        let longest = Float(max(bounds.width, bounds.height))
        let octaves: [(Int, Float)] = [(3, 0.5), (7, 0.27), (15, 0.15), (31, 0.08)]
        let grids = octaves.map { lattice($0.0) }
        let blotchGrids = [lattice(9), lattice(19)]

        let n = gridWidth * gridHeight
        field = [Float](repeating: 0, count: n)
        blotch = [Float](repeating: 0, count: n)
        var lo: Float = .greatestFiniteMagnitude, hi: Float = -.greatestFiniteMagnitude
        for y in 0 ..< gridHeight {
            for x in 0 ..< gridWidth {
                let px = Float(x) * Float(cell), py = Float(y) * Float(cell)
                let u = px / longest, v = py / longest
                var fbm: Float = 0
                for (i, octave) in octaves.enumerated() {
                    fbm += octave.1 * sample(grids[i], octave.0, u, v)
                }
                let nu = Float(x) / Float(gridWidth - 1), nv = Float(y) / Float(gridHeight - 1)
                // Diagonal: catches at the bottom-right corner, finishes top-left.
                let ramp = 0.62 * (1 - nv) + 0.38 * (1 - nu)
                let value = 0.5 * ramp + 0.5 * fbm
                let i = y * gridWidth + x
                field[i] = value
                blotch[i] = 0.6 * sample(blotchGrids[0], 9, u, v) + 0.4 * sample(blotchGrids[1], 19, u, v)
                lo = min(lo, value); hi = max(hi, value)
            }
        }
        let range = max(hi - lo, 0.0001)
        var lastValue: Float = -1
        for i in 0 ..< n {
            field[i] = (field[i] - lo) / range
            if field[i] > lastValue {
                lastValue = field[i]
                lastPoint = CGPoint(x: CGFloat(i % gridWidth) * cell, y: CGFloat(i / gridWidth) * cell)
            }
        }
        generator = SeededGenerator(seed: UInt64.random(in: 1 ... 1_000_000))
    }

    // MARK: - Animation

    func start(completion: @escaping () -> Void) {
        self.completion = completion
        startTime = CACurrentMediaTime()
        lastTime = startTime
        // Pre-heat: a warm bloom around the bubble.
        let bloom = CABasicAnimation(keyPath: "shadowOpacity")
        bloom.fromValue = 0
        bloom.toValue = 0.85
        bloom.duration = 0.18
        haloContainer.shadowOpacity = 0.85
        haloContainer.add(bloom, forKey: "bloom")
        let link = CADisplayLink(target: BurnLinkProxy(self), selector: #selector(BurnLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    fileprivate func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - lastTime)
        lastTime = now
        let t = now - startTime
        if !finished {
            let preheat = 0.12
            let x = max(0, min(1, (t - preheat) / duration))
            // Catches slowly, then runs.
            let eased = x < 0.3 ? x * x / 0.6 : x - 0.15
            let progress = CGFloat(-0.04 + eased / 0.85 * 1.1)
            renderFrame(progress: progress, time: t)
            if !flared && progress > 0.98 {
                flared = true
                spawnFlare(at: lastPoint, now: now)
            }
            if x >= 1 {
                finished = true
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                haloContainer.isHidden = true
                rimLayer.isHidden = true
                CATransaction.commit()
                completion?()
                completion = nil
            }
        }
        updateEmbers(now: now, dt: dt)
        if finished && embers.isEmpty {
            displayLink?.invalidate()
            displayLink = nil
            removeFromSuperview()
        }
    }

    private func renderFrame(progress p: CGFloat, time: TimeInterval) {
        let w = gridWidth, h = gridHeight
        var mask = [UInt8](repeating: 0, count: w * h)
        var scorch = [UInt8](repeating: 0, count: w * h * 4)
        var rim = [UInt8](repeating: 0, count: w * h * 4)
        let pf = Float(p)
        let flickerT = Float(time) * 22
        let now = CACurrentMediaTime()
        var spawned = 0

        for y in 0 ..< h {
            for x in 0 ..< w {
                let i = y * w + x
                let flicker = 0.006 * sinf(flickerT + Float(x) * 0.9 + Float(y) * 1.7)
                let d = field[i] - pf + flicker
                mask[i] = UInt8(min(1, max(0, d / 0.012)) * 255)

                // Newly consumed cell → maybe an ember.
                if d <= 0 && !burnt[i] {
                    burnt[i] = true
                    if spawned < 14 && Float.random(in: 0 ... 1, using: &generator) < 0.05 {
                        spawnEmber(at: CGPoint(x: CGFloat(x) * cell + 1, y: CGFloat(y) * cell + 1), now: now)
                        spawned += 1
                    }
                }

                // Scorch: patchy brown stain spreading ahead of the rim.
                if d > 0 && d < 0.2 {
                    let reach = 0.07 + 0.13 * blotch[i]
                    if d < reach {
                        let k = 1 - d / reach
                        let a = min(0.9, 0.95 * k * k)
                        let o = i * 4
                        scorch[o] = UInt8(0.28 * a * 255)
                        scorch[o + 1] = UInt8(0.14 * a * 255)
                        scorch[o + 2] = UInt8(0.04 * a * 255)
                        scorch[o + 3] = UInt8(a * 255)
                    }
                }

                // Rim: thin white-gold core, orange falloff, a whisper into the burnt side.
                if d > -0.012 && d < 0.022 {
                    var r: Float = 1, g: Float = 0, b: Float = 0, a: Float = 0
                    if d < 0 {
                        let k = 1 + d / 0.012
                        g = 0.55; b = 0.12; a = k * 0.9
                    } else if d < 0.006 {
                        g = 0.9; b = 0.6; a = 1
                    } else {
                        let k = (d - 0.006) / 0.016
                        g = 0.62 - 0.3 * k; b = 0.18 - 0.14 * k; a = 1 - k
                        r = 1 - 0.25 * k
                    }
                    let o = i * 4
                    rim[o] = UInt8(min(255, r * a * 255))
                    rim[o + 1] = UInt8(min(255, g * a * 255))
                    rim[o + 2] = UInt8(min(255, b * a * 255))
                    rim[o + 3] = UInt8(min(255, a * 255))
                }
            }
        }

        let maskImage = BurnEffectView.alphaImage(mask, w, h)
        let scorchImage = BurnEffectView.rgbaImage(&scorch, w, h)
        let rimImage = BurnEffectView.rgbaImage(&rim, w, h)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.contents = maskImage
        scorchLayer.contents = scorchImage
        rimLayer.contents = rimImage
        CATransaction.commit()
    }

    private static func rgbaImage(_ bytes: inout [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        bytes.withUnsafeMutableBytes { ptr in
            CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    private static func alphaImage(_ bytes: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0 ..< w * h {
            let a = bytes[i]
            rgba[i * 4] = a; rgba[i * 4 + 1] = a; rgba[i * 4 + 2] = a; rgba[i * 4 + 3] = a
        }
        return rgbaImage(&rgba, w, h)
    }

    // MARK: - Embers

    private static let glowImage: CGImage? = {
        let size = CGSize(width: 32, height: 32)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [
                UIColor(red: 1.0, green: 0.98, blue: 0.85, alpha: 1).cgColor,
                UIColor(red: 1.0, green: 0.82, blue: 0.42, alpha: 0.95).cgColor,
                UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 0.35).cgColor,
                UIColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 0).cgColor
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.18, 0.45, 1])!
            ctx.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 16, y: 16), startRadius: 0, endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
        }.cgImage
    }()

    private func spawnEmber(at point: CGPoint, now: CFTimeInterval, size forcedSize: CGFloat? = nil, life forcedLife: CFTimeInterval? = nil) {
        guard embers.count < 170 else { return }
        let big = Float.random(in: 0 ... 1, using: &generator) < 0.16
        let size = forcedSize ?? (big ? CGFloat.random(in: 9 ... 14, using: &generator) : CGFloat.random(in: 3.5 ... 7, using: &generator))
        let layer = CALayer()
        layer.contents = BurnEffectView.glowImage
        layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        layer.position = point
        layer.opacity = 0
        layer.compositingFilter = "screenBlendMode"
        emberContainer.addSublayer(layer)
        let ember = Ember(
            layer: layer,
            position: point,
            velocity: CGPoint(x: CGFloat.random(in: -9 ... 9, using: &generator), y: CGFloat.random(in: -14 ... 2, using: &generator)),
            size: size,
            born: now,
            life: forcedLife ?? CFTimeInterval.random(in: 0.9 ... 1.7, using: &generator),
            phase: Float.random(in: 0 ... 6.28, using: &generator),
            flicker: Float.random(in: 7 ... 16, using: &generator)
        )
        embers.append(ember)
    }

    private func spawnFlare(at point: CGPoint, now: CFTimeInterval) {
        spawnEmber(at: point, now: now, size: 26, life: 0.55)
        for _ in 0 ..< 8 {
            spawnEmber(at: CGPoint(x: point.x + CGFloat.random(in: -4 ... 4, using: &generator), y: point.y), now: now, size: CGFloat.random(in: 3 ... 5, using: &generator), life: 0.8)
        }
    }

    private func updateEmbers(now: CFTimeInterval, dt: CFTimeInterval) {
        guard !embers.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var alive: [Ember] = []
        alive.reserveCapacity(embers.count)
        for var ember in embers {
            let age = now - ember.born
            if age >= ember.life {
                ember.layer.removeFromSuperlayer()
                continue
            }
            // Gentle drift that settles downwards, with air drag.
            ember.velocity.y += CGFloat(26 * dt)
            ember.velocity.x *= CGFloat(1 - 1.2 * dt)
            ember.position.x += ember.velocity.x * CGFloat(dt)
            ember.position.y += ember.velocity.y * CGFloat(dt)
            let life = Float(age / ember.life)
            let fadeIn = min(1, Float(age / 0.07))
            let fadeOut = life < 0.45 ? 1 : max(0, 1 - (life - 0.45) / 0.55)
            let twinkle = 0.72 + 0.28 * sinf(ember.phase + Float(age) * ember.flicker)
            ember.layer.position = ember.position
            ember.layer.opacity = fadeIn * fadeOut * twinkle
            let shrink = CGFloat(1 - 0.35 * life)
            ember.layer.transform = CATransform3DMakeScale(shrink, shrink, 1)
            alive.append(ember)
        }
        embers = alive
        CATransaction.commit()
    }
}

private final class BurnLinkProxy: NSObject {
    weak var view: BurnEffectView?
    init(_ view: BurnEffectView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) {
        guard let view = view else { link.invalidate(); return }
        view.tick()
    }
}
