import UIKit

enum ChatItemID: Hashable {
    case message(Int)
    case date(Date)
}

enum ListItem {
    case date(day: Date, text: String)
    case message(MessageLayout)

    var id: ChatItemID {
        switch self {
        case let .date(day, _): return .date(day)
        case let .message(layout): return .message(layout.message.id)
        }
    }

    var height: CGFloat {
        switch self {
        case .date: return DateHeaderView.height
        case let .message(layout): return layout.height
        }
    }
}

enum InsertionStyle {
    /// Outgoing message: the text travels from the input field into the bubble.
    case fromInput(textOrigin: CGPoint)
    /// Incoming message: slides up from under the input panel.
    case slideUp
    case fade
}

/// Bottom-anchored message list. The scroll view and every row are flipped vertically
/// (the same trick Telegram's ListView uses), so y = 0 is the newest message and a row that
/// changes height pushes only the older rows upward — no content-offset compensation needed.
final class ChatListView: UIScrollView, UIGestureRecognizerDelegate {
    private final class Row {
        let id: ChatItemID
        let container: UIView
        let content: UIView
        var y: CGFloat = 0
        var height: CGFloat = 0
        init(id: ChatItemID, content: UIView) {
            self.id = id
            self.content = content
            self.container = UIView()
            container.transform = CGAffineTransform(scaleX: 1, y: -1)
            container.addSubview(content)
        }
    }

    private var rows: [Row] = []
    private var rowById: [ChatItemID: Row] = [:]
    private(set) var items: [ListItem] = []

    var configureCell: ((MessageCellView) -> Void)?
    var onSwipeReply: ((Int) -> Void)?
    var swipeEnabled = true

    static let bottomPadding: CGFloat = 6.0
    static let topPadding: CGFloat = 8.0

    // Swipe to reply
    private var swipeRecognizer: UIPanGestureRecognizer!
    private var swipeCell: MessageCellView?
    private var swipeIcon: UIView?
    private var swipeTriggered = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        transform = CGAffineTransform(scaleX: 1, y: -1)
        alwaysBounceVertical = true
        showsHorizontalScrollIndicator = false
        keyboardDismissMode = .interactive
        contentInsetAdjustmentBehavior = .never
        delaysContentTouches = false
        swipeRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRecognizer.delegate = self
        addGestureRecognizer(swipeRecognizer)
        panGestureRecognizer.require(toFail: swipeRecognizer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesShouldCancel(in view: UIView) -> Bool { true }

    func cell(for messageId: Int) -> MessageCellView? {
        rowById[.message(messageId)]?.content as? MessageCellView
    }

    var allCells: [MessageCellView] { rows.compactMap { $0.content as? MessageCellView } }

    func layout(for messageId: Int) -> MessageLayout? {
        for item in items {
            if case let .message(layout) = item, layout.message.id == messageId { return layout }
        }
        return nil
    }

    // MARK: - Updates

    /// Applies a new item list (newest first). Existing rows animate to their new geometry with
    /// `spring`; per-message content transitions come from `transitions`.
    func apply(items newItems: [ListItem], spring: Spring?, transitions: [Int: CellTransition] = [:], insertions: [Int: InsertionStyle] = [:]) {
        let oldIds = Set(rows.map(\.id))
        let newIds = Set(newItems.map(\.id))
        items = newItems

        // Removals.
        for row in rows where !newIds.contains(row.id) {
            rowById[row.id] = nil
            if spring != nil {
                UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn], animations: {
                    row.content.alpha = 0
                    row.content.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
                }, completion: { _ in row.container.removeFromSuperview() })
            } else {
                row.container.removeFromSuperview()
            }
        }

        // Build / update rows.
        var newRows: [Row] = []
        var created: [Row] = []
        let width = bounds.width
        for item in newItems {
            let row: Row
            if let existing = rowById[item.id] {
                row = existing
            } else {
                let content: UIView
                switch item {
                case let .date(_, text):
                    content = DateHeaderView(text: text)
                case .message:
                    let cell = MessageCellView()
                    configureCell?(cell)
                    content = cell
                }
                row = Row(id: item.id, content: content)
                rowById[item.id] = row
                addSubview(row.container)
                created.append(row)
            }
            row.height = item.height
            newRows.append(row)
            if case let .message(layout) = item, let cell = row.content as? MessageCellView {
                let isNew = !oldIds.contains(item.id)
                let transition: CellTransition
                if isNew || spring == nil {
                    transition = .immediate
                } else {
                    transition = transitions[layout.message.id] ?? .animated(spring!)
                }
                cell.apply(layout, transition: transition)
            }
        }
        rows = newRows

        // Positions.
        var y = ChatListView.bottomPadding
        for (index, row) in rows.enumerated() {
            if index > 0 {
                y += spacing(between: newItems[index - 1], and: newItems[index])
            }
            row.y = y
            y += row.height
        }
        let contentHeight = y + ChatListView.topPadding

        let place = { (row: Row) in
            row.container.bounds = CGRect(x: 0, y: 0, width: width, height: row.height)
            row.container.center = CGPoint(x: width / 2, y: row.y + row.height / 2)
            row.content.frame = CGRect(x: 0, y: 0, width: width, height: row.height)
        }

        // New rows start at their final place (optionally offset) without animation.
        UIView.performWithoutAnimation {
            for row in created {
                place(row)
                row.content.layoutIfNeeded()
            }
        }

        if let spring = spring {
            spring.animate {
                for row in self.rows where !created.contains(where: { $0 === row }) {
                    place(row)
                }
                self.contentSize = CGSize(width: width, height: contentHeight)
            }
            for row in created {
                guard case let .message(id) = row.id else {
                    row.content.alpha = 0
                    UIView.animate(withDuration: 0.25) { row.content.alpha = 1 }
                    continue
                }
                animateInsertion(row: row, style: insertions[id] ?? .fade, spring: spring)
            }
        } else {
            for row in rows { place(row) }
            contentSize = CGSize(width: width, height: contentHeight)
        }
    }

    private func animateInsertion(row: Row, style: InsertionStyle, spring: Spring) {
        guard let cell = row.content as? MessageCellView, let layout = cell.layout else { return }
        switch style {
        case let .fromInput(textOrigin):
            // textOrigin is in window coordinates.
            let target = CGPoint(x: layout.bubbleFrame.minX + layout.textFrame.minX, y: layout.bubbleFrame.minY + layout.textFrame.minY)
            let source = cell.convert(textOrigin, from: nil)
            let dx = source.x - target.x
            let dy = source.y - target.y
            cell.bubbleView.transform = CGAffineTransform(translationX: dx, y: dy)
            cell.backgroundImageView.alpha = 0
            cell.statusView.alpha = 0
            spring.animate {
                cell.bubbleView.transform = .identity
            }
            UIView.animate(withDuration: 0.25, delay: 0.04, options: [.curveEaseOut]) {
                cell.backgroundImageView.alpha = 1
                cell.statusView.alpha = 1
            }
        case .slideUp:
            let offset = row.height + 12
            row.container.center.y -= offset
            spring.animate {
                row.container.center.y += offset
            }
        case .fade:
            cell.alpha = 0
            cell.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            spring.animate {
                cell.alpha = 1
                cell.transform = .identity
            }
        }
    }

    private func spacing(between newer: ListItem, and older: ListItem) -> CGFloat {
        switch (newer, older) {
        case let (.message(a), .message(b)):
            if a.message.authorId == b.message.authorId && (a.position == .last || a.position == .middle) {
                return 2.0
            }
            return 8.0
        default:
            return 0.0
        }
    }

    // MARK: - Scrolling

    var isAtBottom: Bool {
        return contentOffset.y <= -contentInset.top + 20
    }

    func scrollToBottom(animated: Bool) {
        setContentOffset(CGPoint(x: 0, y: -contentInset.top), animated: animated)
    }

    func scrollTo(messageId: Int, animated: Bool) {
        guard let row = rowById[.message(messageId)] else { return }
        let visibleHeight = bounds.height - contentInset.top - contentInset.bottom
        var target = row.y + row.height / 2 - visibleHeight / 2 - contentInset.top
        let maxOffset = max(-contentInset.top, contentSize.height - bounds.height + contentInset.bottom)
        target = min(max(target, -contentInset.top), maxOffset)
        setContentOffset(CGPoint(x: 0, y: target), animated: animated)
    }

    /// Content offset that centres a message, clamped to the scrollable range.
    func targetOffset(for messageId: Int, extraBottom: CGFloat = 0) -> CGFloat? {
        guard let row = rowById[.message(messageId)] else { return nil }
        let visibleHeight = bounds.height - contentInset.top - contentInset.bottom - extraBottom
        let target = row.y + row.height / 2 - visibleHeight / 2 - contentInset.top - extraBottom
        let maxOffset = max(-contentInset.top, contentSize.height - bounds.height + contentInset.bottom)
        return min(max(target, -contentInset.top), maxOffset)
    }

    /// Content offset that puts the top of a message at `topEdgeAt` (view coordinates).
    func targetOffset(for messageId: Int, topEdgeAt top: CGFloat) -> CGFloat? {
        guard let row = rowById[.message(messageId)] else { return nil }
        let target = row.y + row.height - bounds.height + top
        let maxOffset = max(-contentInset.top, contentSize.height - bounds.height + contentInset.bottom)
        return min(max(target, -contentInset.top), maxOffset)
    }

    /// Date of the message at the top edge of the visible area (under the header).
    func dateNearTop(offset: CGFloat? = nil) -> Date? {
        let y = (offset ?? contentOffset.y) + bounds.height - contentInset.bottom
        var best: Date?
        for (index, row) in rows.enumerated() where row.y <= y {
            guard index < items.count else { break }
            switch items[index] {
            case let .message(layout): best = layout.message.date
            case let .date(day, _): best = day
            }
        }
        return best
    }

    func frameInWindow(of messageId: Int) -> CGRect? {
        guard let cell = cell(for: messageId), let window = window else { return nil }
        return cell.bubbleView.convert(cell.bubbleView.bounds, to: window)
    }

    // MARK: - Swipe to reply

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === swipeRecognizer {
            guard swipeEnabled else { return false }
            let velocity = swipeRecognizer.velocity(in: self)
            guard velocity.x < 0, abs(velocity.x) > abs(velocity.y) * 1.4 else { return false }
            let point = swipeRecognizer.location(in: self)
            return messageCell(at: point) != nil
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    private func messageCell(at point: CGPoint) -> MessageCellView? {
        for row in rows {
            guard let cell = row.content as? MessageCellView else { continue }
            let local = convert(point, to: cell)
            if cell.bounds.contains(local) { return cell }
        }
        return nil
    }

    @objc private func handleSwipe(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            let point = recognizer.location(in: self)
            guard let cell = messageCell(at: point) else { return }
            swipeCell = cell
            swipeTriggered = false
            let icon = UIView(frame: CGRect(x: 0, y: 0, width: 33, height: 33))
            icon.backgroundColor = Theme.serviceBackground
            icon.layer.cornerRadius = 16.5
            let arrow = UIImageView(image: Icons.symbol("arrowshape.turn.up.left.fill", size: 14, weight: .semibold, color: .white))
            arrow.contentMode = .center
            arrow.frame = icon.bounds
            icon.addSubview(arrow)
            icon.alpha = 0
            icon.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            cell.addSubview(icon)
            if let layout = cell.layout {
                icon.center = CGPoint(x: cell.bounds.width + 20, y: layout.bubbleFrame.midY)
            }
            swipeIcon = icon
        case .changed:
            guard let cell = swipeCell else { return }
            let raw = min(0, recognizer.translation(in: self).x)
            let limit: CGFloat = 60
            let offset = raw > -limit ? raw : -limit + (raw + limit) * 0.25
            let clamped = max(offset, -limit - 40)
            cell.bubbleView.transform = CGAffineTransform(translationX: clamped, y: 0)
            let progress = min(1, -clamped / limit)
            if let icon = swipeIcon, let layout = cell.layout {
                icon.center = CGPoint(x: layout.bubbleFrame.maxX + clamped + 26 + (1 - progress) * 10, y: layout.bubbleFrame.midY)
                icon.alpha = progress
                let scale = 0.3 + 0.7 * progress
                icon.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
            if progress >= 1 && !swipeTriggered {
                swipeTriggered = true
                Haptics.impact(.light)
                if let icon = swipeIcon {
                    UIView.animate(withDuration: 0.12, animations: { icon.transform = CGAffineTransform(scaleX: 1.15, y: 1.15) }, completion: { _ in
                        UIView.animate(withDuration: 0.12) { icon.transform = .identity }
                    })
                }
            } else if progress < 1 && swipeTriggered {
                swipeTriggered = false
            }
        case .ended, .cancelled, .failed:
            guard let cell = swipeCell else { return }
            let icon = swipeIcon
            let shouldReply = swipeTriggered && recognizer.state == .ended
            Spring.standard.animate({
                cell.bubbleView.transform = .identity
                icon?.alpha = 0
                icon?.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            }, completion: { _ in icon?.removeFromSuperview() })
            swipeCell = nil
            swipeIcon = nil
            if shouldReply { onSwipeReply?(cell.messageId) }
        default:
            break
        }
    }
}
