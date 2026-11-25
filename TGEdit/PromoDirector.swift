import UIKit

/// Scripted walkthrough for the submission video (`-promo` launch argument). It drives the
/// real UI — press, menu, typing, confirm, delete, select — and logs every touch so the video
/// renderer can draw tap circles at the right place and time.
final class PromoDirector {
    private weak var controller: ChatViewController?
    private var startTime: CFTimeInterval = 0

    init(controller: ChatViewController) {
        self.controller = controller
    }

    func run() {
        let delay = Double(ProcessInfo.processInfo.environment["PROMO_DELAY"] ?? "") ?? 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            startTime = CACurrentMediaTime()
            print("PROMO_START")
            schedule()
        }
    }

    private func at(_ t: TimeInterval, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: block)
    }

    private func logTap(_ point: CGPoint, hold: Double = 0) {
        let t = CACurrentMediaTime() - startTime
        print(String(format: "PROMO_TAP %.3f %.1f %.1f %.2f", t, point.x, point.y, hold))
    }

    private func longPress(_ id: Int) {
        guard let c = controller, let cell = c.promoList.cell(for: id) else { return }
        let bubble = cell.bubbleView
        logTap(bubble.convert(CGPoint(x: bubble.bounds.midX, y: bubble.bounds.midY), to: nil), hold: 0.45)
        cell.simulatePressDown()
        at(0.42) { c.showMenu(for: cell) }
    }

    private func menu(_ title: String) {
        guard let frame = controller?.promoMenu?.performAction(titled: title) else { return }
        logTap(CGPoint(x: frame.midX, y: frame.midY))
    }

    private func tapSend() {
        guard let frame = controller?.promoInput.simulateSendTap() else { return }
        logTap(CGPoint(x: frame.midX, y: frame.midY))
    }

    private func tapCell(_ id: Int) {
        guard let c = controller, let cell = c.promoList.cell(for: id) else { return }
        let bubble = cell.bubbleView
        logTap(bubble.convert(CGPoint(x: bubble.bounds.midX, y: bubble.bounds.midY), to: nil))
        c.toggleSelection(id)
    }

    private func tapTrash() {
        guard let c = controller else { return }
        let button = c.promoSelectionBar.deleteButton
        logTap(button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil))
        button.isHighlighted = true
        let ids = Array(c.promoSelection)
        at(0.15) {
            button.isHighlighted = false
            c.exitSelection()
            c.burnAndDelete(ids)
        }
    }

    /// Types like a person: backspaces to the common prefix, then adds characters one by one.
    private func type(_ target: String, deleteStep: Double = 0.035, typeStep: Double = 0.07, clearAll: Bool = false) -> Double {
        guard let input = controller?.promoInput else { return 0 }
        var current = Array(input.text)
        let goal = Array(target)
        var t: Double = 0
        if clearAll {
            at(t) { input.text = "" }
            current = []
            t += 0.25
        } else {
            var common = 0
            while common < min(current.count, goal.count) && current[common] == goal[common] { common += 1 }
            while current.count > common {
                current.removeLast()
                let snapshot = String(current)
                at(t) { input.text = snapshot }
                t += deleteStep
            }
        }
        while current.count < goal.count {
            current.append(goal[current.count])
            let snapshot = String(current)
            at(t) { input.text = snapshot }
            t += typeStep + Double.random(in: -0.015 ... 0.02)
        }
        return t
    }

    private func schedule() {
        // 1. One message: Anita's group-chat threat goes up in flames.
        at(0.0) { self.longPress(10) }
        at(1.6) { self.menu("Delete") }
        // 2. Several at once: the 2 AM texts burn as a cascade, newest first.
        at(5.4) { self.longPress(8) }
        at(7.0) { self.menu("Select") }
        at(8.1) { self.tapCell(7) }
        at(8.9) { self.tapCell(6) }
        at(9.7) { self.tapCell(5) }
        at(10.8) { self.tapTrash() }
        at(15.0) { print("PROMO_END") }
    }
}
