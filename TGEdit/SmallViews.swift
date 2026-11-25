import UIKit

/// Initials on a Telegram avatar gradient.
final class AvatarView: UIView {
    private let gradient = CAGradientLayer()
    private let label = UILabel()

    init(peer: Peer, fontSize: CGFloat, rounded: Bool = false) {
        super.init(frame: .zero)
        let colors = Theme.avatarGradients[peer.colorIndex % Theme.avatarGradients.count]
        gradient.colors = [UIColor(rgb: colors.0).cgColor, UIColor(rgb: colors.1).cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradient)
        label.text = peer.initials
        label.textColor = .white
        let base = UIFont.systemFont(ofSize: fontSize, weight: rounded ? .bold : .semibold)
        if rounded, let descriptor = base.fontDescriptor.withDesign(.rounded) {
            label.font = UIFont(descriptor: descriptor, size: fontSize)
        } else {
            label.font = base
        }
        label.textAlignment = .center
        addSubview(label)
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
        label.frame = bounds
        layer.cornerRadius = bounds.width / 2
    }
}

enum Icons {
    /// Telegram-style delivery checks. `read` adds the second (partial) check.
    static func checks(read: Bool, color: UIColor) -> UIImage {
        let size = CGSize(width: read ? 16.0 : 11.5, height: 10.0)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            color.setStroke()
            let first = UIBezierPath()
            first.move(to: CGPoint(x: 1.0, y: 5.4))
            first.addLine(to: CGPoint(x: 4.0, y: 8.4))
            first.addLine(to: CGPoint(x: 10.4, y: 1.4))
            first.lineWidth = 1.33
            first.lineCapStyle = .round
            first.lineJoinStyle = .round
            first.stroke()
            if read {
                let second = UIBezierPath()
                second.move(to: CGPoint(x: 7.0, y: 7.6))
                second.addLine(to: CGPoint(x: 7.8, y: 8.4))
                second.addLine(to: CGPoint(x: 14.6, y: 1.4))
                second.lineWidth = 1.33
                second.lineCapStyle = .round
                second.lineJoinStyle = .round
                second.stroke()
            }
        }
    }

    static func symbol(_ name: String, size: CGFloat, weight: UIImage.SymbolWeight = .regular, color: UIColor) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: weight)
        return UIImage(systemName: name, withConfiguration: config)?.withTintColor(color, renderingMode: .alwaysOriginal)
    }

    /// iOS-style back chevron as used by Telegram's navigation bar.
    static func backChevron(color: UIColor) -> UIImage {
        let size = CGSize(width: 13, height: 22)
        return UIGraphicsImageRenderer(size: size).image { _ in
            color.setStroke()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 11.0, y: 1.5))
            path.addLine(to: CGPoint(x: 1.8, y: 11.0))
            path.addLine(to: CGPoint(x: 11.0, y: 20.5))
            path.lineWidth = 3.0
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }
}

/// Delivery status: "изменено 09:55 ✓✓".
final class StatusView: UIView {
    let label = UILabel()
    private let checksView = UIImageView()
    private(set) var text = ""
    private var outgoing = false
    private var read = false

    static let height: CGFloat = 14.0
    static let checksGap: CGFloat = 3.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        label.font = Theme.dateFont
        label.contentMode = .left
        addSubview(label)
        checksView.contentMode = .left
        addSubview(checksView)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func width(text: String, outgoing: Bool, read: Bool) -> CGFloat {
        let labelWidth = ceilToPixel((text as NSString).size(withAttributes: [.font: Theme.dateFont]).width)
        guard outgoing else { return labelWidth }
        return labelWidth + checksGap + (read ? 16.0 : 11.5)
    }

    func update(text: String, outgoing: Bool, read: Bool, animated: Bool) {
        let textChanged = text != self.text
        let readChanged = read != self.read || outgoing != self.outgoing
        self.text = text
        self.outgoing = outgoing
        self.read = read
        label.textColor = outgoing ? Theme.outgoingSecondaryText : Theme.incomingSecondaryText
        if textChanged {
            if animated && !label.text.isNilOrEmpty {
                UIView.transition(with: label, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction], animations: {
                    self.label.text = text
                })
            } else {
                label.text = text
            }
        }
        checksView.isHidden = !outgoing
        if outgoing && (readChanged || checksView.image == nil) {
            let image = Icons.checks(read: read, color: Theme.outgoingCheck)
            if animated && checksView.image != nil {
                UIView.transition(with: checksView, duration: 0.2, options: [.transitionCrossDissolve], animations: {
                    self.checksView.image = image
                })
            } else {
                checksView.image = image
            }
        }
        layoutContent()
    }

    func layoutContent() {
        let labelWidth = ceilToPixel((text as NSString).size(withAttributes: [.font: Theme.dateFont]).width)
        label.frame = CGRect(x: 0, y: 0, width: labelWidth + 1, height: StatusView.height)
        checksView.frame = CGRect(x: labelWidth + StatusView.checksGap, y: 2.5, width: read ? 16.0 : 11.5, height: 10.0)
    }
}

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}

/// Date separator ("Сегодня").
final class DateHeaderView: UIView {
    private let capsule = UIView()
    private let label = UILabel()
    static let height: CGFloat = 36.0

    init(text: String) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        capsule.backgroundColor = Theme.serviceBackground
        addSubview(capsule)
        label.text = text
        label.font = Theme.serviceFont
        label.textColor = .white
        label.textAlignment = .center
        capsule.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let textWidth = ceilToPixel(label.intrinsicContentSize.width)
        let size = CGSize(width: textWidth + 16, height: 22)
        capsule.frame = CGRect(x: roundToPixel((bounds.width - size.width) / 2), y: roundToPixel((bounds.height - size.height) / 2), width: size.width, height: size.height)
        capsule.layer.cornerRadius = size.height / 2
        label.frame = capsule.bounds
    }
}

/// Reply quote inside a bubble: tinted rounded block with an accent bar.
final class ReplyHeaderView: UIControl {
    private let bar = UIView()
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let background = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        background.isUserInteractionEnabled = false
        background.layer.cornerRadius = 6
        background.clipsToBounds = true
        addSubview(background)
        bar.isUserInteractionEnabled = false
        background.addSubview(bar)
        titleLabel.font = Theme.replyTitleFont
        titleLabel.contentMode = .left
        textLabel.font = Theme.replyTextFont
        textLabel.textColor = Theme.primaryText
        textLabel.contentMode = .left
        addSubview(titleLabel)
        addSubview(textLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ preview: ReplyPreview, outgoing: Bool) {
        let tint = outgoing ? Theme.outgoingAccent : preview.color
        background.backgroundColor = tint.withAlphaComponent(0.1)
        bar.backgroundColor = tint
        titleLabel.textColor = tint
        titleLabel.text = preview.title
        textLabel.text = preview.text.replacingOccurrences(of: "\n", with: " ")
        setNeedsLayout()
    }

    override var isHighlighted: Bool {
        didSet { background.alpha = isHighlighted ? 0.6 : 1.0 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        bar.frame = CGRect(x: 0, y: 0, width: 3, height: bounds.height)
        titleLabel.frame = CGRect(x: 9, y: 3, width: bounds.width - 15, height: 17)
        textLabel.frame = CGRect(x: 9, y: 20, width: bounds.width - 15, height: 17)
    }

    static func preferredWidth(_ preview: ReplyPreview) -> CGFloat {
        let title = (preview.title as NSString).size(withAttributes: [.font: Theme.replyTitleFont]).width
        let text = (preview.text.replacingOccurrences(of: "\n", with: " ") as NSString).size(withAttributes: [.font: Theme.replyTextFont]).width
        return ceil(max(title, text)) + 17
    }
}

struct ReplyPreview: Equatable {
    let title: String
    let text: String
    let color: UIColor
}

/// A reaction chip inside the bubble: emoji + avatars of who reacted.
final class ReactionButton: UIControl {
    private(set) var reaction: Reaction
    private let outgoing: Bool
    private let background = UIView()
    private let emojiLabel = UILabel()
    private var avatarViews: [AvatarView] = []

    static let height: CGFloat = 30.0

    init(reaction: Reaction, outgoing: Bool) {
        self.reaction = reaction
        self.outgoing = outgoing
        super.init(frame: .zero)
        background.isUserInteractionEnabled = false
        background.layer.cornerRadius = ReactionButton.height / 2
        addSubview(background)
        emojiLabel.font = UIFont.systemFont(ofSize: 18)
        emojiLabel.textAlignment = .center
        addSubview(emojiLabel)
        update(reaction)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func width(for reaction: Reaction) -> CGFloat {
        let avatars = min(reaction.peers.count, 3)
        return 6 + 22 + 3 + 22 + CGFloat(max(0, avatars - 1)) * 14 + 4
    }

    func update(_ reaction: Reaction) {
        self.reaction = reaction
        let accent = outgoing ? Theme.outgoingReactionAccent : Theme.accent
        background.backgroundColor = reaction.chosenByMe ? accent : accent.withAlphaComponent(outgoing ? 0.12 : 0.1)
        emojiLabel.text = reaction.emoji
        let peers = Array(reaction.peers.prefix(3))
        if avatarViews.map({ $0.tag }) != peers.map({ $0.id }) {
            avatarViews.forEach { $0.removeFromSuperview() }
            avatarViews = peers.map { peer in
                let view = AvatarView(peer: peer, fontSize: 9)
                view.tag = peer.id
                view.layer.borderWidth = 1.5
                return view
            }
            avatarViews.reversed().forEach { addSubview($0) }
        }
        let borderColor = reaction.chosenByMe ? accent : (outgoing ? Theme.outgoingFill : Theme.incomingFill)
        avatarViews.forEach { $0.layer.borderColor = borderColor.cgColor }
        setNeedsLayout()
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        emojiLabel.frame = CGRect(x: 6, y: 4, width: 22, height: 22)
        for (i, avatar) in avatarViews.enumerated() {
            avatar.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
            avatar.center = CGPoint(x: 6 + 22 + 3 + 11 + CGFloat(i) * 14, y: bounds.height / 2)
        }
    }

    var emojiFrameInSelf: CGRect { emojiLabel.frame }

    func setEmojiHidden(_ hidden: Bool) { emojiLabel.alpha = hidden ? 0 : 1 }
}

/// Telegram's undo/notice overlay.
final class ToastView: UIView {
    private let label = UILabel()
    private let icon = UIImageView()

    init(text: String, symbol: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.0, alpha: 0.8)
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        icon.image = Icons.symbol(symbol, size: 20, weight: .medium, color: .white)
        icon.contentMode = .center
        addSubview(icon)
        label.text = text
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14)
        label.numberOfLines = 2
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        icon.frame = CGRect(x: 12, y: 0, width: 32, height: bounds.height)
        label.frame = CGRect(x: 54, y: 0, width: bounds.width - 66, height: bounds.height)
    }

    static func show(in view: UIView, text: String, symbol: String, bottomInset: CGFloat) {
        view.subviews.compactMap { $0 as? ToastView }.forEach { $0.removeFromSuperview() }
        let toast = ToastView(text: text, symbol: symbol)
        let width = view.bounds.width - 20
        toast.frame = CGRect(x: 10, y: view.bounds.height - bottomInset - 58, width: width, height: 50)
        view.addSubview(toast)
        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.96, y: 0.96)
        Spring.menu.animate {
            toast.alpha = 1
            toast.transform = .identity
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            UIView.animate(withDuration: 0.2, animations: {
                toast.alpha = 0
                toast.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            }, completion: { _ in toast.removeFromSuperview() })
        }
    }
}

/// Selection circle: white ring when empty, accent disc with a check when selected.
final class SelectionCheckView: UIView {
    private let ring = CAShapeLayer()
    private let fill = CAShapeLayer()
    private let check = CAShapeLayer()
    private(set) var isSelected = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        ring.fillColor = UIColor(white: 0, alpha: 0.08).cgColor
        ring.strokeColor = UIColor.white.cgColor
        ring.lineWidth = 1.5
        layer.addSublayer(ring)
        fill.fillColor = Theme.accent.cgColor
        layer.addSublayer(fill)
        check.strokeColor = UIColor.white.cgColor
        check.fillColor = UIColor.clear.cgColor
        check.lineWidth = 1.8
        check.lineCap = .round
        check.lineJoin = .round
        layer.addSublayer(check)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 0.5)
        setSelected(false, animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let r = bounds.insetBy(dx: 0.75, dy: 0.75)
        ring.path = UIBezierPath(ovalIn: r).cgPath
        fill.frame = bounds
        fill.path = UIBezierPath(ovalIn: bounds).cgPath
        let w = bounds.width
        let path = UIBezierPath()
        path.move(to: CGPoint(x: w * 0.28, y: w * 0.52))
        path.addLine(to: CGPoint(x: w * 0.44, y: w * 0.67))
        path.addLine(to: CGPoint(x: w * 0.73, y: w * 0.36))
        check.path = path.cgPath
        check.frame = bounds
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        isSelected = selected
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        fill.opacity = selected ? 1 : 0
        check.strokeEnd = selected ? 1 : 0
        CATransaction.commit()
        if animated && selected {
            let pop = CASpringAnimation(perceptualDuration: 0.35, bounce: 0.35)
            pop.keyPath = "transform.scale"
            pop.fromValue = 0.6
            pop.toValue = 1.0
            pop.duration = pop.settlingDuration
            fill.add(pop, forKey: "pop")
        }
    }
}

/// Bottom glass bar shown while messages are selected.
final class SelectionBarView: UIView {
    private let glass = GlassSurfaceView(cornerRadius: 25)
    let deleteButton = UIButton(type: .custom)
    let forwardButton = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(glass)
        deleteButton.setImage(Icons.symbol("trash", size: 21, weight: .regular, color: Theme.destructive), for: .normal)
        deleteButton.setImage(Icons.symbol("trash", size: 21, weight: .regular, color: UIColor(white: 0, alpha: 0.25)), for: .disabled)
        deleteButton.accessibilityLabel = "Delete"
        addSubview(deleteButton)
        forwardButton.setImage(Icons.symbol("arrowshape.turn.up.right", size: 21, weight: .regular, color: .black), for: .normal)
        forwardButton.setImage(Icons.symbol("arrowshape.turn.up.right", size: 21, weight: .regular, color: UIColor(white: 0, alpha: 0.25)), for: .disabled)
        forwardButton.accessibilityLabel = "Forward"
        addSubview(forwardButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        deleteButton.frame = CGRect(x: 6, y: 0, width: 56, height: bounds.height)
        forwardButton.frame = CGRect(x: bounds.width - 62, y: 0, width: 56, height: bounds.height)
    }
}
