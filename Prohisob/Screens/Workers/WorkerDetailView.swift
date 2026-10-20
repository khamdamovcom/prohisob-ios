// Usta sahifasi: GET /api/workers/:id — ism, kasbi, telefon; hisob (hisoblangan haq + o'z puliga olgan mol − berilgan pul
// = QARZ); tezkor amallar (pul berish, haq yozish, o'z puliga mol); obyektlar kesimi, magazinlar (usta olib kelgan mol),
// oxirgi yozuvlar. Amallar: tahrirlash (PUT), Excel (worker_id), o'chirish (faqat prorab).
import SwiftUI

struct WorkerDetailView: View {
    let id: Int

    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var data: WorkerDetail?
    @State private var error: Error?
    @State private var editing = false
    @State private var share: ObjShareFile?
    @State private var exporting = false
    @State private var confirmDelete = false
    @State private var alertText: String?
    @State private var gone = false
    @State private var titleShown = !ObjTitleTracker.tracks

    private var name: String { data?.usta.name ?? "Usta" }

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
                if let w = data?.usta { WrkForm(item: w) }
            }
            .sheet(item: $share) { f in
                ObjShareSheet(url: f.url).presentationDetents([.medium, .large]).ignoresSafeArea()
            }
            .confirmationDialog("Usta o‘chirilsinmi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("O‘chirish", role: .destructive) { Task { await remove() } }
                Button("Bekor qilish", role: .cancel) {}
            } message: {
                Text("«\(name)» butunlay o‘chiriladi. Yozuvlari bor ustani o‘chirib bo‘lmaydi — uni «faol emas» qilib qo‘yish mumkin.")
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
                    WrkHeaderCard(worker: d.usta)
                    WrkQuickActions(workerId: id)
                    WrkSummaryCard(s: d.summary)
                    sections(d)
                }
                .padding(.horizontal, Metrics.pad)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .refreshable { await load() }
            .modifier(ObjTitleTracker(shown: $titleShown, threshold: 56))
        } else if let error {
            ErrorState(error: error) { await load() }
        } else {
            LoadingState()
        }
    }

    @ViewBuilder
    private func sections(_ d: WorkerDetail) -> some View {
        if !d.obyektlar.isEmpty { WrkObjectsSection(rows: d.obyektlar) }
        if !d.magazinlar.isEmpty { WrkShopsSection(rows: d.magazinlar, total: d.summary.olibKelganMol) }
        ObjRecentSection(entries: d.tarix, hideWorker: true, filter: EntryFilter(workerId: id, title: d.usta.name)) {
            router.addEntry(EntryPrefill(workerId: id))
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
                    Button { add(.ustaTolov) } label: { Label("Pul berish", systemImage: EntryType.ustaTolov.symbol) }
                    Button { add(.ustaHaqi) } label: { Label("Haq yozish", systemImage: EntryType.ustaHaqi.symbol) }
                    Button { add(.ustaXarid) } label: { Label("O‘z puliga mol", systemImage: EntryType.ustaXarid.symbol) }
                    Button { add(.ovqat) } label: { Label(EntryType.ovqat.short, systemImage: EntryType.ovqat.symbol) }
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
        router.addEntry(EntryPrefill(type: t, workerId: id))
    }

    // MARK: Ma'lumot

    private func load() async {
        guard !gone else { return }
        do {
            let d: WorkerDetail = try await API.shared.get("/api/workers/\(id)")
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
            let url = try await ObjExport.excel("worker_id", id, title: name)
            share = ObjShareFile(url: url)
        } catch is CancellationError {
        } catch {
            session.show(error.localizedDescription, error: true)
        }
    }

    private func remove() async {
        do {
            try await API.shared.delete("/api/workers/\(id)")
            gone = true
            dismiss()
            session.changed()
            session.show("Usta o‘chirildi")
        } catch is CancellationError {
        } catch {
            alertText = error.localizedDescription
        }
    }
}

// MARK: - Sarlavha

private struct WrkHeaderCard: View {
    let worker: Worker

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    Avatar(name: worker.name, size: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(worker.name)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(2)
                            if !worker.active { ObjTag(text: "faol emas") }
                        }
                        Text(ObjText.value(worker.specialty) ?? "Kasbi yozilmagan")
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                        if let p = ObjText.value(worker.phone) { PhoneButton(phone: p) }
                    }
                    Spacer(minLength: 0)
                }
                if let n = ObjText.value(worker.note) {
                    ObjNoteBox(text: n)
                }
            }
        }
    }
}

// MARK: - Tezkor amallar

private struct WrkQuickActions: View {
    let workerId: Int
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 8) {
            ObjActionTile("Pul berish", type: .ustaTolov) { add(.ustaTolov) }
            ObjActionTile("Haq yozish", type: .ustaHaqi) { add(.ustaHaqi) }
            ObjActionTile("O‘z puliga mol", type: .ustaXarid) { add(.ustaXarid) }
        }
    }

    private func add(_ t: EntryType) {
        router.addEntry(EntryPrefill(type: t, workerId: workerId))
    }
}

// MARK: - Hisob

private struct WrkSummaryCard: View {
    let s: WorkerDetail.Summary

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                Text("Hisob").font(.headline).foregroundStyle(Palette.ink)
                ObjLine(title: "Hisoblangan haq", amount: s.haqi, sign: "+", color: Palette.purple, symbol: EntryType.ustaHaqi.symbol)
                ObjLine(title: "O‘z puliga olgan mol", amount: s.ozPuliga, sign: "+", color: Palette.purple, symbol: EntryType.ustaXarid.symbol)
                ObjLine(title: "Berilgan pul", amount: s.tolangan, sign: "−", color: Palette.ink, symbol: EntryType.ustaTolov.symbol)
                Divider().padding(.vertical, 2)
                ObjBigDebt(amount: s.qarz, positive: "Ustaga berilishi kerak", zero: "Qarz yo‘q — hisob teng",
                           negative: "Ortiqcha berilgan (avans)")
            }
        }
    }
}

// MARK: - Obyektlar va magazinlar

private struct WrkObjectsSection: View {
    let rows: [WorkerDetail.ObjectRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Obyektlar")
            ObjBox {
                ObjRows(items: rows, inset: 64) { o in
                    if let oid = o.id {
                        NavigationLink(value: Route.object(oid)) { WrkObjectRow(row: o, link: true) }
                            .buttonStyle(ObjRowStyle())
                    } else {
                        WrkObjectRow(row: o, link: false)
                    }
                }
            }
        }
    }
}

private struct WrkObjectRow: View {
    let row: WorkerDetail.ObjectRow
    let link: Bool

    private var status: ObjectStatus? { row.status.flatMap { ObjectStatus(rawValue: $0) } }

    private var detail: String {
        var p = ["Haqi " + Fmt.compact(row.haqi)]
        if row.ozPuliga > 0 { p.append("mol " + Fmt.compact(row.ozPuliga)) }
        p.append("berilgan " + Fmt.compact(row.tolangan))
        return p.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: row.id == nil ? "tray.fill" : "building.2.fill",
                      color: status?.color ?? Palette.gray,
                      soft: status.map { $0.color.opacity(0.14) } ?? Palette.graySoft, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.id == nil ? "Obyektsiz" : row.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let r = ObjText.range(row.birinchi, row.oxirgi) {
                    Text(r).font(.caption2).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            ObjDebtText(amount: row.qarz)
            if link { ObjChevron() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

private struct WrkShopsSection: View {
    let rows: [WorkerDetail.ShopRow]
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Olib kelgan mollari")
            ObjBox {
                ObjRows(items: rows, inset: 64) { m in
                    NavigationLink(value: Route.shop(m.id)) { row(m) }
                        .buttonStyle(ObjRowStyle())
                }
            }
            Text(verbatim: "Usta magazindan olib kelgan mol — jami " + Fmt.som(total) + ". Bu summa magazin hisobida, ustaga qarz emas.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 4)
        }
    }

    private func row(_ m: WorkerDetail.ShopRow) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "storefront.fill", color: Palette.blue, soft: Palette.blueSoft, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text("\(m.soni) ta xarid").font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            MoneyText(amount: m.summa, size: 15, weight: .semibold, color: Palette.ink)
            ObjChevron()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
