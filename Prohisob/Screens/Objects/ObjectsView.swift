// Obyektlar ro'yxati (pastki menyu bo'limi): holat bo'yicha segment, qidiruv (nomi, manzil, uy egasi), kartalar —
// kirim / jami xarajat (real) / qo'ldagi pul, shartnomadan olingan qism, tugaganda sof foyda. GET /api/objects.
// Obyekt sahifasi — ObjectDetailView.swift, forma — ObjectForm.swift, umumiy qismlar — ObjKit.swift.
import SwiftUI

private enum ObjSegment: String, CaseIterable, Identifiable {
    case faol, tugagan, toxtatilgan, hammasi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .faol: return "Ish ketyapti"
        case .tugagan: return "Tugagan"
        case .toxtatilgan: return "To‘xtatilgan"
        case .hammasi: return "Hammasi"
        }
    }

    func includes(_ o: ObjectItem) -> Bool {
        switch self {
        case .hammasi: return true
        case .faol: return o.statusValue == .faol
        case .tugagan: return o.statusValue == .tugagan
        case .toxtatilgan: return o.statusValue == .toxtatilgan
        }
    }
}

struct ObjectsView: View {
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @State private var items: [ObjectItem]?
    @State private var error: Error?
    @State private var segment: ObjSegment = .faol
    @State private var query = ""
    @State private var showNew = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bg)
            .navigationTitle("Obyektlar")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Nomi, manzil yoki uy egasi")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Yangi obyekt")
                }
            }
            .task(id: session.dataVersion) { await load() }
            .sheet(isPresented: $showNew) {
                ObjForm(item: nil) { newId in
                    if let newId { router.push(.object(newId)) }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let items {
            ScrollView {
                LazyVStack(spacing: 12) {
                    Picker("Holat", selection: $segment) {
                        ForEach(ObjSegment.allCases) { s in Text(s.title).tag(s) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 2)
                    list(items)
                }
                .padding(.horizontal, Metrics.pad)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .refreshable { await load() }
        } else if let error {
            ErrorState(error: error) { await load() }
        } else {
            LoadingState()
        }
    }

    @ViewBuilder
    private func list(_ all: [ObjectItem]) -> some View {
        let shown = filtered(all)
        if all.isEmpty {
            EmptyState(symbol: "building.2", title: "Hali obyekt yo‘q",
                       message: "Birinchi obyektni qo‘shing — kirim, xarajat va qarzlar shu yerda hisoblanadi.",
                       actionTitle: "Obyekt qo‘shish") { showNew = true }
                .padding(.top, 40)
        } else if shown.isEmpty {
            emptyFiltered(all)
        } else {
            ForEach(shown) { o in
                NavigationLink(value: Route.object(o.id)) {
                    ObjCard(item: o)
                }
                .buttonStyle(PressableStyle())
                .contextMenu { quickMenu(o.id) }
            }
        }
    }

    @ViewBuilder
    private func emptyFiltered(_ all: [ObjectItem]) -> some View {
        let q = ObjText.trim(query)
        let elsewhere = all.filter { ObjText.matches(q, [$0.name, $0.address, $0.ownerName, $0.ownerPhone]) }.count
        if !q.isEmpty {
            EmptyState(symbol: "magnifyingglass", title: "Topilmadi",
                       message: elsewhere > 0 && segment != .hammasi ? "Boshqa bo‘limlarda \(elsewhere) ta obyekt topildi." : "«\(q)» bo‘yicha obyekt yo‘q.",
                       actionTitle: elsewhere > 0 && segment != .hammasi ? "Hammasini ko‘rish" : nil) { segment = .hammasi }
                .padding(.top, 30)
        } else {
            EmptyState(symbol: "building.2", title: "Bu bo‘limda obyekt yo‘q",
                       message: segment == .faol ? "Hozir ish ketayotgan obyekt yo‘q. Yangi obyekt qo‘shing yoki boshqa bo‘limni ko‘ring." : nil,
                       actionTitle: segment == .faol ? "Obyekt qo‘shish" : "Hammasini ko‘rish") {
                if segment == .faol { showNew = true } else { segment = .hammasi }
            }
            .padding(.top, 30)
        }
    }

    @ViewBuilder
    private func quickMenu(_ id: Int) -> some View {
        Section("Yozuv qo‘shish") {
            ForEach([EntryType.kirim, .ustaTolov, .xarid, .obyektXarajat], id: \.self) { t in
                Button { router.addEntry(EntryPrefill(type: t, objectId: id)) } label: { Label(t.short, systemImage: t.symbol) }
            }
        }
    }

    private func filtered(_ all: [ObjectItem]) -> [ObjectItem] {
        all.filter { segment.includes($0) && ObjText.matches(query, [$0.name, $0.address, $0.ownerName, $0.ownerPhone]) }
    }

    private func load() async {
        do {
            let list: [ObjectItem] = try await API.shared.get("/api/objects")
            items = list
            error = nil
        } catch is CancellationError {
        } catch {
            if items == nil { self.error = error } else { session.show(error.localizedDescription, error: true) }
        }
    }
}

// MARK: - Obyekt kartasi

private struct ObjCard: View {
    let item: ObjectItem

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                ObjCardHeader(item: item)
                ObjCardMetrics(item: item)
                if item.contractAmount > 0 { ObjCardContract(item: item) }
                if let f = item.foydaKorinadi { ObjCardProfit(amount: f) }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Obyekt sahifasini ochish")
    }
}

private struct ObjCardHeader: View {
    let item: ObjectItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if let owner = ObjText.value(item.ownerName) {
                    ObjIconLine(symbol: "person.fill", text: owner)
                }
                if let a = ObjText.value(item.address) {
                    ObjIconLine(symbol: "mappin.and.ellipse", text: a)
                }
            }
            Spacer(minLength: 6)
            StatusBadge(status: item.statusValue)
        }
    }
}

private struct ObjCardMetrics: View {
    let item: ObjectItem

    var body: some View {
        HStack(spacing: 0) {
            metric("Kirim", item.kirim, Palette.green)
            divider
            metric("Jami xarajat", item.xarajat, Palette.ink)
            divider
            metric("Qo‘ldagi pul", item.qoldagiPul, item.qoldagiPul < 0 ? Palette.red : Palette.ink)
        }
        .padding(.vertical, 10)
        .background(Palette.surface2.opacity(0.65), in: RoundedRectangle(cornerRadius: Metrics.radiusS, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(Palette.line).frame(width: 0.5, height: 30)
    }

    private func metric(_ title: String, _ v: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(Fmt.compact(v))
                .font(.money(17, .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(Fmt.som(v))")
    }
}

private struct ObjCardContract: View {
    let item: ObjectItem

    private var ratio: Double { Double(item.kirim) / Double(max(item.contractAmount, 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressBar(value: ratio, color: Palette.green, height: 6)
            HStack {
                Text(verbatim: "\(Int((ratio * 100).rounded()))% olindi")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.green)
                Spacer(minLength: 8)
                Text(verbatim: "Shartnoma: " + Fmt.compact(item.contractAmount))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            .lineLimit(1)
        }
    }
}

private struct ObjCardProfit: View {
    let amount: Int

    var body: some View {
        let color = amount < 0 ? Palette.red : Palette.green
        HStack {
            Label(amount < 0 ? "Zarar" : "Sof foyda", systemImage: amount < 0 ? "chart.line.downtrend.xyaxis" : "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Spacer(minLength: 8)
            MoneyText(amount: amount, size: 16, weight: .bold, color: color, signed: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(amount < 0 ? Palette.redSoft : Palette.greenSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
