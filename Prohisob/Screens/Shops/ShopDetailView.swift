// Magazin sahifasi: GET /api/shops/:id — nomi, manzil, telefon; hisob (olingan mol − to'langan = QARZ); tezkor amallar
// (to'lov qilish, mol olish); obyektlar kesimi, ustalar (kim olib kelgan), oxirgi yozuvlar.
// Amallar: tahrirlash (PUT), Excel (shop_id), o'chirish (faqat prorab).
import SwiftUI

struct ShopDetailView: View {
    let id: Int

    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var data: ShopDetail?
    @State private var error: Error?
    @State private var editing = false
    @State private var share: ObjShareFile?
    @State private var exporting = false
    @State private var confirmDelete = false
    @State private var alertText: String?
    @State private var gone = false
    @State private var titleShown = !ObjTitleTracker.tracks

    private var name: String { data?.magazin.name ?? "Magazin" }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bg)
            .navigationTitle(data == nil || titleShown ? name : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { toolbarMenu }
            }
            .task(id: session.dataVersion) { await load() }
            .sheet(isPresented: $editing) {
                if let m = data?.magazin { ShpForm(item: m) }
            }
            .sheet(item: $share) { f in
                ObjShareSheet(url: f.url).presentationDetents([.medium, .large]).ignoresSafeArea()
            }
            .confirmationDialog("Magazin o‘chirilsinmi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("O‘chirish", role: .destructive) { Task { await remove() } }
                Button("Bekor qilish", role: .cancel) {}
            } message: {
                Text("«\(name)» butunlay o‘chiriladi. Yozuvlari bor magazinni o‘chirib bo‘lmaydi — uni «faol emas» qilib qo‘yish mumkin.")
            }
            .alert("O‘chirib bo‘lmadi", isPresented: alertShown) {
                Button("Yaxshi", role: .cancel) {}
            } message: {
                Text(alertText ?? "")
            }
    }

    private var alertShown: Binding<Bool> {
        Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })
    }

    // MARK: Kontent

    @ViewBuilder
    private var content: some View {
        if let d = data {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ShpHeaderCard(shop: d.magazin)
                    ShpQuickActions(shopId: id)
                    ShpSummaryCard(s: d.summary)
                    sections(d)
                }
                .padding(.horizontal, Metrics.pad)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .refreshable { await load() }
            .modifier(ObjTitleTracker(shown: $titleShown, threshold: 56))
            .defaultScrollAnchor(ObjDebug.on && ObjDebug.dark ? UnitPoint.bottom : nil)
        } else if let error {
            ErrorState(error: error) { await load() }
        } else {
            LoadingState()
        }
    }

    @ViewBuilder
    private func sections(_ d: ShopDetail) -> some View {
        if !d.obyektlar.isEmpty { ShpObjectsSection(rows: d.obyektlar) }
        if !d.ustalar.isEmpty { ShpWorkersSection(rows: d.ustalar) }
        ObjRecentSection(entries: d.tarix, hideShop: true, filter: EntryFilter(shopId: id, title: d.magazin.name)) {
            router.addEntry(EntryPrefill(shopId: id))
        }
    }

    // MARK: Amallar menyusi

    @ViewBuilder
    private var toolbarMenu: some View {
        if exporting {
            ProgressView()
        } else {
            Menu {
                Section("Yozuv qo‘shish") {
                    Button { add(.magazinTolov) } label: { Label("To‘lov qilish", systemImage: EntryType.magazinTolov.symbol) }
                    Button { add(.xarid) } label: { Label("Mol olish", systemImage: EntryType.xarid.symbol) }
                }
                Section {
                    Button { editing = true } label: { Label("Tahrirlash", systemImage: "pencil") }
                    Button { Task { await exportExcel() } } label: { Label("Excel’ga yuklash", systemImage: "tablecells") }
                }
                if session.isProrab {
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("O‘chirish", systemImage: "trash") }
                    }
                }
            } label: {
                ObjMoreIcon()
            }
            .disabled(data == nil)
        }
    }

    private func add(_ t: EntryType) {
        router.addEntry(EntryPrefill(type: t, shopId: id))
    }

    // MARK: Ma'lumot

    private func load() async {
        guard !gone else { return }
        do {
            let d: ShopDetail = try await API.shared.get("/api/shops/\(id)")
            data = d
            error = nil
        } catch is CancellationError {
        } catch {
            if data == nil { self.error = error } else { session.show(error.localizedDescription, error: true) }
        }
    }

    private func exportExcel() async {
        guard !exporting else { return }
        exporting = true
        defer { exporting = false }
        do {
            let url = try await ObjExport.excel("shop_id", id, title: name)
            share = ObjShareFile(url: url)
        } catch is CancellationError {
        } catch {
            session.show(error.localizedDescription, error: true)
        }
    }

    private func remove() async {
        do {
            try await API.shared.delete("/api/shops/\(id)")
            gone = true
            dismiss()
            session.changed()
            session.show("Magazin o‘chirildi")
        } catch is CancellationError {
        } catch {
            alertText = error.localizedDescription
        }
    }
}

// MARK: - Sarlavha

private struct ShpHeaderCard: View {
    let shop: Shop

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    IconBadge(symbol: "storefront.fill", color: Palette.blue, soft: Palette.blueSoft, size: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(shop.name)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(2)
                            if !shop.active { ObjTag(text: "faol emas") }
                        }
                        if let a = ObjText.value(shop.address) {
                            ObjIconLine(symbol: "mappin", text: a, font: .subheadline, lines: 2)
                        }
                        if let p = ObjText.value(shop.phone) { PhoneButton(phone: p) }
                    }
                    Spacer(minLength: 0)
                }
                if let n = ObjText.value(shop.note) {
                    ObjNoteBox(text: n)
                }
            }
        }
    }
}

// MARK: - Tezkor amallar

private struct ShpQuickActions: View {
    let shopId: Int
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 8) {
            ObjActionTile("To‘lov qilish", type: .magazinTolov) { add(.magazinTolov) }
            ObjActionTile("Mol olish", type: .xarid) { add(.xarid) }
        }
    }

    private func add(_ t: EntryType) {
        router.addEntry(EntryPrefill(type: t, shopId: shopId))
    }
}

// MARK: - Hisob

private struct ShpSummaryCard: View {
    let s: ShopDetail.Summary

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                Text("Hisob").font(.headline).foregroundStyle(Palette.ink)
                ObjLine(title: "Olingan mol", amount: s.olingan, sign: "+", color: Palette.teal, symbol: EntryType.xarid.symbol)
                ObjLine(title: "To‘langan", amount: s.tolangan, sign: "−", color: Palette.ink, symbol: EntryType.magazinTolov.symbol)
                Divider().padding(.vertical, 2)
                ObjBigDebt(amount: s.qarz, positive: "Magazinga to‘lanishi kerak", zero: "Qarz yo‘q — hisob teng",
                           negative: "Ortiqcha to‘langan")
            }
        }
    }
}

// MARK: - Obyektlar va ustalar

private struct ShpObjectsSection: View {
    let rows: [ShopDetail.ObjectRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Obyektlar")
            ObjBox {
                ObjRows(items: rows, inset: 64) { o in
                    if let oid = o.id {
                        NavigationLink(value: Route.object(oid)) { ShpObjectRow(row: o, link: true) }
                            .buttonStyle(ObjRowStyle())
                    } else {
                        ShpObjectRow(row: o, link: false)
                    }
                }
            }
        }
    }
}

private struct ShpObjectRow: View {
    let row: ShopDetail.ObjectRow
    let link: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: row.id == nil ? "tray.fill" : "building.2.fill",
                      color: row.id == nil ? Palette.gray : Palette.ink2,
                      soft: Palette.surface2, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.id == nil ? "Obyektsiz" : (ObjText.value(row.name) ?? "Obyektsiz"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text("Olingan " + Fmt.compact(row.olingan) + " · to‘langan " + Fmt.compact(row.tolangan))
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let o = ObjText.value(row.oxirgi) {
                    Text("Oxirgi: " + Fmt.day(o)).font(.caption2).foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 8)
            ObjDebtText(amount: row.qarz, negativeLabel: "ortiqcha")
            if link { ObjChevron() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

private struct ShpWorkersSection: View {
    let rows: [ShopDetail.WorkerRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Kim olib kelgan")
            ObjBox {
                ObjRows(items: rows, inset: 64) { w in
                    if let wid = w.id {
                        NavigationLink(value: Route.worker(wid)) { ShpWorkerRow(row: w, link: true) }
                            .buttonStyle(ObjRowStyle())
                    } else {
                        ShpWorkerRow(row: w, link: false)
                    }
                }
            }
        }
    }
}

private struct ShpWorkerRow: View {
    let row: ShopDetail.WorkerRow
    let link: Bool

    private var title: String {
        guard row.id != nil, let n = ObjText.value(row.name) else { return "Usta ko‘rsatilmagan" }
        return n
    }

    private var detail: String {
        var p = ["\(row.soni) ta xarid"]
        if let o = ObjText.value(row.oxirgi) { p.append("oxirgi " + Fmt.day(o)) }
        return p.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            if row.id == nil {
                IconBadge(symbol: "person.fill.questionmark", color: Palette.gray, soft: Palette.graySoft, size: 38)
            } else {
                Avatar(name: title, size: 38)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            MoneyText(amount: row.summa, size: 15, weight: .semibold, color: Palette.ink)
            if link { ObjChevron() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}
