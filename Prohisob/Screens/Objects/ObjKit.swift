// Obyektlar, Ustalar va Magazinlar ekranlari uchun umumiy qismlar (faqat shu uch bo'lim ishlatadi, «Obj» prefiksi):
// qatorlar kartasi, qator tugmasi uslubi, qarz yozuvi, hisob qatori, tezkor amal tugmasi, forma maydoni,
// Excel → ulashish oynasi (UIActivityViewController), oxirgi yozuvlar bo'limi.
import SwiftUI
import UIKit

// MARK: - Server javobi

/// POST/PUT javobi (obyekt / usta / magazin qatori) — bizga faqat id kerak (yo'q bo'lsa 0)
struct ObjSaved: Decodable {
    @Num var id: Int
}

extension ObjectItem {
    /// PUT /api/objects/:id uchun to'liq tana (holatni o'zgartirishda qolgan maydonlar saqlanib qoladi)
    var objBody: ObjectBody {
        ObjectBody(name: name, address: address ?? "", ownerName: ownerName ?? "", ownerPhone: ownerPhone ?? "",
                   contractAmount: contractAmount, startDate: startDate ?? "", endDate: endDate ?? "",
                   status: status, note: note ?? "")
    }
}

extension Entry {
    /// Sahifaning o'zida takrorlanadigan nomni yashirish (obyekt sahifasida — obyekt nomi, usta sahifasida — usta…)
    func objHiding(object: Bool = false, worker: Bool = false, shop: Bool = false) -> Entry {
        Entry(id: id, type: type, objectId: objectId, workerId: workerId, shopId: shopId, amount: amount, date: date,
              title: title, note: note, linkId: linkId, createdBy: createdBy, source: source, createdAt: createdAt,
              objectName: object ? nil : objectName, workerName: worker ? nil : workerName, shopName: shop ? nil : shopName,
              userName: userName, username: username, cheklar: cheklar)
    }
}

enum ObjText {
    /// Bo'sh yoki nil bo'lmasa — matn
    static func value(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "2026-07-30" … "2026-10-17" → "30-iyul – 17-oktabr"
    static func range(_ from: String?, _ to: String?) -> String? {
        let a = value(from).map { Fmt.day($0) }
        let b = value(to).map { Fmt.day($0) }
        switch (a, b) {
        case let (a?, b?): return a == b ? a : a + " – " + b
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }

    /// Qidiruv: katta-kichik harf va belgilarni farqlamay
    static func matches(_ q: String, _ fields: [String?]) -> Bool {
        let q = trim(q)
        if q.isEmpty { return true }
        return fields.contains { ($0 ?? "").localizedStandardContains(q) }
    }
}

// MARK: - Excel va ulashish

struct ObjShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Tizim ulashish oynasi (Excel faylni Telegram, Fayllar, pochta… ga yuborish)
struct ObjShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

enum ObjExport {
    /// "Yunusobod, 14-kvartal 7-uy" → "Prohisob-Yunusobod-14-kvartal-7-uy-2026-10-20.xlsx"
    static func fileName(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var cleaned = ""
        for ch in title.unicodeScalars {
            cleaned.unicodeScalars.append(allowed.contains(ch) ? ch : " ")
        }
        let words = cleaned.split(separator: " ").prefix(8).joined(separator: "-")
        return "Prohisob-" + (words.isEmpty ? "hisob" : words) + "-" + Fmt.apiDate(Date()) + ".xlsx"
    }

    /// GET /api/export.xlsx?<key>=<id> → vaqtinchalik fayl
    static func excel(_ key: String, _ id: Int, title: String) async throws -> URL {
        try await API.shared.download("/api/export.xlsx", query: [key: String(id)], filename: fileName(title))
    }
}

// MARK: - Sahifa sarlavhasi

/// Sahifadagi katta nom ko'rinib turganda tepadagi (navigatsiya) nom yashiriladi — takrorlanmasin; pastga aylantirilsa chiqadi.
/// iOS 18+ (onScrollGeometryChange); iOS 17 da nom doim ko'rinadi.
struct ObjTitleTracker: ViewModifier {
    @Binding var shown: Bool
    var threshold: CGFloat = 70

    static var tracks: Bool {
        if #available(iOS 18.0, *) { return true } else { return false }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { g in
                g.contentOffset.y + g.contentInsets.top > threshold
            } action: { _, v in
                shown = v
            }
        } else {
            content
        }
    }
}

// MARK: - Qatorlar kartasi

/// Ichki qatorlari bo'lgan karta (chetlari qirqilgan — bosilgan qator foni burchakdan chiqmaydi)
struct ObjBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) { content }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        }
    }
}

/// Qatorlar orasida ingichka chiziq
struct ObjRows<Item, Row: View>: View {
    let items: [Item]
    var inset: CGFloat = 16
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { pair in
            if pair.offset > 0 { Divider().padding(.leading, inset) }
            row(pair.element)
        }
    }
}

/// Karta ichidagi bosiladigan qator: bosilganda och fon
struct ObjRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(configuration.isPressed ? Palette.surface2 : Color.clear)
            .contentShape(Rectangle())
    }
}

struct ObjChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(Palette.muted.opacity(0.55))
            .accessibilityHidden(true)
    }
}

/// Toolbar «…» belgisi: iOS 26 — shisha doira ichida nuqtalar, oldingilarida — doirali
struct ObjMoreIcon: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            Image(systemName: "ellipsis").accessibilityLabel("Amallar")
        } else {
            Image(systemName: "ellipsis.circle").accessibilityLabel("Amallar")
        }
    }
}

/// Kichik kulrang yorliq («faol emas»)
struct ObjTag: View {
    let text: String
    var color: Color = Palette.muted
    var soft: Color = Palette.surface2

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(soft, in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}

/// Belgi + matn (manzil, sana, telefon…)
struct ObjIconLine: View {
    let symbol: String
    let text: String
    var font: Font = .footnote
    var color: Color = Palette.muted
    var lines = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(font.weight(.semibold))
                .imageScale(.small)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text).font(font).lineLimit(lines)
        }
        .foregroundStyle(color)
    }
}

/// Izoh bloki
struct ObjNoteBox: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.quote").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            Text(text).font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Metrics.radiusS, style: .continuous))
    }
}

// MARK: - Summalar

/// Qatordagi qarz: qizil summa + «qarz»; 0 — yashil «Qarz yo‘q»; manfiy — to'q sariq (avans / ortiqcha to'langan)
struct ObjDebtText: View {
    let amount: Int
    var negativeLabel = "avans"
    var size: CGFloat = 16

    var body: some View {
        if amount == 0 {
            Text("Qarz yo‘q")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.green)
                .lineLimit(1)
                .fixedSize()
        } else {
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.money(abs(amount)))
                    .font(.money(size, .bold))
                    .foregroundStyle(amount > 0 ? Palette.red : Palette.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(amount > 0 ? "qarz" : negativeLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Palette.muted)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Hisob kartasidagi qator: nomi — belgili summa
struct ObjLine: View {
    let title: String
    let amount: Int
    var sign = ""
    var color: Color = Palette.ink
    var symbol: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.footnote.weight(.semibold)).foregroundStyle(color).frame(width: 18)
                    .accessibilityHidden(true)
            }
            Text(title).font(.subheadline).foregroundStyle(Palette.ink2).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 10)
            Text((amount != 0 ? sign : "") + Fmt.money(amount))
                .font(.money(16))
                .foregroundStyle(amount == 0 ? Palette.muted : color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("so‘m").font(.caption).foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Kichik ko'rsatkich: belgi + nom, ostida summa
struct ObjMetric: View {
    let title: String
    let amount: Int
    var symbol: String?
    var color: Color = Palette.ink
    var amountColor: Color = Palette.ink
    var size: CGFloat = 19

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(color).accessibilityHidden(true)
                }
                Text(title).font(.footnote.weight(.medium)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            MoneyText(amount: amount, size: size, weight: .bold, color: amountColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Katta qarz (usta / magazin sahifasi): summa va izoh
struct ObjBigDebt: View {
    let amount: Int
    let positive: String
    let zero: String
    let negative: String

    private var color: Color { amount > 0 ? Palette.red : amount < 0 ? Palette.orange : Palette.green }
    private var caption: String { amount > 0 ? positive : amount < 0 ? negative : zero }
    private var icon: String {
        amount > 0 ? "exclamationmark.circle.fill" : amount < 0 ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("QARZ").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Palette.muted)
            MoneyText(amount: abs(amount), size: 34, weight: .bold, color: amount == 0 ? Palette.ink : color)
            Label(caption, systemImage: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Ro'yxat tepasidagi jami qarz kartasi (ustalar, magazinlar)
struct ObjTotalCard: View {
    let title: String
    let amount: Int
    let caption: String
    let symbol: String

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                    MoneyText(amount: amount, size: 30, weight: .bold, color: amount > 0 ? Palette.red : Palette.green)
                    Text(caption).font(.footnote).foregroundStyle(Palette.muted).lineLimit(2)
                }
                Spacer(minLength: 8)
                IconBadge(symbol: symbol, color: amount > 0 ? Palette.red : Palette.green,
                          soft: amount > 0 ? Palette.redSoft : Palette.greenSoft, size: 48)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tezkor amallar

/// Sahifa ichidagi tezkor amal tugmasi ko'rinishi (belgi + nom)
struct ObjActionLabel: View {
    let title: String
    let symbol: String
    let color: Color
    let soft: Color

    var body: some View {
        VStack(spacing: 7) {
            IconBadge(symbol: symbol, color: color, soft: soft, size: 38)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radiusS + 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radiusS + 2, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.radiusS + 2, style: .continuous))
    }
}

struct ObjActionTile: View {
    let title: String
    let symbol: String
    let color: Color
    let soft: Color
    let action: () -> Void

    /// Amal turi ranglari bilan
    init(_ title: String, type: EntryType, action: @escaping () -> Void) {
        self.title = title
        self.symbol = type.symbol
        self.color = type.color
        self.soft = type.softColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ObjActionLabel(title: title, symbol: symbol, color: color, soft: soft)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - Forma

/// Forma maydoni: tepasida doim ko'rinadigan nom, ichida namuna
struct ObjField: View {
    let title: String
    @Binding var text: String
    var prompt = ""
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var caps: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
            TextField(prompt, text: $text)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(caps)
                .autocorrectionDisabled(keyboard == .phonePad)
        }
        .padding(.vertical, 2)
    }
}

/// Ko'p qatorli izoh maydoni
struct ObjNoteField: View {
    @Binding var text: String
    var prompt = "Izoh"

    var body: some View {
        TextField(prompt, text: $text, axis: .vertical)
            .lineLimit(3...8)
            .foregroundStyle(Palette.ink)
    }
}

// MARK: - Oxirgi yozuvlar

/// Sahifa pastidagi «Oxirgi yozuvlar» (15 ta) + «Barcha yozuvlar (N)»
struct ObjRecentSection: View {
    let entries: [Entry]
    var hideObject = false
    var hideWorker = false
    var hideShop = false
    let filter: EntryFilter
    var limit = 15
    let onAdd: () -> Void

    private var countText: String { entries.count >= 500 ? "500+" : String(entries.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Oxirgi yozuvlar")
            if entries.isEmpty {
                empty
            } else {
                ObjBox {
                    ObjRows(items: Array(entries.prefix(limit)), inset: 64) { e in
                        NavigationLink(value: Route.entry(e.id)) {
                            EntryRow(entry: e.objHiding(object: hideObject, worker: hideWorker, shop: hideShop), showDate: true)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(ObjRowStyle())
                    }
                    Divider()
                    NavigationLink(value: Route.entries(filter)) {
                        HStack(spacing: 8) {
                            Image(systemName: "list.bullet.rectangle").font(.subheadline.weight(.semibold))
                            Text("Barcha yozuvlar (\(countText))").font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(ObjRowStyle())
                }
            }
        }
    }

    private var empty: some View {
        Card {
            VStack(spacing: 10) {
                Image(systemName: "tray").font(.title2).foregroundStyle(Palette.muted)
                Text("Hali yozuv yo‘q").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Button(action: onAdd) {
                    Label("Yozuv qo‘shish", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .secondaryButton()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }
}
