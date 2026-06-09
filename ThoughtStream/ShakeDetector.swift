import SwiftUI
import UIKit

/// Detects device shake gestures and publishes a notification.
/// SwiftUI has no native shake API, so we intercept the motion event
/// at the UIWindow level and broadcast it as a Notification.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

/// SwiftUI modifier that fires a closure when the device is shaken.
struct OnShakeModifier: ViewModifier {
    var action: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                action()
            }
    }
}

extension View {
    func onShake(_ action: @escaping () -> Void) -> some View {
        modifier(OnShakeModifier(action: action))
    }
}
