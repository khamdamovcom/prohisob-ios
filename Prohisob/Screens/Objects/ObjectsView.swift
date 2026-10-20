// QOLIP — Obyektlar ro'yxati va sahifasi (directory agenti yozadi, docs/AGENTS.md).
import SwiftUI

struct ObjectsView: View {
    var body: some View {
        Text("Obyektlar").navigationTitle("Obyektlar")
    }
}

struct ObjectDetailView: View {
    let id: Int
    var body: some View {
        Text("Obyekt \(id)")
    }
}
