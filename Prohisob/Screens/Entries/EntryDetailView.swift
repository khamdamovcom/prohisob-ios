// Yozuv sahifasi (Route.entry): tur, summa, sana, «nima uchun», izoh, obyekt/usta/magazin (havola), kim va qayerdan
// kiritgani, bog'liq yozuv (xarid ↔ darhol to'langan qism), cheklar (ko'rish, qo'shish: galereya/kamera/PDF, o'chirish),
// yozuvni o'chirish.
import SwiftUI
import UIKit

struct EntryDetailView: View {
    let id: Int

    init(id: Int) {
        self.id = id
    }

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var detail: EntryDetail?
    @State private var error: Error?
    @State private var deleted = false
    @State private var deleting = false
    @State private var confirmDelete = false
    @State private var fileToDelete: FileInfo?
    @State private var viewer: EntViewerItem?
    @State private var source: EntAttachSource?
    @State private var preparing = false
    @State private var uploading = 0

    private var canDelete: Bool {
        guard let d = detail else { return false }
        return session.canDelete(createdBy: d.createdBy)
    }

    var body: some View {
        content
            .background(Palette.bg)
            .navigationTitle("Yozuv")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if deleting {
                        ProgressView()
                    } else if canDelete {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("O‘chirish", systemImage: "trash")
                        }
                        .accessibilityLabel("Yozuvni o‘chirish")
                    }
                }
            }
            .task(id: session.dataVersion) { await load() }
            .modifier(EntAttachSources(source: $source, busy: $preparing, limit: EntPrep.maxFiles,
                                       onPicked: { picked in Task { await upload(picked) } },
                                       onError: { session.show($0, error: true) }))
            .fullScreenCover(item: $viewer) { v in
                ReceiptViewer(refs: v.refs, start: v.start)
            }
            .alert("Yozuvni o‘chirasizmi?", isPresented: $confirmDelete) {
                Button("O‘chirish", role: .destructive) { Task { await deleteEntry() } }
                Button("Bekor qilish", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
            .alert("Chekni o‘chirasizmi?", isPresented: fileAlert, presenting: fileToDelete) { f in
                Button("O‘chirish", role: .destructive) { Task { await deleteFile(f) } }
                Button("Bekor qilish", role: .cancel) {}
            } message: { _ in
                Text("Chek fayli serverdan o‘chadi. Buni ortga qaytarib bo‘lmaydi.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let d = detail {
            EntDetailList(d: d, canDelete: canDelete, preparing: preparing, uploading: uploading, source: $source,
                          open: { i in
                              viewer = EntViewerItem(refs: d.cheklar.map { ReceiptRef(file: $0) }, start: i)
                          },
                          deleteFile: { fileToDelete = $0 },
                          reload: { await load() })
        } else if let error {
            ErrorState(error: error) { await load() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LoadingState()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var fileAlert: Binding<Bool> {
        Binding(get: { fileToDelete != nil }, set: { if !$0 { fileToDelete = nil } })
    }

    private var deleteMessage: String {
        guard let d = detail else { return "" }
        let title = (d.title?.isEmpty == false ? d.title : nil) ?? d.kind?.short ?? d.type
        let paid = d.kind == .xarid ? d.bogliq.filter { $0.kind == .magazinTolov }.reduce(0) { $0 + $1.amount } : nil
        return EntText.deleteMessage(kind: d.kind, title: title, amount: d.amount, linkedPaid: paid)
    }

    // MARK: - Ma'lumot

    private func load() async {
        guard !deleted else { return }
        do {
            let d: EntryDetail = try await API.shared.get("/api/entries/\(id)")
            detail = d
            error = nil
        } catch is CancellationError {
        } catch {
            if detail == nil {
                self.error = error
            } else {
                session.show(error.localizedDescription, error: true)
            }
        }
    }

    private func upload(_ picked: [EntPicked]) async {
        guard !picked.isEmpty else { return }
        uploading = picked.count
        defer { uploading = 0 }
        do {
            _ = try await API.shared.upload(entryId: id, files: picked.map(\.file))
            session.changed()
            session.show(picked.count == 1 ? "Chek qo‘shildi" : "\(picked.count) ta chek qo‘shildi")
        } catch {
            session.show(error.localizedDescription, error: true)
        }
    }

    private func deleteFile(_ f: FileInfo) async {
        do {
            try await API.shared.delete("/api/files/\(f.id)")
            session.changed()
            session.show("Chek o‘chirildi")
        } catch {
            session.show(error.localizedDescription, error: true)
        }
    }

    private func deleteEntry() async {
        deleting = true
        defer { deleting = false }
        do {
            try await API.shared.delete("/api/entries/\(id)")
            deleted = true
            dismiss()
            session.changed()
            session.show("Yozuv o‘chirildi")
        } catch {
            session.show(error.localizedDescription, error: true)
        }
    }
}

private struct EntViewerItem: Identifiable {
    let id = UUID()
    let refs: [ReceiptRef]
    let start: Int
}

// MARK: - Sahifa tarkibi

private struct EntDetailList: View {
    let d: EntryDetail
    let canDelete: Bool
    let preparing: Bool
    let uploading: Int
    @Binding var source: EntAttachSource?
    let open: (Int) -> Void
    let deleteFile: (FileInfo) -> Void
    let reload: () async -> Void

    private var title: String? { d.title?.isEmpty == false ? d.title : nil }
    private var note: String? { d.note?.isEmpty == false ? d.note : nil }
    private var hasLinks: Bool { d.objectId != nil || d.workerId != nil || d.shopId != nil }

    var body: some View {
        List {
            Section {
                EntHero(d: d)
            }
            .listRowBackground(Palette.surface)

            if title != nil || note != nil {
                Section {
                    if let title {
                        EntTextRow(label: "Nima uchun", text: title)
                    }
                    if let note {
                        EntTextRow(label: "Izoh", text: note)
                    }
                }
                .listRowBackground(Palette.surface)
            }

            if hasLinks {
                Section {
                    links
                }
                .listRowBackground(Palette.surface)
            }

            if !d.bogliq.isEmpty {
                Section {
                    ForEach(d.bogliq) { l in
                        NavigationLink(value: Route.entry(l.id)) {
                            EntLinkedRow(l: l)
                        }
                    }
                } header: {
                    Text("Bog‘liq yozuv")
                } footer: {
                    Text(d.kind == .xarid ? "Xarid paytida darhol to‘langan qism" : "Shu to‘lov bilan birga yozilgan xarid")
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                EntReceipts(d: d, canDelete: canDelete, preparing: preparing, uploading: uploading, source: $source,
                            open: open, deleteFile: deleteFile)
            } header: {
                Text(d.cheklar.isEmpty ? "Cheklar" : "Cheklar · \(d.cheklar.count)")
            }
            .listRowBackground(Palette.surface)

            Section {
                info
            } header: {
                Text("Tafsilot")
            }
            .listRowBackground(Palette.surface)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .refreshable { await reload() }
    }

    @ViewBuilder
    private var links: some View {
        if let oid = d.objectId {
            NavigationLink(value: Route.object(oid)) {
                EntLinkLabel(symbol: EntryType.Field.object.symbol, color: Palette.ink2, soft: Palette.surface2,
                             title: "Obyekt", value: d.objectName ?? "Obyekt №\(oid)")
            }
        }
        if let wid = d.workerId {
            NavigationLink(value: Route.worker(wid)) {
                EntLinkLabel(symbol: EntryType.Field.worker.symbol, color: Palette.purple, soft: Palette.purpleSoft,
                             title: "Usta", value: d.workerName ?? "Usta №\(wid)")
            }
        }
        if let sid = d.shopId {
            NavigationLink(value: Route.shop(sid)) {
                EntLinkLabel(symbol: EntryType.Field.shop.symbol, color: Palette.blue, soft: Palette.blueSoft,
                             title: "Magazin", value: d.shopName ?? "Magazin №\(sid)")
            }
        }
    }

    @ViewBuilder
    private var info: some View {
        if let who = (d.userName?.isEmpty == false ? d.userName : nil) ?? d.username {
            InfoRow("Kim kiritdi", who)
        }
        if let src = EntText.source(d.source) {
            InfoRow("Manba", src)
        }
        if let c = d.createdAt, !c.isEmpty {
            InfoRow("Kiritilgan", Fmt.stamp(c))
        }
        InfoRow("Yozuv raqami", "№\(d.id)")
    }
}

/// Tepadagi katta qism: tur belgisi, nomi, summa, (hisoblangan bo'lsa) qarz izohi, sana
private struct EntHero: View {
    let d: EntryDetail

    private var paidNow: Int {
        d.bogliq.filter { $0.kind == .magazinTolov }.reduce(0) { $0 + $1.amount }
    }

    private var fullyPaid: Bool { d.kind == .xarid && paidNow > 0 && paidNow >= d.amount }

    var body: some View {
        VStack(spacing: 10) {
            TypeIcon(type: d.kind, size: 64)
            Text(d.kind?.label ?? d.type)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(d.kind?.signedText(d.amount) ?? Fmt.money(d.amount))
                    .font(.money(40, .bold))
                    .foregroundStyle(d.kind?.amountColor ?? Palette.ink)
                Text("so‘m")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.muted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            if d.kind?.flow == .hisoblangan {
                debtNote
            }
            Label(Fmt.dayHeader(d.date), systemImage: "calendar")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var debtNote: some View {
        VStack(spacing: 5) {
            Text(fullyPaid ? "To‘langan" : "Qarzga yozildi")
                .font(.caption.weight(.bold))
                .foregroundStyle(fullyPaid ? Palette.green : Palette.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(fullyPaid ? Palette.greenSoft : Palette.purpleSoft, in: Capsule())
            Text(debtText)
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var debtText: String {
        switch d.kind {
        case .xarid?:
            if fullyPaid { return "Magazindan olindi va shu zahoti to‘liq to‘landi" }
            if paidNow > 0 {
                return "Shu zahoti \(Fmt.som(paidNow)) to‘landi, qolgan \(Fmt.som(d.amount - paidNow)) magazinga qarz bo‘lib yozildi"
            }
            return "Nasiya — pul berilmadi, magazinga qarz bo‘lib yozildi"
        case .ustaHaqi?:
            return "Pul berilmadi — ustaga hisoblangan haq qarz bo‘lib yozildi"
        case .ustaXarid?:
            return "Usta o‘z puliga oldi — ustaga qarz bo‘lib yozildi"
        default:
            return "Pul berilmadi — qarz bo‘lib yozildi"
        }
    }
}

/// Sarlavha ustida, matn ostida (izoh to'liq, belgilab nusxa olish mumkin)
private struct EntTextRow: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.muted)
            Text(text)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }
}

/// Obyekt / usta / magazin havolasi
private struct EntLinkLabel: View {
    let symbol: String
    let color: Color
    let soft: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: color, soft: soft, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.muted)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Bog'liq yozuv qatori
private struct EntLinkedRow: View {
    let l: EntryDetail.Linked

    var body: some View {
        HStack(spacing: 12) {
            TypeIcon(type: l.kind, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text((l.title?.isEmpty == false ? l.title : nil) ?? l.kind?.short ?? l.type)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text([l.kind?.short, l.date.map { Fmt.day($0) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(l.kind?.signedText(l.amount) ?? Fmt.money(l.amount))
                .font(.money(15))
                .foregroundStyle(l.kind?.amountColor ?? Palette.ink)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Cheklar to'ri + qo'shish tugmalari
private struct EntReceipts: View {
    let d: EntryDetail
    let canDelete: Bool
    let preparing: Bool
    let uploading: Int
    @Binding var source: EntAttachSource?
    let open: (Int) -> Void
    let deleteFile: (FileInfo) -> Void

    let columns = [GridItem(.adaptive(minimum: 84, maximum: 96), spacing: 10, alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if d.cheklar.isEmpty {
                Label("Chek biriktirilmagan", systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(Array(d.cheklar.enumerated()), id: \.element.id) { i, f in
                        thumb(i, f)
                    }
                }
            }
            if uploading > 0 || preparing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(uploading > 0 ? "\(uploading) ta fayl yuklanmoqda…" : "Tayyorlanmoqda…")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
            }
            EntAttachButtons(source: $source, disabled: uploading > 0 || preparing)
        }
        .padding(.vertical, 6)
    }

    private func thumb(_ i: Int, _ f: FileInfo) -> some View {
        Button {
            open(i)
        } label: {
            ReceiptThumb(ref: ReceiptRef(file: f), size: 84)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                open(i)
            } label: {
                Label("Ochish", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            if canDelete {
                Button(role: .destructive) {
                    deleteFile(f)
                } label: {
                    Label("Chekni o‘chirish", systemImage: "trash")
                }
            }
        }
        .accessibilityLabel(f.isPDF ? "PDF chek \(i + 1)" : "Chek rasmi \(i + 1)")
        .accessibilityHint(canDelete ? "Ochish uchun bosing, o‘chirish uchun bosib turing" : "Ochish uchun bosing")
    }
}
