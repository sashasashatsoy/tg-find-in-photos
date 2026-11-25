import UIKit

/// Geometry of one grapheme cluster (a user-perceived character, so emoji with
/// modifiers and ZWJ sequences stay whole).
struct GlyphCell {
    var rect: CGRect
    var line: Int
    var visible: Bool
}

/// A laid-out message text: per-grapheme rectangles plus one rendered bitmap.
/// Animated layers crop that bitmap via `contentsRect`, so hundreds of glyph
/// layers share a single texture and cost almost nothing on the GPU.
final class TextLayout {
    let text: String
    let characters: [Character]
    let cells: [GlyphCell]
    let size: CGSize
    let lineCount: Int
    let lastLineWidth: CGFloat
    let font: UIFont
    let color: UIColor
    let maxWidth: CGFloat

    private let storage: NSTextStorage
    private let layoutManager: NSLayoutManager
    private let container: NSTextContainer

    static let lineHeight: CGFloat = 22.0
    /// Distance from the top of a 22pt line box to its baseline.
    static var baselineOffset: CGFloat { lineHeight - abs(Theme.messageFont.descender) }

    private(set) lazy var image: UIImage = render()

    init(text: String, font: UIFont = Theme.messageFont, color: UIColor = Theme.primaryText, maxWidth: CGFloat) {
        self.text = text
        self.font = font
        self.color = color
        self.maxWidth = maxWidth
        self.characters = Array(text)

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = TextLayout.lineHeight
        paragraph.maximumLineHeight = TextLayout.lineHeight
        paragraph.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
        storage = NSTextStorage(attributedString: attributed)
        layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = false
        container = NSTextContainer(size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        // Collect line fragments.
        var lines: [(rect: CGRect, used: CGRect, glyphs: NSRange)] = []
        let fullGlyphs = layoutManager.glyphRange(for: container)
        layoutManager.enumerateLineFragments(forGlyphRange: fullGlyphs) { rect, used, _, glyphRange, _ in
            lines.append((rect, used, glyphRange))
        }

        func lineIndex(forGlyph glyph: Int) -> Int {
            var lo = 0, hi = lines.count - 1
            while lo <= hi {
                let mid = (lo + hi) / 2
                let r = lines[mid].glyphs
                if glyph < r.location { hi = mid - 1 } else if glyph >= r.location + r.length { lo = mid + 1 } else { return mid }
            }
            return max(0, min(lines.count - 1, lo))
        }

        var cells: [GlyphCell] = []
        cells.reserveCapacity(characters.count)
        let ns = text as NSString
        var utf16Offset = 0
        for character in characters {
            let length = character.utf16.count
            let charRange = NSRange(location: utf16Offset, length: length)
            utf16Offset += length
            let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            if glyphRange.length == 0 || lines.isEmpty {
                cells.append(GlyphCell(rect: .zero, line: max(0, lines.count - 1), visible: false))
                continue
            }
            let line = lineIndex(forGlyph: glyphRange.location)
            let lineRect = lines[line].rect
            let bounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            let rect = CGRect(x: bounds.minX, y: lineRect.minY, width: bounds.width, height: lineRect.height)
            let isWhitespace = character.isWhitespace || character.isNewline
            cells.append(GlyphCell(rect: rect, line: line, visible: !isWhitespace && rect.width > 0.01))
        }
        _ = ns
        self.cells = cells
        self.lineCount = max(1, lines.count)

        var width: CGFloat = 0
        for line in lines { width = max(width, line.used.width) }
        var height = CGFloat(lines.count) * TextLayout.lineHeight
        var lastWidth = lines.last?.used.width ?? 0
        // A trailing newline produces an extra empty line fragment.
        let extra = layoutManager.extraLineFragmentRect
        if extra.height > 0 {
            height = extra.maxY
            lastWidth = 0
        }
        if text.isEmpty { height = TextLayout.lineHeight }
        self.size = CGSize(width: ceilToPixel(width), height: ceilToPixel(height))
        self.lastLineWidth = ceilToPixel(lastWidth)
    }

    private func render() -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let renderSize = CGSize(width: max(1, size.width + 4), height: max(1, size.height))
        return UIGraphicsImageRenderer(size: renderSize, format: format).image { _ in
            let glyphs = layoutManager.glyphRange(for: container)
            layoutManager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
        }
    }

    /// Normalised crop of `image` for a rect in text coordinates.
    func contentsRect(for rect: CGRect) -> CGRect {
        let imageSize = image.size
        return CGRect(x: rect.minX / imageSize.width, y: rect.minY / imageSize.height, width: rect.width / imageSize.width, height: rect.height / imageSize.height)
    }
}
