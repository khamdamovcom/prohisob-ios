// Yozuvlar bo'limi uchun umumiy yordamchilar: davr tanlovi (Bugun / Bu hafta …), kirim-chiqim yig'indisi, matnlar va
// chek qo'shish — galereya (PhotosPicker), kamera (UIImagePickerController), PDF (fileImporter). Yozuv sahifasi va
// «Yangi yozuv» oynasi ishlatadi. Rasmlar ImagePrep bilan siqiladi (1600 px, JPEG).
import SwiftUI
import UIKit
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

// MARK: - Davr

enum EntPeriod: String, CaseIterable, Identifiable, Hashable {
    case today, week, month, lastMonth, all, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Bugun"
        case .week: return "Bu hafta"
        case .month: return "Bu oy"
        case .lastMonth: return "O‘tgan oy"
        case .all: return "Hammasi"
        case .custom: return "Boshqa…"
        }
    }

    /// So'rov uchun sanalar ("yyyy-MM-dd"); «Hammasi» — ikkalasi nil
    func range(from customFrom: Date, to customTo: Date, now: Date = Date()) -> (from: String?, to: String?) {
        let cal = Fmt.cal
        func span(_ i: DateInterval?) -> (from: String?, to: String?) {
            guard let i else { return (nil, nil) }
            return (Fmt.apiDate(i.start), Fmt.apiDate(i.end.addingTimeInterval(-1)))
        }
        switch self {
        case .all:
            return (nil, nil)
        case .today:
            let d = Fmt.apiDate(now)
            return (d, d)
        case .week:
            return span(cal.dateInterval(of: .weekOfYear, for: now))
        case .month:
            return span(cal.dateInterval(of: .month, for: now))
        case .lastMonth:
            guard let prev = cal.date(byAdding: .month, value: -1, to: now) else { return (nil, nil) }
            return span(cal.dateInterval(of: .month, for: prev))
        case .custom:
            return (Fmt.apiDate(min(customFrom, customTo)), Fmt.apiDate(max(customFrom, customTo)))
        }
    }
}

// MARK: - Yig'indi

/// Yozuvlar yig'indisi pul oqimi bo'yicha: kirim, chiqim (real berilgan pul), hisoblangan (qarzga yozilgan)
struct EntSums: Equatable {
    var kirim = 0
    var chiqim = 0
    var hisoblangan = 0

    init() {}

    init<S: Sequence>(_ rows: S) where S.Element == Entry {
        for e in rows {
            switch e.kind?.flow {
            case .kirim?: kirim += e.amount
            case .chiqim?: chiqim += e.amount
            case .hisoblangan?: hisoblangan += e.amount
            case nil: break
            }
        }
    }
}

// MARK: - Matnlar

enum EntText {
    /// Sana tanlagichlar o'zbekcha bo'lsin
    static let uzLocale = Locale(identifier: "uz_Latn_UZ")

    /// Yozuv qayerdan kiritilgan
    static func source(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        switch s.lowercased() {
        case "web", "sayt", "site": return "Sayt"
        case "telegram", "bot", "tg": return "Telegram bot"
        case "ios", "iphone": return "iPhone ilova"
        case "android": return "Android ilova"
        case "app", "ilova", "mobile": return "Ilova"
        default: return s
        }
    }

    /// O'chirishni tasdiqlash matni. linkedPaid — xaridga bog'liq to'lov summasi (ma'lum bo'lsa)
    static func deleteMessage(kind: EntryType?, title: String, amount: Int, linkedPaid: Int? = nil) -> String {
        var s = "«\(title)» — \(Fmt.som(amount))."
        if kind == .xarid {
            if let p = linkedPaid, p > 0 {
                s += " Xarid bilan birga yozilgan bog‘liq to‘lov (\(Fmt.som(p))) ham o‘chadi."
            } else if linkedPaid == nil {
                s += " Xarid o‘chsa, unga bog‘liq to‘lov (shu zahoti to‘langan qism) ham o‘chadi."
            }
        }
        return s + " Buni ortga qaytarib bo‘lmaydi."
    }
}

// MARK: - Chek qo'shish

enum EntAttachSource: Hashable {
    case photos, camera, pdf
}

/// Yuklashga tayyorlangan chek: siqilgan JPEG yoki PDF + kichik ko'rinish
struct EntPicked: Identifiable, @unchecked Sendable {
    let id = UUID()
    let file: UploadFile
    let thumb: UIImage?

    var isPDF: Bool { file.mime == "application/pdf" }
}

enum EntPrep {
    /// Server chegarasi — 20 MB
    static let maxBytes = 20 << 20
    /// Bir yuklashda — 10 tagacha fayl
    static let maxFiles = 10

    /// Katta rasmni xotirani to'ldirmasdan kichraytirib o'qish (orientatsiya saqlanadi)
    static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOpts) else { return nil }
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Galereyadagi rasm baytlari → siqilgan JPEG
    static func image(data: Data, index: Int) -> EntPicked? {
        guard let img = downsample(data, maxPixel: 2000) ?? UIImage(data: data) else { return nil }
        return image(img, index: index)
    }

    /// Kamera yoki tayyor rasm → siqilgan JPEG
    static func image(_ img: UIImage, index: Int) -> EntPicked? {
        guard let f = ImagePrep.upload(img, index: index) else { return nil }
        return EntPicked(file: f, thumb: downsample(f.data, maxPixel: 240))
    }
}

/// «Galereya · Kamera · PDF» tugmalari (kamera yo'q qurilmada — yashirin)
struct EntAttachButtons: View {
    @Binding var source: EntAttachSource?
    var disabled: Bool

    init(source: Binding<EntAttachSource?>, disabled: Bool = false) {
        _source = source
        self.disabled = disabled
    }

    var body: some View {
        HStack(spacing: 8) {
            tile(.photos, title: "Galereya", symbol: "photo.on.rectangle.angled", label: "Galereyadan chek rasmi qo‘shish")
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                tile(.camera, title: "Kamera", symbol: "camera.fill", label: "Chekni suratga olish")
            }
            tile(.pdf, title: "PDF", symbol: "doc.richtext", label: "PDF chek qo‘shish")
        }
    }

    private func tile(_ s: EntAttachSource, title: String, symbol: String, label: String) -> some View {
        Button {
            source = s
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.body.weight(.semibold))
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(label)
    }
}

/// Ekran darajasidagi oynalar: galereya, kamera, PDF tanlash. Tanlanganlar tayyorlanib onPicked ga beriladi.
struct EntAttachSources: ViewModifier {
    @Binding var source: EntAttachSource?
    @Binding var busy: Bool
    let limit: Int
    let onPicked: ([EntPicked]) -> Void
    let onError: (String) -> Void

    @State private var items: [PhotosPickerItem] = []

    init(source: Binding<EntAttachSource?>, busy: Binding<Bool>, limit: Int,
         onPicked: @escaping ([EntPicked]) -> Void, onError: @escaping (String) -> Void) {
        _source = source
        _busy = busy
        self.limit = limit
        self.onPicked = onPicked
        self.onError = onError
    }

    private var maxCount: Int { max(1, min(EntPrep.maxFiles, limit)) }

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: flag(.photos), selection: $items, maxSelectionCount: maxCount, matching: .images)
            .fullScreenCover(isPresented: flag(.camera)) {
                EntCameraPicker(onImage: { camera($0) }, onClose: { source = nil })
                    .ignoresSafeArea()
            }
            .fileImporter(isPresented: flag(.pdf), allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
                pdfs(result)
            }
            .onChange(of: items) { _, picked in
                guard !picked.isEmpty else { return }
                items = []
                Task { await photos(picked) }
            }
    }

    private func flag(_ s: EntAttachSource) -> Binding<Bool> {
        Binding(
            get: { source == s },
            set: { on in
                if on { source = s } else if source == s { source = nil }
            }
        )
    }

    private func photos(_ picked: [PhotosPickerItem]) async {
        busy = true
        defer { busy = false }
        var out: [EntPicked] = []
        let base = Int.random(in: 1...899) * 10      // fayl nomlari bir-biriga to'qnashmasin
        for (i, item) in picked.prefix(maxCount).enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let index = base + i
            let p = await Task.detached(priority: .userInitiated) { EntPrep.image(data: data, index: index) }.value
            if let p { out.append(p) }
        }
        if out.count < min(picked.count, maxCount) { onError("Ba’zi rasmlarni o‘qib bo‘lmadi") }
        if !out.isEmpty { onPicked(out) }
    }

    private func camera(_ img: UIImage) {
        busy = true
        Task {
            let index = Int.random(in: 9000...9999)
            let p = await Task.detached(priority: .userInitiated) { EntPrep.image(img, index: index) }.value
            busy = false
            if let p { onPicked([p]) } else { onError("Rasmni tayyorlab bo‘lmadi") }
        }
    }

    private func pdfs(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            onError(e.localizedDescription)
        case .success(let urls):
            var out: [EntPicked] = []
            var tooBig = false
            var unreadable = false
            for url in urls.prefix(maxCount) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let d = try? Data(contentsOf: url) else { unreadable = true; continue }
                if d.count > EntPrep.maxBytes { tooBig = true; continue }
                out.append(EntPicked(file: UploadFile(data: d, filename: url.pathExtension.lowercased() == "pdf" ? url.lastPathComponent : "chek.pdf", mime: "application/pdf"), thumb: nil))
            }
            if tooBig { onError("PDF 20 MB dan katta — yuklab bo‘lmaydi") }
            else if unreadable { onError("PDF faylni o‘qib bo‘lmadi") }
            if urls.count > maxCount { onError("Bir martada \(maxCount) tagacha fayl qo‘shiladi") }
            if !out.isEmpty { onPicked(out) }
        }
    }
}

/// Kamera (UIImagePickerController) — chekni suratga olish
private struct EntCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.cameraCaptureMode = .photo
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, onClose: onClose) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let onClose: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onClose: @escaping () -> Void) {
            self.onImage = onImage
            self.onClose = onClose
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onImage(img) }
            onClose()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onClose()
        }
    }
}
