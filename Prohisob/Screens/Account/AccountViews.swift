// QOLIP — Kirish, «Yana», sozlamalar, mijozlar, xodimlar, kabinet tanlash (account agenti yozadi, docs/AGENTS.md).
import SwiftUI

struct LoginView: View {
    var body: some View {
        Text("Kirish")
    }
}

struct MoreView: View {
    var body: some View {
        Text("Yana").navigationTitle("Yana")
    }
}

struct ChangePasswordView: View {
    var body: some View {
        Text("Parol")
    }
}

struct KabinetPickerView: View {
    var body: some View {
        Text("Kabinet")
    }
}

struct ClientsView: View {
    var body: some View {
        Text("Mijozlar")
    }
}

struct UsersView: View {
    var body: some View {
        Text("Xodimlar")
    }
}
