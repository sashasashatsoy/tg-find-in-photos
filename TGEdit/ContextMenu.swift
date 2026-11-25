import UIKit

struct ContextAction {
    let title: String
    let icon: String
    var destructive: Bool = false
    /// Run only once the lifted message is back in its slot (deletion animates the real bubble).
    var afterLanding: Bool = false
    let handler: () -> Void
}

/// Telegram-style message context menu: blurred chat, the lifted bubble, a reaction bar above
/// it and an action list below it.
final class ContextMenuOverlay: UIView {
    private let blurView = UIVisualEffectView(effect: nil)
    private let dimView = UIView()
    private let clipView = UIView()
    private let snapshot: UIView
    private let reactionBar: ReactionBarView
    private let menuView: ActionMenuView
    private let sourceFrame: CGRect
    private let outgoing: Bool
    private var targetFrame: CGRect = .zero
    private var isDismissing = false

    var onDismiss: (() -> Void)?
    var onReaction: ((String, CGRect) -> Void)?
    var currentSourceFrame: (() -> CGRect?)?

    init(snapshot: UIView, sourceFrame: CGRect, outgoing: Bool, groups: [[ContextAction]], reactions: [String], chosenReaction: String?) {
        self.snapshot = snapshot
        self.sourceFrame = sourceFrame
        self.outgoing = outgoing
        self.reactionBar = ReactionBarView(reactions: reactions, chosen: chosenReaction)
        self.menuView = ActionMenuView(groups: groups)
        super.init(frame: .zero)
        dimView.backgroundColor = UIColor(white: 0.0, alpha: 0.12)
        dimView.alpha = 0
        addSubview(blurView)
        addSubview(dimView)
        clipView.clipsToBounds = true
        addSubview(clipView)
        clipView.addSubview(snapshot)
        addSubview(reactionBar)
        addSubview(menuView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)

        reactionBar.onSelect = { [weak self] emoji, frame in
            guard let self = self else { return }
            let windowFrame = self.reactionBar.convert(frame, to: nil)
            self.onReaction?(emoji, windowFrame)
        }
        menuView.onAction = { [weak self] action in
            if action.afterLanding {
                self?.dismiss(completion: nil, afterLanding: action.handler)
            } else {
                self?.dismiss(completion: action.handler)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func backgroundTapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        if menuView.frame.contains(point) || reactionBar.frame.insetBy(dx: 0, dy: -6).contains(point) { return }
        dismiss(completion: nil)
    }

    func present(in host: UIView) {
        frame = host.bounds
        host.addSubview(self)
        blurView.frame = bounds
        dimView.frame = bounds

        let safe = host.safeAreaInsets
        let top = safe.top + 10
        let bottom = bounds.height - max(safe.bottom, 10) - 8
        let barHeight = ReactionBarView.height
        let menuSize = menuView.preferredSize
        let gap: CGFloat = 10

        var messageY = sourceFrame.minY
        let minY = top + barHeight + gap
        let maxY = bottom - menuSize.height - gap - sourceFrame.height
        var clipTop = minY
        var clipBottom = bounds.height
        if maxY < minY {
            // Very tall message: pin the menu to the bottom and clip the bubble preview.
            messageY = bottom - menuSize.height - gap - sourceFrame.height
            clipTop = minY - 2
            clipBottom = bottom - menuSize.height - gap + 2
        } else {
            messageY = min(max(messageY, minY), maxY)
        }
        targetFrame = CGRect(x: sourceFrame.minX, y: messageY, width: sourceFrame.width, height: sourceFrame.height)
        if maxY < minY {
            clipView.frame = CGRect(x: 0, y: clipTop, width: bounds.width, height: clipBottom - clipTop)
        } else {
            clipView.frame = bounds
        }

        let bodyMinX = outgoing ? targetFrame.minX : targetFrame.minX + BubbleImages.tailWidth
        let bodyMaxX = outgoing ? targetFrame.maxX - BubbleImages.tailWidth : targetFrame.maxX

        var menuX = outgoing ? bodyMaxX - menuSize.width : bodyMinX
        menuX = min(max(8, menuX), bounds.width - 8 - menuSize.width)
        let menuY = min(targetFrame.maxY, clipView.frame.maxY) + gap
        menuView.frame = CGRect(x: menuX, y: menuY, width: menuSize.width, height: menuSize.height)

        let barWidth = reactionBar.preferredWidth
        var barX = outgoing ? bodyMaxX - barWidth + 12 : bodyMinX - 12
        barX = min(max(8, barX), bounds.width - 8 - barWidth)
        let barY = max(top, targetFrame.minY - gap - barHeight)
        reactionBar.frame = CGRect(x: barX, y: barY, width: barWidth, height: barHeight)
        reactionBar.tailOnRight = outgoing

        // Initial state.
        place(snapshotFrame: sourceFrame, scale: 0.96)
        menuView.setAnchor(CGPoint(x: outgoing ? 1 : 0, y: 0))
        menuView.alpha = 0
        menuView.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        reactionBar.setAnchor(CGPoint(x: outgoing ? 0.9 : 0.1, y: 1))
        reactionBar.alpha = 0
        reactionBar.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)

        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            self.blurView.effect = UIBlurEffect(style: .light)
            self.dimView.alpha = 1
        }
        Spring.menu.animate {
            self.place(snapshotFrame: self.targetFrame, scale: 1.0)
            self.menuView.alpha = 1
            self.menuView.transform = .identity
            self.reactionBar.alpha = 1
            self.reactionBar.transform = .identity
        }
        reactionBar.animateItemsIn()
        Haptics.impact(.medium)
    }

    private func place(snapshotFrame: CGRect, scale: CGFloat) {
        let local = clipView.convert(snapshotFrame, from: self)
        snapshot.bounds = CGRect(origin: .zero, size: snapshotFrame.size)
        snapshot.center = local.center
        snapshot.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    func dismiss(completion: (() -> Void)?, afterLanding: (() -> Void)? = nil) {
        guard !isDismissing else { return }
        isDismissing = true
        isUserInteractionEnabled = false
        let returnFrame = currentSourceFrame?() ?? sourceFrame
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn]) {
            self.menuView.alpha = 0
            self.menuView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            self.reactionBar.alpha = 0
            self.reactionBar.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            self.blurView.effect = nil
            self.dimView.alpha = 0
        }
        let landing = afterLanding == nil ? Spring.standard : Spring(duration: 0.34, bounce: 0)
        landing.animate({
            self.clipView.frame = self.bounds
            self.place(snapshotFrame: returnFrame, scale: 1.0)
        }, completion: { _ in
            self.onDismiss?()
            afterLanding?()
            self.removeFromSuperview()
        })
        if let completion = completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: completion)
        }
    }

    /// Scripted tap on a menu row (promo recording). Returns the row's frame in window space.
    @discardableResult
    func performAction(titled title: String) -> CGRect? {
        guard let row = menuView.row(titled: title) else { return nil }
        row.isHighlighted = true
        let frame = row.convert(row.bounds, to: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            row.isHighlighted = false
            self?.menuView.onAction?(row.action)
        }
        return frame
    }

    /// Lets the controller fly the chosen emoji from the bar.
    func dismissForReaction() {
        dismiss(completion: nil)
    }
}

// MARK: - Reaction bar

final class ReactionBarView: UIView {
    static let height: CGFloat = 50.0
    private static let itemSize: CGFloat = 36.0
    private let background = GlassSurfaceView()
    private let container = UIView()
    private let smallBubble = GlassSurfaceView()
    private let tinyBubble = UIView()
    private var items: [UIButton] = []
    private let expandButton = UIButton(type: .custom)
    private let reactions: [String]
    private let chosen: String?
    var tailOnRight = true { didSet { setNeedsLayout() } }
    var onSelect: ((String, CGRect) -> Void)?

    init(reactions: [String], chosen: String?) {
        self.reactions = reactions
        self.chosen = chosen
        super.init(frame: .zero)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.05
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)
        tinyBubble.backgroundColor = UIColor(white: 1.0, alpha: 0.85)
        addSubview(smallBubble)
        addSubview(tinyBubble)
        addSubview(background)
        addSubview(container)
        for (i, emoji) in reactions.enumerated() {
            let button = UIButton(type: .custom)
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 27)
            button.tag = i
            button.accessibilityLabel = "Reaction \(emoji)"
            if emoji == chosen {
                button.backgroundColor = UIColor(white: 0.0, alpha: 0.08)
                button.layer.cornerRadius = ReactionBarView.itemSize / 2
            }
            button.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
            button.addTarget(self, action: #selector(itemDown(_:)), for: [.touchDown, .touchDragEnter])
            button.addTarget(self, action: #selector(itemUp(_:)), for: [.touchUpOutside, .touchCancel, .touchDragExit])
            container.addSubview(button)
            items.append(button)
        }
        expandButton.backgroundColor = UIColor(white: 0.0, alpha: 0.06)
        expandButton.layer.cornerRadius = 12
        expandButton.setImage(Icons.symbol("chevron.down", size: 12, weight: .bold, color: UIColor(rgb: 0x8e8e93)), for: .normal)
        expandButton.accessibilityLabel = "All reactions"
        container.addSubview(expandButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    var preferredWidth: CGFloat {
        return 8 + CGFloat(reactions.count) * (ReactionBarView.itemSize + 2) + 32
    }

    func setAnchor(_ point: CGPoint) {
        let oldFrame = frame
        layer.anchorPoint = point
        frame = oldFrame
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = ReactionBarView.height
        background.frame = CGRect(x: 0, y: 0, width: bounds.width, height: h)
        container.frame = background.frame
        var x: CGFloat = 6
        for button in items {
            button.bounds = CGRect(x: 0, y: 0, width: ReactionBarView.itemSize, height: ReactionBarView.itemSize)
            button.center = CGPoint(x: x + ReactionBarView.itemSize / 2, y: h / 2)
            x += ReactionBarView.itemSize + 2
        }
        expandButton.frame = CGRect(x: bounds.width - 34, y: (h - 24) / 2, width: 24, height: 24)
        let bubbleX = tailOnRight ? bounds.width - 30 : 30
        smallBubble.frame = CGRect(x: bubbleX - 6, y: h + 1, width: 12, height: 12)
        tinyBubble.frame = CGRect(x: bubbleX + (tailOnRight ? 6 : -10), y: h + 11, width: 5, height: 5)
        tinyBubble.layer.cornerRadius = 2.5
    }

    func animateItemsIn() {
        for (i, button) in items.enumerated() {
            button.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            button.alpha = 0
            UIView.animate(withDuration: 0.45, delay: 0.04 + Double(i) * 0.025, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: [.allowUserInteraction], animations: {
                button.transform = .identity
                button.alpha = 1
            })
        }
    }

    @objc private func itemDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.15) { sender.transform = CGAffineTransform(scaleX: 1.25, y: 1.25) }
    }

    @objc private func itemUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.15) { sender.transform = .identity }
    }

    @objc private func itemTapped(_ sender: UIButton) {
        Haptics.selection()
        let frame = sender.convert(sender.bounds, to: self)
        onSelect?(reactions[sender.tag], frame)
    }
}

// MARK: - Action list

final class ActionMenuView: UIView {
    private let background = GlassSurfaceView(cornerRadius: 22)
    private let container = UIView()
    private var rows: [ActionRow] = []
    private var separators: [(UIView, CGFloat)] = []
    private let groups: [[ContextAction]]
    var onAction: ((ContextAction) -> Void)?

    static let rowHeight: CGFloat = 44.0
    static let groupGap: CGFloat = 8.0
    static let width: CGFloat = 250.0

    init(groups: [[ContextAction]]) {
        self.groups = groups
        super.init(frame: .zero)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.06
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 6)
        addSubview(background)
        container.clipsToBounds = true
        container.layer.cornerRadius = 22
        container.layer.cornerCurve = .continuous
        addSubview(container)
        var y: CGFloat = 0
        for (g, group) in groups.enumerated() {
            if g > 0 {
                let gap = UIView()
                gap.backgroundColor = Theme.menuGroupSeparator
                container.addSubview(gap)
                separators.append((gap, y))
                y += ActionMenuView.groupGap
            }
            for (i, action) in group.enumerated() {
                if i > 0 {
                    let line = UIView()
                    line.backgroundColor = Theme.menuSeparator
                    container.addSubview(line)
                    separators.append((line, y))
                }
                let row = ActionRow(action: action)
                row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
                row.frame.origin.y = y
                container.addSubview(row)
                rows.append(row)
                y += ActionMenuView.rowHeight
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    var preferredSize: CGSize {
        let rowsCount = groups.reduce(0) { $0 + $1.count }
        let height = CGFloat(rowsCount) * ActionMenuView.rowHeight + CGFloat(max(0, groups.count - 1)) * ActionMenuView.groupGap
        return CGSize(width: ActionMenuView.width, height: height)
    }

    func setAnchor(_ point: CGPoint) {
        let oldFrame = frame
        layer.anchorPoint = point
        frame = oldFrame
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        container.frame = bounds
        for row in rows {
            row.frame = CGRect(x: 0, y: row.frame.origin.y, width: bounds.width, height: ActionMenuView.rowHeight)
        }
        for (view, y) in separators {
            if view.backgroundColor == Theme.menuGroupSeparator {
                view.frame = CGRect(x: 0, y: y, width: bounds.width, height: ActionMenuView.groupGap)
            } else {
                view.frame = CGRect(x: 0, y: y - screenPixel / 2, width: bounds.width, height: screenPixel)
            }
        }
    }

    fileprivate func row(titled title: String) -> ActionRow? {
        rows.first { $0.action.title == title }
    }

    @objc private func rowTapped(_ sender: ActionRow) {
        onAction?(sender.action)
    }
}

private final class ActionRow: UIControl {
    let action: ContextAction
    private let titleLabel = UILabel()
    private let iconView = UIImageView()
    private let highlight = UIView()

    init(action: ContextAction) {
        self.action = action
        super.init(frame: .zero)
        highlight.backgroundColor = Theme.menuHighlight
        highlight.alpha = 0
        highlight.isUserInteractionEnabled = false
        addSubview(highlight)
        let color = action.destructive ? Theme.destructive : UIColor.black
        titleLabel.text = action.title
        titleLabel.font = UIFont.systemFont(ofSize: 17)
        titleLabel.textColor = color
        addSubview(titleLabel)
        iconView.image = Icons.symbol(action.icon, size: 19, weight: .regular, color: color)
        iconView.contentMode = .center
        addSubview(iconView)
        accessibilityLabel = action.title
        accessibilityTraits = .button
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { highlight.alpha = isHighlighted ? 1 : 0 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds
        titleLabel.frame = CGRect(x: 18, y: 0, width: bounds.width - 62, height: bounds.height)
        iconView.frame = CGRect(x: bounds.width - 48, y: 0, width: 30, height: bounds.height)
    }
}
