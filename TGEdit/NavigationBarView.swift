import UIKit

/// Telegram chat header (iOS 26 glass design): floating glass capsules — back button with
/// unread badge, centred name + status, avatar — over a faded wallpaper edge.
final class NavigationBarView: UIView {
    private let backPill = GlassSurfaceView(interactive: true)
    private let backIcon = UIImageView(image: NavigationBarView.backArrow)
    private let badge = UILabel()
    private let backButton = UIButton(type: .custom)
    private let titlePill = GlassSurfaceView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let typingDots = TypingDotsView()
    private let avatarPill = GlassSurfaceView(interactive: true)
    private let avatar: AvatarView
    private let cancelLabel = UILabel()
    private let peerName: String
    private var selectionCount: Int?
    var topInset: CGFloat = 0
    var onCancel: (() -> Void)?
    var onTitleTap: (() -> Void)?
    var titlePillFrame: CGRect { titlePill.frame }
    var avatarPillFrame: CGRect { avatarPill.frame }
    private let titleButton = UIButton(type: .custom)

    /// Height of the band that holds the capsules (below the status bar).
    static let contentHeight: CGFloat = 60.0

    init(peer: Peer) {
        avatar = AvatarView(peer: peer, fontSize: 16, rounded: true)
        peerName = peer.name
        super.init(frame: .zero)
        cancelLabel.text = "Cancel"
        cancelLabel.font = UIFont.systemFont(ofSize: 17)
        cancelLabel.textColor = .black
        cancelLabel.alpha = 0
        addSubview(backPill)
        backIcon.tintColor = .black
        backPill.contentView.addSubview(backIcon)
        badge.text = "3"
        badge.font = UIFont.systemFont(ofSize: 13)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = .black
        badge.layer.cornerRadius = 9
        badge.clipsToBounds = true
        backPill.contentView.addSubview(badge)
        backButton.accessibilityLabel = "Back"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        addSubview(backButton)
        backPill.contentView.addSubview(cancelLabel)

        addSubview(titlePill)
        titleLabel.text = peer.name
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .black
        titleLabel.textAlignment = .center
        titlePill.contentView.addSubview(titleLabel)
        statusLabel.font = UIFont.systemFont(ofSize: 13)
        statusLabel.textAlignment = .center
        titlePill.contentView.addSubview(statusLabel)
        typingDots.isHidden = true
        titlePill.contentView.addSubview(typingDots)

        titleButton.accessibilityLabel = "Search in chat"
        titleButton.addTarget(self, action: #selector(titleTapped), for: .touchUpInside)
        titleButton.addTarget(self, action: #selector(titleDown), for: [.touchDown, .touchDragEnter])
        titleButton.addTarget(self, action: #selector(titleUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        addSubview(titleButton)

        addSubview(avatarPill)
        avatarPill.contentView.addSubview(avatar)
        setStatus(.lastSeenRecently)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    /// NavigationButtonNode.glassBackArrowImage geometry.
    static let backArrow: UIImage = {
        let size = CGSize(width: 44, height: 44)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(2.0)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.move(to: CGPoint(x: 24.6, y: 14.0))
            cg.addLine(to: CGPoint(x: 17.0, y: 22.0))
            cg.addLine(to: CGPoint(x: 24.6, y: 30.0))
            cg.strokePath()
        }.withRenderingMode(.alwaysTemplate)
    }()

    @objc private func titleTapped() {
        if selectionCount == nil { onTitleTap?() }
    }

    @objc private func titleDown() {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.titlePill.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }
    }

    @objc private func titleUp() {
        Spring.menu.animate { self.titlePill.transform = .identity }
    }

    /// Scripted tap for recordings: the same press feedback, then the action.
    func simulateTitleTap() {
        titleDown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            self.titleUp()
            self.titleTapped()
        }
    }

    @objc private func backTapped() {
        if selectionCount != nil { onCancel?() }
    }

    func setSelection(count: Int?) {
        let entering = (count != nil) != (selectionCount != nil)
        selectionCount = count
        titleLabel.text = count.map { "\($0) Selected" } ?? peerName
        backButton.accessibilityLabel = count == nil ? "Back" : "Cancel"
        setNeedsLayout()
        let changes = {
            let selecting = count != nil
            self.cancelLabel.alpha = selecting ? 1 : 0
            self.backIcon.alpha = selecting ? 0 : 1
            self.badge.alpha = selecting ? 0 : 1
            self.statusLabel.alpha = selecting ? 0 : 1
            self.typingDots.alpha = selecting ? 0 : 1
            self.avatarPill.alpha = selecting ? 0 : 1
            self.avatarPill.transform = selecting ? CGAffineTransform(scaleX: 0.6, y: 0.6) : .identity
            self.layoutIfNeeded()
        }
        if entering { Spring.standard.animate(changes) } else { changes() }
    }

    enum Status { case lastSeenRecently, online, typing }

    func setStatus(_ status: Status) {
        let text: String
        let color: UIColor
        switch status {
        case .lastSeenRecently: text = "last seen recently"; color = Theme.navSecondaryText
        case .online: text = "online"; color = Theme.accent
        case .typing: text = "typing"; color = Theme.accent
        }
        if statusLabel.text != text {
            UIView.transition(with: statusLabel, duration: 0.2, options: .transitionCrossDissolve, animations: {
                self.statusLabel.text = text
                self.statusLabel.textColor = color
            })
        }
        typingDots.isHidden = status != .typing
        if status == .typing { typingDots.start() } else { typingDots.stop() }
        setNeedsLayout()
        if window != nil {
            Spring.standard.animate { self.layoutIfNeeded() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let top = topInset

        let cancelWidth = ceil(cancelLabel.intrinsicContentSize.width)
        backPill.frame = CGRect(x: 16, y: top + 10, width: selectionCount == nil ? 59 : cancelWidth + 32, height: 44)
        cancelLabel.frame = CGRect(x: 16, y: 0, width: cancelWidth, height: 44)
        backIcon.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        badge.frame = CGRect(x: 30, y: 13, width: 18, height: 18)
        backButton.frame = backPill.frame.insetBy(dx: -4, dy: -4)

        avatarPill.frame = CGRect(x: width - 16 - 44, y: top + 10, width: 44, height: 44)
        avatar.frame = CGRect(x: 3, y: 3, width: 38, height: 38)

        let titleWidth = ceil(titleLabel.intrinsicContentSize.width)
        statusLabel.sizeToFit()
        let statusWidth = ceil(statusLabel.bounds.width)
        let dotsWidth: CGFloat = typingDots.isHidden ? 0 : 18
        let contentWidth = selectionCount == nil ? max(titleWidth, statusWidth + dotsWidth) : titleWidth
        let maxPill = width - 2 * (16 + 59 + 8)
        let pillWidth = min(maxPill, contentWidth + 24)
        titlePill.bounds = CGRect(x: 0, y: 0, width: pillWidth, height: 44)
        titlePill.center = CGPoint(x: roundToPixel(width / 2), y: top + 8 + 22)
        titleButton.frame = CGRect(x: roundToPixel((width - pillWidth) / 2), y: top + 8, width: pillWidth, height: 44)
        titleLabel.frame = CGRect(x: 12, y: selectionCount == nil ? 4 : 11.5, width: pillWidth - 24, height: 21)
        let statusX = (pillWidth - statusWidth - dotsWidth) / 2 + dotsWidth
        statusLabel.frame = CGRect(x: statusX, y: 23, width: statusWidth, height: 16)
        typingDots.frame = CGRect(x: statusX - dotsWidth, y: 23, width: dotsWidth, height: 16)
    }
}

/// Three pulsing dots shown before "typing".
final class TypingDotsView: UIView {
    private var dots: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        for _ in 0 ..< 3 {
            let dot = UIView()
            dot.backgroundColor = Theme.accent
            dot.layer.cornerRadius = 1.75
            addSubview(dot)
            dots.append(dot)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (i, dot) in dots.enumerated() {
            dot.frame = CGRect(x: 2 + CGFloat(i) * 4.5, y: bounds.height / 2 - 1, width: 3.5, height: 3.5)
        }
    }

    func start() {
        for (i, dot) in dots.enumerated() {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.25
            pulse.toValue = 1.0
            pulse.duration = 0.45
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.beginTime = CACurrentMediaTime() + Double(i) * 0.15
            pulse.fillMode = .backwards
            dot.layer.add(pulse, forKey: "pulse")
        }
    }

    func stop() {
        dots.forEach { $0.layer.removeAllAnimations() }
    }
}
