// «Asosiy» (dashboard): salom va kabinet, davr tanlash, qo'ldagi pul (hero), qarzlar va obyektlar plitkalari, tezkor amallar,
// faol obyektlar karuseli, qarzdor ustalar va magazinlar, oxirgi yozuvlar. Ma'lumot: GET /api/dashboard?from&to
// (qarzlar davrga bog'liq emas — server umumiy qoldiqni beradi). Toolbar: hisobot, egasi uchun kabinet almashtirish.
import SwiftUI

// MARK: - Sana oraliqlari (Asosiy va Hisobot uchun umumiy)

/// Oy va yil boshi/oxiri — Fmt.cal (grigorian, mahalliy vaqt) bo'yicha
enum DashDates {
    static func monthStart(_ d: Date) -> Date {
        let c = Fmt.cal
        return c.date(from: c.dateComponents([.year, .month], from: d)) ?? d
    }

    static func monthEnd(_ d: Date) -> Date {
        let start = monthStart(d)
        let next = Fmt.cal.date(byAdding: .month, value: 1, to: start) ?? start
        return Fmt.cal.date(byAdding: .day, value: -1, to: next) ?? d
    }

    static func addMonths(_ n: Int, to d: Date) -> Date {
        Fmt.cal.date(byAdding: .month, value: n, to: d) ?? d
    }

    static func yearStart(_ d: Date) -> Date {
        let c = Fmt.cal
        return c.date(from: c.dateComponents([.year], from: d)) ?? d
    }

    static func yearEnd(_ d: Date) -> Date {
        let start = yearStart(d)
        let next = Fmt.cal.date(byAdding: .year, value: 1, to: start) ?? start
        return Fmt.cal.date(byAdding: .day, value: -1, to: next) ?? d
    }

    /// Date → "2026-10" (Fmt.month uchun)
    static func ym(_ d: Date) -> String { String(Fmt.apiDate(d).prefix(7)) }
}

/// Asosiy ekrandagi davr
private enum DashPeriod: String, CaseIterable, Identifiable {
    case month, lastMonth, year, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: return "Bu oy"
        case .lastMonth: return "O‘tgan oy"
        case .year: return "Shu yil"
        case .all: return "Hammasi"
        }
    }

    /// So'rov uchun (from, to) — "yyyy-MM-dd"; «Hammasi» — chegarasiz
    var range: (from: String?, to: String?) {
        let now = Date()
        switch self {
        case .month:
            return (Fmt.apiDate(DashDates.monthStart(now)), Fmt.apiDate(DashDates.monthEnd(now)))
        case .lastMonth:
            let p = DashDates.addMonths(-1, to: DashDates.monthStart(now))
            return (Fmt.apiDate(p), Fmt.apiDate(DashDates.monthEnd(p)))
        case .year:
            return (Fmt.apiDate(DashDates.yearStart(now)), Fmt.apiDate(DashDates.yearEnd(now)))
        case .all:
            return (nil, nil)
        }
    }

    /// Hero kartadagi izoh: «Oktabr 2026», «2026-yil», «Butun davr»
    var caption: String {
        let now = Date()
        switch self {
        case .month: return Fmt.month(DashDates.ym(now))
        case .lastMonth: return Fmt.month(DashDates.ym(DashDates.addMonths(-1, to: DashDates.monthStart(now))))
        case .year: return "\(Fmt.cal.component(.year, from: now))-yil"
        case .all: return "Butun davr"
        }
    }
}

private struct DashKey: Hashable {
    let version: Int
    let period: DashPeriod
}

// MARK: - Ekran

struct DashboardView: View {
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @AppStorage("home.period") private var period: DashPeriod = .month
    @State private var data: Dashboard?
    @State private var error: Error?
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DashGreeting()
                content
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.top, 2)
            .padding(.bottom, 32)
        }
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle("Asosiy")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .task(id: DashKey(version: session.dataVersion, period: period)) { await load() }
        .refreshable { await load() }
    }

    // MARK: holatlar

    @ViewBuilder
    private var content: some View {
        if let d = data {
            if isBlank(d) {
                blank
            } else {
                loaded(d)
            }
        } else if let error {
            ErrorState(error: error) { await load() }
                .padding(.top, 40)
        } else {
            LoadingState()
                .padding(.top, 40)
        }
    }

    /// Kabinet bo'sh: obyekt ham, yozuv ham, qarz ham yo'q
    private func isBlank(_ d: Dashboard) -> Bool {
        let s = d.stats
        return d.oxirgi.isEmpty && d.obyektlar.isEmpty && s.obyektlarJami == 0 && s.kirim == 0 && s.jamiXarajat == 0
            && s.hisoblanganXarajat == 0 && s.ustaQarz == 0 && s.magazinQarz == 0
    }

    private var blank: some View {
        VStack(spacing: 18) {
            if period != .all { periodPicker }
            EmptyState(symbol: "square.and.pencil",
                       title: "Birinchi yozuvni qo‘shing",
                       message: period == .all
                           ? "Uy egasidan kirim, ustaga to‘lov, magazindan mol — hammasi shu yerda hisoblanadi."
                           : "Bu davrda yozuv yo‘q. Boshqa davrni tanlang yoki yangi yozuv qo‘shing.",
                       actionTitle: "Yozuv qo‘shish") {
                router.addEntry()
            }
            .padding(.top, 24)
        }
    }

    private func loaded(_ d: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            periodPicker
            DashHero(stats: d.stats, caption: period.caption)
                .opacity(loading ? 0.6 : 1)
            DashQuickActions()
            tiles(d)
            objectsSection(d)
            workersSection(d)
            shopsSection(d)
            recentSection(d)
        }
        .animation(.easeOut(duration: 0.2), value: loading)
    }

    private var periodPicker: some View {
        Picker("Davr", selection: $period) {
            ForEach(DashPeriod.allCases) { p in
                Text(p.title).tag(p)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: plitkalar

    private func tiles(_ d: Dashboard) -> some View {
        let s = d.stats
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                Button { router.open(nil, in: .workers) } label: {
                    StatTile(title: "Ustalarga qarz", amount: s.ustaQarz, symbol: "person.2.fill",
                             color: Palette.red, soft: Palette.redSoft,
                             amountColor: s.ustaQarz > 0 ? Palette.red : Palette.ink,
                             note: s.ustaQarz > 0 ? "Berilmagan ish haqi" : "Qarz yo‘q")
                        .overlay(alignment: .topTrailing) { DashChevron() }
                }
                .buttonStyle(PressableStyle())

                NavigationLink(value: Route.shops) {
                    StatTile(title: "Magazinga qarz", amount: s.magazinQarz, symbol: "storefront.fill",
                             color: Palette.blue, soft: Palette.blueSoft,
                             amountColor: s.magazinQarz > 0 ? Palette.red : Palette.ink,
                             note: s.magazinQarz > 0 ? "To‘lanmagan mol" : "Qarz yo‘q")
                        .overlay(alignment: .topTrailing) { DashChevron() }
                }
                .buttonStyle(PressableStyle())

                Button { router.open(nil, in: .objects) } label: {
                    DashCountTile(title: "Faol obyektlar", count: s.obyektlar, symbol: "building.2.fill",
                                  color: Palette.green, soft: Palette.greenSoft,
                                  note: "Jami \(s.obyektlarJami) ta obyekt")
                        .overlay(alignment: .topTrailing) { DashChevron() }
                }
                .buttonStyle(PressableStyle())

                if s.tugaganSoni > 0 {
                    StatTile(title: "Sof foyda", amount: s.tugaganFoyda, symbol: "checkmark.seal.fill",
                             color: Palette.green, soft: Palette.greenSoft,
                             amountColor: s.tugaganFoyda < 0 ? Palette.red : Palette.green,
                             note: "\(s.tugaganSoni) ta tugagan obyektdan")
                }
            }
            if period != .all {
                Label("Qarzlar davrga bog‘liq emas — umumiy qoldiq", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: bo'limlar

    @ViewBuilder
    private func objectsSection(_ d: Dashboard) -> some View {
        let faol = d.obyektlar.filter { $0.statusValue == .faol }
        let list = faol.isEmpty ? d.obyektlar : faol
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: faol.isEmpty ? "Obyektlar" : "Faol obyektlar", actionTitle: "Barchasi") {
                    router.open(nil, in: .objects)
                }
                if list.count == 1, let o = list.first {
                    NavigationLink(value: Route.object(o.id)) { DashObjectCard(object: o) }
                        .buttonStyle(PressableStyle())
                } else {
                    DashObjectCarousel(objects: list)
                }
            }
        }
    }

    @ViewBuilder
    private func workersSection(_ d: Dashboard) -> some View {
        let list = Array(d.qarzdorUstalar.filter { $0.qarz > 0 }.sorted { $0.qarz > $1.qarz }.prefix(5))
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Qarzdor ustalar", actionTitle: "Barchasi") {
                    router.open(nil, in: .workers)
                }
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, w in
                            NavigationLink(value: Route.worker(w.id)) {
                                DashDebtRow(name: w.name, subtitle: w.specialty, amount: w.qarz)
                            }
                            .buttonStyle(.plain)
                            if i < list.count - 1 {
                                Divider().padding(.leading, 66)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func shopsSection(_ d: Dashboard) -> some View {
        let list = d.qarzdorMagazinlar.filter { $0.qarz > 0 }.sorted { $0.qarz > $1.qarz }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Qarzdor magazinlar", actionTitle: "Barchasi") {
                    router.push(.shops)
                }
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                            NavigationLink(value: Route.shop(s.id)) {
                                DashDebtRow(name: s.name, subtitle: s.address, amount: s.qarz, kind: .shop)
                            }
                            .buttonStyle(.plain)
                            if i < list.count - 1 {
                                Divider().padding(.leading, 66)
                            }
                        }
                    }
                }
            }
        }
    }

    private func recentSection(_ d: Dashboard) -> some View {
        let list = Array(d.oxirgi.prefix(8))
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Oxirgi yozuvlar", actionTitle: "Barchasi") {
                router.open(nil, in: .entries)
            }
            if list.isEmpty {
                Card {
                    VStack(spacing: 12) {
                        Text("Bu davrda yozuv yo‘q")
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                        Button { router.addEntry() } label: {
                            Label("Yozuv qo‘shish", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                        }
                        .secondaryButton()
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                            NavigationLink(value: Route.entry(e.id)) {
                                EntryRow(entry: e, showDate: true)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            if i < list.count - 1 {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if session.isEgasi && !session.kabinetlar.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                DashKabinetMenu()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(value: Route.report) {
                Image(systemName: "chart.bar.fill")
            }
            .accessibilityLabel("Hisobot")
        }
    }

    // MARK: yuklash

    private func load() async {
        let r = period.range
        loading = true
        defer { if !Task.isCancelled { loading = false } }
        do {
            let d: Dashboard = try await API.shared.get("/api/dashboard", query: ["from": r.from, "to": r.to])
            data = d
            error = nil
        } catch is CancellationError {
        } catch {
            if data == nil {
                self.error = error
            } else {
                session.show(error.localizedDescription, error: true)
            }
        }
    }
}

// MARK: - Salom va kabinet

private struct DashGreeting: View {
    @Environment(Session.self) private var session

    private var greeting: String {
        session.userName.isEmpty ? "Salom!" : "Salom, " + session.userName
    }

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: session.userName.isEmpty ? "P" : session.userName, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if !session.kabinetName.isEmpty {
                    Label(session.kabinetName, systemImage: "building.2")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Platforma egasi: qaysi prorab kabineti bilan ishlash
private struct DashKabinetMenu: View {
    @Environment(Session.self) private var session

    var body: some View {
        let current = session.me?.kabinet?.id
        Menu {
            Section("Kabinet") {
                ForEach(session.kabinetlar) { k in
                    Button {
                        Task { await session.selectKabinet(k.id) }
                    } label: {
                        if k.id == current {
                            Label(k.name, systemImage: "checkmark")
                        } else {
                            Text(k.name)
                        }
                    }
                }
            }
            if session.kabinetId != nil {
                Button {
                    Task { await session.selectKabinet(nil) }
                } label: {
                    Label("O‘z kabinetimga qaytish", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Image(systemName: "building.2.crop.circle")
        }
        .accessibilityLabel("Kabinetni almashtirish")
    }
}

// MARK: - Hero: qo'ldagi pul

private struct DashHero: View {
    let stats: Stats
    let caption: String

    private var negative: Bool { stats.qoldagiPul < 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(alignment: .leading, spacing: 8) {
                MoneyText(amount: stats.qoldagiPul, size: 40, weight: .bold, color: negative ? Palette.red : Palette.ink)
                if negative {
                    Label("Ortiqcha sarflangan", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Palette.redSoft, in: Capsule())
                }
            }
            HStack(spacing: 10) {
                DashFlowBox(title: "Kirim", amount: stats.kirim, symbol: "arrow.down.left",
                            color: Palette.green, amountColor: Palette.green)
                DashFlowBox(title: "Jami xarajat", amount: stats.jamiXarajat, symbol: "arrow.up.right",
                            color: Palette.red, amountColor: Palette.ink)
            }
            ratio
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { DashHeroBackground() }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.brand.opacity(0.4), lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "banknote.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.onBrand)
                .frame(width: 30, height: 30)
                .background(Palette.brand, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            Text("Qo‘ldagi pul")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink2)
            Spacer(minLength: 8)
            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Palette.surface.opacity(0.75), in: Capsule())
        }
    }

    @ViewBuilder
    private var ratio: some View {
        if stats.kirim > 0 {
            let r = Double(stats.jamiXarajat) / Double(stats.kirim)
            VStack(alignment: .leading, spacing: 6) {
                ProgressBar(value: r, color: r > 1 ? Palette.red : Palette.brand, height: 6)
                Text(verbatim: "Kirimning \(Int((r * 100).rounded()))% qismi sarflandi")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
        } else if stats.jamiXarajat > 0 {
            Text("Bu davrda kirim yo‘q")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
    }
}

private struct DashHeroBackground: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Palette.surface
            LinearGradient(colors: [Palette.brandSoft, Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Palette.brand.opacity(0.22))
                .frame(width: 220, height: 220)
                .blur(radius: 50)
                .offset(x: 80, y: -100)
        }
        .accessibilityHidden(true)
    }
}

private struct DashFlowBox: View {
    let title: String
    let amount: Int
    let symbol: String
    let color: Color
    var amountColor: Color = Palette.ink

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
            MoneyText(amount: amount, size: 17, weight: .bold, color: amountColor)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: Metrics.radiusS, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Plitkalar

/// StatTile bilan bir xil ko'rinish, lekin son (dona) uchun
private struct DashCountTile: View {
    let title: String
    let count: Int
    let symbol: String
    let color: Color
    let soft: Color
    let note: String

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                IconBadge(symbol: symbol, color: color, soft: soft, size: 30)
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(count))
                        .font(.money(19, .bold))
                        .foregroundStyle(Palette.ink)
                    Text("ta")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.muted)
                }
                .lineLimit(1)
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bosiladigan plitka belgisi
private struct DashChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(Palette.muted.opacity(0.6))
            .padding(.top, 22)
            .padding(.trailing, 14)
            .accessibilityHidden(true)
    }
}

// MARK: - Tezkor amallar

private struct DashQuickAction: Identifiable {
    let title: String
    let type: EntryType
    var id: String { type.rawValue }
}

private struct DashQuickActions: View {
    @Environment(Router.self) private var router

    private let items = [
        DashQuickAction(title: "Kirim", type: .kirim),
        DashQuickAction(title: "Ustaga to‘lov", type: .ustaTolov),
        DashQuickAction(title: "Mol olish", type: .xarid),
        DashQuickAction(title: "Xarajat", type: .xarajat),
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                Button {
                    router.addEntry(EntryPrefill(type: item.type))
                } label: {
                    DashActionLabel(item: item)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(item.title): yangi yozuv")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DashActionLabel: View {
    let item: DashQuickAction

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: item.type.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(item.type.color)
                .frame(width: 44, height: 44)
                .background(item.type.softColor, in: Circle())
            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Obyektlar karuseli

private struct DashObjectCarousel: View {
    let objects: [ObjectItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(objects) { o in
                    NavigationLink(value: Route.object(o.id)) {
                        DashObjectCard(object: o)
                            .frame(width: 288)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, Metrics.pad, for: .scrollContent)
        .padding(.horizontal, -Metrics.pad)
    }
}

private struct DashObjectCard: View {
    let object: ObjectItem

    private var progress: Double? {
        guard object.contractAmount > 0 else { return nil }
        return Double(object.kirim) / Double(object.contractAmount)
    }

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    IconBadge(symbol: "building.2.fill", color: Palette.onBrand, soft: Palette.brand, size: 34)
                    Spacer(minLength: 8)
                    StatusBadge(status: object.statusValue)
                }
                Text(object.name)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
                kirimBlock
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("Qo‘ldagi pul")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                    Spacer(minLength: 8)
                    MoneyText(amount: object.qoldagiPul, size: 16, weight: .bold,
                              color: object.qoldagiPul < 0 ? Palette.red : Palette.ink)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var kirimTitle: String { object.contractAmount > 0 ? "Kirim / shartnoma" : "Kirim" }
    private var kirimUnit: String { object.contractAmount > 0 ? "/ " + Fmt.compact(object.contractAmount) + " so‘m" : "so‘m" }

    private var kirimBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(kirimTitle)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 6)
                if let p = progress {
                    Text(verbatim: "\(Int((p * 100).rounded()))%")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.green)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.compact(object.kirim))
                    .font(.money(17, .bold))
                    .foregroundStyle(Palette.green)
                Text(kirimUnit)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.muted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if let p = progress {
                ProgressBar(value: p, color: Palette.green, height: 6)
            } else {
                Capsule().fill(Palette.surface2).frame(height: 6)
            }
        }
    }
}

// MARK: - Qarz qatori (Hisobot ham ishlatadi)

/// Usta (bosh harflar) yoki magazin belgisi, nomi, izoh va qarz (qizil)
struct DashDebtRow: View {
    enum Kind { case worker, shop }

    let name: String
    var subtitle: String?
    let amount: Int
    var kind: Kind = .worker

    private var sub: String? {
        guard let s = subtitle?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    var body: some View {
        HStack(spacing: 12) {
            if kind == .worker {
                Avatar(name: name, size: 40)
            } else {
                IconBadge(symbol: "storefront.fill", color: Palette.blue, soft: Palette.blueSoft, size: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let sub {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            MoneyText(amount: amount, size: 15, weight: .semibold, color: Palette.red)
                .layoutPriority(1)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.muted.opacity(0.6))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
