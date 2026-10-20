// Navigatsiya: 5 bo'lim (pastki menyu), har birining o'z steki; ekranlar orasidagi o'tishlar — Route;
// «Yangi yozuv» oynasi (newEntry) istalgan joydan oldindan to'ldirilgan holda ochiladi.
// Ekranda: NavigationLink(value: Route.object(id)) { … } — yoki router.push(.worker(id)).
import SwiftUI
import Observation

enum AppTab: Hashable {
    case home, objects, workers, entries, more
}

/// Yozuvlar ro'yxati filtri (GET /api/entries so'rov parametrlari)
struct EntryFilter: Hashable {
    var objectId: Int?
    var workerId: Int?
    var shopId: Int?
    var type: EntryType?
    var from: String?          // "yyyy-MM-dd"
    var to: String?
    var q: String?
    /// Ekran sarlavhasi (masalan obyekt nomi) — so'rovga kirmaydi
    var title: String?

    init(objectId: Int? = nil, workerId: Int? = nil, shopId: Int? = nil, type: EntryType? = nil,
         from: String? = nil, to: String? = nil, q: String? = nil, title: String? = nil) {
        self.objectId = objectId; self.workerId = workerId; self.shopId = shopId; self.type = type
        self.from = from; self.to = to; self.q = q; self.title = title
    }

    var query: [String: String?] {
        ["object_id": objectId.map(String.init), "worker_id": workerId.map(String.init), "shop_id": shopId.map(String.init),
         "type": type?.rawValue, "from": from, "to": to, "q": q]
    }

    var isEmpty: Bool { objectId == nil && workerId == nil && shopId == nil && type == nil && from == nil && to == nil && (q ?? "").isEmpty }
}

/// «Yangi yozuv» oynasini oldindan to'ldirish (masalan usta sahifasidan «Pul berish» → type: .ustaTolov, workerId)
struct EntryPrefill: Identifiable, Hashable {
    var id = UUID()
    var type: EntryType?
    var objectId: Int?
    var workerId: Int?
    var shopId: Int?
    var amount: Int?

    init(type: EntryType? = nil, objectId: Int? = nil, workerId: Int? = nil, shopId: Int? = nil, amount: Int? = nil) {
        self.type = type; self.objectId = objectId; self.workerId = workerId; self.shopId = shopId; self.amount = amount
    }
}

enum Route: Hashable {
    case object(Int)
    case worker(Int)
    case shop(Int)
    case entry(Int)
    case shops
    case report
    case entries(EntryFilter)
    case clients
    case users
    case password
    case kabinets
}

/// Obyekt egasi (mijoz) rejimidagi o'tishlar — ClientRootView o'z NavigationStack'ida router.clientPath bilan ishlatadi
enum ClientRoute: Hashable {
    case object(Int)
}

@MainActor
@Observable
final class Router {
    static let shared = Router()

    var tab: AppTab = .home
    var homePath = NavigationPath()
    var objectsPath = NavigationPath()
    var workersPath = NavigationPath()
    var entriesPath = NavigationPath()
    var morePath = NavigationPath()
    /// Obyekt egasi rejimi steki (ClientRoute)
    var clientPath = NavigationPath()
    /// Ochiq «Yangi yozuv» oynasi
    var newEntry: EntryPrefill?

    /// Joriy bo'lim stekiga ekran qo'shish
    func push(_ r: Route) {
        switch tab {
        case .home: homePath.append(r)
        case .objects: objectsPath.append(r)
        case .workers: workersPath.append(r)
        case .entries: entriesPath.append(r)
        case .more: morePath.append(r)
        }
    }

    /// Boshqa bo'limga o'tib, uning ildizidan ekran ochish
    func open(_ r: Route?, in t: AppTab) {
        tab = t
        var p = NavigationPath()
        if let r { p.append(r) }
        switch t {
        case .home: homePath = p
        case .objects: objectsPath = p
        case .workers: workersPath = p
        case .entries: entriesPath = p
        case .more: morePath = p
        }
    }

    func addEntry(_ p: EntryPrefill = EntryPrefill()) { newEntry = p }

    func reset() {
        tab = .home
        homePath = NavigationPath()
        objectsPath = NavigationPath()
        workersPath = NavigationPath()
        entriesPath = NavigationPath()
        morePath = NavigationPath()
        clientPath = NavigationPath()
        newEntry = nil
    }
}

/// Route → ekran
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .object(let id): ObjectDetailView(id: id)
        case .worker(let id): WorkerDetailView(id: id)
        case .shop(let id): ShopDetailView(id: id)
        case .entry(let id): EntryDetailView(id: id)
        case .shops: ShopsView()
        case .report: ReportView()
        case .entries(let f): EntriesView(filter: f)
        case .clients: ClientsView()
        case .users: UsersView()
        case .password: ChangePasswordView()
        case .kabinets: KabinetPickerView()
        }
    }
}

extension View {
    /// NavigationStack ildizida bir marta: Route qiymatlari uchun ekranlar
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { RouteView(route: $0) }
    }
}
