// Yozuvlar ro'yxati: pastki menyudagi «Yozuvlar» bo'limi (filtr bo'sh) yoki obyekt/usta/magazin sahifasidan ochilgan
// filtrlangan ro'yxat. Qidiruv, tur va davr chiplari, obyekt filtri, 50 talab sahifalab yuklash, kun bo'yicha guruh
// (kunlik kirim/chiqim), jami (faqat aniq bo'lsa), swipe → o'chirish, Excel (joriy filtr bilan).
// Yozuv sahifasi — EntryDetailView.swift, «Yangi yozuv» — NewEntryView.swift.
import SwiftUI
import UIKit

struct EntriesView: View {
    let filter: EntryFilter

    init(filter: EntryFilter = EntryFilter()) {
        self.filter = filter
    }

    @Environment(Session.self) private var session
    @Environment(Router.self) private var router

    /// Bir sahifa
    private static let pageSize = 50
    /// Jami shuncha yoki kamroq bo'lsa — qolgani ham yuklanadi (jami kirim/chiqim aniq bo'lishi uchun)
    private static let loadAllUpTo = 500

    // foydalanuvchi tanlovi
    @State private var type: EntryType?
    @State private var period: EntPeriod = .all
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var customTo = Date()
    @State private var objectId: Int?
    @State private var search = ""
    @State private var q = ""

    // ma'lumot
    @State private var rows: [Entry] = []
    @State private var total = 0
    /// Ekrandagi yozuvlar qaysi filtr bo'yicha yuklangan (nil — hali yuklanmagan)
    @State private var loadedFor: EntryFilter?
    @State private var error: Error?
    @State private var loadingMore = false
    @State private var moreFailed = false
    @State private var generation = 0
    @State private var objects: [ObjectItem] = []

    // oynalar
    @State private var customSheet = false
    @State private var pendingDelete: Entry?
    @State private var exporting = false
    @State private var exportFile: EntExportFile?

    // MARK: - Filtr

    private var isRoot: Bool { filter.isEmpty }
    private var typeLocked: Bool { filter.type != nil }
    private var periodLocked: Bool { filter.from != nil || filter.to != nil }

    /// Joriy so'rov filtri: berilgan (qat'iy) filtr + foydalanuvchi tanlovi
    private var effective: EntryFilter {
        var f = filter
        if !typeLocked { f.type = type }
        if !periodLocked {
            let r = period.range(from: customFrom, to: customTo)
            f.from = r.from
            f.to = r.to
        }
        if isRoot { f.objectId = objectId }
        if (filter.q ?? "").isEmpty { f.q = q.isEmpty ? nil : q }
        return f
    }

    private var isStale: Bool { loadedFor != effective }

    private var prefill: EntryPrefill {
        let f = effective
        return EntryPrefill(type: f.type, objectId: f.objectId, workerId: f.workerId, shopId: f.shopId)
    }

    // MARK: - Ekran

    var body: some View {
        List {
            summarySection
            listContent
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .modifier(EntTopBar(bar: chipsBar))
        .navigationTitle(isRoot ? "Yozuvlar" : (filter.title ?? "Yozuvlar"))
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .searchable(text: $search, prompt: "Nima uchun yoki izoh bo‘yicha")
        .toolbar { toolbarItems }
        .task(id: EntLoadKey(filter: effective, version: session.dataVersion)) { await load() }
        .task(id: search) { await debounceSearch() }
        .task(id: session.dataVersion) { await loadObjects() }
        .refreshable { await load() }
        .alert("Yozuvni o‘chirasizmi?", isPresented: deleteAlert, presenting: pendingDelete) { e in
            Button("O‘chirish", role: .destructive) { Task { await delete(e) } }
            Button("Bekor qilish", role: .cancel) {}
        } message: { e in
            Text(EntText.deleteMessage(kind: e.kind, title: e.headline, amount: e.amount))
        }
        .sheet(isPresented: $customSheet) {
            EntPeriodSheet(from: customFrom, to: customTo) { a, b in
                customFrom = a
                customTo = b
                period = .custom
            }
        }
        .sheet(item: $exportFile) { f in
            EntShareSheet(url: f.url).ignoresSafeArea()
        }
    }

    private var deleteAlert: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if exporting {
                ProgressView()
            } else {
                Button {
                    Task { await export() }
                } label: {
                    Label("Excel", systemImage: "square.and.arrow.up")
                }
                .disabled(loadedFor == nil || rows.isEmpty)
                .accessibilityLabel("Excel faylini ulashish")
            }
        }
        if !isRoot {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.addEntry(prefill)
                } label: {
                    Label("Yangi yozuv", systemImage: "plus")
                }
            }
        }
    }

    // MARK: Chiplar (davr, obyekt, tur)

    private var chipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !periodLocked { periodMenu }
                if isRoot { objectMenu }
                if !typeLocked {
                    if !periodLocked || isRoot {
                        Rectangle().fill(Palette.line).frame(width: 1, height: 22)
                    }
                    typeChips
                }
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.vertical, 8)
        }
    }

    private var periodMenu: some View {
        Menu {
            Picker("Davr", selection: $period) {
                ForEach(EntPeriod.allCases.filter { $0 != .custom }) { p in
                    Text(p.title).tag(p)
                }
            }
            Button {
                customSheet = true
            } label: {
                Label(period == .custom ? "Boshqa: \(customLabel)" : "Boshqa davr…", systemImage: "calendar.badge.clock")
            }
        } label: {
            EntMenuChip(title: periodLabel, symbol: "calendar", active: period != .all)
        }
        .accessibilityLabel("Davr: \(period == .all ? "hammasi" : periodLabel)")
    }

    private var periodLabel: String {
        switch period {
        case .all: return "Davr"
        case .custom: return customLabel
        default: return period.title
        }
    }

    private var customLabel: String {
        "\(Fmt.day(min(customFrom, customTo))) – \(Fmt.day(max(customFrom, customTo)))"
    }

    private var objectMenu: some View {
        Menu {
            Picker("Obyekt", selection: $objectId) {
                Text("Hamma obyektlar").tag(Int?.none)
                ForEach(sortedObjects) { o in
                    Text(o.statusValue == .faol ? o.name : o.name + " · " + o.statusValue.label).tag(Int?.some(o.id))
                }
            }
        } label: {
            EntMenuChip(title: selectedObjectName ?? "Obyekt", symbol: "building.2", active: objectId != nil)
        }
        .accessibilityLabel("Obyekt: \(selectedObjectName ?? "hammasi")")
    }

    /// Faol obyektlar — tepada
    private var sortedObjects: [ObjectItem] {
        objects.filter { $0.statusValue == .faol } + objects.filter { $0.statusValue != .faol }
    }

    private var selectedObjectName: String? {
        guard let objectId else { return nil }
        return objects.first { $0.id == objectId }?.name ?? "Obyekt"
    }

    @ViewBuilder
    private var typeChips: some View {
        Chip(title: "Hammasi", selected: type == nil) { type = nil }
        ForEach(EntryType.allCases) { t in
            Chip(title: t.short, symbol: t.symbol, selected: type == t) {
                type = type == t ? nil : t
            }
        }
    }

    // MARK: Jami

    @ViewBuilder
    private var summarySection: some View {
        if loadedFor != nil && !(rows.isEmpty && !isStale) {
            Section {
                EntSummary(total: total, sums: isStale ? nil : exactSums, busy: isStale,
                           hint: !isStale && exactSums == nil ? "Jami summa — davrni toraytirsangiz yoki hammasini ko‘rsangiz chiqadi" : nil)
            }
            .listRowBackground(Palette.surface)
        }
    }

    /// Faqat hamma yozuv yuklangan bo'lsa — aniq yig'indi
    private var exactSums: EntSums? {
        rows.count >= total ? EntSums(rows) : nil
    }

    // MARK: Ro'yxat

    @ViewBuilder
    private var listContent: some View {
        if loadedFor == nil {
            if let error {
                Section {
                    ErrorState(error: error) { await load() }
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    LoadingState()
                }
                .listRowBackground(Color.clear)
            }
        } else if rows.isEmpty {
            Section {
                if isStale {
                    LoadingState()
                } else {
                    emptyState
                }
            }
            .listRowBackground(Color.clear)
        } else {
            daySections
            pager
        }
    }

    private var emptyState: some View {
        let filtered = !effective.isEmpty
        return EmptyState(symbol: "tray", title: "Yozuv yo‘q",
                          message: filtered ? "Tanlangan filtr bo‘yicha yozuv topilmadi" : "Birinchi kirim yoki xarajatni yozing",
                          actionTitle: "Yangi yozuv") {
            router.addEntry(prefill)
        }
    }

    @ViewBuilder
    private var daySections: some View {
        let groups = EntDay.group(rows)
        let complete = rows.count >= total
        ForEach(Array(groups.enumerated()), id: \.element.id) { i, day in
            Section {
                ForEach(day.rows) { e in
                    row(e)
                }
            } header: {
                EntDayHeader(date: day.date, sums: complete || i < groups.count - 1 ? EntSums(day.rows) : nil)
            }
        }
    }

    private func row(_ e: Entry) -> some View {
        NavigationLink(value: Route.entry(e.id)) {
            EntryRow(entry: e)
                .opacity(isStale ? 0.45 : 1)
        }
        .listRowBackground(Palette.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if session.canDelete(createdBy: e.createdBy) {
                Button {
                    pendingDelete = e
                } label: {
                    Label("O‘chirish", systemImage: "trash")
                }
                .tint(Palette.red)
            }
        }
    }

    @ViewBuilder
    private var pager: some View {
        if !isStale && rows.count < total {
            Section {
                HStack {
                    Spacer()
                    if moreFailed && !loadingMore {
                        Button("Yana yuklash") { Task { await loadMore(auto: false) } }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                    } else {
                        ProgressView()
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .task(id: rows.count) { await loadMore() }
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Yuklash

    private static func query(_ f: EntryFilter, limit: Int, offset: Int) -> [String: String?] {
        var q = f.query
        q["limit"] = String(limit)
        q["offset"] = String(offset)
        return q
    }

    private func load() async {
        let f = effective
        let refreshing = loadedFor == f
        if loadedFor == nil { error = nil }
        generation += 1
        let gen = generation
        // yangilashda — ko'rilgan chuqurlik saqlanadi
        let limit = refreshing ? min(2000, max(Self.pageSize, rows.count)) : Self.pageSize
        do {
            let page: EntriesPage = try await API.shared.get("/api/entries", query: Self.query(f, limit: limit, offset: 0))
            guard gen == generation else { return }
            rows = page.rows
            total = max(page.total, page.rows.count)
            loadedFor = f
            error = nil
            moreFailed = false
            if total > rows.count && total <= Self.loadAllUpTo {
                await loadMore()
            }
        } catch is CancellationError {
        } catch {
            guard gen == generation else { return }
            if refreshing {
                session.show(error.localizedDescription, error: true)
            } else {
                rows = []
                total = 0
                loadedFor = nil
                self.error = error
            }
        }
    }

    private func loadMore(auto: Bool = true) async {
        guard !loadingMore, let f = loadedFor, f == effective, rows.count < total else { return }
        if auto && moreFailed { return }
        loadingMore = true
        moreFailed = false
        defer { loadingMore = false }
        let gen = generation
        let limit = total <= Self.loadAllUpTo ? total - rows.count : Self.pageSize
        do {
            let page: EntriesPage = try await API.shared.get("/api/entries",
                                                             query: Self.query(f, limit: min(2000, limit), offset: rows.count))
            guard gen == generation else { return }
            let have = Set(rows.map(\.id))
            rows.append(contentsOf: page.rows.filter { !have.contains($0.id) })
            total = page.rows.isEmpty ? rows.count : max(page.total, rows.count)
        } catch is CancellationError {
        } catch {
            guard gen == generation else { return }
            moreFailed = true
            if !auto { session.show(error.localizedDescription, error: true) }
        }
    }

    private func debounceSearch() async {
        let s = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s != q else { return }
        if !s.isEmpty { try? await Task.sleep(for: .milliseconds(450)) }
        guard !Task.isCancelled else { return }
        q = s
    }

    private func loadObjects() async {
        guard isRoot else { return }
        if let list: [ObjectItem] = try? await API.shared.get("/api/objects") {
            objects = list
        }
    }

    // MARK: - Amallar

    private func delete(_ e: Entry) async {
        do {
            try await API.shared.delete("/api/entries/\(e.id)")
            rows.removeAll { $0.id == e.id }
            total = max(0, total - 1)
            session.changed()
            session.show("O‘chirildi")
        } catch {
            session.show(error.localizedDescription, error: true)
        }
    }

    private func export() async {
        exporting = true
        defer { exporting = false }
        do {
            let url = try await API.shared.download("/api/export.xlsx", query: effective.query,
                                                    filename: "Prohisob-yozuvlar-\(Fmt.apiDate(Date())).xlsx")
            exportFile = EntExportFile(url: url)
        } catch is CancellationError {
        } catch {
            session.show(error.localizedDescription, error: true)
        }
    }
}

// MARK: - Yordamchilar

private struct EntLoadKey: Hashable {
    let filter: EntryFilter
    let version: Int
}

/// Bir kunning yozuvlari (server sanasi bo'yicha kamayish tartibida beradi)
private struct EntDay: Identifiable {
    let id: String
    let date: String
    var rows: [Entry]

    static func group(_ rows: [Entry]) -> [EntDay] {
        var out: [EntDay] = []
        for e in rows {
            if let last = out.last, last.date == e.date {
                out[out.count - 1].rows.append(e)
            } else {
                out.append(EntDay(id: "\(e.date)#\(out.count)", date: e.date, rows: [e]))
            }
        }
        return out
    }
}

/// Kun sarlavhasi: «Bugun» / «17-oktabr, juma» + o'sha kunning kirim/chiqimi (kun to'liq yuklangan bo'lsa)
private struct EntDayHeader: View {
    let date: String
    let sums: EntSums?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Fmt.dayHeader(date))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink2)
            Spacer(minLength: 4)
            if let s = sums {
                HStack(spacing: 8) {
                    if s.kirim > 0 {
                        Text("+" + Fmt.money(s.kirim)).foregroundStyle(Palette.green)
                    }
                    if s.chiqim > 0 {
                        Text("−" + Fmt.money(s.chiqim)).foregroundStyle(Palette.muted)
                    }
                }
                .font(.money(12, .semibold))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(dayLabel(s))
            }
        }
        .lineLimit(1)
        .textCase(nil)
    }

    private func dayLabel(_ s: EntSums) -> String {
        var parts: [String] = []
        if s.kirim > 0 { parts.append("kirim \(Fmt.som(s.kirim))") }
        if s.chiqim > 0 { parts.append("chiqim \(Fmt.som(s.chiqim))") }
        return parts.joined(separator: ", ")
    }
}

/// Tepadagi jami: «N ta yozuv» + kirim / chiqim / qarzga yozilgan (faqat aniq bo'lsa)
private struct EntSummary: View {
    let total: Int
    let sums: EntSums?
    let busy: Bool
    let hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(busy ? "Yuklanmoqda…" : "\(total) ta yozuv")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }
            if let s = sums {
                HStack(spacing: 8) {
                    EntSumCell(title: "Kirim", text: s.kirim > 0 ? "+" + Fmt.money(s.kirim) : "0", color: Palette.green)
                    EntSumCell(title: "Chiqim", text: s.chiqim > 0 ? "−" + Fmt.money(s.chiqim) : "0", color: Palette.ink)
                    if s.hisoblangan > 0 {
                        EntSumCell(title: "Qarzga", text: Fmt.money(s.hisoblangan), color: Palette.purple)
                    }
                }
            } else if let hint {
                Text(hint).font(.caption).foregroundStyle(Palette.muted)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct EntSumCell: View {
    let title: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
            Text(text)
                .font(.money(15, .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Menyu ochadigan chip (Chip bilan bir xil ko'rinish, ▾ belgisi bilan)
private struct EntMenuChip: View {
    let title: String
    let symbol: String
    let active: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption.weight(.semibold))
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(active ? Palette.onBrand : Palette.ink2)
        .background(active ? Palette.brand : Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(active ? Color.clear : Palette.line, lineWidth: 0.5))
        .frame(maxWidth: 230)
        .contentShape(Capsule())
    }
}

/// Chiplar paneli ro'yxat tepasida turadi (safeAreaBar katta sarlavhani xiralashtirgani uchun — safeAreaInset)
private struct EntTopBar<Bar: View>: ViewModifier {
    let bar: Bar

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            bar.background(Palette.bg)
        }
    }
}

/// «Boshqa davr»: ikki sana
private struct EntPeriodSheet: View {
    @State var from: Date
    @State var to: Date
    let apply: (Date, Date) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Boshlanish", selection: $from, displayedComponents: .date)
                DatePicker("Tugash", selection: $to, in: from..., displayedComponents: .date)
            }
            .environment(\.locale, EntText.uzLocale)
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .navigationTitle("Davr")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Bekor qilish") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Qo‘llash") {
                        apply(from, max(from, to))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct EntExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Tizim ulashish oynasi (Excel fayl)
private struct EntShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
