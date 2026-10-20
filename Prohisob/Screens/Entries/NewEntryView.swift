// «Yangi yozuv» oynasi (router.newEntry): 1-qadam — «Nima bo'ldi?» (amal turi to'ri), 2-qadam — forma: summa (ochilganda
// fokus), turga qarab obyekt/usta/magazin (qidiruvli tanlash), sana, «nima uchun», izoh, xaridda shu zahoti to'langan
// qism, chek rasmlari (galereya/kamera/PDF). Saqlash: POST /api/entries → cheklar yuklanadi → session.changed().
// Maqsad: prorab obyektda turib bir qo'lda 10 soniyada yozuv qo'shsin (oxirgi obyekt eslab qolinadi, tugma pastda).
import SwiftUI
import UIKit
import Observation

struct NewEntryView: View {
    let prefill: EntryPrefill

    init(prefill: EntryPrefill) {
        self.prefill = prefill
        _model = State(initialValue: NewEntModel(prefill: prefill))
        _path = State(initialValue: prefill.type.map { [$0] } ?? [])
    }

    @Environment(\.dismiss) private var dismiss
    @State private var model: NewEntModel
    @State private var path: [EntryType]
    @State private var confirmClose = false

    var body: some View {
        NavigationStack(path: $path) {
            NewEntTypeGrid(model: model, current: model.type) { t in
                path = [t]
            }
            .navigationTitle("Nima bo‘ldi?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Bekor qilish") { requestClose() }
                }
            }
            .navigationDestination(for: EntryType.self) { t in
                NewEntForm(type: t, model: model,
                           changeType: { path = [] },
                           cancel: { requestClose() },
                           close: { dismiss() })
            }
        }
        .interactiveDismissDisabled(model.hasInput || model.saving)
        .task { await model.loadDirectory() }
        .confirmationDialog("Kiritilgan ma’lumot saqlanmaydi", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Saqlamasdan chiqish", role: .destructive) { dismiss() }
            Button("Davom etish", role: .cancel) {}
        }
    }

    private func requestClose() {
        if model.saving { return }
        if model.hasInput { confirmClose = true } else { dismiss() }
    }
}

// MARK: - Holat

enum NewEntErr: CaseIterable, Hashable {
    case amount, object, worker, shop, paid

    init(_ f: EntryType.Field) {
        switch f {
        case .object: self = .object
        case .worker: self = .worker
        case .shop: self = .shop
        }
    }
}

struct NewEntItem: Identifiable, Hashable {
    let id: Int
    let name: String
    let detail: String?
}

struct NewEntGroup: Identifiable {
    let title: String
    let items: [NewEntItem]
    var id: String { title }
}

/// Forma holati: kiritilgan qiymatlar, tanlovlar, ro'yxatlar (obyekt/usta/magazin — bir marta yuklanadi)
@MainActor
@Observable
final class NewEntModel {
    static let lastObjectKey = "newEntry.lastObject"

    var type: EntryType?
    var amountText: String
    var paidText = ""
    var date = Date()
    var title = ""
    var note = ""
    var objectId: Int?
    var workerId: Int?
    var shopId: Int?
    /// Obyekt avtomatik tanlangan (oxirgi ishlatilgan yoki yagona faol)
    var autoObject = false
    var attachments: [EntPicked] = []
    var preparing = false
    var saving = false
    var errors: [NewEntErr: String] = [:]
    var formError: String?

    var objects: [ObjectItem] = []
    var workers: [Worker] = []
    var shops: [Shop] = []
    var dirLoading = false
    var dirLoaded = false
    var dirError: String?

    let prefill: EntryPrefill
    private let initialAmount: String

    init(prefill: EntryPrefill) {
        self.prefill = prefill
        objectId = prefill.objectId
        workerId = prefill.workerId
        shopId = prefill.shopId
        let a = prefill.amount.flatMap { $0 > 0 ? Fmt.money($0) : nil } ?? ""
        amountText = a
        initialAmount = a
    }

    var amount: Int { Fmt.parseAmount(amountText) ?? 0 }

    /// Bekor qilishda so'rash kerakmi
    var hasInput: Bool {
        amountText != initialAmount || !paidText.isEmpty || !trim(title).isEmpty || !trim(note).isEmpty || !attachments.isEmpty
    }

    var firstError: NewEntErr? { NewEntErr.allCases.first { errors[$0] != nil } }

    private func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: ro'yxatlar

    func loadDirectory() async {
        guard !dirLoading else { return }
        dirLoading = true
        dirError = nil
        async let o: [ObjectItem] = API.shared.get("/api/objects")
        async let w: [Worker] = API.shared.get("/api/workers")
        async let s: [Shop] = API.shared.get("/api/shops")
        var failure: Error?
        do { objects = try await o } catch { failure = error }
        do { workers = try await w } catch { failure = failure ?? error }
        do { shops = try await s } catch { failure = failure ?? error }
        dirLoading = false
        if let failure, !(failure is CancellationError) {
            dirError = failure.localizedDescription
        }
        dirLoaded = failure == nil || !(objects.isEmpty && workers.isEmpty && shops.isEmpty)
        if let t = type { autoselect(for: t) }
    }

    func id(_ f: EntryType.Field) -> Int? {
        switch f {
        case .object: return objectId
        case .worker: return workerId
        case .shop: return shopId
        }
    }

    func select(_ f: EntryType.Field, _ id: Int?) {
        switch f {
        case .object:
            objectId = id
            autoObject = false
        case .worker:
            workerId = id
        case .shop:
            shopId = id
        }
        errors[NewEntErr(f)] = nil
    }

    func name(_ f: EntryType.Field) -> String? {
        guard let id = id(f) else { return nil }
        let found: String?
        switch f {
        case .object: found = objects.first { $0.id == id }?.name
        case .worker: found = workers.first { $0.id == id }?.name
        case .shop: found = shops.first { $0.id == id }?.name
        }
        return found ?? (dirLoaded ? "№\(id)" : "Yuklanmoqda…")
    }

    /// Tanlash oynasidagi guruhlar: faollari tepada; nofaol usta/magazin — faqat tanlangan bo'lsa
    func groups(_ f: EntryType.Field) -> [NewEntGroup] {
        switch f {
        case .object:
            let active = objects.filter { $0.statusValue == .faol }.map { objectItem($0) }
            let other = objects.filter { $0.statusValue != .faol }.map { objectItem($0) }
            return [NewEntGroup(title: "Ish ketyapti", items: active),
                    NewEntGroup(title: "Tugagan va to‘xtatilgan", items: other)].filter { !$0.items.isEmpty }
        case .worker:
            let list = workers.filter { $0.active || $0.id == workerId }.map { w in
                NewEntItem(id: w.id, name: w.name, detail: joined([w.specialty, w.qarz > 0 ? "qarz \(Fmt.compact(w.qarz))" : nil]))
            }
            return list.isEmpty ? [] : [NewEntGroup(title: "Ustalar", items: list)]
        case .shop:
            let list = shops.filter { $0.active || $0.id == shopId }.map { s in
                NewEntItem(id: s.id, name: s.name, detail: joined([s.address, s.qarz > 0 ? "qarz \(Fmt.compact(s.qarz))" : nil]))
            }
            return list.isEmpty ? [] : [NewEntGroup(title: "Magazinlar", items: list)]
        }
    }

    private func objectItem(_ o: ObjectItem) -> NewEntItem {
        NewEntItem(id: o.id, name: o.name, detail: joined([o.address, o.statusValue == .faol ? nil : o.statusValue.label]))
    }

    private func joined(_ parts: [String?]) -> String? {
        let s = parts.compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        return s.isEmpty ? nil : s
    }

    /// Majburiy obyekt bo'sh bo'lsa: oxirgi ishlatilgan (hali faol bo'lsa) yoki yagona faol obyekt
    func autoselect(for t: EntryType) {
        guard t.isRequired(.object), objectId == nil, dirLoaded else { return }
        let active = objects.filter { $0.statusValue == .faol }
        let last = UserDefaults.standard.object(forKey: Self.lastObjectKey) as? Int
        if let last, active.contains(where: { $0.id == last }) {
            objectId = last
            autoObject = true
        } else if active.count == 1 {
            objectId = active[0].id
            autoObject = true
        }
    }

    // MARK: tekshiruv va saqlash

    func validate(_ t: EntryType) -> Bool {
        var e: [NewEntErr: String] = [:]
        let a = amount
        if a <= 0 { e[.amount] = amountText.isEmpty ? "Summani kiriting" : "Summa noto‘g‘ri" }
        for f in t.required where id(f) == nil {
            switch f {
            case .object: e[.object] = "Obyektni tanlang"
            case .worker: e[.worker] = "Ustani tanlang"
            case .shop: e[.shop] = "Magazinni tanlang"
            }
        }
        if t.hasPaidNow, !trim(paidText).isEmpty {
            if let p = Fmt.parseAmount(paidText) {
                if a > 0 && p > a { e[.paid] = "To‘langan qism summadan oshmasin" }
            } else {
                e[.paid] = "Summani to‘g‘ri yozing"
            }
        }
        errors = e
        return e.isEmpty
    }

    func body(for t: EntryType) -> NewEntryBody {
        let fields = t.fields
        var paid: Int?
        if t.hasPaidNow, let p = Fmt.parseAmount(paidText), p > 0 { paid = p }
        return NewEntryBody(type: t.rawValue, amount: amount, date: Fmt.apiDate(date),
                            title: trim(title), note: trim(note),
                            objectId: fields.contains(.object) ? objectId : nil,
                            workerId: fields.contains(.worker) ? workerId : nil,
                            shopId: fields.contains(.shop) ? shopId : nil,
                            paidNow: paid)
    }

    func rememberObject(for t: EntryType) {
        if t.fields.contains(.object), let objectId {
            UserDefaults.standard.set(objectId, forKey: Self.lastObjectKey)
        }
    }
}

// MARK: - 1-qadam: «Nima bo'ldi?»

private struct NewEntTypeGrid: View {
    let model: NewEntModel
    let current: EntryType?
    let pick: (EntryType) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let ctx = contextText {
                    Label(ctx, systemImage: "link")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Palette.brandSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                ForEach(0..<EntryType.groups.count, id: \.self) { gi in
                    NewEntTypeGroup(title: EntryType.groups[gi].title, types: EntryType.groups[gi].types,
                                    current: current, pick: pick)
                }
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Palette.bg)
    }

    /// Oldindan to'ldirilgan obyekt/usta/magazin nomlari
    private var contextText: String? {
        let p = model.prefill
        var parts: [String] = []
        if let id = p.objectId, let n = model.objects.first(where: { $0.id == id })?.name { parts.append(n) }
        if let id = p.workerId, let n = model.workers.first(where: { $0.id == id })?.name { parts.append(n) }
        if let id = p.shopId, let n = model.shops.first(where: { $0.id == id })?.name { parts.append(n) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct NewEntTypeGroup: View {
    let title: String
    let types: [EntryType]
    let current: EntryType?
    let pick: (EntryType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .padding(.leading, 4)
            ForEach(0..<((types.count + 1) / 2), id: \.self) { r in
                HStack(spacing: 10) {
                    NewEntTypeTile(type: types[r * 2], selected: types[r * 2] == current) { pick(types[r * 2]) }
                    if r * 2 + 1 < types.count {
                        NewEntTypeTile(type: types[r * 2 + 1], selected: types[r * 2 + 1] == current) { pick(types[r * 2 + 1]) }
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct NewEntTypeTile: View {
    let type: EntryType
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    TypeIcon(type: type, size: 36)
                    Text(type.short)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(type.hint)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Palette.brand : Palette.line, lineWidth: selected ? 2 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(type.label)
        .accessibilityHint(type.hint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - 2-qadam: forma

private enum NewEntFocus: Hashable {
    case amount, paid, title, note
}

private struct NewEntPickField: Identifiable {
    let field: EntryType.Field
    var id: String { "\(field)" }
}

private struct NewEntForm: View {
    let type: EntryType
    @Bindable var model: NewEntModel
    let changeType: () -> Void
    let cancel: () -> Void
    let close: () -> Void

    @Environment(Session.self) var session
    @FocusState var focus: NewEntFocus?
    @State var picking: NewEntPickField?
    @State var source: EntAttachSource?
    @State var scrollTick = 0

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                typeSection
                amountSection
                if !type.fields.isEmpty { fieldsSection }
                if type.hasPaidNow { paidSection }
                detailsSection
                receiptsSection
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollTick) { _, _ in
                guard let k = model.firstError else { return }
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(k, anchor: .center) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        .navigationTitle("Yangi yozuv")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Bekor qilish", action: cancel)
                    .disabled(model.saving)
            }
        }
        .sheet(item: $picking) { p in
            NewEntPicker(field: p.field, title: label(p.field), required: type.isRequired(p.field), model: model)
        }
        .modifier(EntAttachSources(source: $source, busy: $model.preparing,
                                   limit: EntPrep.maxFiles - model.attachments.count,
                                   onPicked: { add($0) },
                                   onError: { model.formError = $0 }))
        .onAppear {
            if model.type != type {
                model.type = type
                model.errors = [:]
                model.formError = nil
            }
            model.autoselect(for: type)
        }
        .task { await autofocus() }
    }

    /// Majburiy maydonlar tepada (masalan «Ustaga pul berildi» — avval usta, keyin obyekt)
    private var orderedFields: [EntryType.Field] {
        type.fields.filter { type.isRequired($0) } + type.fields.filter { !type.isRequired($0) }
    }

    private func label(_ f: EntryType.Field) -> String {
        f == .worker ? type.workerLabel : f.title
    }

    // MARK: bo'limlar

    private var typeSection: some View {
        Section {
            HStack(spacing: 12) {
                TypeIcon(type: type, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.label)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(type.hint)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button("O‘zgartirish", action: changeType)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .buttonStyle(.borderless)
                    .disabled(model.saving)
                    .accessibilityLabel("Amal turini o‘zgartirish")
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(Palette.surface)
    }

    private var amountSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                AmountField(title: "Summa", text: $model.amountText, large: true)
                    .focused($focus, equals: .amount)
                    .onChange(of: model.amountText) { _, _ in model.errors[.amount] = nil }
                if let e = model.errors[.amount] { NewEntErrorText(text: e) }
            }
            .padding(.vertical, 4)
            .id(NewEntErr.amount)
        }
        .listRowBackground(Palette.surface)
    }

    private var fieldsSection: some View {
        Section {
            ForEach(orderedFields, id: \.self) { f in
                NewEntFieldRow(symbol: f.symbol, label: label(f), required: type.isRequired(f), value: model.name(f),
                               note: f == .object && model.autoObject ? "Oxirgi tanlangan obyekt — kerak bo‘lsa o‘zgartiring" : nil,
                               error: model.errors[NewEntErr(f)]) {
                    focus = nil
                    picking = NewEntPickField(field: f)
                }
                .id(NewEntErr(f))
            }
        }
        .listRowBackground(Palette.surface)
    }

    private var paidSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                AmountField(title: "Shu zahoti to‘langan", text: $model.paidText)
                    .focused($focus, equals: .paid)
                    .onChange(of: model.paidText) { _, _ in model.errors[.paid] = nil }
                HStack(spacing: 10) {
                    Button {
                        model.paidText = model.amountText
                        model.errors[.paid] = nil
                    } label: {
                        Label("To‘liq to‘landi", systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Palette.green)
                    .disabled(model.amount <= 0)
                    Spacer(minLength: 4)
                    Text(paidStatus)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.trailing)
                }
                if let e = model.errors[.paid] { NewEntErrorText(text: e) }
            }
            .padding(.vertical, 4)
            .id(NewEntErr.paid)
        } footer: {
            Text("Bo‘sh qoldirilsa — nasiya: summa magazinga qarz bo‘lib yoziladi.")
        }
        .listRowBackground(Palette.surface)
    }

    private var paidStatus: String {
        let a = model.amount
        guard let p = Fmt.parseAmount(model.paidText), p > 0 else { return "Nasiya" }
        if a > 0 && p >= a { return "To‘liq to‘langan" }
        if a > p { return "Qarz: " + Fmt.som(a - p) }
        return ""
    }

    private var detailsSection: some View {
        Section {
            DatePicker("Sana", selection: $model.date, displayedComponents: .date)
                .environment(\.locale, EntText.uzLocale)
                .foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nima uchun").font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
                TextField(type.titlePlaceholder, text: $model.title)
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focus = .note }
            }
            .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Izoh").font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
                TextField("Qo‘shimcha ma’lumot", text: $model.note, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($focus, equals: .note)
            }
            .padding(.vertical, 2)
        } footer: {
            Text("Dollarda olingan bo‘lsa kursini yozing")
        }
        .listRowBackground(Palette.surface)
    }

    private var receiptsSection: some View {
        Section {
            if !model.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.attachments) { a in
                            NewEntThumb(item: a) {
                                model.attachments.removeAll { $0.id == a.id }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            if model.preparing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Rasm tayyorlanmoqda…").font(.subheadline).foregroundStyle(Palette.muted)
                }
            }
            EntAttachButtons(source: $source,
                             disabled: model.attachments.count >= EntPrep.maxFiles || model.preparing || model.saving)
                .padding(.vertical, 4)
        } header: {
            Text("Chek rasmlari")
        } footer: {
            Text(model.attachments.isEmpty ? "10 tagacha rasm yoki PDF — saqlanganda yuklanadi"
                                           : "\(model.attachments.count) ta fayl — saqlanganda yuklanadi")
        }
        .listRowBackground(Palette.surface)
    }

    private var saveBar: some View {
        VStack(spacing: 8) {
            if let e = model.formError {
                Text(e)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            BrandButton(title: model.saving ? "Saqlanmoqda…" : "Saqlash", symbol: "checkmark",
                        loading: model.saving, disabled: model.preparing) {
                save()
            }
            .accessibilityLabel("Yozuvni saqlash")
        }
        .padding(.horizontal, Metrics.pad)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [Palette.bg.opacity(0), Palette.bg, Palette.bg], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: amallar

    private func add(_ picked: [EntPicked]) {
        let room = max(0, EntPrep.maxFiles - model.attachments.count)
        model.attachments.append(contentsOf: picked.prefix(room))
        if picked.count > room { model.formError = "Bitta yozuvga 10 tagacha fayl qo‘shiladi" }
    }

    private func autofocus() async {
        guard session.shot == nil, model.amount == 0 else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled, picking == nil else { return }
        focus = .amount
    }

    private func save() {
        guard !model.saving else { return }
        focus = nil
        model.formError = nil
        guard model.validate(type) else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            scrollTick += 1
            return
        }
        model.saving = true
        Task { await submit() }
    }

    private func submit() async {
        defer { model.saving = false }
        do {
            let created: CreatedEntry = try await API.shared.post("/api/entries", body: model.body(for: type))
            model.rememberObject(for: type)
            if !model.attachments.isEmpty {
                do {
                    _ = try await API.shared.upload(entryId: created.id, files: model.attachments.map(\.file))
                } catch {
                    session.changed()
                    close()
                    session.show("Yozuv saqlandi, lekin chek yuklanmadi: \(error.localizedDescription)", error: true)
                    return
                }
            }
            session.changed()
            close()
            session.show("Saqlandi")
        } catch is CancellationError {
        } catch {
            model.formError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

private struct NewEntErrorText: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.red)
    }
}

/// Obyekt / usta / magazin maydoni (bosilsa — tanlash oynasi)
private struct NewEntFieldRow: View {
    let symbol: String
    let label: String
    let required: Bool
    let value: String?
    let note: String?
    let error: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(symbol: symbol, color: Palette.ink2, soft: Palette.surface2, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Text(label)
                        if required {
                            Text("*").foregroundStyle(Palette.red)
                        } else {
                            Text("(ixtiyoriy)")
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.muted)
                    Text(value ?? "Tanlang")
                        .font(.body.weight(value == nil ? .regular : .semibold))
                        .foregroundStyle(value == nil ? (required ? Palette.accent : Palette.muted) : Palette.ink)
                        .lineLimit(2)
                    if let note {
                        Text(note).font(.caption2).foregroundStyle(Palette.muted)
                    }
                    if let error {
                        NewEntErrorText(text: error)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label)\(required ? ", majburiy" : ", ixtiyoriy"): \(value ?? "tanlanmagan")")
    }
}

/// Tanlangan chek (kichik ko'rinish, olib tashlash tugmasi bilan)
private struct NewEntThumb: View {
    let item: EntPicked
    let remove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = item.thumb {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    VStack(spacing: 3) {
                        Image(systemName: "doc.richtext.fill").font(.title3).foregroundStyle(Palette.red)
                        Text("PDF").font(.caption2.weight(.bold)).foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.surface2)
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
            .padding(6)

            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.65))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isPDF ? "PDF ni olib tashlash" : "Rasmni olib tashlash")
        }
    }
}

// MARK: - Tanlash oynasi (qidiruvli)

private struct NewEntPicker: View {
    let field: EntryType.Field
    let title: String
    let required: Bool
    @Bindable var model: NewEntModel

    @Environment(\.dismiss) var dismiss
    @State var search = ""

    private var groups: [NewEntGroup] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = model.groups(field)
        guard !q.isEmpty else { return all }
        return all.map { g in
            NewEntGroup(title: g.title, items: g.items.filter {
                $0.name.localizedCaseInsensitiveContains(q) || ($0.detail ?? "").localizedCaseInsensitiveContains(q)
            })
        }
        .filter { !$0.items.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                content
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Qidirish")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Yopish") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var content: some View {
        let list = groups
        if !required && search.isEmpty {
            Section {
                row(nil, name: "Tanlanmagan", detail: nil)
            }
            .listRowBackground(Palette.surface)
        }
        if list.isEmpty {
            if model.dirLoading {
                Section { LoadingState() }.listRowBackground(Color.clear)
            } else if let e = model.dirError, model.groups(field).isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Yuklab bo‘lmadi", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(e)
                    } actions: {
                        Button("Qayta urinish") { Task { await model.loadDirectory() } }.buttonStyle(.bordered)
                    }
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ContentUnavailableView(search.isEmpty ? "Ro‘yxat bo‘sh" : "Topilmadi",
                                           systemImage: field.symbol,
                                           description: Text(search.isEmpty ? "Avval saytda yoki «\(field.title)» bo‘limida qo‘shing"
                                                                            : "Boshqa so‘z bilan qidirib ko‘ring"))
                }
                .listRowBackground(Color.clear)
            }
        } else {
            ForEach(list) { g in
                Section {
                    ForEach(g.items) { item in
                        row(item.id, name: item.name, detail: item.detail)
                    }
                } header: {
                    Text(g.title)
                }
                .listRowBackground(Palette.surface)
            }
        }
    }

    private func row(_ id: Int?, name: String, detail: String?) -> some View {
        let selected = model.id(field) == id
        return Button {
            model.select(field, id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                if id == nil {
                    IconBadge(symbol: "minus", color: Palette.muted, soft: Palette.surface2, size: 34)
                } else if field == .worker {
                    Avatar(name: name, size: 34)
                } else {
                    IconBadge(symbol: field.symbol, color: field == .shop ? Palette.blue : Palette.ink2,
                              soft: field == .shop ? Palette.blueSoft : Palette.surface2, size: 34)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(id == nil ? Palette.muted : Palette.ink)
                        .lineLimit(2)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
