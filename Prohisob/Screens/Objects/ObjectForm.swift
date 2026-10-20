// Obyekt formasi (yangi / tahrirlash): nomi*, manzil, uy egasi va telefoni, shartnoma summasi, boshlanish/tugash sanasi
// (ixtiyoriy), holat, izoh. POST /api/objects yoki PUT /api/objects/:id → session.changed() + xabar.
import SwiftUI

struct ObjForm: View {
    let item: ObjectItem?
    /// Yangi obyekt saqlangach — uning id si (sahifasini ochish uchun)
    var onSaved: ((Int?) -> Void)?

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var address: String
    @State private var ownerName: String
    @State private var ownerPhone: String
    @State private var contract: String
    @State private var hasStart: Bool
    @State private var start: Date
    @State private var hasEnd: Bool
    @State private var end: Date
    @State private var status: ObjectStatus
    @State private var note: String
    @State private var saving = false
    @State private var errorText: String?
    @FocusState private var nameFocused: Bool

    init(item: ObjectItem?, onSaved: ((Int?) -> Void)? = nil) {
        self.item = item
        self.onSaved = onSaved
        _name = State(initialValue: item?.name ?? "")
        _address = State(initialValue: item?.address ?? "")
        _ownerName = State(initialValue: item?.ownerName ?? "")
        _ownerPhone = State(initialValue: item?.ownerPhone ?? "")
        let c = item?.contractAmount ?? 0
        _contract = State(initialValue: c > 0 ? Fmt.money(c) : "")
        let s = Fmt.parseDay(item?.startDate)
        let e = Fmt.parseDay(item?.endDate)
        // yangi obyekt — bugundan boshlanadi (o'chirib qo'yish mumkin)
        _hasStart = State(initialValue: item == nil ? true : s != nil)
        _start = State(initialValue: s ?? Date())
        _hasEnd = State(initialValue: e != nil)
        _end = State(initialValue: e ?? Date())
        _status = State(initialValue: item?.statusValue ?? .faol)
        _note = State(initialValue: item?.note ?? "")
    }

    private var canSave: Bool { !ObjText.trim(name).isEmpty && !saving }

    var body: some View {
        NavigationStack {
            Form {
                mainSection
                ownerSection
                contractSection
                statusSection
                Section {
                    ObjNoteField(text: $note, prompt: "Kelishuv shartlari, dollar kursi…")
                } header: {
                    Text("Izoh")
                }
                .listRowBackground(Palette.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(item == nil ? "Yangi obyekt" : "Obyektni tahrirlash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            .alert("Saqlab bo‘lmadi", isPresented: errorShown) {
                Button("Yaxshi", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
            .interactiveDismissDisabled(saving)
            .task {
                guard item == nil else { return }
                try? await Task.sleep(for: .milliseconds(450))
                nameFocused = true
            }
        }
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
    }

    // MARK: Bo'limlar

    private var mainSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nomi *").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                TextField("masalan: Chilonzor 9, hovli", text: $name)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .focused($nameFocused)
                    .submitLabel(.next)
            }
            .padding(.vertical, 2)
            ObjField(title: "Manzil", text: $address, prompt: "masalan: Toshkent, Yunusobod tumani")
        } header: {
            Text("Obyekt")
        }
        .listRowBackground(Palette.surface)
    }

    private var ownerSection: some View {
        Section {
            ObjField(title: "Ismi", text: $ownerName, prompt: "masalan: Akmal Karimov", caps: .words)
            ObjField(title: "Telefoni", text: $ownerPhone, prompt: "+998 90 123 45 67",
                     keyboard: .phonePad, contentType: .telephoneNumber, caps: .never)
        } header: {
            Text("Uy egasi")
        }
        .listRowBackground(Palette.surface)
    }

    private var contractSection: some View {
        Section {
            AmountField(title: "Shartnoma summasi", text: $contract)
                .padding(.vertical, 2)
            Toggle("Boshlanish sanasi", isOn: $hasStart.animation())
                .tint(Palette.green)
            if hasStart {
                DatePicker("Boshlangan", selection: $start, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "uz_Latn_UZ"))
            }
            Toggle("Tugash sanasi", isOn: $hasEnd.animation())
                .tint(Palette.green)
            if hasEnd {
                DatePicker("Tugash", selection: $end, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "uz_Latn_UZ"))
            }
        } header: {
            Text("Shartnoma va muddat")
        } footer: {
            Text("Shartnoma summasi yozilsa, uy egasidan necha foiz olingani ko‘rinadi. Bo‘sh qoldirish mumkin.")
        }
        .listRowBackground(Palette.surface)
    }

    private var statusSection: some View {
        Section {
            Picker("Holat", selection: $status) {
                ForEach(ObjectStatus.allCases) { s in Text(s.label).tag(s) }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
        } header: {
            Text("Holat")
        } footer: {
            Text("Sof foyda faqat «Tugagan» obyektda ko‘rsatiladi.")
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: Saqlash

    private func save() async {
        let n = ObjText.trim(name)
        guard !n.isEmpty else {
            errorText = "Obyekt nomini yozing."
            return
        }
        var amount = 0
        let raw = ObjText.trim(contract)
        if !raw.isEmpty {
            guard let v = Fmt.parseAmount(raw) else {
                errorText = "Shartnoma summasini to‘g‘ri yozing (masalan: 180 000 000 yoki 180 mln)."
                return
            }
            amount = v
        }
        let body = ObjectBody(name: n, address: ObjText.trim(address), ownerName: ObjText.trim(ownerName),
                              ownerPhone: ObjText.trim(ownerPhone), contractAmount: amount,
                              startDate: hasStart ? Fmt.apiDate(start) : "", endDate: hasEnd ? Fmt.apiDate(end) : "",
                              status: status.rawValue, note: ObjText.trim(note))
        saving = true
        defer { saving = false }
        do {
            let saved: ObjSaved
            if let item {
                saved = try await API.shared.put("/api/objects/\(item.id)", body: body)
            } else {
                saved = try await API.shared.post("/api/objects", body: body)
            }
            session.changed()
            session.show(item == nil ? "Obyekt qo‘shildi" : "Saqlandi")
            dismiss()
            if item == nil { onSaved?(saved.id > 0 ? saved.id : nil) }
        } catch is CancellationError {
        } catch {
            errorText = error.localizedDescription
        }
    }
}
