import UIKit

/// Pure geometry of a message cell; computed off any view so it can be diffed and animated.
struct MessageLayout {
    let message: Message
    let reply: ReplyPreview?
    let position: BubbleGroupPosition
    let width: CGFloat
    let textLayout: TextLayout
    let bubbleFrame: CGRect          // in cell coordinates (includes the tail column)
    let bodyOffsetX: CGFloat         // 6 for incoming (tail on the left), 0 for outgoing
    let textFrame: CGRect            // bubble coordinates
    let replyFrame: CGRect?
    let statusFrame: CGRect
    let statusText: String
    let reactionFrames: [CGRect]
    /// Photo messages: the picture inside the bubble (bubble coordinates).
    var photoFrame: CGRect? = nil
    var height: CGFloat { bubbleFrame.height }

    static let photoInset: CGFloat = 2.0

    /// Telegram media bubble: the picture fills the bubble up to a hairline of bubble colour,
    /// time sits on a dark capsule over the image.
    static func makePhoto(message: Message, asset: PhotoAsset, position: BubbleGroupPosition, width: CGFloat) -> MessageLayout {
        let outgoing = message.isOutgoing
        let tail = BubbleImages.tailWidth
        let maxWidth = min(floor(width * 0.68), 280)
        let maxHeight: CGFloat = 330
        var w = maxWidth
        var h = w / asset.aspect
        if h > maxHeight { h = maxHeight; w = h * asset.aspect }
        w = ceilToPixel(w); h = ceilToPixel(h)
        let inset = photoInset
        let bodyWidth = w + inset * 2
        let height = h + inset * 2
        let bodyOffsetX: CGFloat = outgoing ? 0 : tail
        let bubbleWidth = bodyWidth + tail
        let bubbleX = outgoing ? width - edgeInset - bubbleWidth : edgeInset
        let bubbleFrame = CGRect(x: bubbleX, y: 0, width: bubbleWidth, height: height)
        let photoFrame = CGRect(x: bodyOffsetX + inset, y: inset, width: w, height: h)
        let time = DateFormatting.time.string(from: message.date)
        let statusWidth = PhotoStatusView.width(text: time, outgoing: outgoing)
        let statusFrame = CGRect(x: photoFrame.maxX - 6 - statusWidth, y: photoFrame.maxY - 6 - PhotoStatusView.height, width: statusWidth, height: PhotoStatusView.height)
        return MessageLayout(
            message: message, reply: nil, position: position, width: width,
            textLayout: TextLayout(text: "", maxWidth: 10),
            bubbleFrame: bubbleFrame, bodyOffsetX: bodyOffsetX,
            textFrame: .zero, replyFrame: nil, statusFrame: statusFrame, statusText: time,
            reactionFrames: [], photoFrame: photoFrame
        )
    }

    // Telegram ChatMessageItemLayoutConstants (compact width)
    static let edgeInset: CGFloat = 3.0
    static let textInsetX: CGFloat = 11.0
    static let textTop: CGFloat = 4.667
    static let textBottom: CGFloat = 10.333
    static let statusLineHeight: CGFloat = 14.0
    static let minBodyWidth: CGFloat = 40.0

    static func make(message: Message, reply: ReplyPreview?, position: BubbleGroupPosition, width: CGFloat, reusing previous: TextLayout?) -> MessageLayout {
        if let asset = message.photoAsset {
            return makePhoto(message: message, asset: asset, position: position, width: width)
        }
        let outgoing = message.isOutgoing
        let tail = BubbleImages.tailWidth
        let maxBubbleWidth = floor(width - 54.0)
        let maxBody = maxBubbleWidth - tail
        let textMaxWidth = maxBody - textInsetX * 2

        let textLayout: TextLayout
        if let previous = previous, previous.text == message.text, previous.maxWidth == textMaxWidth {
            textLayout = previous
        } else {
            textLayout = TextLayout(text: message.text, maxWidth: textMaxWidth)
        }

        let time = DateFormatting.time.string(from: message.date)
        let statusText = message.isEdited ? "edited \(time)" : time
        let statusWidth = StatusView.width(text: statusText, outgoing: outgoing, read: message.isRead)
        let statusRight: CGFloat = outgoing ? 7.0 : 10.0

        var bodyWidth = minBodyWidth
        var replyFrame: CGRect?
        var textTop = textTop
        if let reply = reply {
            let replyWidth = min(maxBody - 18, max(80, ReplyHeaderView.preferredWidth(reply)))
            replyFrame = CGRect(x: 9, y: 7, width: replyWidth, height: 40)
            bodyWidth = max(bodyWidth, replyWidth + 18)
            textTop = 47 + 1.667
        }

        let textSize = textLayout.size
        let textBottomY = textTop + textSize.height
        bodyWidth = max(bodyWidth, textInsetX * 2 + textSize.width)

        var reactionFrames: [CGRect] = []
        var height: CGFloat
        var statusY: CGFloat
        if message.reactions.isEmpty {
            let inlineWidth = textInsetX + textLayout.lastLineWidth + 6 + statusWidth + statusRight
            if inlineWidth <= maxBody && textLayout.lastLineWidth > 0 {
                bodyWidth = max(bodyWidth, inlineWidth)
                height = textBottomY + textBottom
            } else {
                bodyWidth = max(bodyWidth, textInsetX + statusWidth + statusRight)
                height = textBottomY + textBottom + statusLineHeight
            }
            statusY = height - 5 - StatusView.height
        } else {
            let rowMax = maxBody - textInsetX * 2
            var x: CGFloat = 0
            var y: CGFloat = textBottomY + 5
            var rowsWidth: CGFloat = 0
            for reaction in message.reactions {
                let w = ReactionButton.width(for: reaction)
                if x > 0 && x + w > rowMax {
                    x = 0
                    y += ReactionButton.height + 6
                }
                reactionFrames.append(CGRect(x: textInsetX + x, y: y, width: w, height: ReactionButton.height))
                x += w + 6
                rowsWidth = max(rowsWidth, x - 6)
            }
            let lastRowWidth = x - 6
            let rowsBottom = y + ReactionButton.height
            bodyWidth = max(bodyWidth, textInsetX * 2 + rowsWidth)
            let inlineWidth = textInsetX + lastRowWidth + 10 + statusWidth + statusRight
            if inlineWidth <= maxBody {
                bodyWidth = max(bodyWidth, inlineWidth)
                height = rowsBottom + 6
            } else {
                bodyWidth = max(bodyWidth, textInsetX + statusWidth + statusRight)
                height = rowsBottom + 4 + statusLineHeight + 5
            }
            statusY = height - 5 - StatusView.height
        }

        bodyWidth = ceilToPixel(bodyWidth)
        height = ceilToPixel(max(height, 35))
        let bodyOffsetX: CGFloat = outgoing ? 0 : tail
        let bubbleWidth = bodyWidth + tail
        let bubbleX = outgoing ? width - edgeInset - bubbleWidth : edgeInset
        let bubbleFrame = CGRect(x: bubbleX, y: 0, width: bubbleWidth, height: height)

        let textFrame = CGRect(x: bodyOffsetX + textInsetX, y: roundToPixel(textTop), width: textSize.width, height: textSize.height)
        let statusFrame = CGRect(x: bodyOffsetX + bodyWidth - statusRight - statusWidth, y: roundToPixel(statusY), width: statusWidth, height: StatusView.height)
        return MessageLayout(
            message: message,
            reply: reply,
            position: position,
            width: width,
            textLayout: textLayout,
            bubbleFrame: bubbleFrame,
            bodyOffsetX: bodyOffsetX,
            textFrame: textFrame,
            replyFrame: replyFrame.map { $0.offsetBy(dx: bodyOffsetX, dy: 0) },
            statusFrame: statusFrame,
            statusText: statusText,
            reactionFrames: reactionFrames.map { $0.offsetBy(dx: bodyOffsetX, dy: 0) }
        )
    }
}

enum CellTransition {
    case immediate
    case animated(Spring)
    /// Local edit by the current user: glyph-level morph.
    case morph(Spring)
    /// Remote edit: standard cross-dissolve.
    case crossfade(Spring)

    var spring: Spring? {
        switch self {
        case .immediate: return nil
        case let .animated(s), let .morph(s), let .crossfade(s): return s
        }
    }
}

final class MessageCellView: UIView, UIGestureRecognizerDelegate {
    let bubbleView = UIView()
    let backgroundImageView = UIImageView()
    let textView = AnimatedTextView()
    let statusView = StatusView()
    let photoView = UIImageView()
    private let photoMask = CAShapeLayer()
    private let photoStatus = PhotoStatusView()
    private var replyView: ReplyHeaderView?
    private var reactionButtons: [String: ReactionButton] = [:]
    private(set) var layout: MessageLayout?

    var onLongPress: ((MessageCellView) -> Void)?
    var onDoubleTap: ((MessageCellView) -> Void)?
    var onReplyTap: ((MessageCellView) -> Void)?
    var onReactionTap: ((MessageCellView, String) -> Void)?
    var onSelectTap: ((MessageCellView) -> Void)?

    private let checkView = SelectionCheckView()
    private var selectTap: UITapGestureRecognizer!
    private(set) var selectionActive = false
    /// Set while the bubble burns away so nothing makes it visible again.
    var isBeingDeleted = false
    private var selectionShift: CGAffineTransform = .identity

    private var pressRecognizer: UILongPressGestureRecognizer!
    private var menuRecognizer: UILongPressGestureRecognizer!
    private var menuOpened = false

    var messageId: Int { layout?.message.id ?? -1 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(bubbleView)
        bubbleView.addSubview(backgroundImageView)
        bubbleView.addSubview(textView)
        bubbleView.addSubview(statusView)
        photoView.contentMode = .scaleAspectFill
        photoView.layer.mask = photoMask
        photoView.isHidden = true
        bubbleView.addSubview(photoView)
        photoStatus.isHidden = true
        bubbleView.addSubview(photoStatus)

        pressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        pressRecognizer.minimumPressDuration = 0.08
        pressRecognizer.delegate = self
        pressRecognizer.cancelsTouchesInView = false
        bubbleView.addGestureRecognizer(pressRecognizer)

        menuRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleMenuPress(_:)))
        menuRecognizer.minimumPressDuration = 0.32
        menuRecognizer.delegate = self
        bubbleView.addGestureRecognizer(menuRecognizer)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        bubbleView.addGestureRecognizer(doubleTap)

        checkView.alpha = 0
        addSubview(checkView)
        selectTap = UITapGestureRecognizer(target: self, action: #selector(handleSelectTap))
        selectTap.delegate = self
        addGestureRecognizer(selectTap)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === selectTap { return selectionActive }
        if gestureRecognizer === pressRecognizer || gestureRecognizer === menuRecognizer || gestureRecognizer.view === bubbleView {
            return !selectionActive
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    @objc private func handleSelectTap() {
        onSelectTap?(self)
    }

    /// Telegram's selection mode: a check circle on the left, incoming bubbles slide right.
    func setSelection(active: Bool, selected: Bool, animated: Bool) {
        let wasActive = selectionActive
        selectionActive = active
        let incoming = !(layout?.message.isOutgoing ?? true)
        selectionShift = active && incoming ? CGAffineTransform(translationX: 42, y: 0) : .identity
        checkView.setSelected(selected, animated: animated && wasActive && active)
        let size: CGFloat = 24
        checkView.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        checkView.center = CGPoint(x: 8 + size / 2, y: bounds.height / 2)
        let changes = {
            self.bubbleView.transform = self.selectionShift
            self.checkView.alpha = active ? 1 : 0
            self.checkView.transform = active ? .identity : CGAffineTransform(translationX: -30, y: 0)
        }
        if animated && wasActive != active {
            Spring.standard.animate(changes)
        } else {
            changes()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        checkView.center = CGPoint(x: 8 + 12, y: bounds.height / 2)
    }

    required init?(coder: NSCoder) { fatalError() }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer === pressRecognizer || otherGestureRecognizer === pressRecognizer
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view is UIControl { return false }
        return true
    }

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            menuOpened = false
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
                self.bubbleView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            }
        case .ended, .cancelled, .failed:
            if !menuOpened {
                Spring.standard.animate {
                    self.bubbleView.transform = .identity
                }
            }
        default:
            break
        }
    }

    @objc private func handleMenuPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        menuOpened = true
        onLongPress?(self)
    }

    @objc private func handleDoubleTap() {
        onDoubleTap?(self)
    }

    /// Scripted touch-down (promo recording): the same shrink a real long press starts with.
    func simulatePressDown() {
        menuOpened = true
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.bubbleView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }
    }

    func resetPressState() {
        menuOpened = false
        bubbleView.transform = selectionShift
    }

    @objc private func replyTapped() {
        onReplyTap?(self)
    }

    @objc private func reactionTapped(_ sender: ReactionButton) {
        onReactionTap?(self, sender.reaction.emoji)
    }

    func reactionButton(for emoji: String) -> ReactionButton? { reactionButtons[emoji] }

    // MARK: - Apply

    func apply(_ newLayout: MessageLayout, transition: CellTransition) {
        let old = layout
        layout = newLayout
        let message = newLayout.message
        let outgoing = message.isOutgoing

        // Background shape.
        let image = BubbleImages.image(outgoing: outgoing, position: newLayout.position)
        if backgroundImageView.image !== image {
            if old != nil, transition.spring != nil, old?.position != newLayout.position {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.2
                backgroundImageView.layer.add(fade, forKey: "image")
            }
            backgroundImageView.image = image
        }

        // Text.
        switch transition {
        case .immediate, .animated:
            if textView.textLayout !== newLayout.textLayout {
                if old != nil, case .animated = transition, old?.textLayout.text != newLayout.textLayout.text {
                    textView.crossfade(to: newLayout.textLayout)
                } else {
                    textView.setLayout(newLayout.textLayout)
                }
            }
        case .morph:
            if let previous = textView.textLayout, previous.text != newLayout.textLayout.text {
                textView.morph(to: newLayout.textLayout, spring: transition.spring ?? .textMorph)
            } else if textView.textLayout !== newLayout.textLayout {
                textView.setLayout(newLayout.textLayout)
            }
        case .crossfade:
            if textView.textLayout !== newLayout.textLayout {
                textView.crossfade(to: newLayout.textLayout)
            }
        }

        let animated = old != nil && transition.spring != nil
        let isPhoto = newLayout.photoFrame != nil
        photoView.isHidden = !isPhoto
        photoStatus.isHidden = !isPhoto
        textView.isHidden = isPhoto
        statusView.isHidden = isPhoto
        if let asset = message.photoAsset, let frame = newLayout.photoFrame {
            if photoView.image == nil || old?.message.photo != message.photo {
                photoView.image = asset.image
            }
            photoView.frame = frame
            photoMask.path = MessageCellView.photoPath(size: frame.size, outgoing: outgoing, position: newLayout.position)
            photoStatus.update(text: newLayout.statusText, outgoing: outgoing, read: message.isRead)
        }
        statusView.update(text: newLayout.statusText, outgoing: outgoing, read: message.isRead, animated: animated)

        // Reply header.
        var appearingViews: [UIView] = []
        if let reply = newLayout.reply, let frame = newLayout.replyFrame {
            if replyView == nil {
                let view = ReplyHeaderView()
                view.addTarget(self, action: #selector(replyTapped), for: .touchUpInside)
                bubbleView.addSubview(view)
                view.frame = frame
                replyView = view
                if animated { appearingViews.append(view) }
            }
            replyView?.update(reply, outgoing: outgoing)
        } else if let view = replyView {
            replyView = nil
            if animated {
                UIView.animate(withDuration: 0.15, animations: { view.alpha = 0 }, completion: { _ in view.removeFromSuperview() })
            } else {
                view.removeFromSuperview()
            }
        }

        // Reactions.
        var newButtons: [String: ReactionButton] = [:]
        var buttonFrames: [(ReactionButton, CGRect)] = []
        for (reaction, frame) in zip(message.reactions, newLayout.reactionFrames) {
            if let existing = reactionButtons[reaction.emoji] {
                existing.update(reaction)
                newButtons[reaction.emoji] = existing
                buttonFrames.append((existing, frame))
            } else {
                let button = ReactionButton(reaction: reaction, outgoing: outgoing)
                button.addTarget(self, action: #selector(reactionTapped(_:)), for: .touchUpInside)
                bubbleView.addSubview(button)
                button.frame = frame
                newButtons[reaction.emoji] = button
                if animated {
                    button.alpha = 0
                    button.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
                    Spring.menu.animate {
                        button.alpha = 1
                        button.transform = .identity
                    }
                }
            }
        }
        for (emoji, button) in reactionButtons where newButtons[emoji] == nil {
            if animated {
                UIView.animate(withDuration: 0.18, animations: {
                    button.alpha = 0
                    button.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
                }, completion: { _ in button.removeFromSuperview() })
            } else {
                button.removeFromSuperview()
            }
        }
        reactionButtons = newButtons

        let applyFrames = {
            self.bubbleView.bounds = CGRect(origin: .zero, size: newLayout.bubbleFrame.size)
            self.bubbleView.center = newLayout.bubbleFrame.center
            self.backgroundImageView.frame = CGRect(origin: .zero, size: newLayout.bubbleFrame.size).insetBy(dx: -BubbleImages.padding, dy: -BubbleImages.padding)
            self.textView.frame = newLayout.textFrame
            self.statusView.frame = newLayout.statusFrame
            self.statusView.layoutContent()
            if isPhoto {
                self.photoStatus.frame = newLayout.statusFrame
                self.photoStatus.layoutIfNeeded()
            }
            if let replyView = self.replyView, let frame = newLayout.replyFrame {
                replyView.frame = frame
                replyView.layoutIfNeeded()
            }
            for (button, frame) in buttonFrames {
                button.bounds = CGRect(origin: .zero, size: frame.size)
                button.center = frame.center
                button.layoutIfNeeded()
            }
        }
        if animated, let spring = transition.spring {
            spring.animate(applyFrames)
            for view in appearingViews {
                view.alpha = 0
                UIView.animate(withDuration: 0.2) { view.alpha = 1 }
            }
        } else {
            UIView.performWithoutAnimation(applyFrames)
        }
    }

    private var searchHighlights: [UIView] = []

    /// Telegram search: matched characters get a yellow marker behind the text.
    func setSearchHighlights(_ ranges: [Range<Int>]) {
        var rects: [CGRect] = []
        if let layout = layout, layout.photoFrame == nil {
            let cells = layout.textLayout.cells
            for range in ranges {
                var lines: [Int: CGRect] = [:]
                for i in range where i < cells.count && cells[i].visible {
                    lines[cells[i].line] = lines[cells[i].line].map { $0.union(cells[i].rect) } ?? cells[i].rect
                }
                rects += lines.values.map { $0.offsetBy(dx: layout.textFrame.minX, dy: layout.textFrame.minY).insetBy(dx: -2, dy: 1.5) }
            }
        }
        // Keep markers that did not move; grow new ones from their left edge, fade the rest.
        var kept: [UIView] = []
        for marker in searchHighlights {
            if let match = rects.firstIndex(where: { abs($0.minX - marker.frame.minX) < 0.5 && abs($0.minY - marker.frame.minY) < 0.5 }) {
                let rect = rects.remove(at: match)
                if abs(rect.width - marker.frame.width) > 0.5 {
                    UIView.animate(springDuration: 0.25, bounce: 0) { marker.frame = rect }
                }
                kept.append(marker)
            } else {
                UIView.animate(withDuration: 0.15, animations: { marker.alpha = 0 }, completion: { _ in marker.removeFromSuperview() })
            }
        }
        for rect in rects {
            let marker = UIView(frame: CGRect(x: rect.minX, y: rect.minY, width: min(rect.width, 6), height: rect.height))
            marker.backgroundColor = UIColor(rgb: 0xffd53d)
            marker.layer.cornerRadius = 4
            marker.layer.cornerCurve = .continuous
            marker.isUserInteractionEnabled = false
            marker.alpha = 0
            bubbleView.insertSubview(marker, belowSubview: textView)
            UIView.animate(springDuration: 0.3, bounce: 0) {
                marker.alpha = 1
                marker.frame = rect
            }
            kept.append(marker)
        }
        searchHighlights = kept
    }

    /// The picture's own outline: bubble corners pulled in by the photo inset.
    static func photoPath(size: CGSize, outgoing: Bool, position: BubbleGroupPosition) -> CGPath {
        let big = BubbleImages.maxCornerRadius - MessageLayout.photoInset
        let small = BubbleImages.minCornerRadius - MessageLayout.photoInset
        // Radii in outgoing orientation (tail side on the right).
        var tl = big, tr = big, bl = big, br = big
        switch position {
        case .single: break
        case .first: br = small
        case .middle: tr = small; br = small
        case .last: tr = small
        }
        if !outgoing { swap(&tl, &tr); swap(&bl, &br) }
        return UIBezierPath.roundedRect(size: size, tl: tl, tr: tr, br: br, bl: bl).cgPath
    }

    /// Photo frame in another view's coordinates (search flights land here).
    func photoFrame(in view: UIView) -> CGRect? {
        guard let frame = layout?.photoFrame else { return nil }
        let center = bubbleView.center
        let size = bubbleView.bounds.size
        let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        return convert(frame.offsetBy(dx: origin.x, dy: origin.y), to: view)
    }

    /// Telegram flashes the bubble with its highlighted fill when you jump to a message.
    func flashHighlight() {
        guard let layout = layout else { return }
        let highlighted = UIImageView(image: BubbleImages.image(outgoing: layout.message.isOutgoing, position: layout.position, highlighted: true))
        highlighted.frame = backgroundImageView.frame
        bubbleView.insertSubview(highlighted, aboveSubview: backgroundImageView)
        highlighted.alpha = 0
        UIView.animate(withDuration: 0.2, animations: { highlighted.alpha = 1 }, completion: { _ in
            UIView.animate(withDuration: 0.6, delay: 0.7, options: [], animations: { highlighted.alpha = 0 }, completion: { _ in highlighted.removeFromSuperview() })
        })
    }
}

extension UIBezierPath {
    static func roundedRect(size: CGSize, tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat) -> UIBezierPath {
        let w = size.width, h = size.height
        let path = UIBezierPath()
        path.move(to: CGPoint(x: tl, y: 0))
        path.addLine(to: CGPoint(x: w - tr, y: 0))
        path.addArc(withCenter: CGPoint(x: w - tr, y: tr), radius: tr, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(withCenter: CGPoint(x: w - br, y: h - br), radius: br, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: bl, y: h))
        path.addArc(withCenter: CGPoint(x: bl, y: h - bl), radius: bl, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(withCenter: CGPoint(x: tl, y: tl), radius: tl, startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        path.close()
        return path
    }
}

/// Time on a photo: white text on a dark translucent capsule (Telegram media date node).
final class PhotoStatusView: UIView {
    private let label = UILabel()
    private let checks = UIImageView()
    private var outgoing = false
    static let height: CGFloat = 18.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor(white: 0, alpha: 0.3)
        layer.cornerRadius = PhotoStatusView.height / 2
        label.font = Theme.dateFont
        label.textColor = .white
        addSubview(label)
        addSubview(checks)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func width(text: String, outgoing: Bool) -> CGFloat {
        let labelWidth = ceilToPixel((text as NSString).size(withAttributes: [.font: Theme.dateFont]).width)
        return labelWidth + 12 + (outgoing ? 19 : 0)
    }

    func update(text: String, outgoing: Bool, read: Bool) {
        label.text = text
        self.outgoing = outgoing
        checks.isHidden = !outgoing
        if outgoing { checks.image = Icons.checks(read: read, color: .white) }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let labelWidth = ceilToPixel(label.intrinsicContentSize.width)
        label.frame = CGRect(x: 6, y: 2, width: labelWidth + 1, height: 14)
        checks.frame = CGRect(x: 6 + labelWidth + 3, y: 4, width: 16, height: 10)
    }
}
