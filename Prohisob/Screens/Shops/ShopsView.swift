// Magazinlar ro'yxati (Route.shops — «Yana» va Asosiy'dan ochiladi): jami qarz, qidiruv, segment (Hammasi / Qarzdorlar),
// qatorlar — nomi, manzil, qarz. GET /api/shops. Magazin sahifasi — ShopDetailView.swift, forma — ShopForm.swift.
import SwiftUI

private enum ShpSegment: String, CaseIterable, Identifiable {
    case hammasi, qarzdor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hammasi: return "Hammasi"
        case .qarzdor: return "Qarzdorlar"
        }
    }
}

struct ShopsView: View {
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @State private var items: [Shop]?
    @State private var error: Error?
    @State private var segment: ShpSegment = .hammasi
    @State private var query = ""
    @State private var showNew = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bg)
            .navigationTitle("Magazinlar")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Nomi, manzil yoki telefon")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Yangi magazin")
                }
            }
            .task(id: session.dataVersion) { await load() }
            .sheet(isPresented: $showNew) {
                ShpForm(item: nil) { newId in
                    if let newId { router.push(.shop(newId)) }
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

    private func list(_ all: [Shop]) -> some View {
        let shown = filtered(all)
        return List {
            Section {
                ShpTotalCard(shops: all)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                Picker("Ko‘rinish", selection: $segment) {
                    ForEach(ShpSegment.allCases) { s in Text(s.title).tag(s) }
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
                    ForEach(shown) { m in
                        NavigationLink(value: Route.shop(m.id)) {
                            ShpRow(shop: m)
                        }
                        .listRowBackground(Palette.surface)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { router.addEntry(EntryPrefill(type: .magazinTolov, shopId: m.id)) } label: {
                                Label("To‘lov", systemImage: EntryType.magazinTolov.symbol)
                            }
                            .tint(Palette.blue)
                        }
                        .contextMenu {
                            Button { router.addEntry(EntryPrefill(type: .magazinTolov, shopId: m.id)) } label: {
                                Label("To‘lov qilish", systemImage: EntryType.magazinTolov.symbol)
                            }
                            Button { router.addEntry(EntryPrefill(type: .xarid, shopId: m.id)) } label: {
                                Label("Mol olish", systemImage: EntryType.xarid.symbol)
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
    private func empty(_ all: [Shop]) -> some View {
        if all.isEmpty {
            EmptyState(symbol: "storefront", title: "Hali magazin yo‘q",
                       message: "Mol oladigan magazinlarni qo‘shing — olingan mol, to‘lov va qarz shu yerda hisoblanadi.",
                       actionTitle: "Magazin qo‘shish") { showNew = true }
        } else if !ObjText.trim(query).isEmpty {
            EmptyState(symbol: "magnifyingglass", title: "Topilmadi", message: "«\(ObjText.trim(query))» bo‘yicha magazin yo‘q.")
        } else {
            EmptyState(symbol: "checkmark.circle", title: "Qarz yo‘q", message: "Hamma magazinlar bilan hisob teng.")
        }
    }

    private func footer(_ shown: [Shop]) -> String {
        let sum = shown.reduce(0) { $0 + max(0, $1.qarz) }
        switch segment {
        case .qarzdor: return "\(shown.count) ta magazinga qarzmiz — jami " + Fmt.som(sum)
        case .hammasi: return "\(shown.count) ta magazin"
        }
    }

    private func filtered(_ all: [Shop]) -> [Shop] {
        let found = all.filter { ObjText.matches(query, [$0.name, $0.address, $0.phone]) }
        switch segment {
        case .hammasi:
            return found.filter(\.active) + found.filter { !$0.active }
        case .qarzdor:
            return found.filter { $0.qarz > 0 }.sorted { $0.qarz > $1.qarz }
        }
    }

    private func load() async {
        do {
            let list: [Shop] = try await API.shared.get("/api/shops")
            items = list
            error = nil
            if ObjDebug.on, !ObjDebug.pushedShop, let f = list.first(where: { $0.qarz > 0 }) {
                ObjDebug.pushedShop = true
                router.push(.shop(f.id))
            }
        } catch is CancellationError {
        } catch {
            if items == nil { self.error = error } else { session.show(error.localizedDescription, error: true) }
        }
    }
}

// MARK: - Jami qarz

private struct ShpTotalCard: View {
    let shops: [Shop]

    private var total: Int { shops.reduce(0) { $0 + max(0, $1.qarz) } }
    private var debtors: Int { shops.filter { $0.qarz > 0 }.count }

    var body: some View {
        ObjTotalCard(title: "Magazinlarga jami qarz", amount: total,
                     caption: debtors > 0 ? "\(debtors) ta magazinga qarzmiz · jami \(shops.count) ta magazin"
                                          : "Hamma magazinlar bilan hisob teng",
                     symbol: "storefront.fill")
    }
}

// MARK: - Qator

private struct ShpRow: View {
    let shop: Shop

    private var subtitle: String {
        ObjText.value(shop.address) ?? ObjText.value(shop.phone) ?? ("Olingan mol: " + Fmt.compact(shop.olingan))
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "storefront.fill", color: Palette.blue, soft: Palette.blueSoft, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(shop.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if !shop.active { ObjTag(text: "faol emas") }
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ObjDebtText(amount: shop.qarz, negativeLabel: "ortiqcha")
        }
        .padding(.vertical, 3)
        .opacity(shop.active ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }
}
