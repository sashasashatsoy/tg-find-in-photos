import UIKit

final class ChatViewController: UIViewController {
    private let store: ChatStore
    private let wallpaper = WallpaperView()
    private let listView = ChatListView()
    private let navBar: NavigationBarView
    private let inputPanel = InputPanelView()
    private let pinnedBar = PinnedBarView()
    private let keyboardTracker = UIView()
    private let selectionBar = SelectionBarView()
    private var selection: Set<Int>?
    private let topEdge = EdgeEffectView(edge: .top)
    private let bottomEdge = EdgeEffectView(edge: .bottom)

    private var layoutCache: [Int: MessageLayout] = [:]
    private var menuOverlay: ContextMenuOverlay?
    private var pinnedMessageId: Int?
    private var lastListWidth: CGFloat = 0
    private var lastBottomInset: CGFloat?
    private var replyScriptIndex = 0
    private var companionWork: [DispatchWorkItem] = []
    private(set) lazy var recall = PhotoRecallController(host: view, list: listView, inputPanel: inputPanel, navBar: navBar, store: store)

    static let quickReaction = "👍"
    static let reactions = ["👍", "❤️", "🔥", "🥰", "👏", "😁", "🤔"]

    init(store: ChatStore) {
        self.store = store
        self.navBar = NavigationBarView(peer: store.peer)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.wallpaperColors[0]
        view.addSubview(wallpaper)
        view.addSubview(listView)
        view.addSubview(topEdge)
        view.addSubview(bottomEdge)
        view.addSubview(pinnedBar)
        view.addSubview(navBar)
        view.addSubview(inputPanel)
        selectionBar.alpha = 0
        selectionBar.isHidden = true
        selectionBar.deleteButton.addTarget(self, action: #selector(deleteSelectedTapped), for: .touchUpInside)
        selectionBar.forwardButton.addTarget(self, action: #selector(forwardSelectedTapped), for: .touchUpInside)
        view.addSubview(selectionBar)
        navBar.onCancel = { [weak self] in self?.exitSelection() }
        recall.install(blurAbove: listView, chromeAbove: selectionBar)
        navBar.onTitleTap = { [weak self] in
            guard let self = self, self.selection == nil else { return }
            self.cancelAccessory()
            self.recall.open()
        }

        keyboardTracker.isUserInteractionEnabled = false
        view.addSubview(keyboardTracker)
        keyboardTracker.translatesAutoresizingMaskIntoConstraints = false
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            keyboardTracker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardTracker.widthAnchor.constraint(equalToConstant: 1),
            keyboardTracker.heightAnchor.constraint(equalToConstant: 1),
            keyboardTracker.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])

        pinnedBar.isHidden = true
        pinnedBar.addTarget(self, action: #selector(pinnedTapped), for: .touchUpInside)

        listView.configureCell = { [weak self] cell in self?.configure(cell) }
        listView.onSwipeReply = { [weak self] id in self?.startReply(to: id) }

        inputPanel.onSend = { [weak self] text in self?.sendOrCommit(text) }
        inputPanel.onCancelAccessory = { [weak self] in self?.cancelAccessory() }
        inputPanel.onHeightChange = { [weak self] in self?.animateLayout() }
        inputPanel.onAttach = { [weak self] in
            guard let self = self else { return }
            ToastView.show(in: self.view, text: "Attachments aren't available in this prototype", symbol: "paperclip", bottomInset: self.view.bounds.height - self.inputPanel.frame.minY)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutChrome()
        if abs(lastListWidth - view.bounds.width) > 0.5 {
            lastListWidth = view.bounds.width
            reload(spring: nil)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if ProcessInfo.processInfo.arguments.contains("-editDemo") {
            DemoRunner.run(on: self)
        }
        if ProcessInfo.processInfo.arguments.contains("-promo") {
            PromoDirector(controller: self).run()
        }
        if ProcessInfo.processInfo.arguments.contains("-recallPromo") {
            RecallPromo.run(on: self)
        }
        if ProcessInfo.processInfo.arguments.contains("-recallDemo") {
            RecallDemo.run(on: self)
        }
        if ProcessInfo.processInfo.arguments.contains("-burnDemo") {
            let ids = store.messages.suffix(4).map(\.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.burnAndDelete(ids[3]) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in self?.burnAndDelete([ids[0], ids[1], ids[2]]) }
        }
    }

    private var keyboardHeight: CGFloat {
        let guideTop = view.keyboardLayoutGuide.layoutFrame.minY
        return max(0, view.bounds.height - guideTop)
    }

    private func layoutChrome() {
        let bounds = view.bounds
        let safe = view.safeAreaInsets
        wallpaper.frame = bounds
        navBar.topInset = safe.top
        navBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: safe.top + NavigationBarView.contentHeight)
        let pinnedHeight: CGFloat = pinnedMessageId == nil ? 0 : PinnedBarView.height + 6
        pinnedBar.frame = CGRect(x: 8, y: navBar.frame.maxY + (pinnedMessageId == nil ? -PinnedBarView.height : 0), width: bounds.width - 16, height: PinnedBarView.height)
        pinnedBar.alpha = pinnedMessageId == nil ? 0 : 1

        let keyboard = keyboardHeight
        let bottomMargin = max(keyboard, safe.bottom) + 8
        let panelHeight = inputPanel.preferredHeight
        inputPanel.frame = CGRect(x: 0, y: bounds.height - bottomMargin - panelHeight, width: bounds.width, height: panelHeight)
        inputPanel.layoutContent()

        selectionBar.frame = CGRect(x: 8, y: bounds.height - bottomMargin - 50, width: bounds.width - 16, height: 50)

        topEdge.frame = bounds
        // Solid wallpaper right down to the bottom of the header capsules, then a short fade,
        // so messages scrolling underneath never show through as a ghost strip.
        topEdge.ramp = 36
        topEdge.extent = navBar.frame.maxY + 30 + pinnedHeight
        bottomEdge.frame = bounds
        bottomEdge.ramp = 44
        bottomEdge.extent = bounds.height - inputPanel.frame.minY + 30

        recall.layout(panelFrame: CGRect(x: 0, y: bounds.height - bottomMargin - 40, width: bounds.width, height: 40), navBottom: navBar.frame.maxY)

        listView.frame = bounds
        let bottomInset = bounds.height - inputPanel.frame.minY + 6 + recall.extraBottomInset
        let topInset = navBar.frame.maxY + pinnedHeight
        let oldInsets = listView.contentInset
        // Flipped list: contentInset.top is the visual bottom.
        let newInsets = UIEdgeInsets(top: bottomInset, left: 0, bottom: topInset, right: 0)
        if oldInsets != newInsets {
            let offset = listView.contentOffset
            listView.contentInset = newInsets
            listView.verticalScrollIndicatorInsets = UIEdgeInsets(top: bottomInset, left: 0, bottom: topInset, right: 0)
            if lastBottomInset == nil {
                listView.contentOffset = CGPoint(x: 0, y: -bottomInset)
            } else if !listView.isDragging {
                listView.contentOffset = CGPoint(x: 0, y: offset.y - (newInsets.top - oldInsets.top))
            }
            lastBottomInset = bottomInset
        }
    }

    private func animateLayout() {
        view.setNeedsLayout()
        Spring.standard.animate {
            self.view.layoutIfNeeded()
            self.layoutChrome()
        }
    }

    // MARK: - Items

    private func buildItems() -> [ListItem] {
        let messages = store.messages
        let width = view.bounds.width
        let calendar = Calendar.current
        func merges(_ a: Message, _ b: Message) -> Bool {
            a.authorId == b.authorId && calendar.isDate(a.date, inSameDayAs: b.date) && abs(a.date.timeIntervalSince(b.date)) < 600
        }
        var result: [ListItem] = []
        var newLayouts: [Int: MessageLayout] = [:]
        for index in stride(from: messages.count - 1, through: 0, by: -1) {
            let message = messages[index]
            let older = index > 0 ? messages[index - 1] : nil
            let newer = index + 1 < messages.count ? messages[index + 1] : nil
            let mergedOlder = older.map { merges($0, message) } ?? false
            let mergedNewer = newer.map { merges(message, $0) } ?? false
            let position: BubbleGroupPosition
            switch (mergedOlder, mergedNewer) {
            case (false, false): position = .single
            case (false, true): position = .first
            case (true, true): position = .middle
            case (true, false): position = .last
            }
            let layout = MessageLayout.make(message: message, reply: replyPreview(for: message), position: position, width: width, reusing: layoutCache[message.id]?.textLayout)
            newLayouts[message.id] = layout
            result.append(.message(layout))
            if older == nil || !calendar.isDate(older!.date, inSameDayAs: message.date) {
                let day = calendar.startOfDay(for: message.date)
                result.append(.date(day: day, text: DateFormatting.header(for: message.date)))
            }
        }
        layoutCache = newLayouts
        return result
    }

    private func replyPreview(for message: Message) -> ReplyPreview? {
        guard let replyId = message.replyToId else { return nil }
        guard let original = store.message(id: replyId) else {
            return ReplyPreview(title: "Deleted Message", text: "", color: Theme.accent)
        }
        return preview(of: original)
    }

    private func preview(of message: Message) -> ReplyPreview {
        let author = message.isOutgoing ? Peer.me : store.peer
        let color = message.isOutgoing ? UIColor(rgb: 0x368ad1) : UIColor(rgb: 0xc7508b)
        return ReplyPreview(title: author.shortName, text: message.text, color: color)
    }

    func reload(spring: Spring?, transitions: [Int: CellTransition] = [:], insertions: [Int: InsertionStyle] = [:]) {
        guard view.bounds.width > 0 else { return }
        listView.apply(items: buildItems(), spring: spring, transitions: transitions, insertions: insertions)
        if let selection = selection {
            for cell in listView.allCells where cell.selectionActive == false {
                cell.setSelection(active: true, selected: selection.contains(cell.messageId), animated: false)
            }
        }
    }

    private func configure(_ cell: MessageCellView) {
        cell.onSelectTap = { [weak self] cell in self?.toggleSelection(cell.messageId) }
        cell.onLongPress = { [weak self] cell in self?.showMenu(for: cell) }
        cell.onDoubleTap = { [weak self] cell in
            guard let self = self else { return }
            Haptics.impact(.light)
            self.store.toggleReaction(id: cell.messageId, emoji: ChatViewController.quickReaction, by: Peer.me)
            self.reload(spring: .standard)
        }
        cell.onReplyTap = { [weak self] cell in
            guard let self = self, let replyId = self.store.message(id: cell.messageId)?.replyToId else { return }
            self.jump(to: replyId)
        }
        cell.onReactionTap = { [weak self] cell, emoji in
            guard let self = self else { return }
            Haptics.selection()
            self.store.toggleReaction(id: cell.messageId, emoji: emoji, by: Peer.me)
            self.reload(spring: .standard)
        }
    }

    private func jump(to messageId: Int) {
        guard store.message(id: messageId) != nil else { return }
        listView.scrollTo(messageId: messageId, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.listView.cell(for: messageId)?.flashHighlight()
        }
    }

    // MARK: - Sending & editing

    private func sendOrCommit(_ text: String) {
        switch inputPanel.mode {
        case let .edit(id, _):
            commitEdit(id: id, text: text)
        case let .reply(id, _):
            send(text: text, replyTo: id)
        case .normal:
            send(text: text, replyTo: nil)
        }
    }

    private func send(text: String, replyTo: Int?) {
        let origin = inputPanel.textOriginInWindow
        let message = store.send(text: text, from: Peer.me, replyTo: replyTo)
        inputPanel.text = ""
        if inputPanel.mode != .normal {
            inputPanel.setMode(.normal, animated: true)
        }
        if !listView.isAtBottom {
            listView.scrollToBottom(animated: false)
        }
        reload(spring: .standard, insertions: [message.id: .fromInput(textOrigin: origin)])
        wallpaper.animateToNextPhase()
        topEdge.wallpaper.animateToNextPhase()
        bottomEdge.wallpaper.animateToNextPhase()
        scheduleCompanionResponse(to: message.id)
    }

    func startEdit(messageId: Int) {
        guard let message = store.message(id: messageId), message.isOutgoing else { return }
        inputPanel.setMode(.edit(messageId: messageId, preview: preview(of: message)), animated: true)
        inputPanel.text = message.text
        inputPanel.textView.becomeFirstResponder()
        let end = inputPanel.textView.endOfDocument
        inputPanel.textView.selectedTextRange = inputPanel.textView.textRange(from: end, to: end)
    }

    /// The feature: a locally confirmed edit morphs the bubble's text glyph by glyph.
    func commitEdit(id: Int, text: String) {
        guard let original = store.message(id: id) else {
            cancelAccessory()
            return
        }
        inputPanel.text = ""
        inputPanel.setMode(.normal, animated: true)
        guard original.text != text else { return }
        store.edit(id: id, text: text)
        reload(spring: .textMorph, transitions: [id: .morph(.textMorph)])
    }

    /// Applies an edit coming from the other side: standard Telegram behaviour, no glyph morph.
    func applyRemoteEdit(id: Int, text: String) {
        store.edit(id: id, text: text)
        reload(spring: .standard, transitions: [id: .crossfade(.standard)])
    }

    private func startReply(to messageId: Int) {
        guard let message = store.message(id: messageId) else { return }
        if case .edit = inputPanel.mode { inputPanel.text = "" }
        inputPanel.setMode(.reply(messageId: messageId, preview: preview(of: message)), animated: true)
        inputPanel.textView.becomeFirstResponder()
    }

    private func cancelAccessory() {
        if case .edit = inputPanel.mode { inputPanel.text = "" }
        inputPanel.setMode(.normal, animated: true)
    }

    private func delete(messageId: Int) {
        if ProcessInfo.processInfo.arguments.contains("-promo") {
            burnAndDelete(messageId)
            return
        }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let perform = { [weak self] in
            guard let self = self else { return }
            switch self.inputPanel.mode {
            case let .edit(id, _) where id == messageId, let .reply(id, _) where id == messageId:
                self.cancelAccessory()
            default: break
            }
            if self.pinnedMessageId == messageId { self.setPinned(nil) }
            self.burnAndDelete(messageId)
        }
        let isOutgoing = store.message(id: messageId)?.isOutgoing ?? false
        sheet.addAction(UIAlertAction(title: "Delete for me and Anita", style: .destructive) { _ in perform() })
        sheet.addAction(UIAlertAction(title: "Delete for me", style: .destructive) { _ in perform() })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    /// Deletion: bubbles burn away from the bottom up — several at once cascade from the newest
    /// upwards — then the neighbours close the gap with one spring.
    func burnAndDelete(_ messageId: Int) {
        burnAndDelete([messageId])
    }

    func burnAndDelete(_ ids: [Int]) {
        let order = Dictionary(uniqueKeysWithValues: store.messages.enumerated().map { ($1.id, $0) })
        let sorted = ids.sorted { (order[$0] ?? 0) > (order[$1] ?? 0) }
        var burns: [(BurnEffectView, UIView)] = []
        for id in sorted {
            guard let cell = listView.cell(for: id), cell.window != nil else { continue }
            cell.isBeingDeleted = true
            cell.resetPressState()
            let bubble = cell.bubbleView
            let frame = bubble.convert(bubble.bounds, to: view)
            // Skip bubbles that are scrolled far off screen.
            guard frame.maxY > -40, frame.minY < view.bounds.height + 40 else { continue }
            let pad: CGFloat = 2
            let format = UIGraphicsImageRendererFormat.preferred()
            format.opaque = false
            let image = UIGraphicsImageRenderer(bounds: bubble.bounds.insetBy(dx: -pad, dy: -pad), format: format).image { ctx in
                bubble.layer.render(in: ctx.cgContext)
            }
            let burn = BurnEffectView(image: image, frame: frame.insetBy(dx: -pad, dy: -pad), duration: sorted.count > 1 ? 1.15 : 1.35)
            burns.append((burn, bubble))
        }
        let step: TimeInterval = burns.count > 1 ? min(0.12, 0.6 / Double(burns.count)) : 0
        for (index, pair) in burns.enumerated() {
            let (burn, bubble) = pair
            let delay = Double(index) * step
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                self.view.insertSubview(burn, aboveSubview: self.bottomEdge)
                bubble.alpha = 0
                Haptics.impact(.soft)
                burn.start { }
            }
        }
        let total = (burns.isEmpty ? 0 : Double(burns.count - 1) * step + (burns.count > 1 ? 1.0 : 1.15))
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            guard let self = self else { return }
            for id in ids { self.store.delete(id: id) }
            self.reload(spring: .standard)
        }
    }

    // MARK: - Selection

    func enterSelection(with id: Int) {
        selection = [id]
        inputPanel.textView.resignFirstResponder()
        listView.swipeEnabled = false
        for cell in listView.allCells {
            cell.setSelection(active: true, selected: cell.messageId == id, animated: true)
        }
        navBar.setSelection(count: 1)
        inputPanel.isUserInteractionEnabled = false
        selectionBar.isHidden = false
        selectionBar.transform = CGAffineTransform(translationX: 0, y: 30)
        Spring.standard.animate {
            self.selectionBar.alpha = 1
            self.selectionBar.transform = .identity
            self.inputPanel.alpha = 0
            self.inputPanel.transform = CGAffineTransform(translationX: 0, y: 30)
        }
        updateSelectionControls()
    }

    func toggleSelection(_ id: Int) {
        guard var current = selection else { return }
        if current.contains(id) { current.remove(id) } else { current.insert(id) }
        selection = current
        Haptics.selection()
        listView.cell(for: id)?.setSelection(active: true, selected: current.contains(id), animated: true)
        navBar.setSelection(count: current.count)
        updateSelectionControls()
    }

    private func updateSelectionControls() {
        let hasAny = !(selection?.isEmpty ?? true)
        selectionBar.deleteButton.isEnabled = hasAny
        selectionBar.forwardButton.isEnabled = hasAny
    }

    func exitSelection() {
        guard selection != nil else { return }
        selection = nil
        listView.swipeEnabled = true
        for cell in listView.allCells {
            cell.setSelection(active: false, selected: false, animated: true)
        }
        navBar.setSelection(count: nil)
        inputPanel.isUserInteractionEnabled = true
        Spring.standard.animate({
            self.selectionBar.alpha = 0
            self.selectionBar.transform = CGAffineTransform(translationX: 0, y: 30)
            self.inputPanel.alpha = 1
            self.inputPanel.transform = .identity
        }, completion: { _ in
            if self.selection == nil { self.selectionBar.isHidden = true }
        })
    }

    @objc private func deleteSelectedTapped() {
        guard let ids = selection, !ids.isEmpty else { return }
        let count = ids.count
        let title = count == 1 ? "Delete message?" : "Delete \(count) \(ChatViewController.messagesWord(count))?"
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        let perform = { [weak self] in
            guard let self = self else { return }
            if let pinned = self.pinnedMessageId, ids.contains(pinned) { self.setPinned(nil) }
            self.exitSelection()
            self.burnAndDelete(Array(ids))
        }
        sheet.addAction(UIAlertAction(title: "Delete for me and Anita", style: .destructive) { _ in perform() })
        sheet.addAction(UIAlertAction(title: "Delete for me", style: .destructive) { _ in perform() })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func forwardSelectedTapped() {
        guard let ids = selection, !ids.isEmpty else { return }
        exitSelection()
        toast(ids.count == 1 ? "Message forwarded to Saved Messages." : "Messages forwarded to Saved Messages.", symbol: "bookmark")
    }

    static func messagesWord(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        return n == 1 ? "message" : "messages"
    }

    // MARK: - Context menu

    func showMenu(for cell: MessageCellView) {
        guard menuOverlay == nil, let message = store.message(id: cell.messageId) else { return }
        let id = message.id
        inputPanel.textView.resignFirstResponder()

        let bubble = cell.bubbleView
        let untransformed = CGRect(x: bubble.center.x - bubble.bounds.width / 2, y: bubble.center.y - bubble.bounds.height / 2, width: bubble.bounds.width, height: bubble.bounds.height)
        let source = cell.convert(untransformed, to: view)
        guard let snapshot = bubble.snapshotView(afterScreenUpdates: false) else { return }

        var main: [ContextAction] = [
            ContextAction(title: "Reply", icon: "arrowshape.turn.up.left") { [weak self] in self?.startReply(to: id) }
        ]
        if message.isOutgoing {
            main.append(ContextAction(title: "Edit", icon: "pencil") { [weak self] in self?.startEdit(messageId: id) })
        }
        main.append(ContextAction(title: "Copy", icon: "doc.on.doc") { [weak self] in
            UIPasteboard.general.string = message.text
            self?.toast("Copied to clipboard.", symbol: "doc.on.doc")
        })
        let isPinned = pinnedMessageId == id
        main.append(ContextAction(title: isPinned ? "Unpin" : "Pin", icon: isPinned ? "pin.slash" : "pin") { [weak self] in
            self?.setPinned(isPinned ? nil : id)
        })
        main.append(ContextAction(title: "Forward", icon: "arrowshape.turn.up.right") { [weak self] in
            self?.toast("Message forwarded to Saved Messages.", symbol: "bookmark")
        })
        main.append(ContextAction(title: "Delete", icon: "trash", destructive: true, afterLanding: true) { [weak self] in self?.delete(messageId: id) })

        let extra = [ContextAction(title: "Select", icon: "checkmark.circle") { [weak self] in self?.enterSelection(with: id) }]
        let chosen = message.reactions.first { $0.chosenByMe }?.emoji
        let overlay = ContextMenuOverlay(snapshot: snapshot, sourceFrame: source, outgoing: message.isOutgoing, groups: [main, extra], reactions: ChatViewController.reactions, chosenReaction: chosen)
        overlay.currentSourceFrame = { [weak self, weak cell] in
            guard let self = self, let cell = cell, cell.window != nil else { return nil }
            let b = cell.bubbleView
            let rect = CGRect(x: b.center.x - b.bounds.width / 2, y: b.center.y - b.bounds.height / 2, width: b.bounds.width, height: b.bounds.height)
            return cell.convert(rect, to: self.view)
        }
        overlay.onDismiss = { [weak self, weak cell] in
            if cell?.isBeingDeleted != true { cell?.bubbleView.alpha = 1 }
            cell?.resetPressState()
            self?.menuOverlay = nil
        }
        overlay.onReaction = { [weak self, weak overlay, weak cell] emoji, fromFrame in
            guard let self = self else { return }
            cell?.bubbleView.alpha = 1
            cell?.resetPressState()
            overlay?.dismiss(completion: nil)
            self.applyReactionFromMenu(messageId: id, emoji: emoji, fromWindowFrame: fromFrame)
        }
        menuOverlay = overlay
        cell.bubbleView.alpha = 0
        overlay.present(in: view)
    }

    private func applyReactionFromMenu(messageId: Int, emoji: String, fromWindowFrame: CGRect) {
        let hadIt = store.message(id: messageId)?.reactions.contains { $0.emoji == emoji && $0.chosenByMe } ?? false
        store.toggleReaction(id: messageId, emoji: emoji, by: Peer.me)
        reload(spring: .standard)
        guard !hadIt, let cell = listView.cell(for: messageId), let button = cell.reactionButton(for: emoji) else { return }
        cell.layoutIfNeeded()
        let target = button.convert(button.emojiFrameInSelf, to: view)
        let start = view.convert(fromWindowFrame, from: nil)
        let flyer = UILabel()
        flyer.text = emoji
        flyer.font = UIFont.systemFont(ofSize: 27)
        flyer.textAlignment = .center
        flyer.frame = start
        view.addSubview(flyer)
        button.setEmojiHidden(true)

        let path = UIBezierPath()
        path.move(to: start.center)
        let control = CGPoint(x: (start.midX + target.midX) / 2, y: min(start.midY, target.midY) - 60)
        path.addQuadCurve(to: target.center, controlPoint: control)
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path.cgPath
        move.duration = 0.5
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
        flyer.layer.position = target.center
        flyer.layer.add(move, forKey: "fly")
        let scale = target.width / start.width
        UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseInOut], animations: {
            flyer.transform = CGAffineTransform(scaleX: scale, y: scale)
        }, completion: { _ in
            flyer.removeFromSuperview()
            button.setEmojiHidden(false)
            button.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            Spring.menu.animate { button.transform = .identity }
            Haptics.impact(.light)
        })
    }

    private func toast(_ text: String, symbol: String) {
        ToastView.show(in: view, text: text, symbol: symbol, bottomInset: view.bounds.height - inputPanel.frame.minY)
    }

    // MARK: - Pinned

    private func setPinned(_ id: Int?) {
        pinnedMessageId = id
        if let id = id, let message = store.message(id: id) {
            pinnedBar.configure(text: message.text)
            pinnedBar.isHidden = false
        }
        view.setNeedsLayout()
        Spring.standard.animate({
            self.view.layoutIfNeeded()
            self.layoutChrome()
        }, completion: { _ in
            if self.pinnedMessageId == nil { self.pinnedBar.isHidden = true }
        })
    }

    @objc private func pinnedTapped() {
        if let id = pinnedMessageId { jump(to: id) }
    }

    // MARK: - Companion simulation

    private static let script = [
        "Wait, the letters actually flow 👀",
        "What if you replace the whole thing?",
        "The bubble stretches with the text, so smooth",
        "Try fixing just one letter",
        "Sending this to the team 🚀",
        "Even the \"edited\" label slides over nicely"
    ]

    private func scheduleCompanionResponse(to messageId: Int) {
        companionWork.forEach { $0.cancel() }
        companionWork.removeAll()
        func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
            let item = DispatchWorkItem(block: block)
            companionWork.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
        after(0.9) { [weak self] in
            guard let self = self else { return }
            self.navBar.setStatus(.online)
            self.store.markOutgoingRead()
            self.reload(spring: .standard)
        }
        after(1.8) { [weak self] in self?.navBar.setStatus(.typing) }
        after(3.6) { [weak self] in
            guard let self = self else { return }
            self.navBar.setStatus(.online)
            let text = ChatViewController.script[self.replyScriptIndex % ChatViewController.script.count]
            self.replyScriptIndex += 1
            let incoming = self.store.send(text: text, from: self.store.peer, replyTo: nil)
            self.reload(spring: .standard, insertions: [incoming.id: .slideUp])
            if self.replyScriptIndex % 2 == 1, self.store.message(id: messageId) != nil {
                after(0.9) { [weak self] in
                    guard let self = self, self.store.message(id: messageId) != nil else { return }
                    self.store.toggleReaction(id: messageId, emoji: "❤️", by: self.store.peer)
                    self.reload(spring: .standard)
                }
            }
        }
        after(9.0) { [weak self] in self?.navBar.setStatus(.lastSeenRecently) }
    }

    // MARK: - Demo hooks

    var promoList: ChatListView { listView }
    var promoInput: InputPanelView { inputPanel }
    var promoMenu: ContextMenuOverlay? { menuOverlay }
    var promoSelectionBar: SelectionBarView { selectionBar }
    var promoSelection: Set<Int> { selection ?? [] }

    var store_: ChatStore { store }

    var promoTitleFrame: CGRect { navBar.convert(navBar.titlePillFrame, to: nil) }

    func recallSimulateOpen() {
        navBar.simulateTitleTap()
    }

    func demoSend(_ text: String) -> Int {
        let message = store.send(text: text, from: Peer.me, replyTo: nil)
        store.markOutgoingRead()
        reload(spring: .standard, insertions: [message.id: .fade])
        return message.id
    }
}

/// Pinned message strip under the navigation bar.
final class PinnedBarView: UIControl {
    static let height: CGFloat = 46.0
    private let glass = GlassSurfaceView(cornerRadius: 23)
    private let line = UIView()
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let icon = UIImageView(image: Icons.symbol("pin", size: 15, weight: .regular, color: UIColor(white: 0, alpha: 0.5)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(glass)
        line.backgroundColor = Theme.accent
        line.layer.cornerRadius = 1
        addSubview(line)
        titleLabel.text = "Pinned Message"
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = Theme.accent
        addSubview(titleLabel)
        textLabel.font = UIFont.systemFont(ofSize: 14)
        textLabel.textColor = .black
        addSubview(textLabel)
        icon.contentMode = .center
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String) {
        textLabel.text = text.replacingOccurrences(of: "\n", with: " ")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        line.frame = CGRect(x: 16, y: 9, width: 2, height: bounds.height - 18)
        titleLabel.frame = CGRect(x: 26, y: 5, width: bounds.width - 70, height: 18)
        textLabel.frame = CGRect(x: 26, y: 23, width: bounds.width - 70, height: 18)
        icon.frame = CGRect(x: bounds.width - 44, y: 0, width: 40, height: bounds.height)
    }
}

/// Scripted run through the edge cases from the brief, for recording and frame-by-frame review.
enum DemoRunner {
    static let steps: [String] = [
        "Let's meet tomorrow at 10 am by the station",
        "Let's meet tomorrow at 11 am by the station",
        "Let's meet tomorrow at 11 am by the station entrance",
        "Let's meet tomorrow by the station entrance",
        "Plans changed, can we move it to Friday? 🙏",
        "Plans changed, can we move it to Friday? 🙏\nDoes 7 pm work for you?\nI can pick you up",
        "Ok 👍",
        "Ok 🔥",
        "Ok 🔥 see you there!"
    ]

    static func run(on controller: ChatViewController) {
        let interval = Double(ProcessInfo.processInfo.environment["DEMO_INTERVAL"] ?? "") ?? 2.2
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let id = controller.demoSend(steps[0])
            for (i, text) in steps.enumerated().dropFirst() {
                DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) {
                    controller.commitEdit(id: id, text: text)
                }
            }
        }
    }
}
