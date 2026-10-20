// Obyekt egalari (mijozlar) — faqat prorab/egasi: ro'yxat, qo'shish, tahrirlash, o'chirish va kirish ma'lumotini yuborish.
// GET/POST/PUT/DELETE /api/clients[/:id]. Obyekt egasi ilovada (obyekt egasi rejimi) yoki Telegram botda faqat o'z obyekti
// hisobini ko'radi: bergan puli, har bir xarajat (izoh va cheki bilan), qoldiq. Foyda va qarzlar unga ko'rinmaydi.
import SwiftUI
import UIKit

private enum AccClientEditor: Identifiable {
    case new
    case edit(Client)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let c): return "c\(c.id)"
        }
    }

    var client: Client? {
        if case .edit(let c) = self { return c }
        return nil
    }
}

struct ClientsView: View {
    @Environment(Session.self) private var session
    @State private var clients: [Client] = []
    @State private var bot: String?
    @State private var loaded = false
    @State private var loadError: Error?
    @State private var editor: AccClientEditor?
    @State private var deleting: Client?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bg)
            .navigationTitle("Obyekt egalari")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Obyekt egasi qo‘shish")
                }
            }
            .sheet(item: $editor) { e in
                AccClientForm(original: e.client, bot: bot)
            }
            .confirmationDialog("Obyekt egasi o‘chirilsinmi?", isPresented: askDelete, titleVisibility: .visible, presenting: deleting) { c in
                Button("O‘chirish", role: .destructive) { Task { await delete(c) } }
                Button("Bekor qilish", role: .cancel) {}
            } message: { c in
                Text(verbatim: "«\(c.name)» endi ilova va Telegram bot orqali obyekt hisobini ko‘ra olmaydi.")
            }
            .task(id: session.dataVersion) { await load() }
    }

    private var askDelete: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    @ViewBuilder
    private var content: some View {
        if loaded {
            List {
                Section {
                    AccClientsIntro(bot: bot)
                        .accRow()
                }
                if clients.isEmpty {
                    Section {
                        emptyRow
                            .accRow()
                    }
                } else {
                    Section {
                        ForEach(clients) { c in
                            row(c)
                        }
                    } header: {
                        Text(verbatim: "Obyekt egalari · \(clients.count)")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .refreshable { await load() }
        } else if let loadError {
            ErrorState(error: loadError) { await load() }
        } else {
            LoadingState()
        }
    }

    private var emptyRow: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            Text("Hali obyekt egasi qo‘shilmagan")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("Uy egasiga login va parol bering — u obyekt hisobini telefonida kuzatib boradi.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Button {
                editor = .new
            } label: {
                Label("Obyekt egasi qo‘shish", systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.onBrand)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.brand)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func row(_ c: Client) -> some View {
        Button {
            editor = .edit(c)
        } label: {
            AccClientRow(client: c)
        }
        .accRow()
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                deleting = c
            } label: {
                Label("O‘chirish", systemImage: "trash")
            }
            .tint(Palette.red)
            Button {
                editor = .edit(c)
            } label: {
                Label("Tahrirlash", systemImage: "pencil")
            }
            .tint(Palette.blue)
        }
        .contextMenu {
            Button {
                editor = .edit(c)
            } label: {
                Label("Tahrirlash", systemImage: "pencil")
            }
            if let url = accTelURL(c.phone) {
                Link(destination: url) {
                    Label("Qo‘ng‘iroq qilish", systemImage: "phone")
                }
            }
            Button(role: .destructive) {
                deleting = c
            } label: {
                Label("O‘chirish", systemImage: "trash")
            }
        }
    }

    private func load() async {
        do {
            let r: ClientsResponse = try await API.shared.get("/api/clients")
            clients = r.clients
            bot = r.bot
            loaded = true
            loadError = nil
        } catch is CancellationError {
        } catch {
            if loaded { session.show(error.localizedDescription, error: true) } else { loadError = error }
        }
    }

    private func delete(_ c: Client) async {
        do {
            try await API.shared.delete("/api/clients/\(c.id)")
            clients.removeAll { $0.id == c.id }
            session.changed()
            session.show("O‘chirildi")
        } catch is CancellationError {
        } catch {
            session.show(error.localizedDescription, error: true)
        }
    }
}

// MARK: - Qismlar

/// Tepadagi izoh: obyekt egasi nimani ko'radi va nimani ko'rmaydi
private struct AccClientsIntro: View {
    let bot: String?

    private var lead: String {
        if let bot, !bot.isEmpty {
            return "Ilovada yoki Telegram botda (@\(bot)) o‘z obyektining hisobini kuzatadi."
        }
        return "Ilovada yoki Telegram botda o‘z obyektining hisobini kuzatadi."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AccIcon(symbol: "eye.fill", tone: .teal)
                Text("Obyekt egasi nimani ko‘radi")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
            }
            Text(verbatim: lead)
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            AccBullet(symbol: "checkmark.circle.fill", color: Palette.green,
                      text: "Bergan puli, har bir xarajat (izohi va cheki bilan) va qoldiq")
            AccBullet(symbol: "eye.slash.fill", color: Palette.orange, text: "Foyda va qarzlarni ko‘rmaydi")
            AccBullet(symbol: "lock.fill", color: Palette.gray, text: "Hech narsani o‘zgartira olmaydi")
        }
        .padding(.vertical, 6)
    }
}

private struct AccClientRow: View {
    let client: Client

    private var objectsText: String {
        client.objects.isEmpty ? "Obyekt biriktirilmagan" : client.objects.map(\.name).joined(separator: ", ")
    }

    private var telegramText: String {
        client.telegram > 0 ? "Telegram: \(client.telegram) ta ulangan" : "Telegram ulanmagan"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(name: accAvatarName(client.name), size: 44, color: client.active ? Palette.ink : Palette.muted,
                   soft: client.active ? Palette.brandSoft : Palette.graySoft)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(verbatim: client.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if !client.active {
                        AccTag(text: "Faol emas")
                    }
                }
                AccMeta(symbol: "person.text.rectangle", text: client.login, lines: 1)
                AccMeta(symbol: "building.2", text: objectsText,
                        color: client.objects.isEmpty ? Palette.orange : Palette.muted)
                AccMeta(symbol: "paperplane", text: telegramText,
                        color: client.telegram > 0 ? Palette.blue : Palette.muted, lines: 1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tahrirlash")
    }
}

// MARK: - Forma (qo'shish / tahrirlash)

private struct AccClientForm: View {
    let original: Client?
    let bot: String?
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var phone: String
    @State private var login = ""
    @State private var password = ""
    @State private var note: String
    @State private var selected: Set<Int>
    @State private var active: Bool
    @State private var objects: [ObjectItem]?
    @State private var objectsError: String?
    @State private var saving = false
    @State private var errorText: String?
    @State private var done: AccCredentials?
    @State private var askDelete = false
    @FocusState private var focus: Int?

    init(original: Client?, bot: String?) {
        self.original = original
        self.bot = bot
        _name = State(initialValue: original?.name ?? "")
        _phone = State(initialValue: original?.phone ?? "")
        _note = State(initialValue: original?.note ?? "")
        _selected = State(initialValue: Set(original?.objects.map(\.id) ?? []))
        _active = State(initialValue: original?.active ?? true)
    }

    private var isNew: Bool { original == nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var loginValid: Bool { login.range(of: "^[a-z0-9_.]{3,32}$", options: .regularExpression) != nil }
    private var canSave: Bool {
        !saving && !trimmedName.isEmpty && (!isNew || (loginValid && !password.isEmpty))
    }

    private var title: String {
        if done != nil { return "Kirish ma’lumoti" }
        return isNew ? "Yangi obyekt egasi" : "Obyekt egasi"
    }

    var body: some View {
        NavigationStack {
            Group {
                if let done {
                    AccCredentialsView(cred: done)
                } else {
                    form
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(saving || done != nil)
        .task { await loadObjects() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if done != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Tayyor") { dismiss() }
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Bekor qilish") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if saving {
                    ProgressView()
                } else {
                    Button("Saqlash") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    private var form: some View {
        Form {
            if let errorText {
                Section {
                    AccErrorBanner(text: errorText)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            personSection
            accessSection
            objectsSection
            noteSection
            if !isNew {
                statusSection
                deleteSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .scrollDismissesKeyboard(.interactively)
        .animation(.snappy(duration: 0.25), value: errorText)
        .confirmationDialog("Obyekt egasi o‘chirilsinmi?", isPresented: $askDelete, titleVisibility: .visible) {
            Button("O‘chirish", role: .destructive) { Task { await remove() } }
            Button("Bekor qilish", role: .cancel) {}
        } message: {
            Text("U endi ilova va Telegram bot orqali obyekt hisobini ko‘ra olmaydi.")
        }
    }

    private var personSection: some View {
        Section {
            TextField("Ism familiya *", text: $name)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($focus, equals: 0)
                .onSubmit { focus = 1 }
            TextField("Telefon", text: $phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .focused($focus, equals: 1)
        } header: {
            Text("Obyekt egasi")
        }
        .accRow()
    }

    @ViewBuilder
    private var accessSection: some View {
        if let original {
            Section {
                LabeledContent("Login") {
                    Text(verbatim: original.login)
                        .font(.body.monospaced())
                        .foregroundStyle(Palette.ink)
                }
                AccPasswordField("Yangi parol (ixtiyoriy)", text: $password, focus: $focus, tag: 3,
                                 contentType: nil, submitLabel: .done, revealed: true)
            } header: {
                Text("Kirish")
            } footer: {
                if password.isEmpty {
                    Text("Parolni o‘zgartirmasangiz, bo‘sh qoldiring.")
                } else {
                    Text("Parol o‘zgarsa, obyekt egasining Telegram bot va ilovadagi kirishlari yopiladi — yangi parolni unga yuboring.")
                        .foregroundStyle(Palette.orange)
                }
            }
            .accRow()
        } else {
            Section {
                TextField("Login *", text: $login)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.next)
                    .focused($focus, equals: 2)
                    .onSubmit { focus = 3 }
                    .onChange(of: login) { _, v in
                        let f = v.lowercased().filter { !$0.isWhitespace }
                        if f != v { login = f }
                    }
                HStack(spacing: 4) {
                    AccPasswordField("Parol *", text: $password, focus: $focus, tag: 3,
                                     contentType: nil, submitLabel: .done, revealed: true)
                    Button {
                        password = AccPassword.generate()
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Parol yaratish")
                }
            } header: {
                Text("Kirish ma’lumoti")
            } footer: {
                if !login.isEmpty && !loginValid {
                    Text(verbatim: "Login: 3–32 belgi — lotin kichik harf, raqam, «_» yoki «.»")
                        .foregroundStyle(Palette.red)
                } else {
                    Text(verbatim: "Login: 3–32 belgi — lotin kichik harf, raqam, «_» yoki «.». Obyekt egasi shu login va parol bilan ilovaga yoki Telegram botga kiradi.")
                }
            }
            .accRow()
        }
    }

    private var objectsSection: some View {
        Section {
            if let objects {
                if objects.isEmpty {
                    Text("Hozircha obyekt yo‘q")
                        .foregroundStyle(Palette.muted)
                } else {
                    ForEach(objects) { o in
                        Toggle(isOn: objectBinding(o.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: o.name)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(2)
                                Text(verbatim: o.statusValue.label)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(o.statusValue.color)
                            }
                        }
                        .tint(Palette.green)
                    }
                }
            } else if let objectsError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: objectsError)
                        .font(.subheadline)
                        .foregroundStyle(Palette.red)
                    Button("Qayta urinish") { Task { await loadObjects() } }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Palette.accent)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Obyektlar yuklanmoqda…")
                        .foregroundStyle(Palette.muted)
                }
            }
        } header: {
            Text("Obyektlari")
        } footer: {
            Text("Obyekt egasi faqat belgilangan obyektlar hisobini ko‘radi.")
        }
        .accRow()
    }

    private var noteSection: some View {
        Section {
            TextField("Izoh", text: $note, axis: .vertical)
                .lineLimit(1...4)
        } header: {
            Text("Izoh")
        }
        .accRow()
    }

    private var statusSection: some View {
        Section {
            Toggle("Faol", isOn: $active)
                .tint(Palette.green)
        } footer: {
            Text("Faol bo‘lmasa, obyekt egasi ilovaga ham, Telegram botga ham kira olmaydi.")
        }
        .accRow()
    }

    private var deleteSection: some View {
        Section {
            Button {
                askDelete = true
            } label: {
                HStack {
                    Spacer()
                    Label("Obyekt egasini o‘chirish", systemImage: "trash")
                        .foregroundStyle(Palette.red)
                    Spacer()
                }
            }
            .disabled(saving)
        }
        .accRow()
    }

    private func objectBinding(_ id: Int) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { on in
            if on { selected.insert(id) } else { selected.remove(id) }
        })
    }

    // MARK: amallar

    private func loadObjects() async {
        objectsError = nil
        do {
            let list: [ObjectItem] = try await API.shared.get("/api/objects")
            objects = list
        } catch is CancellationError {
        } catch {
            objectsError = error.localizedDescription
        }
    }

    private func save() async {
        guard canSave else { return }
        focus = nil
        saving = true
        errorText = nil
        var req = ClientBody(name: trimmedName)
        req.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        req.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        req.objectIds = selected.sorted()
        do {
            if let original {
                req.active = active
                if !password.isEmpty { req.password = password }
                let _: AccIgnored = try await API.shared.put("/api/clients/\(original.id)", body: req)
                session.changed()
                if password.isEmpty {
                    session.show("Saqlandi")
                    dismiss()
                } else {
                    done = credentials(login: original.login, isNew: false)
                }
            } else {
                req.login = login
                req.password = password
                let _: AccIgnored = try await API.shared.post("/api/clients", body: req)
                session.changed()
                done = credentials(login: login, isNew: true)
            }
        } catch is CancellationError {
        } catch {
            errorText = error.localizedDescription
        }
        saving = false
    }

    private func remove() async {
        guard let original else { return }
        saving = true
        errorText = nil
        do {
            try await API.shared.delete("/api/clients/\(original.id)")
            session.changed()
            session.show("O‘chirildi")
            dismiss()
        } catch is CancellationError {
        } catch {
            errorText = error.localizedDescription
        }
        saving = false
    }

    private func credentials(login: String, isNew: Bool) -> AccCredentials {
        var botPart = ""
        if let bot, !bot.isEmpty { botPart = " (@\(bot))" }
        let text = "Prohisob: obyektingiz hisobini kuzatish uchun ilovani o‘rnating (App Store: Prohisob) yoki Telegram botga kiring\(botPart). Login: \(login), parol: \(password)"
        return AccCredentials(
            title: isNew ? "Obyekt egasi qo‘shildi" : "Parol o‘zgardi",
            message: "Kirish ma’lumotini obyekt egasiga yuboring — u ilovada yoki Telegram botda obyekt hisobini ko‘radi.",
            login: login,
            password: password,
            shareText: text
        )
    }
}
