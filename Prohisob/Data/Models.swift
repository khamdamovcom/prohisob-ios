// Server javoblari (https://cabinet.prohisob.com/api/*). Kalitlar snake_case — API dekoderi convertFromSnakeCase bilan
// o'qiydi (object_id → objectId), shuning uchun bu yerda CodingKeys YOZILMAYDI. Summalar — so'm, butun son (@Num: yo'q/null → 0).
// SQLite 0/1 ni ham, true/false ni ham @Flag o'qiydi. Namuna javoblar: docs/samples/*.json
import Foundation

// MARK: - Moslashuvchan o'qish

/// Son: Int, Double (yaxlitlanadi) yoki "123" matn; kalit yo'q yoki null bo'lsa — 0
@propertyWrapper
struct Num: Codable, Hashable, Sendable {
    var wrappedValue: Int
    init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { wrappedValue = 0 }
        else if let i = try? c.decode(Int.self) { wrappedValue = i }
        else if let d = try? c.decode(Double.self) { wrappedValue = Int(d.rounded()) }
        else if let s = try? c.decode(String.self), let i = Int(s) { wrappedValue = i }
        else { wrappedValue = 0 }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue)
    }
}

/// Mantiqiy: true/false, 1/0 yoki "1"; kalit yo'q yoki null bo'lsa — true (faol)
@propertyWrapper
struct Flag: Codable, Hashable, Sendable {
    var wrappedValue: Bool
    init(wrappedValue: Bool) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { wrappedValue = true }
        else if let b = try? c.decode(Bool.self) { wrappedValue = b }
        else if let i = try? c.decode(Int.self) { wrappedValue = i != 0 }
        else if let s = try? c.decode(String.self) { wrappedValue = s == "1" || s == "true" }
        else { wrappedValue = true }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    func decode(_ type: Num.Type, forKey key: Key) throws -> Num {
        try decodeIfPresent(type, forKey: key) ?? Num(wrappedValue: 0)
    }
    func decode(_ type: Flag.Type, forKey key: Key) throws -> Flag {
        try decodeIfPresent(type, forKey: key) ?? Flag(wrappedValue: true)
    }
}

/// Matn yoki son bo'lishi mumkin bo'lgan qiymat (masalan telegram_id)
struct Loose: Codable, Hashable, Sendable {
    let text: String
    init(_ text: String) { self.text = text }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { text = s }
        else if let i = try? c.decode(Int.self) { text = String(i) }
        else if let d = try? c.decode(Double.self) { text = String(Int(d)) }
        else { text = "" }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(text)
    }
}

struct OKResponse: Decodable { let ok: Bool? }

// MARK: - Kirish, foydalanuvchi, kabinet

struct User: Decodable, Hashable, Identifiable {
    let id: Int
    let username: String
    let name: String?
    let role: String
    @Flag var active: Bool
    let tenantId: Int?

    var roleValue: Role { Role(rawValue: role) ?? .xodim }
    var displayName: String { (name?.isEmpty == false ? name : nil) ?? username }
}

struct KabinetRef: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    @Flag var active: Bool
}

/// GET /api/me
struct Me: Decodable {
    let user: User?
    let company: String?
    let kabinet: KabinetRef?
    let kabinetlar: [KabinetRef]?
}

/// POST /api/login (app: "ios") → token
struct LoginResponse: Decodable {
    let user: User
    let token: String
}

struct MijozLoginResponse: Decodable {
    struct Info: Decodable { let id: Int; let name: String }
    let token: String
    let mijoz: Info
}

/// GET /api/app/config
struct AppConfig: Decodable {
    struct IOS: Decodable {
        @Num var minBuild: Int
        @Num var latestBuild: Int
        let storeUrl: String?
    }
    let ios: IOS?
    let sayt: String?
    let yordam: String?
}

// MARK: - Hisob ko'rsatkichlari

/// Dashboard/hisobot «stats» va obyekt «summary» (hisob.js derive). Ekranlarda «Jami xarajat» = jamiXarajat (real, berilgan pul).
/// sofFoyda ish ketayotgan obyektda ko'rsatilmaydi — faqat tugagan obyekt (tugaganFoyda).
struct Stats: Decodable, Hashable {
    @Num var kirimYalpi: Int
    @Num var qaytarish: Int
    @Num var kirim: Int                 // sof kirim (kirim − qaytarish)
    @Num var ustaHaqi: Int
    @Num var ustaXarid: Int
    @Num var ustaTolov: Int
    @Num var xarid: Int
    @Num var magazinTolov: Int
    @Num var obyektXarajat: Int
    @Num var ovqat: Int
    @Num var xarajat: Int
    @Num var boshqaXarajat: Int
    @Num var jamiXarajat: Int           // real: haqiqatda berilgan pul
    @Num var hisoblanganXarajat: Int
    @Num var qoldagiPul: Int            // kirim − real xarajat
    @Num var sofFoyda: Int
    @Num var ustaQarz: Int
    @Num var magazinQarz: Int
    // faqat dashboard/hisobot
    @Num var tugaganSoni: Int
    @Num var tugaganFoyda: Int
    @Num var obyektlar: Int             // faol obyektlar
    @Num var obyektlarJami: Int
    @Num var ustalar: Int
    @Num var magazinlar: Int
    // faqat obyekt summary
    @Num var shartnoma: Int
    @Num var qoldiqOlinadigan: Int      // shartnomadan hali olinadigan
}

// MARK: - Obyekt, usta, magazin

struct ObjectItem: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let address: String?
    let ownerName: String?
    let ownerPhone: String?
    @Num var contractAmount: Int
    let startDate: String?
    let endDate: String?
    let status: String
    let note: String?
    let createdAt: String?
    // ro'yxatdagi jamlar (GET /api/objects, dashboard)
    @Num var kirim: Int
    @Num var xarajat: Int               // real xarajat
    @Num var hisoblangan: Int
    @Num var qoldagiPul: Int
    let foyda: Int?

    var statusValue: ObjectStatus { ObjectStatus(rawValue: status) ?? .faol }
    /// Sof foyda faqat tugagan obyektda ko'rsatiladi
    var foydaKorinadi: Int? { statusValue == .tugagan ? foyda : nil }
}

struct Worker: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let phone: String?
    let specialty: String?
    let note: String?
    @Flag var active: Bool
    @Num var haqi: Int
    @Num var ozPuliga: Int
    @Num var tolangan: Int
    @Num var obyektlar: Int
    @Num var qarz: Int                  // > 0 — ustaga qarzmiz
}

struct Shop: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let phone: String?
    let address: String?
    let note: String?
    @Flag var active: Bool
    @Num var olingan: Int
    @Num var tolangan: Int
    @Num var qarz: Int                  // > 0 — magazinga qarzmiz
}

/// GET /api/objects/:id
struct ObjectDetail: Decodable {
    struct WorkerRow: Decodable, Hashable, Identifiable {
        let id: Int
        let name: String
        let specialty: String?
        @Num var haqi: Int
        @Num var ozPuliga: Int
        @Num var tolangan: Int
        @Num var olibKelgan: Int
        @Num var ovqat: Int
        @Num var qarz: Int
    }
    struct ShopRow: Decodable, Hashable, Identifiable {
        let id: Int
        let name: String
        @Num var olingan: Int
        @Num var tolangan: Int
        @Num var qarz: Int
    }
    struct ClientRow: Decodable, Hashable, Identifiable {
        let id: Int
        let name: String
        @Flag var active: Bool
        @Num var telegram: Int
    }
    let obj: ObjectItem
    let summary: Stats
    let ustalar: [WorkerRow]
    let magazinlar: [ShopRow]
    let tarix: [Entry]
    let mijozlar: [ClientRow]?
}

/// GET /api/workers/:id
struct WorkerDetail: Decodable {
    struct Summary: Decodable, Hashable {
        @Num var haqi: Int
        @Num var ozPuliga: Int
        @Num var tolangan: Int
        @Num var qarz: Int
        @Num var olibKelganMol: Int
        @Num var ovqat: Int
    }
    struct ObjectRow: Decodable, Hashable {
        let id: Int?                    // obyektsiz yozuvlar — nil, name «Obyektsiz»
        let name: String
        let status: String?
        @Num var haqi: Int
        @Num var ozPuliga: Int
        @Num var tolangan: Int
        @Num var olibKelgan: Int
        @Num var ovqat: Int
        let birinchi: String?
        let oxirgi: String?
        @Num var qarz: Int
        var rowId: String { "\(id ?? 0)-\(name)" }
    }
    struct ShopRow: Decodable, Hashable, Identifiable {
        let id: Int
        let name: String
        @Num var summa: Int
        @Num var soni: Int
    }
    let usta: Worker
    let summary: Summary
    let obyektlar: [ObjectRow]
    let magazinlar: [ShopRow]
    let tarix: [Entry]
}

/// GET /api/shops/:id
struct ShopDetail: Decodable {
    struct Summary: Decodable, Hashable {
        @Num var olingan: Int
        @Num var tolangan: Int
        @Num var qarz: Int
    }
    struct ObjectRow: Decodable, Hashable {
        let id: Int?
        let name: String?
        @Num var olingan: Int
        @Num var tolangan: Int
        let oxirgi: String?
        @Num var qarz: Int
        var rowId: String { "\(id ?? 0)-\(name ?? "")" }
    }
    struct WorkerRow: Decodable, Hashable {
        let id: Int?
        let name: String?
        @Num var summa: Int
        @Num var soni: Int
        let oxirgi: String?
        var rowId: String { "\(id ?? 0)-\(name ?? "")" }
    }
    let magazin: Shop
    let summary: Summary
    let obyektlar: [ObjectRow]
    let ustalar: [WorkerRow]
    let tarix: [Entry]
}

// MARK: - Yozuvlar

/// Ro'yxatdagi yozuv (GET /api/entries, tarix, dashboard «oxirgi»). cheklar — soni.
struct Entry: Decodable, Hashable, Identifiable {
    let id: Int
    let type: String
    let objectId: Int?
    let workerId: Int?
    let shopId: Int?
    @Num var amount: Int
    let date: String
    let title: String?
    let note: String?
    let linkId: Int?
    let createdBy: Int?
    let source: String?
    let createdAt: String?
    let objectName: String?
    let workerName: String?
    let shopName: String?
    let userName: String?
    let username: String?
    @Num var cheklar: Int

    var kind: EntryType? { EntryType(rawValue: type) }
    /// Ro'yxatdagi asosiy matn: «nima uchun» bo'lsa — u, aks holda tur nomi
    var headline: String { (title?.isEmpty == false ? title : nil) ?? kind?.short ?? type }
    /// Obyekt · usta · magazin
    var context: String {
        [objectName, workerName, shopName].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }
}

/// GET /api/entries?… → { rows, total }
struct EntriesPage: Decodable {
    let rows: [Entry]
    @Num var total: Int
}

struct FileInfo: Decodable, Hashable, Identifiable {
    let id: Int
    let origName: String?
    let mime: String?
    @Num var size: Int
    let createdAt: String?

    var isPDF: Bool { (mime ?? "").contains("pdf") }
}

/// GET /api/entries/:id — cheklar ro'yxati va bog'liq yozuv (xarid ↔ darhol to'langan qism)
struct EntryDetail: Decodable, Hashable, Identifiable {
    struct Linked: Decodable, Hashable, Identifiable {
        let id: Int
        let type: String
        @Num var amount: Int
        let date: String?
        let title: String?
        var kind: EntryType? { EntryType(rawValue: type) }
    }
    let id: Int
    let type: String
    let objectId: Int?
    let workerId: Int?
    let shopId: Int?
    @Num var amount: Int
    let date: String
    let title: String?
    let note: String?
    let linkId: Int?
    let createdBy: Int?
    let source: String?
    let createdAt: String?
    let objectName: String?
    let workerName: String?
    let shopName: String?
    let userName: String?
    let username: String?
    let cheklar: [FileInfo]
    let bogliq: [Linked]

    var kind: EntryType? { EntryType(rawValue: type) }
}

/// POST /api/entries/:id/files → { ok, cheklar }
struct UploadResponse: Decodable {
    let ok: Bool?
    let cheklar: [FileInfo]?
}

/// POST /api/entries → yaratilgan yozuv (jadval qatori)
struct CreatedEntry: Decodable {
    let id: Int
    let type: String
    @Num var amount: Int
    let date: String?
}

// MARK: - Hisobot

/// GET /api/report?from&to
struct Report: Decodable {
    struct ObjectRow: Decodable, Hashable, Identifiable {
        let id: Int
        let name: String
        let status: String
        @Num var contractAmount: Int
        @Num var kirim: Int
        @Num var ustaTolov: Int
        @Num var magazinTolov: Int
        @Num var ovqat: Int
        @Num var xarajat: Int           // obyekt_xarajat + boshqa
        @Num var hisoblangan: Int
        @Num var jamiXarajat: Int
        @Num var qoldagiPul: Int
        let foyda: Int?                 // faqat tugagan obyektda (server null qaytaradi)
        var statusValue: ObjectStatus { ObjectStatus(rawValue: status) ?? .faol }
    }
    struct Month: Decodable, Hashable, Identifiable {
        let oy: String                  // "2026-10"
        @Num var kirim: Int
        @Num var xarajat: Int
        @Num var farq: Int
        var id: String { oy }
    }
    let stats: Stats
    let perObject: [ObjectRow]
    let perMonth: [Month]
    let ustalar: [Worker]
    let magazinlar: [Shop]
}

/// GET /api/dashboard?from&to
struct Dashboard: Decodable {
    let stats: Stats
    let oxirgi: [Entry]
    let obyektlar: [ObjectItem]
    let qarzdorUstalar: [Worker]
    let qarzdorMagazinlar: [Shop]
}

// MARK: - Mijozlar va xodimlar (prorab boshqaradi)

struct Client: Decodable, Hashable, Identifiable {
    struct ObjectRef: Decodable, Hashable, Identifiable {
        let id: Int
        let name: String
        let status: String?
    }
    let id: Int
    let name: String
    let phone: String?
    let login: String
    let note: String?
    @Flag var active: Bool
    let createdAt: String?
    @Num var telegram: Int              // botga ulangan telegramlar soni
    let objects: [ObjectRef]
}

/// GET /api/clients
struct ClientsResponse: Decodable {
    let clients: [Client]
    let bot: String?
}

/// GET /api/users
struct UserRow: Decodable, Hashable, Identifiable {
    let id: Int
    let username: String
    let name: String?
    let role: String
    let telegramId: Loose?
    @Flag var active: Bool
    let createdAt: String?
    let tenantId: Int?
    let kabinet: String?

    var roleValue: Role { Role(rawValue: role) ?? .xodim }
}

// MARK: - Obyekt egasi (mijoz) rejimi — /api/mijoz/*

struct MijozTarkib: Decodable, Hashable {
    @Num var ustaTolov: Int
    @Num var magazinTolov: Int
    @Num var ovqat: Int
    @Num var obyektXarajat: Int
    @Num var xarajat: Int
}

/// Mijozga ko'rinadigan obyekt hisobi: o'zi bergan pul va real xarajat (qarzlar, foyda yo'q)
struct MijozObject: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let address: String?
    let status: String
    let startDate: String?
    let endDate: String?
    @Num var kirim: Int                 // siz bergan pul (qaytarilgani ayirilgan)
    @Num var kirimYalpi: Int
    @Num var qaytarish: Int
    @Num var jamiXarajat: Int           // sarflangan
    @Num var qoldiq: Int                // siz bergan − sarflangan (manfiy — ortiqcha sarflangan)
    @Num var shartnoma: Int
    @Num var qolganTolov: Int
    let tarkib: MijozTarkib

    var statusValue: ObjectStatus { ObjectStatus(rawValue: status) ?? .faol }
}

/// GET /api/mijoz/me
struct MijozMe: Decodable {
    struct Info: Decodable, Hashable { let id: Int; let name: String; let login: String; let phone: String? }
    struct Prorab: Decodable, Hashable { let name: String; let phone: String? }
    let mijoz: Info
    let prorab: Prorab
    let obyektlar: [MijozObject]
}

/// GET /api/mijoz/objects/:id
struct MijozObjectDetail: Decodable {
    struct Ref: Decodable, Hashable { let id: Int; let name: String; let address: String?; let status: String; let startDate: String?; let endDate: String? }
    struct WorkerRow: Decodable, Hashable, Identifiable { let id: Int; let name: String; let specialty: String?; @Num var tolangan: Int }
    struct ShopRow: Decodable, Hashable, Identifiable { let id: Int; let name: String; @Num var tolangan: Int }
    let obyekt: Ref
    @Num var kirim: Int
    @Num var kirimYalpi: Int
    @Num var qaytarish: Int
    @Num var jamiXarajat: Int
    @Num var qoldiq: Int
    @Num var shartnoma: Int
    @Num var qolganTolov: Int
    let tarkib: MijozTarkib
    let ustalar: [WorkerRow]
    let magazinlar: [ShopRow]
}

/// GET /api/mijoz/objects/:id/entries → { rows, total }. type — EntryType (xarid bilan to'langan bo'lsa "xarid")
struct MijozEntry: Decodable, Hashable, Identifiable {
    let id: Int
    let type: String
    let nomi: String                    // «Siz bergan pul», «Ustaga berildi», «Magazindan mol»…
    @Num var amount: Int
    let date: String
    let title: String?
    let note: String?
    let workerName: String?
    let shopName: String?
    @Num var cheklar: Int

    var kind: EntryType? { EntryType(rawValue: type) }
}

struct MijozEntriesPage: Decodable {
    let rows: [MijozEntry]
    @Num var total: Int
}

// MARK: - So'rov tanalari (encoder: convertToSnakeCase; nil maydonlar yuborilmaydi)

struct LoginBody: Encodable { let username: String; let password: String; var app = "ios"; let device: String }
struct MijozLoginBody: Encodable { let login: String; let password: String; let device: String }
struct PasswordBody: Encodable { let eski: String; let yangi: String }

struct NewEntryBody: Encodable {
    var type: String
    var amount: Int
    var date: String
    var title: String
    var note: String
    var objectId: Int?
    var workerId: Int?
    var shopId: Int?
    var paidNow: Int?
}

struct ObjectBody: Encodable {
    var name: String
    var address: String = ""
    var ownerName: String = ""
    var ownerPhone: String = ""
    var contractAmount: Int = 0
    var startDate: String = ""
    var endDate: String = ""
    var status: String = ObjectStatus.faol.rawValue
    var note: String = ""
}

struct WorkerBody: Encodable {
    var name: String
    var phone: String = ""
    var specialty: String = ""
    var note: String = ""
    var active: Bool = true
}

struct ShopBody: Encodable {
    var name: String
    var phone: String = ""
    var address: String = ""
    var note: String = ""
    var active: Bool = true
}

/// POST /api/clients (login, password majburiy) va PUT /api/clients/:id (password — faqat o'zgartirilsa)
struct ClientBody: Encodable {
    var name: String
    var phone: String = ""
    var login: String?
    var password: String?
    var note: String = ""
    var objectIds: [Int] = []
    var active: Bool?
}

/// POST /api/users (prorab xodim qo'shadi) va PUT /api/users/:id
struct UserBody: Encodable {
    var username: String?
    var password: String?
    var name: String
    var active: Bool?
}
