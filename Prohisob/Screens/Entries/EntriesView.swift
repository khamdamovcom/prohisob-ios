// QOLIP — Yozuvlar ro'yxati, yozuv sahifasi, «Yangi yozuv» (entries agenti yozadi, docs/AGENTS.md).
import SwiftUI

struct EntriesView: View {
    var filter = EntryFilter()
    var body: some View {
        Text("Yozuvlar").navigationTitle("Yozuvlar")
    }
}

struct EntryDetailView: View {
    let id: Int
    var body: some View {
        Text("Yozuv \(id)")
    }
}

struct NewEntryView: View {
    let prefill: EntryPrefill
    var body: some View {
        Text("Yangi yozuv")
    }
}
