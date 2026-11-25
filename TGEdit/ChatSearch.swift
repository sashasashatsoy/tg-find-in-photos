import UIKit

// MARK: - Top bar

/// Telegram iOS 26 in-chat search field: a glass capsule where the header was, and a glass
/// close circle. When the query reads as a description of a picture, the magnifier turns into
/// the AI sparkle and the capsule glows while the photos are being looked at.
final class ChatSearchBar: UIView, UITextFieldDelegate {
    private let fieldGlass = GlassSurfaceView(cornerRadius: 25, interactive: true)
    let glow = AIGlowBorder(cornerRadius: 25, lineWidth: 2, glow: 7)
    private let magnifier = UIImageView(image: Icons.symbol("magnifyingglass", size: 17, weight: .medium, color: UIColor(white: 0, alpha: 0.45)))
    private let sparkle = GradientSymbolView(symbol: "sparkle.magnifyingglass", size: 18, weight: .semibold)
    let field = UITextField()
    private let clearButton = UIButton(type: .custom)
    private let closeGlass = GlassSurfaceView(interactive: true)
    var closeFrame: CGRect { closeGlass.frame }
    private let closeIcon = UIImageView(image: Icons.symbol("xmark", size: 18, weight: .regular, color: .black))
    private let closeButton = UIButton(type: .custom)
    private var aiMode = false

    var onChange: ((String) -> Void)?
    var onClose: (() -> Void)?
    var onFocus: (() -> Void)?

    static let height: CGFloat = 50

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(glow)
        addSubview(fieldGlass)
        magnifier.contentMode = .center
        addSubview(magnifier)
        sparkle.alpha = 0
        addSubview(sparkle)
        field.font = UIFont.systemFont(ofSize: 17)
        field.textColor = .black
        field.tintColor = Theme.accent
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.keyboardAppearance = .light
        field.attributedPlaceholder = NSAttributedString(string: "Search", attributes: [.foregroundColor: UIColor(white: 0, alpha: 0.4)])
        field.delegate = self
        field.addTarget(self, action: #selector(changed), for: .editingChanged)
        addSubview(field)
        clearButton.setImage(Icons.symbol("xmark.circle.fill", size: 17, weight: .regular, color: UIColor(white: 0, alpha: 0.85)), for: .normal)
        clearButton.accessibilityLabel = "Clear"
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        clearButton.alpha = 0
        addSubview(clearButton)
        addSubview(closeGlass)
        closeIcon.contentMode = .center
        closeGlass.contentView.addSubview(closeIcon)
        closeButton.accessibilityLabel = "Close search"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self { return fieldGlass.frame.contains(point) ? field : nil }
        return hit
    }

    var text: String {
        get { field.text ?? "" }
        set { field.text = newValue; refreshClear() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = ChatSearchBar.height
        let fieldFrame = CGRect(x: 16, y: 0, width: w - 16 - 10 - h - 16, height: h)
        fieldGlass.frame = fieldFrame
        glow.frame = fieldFrame
        magnifier.frame = CGRect(x: fieldFrame.minX + 8, y: 0, width: 32, height: h)
        sparkle.frame = magnifier.frame
        field.frame = CGRect(x: fieldFrame.minX + 44, y: 0, width: fieldFrame.width - 44 - 40, height: h)
        clearButton.frame = CGRect(x: fieldFrame.maxX - 42, y: 0, width: 40, height: h)
        closeGlass.frame = CGRect(x: w - 16 - h, y: 0, width: h, height: h)
        closeIcon.frame = closeGlass.bounds
        closeButton.frame = closeGlass.frame.insetBy(dx: -4, dy: -4)
    }

    private var contentViews: [UIView] { [magnifier, sparkle, field, clearButton, closeIcon] }

    /// Grows out of the header: the title capsule stretches into the field, the avatar circle
    /// becomes the close button.
    func morphIn(fromTitle title: CGRect, fromAvatar avatar: CGRect) {
        alpha = 1
        isHidden = false
        layoutIfNeeded()
        let fieldTarget = fieldGlass.frame, closeTarget = closeGlass.frame
        fieldGlass.frame = title
        glow.frame = title
        closeGlass.frame = avatar
        closeIcon.frame = closeGlass.bounds
        let contentAlpha = contentViews.map(\.alpha)
        contentViews.forEach { $0.alpha = 0 }
        UIView.animate(springDuration: 0.5, bounce: 0.12) {
            self.fieldGlass.frame = fieldTarget
            self.glow.frame = fieldTarget
            self.closeGlass.frame = closeTarget
            self.closeIcon.frame = self.closeGlass.bounds
        }
        UIView.animate(withDuration: 0.25, delay: 0.12, options: [.curveEaseOut]) {
            for (view, value) in zip(self.contentViews, contentAlpha) { view.alpha = value }
        }
    }

    func morphOut(toTitle title: CGRect, toAvatar avatar: CGRect, completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.12) { self.contentViews.forEach { $0.alpha = 0 } }
        UIView.animate(springDuration: 0.42, bounce: 0.05, initialSpringVelocity: 0, delay: 0, options: [], animations: {
            self.fieldGlass.frame = title
            self.glow.frame = title
            self.closeGlass.frame = avatar
            self.closeIcon.frame = self.closeGlass.bounds
            self.fieldGlass.alpha = 0
            self.closeGlass.alpha = 0
        }, completion: { _ in
            self.isHidden = true
            self.fieldGlass.alpha = 1
            self.closeGlass.alpha = 1
            self.magnifier.alpha = 1
            self.field.alpha = 1
            self.closeIcon.alpha = 1
            self.sparkle.alpha = 0
            self.aiMode = false
            self.setNeedsLayout()
            completion()
        })
    }

    func setAIMode(_ ai: Bool) {
        guard ai != aiMode else { return }
        aiMode = ai
        if ai { sparkle.transform = CGAffineTransform(scaleX: 0.4, y: 0.4).rotated(by: -0.6) }
        UIView.animate(springDuration: 0.45, bounce: 0.35) {
            self.sparkle.alpha = ai ? 1 : 0
            self.sparkle.transform = ai ? .identity : CGAffineTransform(scaleX: 0.4, y: 0.4)
            self.magnifier.alpha = ai ? 0 : 1
            self.magnifier.transform = ai ? CGAffineTransform(scaleX: 0.4, y: 0.4) : .identity
        }
    }

    private func refreshClear() {
        let visible = !(field.text ?? "").isEmpty
        UIView.animate(withDuration: 0.15) { self.clearButton.alpha = visible ? 1 : 0 }
    }

    @objc private func changed() {
        refreshClear()
        onChange?(text)
    }

    @objc private func clearTapped() {
        text = ""
        onChange?("")
        field.becomeFirstResponder()
    }

    @objc private func closeTapped() { onClose?() }

    func textFieldDidBeginEditing(_ textField: UITextField) { onFocus?() }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func simulateType(_ character: Character) {
        field.text = text + String(character)
        changed()
    }
}

// MARK: - Bottom controls

/// Telegram's floating search controls: "1 of N" with the calendar on the left, "Show as List"
/// on the right, up/down circles above it — plus the new AI pill with the photos it found.
final class ChatSearchControls: UIView {
    enum AIState: Equatable {
        case hidden
        case offer
        case thinking
        case none
        case found(count: Int)
        case active(count: Int)
    }

    private let counterGlass = GlassSurfaceView(interactive: true)
    private let calendarIcon = UIImageView(image: Icons.symbol("calendar", size: 17, weight: .regular, color: UIColor(white: 0, alpha: 0.55)))
    private let counterLabel = UILabel()
    private let counterSparkle = GradientSymbolView(symbol: "sparkles", size: 13, weight: .semibold)
    private let toggleGlass = GlassSurfaceView(interactive: true)
    private let toggleLabel = UILabel()
    let toggleButton = UIButton(type: .custom)
    private let upGlass = GlassSurfaceView(interactive: true)
    private let downGlass = GlassSurfaceView(interactive: true)
    private let upIcon = UIImageView()
    private let downIcon = UIImageView()
    let upButton = UIButton(type: .custom)
    let downButton = UIButton(type: .custom)
    private let aiGlass = GlassSurfaceView(interactive: true)
    let aiGlow = AIGlowBorder(cornerRadius: 23, lineWidth: 2, glow: 7)
    private let aiIcon = GradientSymbolView(symbol: "sparkles", size: 14, weight: .semibold)
    private let aiLabel = UILabel()
    private let aiClose = UIImageView(image: Icons.symbol("xmark", size: 11, weight: .bold, color: UIColor(white: 0, alpha: 0.45)))
    private var thumbs: [UIImageView] = []
    let aiButton = UIButton(type: .custom)
    private(set) var ai: AIState = .hidden
    private var photoMode = false

    static let row: CGFloat = 46
    static let height: CGFloat = row * 3 + 18

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(counterGlass)
        calendarIcon.contentMode = .center
        addSubview(calendarIcon)
        counterSparkle.alpha = 0
        addSubview(counterSparkle)
        counterLabel.font = UIFont.systemFont(ofSize: 17)
        addSubview(counterLabel)
        addSubview(toggleGlass)
        toggleLabel.font = UIFont.systemFont(ofSize: 17)
        toggleLabel.textColor = .black
        toggleLabel.textAlignment = .center
        addSubview(toggleLabel)
        addSubview(toggleButton)
        for (glass, icon, button, symbol, label) in [(upGlass, upIcon, upButton, "chevron.up", "Previous result"), (downGlass, downIcon, downButton, "chevron.down", "Next result")] {
            addSubview(glass)
            icon.image = Icons.symbol(symbol, size: 18, weight: .medium, color: .black)
            icon.contentMode = .center
            addSubview(icon)
            button.accessibilityLabel = label
            addSubview(button)
        }
        addSubview(aiGlow)
        addSubview(aiGlass)
        for _ in 0 ..< 3 {
            let thumb = UIImageView()
            thumb.contentMode = .scaleAspectFill
            thumb.clipsToBounds = true
            thumb.layer.cornerRadius = 13
            thumb.layer.borderColor = UIColor.white.cgColor
            thumb.layer.borderWidth = 2
            addSubview(thumb)
            thumbs.append(thumb)
        }
        addSubview(aiIcon)
        aiLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        aiLabel.textColor = .black
        addSubview(aiLabel)
        addSubview(aiClose)
        aiButton.accessibilityLabel = "Photos found by description"
        addSubview(aiButton)
        setAI(.hidden, thumbnails: [], animated: false)
        setArrows(up: nil, down: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    func setCounter(_ text: String, active: Bool, photos: Bool) {
        if let old = counterLabel.text, old != text, !old.isEmpty {
            let push = CATransition()
            push.type = .push
            push.subtype = .fromTop
            push.duration = 0.22
            push.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
            counterLabel.layer.add(push, forKey: "push")
        }
        counterLabel.text = text
        counterLabel.textColor = active ? .black : UIColor(white: 0, alpha: 0.45)
        photoMode = photos
        counterSparkle.alpha = photos ? 1 : 0
        calendarIcon.alpha = photos ? 0 : 1
        setNeedsLayout()
    }

    func setToggle(_ title: String) {
        if let old = toggleLabel.text, old != title {
            UIView.transition(with: toggleLabel, duration: 0.2, options: .transitionCrossDissolve, animations: nil)
        }
        toggleLabel.text = title
        setNeedsLayout()
    }

    func setArrows(up: Bool?, down: Bool?) {
        let visible = up != nil
        for view in [upGlass, downGlass, upIcon, downIcon, upButton, downButton] as [UIView] { view.alpha = visible ? 1 : 0 }
        upButton.isEnabled = up ?? false
        downButton.isEnabled = down ?? false
        upIcon.alpha = visible ? ((up ?? false) ? 1 : 0.3) : 0
        downIcon.alpha = visible ? ((down ?? false) ? 1 : 0.3) : 0
    }

    func setAI(_ state: AIState, thumbnails: [UIImage], animated: Bool) {
        let wasHidden = ai == .hidden
        ai = state
        switch state {
        case .hidden: aiLabel.text = nil
        case .offer: aiLabel.text = "Find in Photos"
        case .none: aiLabel.text = "No photos like that"
        case .thinking: aiLabel.text = "Looking at photos…"
        case let .found(count): aiLabel.text = count == 1 ? "1 photo matches" : "\(count) photos match"
        case let .active(count): aiLabel.text = count == 1 ? "1 photo" : "\(count) photos"
        }
        aiLabel.textColor = (state == .thinking || state == .none) ? UIColor(white: 0, alpha: 0.5) : .black
        setShimmer(state == .thinking)
        for (index, thumb) in thumbs.enumerated() {
            thumb.image = index < thumbnails.count ? thumbnails[index] : nil
            thumb.isHidden = index >= thumbnails.count || state == .thinking
        }
        aiClose.isHidden = !(state.isActive)
        aiGlow.set(visible: state == .thinking || state.isActive, duration: 0.3)
        let visible = state != .hidden
        let changes = {
            for view in [self.aiGlass, self.aiIcon, self.aiLabel, self.aiButton, self.aiClose] as [UIView] { view.alpha = visible ? 1 : 0 }
            self.thumbs.forEach { $0.alpha = visible ? 1 : 0 }
            self.layoutAI()
        }
        if animated {
            if wasHidden && visible {
                layoutAI()
                aiGlass.transform = CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.9, y: 0.9)
            }
            UIView.animate(springDuration: 0.45, bounce: 0.2) {
                changes()
                self.aiGlass.transform = .identity
            }
        } else {
            changes()
        }
    }

    var aiFrame: CGRect { aiGlass.frame }
    var toggleFrame: CGRect { toggleGlass.frame }
    var upFrame: CGRect { upGlass.frame }
    var aiCloseFrame: CGRect { aiClose.frame.insetBy(dx: -8, dy: -8) }

    /// "Looking at photos…" shimmers while the model works.
    private func setShimmer(_ on: Bool) {
        guard on else { aiLabel.layer.mask = nil; return }
        guard aiLabel.layer.mask == nil else { return }
        let mask = CAGradientLayer()
        mask.colors = [UIColor(white: 0, alpha: 0.45).cgColor, UIColor.black.cgColor, UIColor(white: 0, alpha: 0.45).cgColor]
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        mask.locations = [-0.6, -0.3, 0]
        mask.frame = CGRect(x: 0, y: 0, width: 260, height: ChatSearchControls.row)
        let move = CABasicAnimation(keyPath: "locations")
        move.fromValue = [-0.6, -0.3, 0]
        move.toValue = [1, 1.3, 1.6]
        move.duration = 1.2
        move.repeatCount = .infinity
        mask.add(move, forKey: "shimmer")
        aiLabel.layer.mask = mask
    }

    private func layoutAI() {
        let rowY = bounds.height - ChatSearchControls.row
        let y = rowY - 10 - ChatSearchControls.row
        let visibleThumbs = thumbs.filter { !$0.isHidden && $0.image != nil }
        var x: CGFloat = 16 + 10
        for (index, thumb) in thumbs.enumerated() {
            thumb.frame = CGRect(x: x + CGFloat(index) * 18, y: y + 10, width: 26, height: 26)
        }
        if !visibleThumbs.isEmpty { x += CGFloat(visibleThumbs.count - 1) * 18 + 26 + 8 }
        aiIcon.frame = CGRect(x: x, y: y + 13, width: 18, height: 20)
        let labelWidth = ceil(aiLabel.intrinsicContentSize.width)
        aiLabel.frame = CGRect(x: x + 22, y: y, width: labelWidth, height: ChatSearchControls.row)
        var right = aiLabel.frame.maxX + 16
        if !aiClose.isHidden {
            aiClose.frame = CGRect(x: right - 4, y: y, width: 14, height: ChatSearchControls.row)
            aiClose.contentMode = .center
            right += 16
        }
        aiGlass.frame = CGRect(x: 16, y: y, width: right - 16, height: ChatSearchControls.row)
        aiGlow.frame = aiGlass.frame
        aiButton.frame = aiGlass.frame
        bringSubviewToFront(aiButton)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = ChatSearchControls.row
        let rowY = bounds.height - h
        let counterWidth = (photoMode ? 22 : 30) + ceil(counterLabel.intrinsicContentSize.width) + 32
        counterGlass.frame = CGRect(x: 16, y: rowY, width: max(110, counterWidth), height: h)
        calendarIcon.frame = CGRect(x: 30, y: rowY, width: 24, height: h)
        counterSparkle.frame = CGRect(x: 30, y: rowY + 13, width: 18, height: 20)
        counterLabel.frame = CGRect(x: photoMode ? 54 : 62, y: rowY, width: counterGlass.frame.maxX - (photoMode ? 54 : 62) - 14, height: h)
        let toggleWidth = ceil(toggleLabel.intrinsicContentSize.width) + 40
        toggleGlass.frame = CGRect(x: w - 16 - toggleWidth, y: rowY, width: toggleWidth, height: h)
        toggleLabel.frame = toggleGlass.frame
        toggleButton.frame = toggleGlass.frame
        downGlass.frame = CGRect(x: w - 16 - h, y: rowY - 10 - h, width: h, height: h)
        upGlass.frame = CGRect(x: w - 16 - h, y: downGlass.frame.minY - 8 - h, width: h, height: h)
        upIcon.frame = upGlass.frame
        downIcon.frame = downGlass.frame
        upButton.frame = upGlass.frame
        downButton.frame = downGlass.frame
        layoutAI()
    }
}

private extension ChatSearchControls.AIState {
    var isActive: Bool { if case .active = self { return true } else { return false } }
}

// MARK: - List

/// A result row as Telegram lists them: avatar, name, date with ticks, the line around the match.
final class ChatSearchRow: UIControl {
    let messageId: Int
    private let avatar: AvatarView
    private let nameLabel = UILabel()
    private let dateLabel = UILabel()
    private let checks = UIImageView()
    private let textLabel = UILabel()
    private let separator = UIView()

    static let height: CGFloat = 78

    init(message: Message, author: Peer, tokens: [String]) {
        messageId = message.id
        avatar = AvatarView(peer: author, fontSize: 20, rounded: true)
        super.init(frame: .zero)
        avatar.isUserInteractionEnabled = false
        addSubview(avatar)
        nameLabel.text = message.isOutgoing ? "You" : author.shortName
        nameLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        nameLabel.textColor = .black
        addSubview(nameLabel)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = Calendar.current.isDateInToday(message.date) ? "HH:mm" : "dd.MM."
        dateLabel.text = df.string(from: message.date)
        dateLabel.font = UIFont.systemFont(ofSize: 15)
        dateLabel.textColor = Theme.navSecondaryText
        dateLabel.textAlignment = .right
        addSubview(dateLabel)
        checks.image = message.isOutgoing ? Icons.checks(read: message.isRead, color: Theme.outgoingCheck) : nil
        checks.contentMode = .center
        addSubview(checks)
        textLabel.attributedText = ChatSearchRow.snippet(message.text, tokens: tokens)
        textLabel.numberOfLines = 2
        textLabel.lineBreakMode = .byTruncatingTail
        addSubview(textLabel)
        separator.backgroundColor = UIColor(white: 0, alpha: 0.12)
        addSubview(separator)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Gray text with the matched words in black, trimmed to start near the first match.
    static func snippet(_ fullText: String, tokens: [String]) -> NSAttributedString {
        var text = fullText.replacingOccurrences(of: "\n", with: " ")
        let ranges = ChatSearchHighlighter.ranges(in: text, tokens: tokens)
        if let first = ranges.first, first.lowerBound > 26 {
            let chars = Array(text)
            var start = first.lowerBound
            var spaces = 0
            while start > 0 && spaces < 3 { start -= 1; if chars[start] == " " { spaces += 1 } }
            text = "…" + String(chars[(start == 0 ? 0 : start + 1)...])
        }
        let result = NSMutableAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: Theme.navSecondaryText])
        let ns = text as NSString
        var utf16 = 0
        var index = 0
        let matched = ChatSearchHighlighter.ranges(in: text, tokens: tokens)
        for character in text {
            let length = character.utf16.count
            if matched.contains(where: { $0.contains(index) }) {
                result.addAttribute(.foregroundColor, value: UIColor.black, range: NSRange(location: utf16, length: length))
            }
            utf16 += length
            index += 1
        }
        _ = ns
        return result
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? UIColor(white: 0, alpha: 0.06) : .clear }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        avatar.frame = CGRect(x: 16, y: (bounds.height - 56) / 2, width: 56, height: 56)
        let dateWidth = ceil(dateLabel.intrinsicContentSize.width)
        dateLabel.frame = CGRect(x: bounds.width - 16 - dateWidth, y: 10, width: dateWidth, height: 20)
        checks.frame = CGRect(x: dateLabel.frame.minX - 20, y: 10, width: 18, height: 20)
        nameLabel.frame = CGRect(x: 84, y: 9, width: checks.frame.minX - 84 - 6, height: 22)
        textLabel.frame = CGRect(x: 84, y: 31, width: bounds.width - 84 - 16, height: 40)
        separator.frame = CGRect(x: 84, y: bounds.height - screenPixel, width: bounds.width - 84, height: screenPixel)
    }
}

/// "Show as List": message results as Telegram lists them, or — after "Find in Photos" — every
/// photo that fits the description, as a media grid in order of relevance.
final class ChatSearchListView: UIView {
    enum Content { case messages, photos }

    private let scroll = UIScrollView()
    private let header = UILabel()
    private let headerIcon = GradientSymbolView(symbol: "sparkles", size: 13, weight: .semibold)
    private let emptyLabel = UILabel()
    private var rows: [ChatSearchRow] = []
    private var tiles: [UIView] = []
    func tileFrame(_ index: Int) -> CGRect? { tiles.indices.contains(index) ? tiles[index].convert(tiles[index].bounds, to: nil) : nil }
    private(set) var content: Content = .messages
    var insets = UIEdgeInsets.zero { didSet { setNeedsLayout() } }
    var onMessage: ((Int) -> Void)?
    var onPhoto: ((Int, UIView) -> Void)?

    static let columns = 3
    static let gap: CGFloat = 2

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        scroll.contentInsetAdjustmentBehavior = .never
        addSubview(scroll)
        header.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        header.textColor = Theme.navSecondaryText
        scroll.addSubview(header)
        scroll.addSubview(headerIcon)
        emptyLabel.text = "No messages found"
        emptyLabel.font = UIFont.systemFont(ofSize: 17)
        emptyLabel.textColor = Theme.navSecondaryText
        emptyLabel.textAlignment = .center
        scroll.addSubview(emptyLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func clear() {
        rows.forEach { $0.removeFromSuperview() }
        rows = []
        tiles.forEach { $0.removeFromSuperview() }
        tiles = []
    }

    func showMessages(_ messages: [Message], store: ChatStore, tokens: [String]) {
        clear()
        content = .messages
        rows = messages.map { message in
            let row = ChatSearchRow(message: message, author: message.isOutgoing ? Peer.me : store.peer, tokens: tokens)
            row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
            scroll.addSubview(row)
            return row
        }
        emptyLabel.text = "No messages found"
        emptyLabel.isHidden = !messages.isEmpty
        header.isHidden = true
        headerIcon.isHidden = true
        setNeedsLayout()
    }

    func showPhotos(_ results: [RecallResult], animated: Bool) {
        clear()
        content = .photos
        header.text = results.count == 1 ? "1 PHOTO FITS THE DESCRIPTION" : "\(results.count) PHOTOS FIT THE DESCRIPTION"
        header.isHidden = false
        headerIcon.isHidden = false
        emptyLabel.text = "No photos like that"
        emptyLabel.isHidden = !results.isEmpty
        for (index, result) in results.enumerated() {
            let tile = UIView()
            tile.clipsToBounds = true
            let image = UIImageView(image: result.asset.image)
            image.contentMode = .scaleAspectFill
            image.tag = 1
            tile.addSubview(image)
            let shade = CAGradientLayer()
            shade.colors = [UIColor.clear.cgColor, UIColor(white: 0, alpha: 0.45).cgColor]
            shade.name = "shade"
            tile.layer.addSublayer(shade)
            let date = UILabel()
            date.text = RecallFormatting.shortDate.string(from: result.date)
            date.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            date.textColor = .white
            date.tag = 2
            tile.addSubview(date)
            tile.isAccessibilityElement = true
            tile.accessibilityTraits = .button
            tile.accessibilityLabel = "Photo from \(result.author.shortName), \(RecallFormatting.longDate.string(from: result.date))"
            tile.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tileTapped(_:))))
            scroll.addSubview(tile)
            tiles.append(tile)
            if animated {
                tile.alpha = 0
                tile.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
                UIView.animate(springDuration: 0.45, bounce: 0.1, initialSpringVelocity: 0, delay: 0.05 + Double(index) * 0.035, options: [.allowUserInteraction]) {
                    tile.alpha = 1
                    tile.transform = .identity
                }
            }
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        scroll.contentInset = insets
        scroll.verticalScrollIndicatorInsets = insets
        let w = bounds.width
        var y: CGFloat = 0
        switch content {
        case .messages:
            emptyLabel.frame = CGRect(x: 16, y: 40, width: w - 32, height: 24)
            for row in rows {
                row.frame = CGRect(x: 0, y: y, width: w, height: ChatSearchRow.height)
                y += ChatSearchRow.height
            }
        case .photos:
            headerIcon.frame = CGRect(x: 16, y: 10, width: 16, height: 18)
            header.frame = CGRect(x: 36, y: 10, width: w - 52, height: 18)
            y = 38
            emptyLabel.frame = CGRect(x: 16, y: y + 30, width: w - 32, height: 24)
            let n = CGFloat(ChatSearchListView.columns)
            let cell = floor((w - ChatSearchListView.gap * (n - 1)) / n)
            for (index, tile) in tiles.enumerated() {
                let column = CGFloat(index % ChatSearchListView.columns)
                let row = CGFloat(index / ChatSearchListView.columns)
                let x = column == n - 1 ? w - cell : column * (cell + ChatSearchListView.gap)
                tile.bounds = CGRect(x: 0, y: 0, width: cell, height: cell)
                tile.center = CGPoint(x: x + cell / 2, y: y + row * (cell + ChatSearchListView.gap) + cell / 2)
                tile.viewWithTag(1)?.frame = tile.bounds
                tile.viewWithTag(2)?.frame = CGRect(x: 8, y: cell - 24, width: cell - 16, height: 18)
                tile.layer.sublayers?.first { $0.name == "shade" }?.frame = CGRect(x: 0, y: cell * 0.6, width: cell, height: cell * 0.4)
            }
            let rows = ceil(CGFloat(tiles.count) / n)
            y += rows * cell + max(0, rows - 1) * ChatSearchListView.gap
        }
        scroll.contentSize = CGSize(width: w, height: max(y, emptyLabel.frame.maxY + 20))
    }

    @objc private func rowTapped(_ row: ChatSearchRow) { onMessage?(row.messageId) }

    @objc private func tileTapped(_ recognizer: UITapGestureRecognizer) {
        guard let tile = recognizer.view, let index = tiles.firstIndex(where: { $0 === tile }) else { return }
        UIView.animate(withDuration: 0.1, animations: { tile.transform = CGAffineTransform(scaleX: 0.95, y: 0.95) }, completion: { _ in
            UIView.animate(withDuration: 0.15) { tile.transform = .identity }
            self.onPhoto?(index, tile)
        })
    }
}

// MARK: - Highlighting

enum ChatSearchHighlighter {
    /// Character (grapheme) ranges of the query words in a text, prefix-matched like Telegram.
    static func ranges(in text: String, tokens: [String]) -> [Range<Int>] {
        guard !tokens.isEmpty else { return [] }
        let chars = Array(text)
        var result: [Range<Int>] = []
        var i = 0
        while i < chars.count {
            guard chars[i].isLetter || chars[i].isNumber else { i += 1; continue }
            var j = i
            while j < chars.count && (chars[j].isLetter || chars[j].isNumber) { j += 1 }
            let word = RecallMatcher.normalize(String(chars[i ..< j]))
            if let token = tokens.first(where: { word.hasPrefix(RecallMatcher.stem($0)) }) {
                result.append(i ..< min(j, i + max(token.count, RecallMatcher.stem(token).count)))
            }
            i = j
        }
        return result
    }
}

// MARK: - Controller

/// Telegram's in-chat search, as it is — results in the chat with the words highlighted, "1 of N",
/// arrows, "Show as List". Photos are searched only when asked: "Find in Photos" sends the same
/// words to the model, which finds the pictures that fit and lifts what it recognised on them.
final class PhotoRecallController {
    private unowned let host: UIView
    private let list: ChatListView
    private let inputPanel: InputPanelView
    private let navBar: NavigationBarView
    private let store: ChatStore

    let bar = ChatSearchBar()
    let controls = ChatSearchControls()
    private let listView = ChatSearchListView()
    private(set) var viewer: RecallViewer?
    private var lift: SubjectLiftView?

    private enum Mode { case text, photos }
    private(set) var isActive = false
    private var mode: Mode = .text
    private var showingList = false
    private var textHits: [Message] = []
    private var textIndex = 0
    private var photoHits: [RecallResult] = []
    private var photoQuery: String?
    private var photoIndex = 0
    private var searchingPhotos = false
    private var photoSearch: DispatchWorkItem?
    private var bottomY: CGFloat = 0
    private var controlsShown = false
    /// While the search controls float over the chat, the newest messages sit above them.
    private(set) var extraBottomInset: CGFloat = 0

    init(host: UIView, list: ChatListView, inputPanel: InputPanelView, navBar: NavigationBarView, store: ChatStore) {
        self.host = host
        self.list = list
        self.inputPanel = inputPanel
        self.navBar = navBar
        self.store = store
    }

    func install(blurAbove: UIView, chromeAbove: UIView) {
        for view in [controls, listView] as [UIView] {
            view.isHidden = true
            view.alpha = 0
        }
        bar.isHidden = true
        host.insertSubview(listView, aboveSubview: chromeAbove)
        host.insertSubview(controls, aboveSubview: listView)
        host.insertSubview(bar, aboveSubview: controls)
        bar.onChange = { [weak self] in self?.queryChanged($0) }
        bar.onClose = { [weak self] in self?.close() }
        controls.upButton.addTarget(self, action: #selector(stepUp), for: .touchUpInside)
        controls.downButton.addTarget(self, action: #selector(stepDown), for: .touchUpInside)
        controls.toggleButton.addTarget(self, action: #selector(toggleList), for: .touchUpInside)
        controls.aiButton.addTarget(self, action: #selector(aiTapped), for: .touchUpInside)
        listView.onMessage = { [weak self] in self?.listPickedMessage($0) }
        listView.onPhoto = { [weak self] index, _ in self?.listPickedPhoto(index) }
    }

    func layout(panelFrame: CGRect, navBottom: CGFloat) {
        bottomY = panelFrame.maxY
        let bounds = host.bounds
        bar.frame = CGRect(x: 0, y: host.safeAreaInsets.top + 4, width: bounds.width, height: ChatSearchBar.height)
        controls.frame = CGRect(x: 0, y: bottomY - ChatSearchControls.height, width: bounds.width, height: ChatSearchControls.height)
        listView.frame = bounds
        listView.insets = UIEdgeInsets(top: bar.frame.maxY + 10, left: 0, bottom: bounds.height - bottomY + ChatSearchControls.row * 2 + 24, right: 0)
        viewer?.frame = bounds
    }

    // MARK: Open / close

    func open() {
        guard !isActive else { return }
        isActive = true
        Haptics.impact(.light)
        inputPanel.isUserInteractionEnabled = false
        navBar.isUserInteractionEnabled = false
        bar.morphIn(fromTitle: navBar.convert(navBar.titlePillFrame, to: bar), fromAvatar: navBar.convert(navBar.avatarPillFrame, to: bar))
        UIView.animate(withDuration: 0.2) { self.navBar.alpha = 0 }
        UIView.animate(springDuration: 0.4, bounce: 0) {
            self.inputPanel.alpha = 0
            self.inputPanel.transform = CGAffineTransform(translationX: 0, y: 10)
        }
        bar.field.becomeFirstResponder()
    }

    func close() {
        guard isActive else { return }
        isActive = false
        photoSearch?.cancel()
        viewer?.removeFromSuperview()
        viewer = nil
        dropLift()
        bar.field.resignFirstResponder()
        bar.text = ""
        bar.setAIMode(false)
        bar.glow.set(visible: false)
        textHits = []
        photoHits = []
        photoQuery = nil
        searchingPhotos = false
        mode = .text
        applyHighlights(tokens: [])
        setList(false)
        setControlsVisible(false)
        controls.setAI(.hidden, thumbnails: [], animated: true)
        inputPanel.isUserInteractionEnabled = true
        navBar.isUserInteractionEnabled = true
        bar.morphOut(toTitle: navBar.convert(navBar.titlePillFrame, to: bar), toAvatar: navBar.convert(navBar.avatarPillFrame, to: bar)) {}
        UIView.animate(withDuration: 0.25, delay: 0.12, options: [.curveEaseOut]) { self.navBar.alpha = 1 }
        UIView.animate(springDuration: 0.45, bounce: 0.1) {
            self.inputPanel.alpha = 1
            self.inputPanel.transform = .identity
        }
    }

    // MARK: Regular search

    private var tokens: [String] { RecallMatcher.textTokens(bar.text) }

    private func queryChanged(_ query: String) {
        photoSearch?.cancel()
        searchingPhotos = false
        bar.glow.set(visible: false)
        if mode == .photos {
            mode = .text
            dropLift()
            bar.setAIMode(false)
        }
        let words = tokens
        guard !words.isEmpty else {
            textHits = []
            applyHighlights(tokens: [])
            controls.setAI(.hidden, thumbnails: [], animated: true)
            setControlsVisible(false)
            refreshList()
            return
        }
        // Instant, newest first, words highlighted right in the chat.
        textHits = RecallMatcher.messages(query, in: store)
        textIndex = 0
        setControlsVisible(true)
        applyHighlights(tokens: words)
        if !textHits.isEmpty && !showingList { scroll(to: textHits[0].id, animated: true) }
        controls.setAI(.offer, thumbnails: [], animated: true)
        updateControls()
        refreshList()
    }

    private func setControlsVisible(_ visible: Bool) {
        guard visible != controlsShown else { return }
        controlsShown = visible
        extraBottomInset = visible ? ChatSearchControls.row + 14 : 0
        host.setNeedsLayout()
        UIView.animate(springDuration: 0.45, bounce: 0) { self.host.layoutIfNeeded() }
        controls.isHidden = false
        if visible { controls.transform = CGAffineTransform(translationX: 0, y: 14) }
        UIView.animate(springDuration: 0.45, bounce: 0.1, initialSpringVelocity: 0, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.controls.alpha = visible ? 1 : 0
            self.controls.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 14)
        }, completion: { _ in
            if !self.controlsShown { self.controls.isHidden = true }
        })
    }

    private func updateControls() {
        controls.setToggle(showingList ? "Show as Chat" : "Show as List")
        switch mode {
        case .text:
            if textHits.isEmpty {
                controls.setCounter("No results", active: false, photos: false)
                controls.setArrows(up: nil, down: nil)
            } else if showingList {
                controls.setCounter(textHits.count == 1 ? "1 message" : "\(textHits.count) messages", active: false, photos: false)
                controls.setArrows(up: nil, down: nil)
            } else {
                controls.setCounter("\(textIndex + 1) of \(textHits.count)", active: false, photos: false)
                controls.setArrows(up: textIndex + 1 < textHits.count, down: textIndex > 0)
            }
        case .photos:
            if showingList {
                controls.setCounter(photoHits.count == 1 ? "1 photo" : "\(photoHits.count) photos", active: true, photos: true)
                controls.setArrows(up: nil, down: nil)
            } else {
                controls.setCounter("\(photoIndex + 1) of \(photoHits.count)", active: true, photos: true)
                controls.setArrows(up: photoIndex + 1 < photoHits.count, down: photoIndex > 0)
            }
        }
        UIView.animate(withDuration: 0.2) { self.controls.layoutIfNeeded() }
    }

    private func applyHighlights(tokens: [String]) {
        for cell in list.allCells {
            guard let message = cell.layout?.message, message.photo == nil else { continue }
            cell.setSearchHighlights(ChatSearchHighlighter.ranges(in: message.text, tokens: tokens))
        }
    }

    private func scroll(to id: Int, animated: Bool, completion: (() -> Void)? = nil) {
        guard let target = list.targetOffset(for: id, extraBottom: 110) else { completion?(); return }
        if animated && abs(list.contentOffset.y - target) > 1 {
            let distance = abs(list.contentOffset.y - target)
            let duration = min(0.75, 0.45 + Double(distance) / 6000)
            UIView.animate(springDuration: duration, bounce: 0, initialSpringVelocity: 0, delay: 0, options: [.allowUserInteraction], animations: {
                self.list.contentOffset = CGPoint(x: 0, y: target)
            })
            if let completion = completion {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.8, execute: completion)
            }
        } else {
            list.contentOffset = CGPoint(x: 0, y: target)
            completion?()
        }
    }

    @objc private func stepUp() { step(by: 1) }
    @objc private func stepDown() { step(by: -1) }

    private func step(by delta: Int) {
        Haptics.selection()
        switch mode {
        case .text:
            let index = textIndex + delta
            guard textHits.indices.contains(index) else { return }
            textIndex = index
            scroll(to: textHits[index].id, animated: true)
        case .photos:
            let index = photoIndex + delta
            guard photoHits.indices.contains(index) else { return }
            photoIndex = index
            showPhoto(at: index)
        }
        updateControls()
    }

    // MARK: Find in Photos

    private var thumbnails: [UIImage] { photoHits.prefix(3).map(\.asset.image) }

    @objc private func aiTapped() {
        guard !searchingPhotos else { return }
        Haptics.impact(.light)
        if mode == .photos {
            // Back to the regular results.
            mode = .text
            dropLift()
            bar.setAIMode(false)
            controls.setAI(.offer, thumbnails: [], animated: true)
            if showingList { refreshList() } else if !textHits.isEmpty { scroll(to: textHits[textIndex].id, animated: true) }
            updateControls()
            return
        }
        if photoQuery == bar.text {
            enterPhotos()
            return
        }
        // The model looks through the chat's photos for this description.
        let query = bar.text
        searchingPhotos = true
        bar.field.resignFirstResponder()
        bar.setAIMode(true)
        bar.glow.set(visible: true, duration: 0.2)
        controls.setAI(.thinking, thumbnails: [], animated: true)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.searchingPhotos = false
            self.photoHits = RecallMatcher.search(query, in: self.store)
            self.photoQuery = query
            self.bar.glow.set(visible: false, duration: 0.6)
            if self.photoHits.isEmpty {
                Haptics.impact(.rigid)
                self.bar.setAIMode(false)
                self.controls.setAI(.none, thumbnails: [], animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                    guard let self = self, self.controls.ai == .none else { return }
                    self.controls.setAI(.offer, thumbnails: [], animated: true)
                }
            } else {
                self.enterPhotos()
            }
        }
        photoSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    private func enterPhotos() {
        mode = .photos
        photoIndex = 0
        bar.setAIMode(true)
        controls.setAI(.active(count: photoHits.count), thumbnails: thumbnails, animated: true)
        if showingList {
            listView.showPhotos(photoHits, animated: true)
        } else {
            showPhoto(at: 0)
        }
        updateControls()
    }

    /// Jump to a found photo in the chat and lift what the AI recognised on it.
    private func showPhoto(at index: Int) {
        dropLift()
        let result = photoHits[index]
        scroll(to: result.messageId, animated: true) { [weak self] in
            guard let self = self, self.mode == .photos, self.photoIndex == index, !self.showingList else { return }
            self.liftPhoto(result)
        }
    }

    private func liftPhoto(_ result: RecallResult) {
        guard let cell = list.cell(for: result.messageId), let frame = cell.layout?.photoFrame else { return }
        let lift = SubjectLiftView(asset: result.asset, regions: result.matchedRegions, cornerRadius: BubbleImages.maxCornerRadius - MessageLayout.photoInset)
        lift.frame = frame
        cell.bubbleView.addSubview(lift)
        lift.onTap = { [weak self, weak lift] in
            guard let self = self, let lift = lift else { return }
            self.openViewer(result, from: lift)
        }
        self.lift = lift
        lift.lift()
    }

    private func dropLift() {
        guard let lift = lift else { return }
        self.lift = nil
        lift.drop { lift.removeFromSuperview() }
    }

    // MARK: List

    @objc private func toggleList() {
        Haptics.selection()
        setList(!showingList)
    }

    private func setList(_ show: Bool) {
        guard show != showingList else { return }
        showingList = show
        if show {
            dropLift()
            refreshList(animated: true)
            listView.isHidden = false
            listView.transform = CGAffineTransform(translationX: 0, y: 18)
        } else if mode == .photos {
            showPhoto(at: photoIndex)
        }
        UIView.animate(springDuration: 0.4, bounce: 0, initialSpringVelocity: 0, delay: 0, options: [.beginFromCurrentState], animations: {
            self.listView.alpha = show ? 1 : 0
            self.listView.transform = show ? .identity : CGAffineTransform(translationX: 0, y: 18)
        }, completion: { _ in
            if !self.showingList { self.listView.isHidden = true }
        })
        updateControls()
    }

    private func refreshList(animated: Bool = false) {
        guard showingList else { return }
        if mode == .photos {
            listView.showPhotos(photoHits, animated: animated)
        } else {
            listView.showMessages(textHits, store: store, tokens: tokens)
        }
        updateControls()
    }

    private func listPickedMessage(_ id: Int) {
        guard let index = textHits.firstIndex(where: { $0.id == id }) else { return }
        textIndex = index
        bar.field.resignFirstResponder()
        scroll(to: id, animated: false)
        setList(false)
        updateControls()
    }

    private func listPickedPhoto(_ index: Int) {
        guard photoHits.indices.contains(index) else { return }
        photoIndex = index
        bar.field.resignFirstResponder()
        if let target = list.targetOffset(for: photoHits[index].messageId, extraBottom: 110) {
            list.contentOffset = CGPoint(x: 0, y: target)
        }
        setList(false)
        updateControls()
    }

    // MARK: Viewer

    private func openViewer(_ result: RecallResult, from source: UIView) {
        guard viewer == nil else { return }
        Haptics.impact(.light)
        bar.field.resignFirstResponder()
        let viewer = RecallViewer(result: result, showsChatButton: false)
        self.viewer = viewer
        let frame = source.convert(source.bounds, to: host)
        source.alpha = 0
        let radius = BubbleImages.maxCornerRadius - MessageLayout.photoInset
        viewer.present(in: host, from: frame, radius: radius)
        viewer.onClose = { [weak self, weak viewer, weak source] in
            guard let self = self, let viewer = viewer else { return }
            let back = source.flatMap { $0.window != nil ? $0.convert($0.bounds, to: self.host) : nil }
            viewer.dismiss(to: back, radius: radius) {
                source?.alpha = 1
                self.viewer = nil
            }
        }
    }

    // MARK: Scripted run

    var promoAI: CGRect { controls.convert(controls.aiFrame, to: nil) }
    var promoAIClose: CGRect { controls.convert(controls.aiCloseFrame, to: nil) }
    var promoToggle: CGRect { controls.convert(controls.toggleFrame, to: nil) }
    var promoUp: CGRect { controls.convert(controls.upFrame, to: nil) }
    var promoClose: CGRect { bar.convert(bar.closeFrame, to: nil) }
    var promoLift: CGRect? { lift.map { $0.convert($0.bounds, to: nil) } }
    func promoTile(_ index: Int) -> CGRect? { listView.tileFrame(index) }
    func simulateSearchKey() { bar.field.resignFirstResponder() }
    func simulateStep(_ delta: Int) { step(by: delta) }
    func simulateClose() { close() }

    func simulateAITap() { aiTapped() }
    func simulateListToggle() { toggleList() }
    func simulatePickPhoto(_ index: Int) { listPickedPhoto(index) }
    func simulateOpenLifted() {
        guard let lift = lift, photoHits.indices.contains(photoIndex) else { return }
        openViewer(photoHits[photoIndex], from: lift)
    }
}

/// Scripted run of the scenario for recordings and review.
enum RecallDemo {
    static func run(on controller: ChatViewController) {
        let env = ProcessInfo.processInfo.environment
        let query = env["RECALL_QUERY"] ?? "black cat on the windowsill"
        let charDelay = Double(env["RECALL_CHAR"] ?? "") ?? 0.075
        let recall = controller.recall
        var t: Double = 1.0
        func at(_ time: Double, _ block: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + time, execute: block)
        }
        at(t) { controller.recallSimulateOpen() }
        t += 0.9
        for character in query {
            let time = t
            at(time) { recall.bar.simulateType(character) }
            t += character == " " ? 0.35 : charDelay
        }
        if env["RECALL_STOP"] == "typed" { return }
        t += 1.8
        at(t) { recall.simulateAITap() }
        if env["RECALL_STOP"] == "lift" { return }
        t += 4.2
        at(t) { recall.simulateListToggle() }
        t += 3.0
        at(t) { recall.simulatePickPhoto(1) }
        t += 3.2
        at(t) { recall.simulateOpenLifted() }
        t += 3.0
        at(t) { recall.viewer?.simulateClose() }
    }
}

/// Timeline for the promo video: when each scripted touch happened and where (window points).
enum PromoLog {
    static let url = FileManager.default.temporaryDirectory.appendingPathComponent("recall_promo.jsonl")

    static func reset() { try? FileManager.default.removeItem(at: url) }

    static func mark(_ name: String, _ rect: CGRect? = nil) {
        var item: [String: Any] = ["t": Date().timeIntervalSince1970, "name": name]
        if let r = rect { item["x"] = r.midX; item["y"] = r.midY; item["w"] = r.width; item["h"] = r.height; item["minX"] = r.minX; item["minY"] = r.minY }
        guard let data = try? JSONSerialization.data(withJSONObject: item), var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// `-recallPromo`: the whole feature in one take, for the promo video. Steps run one after another
/// (each waits for the previous one to have fired), so a busy frame never squeezes the pauses.
enum RecallPromo {
    static func run(on controller: ChatViewController) {
        PromoLog.reset()
        let recall = controller.recall
        let query = "black cat on the windowsill"
        var steps: [(TimeInterval, () -> Void)] = []
        func step(_ wait: TimeInterval, _ block: @escaping () -> Void) { steps.append((wait, block)) }

        // 1. Straight to the new button: open search, type the description.
        step(1.0) { PromoLog.mark("open", controller.promoTitleFrame); controller.recallSimulateOpen() }
        step(0.6) { PromoLog.mark("typeStart") }
        for character in query {
            step(character == " " ? 0.1 : 0.04) { recall.bar.simulateType(character) }
        }
        step(0.1) { PromoLog.mark("typeEnd") }
        step(0.45) { PromoLog.mark("searchKey", CGRect(x: 349, y: 773, width: 1, height: 1)); recall.simulateSearchKey() }
        // 2. The new button, zoomed in, then the AI.
        step(1.9) { PromoLog.mark("ai", recall.promoAI); recall.simulateAITap() }
        step(2.1) { PromoLog.mark("lifted", recall.promoLift) }
        step(1.5) { PromoLog.mark("up", recall.promoUp); recall.simulateStep(1) }
        step(1.7) { PromoLog.mark("grid", recall.promoToggle); recall.simulateListToggle() }
        step(2.6) { PromoLog.mark("tile", recall.promoTile(0)); recall.simulatePickPhoto(0) }
        step(1.9) { PromoLog.mark("liftTap", recall.promoLift); recall.simulateOpenLifted() }
        step(2.2) { PromoLog.mark("viewerClose", CGRect(x: 16, y: controller.view.safeAreaInsets.top + 8, width: 46, height: 46)); recall.viewer?.simulateClose() }
        step(1.1) { PromoLog.mark("aiClose", recall.promoAIClose); recall.simulateAITap() }
        step(1.2) { PromoLog.mark("close", recall.promoClose); recall.simulateClose() }
        step(1.1) { PromoLog.mark("end") }

        func next(_ index: Int) {
            guard index < steps.count else { return }
            let (wait, block) = steps[index]
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                block()
                next(index + 1)
            }
        }
        next(0)
    }
}
