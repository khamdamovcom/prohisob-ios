// Ilova holati: kim kirgan (prorab/xodim yoki obyekt egasi), token (Keychain), /api/me, egasining kabinet tanlovi,
// ma'lumot o'zgarganda ekranlarni yangilash (dataVersion), xabarlar (toast), Face ID qulfi, mavzu, versiya talabi.
import SwiftUI
import Observation
import LocalAuthentication

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Telefon bo‘yicha"
        case .light: return "Yorug‘"
        case .dark: return "Qorong‘i"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

@MainActor
@Observable
final class Session {
    static let shared = Session()

    enum Kind: String { case user, mijoz }

    /// nil — kirilmagan (kirish ekrani)
    private(set) var kind: Kind?
    /// Prorab/xodim: GET /api/me
    private(set) var me: Me?
    /// Obyekt egasi: GET /api/mijoz/me
    private(set) var mijozMe: MijozMe?
    /// Ilova ochilib, saqlangan sessiya tekshirilyapti
    private(set) var restoring = true
    private(set) var config: AppConfig?
    /// Har qanday yozuv/obyekt o'zgarganda oshadi — ekranlar `.task(id: session.dataVersion)` bilan qayta yuklanadi
    private(set) var dataVersion = 0
    var toast: Toast?
    /// Face ID qulfi yoqilgan va ilova hali ochilmagan
    var locked = false
    /// Skrinshot rejimi (CI): -shot <ekran>
    let shot: String?

    var lockEnabled: Bool {
        didSet { UserDefaults.standard.set(lockEnabled, forKey: "lockEnabled") }
    }
    var theme: ThemeChoice {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    /// Platforma egasi tanlagan kabinet (prorab) — X-Kabinet sarlavhasi
    private(set) var kabinetId: Int?

    private var toastTask: Task<Void, Never>?
    private var unlocking = false

    init() {
        let d = UserDefaults.standard
        // Keychain ilova o'chirilganda ham qoladi, UserDefaults (Face ID sozlamasi) esa o'chadi — qayta o'rnatilgan ilova
        // eski hisobga qulfsiz kirmasin
        if !d.bool(forKey: "installed") {
            Keychain.set(nil, for: "token")
            Keychain.set(nil, for: "kind")
            d.set(true, forKey: "installed")
        }
        lockEnabled = d.bool(forKey: "lockEnabled")
        theme = ThemeChoice(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        kabinetId = d.object(forKey: "kabinet") as? Int
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-shot"), i + 1 < args.count { shot = args[i + 1] } else { shot = nil }
        API.shared.onUnauthorized = {
            Task { @MainActor in Session.shared.expire() }
        }
    }

    // MARK: - Kim kirgan

    var user: User? { me?.user }
    var role: Role { user?.roleValue ?? .xodim }
    var isEgasi: Bool { role == .egasi }
    /// Prorab yoki egasi: obyekt/usta/magazinni o'chirish, mijozlar va xodimlarni boshqarish
    var isProrab: Bool { role == .egasi || role == .prorab }
    var userName: String { user?.displayName ?? "" }
    var kabinetName: String { me?.kabinet?.name ?? "" }
    var kabinetlar: [KabinetRef] { me?.kabinetlar ?? [] }

    /// Yozuv yoki chekni o'chira oladimi: prorab/egasi — hammasini, xodim — faqat o'zi kiritganini
    func canDelete(createdBy: Int?) -> Bool {
        isProrab || (createdBy != nil && createdBy == user?.id)
    }

    // MARK: - Ishga tushish

    func start() async {
        async let cfg: Void = loadConfig()
        if let shot {
            await ShotMode.start(shot, session: self)
        } else if let tok = Keychain.get("token"), let k = Kind(rawValue: Keychain.get("kind") ?? "") {
            API.shared.token = tok
            API.shared.kabinet = k == .user ? kabinetId : nil
            kind = k
            if lockEnabled { locked = true }
            await refresh()
        }
        _ = await cfg
        withAnimation(.easeOut(duration: 0.25)) { restoring = false }
    }

    func loadConfig() async {
        config = try? await API.shared.get("/api/app/config")
    }

    var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    var updateRequired: Bool {
        guard let min = config?.ios?.minBuild, min > 0 else { return false }
        return currentBuild < min
    }

    /// /api/me yoki /api/mijoz/me ni qayta o'qish (xato bo'lsa — jim; 401 bo'lsa API o'zi chiqaradi)
    func refresh() async {
        switch kind {
        case .user:
            guard let m: Me = try? await API.shared.get("/api/me") else { return }
            if m.user == nil { clear(); return }
            me = m
            // egasi tanlagan kabinet o'chirilgan yoki to'xtatilgan bo'lsa (server o'z kabinetini qaytaradi) — o'zinikiga qaytamiz
            if m.user?.roleValue == .egasi, let k = kabinetId, m.kabinet?.id != k {
                setKabinet(nil)
                if let again: Me = try? await API.shared.get("/api/me") { me = again }
                changed()
            }
        case .mijoz:
            if let m: MijozMe = try? await API.shared.get("/api/mijoz/me") { mijozMe = m }
        case nil:
            break
        }
    }

    // MARK: - Kirish / chiqish

    /// Prorab yoki xodim (saytdagi login-parol)
    func login(username: String, password: String) async throws {
        let r: LoginResponse = try await API.shared.post("/api/login",
            body: LoginBody(username: username.trimmingCharacters(in: .whitespaces), password: password, device: API.deviceName))
        begin(.user, token: r.token)
        setKabinet(nil)
        await refresh()
        if me == nil { me = Me(user: r.user, company: nil, kabinet: nil, kabinetlar: nil) }
    }

    /// Obyekt egasi (prorab bergan login-parol)
    func loginMijoz(login: String, password: String) async throws {
        let r: MijozLoginResponse = try await API.shared.post("/api/mijoz/login",
            body: MijozLoginBody(login: login.trimmingCharacters(in: .whitespaces), password: password, device: API.deviceName))
        begin(.mijoz, token: r.token)
        await refresh()
    }

    private func begin(_ k: Kind, token: String) {
        API.shared.token = token
        Keychain.set(token, for: "token")
        Keychain.set(k.rawValue, for: "kind")
        Router.shared.reset()
        kind = k
        locked = false
    }

    func logout() async {
        let path = kind == .mijoz ? "/api/mijoz/logout" : "/api/logout"
        try? await API.shared.post(path)
        clear()
    }

    /// Server 401 qaytardi (parol almashgan, sessiya eskirgan, hisob o'chirilgan)
    func expire() {
        guard kind != nil else { return }
        clear()
        show("Sessiya tugadi. Qaytadan kiring.", error: true)
    }

    private func clear() {
        API.shared.token = nil
        API.shared.kabinet = nil
        Keychain.set(nil, for: "token")
        Keychain.set(nil, for: "kind")
        kind = nil
        me = nil
        mijozMe = nil
        locked = false
        setKabinet(nil)
        Router.shared.reset()
        // yuklab olingan Excel fayllar telefonda qolmasin
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("eksport"))
    }

    // MARK: - Kabinet (faqat platforma egasi)

    func selectKabinet(_ id: Int?) async {
        setKabinet(id)
        Router.shared.reset()
        await refresh()
        changed()
    }

    private func setKabinet(_ id: Int?) {
        kabinetId = id
        API.shared.kabinet = id
        if let id { UserDefaults.standard.set(id, forKey: "kabinet") } else { UserDefaults.standard.removeObject(forKey: "kabinet") }
    }

    // MARK: - Ma'lumot o'zgardi, xabarlar

    /// Yozuv/obyekt/usta… qo'shildi, o'zgardi yoki o'chdi — ochiq ekranlar qayta yuklanadi
    func changed() { dataVersion += 1 }

    func show(_ text: String, error: Bool = false) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.35)) { toast = Toast(text: text, isError: error) }
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(error ? .error : .success)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(error ? 3.5 : 2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self?.toast = nil }
        }
    }

    // MARK: - Face ID qulfi

    var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Telefon paroli"
        }
    }

    var biometrySymbol: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.fill"
        }
    }

    /// Face ID / Touch ID (yoki telefon paroli) bilan tasdiqlash
    func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    func unlock() async {
        guard locked, !unlocking else { return }
        unlocking = true
        defer { unlocking = false }
        if await authenticate(reason: "Prohisob’ni ochish") {
            withAnimation(.easeOut(duration: 0.25)) { locked = false }
        }
    }

    /// Sozlamalardagi «Face ID bilan qulflash» — yoqishdan oldin bir marta tasdiqlanadi
    func setLock(_ on: Bool) async {
        if on {
            guard await authenticate(reason: "Face ID qulfini yoqish") else {
                show("\(biometryName) tasdiqlanmadi", error: true)
                return
            }
        }
        lockEnabled = on
    }

    /// Ilova fonga o'tdi — qaytganda qulf so'raladi
    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .background, lockEnabled, kind != nil, shot == nil { locked = true }
        // qaytganda: versiya talabi va /api/me (kabinet to'xtatilgan, hisob nofaol qilingan bo'lsa — darhol bilinadi)
        if phase == .active, kind != nil, !restoring { Task { await loadConfig(); await refresh() } }
    }

    // MARK: - Skrinshot rejimi uchun

    func shotLogin(user: String, password: String) async {
        try? await login(username: user, password: password)
    }

    func shotLoginMijoz(login: String, password: String) async {
        try? await loginMijoz(login: login, password: password)
    }
}
