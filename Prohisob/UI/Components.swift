// Umumiy UI qismlari — hamma ekranlar shulardan foydalanadi (bir xil ko'rinish uchun):
// Card, MoneyText, StatTile, IconBadge, TypeIcon, EntryRow, StatusBadge, Chip, Avatar, InfoRow, SectionHeader,
// BrandButton, AmountField, ProgressBar, EmptyState, ErrorState, LoadingState, ToastView, AuthImage, ReceiptViewer, PhoneButton.
import SwiftUI
import UIKit
import PDFKit

// MARK: - Karta

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
    }
}

// MARK: - Summa

/// 1 250 000 so‘m — raqamlar yumaloq va teng kenglikda; sig'masa kichrayadi
struct MoneyText: View {
    let amount: Int
    var size: CGFloat = 17
    var weight: Font.Weight = .semibold
    var color: Color = Palette.ink
    var currency = true
    /// «+» belgisi bilan (kirim)
    var signed = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(signed ? Fmt.signed(amount) : Fmt.money(amount))
                .font(.money(size, weight))
                .foregroundStyle(color)
            if currency {
                Text("so‘m")
                    .font(.system(size: max(11, size * 0.55), weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Belgilar

/// Yumaloq burchakli rangli fon ustida SF Symbol
struct IconBadge: View {
    let symbol: String
    var color: Color = Palette.ink
    var soft: Color = Palette.surface2
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(soft, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Amal turi belgisi
struct TypeIcon: View {
    let type: EntryType?
    var size: CGFloat = 38

    var body: some View {
        IconBadge(symbol: type?.symbol ?? "circle.fill", color: type?.color ?? Palette.gray,
                  soft: type?.softColor ?? Palette.graySoft, size: size)
    }
}

/// Ism bosh harflari (usta, mijoz, xodim)
struct Avatar: View {
    let name: String
    var size: CGFloat = 40
    var color: Color = Palette.ink
    var soft: Color = Palette.brandSoft

    private var initials: String {
        // faqat harflar: «Demo (App Store)» → «DA», «“Nur Savdo” MChJ» → «NS»
        let parts = name.split(separator: " ").map { $0.filter(\.isLetter) }.filter { !$0.isEmpty }.prefix(2)
        let s = parts.compactMap { $0.first.map(String.init) }.joined()
        return s.isEmpty ? "?" : s.uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(soft, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Obyekt holati: ● Ish ketyapti / Tugagan / To'xtatilgan
struct StatusBadge: View {
    let status: ObjectStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(status.color).frame(width: 7, height: 7)
            Text(status.label).font(.caption.weight(.semibold)).foregroundStyle(status.color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Ko'rsatkich plitkasi

struct StatTile: View {
    let title: String
    let amount: Int
    var symbol: String = "circle"
    var color: Color = Palette.ink
    var soft: Color = Palette.surface2
    var amountColor: Color = Palette.ink
    var note: String?

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                IconBadge(symbol: symbol, color: color, soft: soft, size: 30)
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                MoneyText(amount: amount, size: 19, weight: .bold, color: amountColor)
                if let note {
                    Text(note).font(.caption2).foregroundStyle(Palette.muted).lineLimit(2)
                }
            }
        }
    }
}

// MARK: - Yozuv qatori

/// Ro'yxatdagi bitta yozuv: tur belgisi, «nima uchun», obyekt · usta · magazin, summa (kirim yashil «+», chiqim «−»,
/// hisoblangan — binafsha, belgisiz), chek soni
struct EntryRow: View {
    let entry: Entry
    var showContext = true
    var showDate = false

    var body: some View {
        HStack(spacing: 12) {
            TypeIcon(type: entry.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.kind?.signedText(entry.amount) ?? Fmt.money(entry.amount))
                    .font(.money(15))
                    .foregroundStyle(entry.kind?.amountColor ?? Palette.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if entry.cheklar > 0 {
                        Label("\(entry.cheklar)", systemImage: "paperclip").labelStyle(.titleAndIcon)
                    }
                    if showDate { Text(Fmt.day(entry.date)) }
                }
                .font(.caption2)
                .foregroundStyle(Palette.muted)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let kind = entry.kind?.short ?? entry.type
        let ctx = showContext ? entry.context : ""
        if entry.title?.isEmpty == false {
            return ctx.isEmpty ? kind : kind + " · " + ctx
        }
        return ctx.isEmpty ? Fmt.day(entry.date) : ctx
    }
}

// MARK: - Kichik qismlar

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.top, 8)
    }
}

/// Filtr chipi
struct Chip: View {
    let title: String
    var symbol: String?
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)) }
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Palette.onBrand : Palette.ink2)
            .background(selected ? Palette.brand : Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Palette.line, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Chapda nom, o'ngda qiymat
struct InfoRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundStyle(Palette.muted)
            Spacer(minLength: 12)
            value.font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}

extension InfoRow where Value == Text {
    init(_ label: String, _ text: String) {
        self.label = label
        self.value = Text(text)
    }
}

/// Ingichka chiziqli progress (masalan shartnomadan olingan qism)
struct ProgressBar: View {
    let value: Double            // 0…1
    var color: Color = Palette.green
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surface2)
                Capsule().fill(color).frame(width: max(height, g.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityValue("\(Int((min(max(value, 0), 1)) * 100)) foiz")
    }
}

/// Asosiy (brend) tugma: sariq, siyoh matn, butun kenglik
struct BrandButton: View {
    let title: String
    var symbol: String?
    var loading = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading {
                    ProgressView().tint(Palette.onBrand)
                } else if let symbol {
                    Image(systemName: symbol).font(.body.weight(.semibold))
                }
                Text(title).font(.body.weight(.bold))
            }
            .foregroundStyle(Palette.onBrand)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Palette.brand.opacity(disabled ? 0.45 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(loading || disabled)
    }
}

/// Bosilganda biroz kichrayadi
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Summa kiritish: yozilayotganda 1 500 000 ko'rinishida guruhlanadi, ostida qisqa yozuv (1,5 mln so'm).
/// Qiymat: Fmt.parseAmount(text)
struct AmountField: View {
    let title: String
    @Binding var text: String
    var placeholder = "0"
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField(placeholder, text: $text)
                    .keyboardType(.numberPad)
                    .font(.money(large ? 34 : 20, .bold))
                    .foregroundStyle(Palette.ink)
                    .onChange(of: text) { old, v in
                        // faqat oxiriga yozilganda/o'chirilganda guruhlanadi — o'rtadan tahrirlaganda kursor sakramasin
                        let d = { (s: String) in s.filter(\.isNumber) }
                        guard d(v).hasPrefix(d(old)) || d(old).hasPrefix(d(v)) else { return }
                        let g = Fmt.groupTyping(v)
                        if g != v { text = g }
                    }
                Text("so‘m").font(.headline).foregroundStyle(Palette.muted)
            }
            if let v = Fmt.parseAmount(text), v >= 1000 {
                Text(Fmt.compact(v) + " so‘m").font(.caption).foregroundStyle(Palette.muted)
            }
        }
    }
}

/// Telefon raqami — bosilsa qo'ng'iroq
struct PhoneButton: View {
    let phone: String

    var body: some View {
        if let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
            Link(destination: url) {
                Label(phone, systemImage: "phone.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
    }
}

// MARK: - Holatlar

struct LoadingState: View {
    var text = "Yuklanmoqda…"
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(text).font(.subheadline).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let message { Text(message) }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(Palette.brand).foregroundStyle(Palette.onBrand)
            }
        }
    }
}

struct ErrorState: View {
    let error: Error
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label((error as? APIError) == .offline ? "Internet yo‘q" : "Xatolik", systemImage: (error as? APIError) == .offline ? "wifi.slash" : "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Qayta urinish") { Task { await retry() } }.buttonStyle(.bordered)
        }
    }
}

/// Ekran tepasida qisqa xabar (Session.show)
struct ToastView: View {
    @Environment(Session.self) private var session

    var body: some View {
        if let t = session.toast {
            HStack(spacing: 10) {
                Image(systemName: t.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(t.isError ? Palette.red : Palette.green)
                Text(t.text).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassBackground(Capsule(), fallback: .regularMaterial)
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture { session.toast = nil }
            .id(t.id)
        }
    }
}

// MARK: - Chek rasmlari

/// Serverdagi chek (rasm yoki PDF). path: "/api/files/12" (prorab) yoki "/api/mijoz/files/12" (obyekt egasi)
struct ReceiptRef: Identifiable, Hashable {
    let id: Int
    let path: String
    let isPDF: Bool
    var name: String = ""

    init(file: FileInfo, mijoz: Bool = false) {
        id = file.id
        path = (mijoz ? "/api/mijoz/files/" : "/api/files/") + String(file.id)
        isPDF = file.isPDF
        name = file.origName ?? ""
    }
}

/// Token bilan yuklanadigan rasm (chek kichik nusxasi)
struct AuthImage: View {
    let path: String
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Palette.surface2
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if failed {
                Image(systemName: "photo.badge.exclamationmark").foregroundStyle(Palette.muted)
            } else {
                ProgressView()
            }
        }
        .clipped()
        .task(id: path) {
            failed = false
            do {
                let d = try await API.shared.data(path)
                let img = await Task.detached(priority: .userInitiated) { UIImage(data: d)?.preparingThumbnail(of: CGSize(width: 900, height: 900)) ?? UIImage(data: d) }.value
                image = img
                failed = img == nil
            } catch is CancellationError {
                // ekran yopildi — xato emas
            } catch { failed = true }
        }
    }
}

/// Chek kichik ko'rinishi (ro'yxatda): rasm yoki PDF belgisi
struct ReceiptThumb: View {
    let ref: ReceiptRef
    var size: CGFloat = 84

    var body: some View {
        Group {
            if ref.isPDF {
                VStack(spacing: 4) {
                    Image(systemName: "doc.richtext.fill").font(.title2).foregroundStyle(Palette.red)
                    Text("PDF").font(.caption2.weight(.bold)).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.surface2)
            } else {
                AuthImage(path: ref.path)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
    }
}

/// To'liq ekranda cheklar: varaqlash, kattalashtirish (ikki barmoq / ikki marta bosish), PDF, ulashish
struct ReceiptViewer: View {
    let refs: [ReceiptRef]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    init(refs: [ReceiptRef], start: Int = 0) {
        self.refs = refs
        _index = State(initialValue: min(max(0, start), max(0, refs.count - 1)))
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(refs.enumerated()), id: \.element.id) { i, r in
                    ReceiptPage(ref: r).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: refs.count > 1 ? .automatic : .never))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(refs.count > 1 ? "Chek \(index + 1) / \(refs.count)" : "Chek")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Yopish") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ReceiptPage: View {
    let ref: ReceiptRef
    @State private var data: Data?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let data {
                if ref.isPDF {
                    PDFViewer(data: data)
                } else if let img = UIImage(data: data) {
                    ZoomableImage(image: img)
                } else {
                    Text("Faylni ochib bo‘lmadi").foregroundStyle(.white)
                }
            } else if failed {
                Label("Yuklab bo‘lmadi", systemImage: "exclamationmark.triangle").foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            failed = false
            do { data = try await API.shared.data(ref.path) } catch is CancellationError {} catch { failed = true }
        }
    }
}

/// UIScrollView asosidagi kattalashtiriladigan rasm
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let sv = UIScrollView()
        sv.minimumZoomScale = 1
        sv.maximumZoomScale = 5
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false
        sv.delegate = context.coordinator
        sv.backgroundColor = .black
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isUserInteractionEnabled = true
        sv.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalTo: sv.frameLayoutGuide.widthAnchor),
            iv.heightAnchor.constraint(equalTo: sv.frameLayoutGuide.heightAnchor),
            iv.leadingAnchor.constraint(equalTo: sv.contentLayoutGuide.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: sv.contentLayoutGuide.trailingAnchor),
            iv.topAnchor.constraint(equalTo: sv.contentLayoutGuide.topAnchor),
            iv.bottomAnchor.constraint(equalTo: sv.contentLayoutGuide.bottomAnchor),
        ])
        context.coordinator.imageView = iv
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        sv.addGestureRecognizer(tap)
        return sv
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let sv = g.view as? UIScrollView else { return }
            if sv.zoomScale > 1 {
                sv.setZoomScale(1, animated: true)
            } else {
                let p = g.location(in: imageView)
                let size = CGSize(width: sv.bounds.width / 2.5, height: sv.bounds.height / 2.5)
                sv.zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}

/// PDF chek
struct PDFViewer: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.backgroundColor = .black
        v.document = PDFDocument(data: data)
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

// MARK: - Rasmni yuklashga tayyorlash

enum ImagePrep {
    /// Chek rasmi: 1600 px gacha kichraytirib, JPEG (sayt bilan bir xil) — trafik va joy tejaladi
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let s = image.size
        let k = min(1, maxSide / max(s.width, s.height))
        let target = CGSize(width: (s.width * k).rounded(), height: (s.height * k).rounded())
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let out = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return out.jpegData(compressionQuality: quality)
    }

    static func upload(_ image: UIImage, index: Int = 0) -> UploadFile? {
        guard let d = jpeg(image) else { return nil }
        return UploadFile(data: d, filename: "chek-\(index)-\(UUID().uuidString.prefix(8)).jpg", mime: "image/jpeg")
    }
}
