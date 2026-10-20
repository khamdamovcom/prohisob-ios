// Obyekt egasi: bitta obyekt hisobi — siz bergan pul, sarflangan, qoldiq, shartnoma; pul nimaga sarflandi (donut),
// ustalarga va magazinlarga berilgan pul; yozuvlar kun bo'yicha (sahifalab, 30 tadan) va cheklar.
// GET /api/mijoz/objects/:id, /api/mijoz/objects/:id/entries?limit&offset, /api/mijoz/entries/:id/files
import SwiftUI
import Charts

private struct CliDay: Identifiable {
    let id: String
    var rows: [MijozEntry]
}

private struct CliReceipts: Identifiable {
    let id = UUID()
    let refs: [ReceiptRef]
}

struct CliObjectView: View {
    let id: Int
    @Environment(Session.self) private var session
    @State private var detail: MijozObjectDetail?
    @State private var rows: [MijozEntry] = []
    @State private var total = 0
    @State private var loadError: Error?
    @State private var loadingMore = false
    @State private var moreFailed = false
    /// yangilash (pull-to-refresh) eski «yana yuklash» javobini bekor qiladi
    @State private var generation = 0
    @State private var receipts: CliReceipts?
    @State private var opening: Int?

    private static let pageSize = 30

    var body: some View {
        Group {
            if let detail {
                content(detail)
            } else if let loadError {
                ErrorState(error: loadError) { await load() }
            } else {
                LoadingState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.dataVersion) { await load() }
        .fullScreenCover(item: $receipts) { r in
            ReceiptViewer(refs: r.refs)
        }
    }

    private var title: String {
        if let d = detail { return d.obyekt.name }
        return session.mijozMe?.obyektlar.first(where: { $0.id == id })?.name ?? "Obyekt"
    }

    private func content(_ d: MijozObjectDetail) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                CliObjectHeader(ref: d.obyekt)
                Card(padding: 16) {
                    CliSummary(money: CliMoney(d), large: true)
                }
                CliBreakdown(tarkib: d.tarkib, total: d.jamiXarajat)
                if !d.ustalar.isEmpty {
                    CliWorkersCard(rows: d.ustalar)
                }
                if !d.magazinlar.isEmpty {
                    CliShopsCard(rows: d.magazinlar)
                }
                entriesHeader
                if rows.isEmpty {
                    Card {
                        Text("Hali yozuv yo‘q")
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                    }
                } else {
                    ForEach(groups) { g in
                        CliDayBlock(day: g, opening: opening) { e in
                            Task { await openReceipts(e) }
                        }
                    }
                    if rows.count < total {
                        moreFooter
                    }
                }
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable { await load() }
    }

    private var entriesHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Yozuvlar")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
            Spacer()
            if total > 0 {
                Text(verbatim: "\(total) ta")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.top, 8)
    }

    private var moreFooter: some View {
        HStack {
            Spacer()
            if loadingMore {
                ProgressView()
            } else {
                Button {
                    moreFailed = false
                    Task { await loadMore() }
                } label: {
                    Label("Yana yuklash", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .task(id: rows.count) {
            if !moreFailed { await loadMore() }
        }
    }

    /// Yozuvlar kun bo'yicha (server sanasi kamayish tartibida beradi)
    private var groups: [CliDay] {
        var out: [CliDay] = []
        var index: [String: Int] = [:]
        for r in rows {
            let d = String(r.date.prefix(10))
            if let i = index[d] {
                out[i].rows.append(r)
            } else {
                index[d] = out.count
                out.append(CliDay(id: d, rows: [r]))
            }
        }
        return out
    }

    // MARK: yuklash

    private func load() async {
        let detailPath = "/api/mijoz/objects/\(id)"
        let entriesPath = detailPath + "/entries"
        let limit = String(Self.pageSize)
        generation += 1
        let gen = generation
        do {
            async let d: MijozObjectDetail = API.shared.get(detailPath)
            async let p: MijozEntriesPage = API.shared.get(entriesPath, query: ["limit": limit, "offset": "0"])
            let (dd, pp) = try await (d, p)
            guard gen == generation else { return }
            detail = dd
            rows = pp.rows
            total = max(pp.total, pp.rows.count)
            moreFailed = false
            loadError = nil
        } catch is CancellationError {
        } catch {
            if detail == nil { loadError = error } else { session.show(error.localizedDescription, error: true) }
        }
    }

    private func loadMore() async {
        guard !loadingMore, rows.count < total else { return }
        loadingMore = true
        defer { loadingMore = false }
        let gen = generation
        do {
            let p: MijozEntriesPage = try await API.shared.get("/api/mijoz/objects/\(id)/entries",
                                                               query: ["limit": String(Self.pageSize), "offset": String(rows.count)])
            guard gen == generation else { return }
            let known = Set(rows.map(\.id))
            let fresh = p.rows.filter { !known.contains($0.id) }
            rows.append(contentsOf: fresh)
            // server kamroq bersa — oxiriga yetdik
            total = fresh.isEmpty ? rows.count : max(p.total, rows.count)
        } catch is CancellationError {
        } catch {
            moreFailed = true
            session.show(error.localizedDescription, error: true)
        }
    }

    private func openReceipts(_ e: MijozEntry) async {
        guard opening == nil else { return }
        opening = e.id
        defer { opening = nil }
        do {
            let files: [FileInfo] = try await API.shared.get("/api/mijoz/entries/\(e.id)/files")
            if files.isEmpty {
                session.show("Chek topilmadi", error: true)
            } else {
                receipts = CliReceipts(refs: files.map { ReceiptRef(file: $0, mijoz: true) })
            }
        } catch is CancellationError {
        } catch {
            session.show(error.localizedDescription, error: true)
        }
    }
}

// MARK: - Sarlavha

private struct CliObjectHeader: View {
    let ref: MijozObjectDetail.Ref

    private var dates: String? {
        let start = Fmt.parseDay(ref.startDate) != nil ? Fmt.day(ref.startDate) : nil
        let end = Fmt.parseDay(ref.endDate) != nil ? Fmt.day(ref.endDate) : nil
        switch (start, end) {
        case let (s?, e?): return "\(s) — \(e)"
        case let (s?, nil): return "Boshlangan: \(s)"
        case let (nil, e?): return "Tugash: \(e)"
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                StatusBadge(status: ObjectStatus(rawValue: ref.status) ?? .faol)
                if let dates {
                    Text(verbatim: dates)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            if let a = ref.address, !a.isEmpty {
                AccMeta(symbol: "mappin.and.ellipse", text: a)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Xarajat tarkibi

private struct CliPart: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let amount: Int
    let color: Color
}

private struct CliBreakdown: View {
    let tarkib: MijozTarkib
    let total: Int

    private var parts: [CliPart] {
        let all = [
            CliPart(id: "usta", title: "Ustalarga berilgan", symbol: "person.fill", amount: tarkib.ustaTolov, color: Palette.purple),
            CliPart(id: "magazin", title: "Magazinlarga to‘langan", symbol: "storefront.fill", amount: tarkib.magazinTolov, color: Palette.blue),
            CliPart(id: "ovqat", title: "Obed", symbol: "fork.knife", amount: tarkib.ovqat, color: Palette.orange),
            CliPart(id: "obyekt", title: "Obyekt xarajati", symbol: "wrench.and.screwdriver.fill", amount: tarkib.obyektXarajat, color: Palette.teal),
            CliPart(id: "boshqa", title: "Boshqa xarajatlar", symbol: "creditcard.fill", amount: tarkib.xarajat, color: Palette.gray),
        ]
        return all.filter { $0.amount > 0 }
    }

    var body: some View {
        let list = parts
        let sum = max(1, list.reduce(0) { $0 + $1.amount })
        VStack(alignment: .leading, spacing: 10) {
            Text("Pul nimaga sarflandi")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
                .padding(.top, 8)
            Card(padding: 18) {
                if list.isEmpty {
                    Text("Hali xarajat yozilmagan")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                } else {
                    VStack(spacing: 18) {
                        CliDonut(parts: list, total: total)
                            .frame(height: 190)
                        VStack(spacing: 12) {
                            ForEach(list) { p in
                                CliPartRow(part: p, share: Double(p.amount) / Double(sum))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct CliDonut: View {
    let parts: [CliPart]
    let total: Int

    var body: some View {
        ZStack {
            Chart(parts) { p in
                SectorMark(angle: .value("Summa", p.amount), innerRadius: .ratio(0.64), angularInset: 2)
                    .cornerRadius(5)
                    .foregroundStyle(p.color)
            }
            .chartLegend(.hidden)
            VStack(spacing: 1) {
                Text("Sarflangan")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                Text(verbatim: Fmt.compact(total))
                    .font(.money(21, .bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("so‘m")
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: 104)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sarflangan: \(Fmt.som(total))")
    }
}

private struct CliPartRow: View {
    let part: CliPart
    let share: Double

    private var percent: String {
        let p = Int((share * 100).rounded())
        return p < 1 ? "1% dan kam" : "\(p)%"
    }

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: part.symbol, color: part.color, soft: part.color.opacity(0.14), size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: part.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(verbatim: percent)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            MoneyText(amount: part.amount, size: 15)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ustalar va magazinlar

private struct CliWorkersCard: View {
    let rows: [MijozObjectDetail.WorkerRow]

    var body: some View {
        let sorted = rows.sorted { $0.tolangan > $1.tolangan }
        VStack(alignment: .leading, spacing: 10) {
            Text("Ustalarga berilgan")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
                .padding(.top, 8)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { i, w in
                        if i > 0 {
                            Divider().padding(.leading, 66)
                        }
                        CliPersonRow(title: w.name, subtitle: capitalized(w.specialty), amount: w.tolangan) {
                            Avatar(name: accAvatarName(w.name), size: 38)
                        }
                    }
                }
            }
        }
    }

    private func capitalized(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

private struct CliShopsCard: View {
    let rows: [MijozObjectDetail.ShopRow]

    var body: some View {
        let sorted = rows.sorted { $0.tolangan > $1.tolangan }
        VStack(alignment: .leading, spacing: 10) {
            Text("Magazinlarga to‘langan")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
                .padding(.top, 8)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { i, s in
                        if i > 0 {
                            Divider().padding(.leading, 66)
                        }
                        CliPersonRow(title: s.name, subtitle: nil, amount: s.tolangan) {
                            IconBadge(symbol: "storefront.fill", color: Palette.blue, soft: Palette.blueSoft, size: 38)
                        }
                    }
                }
            }
        }
    }
}

private struct CliPersonRow<Leading: View>: View {
    let title: String
    let subtitle: String?
    let amount: Int
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            MoneyText(amount: amount, size: 15)
                .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Yozuvlar

private struct CliDayBlock: View {
    let day: CliDay
    let opening: Int?
    let open: (MijozEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: Fmt.dayHeader(day.id))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .padding(.leading, 4)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(day.rows.enumerated()), id: \.element.id) { i, e in
                        if i > 0 {
                            Divider().padding(.leading, 64)
                        }
                        CliEntryRow(entry: e, opening: opening == e.id) { open(e) }
                    }
                }
            }
        }
    }
}

/// Mijoz yozuvi: tur belgisi, nomi («Siz bergan pul», «Ustaga berildi»…), «nima uchun», usta/magazin, izoh;
/// summa — kirim «+» yashil, qolgani «−»; cheki bo'lsa — bosilganda ko'rsatiladi
private struct CliEntryRow: View {
    let entry: MijozEntry
    let opening: Bool
    let open: () -> Void

    private var isKirim: Bool { entry.kind == .kirim }

    private var who: String? {
        let parts = [entry.workerName, entry.shopName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var whoSymbol: String {
        (entry.workerName ?? "").isEmpty ? "storefront" : "person"
    }

    var body: some View {
        if entry.cheklar > 0 {
            Button(action: open) {
                row
            }
            .buttonStyle(.plain)
            .accessibilityHint("Chekni ko‘rish")
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 12) {
            TypeIcon(type: entry.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.nomi)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                if let t = entry.title, !t.isEmpty, t != entry.nomi {
                    Text(verbatim: t)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                }
                if let who {
                    AccMeta(symbol: whoSymbol, text: who, lines: 1)
                }
                if let n = entry.note, !n.isEmpty {
                    Text(verbatim: n)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                Text(verbatim: (isKirim ? "+" : "−") + Fmt.money(entry.amount))
                    .font(.money(15))
                    .foregroundStyle(isKirim ? Palette.green : Palette.ink)
                    .lineLimit(1)
                if entry.cheklar > 0 {
                    receiptBadge
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var receiptBadge: some View {
        if opening {
            ProgressView()
                .controlSize(.small)
        } else {
            HStack(spacing: 3) {
                Image(systemName: "paperclip")
                Text(verbatim: entry.cheklar == 1 ? "Chek" : "\(entry.cheklar) chek")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Palette.brandSoft, in: Capsule())
        }
    }
}
