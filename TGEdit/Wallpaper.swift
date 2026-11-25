import UIKit

/// Telegram's default chat background: a four-point "swirl" gradient that shifts one phase
/// every time a message is sent, plus a doodle pattern blended with soft light.
final class WallpaperView: UIView {
    private static let basePositions: [CGPoint] = [
        CGPoint(x: 0.80, y: 0.10),
        CGPoint(x: 0.60, y: 0.20),
        CGPoint(x: 0.35, y: 0.25),
        CGPoint(x: 0.25, y: 0.60),
        CGPoint(x: 0.20, y: 0.90),
        CGPoint(x: 0.40, y: 0.80),
        CGPoint(x: 0.65, y: 0.75),
        CGPoint(x: 0.75, y: 0.40)
    ]

    private let gradientLayer = CALayer()
    private let patternLayer = CALayer()
    private var phase = 0
    private let gradientSize = CGSize(width: 60, height: 80)
    private var tileImage: UIImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = Theme.wallpaperColors[0]
        gradientLayer.magnificationFilter = .linear
        gradientLayer.contentsGravity = .resize
        layer.addSublayer(gradientLayer)
        patternLayer.compositingFilter = "softLightBlendMode"
        patternLayer.opacity = 0.5
        layer.addSublayer(patternLayer)
        gradientLayer.contents = WallpaperView.gradientImage(size: gradientSize, positions: WallpaperView.positions(phase: 0))?.cgImage
        let tile = WallpaperView.makePatternTile()
        tileImage = tile
        patternLayer.backgroundColor = UIColor(patternImage: tile).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        patternLayer.frame = bounds
        CATransaction.commit()
    }

    /// Mirrors GradientBackgroundNode.animateEvent: morph the control points to the next phase.
    func animateToNextPhase() {
        let from = phase
        phase = (phase + 1) % 8
        let steps = 12
        var frames: [CGImage] = []
        let fromPositions = WallpaperView.positions(phase: from)
        let toPositions = WallpaperView.positions(phase: phase)
        for step in 0 ... steps {
            let t = CGFloat(step) / CGFloat(steps)
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let positions = zip(fromPositions, toPositions).map { a, b in
                CGPoint(x: a.x + (b.x - a.x) * eased, y: a.y + (b.y - a.y) * eased)
            }
            if let image = WallpaperView.gradientImage(size: gradientSize, positions: positions)?.cgImage {
                frames.append(image)
            }
        }
        guard let last = frames.last else { return }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.duration = 0.5
        animation.calculationMode = .linear
        gradientLayer.contents = last
        gradientLayer.add(animation, forKey: "phase")
    }

    private static func positions(phase: Int) -> [CGPoint] {
        var shifted = basePositions
        for _ in 0 ..< phase {
            shifted.insert(shifted.removeLast(), at: 0)
        }
        // Every second point is a colour anchor.
        return stride(from: 0, to: shifted.count, by: 2).map { shifted[$0] }
    }

    static func gradientImage(size: CGSize, positions: [CGPoint]) -> UIImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        var rgb: [Float] = []
        for color in Theme.wallpaperColors {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: nil)
            rgb.append(contentsOf: [Float(r), Float(g), Float(b)])
        }
        let points = positions.map { (Float($0.x), Float(1.0 - $0.y)) }
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0 ..< height {
            let directY = Float(y) / Float(height)
            let centerY = directY - 0.5
            for x in 0 ..< width {
                let directX = Float(x) / Float(width)
                let centerX = directX - 0.5
                let centerDistance = sqrtf(centerX * centerX + centerY * centerY)
                let swirl = 0.35 * centerDistance
                let theta = swirl * swirl * 0.8 * 8.0
                let s = sinf(theta), c = cosf(theta)
                let px = max(0, min(1, 0.5 + centerX * c - centerY * s))
                let py = max(0, min(1, 0.5 + centerX * s + centerY * c))
                var sum: Float = 0, r: Float = 0, g: Float = 0, b: Float = 0
                for i in 0 ..< points.count {
                    let dx = px - points[i].0
                    let dy = py - points[i].1
                    var d = max(0, 0.92 - sqrtf(dx * dx + dy * dy))
                    d = d * d * d
                    sum += d
                    r += d * rgb[i * 3]
                    g += d * rgb[i * 3 + 1]
                    b += d * rgb[i * 3 + 2]
                }
                sum = max(sum, 0.00001)
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8(min(255, r / sum * 255))
                bytes[offset + 1] = UInt8(min(255, g / sum * 255))
                bytes[offset + 2] = UInt8(min(255, b / sum * 255))
                bytes[offset + 3] = 255
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image)
    }

    /// A doodle tile in the spirit of Telegram's default pattern: outlined everyday objects,
    /// scattered on a jittered grid with random rotation.
    private static func makePatternTile() -> UIImage {
        let symbols = [
            "star", "heart", "cat", "pawprint", "camera", "music.note", "paperplane", "gamecontroller",
            "cloud", "moon", "sun.max", "leaf", "bicycle", "airplane", "gift", "balloon", "cup.and.saucer",
            "headphones", "umbrella", "fish", "bolt", "flame", "globe", "envelope", "bell", "key",
            "lightbulb", "puzzlepiece", "crown", "bird", "tortoise", "hare", "ladybug", "film", "book",
            "pencil", "scissors", "paintbrush", "guitars", "basketball", "football", "car", "sailboat",
            "snowflake", "drop", "sparkles", "face.smiling", "hand.thumbsup", "birthday.cake", "carrot",
            "fork.knife", "popcorn", "teddybear", "atom", "binoculars", "camera.macro", "tram", "dice",
            "theatermasks", "trophy", "graduationcap", "tent", "mountain.2", "beach.umbrella", "fossil.shell"
        ]
        let tileSize = CGSize(width: 360, height: 360)
        var generator = SeededGenerator(seed: 42)
        let renderer = UIGraphicsImageRenderer(size: tileSize)
        return renderer.image { context in
            let cg = context.cgContext
            let columns = 6
            let rows = 7
            let cellW = tileSize.width / CGFloat(columns)
            let cellH = tileSize.height / CGFloat(rows)
            var index = 0
            for row in 0 ..< rows {
                for column in 0 ..< columns {
                    let name = symbols[index % symbols.count]
                    index += 7
                    let size = CGFloat.random(in: 20 ... 28, using: &generator)
                    let config = UIImage.SymbolConfiguration(pointSize: size, weight: .light)
                    guard let image = UIImage(systemName: name, withConfiguration: config)?.withTintColor(.black, renderingMode: .alwaysOriginal) else { continue }
                    let offsetX = CGFloat(row % 2) * cellW * 0.5
                    let cx = (CGFloat(column) + 0.5) * cellW + offsetX + CGFloat.random(in: -8 ... 8, using: &generator)
                    let cy = (CGFloat(row) + 0.5) * cellH + CGFloat.random(in: -6 ... 6, using: &generator)
                    let angle = CGFloat.random(in: -0.6 ... 0.6, using: &generator)
                    for dx in [-tileSize.width, 0, tileSize.width] {
                        for dy in [-tileSize.height, 0, tileSize.height] {
                            cg.saveGState()
                            cg.translateBy(x: cx + dx, y: cy + dy)
                            cg.rotate(by: angle)
                            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
                            cg.restoreGState()
                        }
                    }
                }
            }
        }
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
