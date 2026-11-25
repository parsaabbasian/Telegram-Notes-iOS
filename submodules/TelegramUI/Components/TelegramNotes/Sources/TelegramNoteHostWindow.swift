import Foundation
import UIKit

// Telegram's own window routes touches only to its node hierarchy, so a UIKit sheet presented inside it never
// receives them. Note sheets and the Memories viewer get a window of their own, which goes away when they close.
public enum TelegramNoteHostWindow {
    private static var window: UIWindow?
    // Keeps the window while the Note flies to its avatar, after the sheet has gone.
    static var isHoldingForFlight = false

    public static func present(_ controller: UIViewController, windowScene: UIWindowScene, animated: Bool = true) {
        if self.window != nil {
            return
        }
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .clear
        window.windowLevel = .normal + 1.0
        let rootController = UIViewController()
        rootController.view.backgroundColor = .clear
        window.rootViewController = rootController
        window.makeKeyAndVisible()
        self.window = window
        rootController.present(controller, animated: animated)
    }

    public static func remove() {
        if self.isHoldingForFlight {
            return
        }
        self.window?.isHidden = true
        self.window = nil
    }

    static func endFlight() {
        self.isHoldingForFlight = false
        self.remove()
    }
}
