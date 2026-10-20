// QOLIP — Ustalar ro'yxati va sahifasi (directory agenti yozadi, docs/AGENTS.md).
import SwiftUI

struct WorkersView: View {
    var body: some View {
        Text("Ustalar").navigationTitle("Ustalar")
    }
}

struct WorkerDetailView: View {
    let id: Int
    var body: some View {
        Text("Usta \(id)")
    }
}
