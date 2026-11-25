import UIKit

/// A photo that lives in the chat history (real photos from Unsplash, see RealPhotos/CREDITS.md),
/// with what an on-device model would "see" in it: tags as Russian word stems (ё → е) and the
/// regions those words point at.
struct PhotoAsset {
    struct Region {
        let label: String
        /// Normalised rect inside the image.
        let rect: CGRect
        /// Tag stems that light this region up.
        let tags: [String]
    }

    let key: String
    let tags: [String]
    let regions: [Region]

    var image: UIImage { PhotoLibrary.image(for: self) }
    /// width / height
    var aspect: CGFloat {
        let size = image.size
        return size.height > 0 ? size.width / size.height : 1
    }

    static let catWindow = PhotoAsset(key: "cat_window",
        tags: ["черн", "кот", "кош", "уголек", "подокон", "окн", "роз", "цвет", "букет", "black", "cat", "ember", "windowsill", "sill", "window", "rose", "flower", "bouquet"],
        regions: [
            Region(label: "black cat", rect: CGRect(x: 0.44, y: 0.37, width: 0.53, height: 0.50), tags: ["черн", "кот", "кош", "black", "cat"]),
            Region(label: "windowsill", rect: CGRect(x: 0.0, y: 0.66, width: 0.44, height: 0.17), tags: ["подокон", "окн", "windowsill", "sill", "window"]),
            Region(label: "roses", rect: CGRect(x: 0.02, y: 0.28, width: 0.52, height: 0.30), tags: ["роз", "цвет", "букет", "rose", "flower", "bouquet"])
        ])
    static let blackKitten = PhotoAsset(key: "black_kitten",
        tags: ["черн", "кот", "котен", "окн", "black", "cat", "kitt", "window"],
        regions: [Region(label: "black kitten", rect: CGRect(x: 0.05, y: 0.28, width: 0.85, height: 0.7), tags: ["черн", "кот", "котен", "black", "cat", "kitt"])])
    static let fluffyCat = PhotoAsset(key: "fluffy_cat",
        tags: ["черн", "кот", "кош", "пушист", "солнц", "black", "cat", "fluff", "sun"],
        regions: [Region(label: "black cat", rect: CGRect(x: 0.42, y: 0.05, width: 0.45, height: 0.9), tags: ["черн", "кот", "кош", "black", "cat"])])
    static let coffeeWindow = PhotoAsset(key: "coffee_window",
        tags: ["черн", "кофе", "стакан", "чашк", "подокон", "окн", "вечер", "black", "coffee", "glass", "mug", "cup", "windowsill", "sill", "window", "evening"],
        regions: [
            Region(label: "black mug", rect: CGRect(x: 0.36, y: 0.45, width: 0.3, height: 0.42), tags: ["черн", "кофе", "стакан", "чашк", "black", "coffee", "glass", "mug", "cup"]),
            Region(label: "windowsill", rect: CGRect(x: 0.0, y: 0.74, width: 1.0, height: 0.2), tags: ["подокон", "окн", "windowsill", "sill", "window"])
        ])
    static let gingerKitten = PhotoAsset(key: "ginger_kitten",
        tags: ["рыж", "кот", "котен", "персик", "лап", "ginger", "orange", "cat", "kitt", "peach", "paw"],
        regions: [Region(label: "ginger kitten", rect: CGRect(x: 0.2, y: 0.25, width: 0.6, height: 0.7), tags: ["рыж", "кот", "котен", "ginger", "orange", "cat", "kitt"])])
    static let dogBeach = PhotoAsset(key: "dog_beach",
        tags: ["собак", "пес", "пляж", "мор", "граф", "dog", "pup", "beach", "sea", "ocean", "count"],
        regions: [Region(label: "dog", rect: CGRect(x: 0.3, y: 0.2, width: 0.65, height: 0.8), tags: ["собак", "пес", "dog", "pup"])])
    static let seaSunset = PhotoAsset(key: "sea_sunset",
        tags: ["мор", "закат", "рассвет", "солнц", "пляж", "вод", "sea", "ocean", "sunset", "sunrise", "dawn", "sun", "beach", "water"],
        regions: [Region(label: "sunset", rect: CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.4), tags: ["закат", "рассвет", "солнц", "sunset", "sunrise", "dawn", "sun"])])
    static let mountains = PhotoAsset(key: "mountains",
        tags: ["гор", "озер", "лес", "ел", "поход", "алта", "mountain", "lake", "forest", "pine", "hike", "hiking", "altai"],
        regions: [Region(label: "lake", rect: CGRect(x: 0.1, y: 0.6, width: 0.8, height: 0.3), tags: ["озер", "вод", "lake", "water"])])
    static let plantsWindow = PhotoAsset(key: "plants_window",
        tags: ["растен", "суккулент", "кактус", "горш", "подокон", "окн", "цвет", "plant", "succulent", "cactus", "pot", "windowsill", "sill", "window", "flower"],
        regions: [Region(label: "succulents", rect: CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8), tags: ["растен", "суккулент", "кактус", "горш", "цвет", "plant", "succulent", "cactus", "pot", "flower"])])

    static let all: [PhotoAsset] = [catWindow, blackKitten, fluffyCat, coffeeWindow, gingerKitten, dogBeach, seaSunset, mountains, plantsWindow]
    static func named(_ key: String) -> PhotoAsset? { all.first { $0.key == key } }
}

enum PhotoLibrary {
    private static var cache: [String: UIImage] = [:]

    static func image(for asset: PhotoAsset) -> UIImage {
        if let cached = cache[asset.key] { return cached }
        let image: UIImage
        if let path = Bundle.main.path(forResource: "photo_\(asset.key)", ofType: "jpg"), let loaded = UIImage(contentsOfFile: path) {
            image = loaded.preparingForDisplay() ?? loaded
        } else {
            image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 3)).image { ctx in
                UIColor.gray.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
            }
        }
        cache[asset.key] = image
        return image
    }

    /// Decodes every photo up front so scrolling and transitions never stall.
    static func warmUp() {
        for asset in PhotoAsset.all { _ = image(for: asset) }
    }
}

/// Where a normalised image point lands inside a view that shows the image aspect-filled.
func aspectFillPoint(_ p: CGPoint, imageAspect: CGFloat, in size: CGSize) -> CGPoint {
    let viewAspect = size.width / max(size.height, 1)
    let drawn = imageAspect > viewAspect
        ? CGSize(width: size.height * imageAspect, height: size.height)
        : CGSize(width: size.width, height: size.width / imageAspect)
    let origin = CGPoint(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
    return CGPoint(x: origin.x + p.x * drawn.width, y: origin.y + p.y * drawn.height)
}

/// `-photoGallery`: every photo in a grid.
final class PhotoGalleryController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let scroll = UIScrollView(frame: view.bounds)
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scroll)
        let width = (UIScreen.main.bounds.width - 12) / 2
        var y: [CGFloat] = [50, 50]
        for asset in PhotoAsset.all {
            let column = y[0] <= y[1] ? 0 : 1
            let h = width / asset.aspect
            let iv = UIImageView(image: asset.image)
            iv.frame = CGRect(x: 4 + CGFloat(column) * (width + 4), y: y[column], width: width, height: h)
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            scroll.addSubview(iv)
            y[column] += h + 4
        }
        scroll.contentSize = CGSize(width: view.bounds.width, height: max(y[0], y[1]))
    }
}
