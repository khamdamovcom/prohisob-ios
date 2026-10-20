// Skrinshot rejimi (CI, simulyator): ilova `-shot <ekran> [-theme dark]` bilan ochiladi, demo kabinetga o'zi kiradi
// (login-parol muhitdan: SIMCTL_CHILD_DEMO_LOGIN / DEMO_PAROL / DEMO_MIJOZ_LOGIN / DEMO_MIJOZ_PAROL — repoda yo'q)
// va kerakli ekranni ochadi. Face ID qulfi va maxfiylik pardasi bu rejimda ishlamaydi.
// Ekranlar: login, home, objects, object, workers, worker, entries, entry, entry-new, entry-form, report, more, shops, clients, users,
// password, client, client-object
import SwiftUI

@MainActor
enum ShotMode {
    static func start(_ shot: String, session: Session) async {
        let env = ProcessInfo.processInfo.environment
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-theme"), i + 1 < args.count, let t = ThemeChoice(rawValue: args[i + 1]) {
            session.theme = t
        }
        let router = Router.shared
        if shot == "login" { return }           // kirish ekrani — demo hisobga kirmasdan
        if shot.hasPrefix("client") && shot != "clients" {
            await session.shotLoginMijoz(login: env["DEMO_MIJOZ_LOGIN"] ?? "", password: env["DEMO_MIJOZ_PAROL"] ?? "")
            if shot == "client-object", let id = session.mijozMe?.obyektlar.first?.id {
                router.clientPath.append(ClientRoute.object(id))
            }
            return
        }
        await session.shotLogin(user: env["DEMO_LOGIN"] ?? "", password: env["DEMO_PAROL"] ?? "")
        switch shot {
        case "objects": router.tab = .objects
        case "object":
            let list: [ObjectItem] = (try? await API.shared.get("/api/objects")) ?? []
            router.open(list.first.map { Route.object($0.id) }, in: .objects)
        case "workers": router.tab = .workers
        case "worker":
            let list: [Worker] = (try? await API.shared.get("/api/workers")) ?? []
            let w = list.max(by: { $0.qarz < $1.qarz })
            router.open(w.map { Route.worker($0.id) }, in: .workers)
        case "entries": router.tab = .entries
        case "entry":
            let page: EntriesPage? = try? await API.shared.get("/api/entries", query: ["type": "xarid", "limit": "1"])
            router.open(page?.rows.first.map { Route.entry($0.id) }, in: .entries)
        case "entry-new": router.addEntry()
        case "entry-form": router.addEntry(EntryPrefill(type: .ustaTolov))
        case "report": router.open(.report, in: .home)
        case "shops": router.open(.shops, in: .more)
        case "more": router.tab = .more
        case "clients": router.open(.clients, in: .more)
        case "users": router.open(.users, in: .more)
        case "password": router.open(.password, in: .more)
        default: router.tab = .home
        }
    }
}
