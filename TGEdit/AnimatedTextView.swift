import UIKit
import CoreImage

/// Displays a `TextLayout` as one bitmap, and can morph between two layouts:
/// surviving characters glide from their old to their new position, removed
/// characters fade and shrink away riding along with their neighbours, inserted
/// characters fade and grow in at their final spot.
final class AnimatedTextView: UIView {
    private(set) var textLayout: TextLayout?
    private let staticLayer = CALayer()
    private let morphLayer = CALayer()
    private var morphToken = 0
    private var gooeyView: GooeyMorphView?
    private(set) var isMorphing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        staticLayer.contentsGravity = .topLeft
        staticLayer.contentsScale = screenScale
        staticLayer.anchorPoint = .zero
        layer.addSublayer(staticLayer)
        morphLayer.anchorPoint = .zero
        layer.addSublayer(morphLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        if layer === staticLayer || layer === morphLayer { return NSNull() }
        return super.action(for: layer, forKey: event)
    }

    func setLayout(_ layout: TextLayout) {
        finishMorph()
        textLayout = layout
        applyStatic(layout)
    }

    /// Standard (non-local) update: a quick cross-dissolve, the way Telegram updates a message
    /// that was edited on another device.
    func crossfade(to layout: TextLayout) {
        finishMorph()
        textLayout = layout
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.2
        staticLayer.add(transition, forKey: "contents")
        applyStatic(layout)
    }

    private func applyStatic(_ layout: TextLayout) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        staticLayer.contents = layout.image.cgImage
        staticLayer.contentsScale = layout.image.scale
        staticLayer.bounds = CGRect(origin: .zero, size: layout.image.size)
        staticLayer.position = .zero
        staticLayer.isHidden = false
        CATransaction.commit()
    }

    private func finishMorph() {
        morphToken += 1
        guard isMorphing else { return }
        isMorphing = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        morphLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        gooeyView?.removeFromSuperview()
        gooeyView = nil
        staticLayer.isHidden = false
        CATransaction.commit()
    }

    // MARK: - Morph

    private struct Run {
        var indices: [Int]
    }

    /// Returns the duration after which the morph has fully settled.
    @discardableResult
    func morph(to newLayout: TextLayout, spring: Spring = .textMorph) -> TimeInterval {
        guard let oldLayout = textLayout else {
            setLayout(newLayout)
            return 0
        }
        finishMorph()
        textLayout = newLayout

        let diff = TextDiff.diff(old: oldLayout.characters, new: newLayout.characters)
        let oldCells = oldLayout.cells
        let newCells = newLayout.cells

        var newToOld = [Int](repeating: -1, count: newCells.count)
        for (o, n) in diff.mapping where n < newToOld.count && o < oldCells.count {
            newToOld[n] = o
        }

        // Displacement of every surviving character.
        var oldDisplacement = [CGPoint?](repeating: nil, count: oldCells.count)
        var newDisplacement = [CGPoint?](repeating: nil, count: newCells.count)
        for (o, n) in diff.mapping where n < newCells.count && o < oldCells.count {
            let from = oldCells[o].rect.origin
            let to = newCells[n].rect.origin
            let delta = CGPoint(x: to.x - from.x, y: to.y - from.y)
            // Only visible glyphs are meaningful anchors; a matched space says nothing visually.
            if oldCells[o].visible { oldDisplacement[o] = delta }
            if newCells[n].visible { newDisplacement[n] = delta }
        }
        func nearest(_ list: [CGPoint?], _ index: Int) -> CGPoint {
            // Ride along with a surviving neighbour only if it is close by (same word or the next one).
            let reach = 3
            for distance in 1 ... reach {
                if index - distance >= 0, let d = list[index - distance] { return d }
                if index + distance < list.count, let d = list[index + distance] { return d }
            }
            return .zero
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        staticLayer.isHidden = true

        let newImage = newLayout.image.cgImage
        let oldImage = oldLayout.image.cgImage
        let now = CACurrentMediaTime()
        var maxDelay: TimeInterval = 0

        func makeLayer(image: CGImage?, layout: TextLayout, rect: CGRect) -> CALayer {
            let glyph = CALayer()
            glyph.contents = image
            glyph.contentsScale = layout.image.scale
            glyph.contentsRect = layout.contentsRect(for: rect)
            glyph.bounds = CGRect(origin: .zero, size: rect.size)
            glyph.position = rect.center
            glyph.allowsEdgeAntialiasing = false
            morphLayer.addSublayer(glyph)
            return glyph
        }

        func union(_ indices: [Int], _ cells: [GlyphCell]) -> CGRect? {
            var result: CGRect?
            for i in indices where cells[i].visible {
                result = result.map { $0.union(cells[i].rect) } ?? cells[i].rect
            }
            return result
        }

        // 1. Surviving characters, grouped into runs that are contiguous in both layouts.
        var keptRuns: [Run] = []
        var current: [Int] = []
        for n in 0 ..< newCells.count {
            let o = newToOld[n]
            if o < 0 {
                if !current.isEmpty { keptRuns.append(Run(indices: current)); current = [] }
                continue
            }
            if let last = current.last {
                let lo = newToOld[last]
                let contiguous = o == lo + 1
                    && newCells[n].line == newCells[last].line
                    && oldCells[o].line == oldCells[lo].line
                    && diff.moved.contains(o) == diff.moved.contains(lo)
                if !contiguous {
                    keptRuns.append(Run(indices: current))
                    current = []
                }
            }
            current.append(n)
        }
        if !current.isEmpty { keptRuns.append(Run(indices: current)) }

        for run in keptRuns {
            guard let newRect = union(run.indices, newCells),
                  let oldRect = union(run.indices.map { newToOld[$0] }, oldCells) else { continue }
            let glyph = makeLayer(image: newImage, layout: newLayout, rect: newRect)
            let from = CGPoint(x: oldRect.minX + newRect.width / 2, y: oldRect.minY + newRect.height / 2)
            if abs(from.x - newRect.midX) > 0.1 || abs(from.y - newRect.midY) > 0.1 {
                let move = spring.animation(keyPath: "position")
                move.fromValue = NSValue(cgPoint: from)
                move.toValue = NSValue(cgPoint: newRect.center)
                glyph.add(move, forKey: "position")
            }
        }

        // 2. Removed and inserted characters melt into each other (gooey morph).
        if GooeyMorphView.isSupported, let oldCI = oldImage.map({ CIImage(cgImage: $0) }), let newCI = newImage.map({ CIImage(cgImage: $0) }) {
            let scale = newLayout.image.scale
            func wordRuns(_ indices: [Int], _ layout: TextLayout) -> [[Int]] {
                var result: [[Int]] = []
                var run: [Int] = []
                for i in indices where i < layout.cells.count {
                    let cell = layout.cells[i]
                    if !cell.visible {
                        if !run.isEmpty { result.append(run); run = [] }
                        continue
                    }
                    let emoji = AnimatedTextView.isEmoji(layout.characters[i])
                    if emoji {
                        if !run.isEmpty { result.append(run); run = [] }
                        result.append([i])
                        continue
                    }
                    if let last = run.last, last + 1 == i, layout.cells[last].line == cell.line {
                        run.append(i)
                    } else {
                        if !run.isEmpty { result.append(run) }
                        run = [i]
                    }
                }
                if !run.isEmpty { result.append(run) }
                return result
            }
            var pieces: [GooeyMorphView.Piece] = []
            var region = CGRect(origin: .zero, size: oldLayout.size).union(CGRect(origin: .zero, size: newLayout.size))
            func include(_ rect: CGRect, _ d: CGPoint) {
                region = region.union(rect).union(rect.offsetBy(dx: d.x, dy: d.y)).union(rect.offsetBy(dx: -d.x, dy: -d.y))
            }

            // Which "gap" between surviving characters each fragment belongs to: fragments in the
            // same gap are the old and new versions of the same edit and flow into each other.
            var keptBeforeOld = [Int](repeating: 0, count: oldCells.count + 1)
            for i in 0 ..< oldCells.count { keptBeforeOld[i + 1] = keptBeforeOld[i] + (diff.mapping[i] != nil ? 1 : 0) }
            var keptBeforeNew = [Int](repeating: 0, count: newCells.count + 1)
            for j in 0 ..< newCells.count { keptBeforeNew[j + 1] = keptBeforeNew[j] + (newToOld[j] >= 0 ? 1 : 0) }

            struct Frag { let run: [Int]; let rect: CGRect; let disp: CGPoint; let gap: Int; let emoji: Bool }
            let removedFrags: [Frag] = wordRuns(diff.removed, oldLayout).compactMap { run in
                guard let rect = union(run, oldCells) else { return nil }
                return Frag(run: run, rect: rect, disp: nearest(oldDisplacement, run[0]), gap: keptBeforeOld[run[0]], emoji: run.count == 1 && AnimatedTextView.isEmoji(oldLayout.characters[run[0]]))
            }
            let insertedFrags: [Frag] = wordRuns(diff.inserted, newLayout).compactMap { run in
                guard let rect = union(run, newCells) else { return nil }
                return Frag(run: run, rect: rect, disp: nearest(newDisplacement, run[0]), gap: keptBeforeNew[run[0]], emoji: run.count == 1 && AnimatedTextView.isEmoji(newLayout.characters[run[0]]))
            }
            let removedByGap = Dictionary(grouping: removedFrags.indices.filter { !removedFrags[$0].emoji }, by: { removedFrags[$0].gap })
            let insertedByGap = Dictionary(grouping: insertedFrags.indices.filter { !insertedFrags[$0].emoji }, by: { insertedFrags[$0].gap })
            func partner(_ index: Int, in own: [Int], other: [Int]?) -> Int? {
                guard let other = other, !other.isEmpty, let k = own.firstIndex(of: index) else { return nil }
                let j = Int((Double(k) + 0.5) / Double(own.count) * Double(other.count))
                return other[min(other.count - 1, max(0, j))]
            }
            func close(_ a: CGRect, _ b: CGRect) -> Bool {
                hypot(a.midX - b.midX, a.midY - b.midY) < 160
            }
            func edgeDrop(_ rect: CGRect, atLeft: Bool) -> CGRect {
                let h = rect.height * 0.55
                return CGRect(x: atLeft ? rect.minX : rect.maxX - 3, y: rect.midY - h / 2, width: 3, height: h)
            }

            var removedDelay: [Int: TimeInterval] = [:]
            let removedStep = removedFrags.count > 1 ? 0.12 / Double(removedFrags.count - 1) : 0
            for (k, frag) in removedFrags.enumerated() {
                let delay = Double(k) * removedStep
                removedDelay[k] = delay
                let pixelRect = CGRect(x: frag.rect.minX * scale, y: oldCI.extent.height - frag.rect.maxY * scale, width: frag.rect.width * scale, height: frag.rect.height * scale)
                var endRect: CGRect
                var endAnchor: GooeyMorphView.Anchor
                if frag.emoji {
                    endRect = frag.rect
                    endAnchor = .old(frag.disp)
                } else if let j = partner(k, in: removedByGap[frag.gap] ?? [], other: insertedByGap[frag.gap]), close(frag.rect, insertedFrags[j].rect) {
                    endRect = insertedFrags[j].rect
                    endAnchor = .new(insertedFrags[j].disp)
                } else {
                    // Nothing replaces it: the word is sucked into the neighbour it was attached to.
                    let attachedLeft = frag.run[0] > 0 && keptBeforeOld[frag.run[0]] > 0 && oldCells[max(0, frag.run[0] - 1)].line == oldCells[frag.run[0]].line
                    endRect = edgeDrop(frag.rect, atLeft: attachedLeft)
                    endAnchor = .old(frag.disp)
                }
                pieces.append(.init(image: oldCI.cropped(to: pixelRect), sourceRect: frag.rect, sourceHeight: oldCI.extent.height, appearing: false, delay: delay, startRect: frag.rect, startAnchor: .old(frag.disp), endRect: endRect, endAnchor: endAnchor, isEmoji: frag.emoji))
                include(frag.rect, frag.disp)
                include(endRect, frag.disp)
            }
            let insertStep = insertedFrags.count > 1 ? 0.16 / Double(insertedFrags.count - 1) : 0
            for (j, frag) in insertedFrags.enumerated() {
                let pixelRect = CGRect(x: frag.rect.minX * scale, y: newCI.extent.height - frag.rect.maxY * scale, width: frag.rect.width * scale, height: frag.rect.height * scale)
                var startRect: CGRect
                var startAnchor: GooeyMorphView.Anchor
                var delay: TimeInterval
                if frag.emoji {
                    startRect = frag.rect
                    startAnchor = .new(frag.disp)
                    delay = (removedFrags.isEmpty ? 0 : 0.1) + Double(j) * insertStep
                } else if let k = partner(j, in: insertedByGap[frag.gap] ?? [], other: removedByGap[frag.gap]), close(frag.rect, removedFrags[k].rect) {
                    startRect = removedFrags[k].rect
                    startAnchor = .old(removedFrags[k].disp)
                    delay = (removedDelay[k] ?? 0) + 0.02
                } else {
                    // A brand-new word is drawn out of its neighbour like a strand of plasticine.
                    startRect = edgeDrop(frag.rect, atLeft: true)
                    startAnchor = .new(frag.disp)
                    delay = (removedFrags.isEmpty ? 0 : 0.08) + Double(j) * insertStep
                }
                pieces.append(.init(image: newCI.cropped(to: pixelRect), sourceRect: frag.rect, sourceHeight: newCI.extent.height, appearing: true, delay: delay, startRect: startRect, startAnchor: startAnchor, endRect: frag.rect, endAnchor: .new(frag.disp), isEmoji: frag.emoji))
                include(frag.rect, frag.disp)
                include(startRect, frag.disp)
            }
            if !pieces.isEmpty {
                let margin: CGFloat = 18
                region = region.insetBy(dx: -margin, dy: -margin).integral
                let gooey = GooeyMorphView(region: region, pieces: pieces, spring: spring, pieceDuration: 0.64, scale: scale)
                insertSubview(gooey, at: 0)
                gooeyView = gooey
                gooey.start()
                maxDelay = max(maxDelay, gooey.totalDuration - spring.duration)
            }
        } else {
            addFallbackLayers(diff: diff, oldLayout: oldLayout, newLayout: newLayout, oldDisplacement: oldDisplacement, newDisplacement: newDisplacement, spring: spring, now: now, maxDelay: &maxDelay, makeLayer: makeLayer, union: union, nearest: nearest)
        }

        CATransaction.commit()
        isMorphing = true

        let total = max(spring.settlingDuration * 0.8, maxDelay + spring.duration + 0.15)
        let token = morphToken
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            guard let self = self, self.morphToken == token else { return }
            self.finishMorph()
            self.applyStatic(newLayout)
        }
        return total
    }

    static func isEmoji(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        return scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && c.unicodeScalars.count > 1)
    }

    private func addFallbackLayers(diff: TextDiffResult, oldLayout: TextLayout, newLayout: TextLayout, oldDisplacement: [CGPoint?], newDisplacement: [CGPoint?], spring: Spring, now: CFTimeInterval, maxDelay: inout TimeInterval, makeLayer: (CGImage?, TextLayout, CGRect) -> CALayer, union: ([Int], [GlyphCell]) -> CGRect?, nearest: ([CGPoint?], Int) -> CGPoint) {
        let oldCells = oldLayout.cells
        let newCells = newLayout.cells
        let oldImage = oldLayout.image.cgImage
        let newImage = newLayout.image.cgImage
        let perGlyph = diff.removed.count + diff.inserted.count <= 320
        func runs(_ indices: [Int], _ cells: [GlyphCell]) -> [[Int]] {
            let visible = indices.filter { $0 < cells.count && cells[$0].visible }
            if perGlyph { return visible.map { [$0] } }
            var result: [[Int]] = []
            var run: [Int] = []
            for i in visible {
                if let last = run.last, last + 1 == i, cells[last].line == cells[i].line {
                    run.append(i)
                } else {
                    if !run.isEmpty { result.append(run) }
                    run = [i]
                }
            }
            if !run.isEmpty { result.append(run) }
            return result
        }

        let removedRuns = runs(diff.removed, oldCells)
        let removedStep = removedRuns.isEmpty ? 0 : min(0.012, 0.10 / Double(removedRuns.count))
        for (k, run) in removedRuns.enumerated() {
            guard let rect = union(run, oldCells) else { continue }
            let delta = nearest(oldDisplacement, run[0])
            let glyph = makeLayer(oldImage, oldLayout, rect)
            let end = CGPoint(x: rect.midX + delta.x, y: rect.midY + delta.y)
            glyph.position = end
            glyph.opacity = 0
            glyph.transform = CATransform3DMakeScale(0.35, 0.35, 1)
            let delay = Double(k) * removedStep
            maxDelay = max(maxDelay, delay)

            let move = spring.animation(keyPath: "position")
            move.fromValue = NSValue(cgPoint: rect.center)
            move.toValue = NSValue(cgPoint: end)
            glyph.add(move, forKey: "position")

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0
            fade.toValue = 0.0
            fade.duration = 0.2
            fade.beginTime = now + delay
            fade.fillMode = .backwards
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
            glyph.add(fade, forKey: "opacity")

            let shrink = CABasicAnimation(keyPath: "transform")
            shrink.fromValue = CATransform3DIdentity
            shrink.toValue = glyph.transform
            shrink.duration = 0.24
            shrink.beginTime = now + delay
            shrink.fillMode = .backwards
            shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
            glyph.add(shrink, forKey: "transform")
        }

        let insertedRuns = runs(diff.inserted, newCells)
        let insertBase: TimeInterval = removedRuns.isEmpty ? 0.0 : 0.06
        let insertStep = insertedRuns.isEmpty ? 0 : min(0.016, 0.22 / Double(insertedRuns.count))
        for (k, run) in insertedRuns.enumerated() {
            guard let rect = union(run, newCells) else { continue }
            let delta = nearest(newDisplacement, run[0])
            let glyph = makeLayer(newImage, newLayout, rect)
            let delay = insertBase + Double(k) * insertStep
            maxDelay = max(maxDelay, delay)

            if abs(delta.x) > 0.1 || abs(delta.y) > 0.1 {
                let move = spring.animation(keyPath: "position")
                move.fromValue = NSValue(cgPoint: CGPoint(x: rect.midX - delta.x, y: rect.midY - delta.y))
                move.toValue = NSValue(cgPoint: rect.center)
                glyph.add(move, forKey: "position")
            }

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue = 1.0
            fade.duration = 0.22
            fade.beginTime = now + delay
            fade.fillMode = .backwards
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            glyph.add(fade, forKey: "opacity")

            let grow = spring.animation(keyPath: "transform")
            grow.fromValue = CATransform3DConcat(CATransform3DMakeScale(0.35, 0.35, 1), CATransform3DMakeTranslation(0, 3, 0))
            grow.toValue = CATransform3DIdentity
            grow.beginTime = now + delay
            grow.fillMode = .backwards
            glyph.add(grow, forKey: "transform")
        }

    }
}
