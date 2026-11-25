import UIKit
import CoreMotion
import CoreImage

/// Cut-outs made offline with Vision's foreground instance mask (RealPhotos/mask_*.png), plus the
/// subject's outline, a soft halo and a soft contact shadow.
struct SubjectCutout {
    let mask: UIImage
    let edge: UIImage
    let glow: UIImage
    let shadow: UIImage
}

extension PhotoLibrary {
    private static var cutouts: [String: SubjectCutout] = [:]
    private static var blurred: [String: UIImage] = [:]

    static func cutout(for asset: PhotoAsset) -> SubjectCutout? {
        if let cached = cutouts[asset.key] { return cached }
        func load(_ name: String) -> UIImage? {
            Bundle.main.path(forResource: "\(name)_\(asset.key)", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
        }
        guard let mask = load("mask"), let edge = load("edge"), let glow = load("glow"), let shadow = load("shadow") else { return nil }
        let cutout = SubjectCutout(mask: mask, edge: edge, glow: glow, shadow: shadow)
        cutouts[asset.key] = cutout
        return cutout
    }

    /// The photo with a shallow depth of field, for behind a lifted subject.
    static func mutedBackground(for asset: PhotoAsset) -> UIImage { blurredBackground(for: asset) }

    static func blurredBackground(for asset: PhotoAsset) -> UIImage {
        if let cached = blurred[asset.key] { return cached }
        let source = asset.image
        // Downscale with UIKit first, then blur the small bitmap: cheap and colour-safe.
        let small = CGSize(width: source.size.width / 2, height: source.size.height / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let shrunk = UIGraphicsImageRenderer(size: small, format: format).image { _ in source.draw(in: CGRect(origin: .zero, size: small)) }
        var result = shrunk
        if let cg = shrunk.cgImage {
            let ci = CIImage(cgImage: cg)
            // Behind the subject the photo stays legible but steps back: less colour, darker, a hair soft.
            let blur = ci.clampedToExtent().applyingGaussianBlur(sigma: 1.2).cropped(to: ci.extent)
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.3, kCIInputBrightnessKey: -0.2, kCIInputContrastKey: 0.85])
            if let out = PhotoLibrary.ciContext.createCGImage(blur, from: ci.extent) {
                result = UIImage(cgImage: out)
            }
        }
        blurred[asset.key] = result
        return result
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func warmUpCutouts() {
        for asset in PhotoAsset.all where cutout(for: asset) != nil { _ = blurredBackground(for: asset) }
    }
}

/// Apple-style subject lift, kept inside the photo: the rest of the picture dims and loses its
/// colour, the recognised subject stays crisp and comes forward a touch over a soft shadow, and a
/// white light runs around its outline. On a phone the subject shifts slightly with the tilt.
final class SubjectLiftView: UIView {
    let asset: PhotoAsset
    private let regions: [PhotoAsset.Region]
    private let backdrop = CALayer()
    private let lifted = CALayer()
    private let shadow = CALayer()
    private let subject = CALayer()
    private let subjectMask = CALayer()
    private let rim = CALayer()
    private let rimMask = CALayer()
    private let rimGradient = CAGradientLayer()
    private let halo = CALayer()
    private let haloMask = CALayer()
    private var chips: [(RecallChipView, PhotoAsset.Region)] = []
    private let motion = CMMotionManager()
    private var baseAttitude: CMAttitude?
    private(set) var isLifted = false
    var onTap: (() -> Void)?

    private static let restingScale: CGFloat = 1.025

    init(asset: PhotoAsset, regions: [PhotoAsset.Region], cornerRadius: CGFloat) {
        self.asset = asset
        self.regions = regions
        super.init(frame: .zero)
        clipsToBounds = true
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous

        backdrop.contents = PhotoLibrary.mutedBackground(for: asset).cgImage
        backdrop.contentsGravity = .resizeAspectFill
        backdrop.opacity = 0
        layer.addSublayer(backdrop)
        layer.addSublayer(lifted)

        let cutout = PhotoLibrary.cutout(for: asset)
        shadow.contents = cutout?.shadow.cgImage
        shadow.contentsGravity = .resize
        shadow.opacity = 0
        lifted.addSublayer(shadow)

        halo.backgroundColor = UIColor.white.cgColor
        haloMask.contents = cutout?.glow.cgImage
        haloMask.contentsGravity = .resize
        halo.mask = haloMask
        halo.opacity = 0
        lifted.addSublayer(halo)

        subject.contents = asset.image.cgImage
        subject.contentsGravity = .resizeAspectFill
        subject.masksToBounds = true
        subjectMask.contents = cutout?.mask.cgImage
        subjectMask.contentsGravity = .resize
        subject.mask = subjectMask
        subject.opacity = 0
        lifted.addSublayer(subject)

        // A white line around the subject with one bright, faintly iridescent spot that travels.
        rimGradient.type = .conic
        let dim = UIColor(white: 1, alpha: 0.8).cgColor
        rimGradient.colors = [dim, dim, UIColor(rgb: 0xf5b9ea, alpha: 0.9).cgColor, UIColor.white.cgColor, UIColor(rgb: 0x9fb2ff, alpha: 0.9).cgColor, dim, dim]
        rimGradient.locations = [0, 0.55, 0.66, 0.72, 0.78, 0.9, 1]
        rimGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        rimGradient.endPoint = CGPoint(x: 0.5, y: 0)
        rim.addSublayer(rimGradient)
        rimMask.contents = cutout?.edge.cgImage
        rimMask.contentsGravity = .resize
        rim.mask = rimMask
        rim.opacity = 0
        lifted.addSublayer(rim)

        for region in regions {
            let chip = RecallChipView(text: region.label, dark: true)
            chip.alpha = 0
            addSubview(chip)
            chips.append((chip, region))
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { motion.stopDeviceMotionUpdates() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        lifted.bounds = bounds
        lifted.position = CGPoint(x: bounds.midX, y: bounds.midY)
        for layer in [subject, subjectMask, rim, rimMask, halo, haloMask] { layer.frame = lifted.bounds }
        shadow.frame = lifted.bounds.offsetBy(dx: 0, dy: bounds.height * 0.012)
        let side = hypot(bounds.width, bounds.height) * 1.2
        rimGradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        rimGradient.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
        var used: [CGRect] = []
        for (chip, region) in chips {
            let size = chip.intrinsicContentSize
            let isSubject = region.rect.height > 0.3
            let anchor = CGPoint(x: region.rect.midX * bounds.width, y: (isSubject ? region.rect.minY : region.rect.midY) * bounds.height)
            var frame = CGRect(x: anchor.x - size.width / 2, y: anchor.y - size.height - (isSubject ? 6 : -4), width: size.width, height: size.height)
            frame.origin.x = min(max(8, frame.minX), bounds.width - 8 - frame.width)
            frame.origin.y = min(max(8, frame.minY), bounds.height - 8 - frame.height)
            while used.contains(where: { $0.intersects(frame.insetBy(dx: -3, dy: -3)) }) { frame.origin.y += size.height + 6 }
            used.append(frame)
            chip.bounds = CGRect(origin: .zero, size: size)
            chip.center = frame.center
        }
    }

    private static let ease = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)

    private func resting(dx: CGFloat = 0, dy: CGFloat = 0) -> CATransform3D {
        let s = SubjectLiftView.restingScale
        return CATransform3DScale(CATransform3DMakeTranslation(dx, dy, 0), s, s, 1)
    }

    /// Bring the subject forward.
    func lift(delay: TimeInterval = 0) {
        guard !isLifted else { return }
        isLifted = true
        layoutIfNeeded()
        let start = CACurrentMediaTime() + delay
        func fade(_ layer: CALayer, to value: Float, duration: TimeInterval, after: TimeInterval = 0) {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = layer.presentation()?.opacity ?? layer.opacity
            a.toValue = value
            a.duration = duration
            a.beginTime = start + after
            a.fillMode = .backwards
            a.timingFunction = SubjectLiftView.ease
            layer.opacity = value
            layer.add(a, forKey: "fade")
        }
        fade(backdrop, to: 1, duration: 0.4)
        fade(subject, to: 1, duration: 0.01)
        fade(shadow, to: 0.45, duration: 0.5)
        fade(rim, to: 1, duration: 0.35, after: 0.1)
        let bloom = CAKeyframeAnimation(keyPath: "opacity")
        bloom.values = [0, 1, 0.55]
        bloom.keyTimes = [0, 0.35, 1]
        bloom.duration = 1.0
        bloom.beginTime = start + 0.05
        bloom.fillMode = .backwards
        halo.opacity = 0.55
        halo.add(bloom, forKey: "bloom")

        let rise = CASpringAnimation(perceptualDuration: 0.5, bounce: 0.15)
        rise.keyPath = "transform"
        rise.fromValue = CATransform3DIdentity
        rise.toValue = resting()
        rise.duration = rise.settlingDuration
        rise.beginTime = start
        rise.fillMode = .backwards
        lifted.transform = resting()
        lifted.add(rise, forKey: "rise")

        // The bright spot runs around the outline: fast once, then slowly.
        let spin = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        spin.values = [0, CGFloat.pi * 2]
        spin.duration = 1.1
        spin.beginTime = start + 0.1
        spin.timingFunction = CAMediaTimingFunction(name: .easeOut)
        rimGradient.add(spin, forKey: "intro")
        let slow = CABasicAnimation(keyPath: "transform.rotation.z")
        slow.fromValue = 0
        slow.toValue = CGFloat.pi * 2
        slow.duration = 5
        slow.beginTime = start + 1.2
        slow.repeatCount = .infinity
        rimGradient.add(slow, forKey: "spin")

        for (index, item) in chips.enumerated() {
            let chip = item.0
            chip.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            UIView.animate(springDuration: 0.45, bounce: 0.2, initialSpringVelocity: 0, delay: delay + 0.35 + Double(index) * 0.08, options: [.allowUserInteraction]) {
                chip.alpha = 1
                chip.transform = .identity
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.08) { Haptics.impact(.soft) }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.6) { [weak self] in self?.startParallax() }
    }

    /// On a phone the subject drifts a few points against the tilt.
    private func startParallax() {
        guard isLifted, window != nil, motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        var smoothed = CGPoint.zero
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let attitude = data?.attitude, self.isLifted else { return }
            if self.baseAttitude == nil { self.baseAttitude = attitude.copy() as? CMAttitude }
            if let base = self.baseAttitude { attitude.multiply(byInverseOf: base) }
            let target = CGPoint(x: CGFloat(max(-0.4, min(0.4, attitude.roll))) * 10, y: CGFloat(max(-0.4, min(0.4, attitude.pitch))) * 10)
            smoothed.x += (target.x - smoothed.x) * 0.12
            smoothed.y += (target.y - smoothed.y) * 0.12
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.lifted.transform = self.resting(dx: smoothed.x, dy: smoothed.y)
            CATransaction.commit()
        }
    }

    /// Settle back into the photo.
    func drop(completion: (() -> Void)? = nil) {
        guard isLifted else { completion?(); return }
        isLifted = false
        motion.stopDeviceMotionUpdates()
        let current = lifted.presentation()?.transform ?? lifted.transform
        lifted.removeAllAnimations()
        let settle = CASpringAnimation(perceptualDuration: 0.35, bounce: 0)
        settle.keyPath = "transform"
        settle.fromValue = current
        settle.toValue = CATransform3DIdentity
        settle.duration = settle.settlingDuration
        lifted.transform = CATransform3DIdentity
        lifted.add(settle, forKey: "settle")
        CATransaction.begin()
        CATransaction.setCompletionBlock { completion?() }
        CATransaction.setAnimationDuration(0.28)
        CATransaction.setAnimationTimingFunction(SubjectLiftView.ease)
        for layer in [backdrop, shadow, halo, rim] { layer.opacity = 0 }
        CATransaction.commit()
        UIView.animate(withDuration: 0.15) { self.chips.forEach { $0.0.alpha = 0 } }
    }

    @objc private func tapped() { onTap?() }
}

// MARK: - Viewer

/// Glass on black, for the media viewer's controls.
final class DarkGlassView: UIView {
    let effectView = UIVisualEffectView()
    var contentView: UIView { effectView.contentView }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(effectView)
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.tintColor = UIColor(white: 0.1, alpha: 0.5)
            effectView.effect = glass
            effectView.cornerConfiguration = .capsule()
        } else {
            effectView.effect = UIBlurEffect(style: .systemThinMaterialDark)
            effectView.clipsToBounds = true
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        effectView.frame = bounds
        if #unavailable(iOS 26.0) { effectView.layer.cornerRadius = bounds.height / 2 }
    }
}

/// Telegram's media viewer: the photo zooms up from where it was, and the AI lift carries over
/// at full size. From the results list it also offers "Show in Chat".
final class RecallViewer: UIView {
    let result: RecallResult
    private let backdrop = UIView()
    let imageView = UIImageView()
    private var lift: SubjectLiftView?
    private let closeGlass = DarkGlassView()
    private let closeIcon = UIImageView(image: Icons.symbol("xmark", size: 16, weight: .semibold, color: .white))
    private let closeButton = UIButton(type: .custom)
    private let titleGlass = DarkGlassView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let understood = UILabel()
    private let understoodIcon = GradientSymbolView(symbol: "sparkles", size: 13, weight: .semibold)
    private let showGlass = DarkGlassView()
    private let showLabel = UILabel()
    private let showButton = UIButton(type: .custom)
    private let showsChatButton: Bool
    private var chrome: [UIView] { [closeGlass, closeButton, titleGlass, understood, understoodIcon] + (showsChatButton ? [showGlass, showButton] : []) }

    var onClose: (() -> Void)?
    var onShowInChat: (() -> Void)?

    init(result: RecallResult, showsChatButton: Bool) {
        self.result = result
        self.showsChatButton = showsChatButton
        super.init(frame: .zero)
        backdrop.backgroundColor = .black
        backdrop.alpha = 0
        addSubview(backdrop)
        imageView.image = result.asset.image
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerCurve = .continuous
        addSubview(imageView)

        addSubview(closeGlass)
        closeIcon.contentMode = .center
        closeGlass.contentView.addSubview(closeIcon)
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(closeButton)
        addSubview(titleGlass)
        titleLabel.text = result.author.shortName
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleGlass.contentView.addSubview(titleLabel)
        subtitleLabel.text = RecallFormatting.longDate.string(from: result.date)
        subtitleLabel.font = UIFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = UIColor(white: 1, alpha: 0.7)
        subtitleLabel.textAlignment = .center
        titleGlass.contentView.addSubview(subtitleLabel)
        let labels = result.matchedRegions.map(\.label)
        understood.text = labels.isEmpty ? "Matches your description" : labels.joined(separator: " · ")
        understood.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        understood.textColor = UIColor(white: 1, alpha: 0.85)
        addSubview(understoodIcon)
        addSubview(understood)
        addSubview(showGlass)
        showLabel.text = "Show in Chat"
        showLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        showLabel.textColor = .white
        showLabel.textAlignment = .center
        showGlass.contentView.addSubview(showLabel)
        showButton.accessibilityLabel = "Show in Chat"
        showButton.addTarget(self, action: #selector(showTapped), for: .touchUpInside)
        addSubview(showButton)
        showGlass.isHidden = !showsChatButton
        showButton.isHidden = !showsChatButton
        chrome.forEach { $0.alpha = 0 }
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
    }

    required init?(coder: NSCoder) { fatalError() }

    private var fitFrame: CGRect {
        let safe = safeAreaInsets
        let bottomReserve: CGFloat = showsChatButton ? 128 : 70
        let area = CGRect(x: 0, y: safe.top + 64, width: bounds.width, height: bounds.height - safe.top - 64 - safe.bottom - bottomReserve)
        let aspect = result.asset.aspect
        var size = CGSize(width: area.width, height: area.width / aspect)
        if size.height > area.height { size = CGSize(width: area.height * aspect, height: area.height) }
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop.frame = bounds
        let safe = safeAreaInsets
        closeGlass.frame = CGRect(x: 16, y: safe.top + 8, width: 46, height: 46)
        closeIcon.frame = closeGlass.bounds
        closeButton.frame = closeGlass.frame.insetBy(dx: -4, dy: -4)
        let titleWidth = max(ceil(titleLabel.intrinsicContentSize.width), ceil(subtitleLabel.intrinsicContentSize.width)) + 34
        titleGlass.frame = CGRect(x: (bounds.width - titleWidth) / 2, y: safe.top + 8, width: titleWidth, height: 46)
        titleLabel.frame = CGRect(x: 0, y: 6, width: titleWidth, height: 19)
        subtitleLabel.frame = CGRect(x: 0, y: 24, width: titleWidth, height: 16)
        showGlass.frame = CGRect(x: 16, y: bounds.height - safe.bottom - 8 - 54, width: bounds.width - 32, height: 54)
        showLabel.frame = showGlass.bounds
        showButton.frame = showGlass.frame
        let labelWidth = min(bounds.width - 80, ceil(understood.intrinsicContentSize.width))
        let rowY = (showsChatButton ? showGlass.frame.minY - 44 : bounds.height - safe.bottom - 40)
        let rowX = (bounds.width - labelWidth - 24) / 2
        understoodIcon.frame = CGRect(x: rowX, y: rowY + 2, width: 18, height: 20)
        understood.frame = CGRect(x: rowX + 24, y: rowY, width: labelWidth, height: 24)
    }

    func present(in host: UIView, from frame: CGRect, radius: CGFloat) {
        self.frame = host.bounds
        host.addSubview(self)
        layoutIfNeeded()
        imageView.frame = frame
        imageView.layer.cornerRadius = radius
        let target = fitFrame
        UIView.animate(springDuration: 0.5, bounce: 0.12) {
            self.imageView.frame = target
            self.imageView.layer.cornerRadius = 0
        }
        UIView.animate(withDuration: 0.3) { self.backdrop.alpha = 1 }
        UIView.animate(withDuration: 0.3, delay: 0.15) { self.chrome.forEach { $0.alpha = 1 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self = self else { return }
            let lift = SubjectLiftView(asset: self.result.asset, regions: self.result.matchedRegions, cornerRadius: 0)
            lift.frame = self.imageView.frame
            lift.isUserInteractionEnabled = false
            self.insertSubview(lift, aboveSubview: self.imageView)
            self.lift = lift
            lift.lift()
        }
    }

    func dismiss(to frame: CGRect?, radius: CGFloat, completion: @escaping () -> Void) {
        lift?.drop()
        UIView.animate(withDuration: 0.15) {
            self.lift?.alpha = 0
            self.chrome.forEach { $0.alpha = 0 }
        }
        UIView.animate(withDuration: 0.3) { self.backdrop.alpha = 0 }
        UIView.animate(springDuration: 0.42, bounce: 0.1, initialSpringVelocity: 0, delay: 0, options: [], animations: {
            if let frame = frame {
                self.imageView.frame = frame
                self.imageView.layer.cornerRadius = radius
            } else {
                self.imageView.alpha = 0
            }
        }, completion: { _ in
            self.removeFromSuperview()
            completion()
        })
    }

    /// Down into its bubble: the viewer's black lifts off the chat as the photo lands.
    func land(in frame: CGRect, completion: @escaping () -> Void) {
        lift?.drop()
        UIView.animate(withDuration: 0.15) {
            self.lift?.alpha = 0
            self.chrome.forEach { $0.alpha = 0 }
        }
        UIView.animate(withDuration: 0.4, delay: 0.05, options: [.curveEaseOut]) { self.backdrop.alpha = 0 }
        UIView.animate(springDuration: 0.55, bounce: 0.14, initialSpringVelocity: 0, delay: 0, options: [], animations: {
            self.imageView.frame = frame
            self.imageView.layer.cornerRadius = BubbleImages.maxCornerRadius - MessageLayout.photoInset
        }, completion: { _ in completion() })
    }

    @objc private func closeTapped() { onClose?() }

    @objc private func showTapped() {
        Haptics.impact(.light)
        onShowInChat?()
    }

    func simulateClose() { onClose?() }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        switch recognizer.state {
        case .changed:
            let dy = max(0, translation.y)
            imageView.transform = CGAffineTransform(translationX: translation.x * 0.5, y: dy)
            lift?.transform = imageView.transform
            backdrop.alpha = max(0.2, 1 - dy / 400)
        case .ended, .cancelled:
            if translation.y > 110 || recognizer.velocity(in: self).y > 900 {
                let current = imageView.frame
                imageView.transform = .identity
                lift?.transform = .identity
                imageView.frame = current
                onClose?()
            } else {
                Spring.standard.animate {
                    self.imageView.transform = .identity
                    self.lift?.transform = .identity
                    self.backdrop.alpha = 1
                }
            }
        default:
            break
        }
    }
}
