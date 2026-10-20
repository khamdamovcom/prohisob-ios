// Prohisob — prorablar uchun qurilish hisobi (iOS). Ma'lumot https://cabinet.prohisob.com dan — saytdagi kabinet bilan bir xil.
// Ikki rejim: prorab/xodim (to'liq kabinet) va obyekt egasi (faqat o'z obyektining hisobini ko'radi).
import SwiftUI

@main
struct ProhisobApp: App {
    @State private var session = Session.shared
    @State private var router = Router.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(router)
                .preferredColorScheme(session.theme.scheme)
                .tint(Palette.accent)
        }
    }
}

/// Ilova qobig'i: ochilish → kirish / kabinet / obyekt egasi; Face ID qulfi; ilovalar oynasida ma'lumot yashiriladi
struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var phase

    /// Qulf yoki (ilova faol bo'lmaganda) maxfiylik pardasi kerakmi — ilovalar oynasidagi suratda summalar ko'rinmasin
    private var shielded: Bool {
        guard session.shot == nil, !session.restoring || session.locked else { return false }
        return session.locked || (phase != .active && session.kind != nil)
    }

    var body: some View {
        ZStack {
            Group {
                if session.restoring {
                    SplashView()
                } else if session.updateRequired {
                    UpdateRequiredView()
                } else if session.kind == .user {
                    // kabinet almashsa — bo'limlarning ichki holati (filtrlar, eski raqamlar) ham yangidan
                    MainTabs().id(session.kabinetId ?? 0)
                } else if session.kind == .mijoz {
                    ClientRootView()
                } else {
                    LoginView()
                }
            }
            .transition(.opacity)
        }
        .background(Palette.bg.ignoresSafeArea())
        .animation(.easeOut(duration: 0.25), value: session.kind)
        .task {
            ToastOverlay.shared.install(session: session)   // xabarlar sheet/alert ustida ham ko'rinadi
            ShieldWindow.shared.install(session: session)   // qulf va maxfiylik pardasi — hamma oynalar ustida
            await session.start()
            ShieldWindow.shared.set(shielded)
        }
        .onChange(of: shielded) { _, on in ShieldWindow.shared.set(on) }
        .onChange(of: phase) { _, p in
            session.scenePhaseChanged(p)
            // qulf fonda qo'yiladi — Face ID ilova qaytganda so'raladi
            if p == .active, session.locked { Task { await session.unlock() } }
        }
    }
}

/// Prorab / xodim: 5 bo'lim + «Yangi yozuv»
struct MainTabs: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.homePath) { DashboardView().withRoutes() }
                .tabItem { Label("Asosiy", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.home)
            NavigationStack(path: $router.objectsPath) { ObjectsView().withRoutes() }
                .tabItem { Label("Obyektlar", systemImage: "building.2.fill") }
                .tag(AppTab.objects)
            NavigationStack(path: $router.workersPath) { WorkersView().withRoutes() }
                .tabItem { Label("Ustalar", systemImage: "person.2.fill") }
                .tag(AppTab.workers)
            NavigationStack(path: $router.entriesPath) { EntriesView().withRoutes() }
                .tabItem { Label("Yozuvlar", systemImage: "list.bullet.rectangle.portrait.fill") }
                .tag(AppTab.entries)
            NavigationStack(path: $router.morePath) { MoreView().withRoutes() }
                .tabItem { Label("Yana", systemImage: "ellipsis.circle.fill") }
                .tag(AppTab.more)
        }
        .minimizingTabBar()
        .modifier(AddEntryButton())
        .sheet(item: $router.newEntry) { p in
            NewEntryView(prefill: p)
        }
    }
}

/// «Yangi yozuv»: iOS 26 — pastki menyu ustidagi shisha panel (tabViewBottomAccessory); oldingilarida — suzuvchi tugma
private struct AddEntryButton: ViewModifier {
    @Environment(Router.self) private var router

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabViewBottomAccessory {
                Button { router.addEntry() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Palette.onBrand)
                            .frame(width: 28, height: 28)
                            .background(Palette.brand, in: Circle())
                        Text("Yangi yozuv")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Yangi yozuv qo‘shish")
            }
        } else {
            // iOS 17–18: suzuvchi tugma ro'yxatlarning oxirgi qatorini yopmasin; klaviatura bilan ko'tarilmasin
            content.contentMargins(.bottom, 76, for: .scrollContent).overlay(alignment: .bottomTrailing) {
                Button { router.addEntry() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Palette.onBrand)
                        .frame(width: 58, height: 58)
                        .background(Palette.brand, in: Circle())
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                }
                .buttonStyle(PressableStyle())
                .padding(.trailing, 18)
                .padding(.bottom, 62)
                .ignoresSafeArea(.keyboard)
                .accessibilityLabel("Yangi yozuv qo‘shish")
            }
        }
    }
}

// MARK: - Brend belgisi, ochilish, qulf

/// «P» belgisi (prohisob.com dagi kabi): sariq kvadrat, siyoh harf
struct BrandMark: View {
    var size: CGFloat = 56

    var body: some View {
        Text("P")
            .font(.system(size: size * 0.74, weight: .black, design: .rounded))
            .foregroundStyle(Palette.onBrand)
            .frame(width: size, height: size)
            .background(Palette.brand, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 14) {
            BrandMark(size: 72)
            Text("Prohisob").font(.title.weight(.heavy)).foregroundStyle(Palette.ink)
            ProgressView().padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
    }
}

struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            BrandMark(size: 72)
        }
    }
}

/// Face ID qulfi
struct LockView: View {
    @Environment(Session.self) private var session
    @State private var tried = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            BrandMark(size: 76)
            Text("Prohisob qulflangan").font(.title2.weight(.bold)).foregroundStyle(Palette.ink)
            Text("Hisobingizni ko‘rish uchun \(session.biometryName) bilan oching")
                .font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            Spacer()
            BrandButton(title: "\(session.biometryName) bilan ochish", symbol: session.biometrySymbol) {
                Task { await session.unlock() }
            }
            Button("Hisobdan chiqish") { Task { await session.logout() } }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .padding(.bottom, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
        .task {
            guard !tried else { return }
            tried = true
            try? await Task.sleep(for: .milliseconds(350))
            if UIApplication.shared.applicationState == .active { await session.unlock() }
        }
    }
}

/// Server minimal versiyani oshirgan (/api/app/config → ios.minBuild)
struct UpdateRequiredView: View {
    @Environment(Session.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            BrandMark(size: 72)
            Text("Yangi versiya chiqdi").font(.title2.weight(.bold))
            Text("Davom etish uchun ilovani App Store’dan yangilang.")
                .font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            Spacer()
            if let s = session.config?.ios?.storeUrl, let url = URL(string: s) {
                Link(destination: url) {
                    Text("App Store’da yangilash")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Palette.onBrand)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Palette.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(24)
        .background(Palette.bg.ignoresSafeArea())
    }
}
