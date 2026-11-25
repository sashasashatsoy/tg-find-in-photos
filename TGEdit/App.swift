import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = .light
        let args = ProcessInfo.processInfo.arguments
        let editStory = args.contains("-promo") || args.contains("-editDemo") || args.contains("-burnDemo")
        PhotoLibrary.warmUp()
        PhotoLibrary.warmUpCutouts()
        window.rootViewController = ChatViewController(store: editStory ? ChatStore.makeDemo() : ChatStore.makeRecallDemo())
        if args.contains("-photoGallery") { window.rootViewController = PhotoGalleryController() }
        window.makeKeyAndVisible()
        self.window = window
    }
}
