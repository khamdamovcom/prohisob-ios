// Hisobni o'chirish (App Store talabi 5.1.1(v)): xodim — darhol o'chadi; prorab — kabinetni o'chirish so'rovi
// (7 kun ichida); obyekt egasi — darhol o'chadi. Parol bilan tasdiqlanadi.
// POST /api/hisob/ochirish {parol} → {ochirildi, xabar} | {sorov, xabar}; POST /api/mijoz/hisob/ochirish {parol} → {ochirildi, xabar}
import SwiftUI

private struct AccDeleteBody: Encodable {
    let parol: String
}

private struct AccDeleteResponse: Decodable {
    let ochirildi: Bool?
    let sorov: Bool?
    let xabar: String?
}

/// Kim o'chiryapti — matn va so'rov manzili shunga bog'liq
enum AccDeleteKind {
    case xodim, prorab, mijoz

    var path: String {
        switch self {
        case .mijoz: return "/api/mijoz/hisob/ochirish"
        case .xodim, .prorab: return "/api/hisob/ochirish"
        }
    }

    var explanation: String {
        switch self {
        case .xodim:
            return "Hisobingiz darhol o‘chadi. Siz kiritgan yozuvlar prorab kabinetida qoladi."
        case .prorab:
            return "Kabinet va undagi barcha ma’lumot (obyektlar, yozuvlar, cheklar) 7 kun ichida butunlay o‘chiriladi. So‘rov platforma egasiga yuboriladi."
        case .mijoz:
            return "Hisobingiz darhol o‘chadi, ilovadan va Telegram botdan chiqasiz. Obyekt hisobi prorabingizda qoladi."
        }
    }

    var confirmMessage: String {
        switch self {
        case .prorab: return "Kabinetni o‘chirish so‘rovi yuboriladi. Bu amalni ortga qaytarib bo‘lmaydi."
        case .xodim, .mijoz: return "Hisobingiz darhol o‘chadi. Bu amalni ortga qaytarib bo‘lmaydi."
        }
    }
}

/// Oyna: nima bo'lishi, parol, qizil «Hisobni o'chirish» + tasdiqlash
struct AccDeleteAccountSheet: View {
    let kind: AccDeleteKind
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var parol = ""
    @State private var working = false
    @State private var errorText: String?
    @State private var askConfirm = false
    @State private var requestMessage: String?
    @FocusState private var focus: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    explanation
                }
                .accRow()

                Section {
                    AccPasswordField("Parolingiz", text: $parol, focus: $focus, tag: 0, contentType: .password, submitLabel: .done) {
                        if !parol.isEmpty { askConfirm = true }
                    }
                } header: {
                    Text("Tasdiqlash uchun parolingiz")
                }
                .accRow()

                if let errorText {
                    Section {
                        AccErrorBanner(text: errorText)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    deleteButton
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .scrollDismissesKeyboard(.interactively)
            .animation(.snappy(duration: 0.25), value: errorText)
            .navigationTitle("Hisobni o‘chirish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Bekor qilish") { dismiss() }
                        .disabled(working)
                }
            }
            .confirmationDialog("Hisob o‘chirilsinmi?", isPresented: $askConfirm, titleVisibility: .visible) {
                Button("Hisobni o‘chirish", role: .destructive) { Task { await submit() } }
                Button("Bekor qilish", role: .cancel) {}
            } message: {
                Text(verbatim: kind.confirmMessage)
            }
            .alert("So‘rov yuborildi", isPresented: requestShown) {
                Button("Yaxshi") { dismiss() }
            } message: {
                Text(verbatim: requestMessage ?? "")
            }
        }
        .interactiveDismissDisabled(working)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            IconBadge(symbol: "person.crop.circle.badge.xmark", color: Palette.red, soft: Palette.redSoft, size: 48)
            Text(verbatim: kind == .prorab ? "Kabinetni o‘chirish" : "Hisobni o‘chirish")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
            Text(verbatim: kind.explanation)
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private var deleteButton: some View {
        Button {
            focus = nil
            askConfirm = true
        } label: {
            HStack(spacing: 8) {
                if working {
                    ProgressView().tint(Palette.red)
                } else {
                    Image(systemName: "trash.fill")
                }
                Text("Hisobni o‘chirish")
                    .font(.body.weight(.bold))
            }
            .foregroundStyle(Palette.red)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Palette.redSoft.opacity(parol.isEmpty ? 0.5 : 1),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(parol.isEmpty ? 0.6 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(parol.isEmpty || working)
    }

    private var requestShown: Binding<Bool> {
        Binding(get: { requestMessage != nil }, set: { if !$0 { requestMessage = nil } })
    }

    private func submit() async {
        guard !parol.isEmpty, !working else { return }
        working = true
        errorText = nil
        do {
            let r: AccDeleteResponse = try await API.shared.post(kind.path, body: AccDeleteBody(parol: parol))
            if r.ochirildi == true {
                let text = (r.xabar?.isEmpty == false ? r.xabar : nil) ?? "Hisobingiz o‘chirildi"
                dismiss()
                await session.logout()
                // chiqishdan keyin — «Sessiya tugadi» xabari ustidan yoziladi
                session.show(text)
            } else {
                requestMessage = (r.xabar?.isEmpty == false ? r.xabar : nil)
                    ?? "So‘rovingiz qabul qilindi. Kabinet 7 kun ichida o‘chiriladi."
            }
        } catch is CancellationError {
        } catch {
            errorText = error.localizedDescription
        }
        working = false
    }
}
