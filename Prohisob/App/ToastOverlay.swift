// Xabar (toast) hamma narsaning ustida: ochiq sheet, fullScreenCover, alert ostida qolmasin. Alohida shaffof UIWindow
// (alert darajasidan yuqori) — bosishlar undan o'tib ketadi, faqat xabarning o'zi bosiladi (yopiladi).
import SwiftUI
import UIKit

@MainActor
final class ToastOverlay {
    static let shared = ToastOverlay()
    private var window: UIWindow?

    func install(session: Session) {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        let w = PassThroughWindow(windowScene: scene)
        let host = UIHostingController(rootView: ToastHost().environment(session))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        w.isHidden = false
        window = w
    }
}

/// Faqat ko'rinadigan elementlar bosiladi, bo'sh joy — ostidagi oynaga
private final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        return hit === rootViewController?.view ? nil : hit
    }
}

private struct ToastHost: View {
    @Environment(Session.self) private var session

    var body: some View {
        VStack {
            ToastView()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(session.theme.scheme)
        .animation(.spring(duration: 0.35), value: session.toast)
    }
}
