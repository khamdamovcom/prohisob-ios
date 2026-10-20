// Liquid Glass (iOS 26): tizim qismlari — pastki menyu, yuqori panel, qidiruv, oynalar — Xcode 26 bilan o'zi «shisha» bo'ladi.
// Bu yerda kontent ustida suzib turadigan boshqaruvlar uchun: «Yangi yozuv» tugmasi, filtr chiplari, xabar, asosiy tugmalar.
// iOS 17–18 da — odatiy ko'rinish (xira material, bordered tugmalar).
import SwiftUI

extension View {
    /// iOS 26 — Liquid Glass; oldingilarida — xira material fon
    func glassBackground<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, fallback: Material = .ultraThinMaterial) -> some View {
        modifier(GlassBG(shape: shape, tint: tint, interactive: interactive, fallback: fallback))
    }

    /// Asosiy tugma: iOS 26 — .glassProminent, oldingi — .borderedProminent (rang — .tint)
    func primaryButton() -> some View { modifier(PrimaryButtonStyle()) }

    /// Ikkinchi darajali tugma: iOS 26 — .glass, oldingi — .bordered
    func secondaryButton() -> some View { modifier(SecondaryButtonStyle()) }

    /// Pastki menyu: pastga aylantirganda kichrayadi (iOS 26)
    func minimizingTabBar() -> some View { modifier(MinimizeTabBar()) }

    /// Bir-biriga yaqin «shisha» elementlar birga chiziladi va qo'shilib ketadi (iOS 26)
    func glassGroup(spacing: CGFloat = 8) -> some View { modifier(GlassGroup(spacing: spacing)) }
}

private struct GlassBG<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    let fallback: Material

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background(fallback, in: shape)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

private struct PrimaryButtonStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

private struct SecondaryButtonStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct MinimizeTabBar: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

private struct GlassGroup: ViewModifier {
    let spacing: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
