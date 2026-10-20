// Usta formasi (yangi / tahrirlash): ism*, telefon, kasbi, izoh, faol. POST /api/workers yoki PUT /api/workers/:id.
import SwiftUI

struct WrkForm: View {
    let item: Worker?
    /// Yangi usta saqlangach — uning id si (sahifasini ochish uchun)
    var onSaved: ((Int?) -> Void)?

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var phone: String
    @State private var specialty: String
    @State private var note: String
    @State private var active: Bool
    @State private var saving = false
    @State private var errorText: String?
    @FocusState private var nameFocused: Bool

    init(item: Worker?, onSaved: ((Int?) -> Void)? = nil) {
        self.item = item
        self.onSaved = onSaved
        _name = State(initialValue: item?.name ?? "")
        _phone = State(initialValue: item?.phone ?? "")
        _specialty = State(initialValue: item?.specialty ?? "")
        _note = State(initialValue: item?.note ?? "")
        _active = State(initialValue: item?.active ?? true)
    }

    private var canSave: Bool { !ObjText.trim(name).isEmpty && !saving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ismi *").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                        TextField("masalan: Aziz aka", text: $name)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                            .textInputAutocapitalization(.words)
                            .focused($nameFocused)
                    }
                    .padding(.vertical, 2)
                    ObjField(title: "Kasbi", text: $specialty, prompt: "masalan: kafelchi, elektrik, suvoqchi")
                    ObjField(title: "Telefoni", text: $phone, prompt: "+998 90 123 45 67",
                             keyboard: .phonePad, contentType: .telephoneNumber, caps: .never)
                } header: {
                    Text("Usta")
                }
                .listRowBackground(Palette.surface)

                Section {
                    ObjNoteField(text: $note, prompt: "Kelishuv, kunlik/metrlik narx, karta raqami…")
                } header: {
                    Text("Izoh")
                }
                .listRowBackground(Palette.surface)

                if item != nil {
                    Section {
                        Toggle("Faol", isOn: $active).tint(Palette.green)
                    } footer: {
                        Text("Ish tugagan ustani o‘chirmasdan «faol emas» qiling — hisobi va yozuvlari saqlanib qoladi.")
                    }
                    .listRowBackground(Palette.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(item == nil ? "Yangi usta" : "Ustani tahrirlash")
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
        guard !saving else { return }   // ikki marta bosilsa ikkita yozuv yaratilmasin
        let n = ObjText.trim(name)
        guard !n.isEmpty else {
            errorText = "Usta ismini yozing."
            return
        }
        let body = WorkerBody(name: n, phone: ObjText.trim(phone), specialty: ObjText.trim(specialty),
                              note: ObjText.trim(note), active: active)
        saving = true
        defer { saving = false }
        do {
            let saved: ObjSaved
            if let item {
                saved = try await API.shared.put("/api/workers/\(item.id)", body: body)
            } else {
                saved = try await API.shared.post("/api/workers", body: body)
            }
            session.changed()
            session.show(item == nil ? "Usta qo‘shildi" : "Saqlandi")
            dismiss()
            if item == nil { onSaved?(saved.id > 0 ? saved.id : nil) }
        } catch is CancellationError {
        } catch {
            errorText = error.localizedDescription
        }
    }
}
