// QOLIP — Magazinlar ro'yxati va sahifasi (directory agenti yozadi, docs/AGENTS.md).
import SwiftUI

struct ShopsView: View {
    var body: some View {
        Text("Magazinlar").navigationTitle("Magazinlar")
    }
}

struct ShopDetailView: View {
    let id: Int
    var body: some View {
        Text("Magazin \(id)")
    }
}
