// Hisobot: davr (bu oy, o'tgan oy, 3 oy, shu yil, hammasi, boshqa), xulosa, oylik kirim/xarajat grafigi, xarajat tarkibi (donut),
// obyektlar kesimi, qarzlar (ustalar, magazinlar), Excel eksport (ulashish oynasi).
// Ma'lumot: GET /api/report?from&to, GET /api/export.xlsx?from&to
import SwiftUI
import Charts
import UIKit

// MARK: - Davr

private enum ReportPeriod: String, CaseIterable, Identifiable {
    case month, lastMonth, three, year, all, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: return "Bu oy"
        case .lastMonth: return "O‘tgan oy"
        case .three: return "3 oy"
        case .year: return "Shu yil"
        case .all: return "Hammasi"
        case .custom: return "Boshqa"
        }
    }

    /// So'rov uchun (from, to) — "yyyy-MM-dd"; «Hammasi» — chegarasiz
    func range(_ from: Date, _ to: Date) -> ReportRange {
        let now = Date()
        switch self {
        case .month:
            return ReportRange(from: Fmt.apiDate(DashDates.monthStart(now)), to: Fmt.apiDate(DashDates.monthEnd(now)))
        case .lastMonth:
            let p = DashDates.addMonths(-1, to: DashDates.monthStart(now))
            return ReportRange(from: Fmt.apiDate(p), to: Fmt.apiDate(DashDates.monthEnd(p)))
        case .three:
            let p = DashDates.addMonths(-2, to: DashDates.monthStart(now))
            return ReportRange(from: Fmt.apiDate(p), to: Fmt.apiDate(DashDates.monthEnd(now)))
        case .year:
            return ReportRange(from: Fmt.apiDate(DashDates.yearStart(now)), to: Fmt.apiDate(DashDates.yearEnd(now)))
        case .all:
            return ReportRange(from: nil, to: nil)
        case .custom:
            return ReportRange(from: Fmt.apiDate(min(from, to)), to: Fmt.apiDate(max(from, to)))
        }
    }
}

private struct ReportRange: Hashable {
    let from: String?
    let to: String?

    /// «1-yanvar – 31-dekabr» yoki «Butun davr»
    var caption: String {
        guard let from, let to else { return "Butun davr" }
        return Fmt.day(from) + " – " + Fmt.day(to)
    }

    /// Oy kalitlari oralig'i ("2026-08"…"2026-10") — perMonth ni davrga moslash uchun
    func contains(month oy: String) -> Bool {
        if let from, oy < String(from.prefix(7)) { return false }
        if let to, oy > String(to.prefix(7)) { return false }
        return true
    }
}

private struct ReportKey: Hashable {
    let version: Int
    let range: ReportRange
}

private struct ReportShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Ekran

struct ReportView: View {
    @Environment(Session.self) private var session
    @State private var period: ReportPeriod = .year
    @State private var customFrom = DashDates.monthStart(Date())
    @State private var customTo = Date()
    @State private var showRange = false
    @State private var report: Report?
    @State private var error: Error?
    @State private var loading = false
    @State private var exporting = false
    @State private var shareFile: ReportShareFile?

    private var range: ReportRange { period.range(customFrom, customTo) }

    private var customTitle: String {
        period == .custom ? Fmt.day(min(customFrom, customTo)) + " – " + Fmt.day(max(customFrom, customTo)) : "Boshqa"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ReportPeriodBar(period: period, customTitle: customTitle) { p in
                    if p == .custom {
                        showRange = true
                    } else {
                        period = p
                    }
                }
                content
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle("Hisobot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { exportButton }
        }
        .task(id: ReportKey(version: session.dataVersion, range: range)) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showRange) {
            ReportRangeSheet(from: customFrom, to: customTo) { f, t in
                customFrom = f
                customTo = t
                period = .custom
            }
        }
        .sheet(item: $shareFile) { f in
            ReportShareSheet(url: f.url) { shareFile = nil }
                .ignoresSafeArea()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: holatlar

    @ViewBuilder
    private var content: some View {
        if let r = report {
            loaded(r)
                .opacity(loading ? 0.6 : 1)
                .animation(.easeOut(duration: 0.2), value: loading)
        } else if let error {
            ErrorState(error: error) { await load() }
                .padding(.top, 40)
        } else {
            LoadingState()
                .padding(.top, 40)
        }
    }

    private func loaded(_ r: Report) -> some View {
        let months = monthRows(r)
        let objects = r.perObject.filter { $0.kirim != 0 || $0.jamiXarajat != 0 || $0.hisoblangan != 0 }
        let workers = r.ustalar.filter { $0.qarz > 0 }.sorted { $0.qarz > $1.qarz }
        let shops = r.magazinlar.filter { $0.qarz > 0 }.sorted { $0.qarz > $1.qarz }
        let empty = r.stats.kirim == 0 && r.stats.jamiXarajat == 0 && r.stats.hisoblanganXarajat == 0 && objects.isEmpty
        return VStack(alignment: .leading, spacing: 16) {
            ReportSummaryCard(stats: r.stats, caption: range.caption)
            if empty {
                EmptyState(symbol: "chart.bar", title: "Bu davrda yozuv yo‘q", message: "Boshqa davrni tanlang.")
                    .padding(.top, 8)
            } else {
                ReportMonthsCard(months: months)
                ReportBreakdownCard(stats: r.stats)
                if !objects.isEmpty {
                    ReportObjectsSection(rows: objects)
                }
            }
            if !workers.isEmpty {
                ReportDebtsSection(title: "Ustalarga qarz", workers: workers, shops: [])
            }
            if !shops.isEmpty {
                ReportDebtsSection(title: "Magazinlarga qarz", workers: [], shops: shops)
            }
        }
    }

    /// perMonth: eskidan yangiga, tanlangan davr ichida, boshidagi bo'sh oylarsiz, oxirgi 12 oy
    private func monthRows(_ r: Report) -> [Report.Month] {
        let rg = range
        var list = r.perMonth.filter { rg.contains(month: $0.oy) }.sorted { $0.oy < $1.oy }
        while let first = list.first, first.kirim == 0, first.xarajat == 0 {
            list.removeFirst()
        }
        return Array(list.suffix(12))
    }

    // MARK: Excel

    @ViewBuilder
    private var exportButton: some View {
        if exporting {
            ProgressView()
        } else {
            Button {
                Task { await export() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Excel")
                }
                .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel("Excel faylga yuklab olish")
        }
    }

    private func export() async {
        guard !exporting else { return }
        exporting = true
        defer { exporting = false }
        let rg = range
        do {
            let url = try await API.shared.download("/api/export.xlsx", query: ["from": rg.from, "to": rg.to],
                                                    filename: "Prohisob-hisobot-\(Fmt.apiDate(Date())).xlsx")
            shareFile = ReportShareFile(url: url)
        } catch is CancellationError {
        } catch {
            session.show(error.localizedDescription, error: true)
        }
    }

    // MARK: yuklash

    private func load() async {
        let rg = range
        loading = true
        defer { if !Task.isCancelled { loading = false } }
        do {
            let r: Report = try await API.shared.get("/api/report", query: ["from": rg.from, "to": rg.to])
            report = r
            error = nil
        } catch is CancellationError {
        } catch {
            if report == nil {
                self.error = error
            } else {
                session.show(error.localizedDescription, error: true)
            }
        }
    }
}

// MARK: - Davr tanlash

private struct ReportPeriodBar: View {
    let period: ReportPeriod
    let customTitle: String
    let select: (ReportPeriod) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ReportPeriod.allCases) { p in
                    Chip(title: p == .custom ? customTitle : p.title,
                         symbol: p == .custom ? "calendar" : nil,
                         selected: p == period) {
                        select(p)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .contentMargins(.horizontal, Metrics.pad, for: .scrollContent)
        .padding(.horizontal, -Metrics.pad)
    }
}

/// «Boshqa» davr: ikki sana
private struct ReportRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var from: Date
    @State var to: Date
    let apply: (Date, Date) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Boshlanishi", selection: $from, displayedComponents: .date)
                    DatePicker("Oxiri", selection: $to, in: from..., displayedComponents: .date)
                } footer: {
                    Text("Hisobot va Excel fayl shu oraliqdagi yozuvlar bo‘yicha tuziladi.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .navigationTitle("Davrni tanlang")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Bekor qilish") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tayyor") {
                        apply(from, max(from, to))
                        dismiss()
                    }
                }
            }
        }
        .environment(\.locale, Locale(identifier: "uz_Latn_UZ"))
        .presentationDetents([.medium])
    }
}

// MARK: - Xulosa

private struct ReportSummaryCard: View {
    let stats: Stats
    let caption: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label(caption, systemImage: "calendar")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                HStack(spacing: 10) {
                    ReportBigValue(title: "Kirim", amount: stats.kirim, symbol: "arrow.down.left",
                                   color: Palette.green, amountColor: Palette.green)
                    ReportBigValue(title: "Jami xarajat", amount: stats.jamiXarajat, symbol: "arrow.up.right",
                                   color: Palette.red, amountColor: Palette.ink)
                }
                Divider()
                VStack(spacing: 10) {
                    ReportLine(title: "Qo‘ldagi pul", amount: stats.qoldagiPul,
                               color: stats.qoldagiPul < 0 ? Palette.red : Palette.ink, bold: true)
                    ReportLine(title: "Ustalarga qarz", amount: stats.ustaQarz,
                               color: stats.ustaQarz > 0 ? Palette.red : Palette.ink)
                    ReportLine(title: "Magazinga qarz", amount: stats.magazinQarz,
                               color: stats.magazinQarz > 0 ? Palette.red : Palette.ink)
                    if stats.tugaganSoni > 0 {
                        ReportLine(title: "Tugagan obyektlar foydasi", amount: stats.tugaganFoyda,
                                   color: stats.tugaganFoyda < 0 ? Palette.red : Palette.green)
                    }
                }
                if stats.qoldagiPul < 0 {
                    Label("Kirimdan ortiqcha sarflangan", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.red)
                }
            }
        }
    }
}

private struct ReportBigValue: View {
    let title: String
    let amount: Int
    let symbol: String
    let color: Color
    let amountColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(color)
                    .frame(width: 20, height: 20)
                    .background(color.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            MoneyText(amount: amount, size: 18, weight: .bold, color: amountColor)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: Metrics.radiusS, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ReportLine: View {
    let title: String
    let amount: Int
    var color: Color = Palette.ink
    var bold = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(bold ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(bold ? Palette.ink : Palette.muted)
                .lineLimit(2)
            Spacer(minLength: 8)
            MoneyText(amount: amount, size: bold ? 17 : 15, weight: bold ? .bold : .semibold, color: color)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Oylik grafik

private struct ReportMonthsCard: View {
    let months: [Report.Month]
    @State private var selected: String?

    private var hasData: Bool { months.contains { $0.kirim != 0 || $0.xarajat != 0 } }
    private var current: Report.Month? { selected.flatMap { s in months.first { $0.oy == s } } }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Oylar bo‘yicha")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    ReportLegendDot(title: "Kirim", color: Palette.green)
                    ReportLegendDot(title: "Xarajat", color: Palette.red)
                }
                if hasData {
                    detail
                    chart
                        .frame(height: 210)
                } else {
                    Text("Bu davrda kirim ham, xarajat ham yo‘q")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
        }
    }

    /// Tanlangan oy (grafikni bosib turing) yoki ko'rsatilgan oylar jami
    private var detail: some View {
        let kirim = current?.kirim ?? months.reduce(0) { $0 + $1.kirim }
        let xarajat = current?.xarajat ?? months.reduce(0) { $0 + $1.xarajat }
        let title = current.map { Fmt.month($0.oy) } ?? (months.count == 1 ? Fmt.month(months[0].oy) : "\(months.count) oy jami")
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                ReportMiniValue(title: "Kirim", text: Fmt.compact(kirim), color: Palette.green)
                ReportMiniValue(title: "Xarajat", text: Fmt.compact(xarajat), color: Palette.ink)
                ReportMiniValue(title: "Farq", text: (kirim - xarajat > 0 ? "+" : "") + Fmt.compact(kirim - xarajat),
                                color: kirim - xarajat < 0 ? Palette.red : Palette.ink)
            }
        }
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var chart: some View {
        Chart {
            ForEach(months) { m in
                BarMark(x: .value("Oy", m.oy), y: .value("Summa", Double(m.kirim)))
                    .foregroundStyle(by: .value("Tur", "Kirim"))
                    .position(by: .value("Tur", "Kirim"))
                    .cornerRadius(4)
                    .opacity(selected == nil || selected == m.oy ? 1 : 0.35)
                BarMark(x: .value("Oy", m.oy), y: .value("Summa", Double(m.xarajat)))
                    .foregroundStyle(by: .value("Tur", "Xarajat"))
                    .position(by: .value("Tur", "Xarajat"))
                    .cornerRadius(4)
                    .opacity(selected == nil || selected == m.oy ? 1 : 0.35)
            }
        }
        .chartForegroundStyleScale(["Kirim": Palette.green, "Xarajat": Palette.red])
        .chartLegend(.hidden)
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let s = value.as(String.self) {
                        Text(Fmt.monthShort(s))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(Fmt.compact(Int(v)))
                    }
                }
            }
        }
        .accessibilityLabel("Oylar bo‘yicha kirim va xarajat grafigi")
    }
}

private struct ReportMiniValue: View {
    let title: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Palette.muted)
            Text(text)
                .font(.money(16, .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ReportLegendDot: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.muted)
        }
        .padding(.leading, 6)
    }
}

// MARK: - Xarajat tarkibi

private struct ReportPart: Identifiable {
    let id: String
    let amount: Int
    let color: Color
}

private struct ReportBreakdownCard: View {
    let stats: Stats

    private var parts: [ReportPart] {
        [
            ReportPart(id: "Ustalarga berilgan", amount: stats.ustaTolov, color: Palette.red),
            ReportPart(id: "Magazinga to‘langan", amount: stats.magazinTolov, color: Palette.blue),
            ReportPart(id: "Obyekt xarajati", amount: stats.obyektXarajat, color: Palette.teal),
            ReportPart(id: "Obed", amount: stats.ovqat, color: Palette.orange),
            ReportPart(id: "Boshqa xarajat", amount: stats.xarajat, color: Palette.gray),
        ].filter { $0.amount > 0 }
    }

    var body: some View {
        let list = parts
        let total = list.reduce(0) { $0 + $1.amount }
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Xarajat tarkibi")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                if total == 0 {
                    Text("Bu davrda xarajat yo‘q")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    ReportDonut(parts: list, total: total)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 12) {
                        ForEach(list) { p in
                            ReportPartRow(part: p, total: total)
                        }
                    }
                }
            }
        }
    }
}

private struct ReportDonut: View {
    let parts: [ReportPart]
    let total: Int

    var body: some View {
        ZStack {
            Chart(parts) { p in
                SectorMark(angle: .value("Summa", Double(p.amount)), innerRadius: .ratio(0.64), angularInset: 1.5)
                    .cornerRadius(4)
                    .foregroundStyle(p.color)
            }
            .chartLegend(.hidden)
            VStack(spacing: 1) {
                Text("Jami")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                Text(Fmt.compact(total))
                    .font(.money(20, .bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("so‘m")
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: 110)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Xarajat tarkibi, jami " + Fmt.som(total))
    }
}

private struct ReportPartRow: View {
    let part: ReportPart
    let total: Int

    private var percent: String {
        let p = Double(part.amount) * 100 / Double(max(total, 1))
        if p > 0 && p < 1 { return "<1%" }
        return String(Int(p.rounded())) + "%"
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(part.color)
                .frame(width: 10, height: 10)
            Text(part.id)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            MoneyText(amount: part.amount, size: 14, weight: .semibold, color: Palette.ink, currency: false)
                .layoutPriority(1)
            Text(verbatim: percent)
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.muted)
                .monospacedDigit()
                .frame(minWidth: 38, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Obyektlar kesimi

private struct ReportObjectsSection: View {
    let rows: [Report.ObjectRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Obyektlar")
            ForEach(rows) { o in
                NavigationLink(value: Route.object(o.id)) {
                    ReportObjectCard(row: o)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

private struct ReportObjectCard: View {
    let row: Report.ObjectRow

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Text(row.name)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    StatusBadge(status: row.statusValue)
                }
                HStack(alignment: .top, spacing: 8) {
                    ReportCell(title: "Kirim", amount: row.kirim, color: Palette.green)
                    ReportCell(title: "Jami xarajat", amount: row.jamiXarajat, color: Palette.ink)
                    ReportCell(title: "Qo‘ldagi pul", amount: row.qoldagiPul,
                               color: row.qoldagiPul < 0 ? Palette.red : Palette.ink)
                }
                if row.contractAmount > 0 {
                    contract
                }
                if row.statusValue == .tugagan, let f = row.foyda {
                    HStack(alignment: .firstTextBaseline) {
                        Label("Sof foyda", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(f < 0 ? Palette.red : Palette.green)
                        Spacer(minLength: 8)
                        MoneyText(amount: f, size: 16, weight: .bold, color: f < 0 ? Palette.red : Palette.green)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(f < 0 ? Palette.redSoft : Palette.greenSoft,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var contract: some View {
        let p = Double(row.kirim) / Double(max(row.contractAmount, 1))
        let text = "Shartnoma " + Fmt.compact(row.contractAmount) + " so‘m · " + String(Int((p * 100).rounded())) + "% olindi"
        return VStack(alignment: .leading, spacing: 6) {
            ProgressBar(value: p, color: Palette.green, height: 6)
            Text(verbatim: text)
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct ReportCell: View {
    let title: String
    let amount: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            MoneyText(amount: amount, size: 15, weight: .semibold, color: color, currency: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Qarzlar

private struct ReportDebtsSection: View {
    let title: String
    let workers: [Worker]
    let shops: [Shop]

    private var total: Int { workers.reduce(0) { $0 + $1.qarz } + shops.reduce(0) { $0 + $1.qarz } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: title)
                MoneyText(amount: total, size: 15, weight: .semibold, color: Palette.red)
                    .fixedSize()
            }
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(workers.enumerated()), id: \.element.id) { i, w in
                        NavigationLink(value: Route.worker(w.id)) {
                            DashDebtRow(name: w.name, subtitle: w.specialty, amount: w.qarz)
                        }
                        .buttonStyle(.plain)
                        if i < workers.count - 1 {
                            Divider().padding(.leading, 66)
                        }
                    }
                    ForEach(Array(shops.enumerated()), id: \.element.id) { i, s in
                        NavigationLink(value: Route.shop(s.id)) {
                            DashDebtRow(name: s.name, subtitle: s.address, amount: s.qarz, kind: .shop)
                        }
                        .buttonStyle(.plain)
                        if i < shops.count - 1 {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Ulashish oynasi (Excel)

private struct ReportShareSheet: UIViewControllerRepresentable {
    let url: URL
    let done: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in done() }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
