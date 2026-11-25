import UIKit

/// Where a message sits inside a run of consecutive messages from the same author.
/// Mirrors Telegram's MessageBubbleImageNeighbors.
enum BubbleGroupPosition: Hashable {
    case single  // .none  – full corners + tail
    case first   // .top   – top of a group, tail-less, tight bottom corner
    case middle  // .both
    case last    // .bottom – bottom of a group, carries the tail

    var hasTail: Bool { self == .single || self == .last }
}

enum BubbleImages {
    static let maxCornerRadius: CGFloat = 16.0
    static let minCornerRadius: CGFloat = 8.0
    static let tailWidth: CGFloat = 6.0
    /// Extra transparent margin drawn around the shape so the hairline stroke is not clipped.
    static let padding: CGFloat = 1.0

    private struct Key: Hashable {
        let outgoing: Bool
        let position: BubbleGroupPosition
        let highlighted: Bool
    }
    private static var cache: [Key: UIImage] = [:]

    static func image(outgoing: Bool, position: BubbleGroupPosition, highlighted: Bool = false) -> UIImage {
        let key = Key(outgoing: outgoing, position: position, highlighted: highlighted)
        if let cached = cache[key] { return cached }
        let fill: UIColor
        if outgoing {
            fill = highlighted ? Theme.outgoingHighlightedFill : Theme.outgoingFill
        } else {
            fill = highlighted ? Theme.incomingHighlightedFill : Theme.incomingFill
        }
        let image = draw(outgoing: outgoing, position: position, fill: fill, stroke: Theme.bubbleStroke)
        cache[key] = image
        return image
    }

    /// Bubble shape in "outgoing" orientation (tail on the right), Telegram geometry:
    /// a 33pt rounded body plus a 6pt tail column; the tail is two quad curves with an
    /// ellipse knocked out of its inner side.
    static func shapePath(position: BubbleGroupPosition) -> CGPath {
        let d: CGFloat = 33.0
        let maxR = maxCornerRadius
        let minR = minCornerRadius
        var tl = maxR, tr = maxR, bl = maxR, br = maxR
        switch position {
        case .single: break
        case .first: br = minR
        case .middle: tr = minR; br = minR
        case .last: tr = minR
        }
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 0, y: tl))
        body.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: tl, y: 0), radius: tl)
        body.addLine(to: CGPoint(x: d - tr, y: 0))
        body.addArc(tangent1End: CGPoint(x: d, y: 0), tangent2End: CGPoint(x: d, y: tr), radius: tr)
        body.addLine(to: CGPoint(x: d, y: d - br))
        body.addArc(tangent1End: CGPoint(x: d, y: d), tangent2End: CGPoint(x: d - br, y: d), radius: br)
        body.addLine(to: CGPoint(x: bl, y: d))
        body.addArc(tangent1End: CGPoint(x: 0, y: d), tangent2End: CGPoint(x: 0, y: d - bl), radius: bl)
        body.closeSubpath()

        guard position.hasTail else { return body }

        let bottomEllipse = CGRect(x: 24.0, y: 16.0, width: 27.0, height: 17.0)
        let topEllipse = CGRect(x: 33.0, y: 14.0, width: 23.0, height: 21.0)
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: bottomEllipse.minX, y: bottomEllipse.midY))
        tail.addQuadCurve(to: CGPoint(x: bottomEllipse.midX, y: bottomEllipse.maxY), control: CGPoint(x: bottomEllipse.minX, y: bottomEllipse.maxY))
        tail.addQuadCurve(to: CGPoint(x: bottomEllipse.maxX, y: bottomEllipse.midY), control: CGPoint(x: bottomEllipse.maxX, y: bottomEllipse.maxY))
        tail.closeSubpath()
        tail.addRect(CGRect(x: d / 2.0, y: floor(d / 2.0), width: d / 2.0, height: ceil(bottomEllipse.midY) - floor(d / 2.0)))
        let knockout = CGPath(ellipseIn: topEllipse, transform: nil)
        let tailShape = tail.subtracting(knockout)
        return body.union(tailShape)
    }

    private static func draw(outgoing: Bool, position: BubbleGroupPosition, fill: UIColor, stroke: UIColor) -> UIImage {
        let inner = CGSize(width: 33.0 + tailWidth, height: 33.0)
        let size = CGSize(width: inner.width + padding * 2, height: inner.height + padding * 2)
        let path = shapePath(position: position)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: padding, y: padding)
            if !outgoing {
                cg.translateBy(x: inner.width, y: 0)
                cg.scaleBy(x: -1, y: 1)
            }
            cg.addPath(path)
            cg.setFillColor(fill.cgColor)
            cg.fillPath()
            cg.addPath(path)
            cg.setStrokeColor(stroke.cgColor)
            cg.setLineWidth(screenPixel)
            cg.strokePath()
        }
        // Stretch through a 1pt slice in the middle of the body.
        let capNear: CGFloat = 16.0 + padding
        let capFar: CGFloat = inner.width - 17.0 + padding
        let insets = outgoing
            ? UIEdgeInsets(top: capNear, left: capNear, bottom: size.height - capNear - 1, right: capFar)
            : UIEdgeInsets(top: capNear, left: capFar, bottom: size.height - capNear - 1, right: capNear)
        return image.resizableImage(withCapInsets: insets, resizingMode: .stretch)
    }
}
