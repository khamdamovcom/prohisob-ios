// Ustalar ro'yxati (pastki menyu bo'limi): tepada hamma ustalarga jami qarz, segment (Hammasi / Qarzdorlar / Faol emas),
// qidiruv, qatorlar — ism, kasbi, qarz. GET /api/workers. Usta sahifasi — WorkerDetailView.swift, forma — WorkerForm.swift.
import SwiftUI

private enum WrkSegment: String, CaseIterable, Identifiable {
    case hammasi, qarzdor, faolEmas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hammasi: return "Hammasi"
        case .qarzdor: return "Qarzdorlar"
        case .faolEmas: return "Faol emas"
        }
    }
}

struct WorkersView: View {
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @State private var items: [Worker]?
    @State private var error: Error?
    @State private var segment: WrkSegment = .hammasi
    @State private var query = ""
    @State private var showNew = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bg)
            .navigationTitle("Ustalar")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Ism, kasbi yoki telefon")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Yangi usta")
                }
            }
            .task(id: session.dataVersion) { await load() }
            .sheet(isPresented: $showNew) {
                WrkForm(item: nil) { newId in
                    if let newId { router.push(.worker(newId)) }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let items {
            list(items)
        } else if let error {
            ErrorState(error: error) { await load() }
        } else {
            LoadingState()
        }
    }

    private func list(_ all: [Worker]) -> some View {
        let shown = filtered(all)
        return List {
            Section {
                WrkTotalCard(workers: all)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                Picker("Ko‘rinish", selection: $segment) {
                    ForEach(WrkSegment.allCases) { s in Text(s.title).tag(s) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 14, leading: 0, bottom: 2, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if shown.isEmpty {
                Section {
                    empty(all)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(shown) { w in
                        NavigationLink(value: Route.worker(w.id)) {
                            WrkRow(worker: w)
                        }
                        .listRowBackground(Palette.surface)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { router.addEntry(EntryPrefill(type: .ustaTolov, workerId: w.id)) } label: {
                                Label("Pul berish", systemImage: EntryType.ustaTolov.symbol)
                            }
                            .tint(Palette.green)
                        }
                        .contextMenu {
                            Button { router.addEntry(EntryPrefill(type: .ustaTolov, workerId: w.id)) } label: {
                                Label("Pul berish", systemImage: EntryType.ustaTolov.symbol)
                            }
                            Button { router.addEntry(EntryPrefill(type: .ustaHaqi, workerId: w.id)) } label: {
                                Label("Haq yozish", systemImage: EntryType.ustaHaqi.symbol)
                            }
                            Button { router.addEntry(EntryPrefill(type: .ustaXarid, workerId: w.id)) } label: {
                                Label("O‘z puliga mol", systemImage: EntryType.ustaXarid.symbol)
                            }
                        }
                    }
                } footer: {
                    Text(footer(shown))
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

    @ViewBuilder
    private func empty(_ all: [Worker]) -> some View {
        if all.isEmpty {
            EmptyState(symbol: "person.2", title: "Hali usta yo‘q",
                       message: "Ustani qo‘shing — haqi, berilgan pul va qarzi shu yerda hisoblanadi.",
                       actionTitle: "Usta qo‘shish") { showNew = true }
        } else if !ObjText.trim(query).isEmpty {
            EmptyState(symbol: "magnifyingglass", title: "Topilmadi", message: "«\(ObjText.trim(query))» bo‘yicha usta yo‘q.")
        } else if segment == .qarzdor {
            EmptyState(symbol: "checkmark.circle", title: "Qarz yo‘q", message: "Hamma ustalar bilan hisob teng.")
        } else {
            EmptyState(symbol: "person.2.slash", title: "Faol bo‘lmagan usta yo‘q")
        }
    }

    private func footer(_ shown: [Worker]) -> String {
        let n = shown.count
        let sum = shown.reduce(0) { $0 + max(0, $1.qarz) }
        switch segment {
        case .qarzdor: return "\(n) ta ustaga qarzmiz — jami " + Fmt.som(sum)
        case .faolEmas: return "\(n) ta usta faol emas"
        case .hammasi: return "\(n) ta usta"
        }
    }

    private func filtered(_ all: [Worker]) -> [Worker] {
        let found = all.filter { ObjText.matches(query, [$0.name, $0.specialty, $0.phone]) }
        switch segment {
        case .hammasi:
            return found.filter(\.active) + found.filter { !$0.active }
        case .qarzdor:
            return found.filter { $0.qarz > 0 }.sorted { $0.qarz > $1.qarz }
        case .faolEmas:
            return found.filter { !$0.active }
        }
    }

    private func load() async {
        do {
            let list: [Worker] = try await API.shared.get("/api/workers")
            items = list
            error = nil
        } catch is CancellationError {
        } catch {
            if items == nil { self.error = error } else { session.show(error.localizedDescription, error: true) }
        }
    }
}

// MARK: - Jami qarz

private struct WrkTotalCard: View {
    let workers: [Worker]

    private var total: Int { workers.reduce(0) { $0 + max(0, $1.qarz) } }
    private var debtors: Int { workers.filter { $0.qarz > 0 }.count }

    var body: some View {
        ObjTotalCard(title: "Ustalarga jami qarz", amount: total,
                     caption: debtors > 0 ? "\(debtors) ta ustaga qarzmiz · jami \(workers.count) ta usta"
                                          : "Hamma ustalar bilan hisob teng",
                     symbol: "person.2.fill")
    }
}

// MARK: - Qator

private struct WrkRow: View {
    let worker: Worker

    private var subtitle: String {
        var p: [String] = []
        if let s = ObjText.value(worker.specialty) { p.append(s) }
        if worker.obyektlar > 0 { p.append("\(worker.obyektlar) ta obyekt") }
        return p.isEmpty ? (ObjText.value(worker.phone) ?? "Kasbi yozilmagan") : p.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: worker.name, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(worker.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if !worker.active { ObjTag(text: "faol emas") }
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ObjDebtText(amount: worker.qarz)
        }
        .padding(.vertical, 3)
        .opacity(worker.active ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }
}
