// «Yana» bo'limi va obyekt egasi rejimi uchun umumiy yordamchilar (Acc… prefiksi): sozlamalar uslubidagi belgi va qator,
// parol maydoni (ko'rsatish/yashirish), xato banneri, teglar, izoh qatorlari, ilova versiyasi va havolalar,
// yaratilgan login-parolni ko'rsatib ulashish oynasi.
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Javobi ishlatilmaydigan POST/PUT so'rovlari uchun — istalgan JSON'ni qabul qiladi
struct AccIgnored: Decodable {
    init(from decoder: Decoder) throws {}
}

/// Ilova versiyasi va doimiy havolalar
enum AccApp {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    static let support = URL(string: "https://t.me/khamdamov")!
    static let cabinet = URL(string: "https://cabinet.prohisob.com")!
    static let home = URL(string: "https://prohisob.com")!
    static let privacy = URL(string: "https://cabinet.prohisob.com/maxfiylik")!
}

/// Boshqa odamga beriladigan parol: 8 belgi, adashtiradigan harflarsiz (l, i, o, 0, 1)
enum AccPassword {
    static func generate(length: Int = 8) -> String {
        let chars = Array("abcdefghjkmnpqrstuvwxyz23456789")
        var out = ""
        for _ in 0..<length { out.append(chars.randomElement() ?? "a") }
        return out
    }
}

/// Avatar bosh harflari uchun: qavs, tire kabi belgilar olib tashlanadi («Demo (App Store)» → «DA»)
func accAvatarName(_ s: String) -> String {
    let cleaned = String(s.map { $0.isLetter || $0.isNumber ? $0 : " " })
    return cleaned.trimmingCharacters(in: .whitespaces).isEmpty ? s : cleaned
}

/// Telefon raqami → tel: havola
func accTelURL(_ phone: String?) -> URL? {
    guard let phone, !phone.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    let digits = phone.filter { $0.isNumber || $0 == "+" }
    guard !digits.isEmpty else { return nil }
    return URL(string: "tel:" + digits)
}

// MARK: - Sozlamalar uslubidagi belgi va qator

enum AccTone {
    case blue, purple, teal, orange, green, red, gray, brand

    var color: Color {
        switch self {
        case .blue: return Palette.blue
        case .purple: return Palette.purple
        case .teal: return Palette.teal
        case .orange: return Palette.orange
        case .green: return Palette.green
        case .red: return Palette.red
        case .gray: return Palette.gray
        case .brand: return Palette.brand
        }
    }

    var soft: Color {
        switch self {
        case .blue: return Palette.blueSoft
        case .purple: return Palette.purpleSoft
        case .teal: return Palette.tealSoft
        case .orange: return Palette.orangeSoft
        case .green: return Palette.greenSoft
        case .red: return Palette.redSoft
        case .gray: return Palette.graySoft
        case .brand: return Palette.brandSoft
        }
    }
}

/// Yorug' mavzuda — rangli kvadrat ustida oq belgi (Sozlamalar kabi), qorong'ida — yumshoq fon ustida rangli belgi
struct AccIcon: View {
    let symbol: String
    var tone: AccTone = .gray
    var size: CGFloat = 30
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme == .dark {
            IconBadge(symbol: symbol, color: tone.color, soft: tone.soft, size: size)
        } else {
            // yorug' mavzuda Palette.surface — oq
            IconBadge(symbol: symbol, color: tone == .brand ? Palette.onBrand : Palette.surface, soft: tone.color, size: size)
        }
    }
}

/// Ro'yxat qatori: belgi, nom, o'ngda qiymat (ixtiyoriy) va tashqi havola belgisi
struct AccRowLabel: View {
    let title: String
    let symbol: String
    var tone: AccTone = .gray
    var value: String?
    var external = false
    var titleColor: Color = Palette.ink

    var body: some View {
        HStack(spacing: 12) {
            AccIcon(symbol: symbol, tone: tone)
            Text(title)
                .foregroundStyle(titleColor)
                .lineLimit(2)
            if value != nil || external {
                Spacer(minLength: 8)
                if let value, !value.isEmpty {
                    Text(value)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                if external {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

extension View {
    /// Ro'yxat qatori foni — kartalar bilan bir xil
    func accRow() -> some View { listRowBackground(Palette.surface) }
}

// MARK: - Parol maydoni

/// Parol: ko'z belgisi bilan ko'rsatish/yashirish. focus/tag — formadagi FocusState (Int?) bilan
struct AccPasswordField: View {
    let placeholder: String
    @Binding var text: String
    let focus: FocusState<Int?>.Binding
    let tag: Int
    let contentType: UITextContentType?
    let submitLabel: SubmitLabel
    let onSubmit: () -> Void
    @State private var visible: Bool

    init(_ placeholder: String, text: Binding<String>, focus: FocusState<Int?>.Binding, tag: Int,
         contentType: UITextContentType? = .password, submitLabel: SubmitLabel = .done, revealed: Bool = false,
         onSubmit: @escaping () -> Void = {}) {
        self.placeholder = placeholder
        _text = text
        self.focus = focus
        self.tag = tag
        self.contentType = contentType
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
        _visible = State(initialValue: revealed)
    }

    var body: some View {
        HStack(spacing: 6) {
            input
            Button(action: toggle) {
                Image(systemName: visible ? "eye.slash" : "eye")
                    .font(.body)
                    .foregroundStyle(Palette.muted)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(visible ? "Parolni yashirish" : "Parolni ko‘rsatish")
        }
    }

    @ViewBuilder
    private var input: some View {
        if visible {
            TextField(placeholder, text: $text)
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .focused(focus, equals: tag)
        } else {
            SecureField(placeholder, text: $text)
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .focused(focus, equals: tag)
        }
    }

    private func toggle() {
        let wasFocused = focus.wrappedValue == tag
        visible.toggle()
        guard wasFocused else { return }
        let f = focus
        let t = tag
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            f.wrappedValue = t
        }
    }
}

// MARK: - Kichik qismlar

/// Qizil xato kartasi (serverning o'zbekcha xabari)
struct AccErrorBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Palette.red)
            Text(verbatim: text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.redSoft, in: RoundedRectangle(cornerRadius: Metrics.radiusS, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Kichik teg: «Faol emas», «Siz», rol
struct AccTag: View {
    let text: String
    var color: Color = Palette.orange
    var soft: Color = Palette.orangeSoft

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(soft, in: Capsule())
            .fixedSize()
    }
}

/// Foydalanuvchi roli tegi
struct AccRoleTag: View {
    let role: Role

    var body: some View {
        switch role {
        case .egasi: AccTag(text: role.label, color: Palette.purple, soft: Palette.purpleSoft)
        case .prorab: AccTag(text: role.label, color: Palette.accent, soft: Palette.brandSoft)
        case .xodim: AccTag(text: role.label, color: Palette.blue, soft: Palette.blueSoft)
        }
    }
}

/// Belgi + qisqa matn (login, obyektlar, telegram…)
struct AccMeta: View {
    let symbol: String
    let text: String
    var color: Color = Palette.muted
    var lines = 2

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.footnote)
                .lineLimit(lines)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(color)
    }
}

/// Izoh ro'yxati qatori: rangli belgi + matn
struct AccBullet: View {
    let symbol: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
    }
}

// MARK: - Yaratilgan login-parol (obyekt egasi, xodim)

struct AccCredentials: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let login: String
    let password: String
    let shareText: String
}

/// Saqlangandan keyin: login va parol, «Kirish ma'lumotini yuborish» (ShareLink) va nusxalash
struct AccCredentialsView: View {
    let cred: AccCredentials
    @Environment(Session.self) private var session

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(Palette.green)
                    .padding(.top, 16)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text(verbatim: cred.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.ink)
                    Text(verbatim: cred.message)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                .multilineTextAlignment(.center)
                Card {
                    VStack(spacing: 10) {
                        InfoRow(label: "Login") {
                            Text(verbatim: cred.login).font(.body.monospaced().weight(.semibold)).textSelection(.enabled)
                        }
                        Divider()
                        InfoRow(label: "Parol") {
                            Text(verbatim: cred.password).font(.body.monospaced().weight(.semibold)).textSelection(.enabled)
                        }
                    }
                }
                ShareLink(item: cred.shareText) {
                    Label("Kirish ma’lumotini yuborish", systemImage: "square.and.arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Palette.onBrand)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Palette.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                Button {
                    // parol bor matn: faqat shu telefonda (iCloud orqali boshqa qurilmaga o'tmaydi), 2 daqiqadan keyin o'chadi
                    UIPasteboard.general.setItems([[UTType.plainText.identifier: cred.shareText]],
                                                  options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                    session.show("Nusxalandi")
                } label: {
                    Label("Matnni nusxalash", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                Text(verbatim: cred.shareText)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Metrics.radiusS, style: .continuous))
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Palette.bg)
    }
}
