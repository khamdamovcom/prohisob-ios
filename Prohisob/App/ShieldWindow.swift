// Face ID qulfi va maxfiylik pardasi — alohida UIWindow'da (alert darajasidan yuqori): ochiq «Yangi yozuv», chek ko'rish,
// formalar (sheet / fullScreenCover) ham uning ostida qoladi. Oddiy ZStack'da ular qulf ustida ishlab turardi va ilovalar
// oynasidagi suratda ko'rinardi (2026-10-20 yakuniy tekshiruv).
import SwiftUI
import UIKit

@MainActor
final class ShieldWindow {
    static let shared = ShieldWindow()
    private var window: UIWindow?

    func install(session: Session) {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        let w = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: ShieldHost().environment(session))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.windowLevel = .alert + 2
        w.backgroundColor = .clear
        w.isHidden = true
        window = w
    }

    /// Ko'rsatish / yashirish. Ko'rinib turganda VoiceOver ham faqat shu oynani o'qiydi.
    func set(_ on: Bool) {
        guard let w = window, w.isHidden == on else { return }
        w.isHidden = !on
        w.rootViewController?.view.accessibilityViewIsModal = on
    }
}

private struct ShieldHost: View {
    @Environment(Session.self) private var session

    var body: some View {
        Group {
            if session.locked {
                LockView()
            } else {
                PrivacyCover()
            }
        }
        .preferredColorScheme(session.theme.scheme)
    }
}
