import UIKit

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xff) / 255.0,
            green: CGFloat((rgb >> 8) & 0xff) / 255.0,
            blue: CGFloat(rgb & 0xff) / 255.0,
            alpha: alpha
        )
    }
}

let screenScale: CGFloat = UIScreen.main.scale
let screenPixel: CGFloat = 1.0 / UIScreen.main.scale

/// Values mirror Telegram iOS "Day Classic" theme (DefaultDayPresentationTheme.swift)
/// and ChatMessageItemLayoutConstants for the default 17pt font size.
enum Theme {
    static let accent = UIColor(rgb: 0x0088ff)
    static let destructive = UIColor(rgb: 0xff3b30)

    // Bubbles
    static let incomingFill = UIColor(rgb: 0xffffff)
    static let incomingHighlightedFill = UIColor(rgb: 0xd9f4ff)
    static let outgoingFill = UIColor(rgb: 0xe1ffc7)
    static let outgoingHighlightedFill = UIColor(rgb: 0xbaff93)
    static let bubbleStroke = UIColor(rgb: 0x5a7a4c, alpha: 0.2)

    static let primaryText = UIColor.black
    static let incomingSecondaryText = UIColor(rgb: 0x77828c)
    static let outgoingSecondaryText = UIColor(rgb: 0x008c09, alpha: 0.8)
    static let outgoingCheck = UIColor(rgb: 0x19c700)
    static let outgoingAccent = UIColor(rgb: 0x00a700)
    static let incomingAccent = UIColor(rgb: 0x0088ff)
    static let outgoingReactionAccent = UIColor(rgb: 0x3fc33b)

    // Wallpaper (default classic gradient)
    static let wallpaperColors: [UIColor] = [
        UIColor(rgb: 0xdbddbb),
        UIColor(rgb: 0x6ba587),
        UIColor(rgb: 0xd5d88d),
        UIColor(rgb: 0x88b884)
    ]
    /// Service (date header) background on the default wallpaper.
    static let serviceBackground = UIColor(rgb: 0x5b7a52, alpha: 0.45)

    // Bars
    static let barBackground = UIColor(rgb: 0xf2f2f2, alpha: 0.9)
    static let navSeparator = UIColor(rgb: 0xc8c7cc)
    static let panelSeparator = UIColor(rgb: 0xbec2c6)
    static let navSecondaryText = UIColor(rgb: 0x787878)
    static let panelIcon = UIColor(rgb: 0x858e99)
    static let inputBackground = UIColor(white: 1.0, alpha: 0.8)
    static let inputStroke = UIColor(rgb: 0x000000, alpha: 0.1)
    static let inputPlaceholder = UIColor(rgb: 0x8e8e93)

    // Context menu
    static let menuBackground = UIColor(white: 0.98, alpha: 0.82)
    static let menuSeparator = UIColor(rgb: 0x3c3c43, alpha: 0.2)
    static let menuGroupSeparator = UIColor(rgb: 0x000000, alpha: 0.08)
    static let menuHighlight = UIColor(rgb: 0x000000, alpha: 0.1)

    // Fonts
    static let messageFont = UIFont.systemFont(ofSize: 17.0)
    static let dateFont = UIFont.systemFont(ofSize: 11.0)
    static let replyTitleFont = UIFont.systemFont(ofSize: 14.0, weight: .semibold)
    static let replyTextFont = UIFont.systemFont(ofSize: 14.0)
    static let serviceFont = UIFont.systemFont(ofSize: 13.0, weight: .medium)

    // Telegram avatar gradients (top, bottom)
    static let avatarGradients: [(UInt32, UInt32)] = [
        (0xff885e, 0xff516a), // red
        (0xffcd6a, 0xffa85c), // orange
        (0x82b1ff, 0x665fff), // violet
        (0xa0de7e, 0x54cb68), // green
        (0x53edd6, 0x28c9b7), // cyan
        (0x72d5fd, 0x2a9ef1), // blue
        (0xe0a2f3, 0xd669ed)  // pink
    ]
}

/// One spring for everything that moves together during a layout transition, so the bubble,
/// the glyphs inside it and the neighbouring messages stay perfectly in sync.
struct Spring {
    var duration: TimeInterval
    var bounce: CGFloat

    static let standard = Spring(duration: 0.5, bounce: 0.0)
    static let textMorph = Spring(duration: 0.52, bounce: 0.06)
    static let menu = Spring(duration: 0.42, bounce: 0.12)

    func animation(keyPath: String) -> CASpringAnimation {
        let animation = CASpringAnimation(perceptualDuration: duration, bounce: bounce)
        animation.keyPath = keyPath
        animation.duration = animation.settlingDuration
        return animation
    }

    var settlingDuration: TimeInterval {
        return CASpringAnimation(perceptualDuration: duration, bounce: bounce).settlingDuration
    }

    func animate(_ animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        UIView.animate(springDuration: duration, bounce: bounce, initialSpringVelocity: 0.0, delay: 0.0, options: [.allowUserInteraction, .beginFromCurrentState], animations: animations, completion: completion)
    }
}

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

func roundToPixel(_ value: CGFloat) -> CGFloat {
    return (value * screenScale).rounded() / screenScale
}

func ceilToPixel(_ value: CGFloat) -> CGFloat {
    return (value * screenScale).rounded(.up) / screenScale
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
