import UIKit

/// Telegram's GlassBackgroundView (`.panel`, light theme): native Liquid Glass on iOS 26+
/// with a 10% white tint; a blur + white fill + edge highlight fallback before that.
final class GlassSurfaceView: UIView {
    let effectView = UIVisualEffectView()
    private let legacyFill = UIView()
    private let cornerRadius: CGFloat?
    var contentView: UIView { effectView.contentView }

    init(cornerRadius: CGFloat? = nil, interactive: Bool = false) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(effectView)
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = interactive
            glass.tintColor = UIColor(white: 1.0, alpha: 0.1)
            effectView.effect = glass
            if let cornerRadius = cornerRadius {
                effectView.cornerConfiguration = .uniformCorners(radius: .fixed(cornerRadius))
            } else {
                effectView.cornerConfiguration = .capsule()
            }
        } else {
            effectView.effect = UIBlurEffect(style: .light)
            effectView.clipsToBounds = true
            effectView.layer.cornerCurve = .continuous
            legacyFill.backgroundColor = UIColor(white: 1.0, alpha: 0.7)
            effectView.contentView.addSubview(legacyFill)
            effectView.layer.borderWidth = 1.0
            effectView.layer.borderColor = UIColor(white: 1.0, alpha: 0.5).cgColor
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.08
            layer.shadowRadius = 8
            layer.shadowOffset = CGSize(width: 0, height: 2)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        effectView.frame = bounds
        if #unavailable(iOS 26.0) {
            effectView.layer.cornerRadius = cornerRadius ?? bounds.height / 2
            legacyFill.frame = effectView.contentView.bounds
        }
    }
}

/// Wallpaper clone faded at one edge — Telegram's WallpaperEdgeEffectNode that keeps the
/// floating glass controls legible over scrolling messages.
final class EdgeEffectView: UIView {
    enum Edge { case top, bottom }
    let wallpaper = WallpaperView()
    private let fadeMask = CAGradientLayer()
    private let edge: Edge
    var extent: CGFloat = 100 { didSet { setNeedsLayout() } }
    /// Length of the fade at the inner end of the effect.
    var ramp: CGFloat = 80 { didSet { setNeedsLayout() } }

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        alpha = 1.0
        addSubview(wallpaper)
        fadeMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        layer.mask = fadeMask
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        wallpaper.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = bounds
        let h = max(bounds.height, 1)
        switch edge {
        case .top:
            fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
            fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        case .bottom:
            fadeMask.startPoint = CGPoint(x: 0.5, y: 1)
            fadeMask.endPoint = CGPoint(x: 0.5, y: 0)
        }
        let solid = max(0, extent - ramp) / h
        fadeMask.locations = [0, NSNumber(value: Double(solid)), NSNumber(value: Double(min(1, extent / h)))]
        CATransaction.commit()
    }
}
