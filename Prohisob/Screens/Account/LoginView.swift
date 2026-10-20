// Kirish ekrani: «Prorab / xodim» (saytdagi login-parol) yoki «Obyekt egasi» (prorab bergan login-parol).
// Klaviatura ochilganda hamma narsa ko'rinadi (ScrollView), xato — serverning o'zbekcha matni qizil kartada.
import SwiftUI
import UIKit

private enum AccLoginMode: String, CaseIterable, Identifiable {
    case prorab, mijoz

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prorab: return "Prorab / xodim"
        case .mijoz: return "Obyekt egasi"
        }
    }

    var symbol: String {
        switch self {
        case .prorab: return "hammer.fill"
        case .mijoz: return "house.fill"
        }
    }

    var hint: String {
        switch self {
        case .prorab: return "Saytdagi login va parolingiz bilan kiring"
        case .mijoz: return "Login va parolni prorabingiz beradi"
        }
    }
}

struct LoginView: View {
    @Environment(Session.self) private var session
    @State private var mode: AccLoginMode = AccLoginMode(rawValue: UserDefaults.standard.string(forKey: "acc.loginMode") ?? "") ?? .prorab
    @State private var login = ""
    @State private var password = ""
    @State private var loading = false
    @State private var errorText: String?
    @FocusState private var focus: Int?

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    AccLoginHeader()
                    Spacer(minLength: 28)
                        .frame(maxHeight: 48)
                    formCard
                    Spacer(minLength: 28)
                    AccLoginFooter()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { AccLoginBackground() }
        .onChange(of: mode) { _, m in
            UserDefaults.standard.set(m.rawValue, forKey: "acc.loginMode")
            errorText = nil
        }
    }

    // MARK: forma

    private var formCard: some View {
        VStack(spacing: 14) {
            AccModeSwitch(mode: $mode)
            hint
            fields
            if let errorText {
                AccErrorBanner(text: errorText)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            BrandButton(title: "Kirish", loading: loading, disabled: !canSubmit) {
                Task { await submit() }
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.07), radius: 24, y: 10)
        .animation(.snappy(duration: 0.25), value: errorText)
    }

    private var hint: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: mode == .mijoz ? "info.circle.fill" : "person.badge.key.fill")
                .foregroundStyle(mode == .mijoz ? Palette.accent : Palette.muted)
                .accessibilityHidden(true)
            Text(verbatim: mode.hint)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 4)
    }

    private var fields: some View {
        VStack(spacing: 10) {
            AccLoginInput(symbol: "person.fill", focused: focus == 0) {
                TextField("Login", text: $login)
                    .textContentType(.username)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: 0)
                    .onSubmit { focus = 1 }
            }
            AccLoginInput(symbol: "lock.fill", focused: focus == 1) {
                AccPasswordField("Parol", text: $password, focus: $focus, tag: 1, contentType: .password, submitLabel: .go) {
                    Task { await submit() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        !login.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func submit() async {
        guard canSubmit, !loading else { return }
        focus = nil
        loading = true
        errorText = nil
        do {
            switch mode {
            case .prorab: try await session.login(username: login, password: password)
            case .mijoz: try await session.loginMijoz(login: login, password: password)
            }
        } catch is CancellationError {
        } catch {
            errorText = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        loading = false
    }
}

// MARK: - Qismlar

/// Tepada: belgi, nom, shior
private struct AccLoginHeader: View {
    var body: some View {
        VStack(spacing: 18) {
            BrandMark(size: 84)
                .shadow(color: Palette.brand.opacity(0.5), radius: 26, y: 12)
            VStack(spacing: 6) {
                Text("Prohisob")
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                Text("Prorablar uchun qurilish hisobi")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// «Prorab / xodim» | «Obyekt egasi» — tanlangani oq (qorong'ida — ochroq) kapsula, siljib o'tadi
private struct AccModeSwitch: View {
    @Binding var mode: AccLoginMode
    @Namespace private var ns
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AccLoginMode.allCases) { m in
                segment(m)
            }
        }
        .padding(4)
        .background(Palette.bg, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))
    }

    private func segment(_ m: AccLoginMode) -> some View {
        let on = mode == m
        return Button {
            withAnimation(.snappy(duration: 0.28)) { mode = m }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: m.symbol)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(on ? Palette.accent : Palette.muted)
                Text(verbatim: m.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(on ? Palette.ink : Palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background {
                if on {
                    Capsule()
                        .fill(scheme == .dark ? Palette.surface2 : Palette.surface)
                        .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.08), radius: 6, y: 2)
                        .matchedGeometryEffect(id: "seg", in: ns)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Maydon qobig'i: chapda belgi, fokusda sariq hoshiya
private struct AccLoginInput<Content: View>: View {
    let symbol: String
    let focused: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(focused ? Palette.accent : Palette.muted)
                .frame(width: 22)
                .accessibilityHidden(true)
            content
                .font(.body)
                .foregroundStyle(Palette.ink)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: 54)
        .background(Palette.bg, in: RoundedRectangle(cornerRadius: Metrics.radiusS, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusS, style: .continuous)
                .strokeBorder(focused ? Palette.brand : Palette.line, lineWidth: focused ? 1.5 : 0.5)
        )
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// Pastda: demo so'rash (Telegram) va sayt
private struct AccLoginFooter: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("Kabinetingiz yo‘qmi? [**Demo so‘rang**](https://t.me/khamdamov)")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .tint(Palette.accent)
                .multilineTextAlignment(.center)
            Link(destination: AccApp.home) {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                    Text(verbatim: "prohisob.com")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink2)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassBackground(Capsule())
            }
            .accessibilityLabel("prohisob.com saytini ochish")
            Link("Maxfiylik siyosati", destination: AccApp.privacy)
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
        .padding(.top, 4)
    }
}

/// Fon: qog'oz rang ustida nozik sariq yorug'lik (yorug' va qorong'i mavzuda)
private struct AccLoginBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack(alignment: .top) {
            Palette.bg
            Circle()
                .fill(Palette.brand.opacity(dark ? 0.20 : 0.42))
                .frame(width: 460, height: 460)
                .blur(radius: 110)
                .offset(x: -120, y: -230)
            Circle()
                .fill(Palette.orange.opacity(dark ? 0.16 : 0.18))
                .frame(width: 340, height: 340)
                .blur(radius: 110)
                .offset(x: 160, y: -110)
            Circle()
                .fill(Palette.brand.opacity(dark ? 0.07 : 0.15))
                .frame(width: 380, height: 380)
                .blur(radius: 130)
                .offset(x: 130, y: 660)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
