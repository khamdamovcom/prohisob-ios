// Magazin formasi (yangi / tahrirlash): nomi*, telefon, manzil, izoh, faol. POST /api/shops yoki PUT /api/shops/:id.
import SwiftUI

struct ShpForm: View {
    let item: Shop?
    /// Yangi magazin saqlangach — uning id si (sahifasini ochish uchun)
    var onSaved: ((Int?) -> Void)?

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var phone: String
    @State private var address: String
    @State private var note: String
    @State private var active: Bool
    @State private var saving = false
    @State private var errorText: String?
    @FocusState private var nameFocused: Bool

    init(item: Shop?, onSaved: ((Int?) -> Void)? = nil) {
        self.item = item
        self.onSaved = onSaved
        _name = State(initialValue: item?.name ?? "")
        _phone = State(initialValue: item?.phone ?? "")
        _address = State(initialValue: item?.address ?? "")
        _note = State(initialValue: item?.note ?? "")
        _active = State(initialValue: item?.active ?? true)
    }

    private var canSave: Bool { !ObjText.trim(name).isEmpty && !saving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nomi *").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                        TextField("masalan: Qurilish Mol Markazi", text: $name)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                            .focused($nameFocused)
                    }
                    .padding(.vertical, 2)
                    ObjField(title: "Manzil", text: $address, prompt: "masalan: Jome bozori, 12-do‘kon")
                    ObjField(title: "Telefoni", text: $phone, prompt: "+998 71 200 10 10",
                             keyboard: .phonePad, contentType: .telephoneNumber, caps: .never)
                } header: {
                    Text("Magazin")
                }
                .listRowBackground(Palette.surface)

                Section {
                    ObjNoteField(text: $note, prompt: "Sotuvchi ismi, karta raqami, chegirma…")
                } header: {
                    Text("Izoh")
                }
                .listRowBackground(Palette.surface)

                if item != nil {
                    Section {
                        Toggle("Faol", isOn: $active).tint(Palette.green)
                    } footer: {
                        Text("Endi mol olinmaydigan magazinni o‘chirmasdan «faol emas» qiling — hisobi saqlanib qoladi.")
                    }
                    .listRowBackground(Palette.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(item == nil ? "Yangi magazin" : "Magazinni tahrirlash")
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

    private func save() async {
        let n = ObjText.trim(name)
        guard !n.isEmpty else {
            errorText = "Magazin nomini yozing."
            return
        }
        let body = ShopBody(name: n, phone: ObjText.trim(phone), address: ObjText.trim(address),
                            note: ObjText.trim(note), active: active)
        saving = true
        defer { saving = false }
        do {
            let saved: ObjSaved
            if let item {
                saved = try await API.shared.put("/api/shops/\(item.id)", body: body)
            } else {
                saved = try await API.shared.post("/api/shops", body: body)
            }
            session.changed()
            session.show(item == nil ? "Magazin qo‘shildi" : "Saqlandi")
            dismiss()
            if item == nil { onSaved?(saved.id > 0 ? saved.id : nil) }
        } catch is CancellationError {
        } catch {
            errorText = error.localizedDescription
        }
    }
}
