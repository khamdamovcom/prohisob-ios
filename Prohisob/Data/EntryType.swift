// Amal turlari — serverdagi src/hisob.js TYPES bilan bir xil (10 tur). Har birida: nomi, belgisi, rangi,
// qaysi maydon majburiy/ixtiyoriy (obyekt, usta, magazin) va pul oqimi (kirim / chiqim / hisoblangan — qarzga yozilgan).
import SwiftUI

enum EntryType: String, CaseIterable, Identifiable, Codable, Hashable {
    case kirim
    case qaytarish
    case ustaHaqi = "usta_haqi"
    case ustaTolov = "usta_tolov"
    case ustaXarid = "usta_xarid"
    case xarid
    case magazinTolov = "magazin_tolov"
    case obyektXarajat = "obyekt_xarajat"
    case ovqat
    case xarajat

    var id: String { rawValue }

    /// Pul oqimi: kirim — qo'lga pul keldi; chiqim — qo'ldan pul ketdi (real xarajat yoki qaytarish);
    /// hisoblangan — pul berilmadi, qarzga yozildi (ustaga haq, magazindan nasiya mol)
    enum Flow { case kirim, chiqim, hisoblangan }

    enum Field: Hashable { case object, worker, shop }

    /// Serverdagi nomi (to'liq)
    var label: String {
        switch self {
        case .kirim: return "Uy egasidan kirim"
        case .qaytarish: return "Uy egasiga qaytardim"
        case .ustaHaqi: return "Usta haqi (hisoblandi)"
        case .ustaTolov: return "Ustaga pul berildi"
        case .ustaXarid: return "Usta o‘z puliga mol oldi"
        case .xarid: return "Magazindan mol olindi"
        case .magazinTolov: return "Magazinga pul berildi"
        case .obyektXarajat: return "Obyekt xarajati"
        case .ovqat: return "Obed (ovqatlanish)"
        case .xarajat: return "Boshqa xarajat"
        }
    }

    /// Qisqa nomi (chip, tugma, ro'yxat)
    var short: String {
        switch self {
        case .kirim: return "Kirim"
        case .qaytarish: return "Qaytarish"
        case .ustaHaqi: return "Usta haqi"
        case .ustaTolov: return "Ustaga to‘lov"
        case .ustaXarid: return "Usta xaridi"
        case .xarid: return "Mol olindi"
        case .magazinTolov: return "Magazinga to‘lov"
        case .obyektXarajat: return "Obyekt xarajati"
        case .ovqat: return "Obed"
        case .xarajat: return "Boshqa xarajat"
        }
    }

    /// Tur tanlash ekranidagi izoh
    var hint: String {
        switch self {
        case .kirim: return "Uy egasi bergan pul"
        case .qaytarish: return "Uy egasiga qaytarilgan pul"
        case .ustaHaqi: return "Kelishilgan ish haqi — ustaga qarz bo‘lib yoziladi"
        case .ustaTolov: return "Ustaga qo‘ldan berilgan pul (avans, hisob)"
        case .ustaXarid: return "Usta o‘z puliga olgan mol — ustaga qarz"
        case .xarid: return "Magazindan olingan mol (naqd yoki nasiya)"
        case .magazinTolov: return "Magazindagi qarzni to‘lash"
        case .obyektXarajat: return "Kran, chiqindi, transport va boshqalar"
        case .ovqat: return "Ustalar tushligi, ovqatlanish"
        case .xarajat: return "Taksi, telefon va boshqa mayda xarajat"
        }
    }

    var symbol: String {
        switch self {
        case .kirim: return "arrow.down.circle.fill"
        case .qaytarish: return "arrow.uturn.backward.circle.fill"
        case .ustaHaqi: return "hammer.fill"
        case .ustaTolov: return "banknote.fill"
        case .ustaXarid: return "shippingbox.fill"
        case .xarid: return "cart.fill"
        case .magazinTolov: return "storefront.fill"
        case .obyektXarajat: return "wrench.and.screwdriver.fill"
        case .ovqat: return "fork.knife"
        case .xarajat: return "creditcard.fill"
        }
    }

    var color: Color {
        switch self {
        case .kirim: return Palette.green
        case .qaytarish: return Palette.orange
        case .ustaHaqi, .ustaXarid: return Palette.purple
        case .ustaTolov: return Palette.red
        case .xarid: return Palette.teal
        case .magazinTolov: return Palette.blue
        case .obyektXarajat: return Palette.gray
        case .ovqat: return Palette.orange
        case .xarajat: return Palette.gray
        }
    }

    var softColor: Color {
        switch self {
        case .kirim: return Palette.greenSoft
        case .qaytarish, .ovqat: return Palette.orangeSoft
        case .ustaHaqi, .ustaXarid: return Palette.purpleSoft
        case .ustaTolov: return Palette.redSoft
        case .xarid: return Palette.tealSoft
        case .magazinTolov: return Palette.blueSoft
        case .obyektXarajat, .xarajat: return Palette.graySoft
        }
    }

    var flow: Flow {
        switch self {
        case .kirim: return .kirim
        case .ustaHaqi, .ustaXarid, .xarid: return .hisoblangan
        default: return .chiqim
        }
    }

    /// Majburiy maydonlar (server addEntry bilan bir xil)
    var required: [Field] {
        switch self {
        case .kirim, .qaytarish, .obyektXarajat: return [.object]
        case .ustaHaqi: return [.object, .worker]
        case .ustaTolov, .ustaXarid: return [.worker]
        case .xarid: return [.shop, .object]
        case .magazinTolov: return [.shop]
        case .ovqat, .xarajat: return []
        }
    }

    /// Ixtiyoriy maydonlar
    var optional: [Field] {
        switch self {
        case .kirim, .qaytarish, .ustaHaqi: return []
        case .ustaTolov, .ustaXarid, .magazinTolov: return [.object]
        case .xarid, .obyektXarajat: return [.worker]
        case .ovqat, .xarajat: return [.object, .worker]
        }
    }

    /// Formada ko'rinadigan maydonlar tartibi
    var fields: [Field] {
        let all: [Field] = [.object, .worker, .shop]
        return all.filter { required.contains($0) || optional.contains($0) }
    }

    func isRequired(_ f: Field) -> Bool { required.contains(f) }

    /// Xarid paytida darhol to'langan qism («paid_now»)
    var hasPaidNow: Bool { self == .xarid }

    /// «Usta» maydoni sarlavhasi
    var workerLabel: String {
        switch self {
        case .ustaHaqi, .ustaTolov, .ustaXarid: return "Usta"
        case .ovqat: return "Kim uchun / kim bilan"
        case .xarid: return "Qaysi usta olib keldi"
        default: return "Qaysi usta bilan bog‘liq"
        }
    }

    /// «Nima uchun» maydoni uchun namuna
    var titlePlaceholder: String {
        switch self {
        case .kirim: return "masalan: 2-bosqich to‘lovi"
        case .qaytarish: return "masalan: ortiqcha olingan"
        case .ustaHaqi: return "masalan: shtukaturka 40 m²"
        case .ustaTolov: return "masalan: avans"
        case .ustaXarid: return "masalan: 10 qop sement"
        case .xarid: return "masalan: 20 qop sement"
        case .magazinTolov: return "masalan: qarzni yopish"
        case .obyektXarajat: return "masalan: kran, chiqindi tashish"
        case .ovqat: return "masalan: 4 kishi tushlik"
        case .xarajat: return "masalan: taksi, telefon"
        }
    }

    /// Tur tanlash ekranidagi guruhlar
    static let groups: [(title: String, types: [EntryType])] = [
        ("Uy egasi", [.kirim, .qaytarish]),
        ("Ustalar", [.ustaTolov, .ustaHaqi, .ustaXarid]),
        ("Magazin", [.xarid, .magazinTolov]),
        ("Xarajatlar", [.obyektXarajat, .ovqat, .xarajat]),
    ]

    /// Ro'yxatdagi summa belgisi: kirim «+», chiqim «−», hisoblangan — belgisiz
    func signedText(_ amount: Int) -> String {
        switch flow {
        case .kirim: return "+" + Fmt.money(amount)
        case .chiqim: return "−" + Fmt.money(amount)
        case .hisoblangan: return Fmt.money(amount)
        }
    }

    var amountColor: Color {
        switch flow {
        case .kirim: return Palette.green
        case .chiqim: return Palette.ink
        case .hisoblangan: return Palette.purple
        }
    }
}

extension EntryType.Field {
    var title: String {
        switch self {
        case .object: return "Obyekt"
        case .worker: return "Usta"
        case .shop: return "Magazin"
        }
    }

    var symbol: String {
        switch self {
        case .object: return "building.2.fill"
        case .worker: return "person.fill"
        case .shop: return "storefront.fill"
        }
    }
}

/// Obyekt holati
enum ObjectStatus: String, CaseIterable, Identifiable, Codable, Hashable {
    case faol, tugagan, toxtatilgan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .faol: return "Ish ketyapti"
        case .tugagan: return "Tugagan"
        case .toxtatilgan: return "To‘xtatilgan"
        }
    }

    var color: Color {
        switch self {
        case .faol: return Palette.green
        case .tugagan: return Palette.blue
        case .toxtatilgan: return Palette.orange
        }
    }
}

/// Foydalanuvchi roli
enum Role: String, Codable, Hashable {
    case egasi, prorab, xodim

    var label: String {
        switch self {
        case .egasi: return "Platforma egasi"
        case .prorab: return "Prorab"
        case .xodim: return "Xodim"
        }
    }
}
