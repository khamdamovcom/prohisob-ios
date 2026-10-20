// Formatlash: so'm (1 250 000 so'm), qisqa summa (1,25 mln), o'zbekcha sanalar (17-oktabr), summa kiritish («1.5mln», «500k»).
// Server sanalari — "yyyy-MM-dd" (yozuv sanasi) va "yyyy-MM-dd HH:mm:ss" (UTC, created_at).
import Foundation

enum Fmt {
    static let months = ["yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avgust", "sentabr", "oktabr", "noyabr", "dekabr"]
    static let weekdays = ["yakshanba", "dushanba", "seshanba", "chorshanba", "payshanba", "juma", "shanba"]   // Calendar: 1 = yakshanba

    private static let grouping: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{2009}"   // ingichka bo'sh joy: 1 250 000
        f.groupingSize = 3
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        return f
    }()

    /// 1250000 → "1 250 000"
    static func money(_ v: Int) -> String {
        let s = grouping.string(from: NSNumber(value: abs(v))) ?? String(abs(v))
        return v < 0 ? "−" + s : s
    }

    /// 1250000 → "1 250 000 so'm"
    static func som(_ v: Int) -> String { money(v) + " so‘m" }

    /// Belgili: +1 250 000 / −1 250 000
    static func signed(_ v: Int) -> String { (v > 0 ? "+" : "") + money(v) }

    /// Qisqa: 1 250 000 → "1,25 mln", 850 000 → "850 ming", 2 100 000 000 → "2,1 mlrd"
    static func compact(_ v: Int) -> String {
        let a = Double(abs(v))
        let sign = v < 0 ? "−" : ""
        func d(_ x: Double, _ unit: String) -> String {
            let r = (x * 100).rounded() / 100
            var s = r == r.rounded() ? String(Int(r)) : String(format: "%.2f", r)
            if s.contains(".") { while s.hasSuffix("0") { s.removeLast() } }
            if s.hasSuffix(".") { s.removeLast() }
            return sign + s.replacingOccurrences(of: ".", with: ",") + " " + unit
        }
        if a >= 1_000_000_000 { return d(a / 1_000_000_000, "mlrd") }
        if a >= 1_000_000 { return d(a / 1_000_000, "mln") }
        if a >= 1_000 { return d(a / 1_000, "ming") }
        return sign + String(Int(a))
    }

    // MARK: sanalar

    private static let apiDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let apiStamp: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    /// Date → "2026-10-17" (serverga yuborish uchun)
    static func apiDate(_ d: Date) -> String { apiDay.string(from: d) }
    /// "2026-10-17" → Date
    static func parseDay(_ s: String?) -> Date? {
        guard let s, s.count >= 10 else { return nil }
        return apiDay.date(from: String(s.prefix(10)))
    }
    /// "2026-10-20 10:16:03" (UTC) → Date
    static func parseStamp(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return apiStamp.date(from: String(s.prefix(19)).replacingOccurrences(of: "T", with: " "))
    }

    /// "2026-10-17" → "17-oktabr" (joriy yil bo'lmasa — "17-oktabr, 2025")
    static func day(_ s: String?) -> String {
        guard let d = parseDay(s) else { return s ?? "" }
        return day(d)
    }

    static func day(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        let now = cal.component(.year, from: Date())
        let base = "\(c.day ?? 1)-\(months[(c.month ?? 1) - 1])"
        return c.year == now ? base : base + ", \(c.year ?? now)"
    }

    /// Ro'yxatdagi kun sarlavhasi: "Bugun", "Kecha", "17-oktabr, juma"
    static func dayHeader(_ s: String?) -> String {
        guard let d = parseDay(s) else { return s ?? "" }
        if cal.isDateInToday(d) { return "Bugun" }
        if cal.isDateInYesterday(d) { return "Kecha" }
        return day(d) + ", " + weekdays[cal.component(.weekday, from: d) - 1]
    }

    /// "2026-10" → "Oktabr 2026"
    static func month(_ ym: String) -> String {
        let p = ym.split(separator: "-")
        guard p.count >= 2, let m = Int(p[1]), (1...12).contains(m) else { return ym }
        return months[m - 1].capitalized + " " + p[0]
    }

    /// "2026-10" → "Okt" (grafik o'qi uchun)
    static func monthShort(_ ym: String) -> String {
        let p = ym.split(separator: "-")
        guard p.count >= 2, let m = Int(p[1]), (1...12).contains(m) else { return ym }
        return String(months[m - 1].prefix(3)).capitalized
    }

    /// created_at → "20-oktabr, 15:16" (mahalliy vaqt)
    static func stamp(_ s: String?) -> String {
        guard let d = parseStamp(s) else { return s ?? "" }
        let t = cal.dateComponents([.hour, .minute], from: d)
        return day(d) + String(format: ", %02d:%02d", t.hour ?? 0, t.minute ?? 0)
    }

    // MARK: summa kiritish

    /// "1 500 000", "1.5mln", "1,5 mln", "500k", "500 ming", "2 mlrd", "$" belgilarsiz → so'm (butun). Noto'g'ri bo'lsa — nil.
    static func parseAmount(_ raw: String) -> Int? {
        var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        s = s.replacingOccurrences(of: "so‘m", with: "").replacingOccurrences(of: "so'm", with: "").replacingOccurrences(of: "som", with: "")
        var mult: Double = 1
        let units: [(String, Double)] = [("mlrd", 1e9), ("milliard", 1e9), ("mln", 1e6), ("million", 1e6), ("m", 1e6),
                                          ("ming", 1e3), ("k", 1e3), ("к", 1e3), ("млн", 1e6), ("тыс", 1e3)]
        for (u, m) in units where s.hasSuffix(u) {
            mult = m
            s = String(s.dropLast(u.count))
            break
        }
        s = s.filter { !$0.isWhitespace && $0 != "\u{2009}" && $0 != "\u{00A0}" }
        if mult == 1 {
            // butun summa: guruh ajratuvchilari (1.500.000 / 1,500,000) olib tashlanadi
            let cleaned = s.filter { $0 != "." && $0 != "," }
            guard !cleaned.isEmpty, cleaned.count <= 15, cleaned.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
            return Int(cleaned)
        }
        s = s.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(s), v > 0 else { return nil }
        return Int((v * mult).rounded())
    }

    /// Kiritish paytida guruhlab ko'rsatish: "1500000" → "1 500 000" (faqat raqamlar bo'lsa)
    static func groupTyping(_ s: String) -> String {
        let rest = s.filter { !$0.isWhitespace && $0 != "\u{2009}" }
        guard !rest.isEmpty, rest.count <= 15, rest.allSatisfy({ ("0"..."9").contains($0) }), let v = Int(rest) else { return s }
        return money(v)
    }
}
