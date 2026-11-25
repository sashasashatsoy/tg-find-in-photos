import UIKit

// MARK: - Matching

/// One photo from the chat that fits the description.
struct RecallResult {
    let messageId: Int
    let asset: PhotoAsset
    let author: Peer
    let date: Date
    let score: Int
    /// Tag stems that the description hit.
    let matchedTags: Set<String>

    var matchedRegions: [PhotoAsset.Region] {
        asset.regions.filter { !Set($0.tags).isDisjoint(with: matchedTags) }
    }
}

enum RecallMatcher {
    /// Words about the act of looking, not about the picture.
    private static let stopWords: Set<String> = ["где", "что", "как", "это", "был", "была", "было", "тот", "там", "мне", "про", "для", "нас", "вас", "его", "она", "они", "который", "которое", "тут", "вот", "сидит", "сидел", "лежит", "the", "was", "where", "that", "this", "with", "from", "our", "his", "her", "one", "first", "time", "very", "remember", "find", "sits", "sitting", "sat", "when", "and", "for"]
    private static let metaPrefixes = ["фот", "сним", "кадр", "карт", "phot", "pic", "shot", "imag", "snap"]

    static func normalize(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    static func tokens(_ query: String) -> [String] {
        normalize(query)
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) && !metaPrefixes.contains(where: $0.hasPrefix) }
    }

    /// Crude Russian stem for matching word forms in message text: «подоконнике» → «подоконни».
    static func stem(_ word: String) -> String {
        word.count > 5 ? String(word.prefix(word.count - 2)) : word
    }

    /// Words for the regular message search (Telegram matches every word of the query).
    static func textTokens(_ query: String) -> [String] {
        normalize(query).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 2 && !["на", "в", "и", "с", "у", "к", "по", "за", "on", "in", "at", "of", "to", "the", "a", "an", "and"].contains($0) }
    }

    static func messages(_ query: String, in store: ChatStore) -> [Message] {
        let words = textTokens(query)
        guard !words.isEmpty else { return [] }
        return store.messages.reversed().filter { message in
            guard !message.text.isEmpty else { return false }
            let messageWords = normalize(message.text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
            return words.allSatisfy { word in messageWords.contains { $0.hasPrefix(stem(word)) } }
        }
    }

    static func matches(_ word: String, _ tag: String) -> Bool {
        if tag.hasPrefix(word) { return true }
        guard word.hasPrefix(tag) else { return false }
        // Russian tags are stems («подокон»); English ones only absorb an ending («kitt» → kittens),
        // so "windowsill" doesn't count as "window".
        let latin = tag.unicodeScalars.allSatisfy { $0.isASCII }
        return !latin || word.count - tag.count <= 3
    }

    /// Words of the query the model "understood": they describe something seen on some photo.
    static func understood(_ query: String) -> Set<String> {
        let vocabulary = Set(PhotoAsset.all.flatMap(\.tags))
        return Set(tokens(query).filter { word in vocabulary.contains { matches(word, $0) } })
    }

    static func search(_ query: String, in store: ChatStore) -> [RecallResult] {
        let words = tokens(query)
        guard !words.isEmpty else { return [] }
        var results: [RecallResult] = []
        for message in store.messages {
            guard let asset = message.photoAsset else { continue }
            var score = 0
            var matched: Set<String> = []
            for word in words {
                let hits = asset.tags.filter { matches(word, $0) }
                if !hits.isEmpty {
                    score += 1
                    matched.formUnion(hits)
                }
            }
            guard score > 0 else { continue }
            let author = message.isOutgoing ? Peer.me : store.peer
            results.append(RecallResult(messageId: message.id, asset: asset, author: author, date: message.date, score: score, matchedTags: matched))
        }
        return results.sorted { $0.score != $1.score ? $0.score > $1.score : $0.date > $1.date }
    }

    /// The frame we are confident about: strictly ahead of the rest, on at least two words.
    static func leader(of results: [RecallResult]) -> RecallResult? {
        guard let first = results.first, first.score >= 2 else { return nil }
        if results.count > 1 && results[1].score == first.score { return nil }
        return first
    }
}

enum RecallFormatting {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f
    }()
    static let longDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM d 'at' HH:mm"
        return f
    }()
}

// MARK: - AI visual language

/// The multicolour light Apple Intelligence uses for "the model is looking".
enum AIPalette {
    static let colors: [UIColor] = [
        UIColor(rgb: 0xbc82f3), UIColor(rgb: 0xf5b9ea), UIColor(rgb: 0x8d9fff),
        UIColor(rgb: 0xff6778), UIColor(rgb: 0xffba71), UIColor(rgb: 0xc686ff)
    ]
    static var loop: [CGColor] { (colors + [colors[0]]).map(\.cgColor) }

    static func gradientImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(rgb: 0x8d6bff).cgColor, UIColor(rgb: 0xd45fd0).cgColor, UIColor(rgb: 0xff6778).cgColor, UIColor(rgb: 0xff9a4d).cgColor] as CFArray, locations: [0, 0.4, 0.7, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
        }
    }
}

/// A rounded outline of rotating multicolour light with a soft glow around it.
final class AIGlowBorder: UIView {
    private let container = CALayer()
    private let gradient = CAGradientLayer()
    private let shape = CAShapeLayer()
    var cornerRadius: CGFloat { didSet { setNeedsLayout() } }
    private let glow: CGFloat

    init(cornerRadius: CGFloat, lineWidth: CGFloat, glow: CGFloat) {
        self.cornerRadius = cornerRadius
        self.glow = glow
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.addSublayer(container)
        gradient.type = .conic
        gradient.colors = AIPalette.loop
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        container.addSublayer(gradient)
        shape.fillColor = nil
        shape.strokeColor = UIColor.black.cgColor
        shape.lineWidth = lineWidth
        shape.shadowColor = UIColor.black.cgColor
        shape.shadowOpacity = 1
        shape.shadowRadius = glow
        shape.shadowOffset = .zero
        container.mask = shape
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, gradient.animation(forKey: "spin") == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = CGFloat.pi * 2
        spin.duration = 2.6
        spin.repeatCount = .infinity
        gradient.add(spin, forKey: "spin")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let pad = glow * 3
        container.frame = bounds.insetBy(dx: -pad, dy: -pad)
        shape.frame = container.bounds
        shape.path = UIBezierPath(roundedRect: CGRect(x: pad, y: pad, width: bounds.width, height: bounds.height), cornerRadius: cornerRadius).cgPath
        let side = hypot(container.bounds.width, container.bounds.height)
        gradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        gradient.position = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
        CATransaction.commit()
    }

    func set(visible: Bool, duration: TimeInterval = 0.3) {
        UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = visible ? 1 : 0
        }
    }

    /// Traces the outline in, like a selection being drawn around something found.
    func drawIn(duration: TimeInterval, delay: TimeInterval) {
        alpha = 1
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = duration
        draw.beginTime = CACurrentMediaTime() + delay
        draw.fillMode = .backwards
        draw.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shape.add(draw, forKey: "draw")
    }
}

/// An SF Symbol filled with the AI gradient.
final class GradientSymbolView: UIView {
    private let gradient = CAGradientLayer()
    private let maskLayer = CALayer()
    private let image: UIImage?

    init(symbol: String, size: CGFloat, weight: UIImage.SymbolWeight = .semibold) {
        image = Icons.symbol(symbol, size: size, weight: weight, color: .black)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        gradient.colors = [UIColor(rgb: 0x8d6bff).cgColor, UIColor(rgb: 0xe060c8).cgColor, UIColor(rgb: 0xff8a5c).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradient)
        maskLayer.contents = image?.cgImage
        maskLayer.contentsGravity = .center
        maskLayer.contentsScale = image?.scale ?? screenScale
        gradient.mask = maskLayer
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { image?.size ?? .zero }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        maskLayer.frame = gradient.bounds
    }
}

/// A band of the AI light sweeping across a view: the model scanning a picture.
enum AISheen {
    static func sweep(_ view: UIView, duration: TimeInterval = 0.75, delay: TimeInterval = 0) {
        let bounds = view.bounds
        guard bounds.width > 0 else { return }
        let band = CAGradientLayer()
        band.colors = [UIColor.clear.cgColor, UIColor(rgb: 0xf5b9ea, alpha: 0.55).cgColor, UIColor(rgb: 0x8d9fff, alpha: 0.7).cgColor, UIColor(rgb: 0xffba71, alpha: 0.45).cgColor, UIColor.clear.cgColor]
        band.locations = [0, 0.3, 0.5, 0.7, 1]
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        let width = max(80, bounds.width * 0.7)
        band.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height * 2)
        band.position = CGPoint(x: bounds.width + width, y: bounds.midY)
        band.transform = CATransform3DMakeRotation(0.3, 0, 0, 1)
        band.compositingFilter = "screenBlendMode"
        view.layer.addSublayer(band)
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = -width
        move.toValue = bounds.width + width
        move.duration = duration
        move.beginTime = CACurrentMediaTime() + delay
        move.fillMode = .backwards
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        band.add(move, forKey: "sweep")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration + 0.05) { band.removeFromSuperlayer() }
    }
}

/// A word from the description, pinned to the part of the picture it matched.
final class RecallChipView: UIView {
    private let label = UILabel()
    private let icon = GradientSymbolView(symbol: "sparkle", size: 9, weight: .bold)

    init(text: String, dark: Bool = false) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = dark ? UIColor(white: 0.08, alpha: 0.72) : UIColor(white: 1, alpha: 0.92)
        layer.cornerRadius = 11
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(icon)
        label.text = text
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = dark ? .white : .black
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: ceil(label.intrinsicContentSize.width) + 28, height: 22)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        icon.frame = CGRect(x: 6, y: 0, width: 14, height: bounds.height)
        label.frame = CGRect(x: 21, y: 0, width: bounds.width - 25, height: bounds.height)
    }
}

