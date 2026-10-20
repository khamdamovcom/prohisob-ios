// Obyekt egasi (mijoz) rejimi — session.kind == .mijoz: «Obyektlarim» (salom, prorab, obyektlar kartalari) va obyekt sahifasi.
// Mijoz faqat o'zi bergan pulni va real xarajatni ko'radi: foyda, qarzlar, ustaga hisoblangan haq bu yerda yo'q (server ham bermaydi).
import SwiftUI

struct ClientRootView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.clientPath) {
            CliHomeView()
                .navigationDestination(for: ClientRoute.self) { route in
                    switch route {
                    case .object(let id): CliObjectView(id: id)
                    }
                }
        }
    }
}

// MARK: - Bosh ekran

private struct CliHomeView: View {
    @Environment(Session.self) private var session
    @State private var loading = true
    @State private var askLogout = false
    @State private var showDelete = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bg)
            .navigationTitle("Obyektlarim")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CliMenu(askLogout: $askLogout, showDelete: $showDelete)
                }
            }
            .confirmationDialog("Hisobdan chiqasizmi?", isPresented: $askLogout, titleVisibility: .visible) {
                Button("Chiqish", role: .destructive) { Task { await session.logout() } }
                Button("Bekor qilish", role: .cancel) {}
            } message: {
                Text("Qayta kirish uchun prorab bergan login va parol kerak bo‘ladi.")
            }
            .sheet(isPresented: $showDelete) { AccDeleteAccountSheet(kind: .mijoz) }
            .task(id: session.dataVersion) { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        if let me = session.mijozMe {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CliGreeting(me: me)
                    if me.obyektlar.isEmpty {
                        EmptyState(symbol: "building.2",
                                   title: "Hozircha sizga obyekt biriktirilmagan",
                                   message: "Prorabingiz obyektni biriktirgach, uning hisobi shu yerda ko‘rinadi.")
                            .padding(.top, 12)
                    } else {
                        if me.obyektlar.count > 1 {
                            Text(verbatim: "Obyektlar · \(me.obyektlar.count)")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Palette.ink)
                                .padding(.top, 4)
                        }
                        ForEach(me.obyektlar) { o in
                            NavigationLink(value: ClientRoute.object(o.id)) {
                                CliObjectCard(object: o)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    Text("Hisob prorabingiz kiritgan yozuvlardan olinadi. Savol bo‘lsa — prorabingizga qo‘ng‘iroq qiling.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
                .padding(.horizontal, Metrics.pad)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .refreshable { await session.refresh() }
        } else if loading {
            LoadingState()
        } else {
            ContentUnavailableView {
                Label("Ma’lumot yuklanmadi", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Internet aloqasini tekshirib, qayta urinib ko‘ring.")
            } actions: {
                Button("Qayta urinish") { Task { await reload() } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func reload() async {
        loading = true
        await session.refresh()
        loading = false
    }
}

/// Salom va prorab (qo'ng'iroq tugmasi bilan)
private struct CliGreeting: View {
    let me: MijozMe

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Assalomu alaykum,")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                Text(verbatim: me.mijoz.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            CliProrabCard(prorab: me.prorab)
        }
    }
}

private struct CliProrabCard: View {
    let prorab: MijozMe.Prorab

    private var phone: String? {
        guard let p = prorab.phone, !p.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return p
    }

    var body: some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                Avatar(name: accAvatarName(prorab.name), size: 46, color: Palette.onBrand, soft: Palette.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prorabingiz")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                    Text(verbatim: prorab.name)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                    if let phone {
                        Text(verbatim: phone)
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength: 8)
                if let url = accTelURL(phone) {
                    Link(destination: url) {
                        Image(systemName: "phone.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.green)
                            .frame(width: 46, height: 46)
                            .background(Palette.greenSoft, in: Circle())
                    }
                    .accessibilityLabel("Prorabga qo‘ng‘iroq qilish")
                }
            }
        }
    }
}

/// Toolbar menyusi: Face ID qulfi, mavzu, yordam, chiqish
private struct CliMenu: View {
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @Binding var askLogout: Bool
    @Binding var showDelete: Bool

    var body: some View {
        Menu {
            Section {
                Toggle(isOn: Binding(get: { session.lockEnabled }, set: { on in Task { await session.setLock(on) } })) {
                    Label("\(session.biometryName) bilan qulflash", systemImage: session.biometrySymbol)
                }
                Picker(selection: Binding(get: { session.theme }, set: { session.theme = $0 })) {
                    ForEach(ThemeChoice.allCases) { t in
                        Text(t.label).tag(t)
                    }
                } label: {
                    Label("Mavzu", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
            }
            Section {
                Button {
                    openURL(AccApp.support)
                } label: {
                    Label("Yordam (Telegram)", systemImage: "paperplane")
                }
            }
            Section {
                Button(role: .destructive) {
                    askLogout = true
                } label: {
                    Label("Chiqish", systemImage: "rectangle.portrait.and.arrow.right")
                }
                Button(role: .destructive) {
                    showDelete = true
                } label: {
                    Label("Hisobni o‘chirish", systemImage: "person.crop.circle.badge.xmark")
                }
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .accessibilityLabel("Sozlamalar")
        }
    }
}

/// Bosh ekrandagi obyekt kartasi
private struct CliObjectCard: View {
    let object: MijozObject

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                header
                CliSummary(money: CliMoney(object))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Batafsil hisobni ochish")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: object.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                if let a = object.address, !a.isEmpty {
                    AccMeta(symbol: "mappin.and.ellipse", text: a)
                }
                StatusBadge(status: object.statusValue)
                    .padding(.top, 2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .padding(.top, 5)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Hisob qismlari (bosh ekran va obyekt sahifasi uchun)

/// Mijozga ko'rinadigan summalar (MijozObject va MijozObjectDetail'dan)
struct CliMoney {
    let kirim: Int
    let kirimYalpi: Int
    let qaytarish: Int
    let jamiXarajat: Int
    let qoldiq: Int
    let shartnoma: Int
    let qolganTolov: Int

    init(_ o: MijozObject) {
        kirim = o.kirim
        kirimYalpi = o.kirimYalpi
        qaytarish = o.qaytarish
        jamiXarajat = o.jamiXarajat
        qoldiq = o.qoldiq
        shartnoma = o.shartnoma
        qolganTolov = o.qolganTolov
    }

    init(_ d: MijozObjectDetail) {
        kirim = d.kirim
        kirimYalpi = d.kirimYalpi
        qaytarish = d.qaytarish
        jamiXarajat = d.jamiXarajat
        qoldiq = d.qoldiq
        shartnoma = d.shartnoma
        qolganTolov = d.qolganTolov
    }
}

/// «Siz bergan pul» | «Sarflangan», qoldiq (yoki ortiqcha sarflangan), shartnoma bo'yicha to'lov
struct CliSummary: View {
    let money: CliMoney
    var large = false

    private var returnedNote: String? {
        money.qaytarish > 0 ? "Jami \(Fmt.compact(money.kirimYalpi)), qaytarilgan \(Fmt.compact(money.qaytarish))" : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CliFigure(title: "Siz bergan pul", amount: money.kirim, symbol: "arrow.down.circle.fill",
                          color: Palette.green, size: large ? 20 : 18, note: returnedNote)
                CliFigure(title: "Sarflangan", amount: money.jamiXarajat, symbol: "arrow.up.circle.fill",
                          color: Palette.orange, size: large ? 20 : 18, note: nil)
            }
            .fixedSize(horizontal: false, vertical: true)
            CliBalance(qoldiq: money.qoldiq, large: large)
            if money.shartnoma > 0 {
                CliContract(money: money)
                    .padding(.top, 2)
            }
        }
    }
}

private struct CliFigure: View {
    let title: String
    let amount: Int
    let symbol: String
    let color: Color
    let size: CGFloat
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            MoneyText(amount: amount, size: size, weight: .bold)
            if let note {
                Text(verbatim: note)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Metrics.radiusS, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Qoldiq ≥ 0 — yashil; manfiy — qizil «Ortiqcha sarflangan»
private struct CliBalance: View {
    let qoldiq: Int
    var large = false

    var body: some View {
        let over = qoldiq < 0
        let color = over ? Palette.red : Palette.green
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: over ? "Ortiqcha sarflangan" : "Qoldiq")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
                Text(verbatim: over ? "Sarflangan pul siz bergandan ko‘p" : "Siz bergan puldan hali sarflanmagan")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            MoneyText(amount: abs(qoldiq), size: large ? 24 : 21, weight: .bold, color: color)
                .layoutPriority(1)
        }
        .padding(14)
        .background(over ? Palette.redSoft : Palette.greenSoft,
                    in: RoundedRectangle(cornerRadius: Metrics.radiusS, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Shartnoma: progress (siz bergan / shartnoma) va qolgan to'lov
private struct CliContract: View {
    let money: CliMoney

    private var ratio: Double {
        money.shartnoma > 0 ? Double(money.kirim) / Double(money.shartnoma) : 0
    }

    private var percentText: String {
        let p = Int((min(max(ratio, 0), 1) * 100).rounded())
        return "\(p)% to‘langan"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Shartnoma")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 8)
                MoneyText(amount: money.shartnoma, size: 15, weight: .semibold)
            }
            ProgressBar(value: ratio, color: Palette.green)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: percentText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 8)
                if money.qolganTolov > 0 {
                    Text("Qolgan to‘lov")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                    MoneyText(amount: money.qolganTolov, size: 14, weight: .bold, color: Palette.ink)
                        .layoutPriority(1)
                } else {
                    Label("To‘liq to‘langan", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.green)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
