import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FontLoader.registerBundledFonts()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = EngineRootViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        WyrmEngineShutdown()
    }
}
