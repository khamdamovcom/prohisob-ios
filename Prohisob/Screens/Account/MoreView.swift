// «Yana» bo'limi: profil, magazinlar va hisobot, boshqaruv (obyekt egalari, xodimlar — prorab/egasi), kabinet tanlash (egasi),
// xavfsizlik (Face ID qulfi, parol), mavzu, yordam, chiqish. Shu yerda: parolni o'zgartirish va kabinet tanlash ekranlari.
import SwiftUI

struct MoreView: View {
    @Environment(Session.self) private var session
    @State private var askLogout = false
    @State private var showAbout = false
    @State private var showDelete = false

    var body: some View {
        List {
            profile
            hisob
            if session.isProrab { boshqaruv }
            if session.isEgasi { kabinet }
            xavfsizlik
            korinish
            yordam
            chiqish
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .navigationTitle("Yana")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Hisobdan chiqasizmi?", isPresented: $askLogout, titleVisibility: .visible) {
            Button("Chiqish", role: .destructive) { Task { await session.logout() } }
            Button("Bekor qilish", role: .cancel) {}
        } message: {
            Text("Qayta kirish uchun login va parol kerak bo‘ladi.")
        }
        .sheet(isPresented: $showAbout) { AccAboutSheet() }
        .sheet(isPresented: $showDelete) {
            AccDeleteAccountSheet(kind: session.role == .xodim ? .xodim : .prorab)
        }
    }

    // MARK: bo'limlar

    private var profile: some View {
        Section {
            AccProfileCard()
                .accRow()
        }
    }

    private var hisob: some View {
        Section("Hisob") {
            NavigationLink(value: Route.shops) {
                AccRowLabel(title: "Magazinlar", symbol: "storefront.fill", tone: .blue)
            }
            .accRow()
            NavigationLink(value: Route.report) {
                AccRowLabel(title: "Hisobot", symbol: "chart.bar.xaxis", tone: .purple)
            }
            .accRow()
        }
    }

    private var boshqaruv: some View {
        Section {
            NavigationLink(value: Route.clients) {
                AccRowLabel(title: "Obyekt egalari", symbol: "house.fill", tone: .teal)
            }
            .accRow()
            NavigationLink(value: Route.users) {
                AccRowLabel(title: "Xodimlar", symbol: "person.2.fill", tone: .orange)
            }
            .accRow()
        } header: {
            Text("Boshqaruv")
        } footer: {
            Text("Obyekt egasi o‘z obyektining hisobini kuzatadi; xodim yozuv kiritadi.")
        }
    }

    private var kabinet: some View {
        Section("Kabinet") {
            NavigationLink(value: Route.kabinets) {
                AccRowLabel(title: "Kabinetni tanlash", symbol: "building.2.fill", tone: .brand, value: session.kabinetName)
            }
            .accRow()
        }
    }

    private var xavfsizlik: some View {
        Section("Xavfsizlik") {
            Toggle(isOn: lockBinding) {
                AccRowLabel(title: "\(session.biometryName) bilan qulflash", symbol: session.biometrySymbol, tone: .green)
            }
            .tint(Palette.green)
            .accRow()
            NavigationLink(value: Route.password) {
                AccRowLabel(title: "Parolni o‘zgartirish", symbol: "key.fill", tone: .gray)
            }
            .accRow()
            // App Store 5.1.1(v): ilovada hisob yaratiladi — o'chirish ham ilovada (platforma egasidan tashqari)
            if !session.isEgasi {
                Button {
                    showDelete = true
                } label: {
                    AccRowLabel(title: "Hisobni o‘chirish", symbol: "person.crop.circle.badge.xmark", tone: .red,
                                titleColor: Palette.red)
                }
                .accRow()
            }
        }
    }

    private var korinish: some View {
        Section("Ko‘rinish") {
            Picker(selection: themeBinding) {
                ForEach(ThemeChoice.allCases) { t in
                    Text(t.label).tag(t)
                }
            } label: {
                AccRowLabel(title: "Mavzu", symbol: "circle.lefthalf.filled", tone: .purple)
            }
            .pickerStyle(.menu)
            .tint(Palette.muted)
            .accRow()
        }
    }

    private var yordam: some View {
        Section("Yordam") {
            Link(destination: AccApp.cabinet) {
                AccRowLabel(title: "Saytda ochish", symbol: "safari.fill", tone: .teal, external: true)
            }
            .accRow()
            Link(destination: AccApp.support) {
                AccRowLabel(title: "Qo‘llab-quvvatlash", symbol: "paperplane.fill", tone: .blue, value: "Telegram", external: true)
            }
            .accRow()
            Link(destination: AccApp.privacy) {
                AccRowLabel(title: "Maxfiylik siyosati", symbol: "hand.raised.fill", tone: .gray, external: true)
            }
            .accRow()
            Button {
                showAbout = true
            } label: {
                AccRowLabel(title: "Ilova haqida", symbol: "info", tone: .gray, value: "v\(AccApp.version) (\(AccApp.build))")
            }
            .accRow()
        }
    }

    private var chiqish: some View {
        Section {
            Button {
                askLogout = true
            } label: {
                HStack {
                    Spacer()
                    Label("Chiqish", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.red)
                    Spacer()
                }
            }
            .accRow()
        } footer: {
            Text(verbatim: "Prohisob \(AccApp.version) (\(AccApp.build)) · cabinet.prohisob.com")
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    // MARK: bog'lamalar

    private var lockBinding: Binding<Bool> {
        Binding(get: { session.lockEnabled }, set: { on in Task { await session.setLock(on) } })
    }

    private var themeBinding: Binding<ThemeChoice> {
        Binding(get: { session.theme }, set: { session.theme = $0 })
    }
}

/// Profil: avatar, ism, rol, login, kabinet
private struct AccProfileCard: View {
    @Environment(Session.self) private var session

    var body: some View {
        HStack(spacing: 14) {
            Avatar(name: accAvatarName(session.userName), size: 60, color: Palette.onBrand, soft: Palette.brand)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: session.userName.isEmpty ? "Foydalanuvchi" : session.userName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    AccRoleTag(role: session.role)
                    if let u = session.user?.username, !u.isEmpty {
                        Text(verbatim: "login: \(u)")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                }
                if !session.kabinetName.isEmpty {
                    AccMeta(symbol: "building.2.fill", text: session.kabinetName, lines: 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// «Ilova haqida»
private struct AccAboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    BrandMark(size: 76)
                        .shadow(color: Palette.brand.opacity(0.45), radius: 20, y: 8)
                        .padding(.top, 8)
                    VStack(spacing: 4) {
                        Text("Prohisob")
                            .font(.system(.title, design: .rounded, weight: .heavy))
                            .foregroundStyle(Palette.ink)
                        Text(verbatim: "Versiya \(AccApp.version) (\(AccApp.build))")
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                    }
                    Text("Prorablar uchun qurilish hisobi: obyektlar, ustalar, magazinlar, kirim-chiqim, cheklar va hisobot. Ma’lumot saytdagi kabinet bilan bir xil — saytda kiritilgani ilovada, ilovada kiritilgani saytda ko‘rinadi.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Link(destination: AccApp.home) {
                            Label("prohisob.com", systemImage: "globe")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .secondaryButton()
                        Link(destination: AccApp.support) {
                            Label("Telegram", systemImage: "paperplane.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .secondaryButton()
                    }
                    .tint(Palette.accent)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.bg)
            .navigationTitle("Ilova haqida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Yopish") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Parolni o'zgartirish

struct ChangePasswordView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var eski = ""
    @State private var yangi = ""
    @State private var takror = ""
    @State private var saving = false
    @State private var errorText: String?
    @FocusState private var focus: Int?

    private var tooShort: Bool { !yangi.isEmpty && yangi.count < 6 }
    private var mismatch: Bool { !takror.isEmpty && takror != yangi }
    private var canSave: Bool { !eski.isEmpty && yangi.count >= 6 && takror == yangi }

    var body: some View {
        Form {
            Section {
                AccPasswordField("Hozirgi parol", text: $eski, focus: $focus, tag: 0, contentType: .password, submitLabel: .next) {
                    focus = 1
                }
            } header: {
                Text("Hozirgi parol")
            }
            .accRow()

            Section {
                AccPasswordField("Yangi parol", text: $yangi, focus: $focus, tag: 1, contentType: .newPassword, submitLabel: .next) {
                    focus = 2
                }
                AccPasswordField("Yangi parolni takrorlang", text: $takror, focus: $focus, tag: 2, contentType: .newPassword, submitLabel: .done) {
                    Task { await save() }
                }
            } header: {
                Text("Yangi parol")
            } footer: {
                newFooter
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
                BrandButton(title: "Parolni o‘zgartirish", loading: saving, disabled: !canSave) {
                    Task { await save() }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Parolni o‘zgartirish")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy(duration: 0.25), value: errorText)
    }

    @ViewBuilder
    private var newFooter: some View {
        if tooShort {
            Text("Kamida 6 belgi bo‘lsin").foregroundStyle(Palette.red)
        } else if mismatch {
            Text("Parollar bir xil emas").foregroundStyle(Palette.red)
        } else {
            Text("Kamida 6 belgi. Parol o‘zgargach, boshqa qurilmalardagi kirishlar yopiladi — u yerda qaytadan kirish kerak bo‘ladi.")
        }
    }

    private func save() async {
        guard canSave, !saving else { return }
        focus = nil
        saving = true
        errorText = nil
        do {
            let _: AccIgnored = try await API.shared.post("/api/parol", body: PasswordBody(eski: eski, yangi: yangi))
            session.show("Parol o‘zgardi. Boshqa qurilmalardan chiqildi.")
            dismiss()
        } catch is CancellationError {
        } catch {
            errorText = error.localizedDescription
        }
        saving = false
    }
}

// MARK: - Kabinet tanlash (platforma egasi)

struct KabinetPickerView: View {
    @Environment(Session.self) private var session
    @State private var switching: Int?
    @State private var query = ""

    private var currentId: Int? { session.me?.kabinet?.id }

    private var list: [KabinetRef] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return session.kabinetlar }
        return session.kabinetlar.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        List {
            if !list.isEmpty {
                Section {
                    ForEach(list) { k in
                        row(k)
                    }
                } footer: {
                    Text("Tanlangan prorab kabineti bilan ishlaysiz: obyektlar, ustalar, yozuvlar va hisobot — shu kabinetniki.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .overlay {
            if session.kabinetlar.isEmpty {
                EmptyState(symbol: "building.2", title: "Kabinetlar yo‘q", message: "Prorab kabinetlari saytda qo‘shiladi.")
            } else if list.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "Topilmadi", message: "«\(query)» bo‘yicha kabinet yo‘q.")
            }
        }
        .searchable(text: $query, prompt: "Kabinet qidirish")
        .navigationTitle("Kabinetlar")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await session.refresh() }
    }

    private func row(_ k: KabinetRef) -> some View {
        Button {
            Task { await select(k) }
        } label: {
            HStack(spacing: 12) {
                AccIcon(symbol: "building.2.fill", tone: k.active ? .brand : .gray)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: k.name)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                    if !k.active {
                        AccTag(text: "To‘xtatilgan")
                    }
                }
                Spacer(minLength: 8)
                if switching == k.id {
                    ProgressView()
                } else if k.id == currentId {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Palette.accent)
                        .accessibilityLabel("Tanlangan")
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(switching != nil)
        .accRow()
        .accessibilityAddTraits(k.id == currentId ? .isSelected : [])
    }

    private func select(_ k: KabinetRef) async {
        guard k.id != currentId, switching == nil else { return }
        switching = k.id
        await session.selectKabinet(k.id)
        switching = nil
        session.show("Kabinet: \(k.name)")
    }
}
