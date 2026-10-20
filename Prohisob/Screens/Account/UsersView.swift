// Xodimlar — faqat prorab/egasi: ro'yxat, qo'shish, tahrirlash (ism, faol, yangi parol), o'chirish (o'zini emas).
// GET/POST/PUT/DELETE /api/users[/:id]. Xodim yozuv kiritadi va ko'radi, faqat o'zi kiritganini o'chiradi, sozlamalar yopiq.
import SwiftUI

private enum AccUserEditor: Identifiable {
    case new
    case edit(UserRow)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let u): return "u\(u.id)"
        }
    }

    var user: UserRow? {
        if case .edit(let u) = self { return u }
        return nil
    }
}

struct UsersView: View {
    @Environment(Session.self) private var session
    @State private var users: [UserRow] = []
    @State private var loaded = false
    @State private var loadError: Error?
    @State private var editor: AccUserEditor?
    @State private var deleting: UserRow?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bg)
            .navigationTitle("Xodimlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Xodim qo‘shish")
                }
            }
            .sheet(item: $editor) { e in
                AccUserForm(original: e.user)
            }
            .confirmationDialog("Xodim o‘chirilsinmi?", isPresented: askDelete, titleVisibility: .visible, presenting: deleting) { u in
                Button("O‘chirish", role: .destructive) { Task { await delete(u) } }
                Button("Bekor qilish", role: .cancel) {}
            } message: { u in
                Text(verbatim: "«\(accUserName(u))» endi ilovaga va saytga kira olmaydi. U kiritgan yozuvlar saqlanib qoladi.")
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
                    AccUsersIntro()
                        .accRow()
                }
                Section {
                    ForEach(users) { u in
                        row(u)
                    }
                } header: {
                    Text(verbatim: "Foydalanuvchilar · \(users.count)")
                } footer: {
                    if users.count <= 1 {
                        Text("Yordamchingiz yoki hisobchingizni «+» orqali qo‘shing.")
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

    private func isMe(_ u: UserRow) -> Bool { u.id == session.user?.id }

    /// O'zini va platforma egasini bu yerdan o'zgartirib bo'lmaydi
    private func editable(_ u: UserRow) -> Bool { !isMe(u) && u.roleValue != .egasi }

    @ViewBuilder
    private func row(_ u: UserRow) -> some View {
        if editable(u) {
            Button {
                editor = .edit(u)
            } label: {
                AccUserRow(user: u, isMe: false)
            }
            .accRow()
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    deleting = u
                } label: {
                    Label("O‘chirish", systemImage: "trash")
                }
                .tint(Palette.red)
                Button {
                    editor = .edit(u)
                } label: {
                    Label("Tahrirlash", systemImage: "pencil")
                }
                .tint(Palette.blue)
            }
            .contextMenu {
                Button {
                    editor = .edit(u)
                } label: {
                    Label("Tahrirlash", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleting = u
                } label: {
                    Label("O‘chirish", systemImage: "trash")
                }
            }
        } else {
            AccUserRow(user: u, isMe: isMe(u))
                .accRow()
        }
    }

    private func load() async {
        do {
            let list: [UserRow] = try await API.shared.get("/api/users")
            // o'zi tepada, keyin faollar
            let meId = session.user?.id
            users = list.enumerated().sorted { a, b in
                let ka = (a.element.id == meId ? 0 : 1, a.element.active ? 0 : 1, a.offset)
                let kb = (b.element.id == meId ? 0 : 1, b.element.active ? 0 : 1, b.offset)
                return ka < kb
            }.map(\.element)
            loaded = true
            loadError = nil
        } catch is CancellationError {
        } catch {
            if loaded { session.show(error.localizedDescription, error: true) } else { loadError = error }
        }
    }

    private func delete(_ u: UserRow) async {
        do {
            try await API.shared.delete("/api/users/\(u.id)")
            users.removeAll { $0.id == u.id }
            session.changed()
            session.show("O‘chirildi")
        } catch is CancellationError {
        } catch {
            session.show(error.localizedDescription, error: true)
        }
    }
}

/// Ko'rinadigan ism: ism bo'lmasa — login
private func accUserName(_ u: UserRow) -> String {
    if let n = u.name, !n.trimmingCharacters(in: .whitespaces).isEmpty { return n }
    return u.username
}

// MARK: - Qismlar

private struct AccUsersIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AccIcon(symbol: "person.2.fill", tone: .orange)
                Text("Xodim nima qila oladi")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
            }
            AccBullet(symbol: "checkmark.circle.fill", color: Palette.green,
                      text: "Yozuv kiritadi (kirim, to‘lov, xarajat, chek) va hisobni ko‘radi")
            AccBullet(symbol: "trash.circle.fill", color: Palette.orange, text: "Faqat o‘zi kiritgan yozuvni o‘chiradi")
            AccBullet(symbol: "lock.fill", color: Palette.gray,
                      text: "Sozlamalar, obyekt egalari va xodimlar bo‘limi unga yopiq")
        }
        .padding(.vertical, 6)
    }
}

private struct AccUserRow: View {
    let user: UserRow
    let isMe: Bool

    private var hasTelegram: Bool { !(user.telegramId?.text ?? "").isEmpty }

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: accAvatarName(accUserName(user)), size: 44, color: user.active ? Palette.ink : Palette.muted,
                   soft: user.active ? Palette.brandSoft : Palette.graySoft)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(verbatim: accUserName(user))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if isMe {
                        AccTag(text: "Siz", color: Palette.green, soft: Palette.greenSoft)
                    }
                }
                AccMeta(symbol: "person.text.rectangle", text: user.username, lines: 1)
                HStack(spacing: 6) {
                    AccRoleTag(role: user.roleValue)
                    if !user.active {
                        AccTag(text: "Faol emas")
                    }
                    if hasTelegram {
                        Image(systemName: "paperplane.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.blue)
                            .accessibilityLabel("Telegram ulangan")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Forma

private struct AccUserForm: View {
    let original: UserRow?
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var name: String
    @State private var password = ""
    @State private var active: Bool
    @State private var saving = false
    @State private var errorText: String?
    @State private var done: AccCredentials?
    @State private var askDelete = false
    @FocusState private var focus: Int?

    init(original: UserRow?) {
        self.original = original
        _name = State(initialValue: original?.name ?? "")
        _active = State(initialValue: original?.active ?? true)
    }

    private var isNew: Bool { original == nil }
    private var trimmedLogin: String { username.trimmingCharacters(in: .whitespaces) }
    private var loginValid: Bool { trimmedLogin.count >= 3 && !trimmedLogin.contains(where: \.isWhitespace) }
    private var canSave: Bool { !saving && (!isNew || (loginValid && !password.isEmpty)) }

    private var title: String {
        if done != nil { return "Kirish ma’lumoti" }
        return isNew ? "Yangi xodim" : "Xodim"
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
            if let original {
                editSections(original)
            } else {
                newSections
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .scrollDismissesKeyboard(.interactively)
        .animation(.snappy(duration: 0.25), value: errorText)
        .confirmationDialog("Xodim o‘chirilsinmi?", isPresented: $askDelete, titleVisibility: .visible) {
            Button("O‘chirish", role: .destructive) { Task { await remove() } }
            Button("Bekor qilish", role: .cancel) {}
        } message: {
            Text("U endi ilovaga va saytga kira olmaydi. Kiritgan yozuvlari saqlanib qoladi.")
        }
    }

    @ViewBuilder
    private var newSections: some View {
        Section {
            TextField("Login *", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.next)
                .focused($focus, equals: 0)
                .onSubmit { focus = 1 }
            TextField("Ism", text: $name)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($focus, equals: 1)
                .onSubmit { focus = 2 }
            HStack(spacing: 4) {
                AccPasswordField("Parol *", text: $password, focus: $focus, tag: 2,
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
            Text("Yangi xodim")
        } footer: {
            if !username.isEmpty && !loginValid {
                Text("Login kamida 3 belgi, bo‘sh joysiz bo‘lsin").foregroundStyle(Palette.red)
            } else {
                Text("Xodim shu login va parol bilan ilovaga yoki cabinet.prohisob.com saytiga kiradi.")
            }
        }
        .accRow()
    }

    @ViewBuilder
    private func editSections(_ u: UserRow) -> some View {
        Section {
            LabeledContent("Login") {
                Text(verbatim: u.username)
                    .font(.body.monospaced())
                    .foregroundStyle(Palette.ink)
            }
            LabeledContent("Rol") {
                AccRoleTag(role: u.roleValue)
            }
            TextField("Ism", text: $name)
                .textInputAutocapitalization(.words)
                .focused($focus, equals: 1)
        } header: {
            Text("Xodim")
        }
        .accRow()

        Section {
            Toggle("Faol", isOn: $active)
                .tint(Palette.green)
        } footer: {
            Text("Faol bo‘lmasa, xodim ilovaga ham, saytga ham kira olmaydi.")
        }
        .accRow()

        Section {
            AccPasswordField("Yangi parol (ixtiyoriy)", text: $password, focus: $focus, tag: 2,
                             contentType: nil, submitLabel: .done, revealed: true)
        } header: {
            Text("Parol")
        } footer: {
            if password.isEmpty {
                Text("Parolni o‘zgartirmasangiz, bo‘sh qoldiring.")
            } else {
                Text("Parol o‘zgarsa, xodimning boshqa qurilmalardagi kirishlari yopiladi — yangi parolni unga yuboring.")
                    .foregroundStyle(Palette.orange)
            }
        }
        .accRow()

        Section {
            Button {
                askDelete = true
            } label: {
                HStack {
                    Spacer()
                    Label("Xodimni o‘chirish", systemImage: "trash")
                        .foregroundStyle(Palette.red)
                    Spacer()
                }
            }
            .disabled(saving)
        }
        .accRow()
    }

    // MARK: amallar

    private func save() async {
        guard canSave else { return }
        focus = nil
        saving = true
        errorText = nil
        var req = UserBody(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            if let original {
                req.active = active
                if !password.isEmpty { req.password = password }
                let _: AccIgnored = try await API.shared.put("/api/users/\(original.id)", body: req)
                session.changed()
                if password.isEmpty {
                    session.show("Saqlandi")
                    dismiss()
                } else {
                    done = credentials(login: original.username, isNew: false)
                }
            } else {
                req.username = trimmedLogin
                req.password = password
                let _: AccIgnored = try await API.shared.post("/api/users", body: req)
                session.changed()
                done = credentials(login: trimmedLogin, isNew: true)
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
            try await API.shared.delete("/api/users/\(original.id)")
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
        let text = "Prohisob: ilovani o‘rnating (App Store: Prohisob) yoki cabinet.prohisob.com saytiga kiring. Login: \(login), parol: \(password)"
        return AccCredentials(
            title: isNew ? "Xodim qo‘shildi" : "Parol o‘zgardi",
            message: "Kirish ma’lumotini xodimga yuboring — u ilovada yoki saytda yozuv kirita oladi.",
            login: login,
            password: password,
            shareText: text
        )
    }
}
