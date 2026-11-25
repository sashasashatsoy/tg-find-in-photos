import UIKit

enum InputMode: Equatable {
    case normal
    case reply(messageId: Int, preview: ReplyPreview)
    case edit(messageId: Int, preview: ReplyPreview)
}

/// Telegram composer, iOS 26 glass design: a glass attach circle, a glass capsule with the
/// text field (and the reply/edit quote on top when active), and a glass mic circle that
/// gives way to the blue send pill as soon as there is text.
final class InputPanelView: UIView, UITextViewDelegate {
    let textView = UITextView()
    private let attachGlass = GlassSurfaceView(interactive: true)
    private let attachIcon = UIImageView(image: UIImage(named: "TGIconAttachment"))
    private let attachButton = UIButton(type: .custom)
    private let fieldGlass = GlassSurfaceView(cornerRadius: 20, interactive: true)
    private let placeholder = UILabel()
    private let stickerButton = UIButton(type: .custom)
    private let micGlass = GlassSurfaceView(interactive: true)
    private let micIcon = UIImageView(image: UIImage(named: "TGIconMicrophone"))
    private let sendPill = UIView()
    private let sendIcon = UIImageView()
    private let sendButton = UIButton(type: .custom)
    private let accessory = AccessoryQuoteView()

    private(set) var mode: InputMode = .normal
    /// Kept for API compatibility: the glass composer floats, so no inset is added inside it.
    var bottomInset: CGFloat = 0

    var onSend: ((String) -> Void)?
    var onCancelAccessory: (() -> Void)?
    var onHeightChange: (() -> Void)?
    var onAttach: (() -> Void)?

    static let minFieldHeight: CGFloat = 40.0
    static let maxFieldHeight: CGFloat = 40.0 + 22.0 * 5
    static let accessoryHeight: CGFloat = 46.0
    private var fieldHeight: CGFloat = minFieldHeight
    private var showsSend = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        addSubview(attachGlass)
        attachIcon.tintColor = .black
        attachIcon.contentMode = .center
        attachGlass.contentView.addSubview(attachIcon)
        attachButton.accessibilityLabel = "Attach"
        attachButton.addTarget(self, action: #selector(attachTapped), for: .touchUpInside)
        addSubview(attachButton)

        addSubview(fieldGlass)
        accessory.alpha = 0
        accessory.closeButton.addTarget(self, action: #selector(cancelAccessory), for: .touchUpInside)
        addSubview(accessory)

        textView.font = Theme.messageFont
        textView.textColor = .black
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 9.5, left: 8, bottom: 9.5, right: 36)
        textView.textContainer.lineFragmentPadding = 4
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.scrollsToTop = false
        textView.keyboardAppearance = .light
        textView.tintColor = Theme.accent
        textView.accessibilityLabel = "Message"
        addSubview(textView)

        placeholder.text = "Message"
        placeholder.font = Theme.messageFont
        placeholder.textColor = UIColor(white: 0, alpha: 0.4)
        placeholder.isUserInteractionEnabled = false
        addSubview(placeholder)

        let stickerImage = UIImage(named: "TGAccessoryIconStickers")?.withRenderingMode(.alwaysTemplate)
        stickerButton.setImage(stickerImage, for: .normal)
        stickerButton.tintColor = UIColor(white: 0, alpha: 0.5)
        stickerButton.accessibilityLabel = "Stickers and emoji"
        addSubview(stickerButton)

        addSubview(micGlass)
        micIcon.tintColor = .black
        micIcon.contentMode = .center
        micGlass.contentView.addSubview(micIcon)

        sendPill.backgroundColor = Theme.accent
        sendPill.layer.cornerRadius = 17
        sendPill.isUserInteractionEnabled = false
        sendPill.transform = CGAffineTransform(scaleX: 0.001, y: 0.001)
        sendPill.alpha = 0
        addSubview(sendPill)
        sendIcon.tintColor = .white
        sendIcon.contentMode = .center
        sendPill.addSubview(sendIcon)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.accessibilityLabel = "Send"
        addSubview(sendButton)
        updateSendIcon()
    }

    required init?(coder: NSCoder) { fatalError() }

    var hasAccessory: Bool { mode != .normal }
    private var accessoryHeight: CGFloat { hasAccessory ? InputPanelView.accessoryHeight : 0 }

    /// Height of the composer row.
    var contentHeight: CGFloat { accessoryHeight + fieldHeight }
    var preferredHeight: CGFloat { contentHeight }

    var text: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            textDidChange(animated: false)
        }
    }

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Window-space origin of the first text line, used to fly a sent message into its bubble.
    var textOriginInWindow: CGPoint {
        let caret = textView.caretRect(for: textView.beginningOfDocument)
        let lineTop = CGPoint(x: textView.textContainerInset.left + textView.textContainer.lineFragmentPadding, y: caret.minY + (caret.height - TextLayout.lineHeight) / 2)
        return textView.convert(lineTop, to: nil)
    }

    func setMode(_ newMode: InputMode, animated: Bool) {
        let hadAccessory = hasAccessory
        mode = newMode
        switch newMode {
        case .normal:
            break
        case let .reply(_, preview):
            accessory.configure(title: "Reply to \(preview.title)", text: preview.text)
        case let .edit(_, preview):
            accessory.configure(title: "Edit Message", text: preview.text)
        }
        if hasAccessory && !hadAccessory {
            accessory.alpha = 0
        }
        updateSendIcon()
        refreshSendVisibility(animated: animated)
        onHeightChange?()
    }

    private var isEditingMessage: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func updateSendIcon() {
        if isEditingMessage {
            sendIcon.image = Icons.symbol("checkmark", size: 15, weight: .bold, color: .white)
            sendButton.accessibilityLabel = "Save"
        } else {
            sendIcon.image = UIImage(named: "TGSendIcon")?.withRenderingMode(.alwaysTemplate)
            sendButton.accessibilityLabel = "Send"
        }
    }

    func layoutContent() {
        let width = bounds.width
        let height = contentHeight
        let rowBottom = height

        attachGlass.frame = CGRect(x: 8, y: rowBottom - 40, width: 40, height: 40)
        attachIcon.frame = attachGlass.bounds
        attachButton.frame = attachGlass.frame.insetBy(dx: -4, dy: -4)

        let fieldX: CGFloat = 54
        let fieldRight = showsSend ? width - 8 : width - 54
        let fieldWidth = fieldRight - fieldX
        let fieldFrame = CGRect(x: fieldX, y: 0, width: fieldWidth, height: height)
        fieldGlass.frame = fieldFrame

        accessory.frame = CGRect(x: fieldX, y: 0, width: fieldWidth, height: InputPanelView.accessoryHeight)
        accessory.alpha = hasAccessory ? 1 : 0

        let textTop = accessoryHeight
        let rightReserve: CGFloat = 36 + (showsSend ? 46 : 0)
        textView.textContainerInset.right = rightReserve
        textView.frame = CGRect(x: fieldX, y: textTop, width: fieldWidth, height: fieldHeight)
        placeholder.frame = CGRect(x: fieldX + 12, y: textTop + 9.5, width: max(0, fieldWidth - 12 - rightReserve), height: 21)

        stickerButton.frame = CGRect(x: fieldRight - 4 - 32 - (showsSend ? 46 : 0), y: rowBottom - 36, width: 32, height: 32)

        let sendFrame = CGRect(x: fieldRight - 46, y: rowBottom - 40, width: 46, height: 40)
        sendPill.bounds = CGRect(x: 0, y: 0, width: 40, height: 34)
        sendPill.center = sendFrame.center
        sendIcon.frame = sendPill.bounds
        sendButton.frame = sendFrame

        micGlass.frame = CGRect(x: width - 48, y: rowBottom - 40, width: 40, height: 40)
        micIcon.frame = micGlass.bounds
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutContent()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self {
            // Taps on the field's glass focus the text view; the transparent gaps pass through.
            return fieldGlass.frame.contains(point) ? textView : nil
        }
        return hit
    }

    // MARK: - Text

    func textViewDidChange(_ textView: UITextView) {
        textDidChange(animated: true)
    }

    private func textDidChange(animated: Bool) {
        placeholder.isHidden = !(textView.text ?? "").isEmpty
        refreshSendVisibility(animated: animated)
        let fitting = textView.sizeThatFits(CGSize(width: max(100, textView.bounds.width), height: .greatestFiniteMagnitude)).height
        let newHeight = min(InputPanelView.maxFieldHeight, max(InputPanelView.minFieldHeight, ceil(fitting)))
        textView.isScrollEnabled = fitting > InputPanelView.maxFieldHeight
        if abs(newHeight - fieldHeight) > 0.5 {
            fieldHeight = newHeight
            onHeightChange?()
        }
    }

    private func refreshSendVisibility(animated: Bool) {
        let shouldShow = isEditingMessage || !trimmedText.isEmpty
        sendButton.isEnabled = !trimmedText.isEmpty
        let pillAlpha: CGFloat = shouldShow ? (trimmedText.isEmpty ? 0.5 : 1) : 0
        guard shouldShow != showsSend else {
            sendPill.alpha = pillAlpha
            return
        }
        showsSend = shouldShow
        sendButton.isUserInteractionEnabled = shouldShow
        let changes = {
            self.layoutContent()
            self.sendPill.alpha = pillAlpha
            self.sendPill.transform = shouldShow ? .identity : CGAffineTransform(scaleX: 0.001, y: 0.001)
            self.micGlass.alpha = shouldShow ? 0 : 1
            self.micGlass.transform = shouldShow ? CGAffineTransform(translationX: 56, y: 0) : .identity
        }
        if shouldShow {
            sendIcon.transform = CGAffineTransform(translationX: -22, y: 18)
        }
        if animated {
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                changes()
                self.sendIcon.transform = .identity
            })
        } else {
            changes()
            sendIcon.transform = .identity
        }
    }

    /// Scripted tap on the send/confirm pill (promo recording). Returns its frame in window space.
    @discardableResult
    func simulateSendTap() -> CGRect {
        let frame = sendPill.convert(sendPill.bounds, to: nil)
        UIView.animate(withDuration: 0.1, animations: { self.sendPill.transform = CGAffineTransform(scaleX: 0.88, y: 0.88) }, completion: { _ in
            UIView.animate(withDuration: 0.2) { self.sendPill.transform = .identity }
            self.sendTapped()
        })
        return frame
    }

    @objc private func sendTapped() {
        let value = trimmedText
        guard !value.isEmpty else { return }
        Haptics.impact(.light)
        onSend?(value)
    }

    @objc private func cancelAccessory() { onCancelAccessory?() }
    @objc private func attachTapped() { onAttach?() }
}

/// Reply / edit quote shown at the top of the glass input capsule.
private final class AccessoryQuoteView: UIView {
    private let quote = UIView()
    private let bar = UIView()
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    let closeButton = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        quote.backgroundColor = Theme.accent.withAlphaComponent(0.1)
        quote.layer.cornerRadius = 10
        quote.layer.cornerCurve = .continuous
        quote.clipsToBounds = true
        quote.isUserInteractionEnabled = false
        addSubview(quote)
        bar.backgroundColor = Theme.accent
        quote.addSubview(bar)
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = Theme.accent
        quote.addSubview(titleLabel)
        textLabel.font = UIFont.systemFont(ofSize: 14)
        textLabel.textColor = .black
        quote.addSubview(textLabel)
        closeButton.setImage(Icons.symbol("xmark", size: 13, weight: .semibold, color: UIColor(white: 0, alpha: 0.5)), for: .normal)
        closeButton.accessibilityLabel = "Cancel"
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, text: String) {
        titleLabel.text = title
        textLabel.text = text.replacingOccurrences(of: "\n", with: " ")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        quote.frame = CGRect(x: 6, y: 6, width: bounds.width - 6 - 38, height: bounds.height - 8)
        bar.frame = CGRect(x: 0, y: 0, width: 3, height: quote.bounds.height)
        titleLabel.frame = CGRect(x: 10, y: 2.5, width: quote.bounds.width - 16, height: 17)
        textLabel.frame = CGRect(x: 10, y: 19.5, width: quote.bounds.width - 16, height: 17)
        closeButton.frame = CGRect(x: bounds.width - 38, y: 4, width: 34, height: bounds.height - 4)
    }
}
