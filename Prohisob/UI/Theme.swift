// Dizayn: prohisob.com uslubi — qog'oz fon, siyoh matn, qurilish sarig'i (brend), yashil (kirim), qizil (chiqim).
// Ranglar yorug'/qorong'i mavzuga o'zi moslashadi. Shrift — tizimniki (SF Pro), summalar — yumaloq va teng kenglikdagi raqamlar.
import SwiftUI
import UIKit

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    /// Yorug' va qorong'i mavzu uchun ikki rang
    static func dyn(_ light: UInt32, _ dark: UInt32, _ la: CGFloat = 1, _ da: CGFloat = 1) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark, alpha: da) : UIColor(rgb: light, alpha: la) })
    }

    init(rgb: UInt32) { self.init(UIColor(rgb: rgb)) }
}

enum Palette {
    // fon va sirtlar
    static let bg = Color.dyn(0xF4F4EF, 0x0D1013)          // ekran foni (qog'oz)
    static let surface = Color.dyn(0xFFFFFF, 0x171B1F)     // kartalar
    static let surface2 = Color.dyn(0xEDEDE6, 0x20252A)    // ichki bloklar, maydonlar
    static let line = Color.dyn(0x171C20, 0xF2F2EC, 0.10, 0.10)
    // matn
    static let ink = Color.dyn(0x171C20, 0xF2F2EC)
    static let ink2 = Color.dyn(0x3B4248, 0xC9CCC6)
    static let muted = Color.dyn(0x667079, 0x8D959C)
    // brend
    static let brand = Color(rgb: 0xFFBC32)                // qurilish sarig'i (ikkala mavzuda bir xil)
    static let brandSoft = Color.dyn(0xFFF1D1, 0x3A2E12)
    static let onBrand = Color(rgb: 0x171C20)              // sariq ustidagi matn — doim siyoh
    static let accent = Color.dyn(0x8A5D00, 0xFFC94D)      // havolalar, tanlangan holat (sariqning o'qiladigan varianti)
    // ma'no ranglari
    static let green = Color.dyn(0x1E7F45, 0x4CC77F)       // kirim, foyda, qarz yo'q
    static let greenSoft = Color.dyn(0xE3F4EA, 0x15301F)
    static let red = Color.dyn(0xC8393B, 0xFF6F6B)         // chiqim, qarz
    static let redSoft = Color.dyn(0xFBE7E6, 0x3A1C1C)
    static let orange = Color.dyn(0xB86200, 0xFFA24D)      // ogohlantirish, ovqat
    static let orangeSoft = Color.dyn(0xFFEFDC, 0x3A2612)
    static let blue = Color.dyn(0x2459C9, 0x7FA8FF)        // magazin
    static let blueSoft = Color.dyn(0xE5EDFC, 0x18233D)
    static let purple = Color.dyn(0x6B47C2, 0xB29BFF)      // hisoblangan (qarzga yozilgan)
    static let purpleSoft = Color.dyn(0xEEE8FB, 0x271F3D)
    static let teal = Color.dyn(0x0F7C78, 0x4FD1C5)
    static let tealSoft = Color.dyn(0xDDF3F1, 0x12302E)
    static let gray = Color.dyn(0x5D6670, 0xA0A8B0)
    static let graySoft = Color.dyn(0xEBEDEF, 0x23282D)
}

extension Font {
    /// Summalar uchun: yumaloq, teng kenglikdagi raqamlar (ustunlar tekis turadi)
    static func money(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

enum Metrics {
    static let radius: CGFloat = 20          // katta kartalar
    static let radiusS: CGFloat = 14         // kichik bloklar, maydonlar
    static let pad: CGFloat = 16             // ekran chetidan
}
