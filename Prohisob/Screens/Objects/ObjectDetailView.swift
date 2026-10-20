// Obyekt sahifasi: GET /api/objects/:id — sarlavha (nomi, manzil, holat, uy egasi), tezkor amallar, hisob (kirim,
// jami xarajat, qo'ldagi pul, shartnoma, qarzlar, tugaganda sof foyda), xarajat tarkibi, ustalar, magazinlar, obyekt egalari,
// oxirgi yozuvlar. Amallar: yozuv qo'shish, tahrirlash, holat (PUT), Excel, o'chirish (faqat prorab).
import SwiftUI

struct ObjectDetailView: View {
    let id: Int

    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var data: ObjectDetail?
    @State private var error: Error?
    @State private var editing = false
    @State private var share: ObjShareFile?
    @State private var exporting = false
    @State private var confirmDelete = false
    @State private var alertText: String?
    @State private var gone = false
    @State private var titleShown = !ObjTitleTracker.tracks

    private var name: String { data?.obj.name ?? "Obyekt" }

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
                if let o = data?.obj { ObjForm(item: o) }
            }
            .sheet(item: $share) { f in
                ObjShareSheet(url: f.url).presentationDetents([.medium, .large]).ignoresSafeArea()
            }
            .confirmationDialog("Obyekt o‘chirilsinmi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("O‘chirish", role: .destructive) { Task { await remove() } }
                Button("Bekor qilish", role: .cancel) {}
            } message: {
                Text("«\(name)» butunlay o‘chiriladi. Yozuvlari bor obyekt o‘chmaydi — uni «Tugagan» qilib qo‘yish mumkin.")
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

    private var statusBinding: Binding<ObjectStatus> {
        Binding(get: { data?.obj.statusValue ?? .faol }, set: { s in Task { await setStatus(s) } })
    }

    // MARK: Kontent

    @ViewBuilder
    private var content: some View {
        if let d = data {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ObjHeaderCard(obj: d.obj, status: statusBinding)
                    ObjQuickActions(objectId: id)
                    ObjSummaryCard(obj: d.obj, s: d.summary)
                    ObjDebtTiles(s: d.summary)
                    if d.summary.jamiXarajat > 0 { ObjBreakdownCard(s: d.summary) }
                    sections(d)
                }
                .padding(.horizontal, Metrics.pad)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .refreshable { await load() }
            .modifier(ObjTitleTracker(shown: $titleShown, threshold: 70))
            .defaultScrollAnchor(ObjDebug.anchor)
        } else if let error {
            ErrorState(error: error) { await load() }
        } else {
            LoadingState()
        }
    }

    @ViewBuilder
    private func sections(_ d: ObjectDetail) -> some View {
        if !d.ustalar.isEmpty { ObjWorkersSection(rows: d.ustalar) }
        if !d.magazinlar.isEmpty { ObjShopsSection(rows: d.magazinlar) }
        if let m = d.mijozlar, !m.isEmpty { ObjClientsSection(rows: m) }
        ObjRecentSection(entries: d.tarix, hideObject: true, filter: EntryFilter(objectId: id, title: d.obj.name)) {
            router.addEntry(EntryPrefill(objectId: id))
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
                    ForEach([EntryType.kirim, .ustaTolov, .ustaHaqi, .xarid, .obyektXarajat, .ovqat, .xarajat], id: \.self) { t in
                        Button { router.addEntry(EntryPrefill(type: t, objectId: id)) } label: { Label(t.short, systemImage: t.symbol) }
                    }
                    Button { router.addEntry(EntryPrefill(objectId: id)) } label: { Label("Boshqa tur…", systemImage: "plus") }
                }
                Section {
                    Button { editing = true } label: { Label("Tahrirlash", systemImage: "pencil") }
                    Picker(selection: statusBinding) {
                        ForEach(ObjectStatus.allCases) { s in Text(s.label).tag(s) }
                    } label: {
                        Label("Holatni o‘zgartirish", systemImage: "flag")
                    }
                    .pickerStyle(.menu)
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

    // MARK: Ma'lumot

    private func load() async {
        guard !gone else { return }
        do {
            let d: ObjectDetail = try await API.shared.get("/api/objects/\(id)")
            data = d
            error = nil
        } catch is CancellationError {
        } catch {
            if data == nil { self.error = error } else { session.show(error.localizedDescription, error: true) }
        }
    }

    private func setStatus(_ s: ObjectStatus) async {
        guard let o = data?.obj, o.statusValue != s else { return }
        var body = o.objBody
        body.status = s.rawValue
        do {
            let _: ObjSaved = try await API.shared.put("/api/objects/\(id)", body: body)
            session.changed()
            session.show("Holat: \(s.label)")
        } catch is CancellationError {
        } catch {
            session.show(error.localizedDescription, error: true)
        }
    }

    private func exportExcel() async {
        guard !exporting else { return }
        exporting = true
        defer { exporting = false }
        do {
            let url = try await ObjExport.excel("object_id", id, title: name)
            share = ObjShareFile(url: url)
        } catch is CancellationError {
        } catch {
            session.show(error.localizedDescription, error: true)
        }
    }

    private func remove() async {
        do {
            try await API.shared.delete("/api/objects/\(id)")
            gone = true
            dismiss()
            session.changed()
            session.show("Obyekt o‘chirildi")
        } catch is CancellationError {
        } catch {
            alertText = error.localizedDescription
        }
    }
}

// MARK: - Sarlavha

private struct ObjHeaderCard: View {
    let obj: ObjectItem
    let status: Binding<ObjectStatus>

    private var dates: String? {
        let s = ObjText.value(obj.startDate).map { Fmt.day($0) }
        let e = ObjText.value(obj.endDate).map { Fmt.day($0) }
        switch (s, e) {
        case let (s?, e?): return s + " – " + e
        case let (s?, nil): return "Boshlangan: " + s
        case let (nil, e?): return "Tugash: " + e
        default: return nil
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    ObjStatusMenu(status: status, current: obj.statusValue)
                        .padding(.bottom, 2)
                    Text(obj.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let a = ObjText.value(obj.address) {
                        ObjIconLine(symbol: "mappin", text: a, font: .subheadline, lines: 2)
                    }
                    if let d = dates {
                        ObjIconLine(symbol: "calendar", text: d, font: .subheadline)
                    }
                }
                if ObjText.value(obj.ownerName) != nil || ObjText.value(obj.ownerPhone) != nil {
                    Divider()
                    ObjOwnerRow(name: ObjText.value(obj.ownerName), phone: ObjText.value(obj.ownerPhone))
                }
                if let n = ObjText.value(obj.note) {
                    ObjNoteBox(text: n)
                }
            }
        }
    }
}

/// Holat yorlig'i — bosilsa holatni tanlash menyusi
private struct ObjStatusMenu: View {
    let status: Binding<ObjectStatus>
    let current: ObjectStatus

    var body: some View {
        Menu {
            Picker("Holat", selection: status) {
                ForEach(ObjectStatus.allCases) { s in Text(s.label).tag(s) }
            }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(current.color).frame(width: 7, height: 7)
                Text(current.label).font(.caption.weight(.semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(current.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(current.color.opacity(0.12), in: Capsule())
            .fixedSize()
        }
        .accessibilityLabel("Holat: \(current.label)")
        .accessibilityHint("Holatni o‘zgartirish")
    }
}

private struct ObjOwnerRow: View {
    let name: String?
    let phone: String?

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: name ?? "?", size: 42, color: Palette.ink, soft: Palette.surface2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Uy egasi").font(.caption).foregroundStyle(Palette.muted)
                Text(name ?? "Ko‘rsatilmagan")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if let phone { PhoneButton(phone: phone) }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Tezkor amallar

private struct ObjQuickActions: View {
    let objectId: Int
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 8) {
            ObjActionTile("Kirim", type: .kirim) { add(.kirim) }
            ObjActionTile("Ustaga to‘lov", type: .ustaTolov) { add(.ustaTolov) }
            ObjActionTile("Mol olish", type: .xarid) { add(.xarid) }
            Menu {
                ForEach([EntryType.obyektXarajat, .ovqat, .xarajat], id: \.self) { t in
                    Button { add(t) } label: { Label(t.short, systemImage: t.symbol) }
                }
                Divider()
                Button { add(.qaytarish) } label: { Label(EntryType.qaytarish.short, systemImage: EntryType.qaytarish.symbol) }
                Button { router.addEntry(EntryPrefill(objectId: objectId)) } label: { Label("Boshqa tur…", systemImage: "plus") }
            } label: {
                ObjActionLabel(title: "Xarajat…", symbol: EntryType.obyektXarajat.symbol,
                               color: EntryType.obyektXarajat.color, soft: EntryType.obyektXarajat.softColor)
            }
            .accessibilityLabel("Xarajat qo‘shish")
        }
    }

    private func add(_ t: EntryType) {
        router.addEntry(EntryPrefill(type: t, objectId: objectId))
    }
}

// MARK: - Hisob

private struct ObjSummaryCard: View {
    let obj: ObjectItem
    let s: Stats

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ObjMetric(title: "Kirim", amount: s.kirim, symbol: "arrow.down.left", color: Palette.green, amountColor: Palette.green)
                    ObjMetric(title: "Jami xarajat", amount: s.jamiXarajat, symbol: "arrow.up.right", color: Palette.red)
                }
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Qo‘ldagi pul").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                    MoneyText(amount: s.qoldagiPul, size: 34, weight: .bold, color: s.qoldagiPul < 0 ? Palette.red : Palette.ink)
                    Text("Kirim − jami xarajat (haqiqatda berilgan pul)")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                .accessibilityElement(children: .combine)
                if s.shartnoma > 0 {
                    Divider()
                    ObjContractBlock(s: s)
                }
                if obj.statusValue == .tugagan {
                    ObjProfitRow(amount: s.sofFoyda)
                }
            }
        }
    }
}

private struct ObjContractBlock: View {
    let s: Stats

    private var ratio: Double { Double(s.kirim) / Double(max(s.shartnoma, 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Shartnoma").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                MoneyText(amount: s.shartnoma, size: 16)
            }
            ProgressBar(value: ratio, color: Palette.green, height: 8)
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(Int((ratio * 100).rounded()))% olindi")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.green)
                Spacer(minLength: 8)
                if s.qoldiqOlinadigan > 0 {
                    Text(verbatim: "Yana olinadigan: " + Fmt.som(s.qoldiqOlinadigan))
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                } else {
                    Label("To‘liq olindi", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.green)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ObjProfitRow: View {
    let amount: Int

    var body: some View {
        let color = amount < 0 ? Palette.red : Palette.green
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Label(amount < 0 ? "Zarar" : "Sof foyda", systemImage: amount < 0 ? "chart.line.downtrend.xyaxis" : "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Obyekt tugagan — yakuniy hisob").font(.caption2).foregroundStyle(Palette.muted)
            }
            .foregroundStyle(color)
            Spacer(minLength: 8)
            MoneyText(amount: amount, size: 18, weight: .bold, color: color, signed: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(amount < 0 ? Palette.redSoft : Palette.greenSoft, in: RoundedRectangle(cornerRadius: Metrics.radiusS, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ObjDebtTiles: View {
    let s: Stats

    var body: some View {
        HStack(spacing: 12) {
            StatTile(title: "Ustalarga qarz", amount: s.ustaQarz, symbol: "person.2.fill",
                     color: Palette.purple, soft: Palette.purpleSoft,
                     amountColor: s.ustaQarz > 0 ? Palette.red : Palette.green,
                     note: s.ustaQarz > 0 ? "berilmagan haq" : "qarz yo‘q")
            StatTile(title: "Magazinga qarz", amount: s.magazinQarz, symbol: "storefront.fill",
                     color: Palette.blue, soft: Palette.blueSoft,
                     amountColor: s.magazinQarz > 0 ? Palette.red : Palette.green,
                     note: s.magazinQarz > 0 ? "to‘lanmagan mol" : "qarz yo‘q")
        }
    }
}

// MARK: - Xarajat tarkibi

private struct ObjBreakdownCard: View {
    let s: Stats

    private struct Part: Identifiable {
        let id: String
        let amount: Int
        let type: EntryType
    }

    private var parts: [Part] {
        [Part(id: "Ustalarga berilgan", amount: s.ustaTolov, type: .ustaTolov),
         Part(id: "Magazinga to‘langan", amount: s.magazinTolov, type: .magazinTolov),
         Part(id: "Obyekt xarajati", amount: s.obyektXarajat, type: .obyektXarajat),
         Part(id: "Obed", amount: s.ovqat, type: .ovqat),
         Part(id: "Boshqa", amount: s.xarajat, type: .xarajat)]
            .filter { $0.amount > 0 }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Xarajat tarkibi").font(.headline).foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    MoneyText(amount: s.jamiXarajat, size: 15, weight: .semibold, color: Palette.ink2)
                }
                ForEach(parts) { p in
                    ObjShareRow(title: p.id, amount: p.amount, total: s.jamiXarajat, color: p.type.color)
                }
            }
        }
    }
}

private struct ObjShareRow: View {
    let title: String
    let amount: Int
    let total: Int
    let color: Color

    private var share: Double { Double(amount) / Double(max(total, 1)) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.subheadline).foregroundStyle(Palette.ink2).lineLimit(1)
                Spacer(minLength: 8)
                Text(Fmt.money(amount)).font(.money(15)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(verbatim: "\(Int((share * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(minWidth: 36, alignment: .trailing)
            }
            ProgressBar(value: share, color: color, height: 4)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ustalar, magazinlar, obyekt egalari

private struct ObjWorkersSection: View {
    let rows: [ObjectDetail.WorkerRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Ustalar")
            ObjBox {
                ObjRows(items: rows, inset: 68) { w in
                    NavigationLink(value: Route.worker(w.id)) { row(w) }
                        .buttonStyle(ObjRowStyle())
                }
            }
        }
    }

    private func row(_ w: ObjectDetail.WorkerRow) -> some View {
        HStack(spacing: 12) {
            Avatar(name: w.name, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                if let sp = ObjText.value(w.specialty) {
                    Text(sp).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Text(detail(w)).font(.caption).foregroundStyle(Palette.ink2).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            ObjDebtText(amount: w.qarz)
            ObjChevron()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func detail(_ w: ObjectDetail.WorkerRow) -> String {
        var p = ["Haqi " + Fmt.compact(w.haqi)]
        if w.ozPuliga > 0 { p.append("mol " + Fmt.compact(w.ozPuliga)) }
        p.append("berilgan " + Fmt.compact(w.tolangan))
        return p.joined(separator: " · ")
    }
}

private struct ObjShopsSection: View {
    let rows: [ObjectDetail.ShopRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Magazinlar")
            ObjBox {
                ObjRows(items: rows, inset: 68) { m in
                    NavigationLink(value: Route.shop(m.id)) { row(m) }
                        .buttonStyle(ObjRowStyle())
                }
            }
        }
    }

    private func row(_ m: ObjectDetail.ShopRow) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "storefront.fill", color: Palette.blue, soft: Palette.blueSoft, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text("Olingan " + Fmt.compact(m.olingan) + " · to‘langan " + Fmt.compact(m.tolangan))
                    .font(.caption).foregroundStyle(Palette.ink2).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            ObjDebtText(amount: m.qarz, negativeLabel: "ortiqcha")
            ObjChevron()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

private struct ObjClientsSection: View {
    let rows: [ObjectDetail.ClientRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Obyekt egalari")
            ObjBox {
                ObjRows(items: rows, inset: 68) { c in row(c) }
            }
            Text("Obyekt egasi ilovada faqat o‘zi bergan pul va real xarajatni ko‘radi.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 4)
        }
    }

    private func row(_ c: ObjectDetail.ClientRow) -> some View {
        HStack(spacing: 12) {
            Avatar(name: c.name, size: 42, color: Palette.teal, soft: Palette.tealSoft)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    if !c.active { ObjTag(text: "faol emas") }
                }
                if c.telegram > 0 {
                    ObjIconLine(symbol: "paperplane.fill", text: "Telegram ulangan", font: .caption, color: Palette.green)
                } else {
                    ObjIconLine(symbol: "paperplane", text: "Telegram ulanmagan", font: .caption)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .opacity(c.active ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}
