import Foundation

struct HistoryItem: Codable, Identifiable, Hashable {
    var id = UUID()
    let original: String
    let result: RewriteResult
    let tone: Tone
    let date: Date
    var isFavorite = false
}

/// History lives on-device only (never synced or uploaded).
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []
    private let key = "history.v1"
    private let limit = 200

    init() {
        load()
        importKeyboardResults()
    }

    /// Adds sentences applied in the keyboard (converted text only).
    func importKeyboardResults() {
        let records = AppSettings.takeKeyboardResults()
        guard !records.isEmpty, AppSettings.saveHistory else { return }
        for r in records.sorted(by: { $0.date < $1.date }) {
            items.insert(HistoryItem(original: "", result: RewriteResult(best: r.text), tone: r.tone, date: r.date), at: 0)
        }
        trim()
        save()
    }

    /// Only the converted sentence is stored; the user's original text is not kept.
    func add(original: String, result: RewriteResult, tone: Tone) {
        guard AppSettings.saveHistory else { return }
        items.insert(HistoryItem(original: "", result: RewriteResult(best: result.best), tone: tone, date: Date()), at: 0)
        trim()
        save()
    }

    private func trim() {
        if items.count > limit {
            // Keep favorites even when trimming.
            var kept = 0
            items = items.filter { item in
                if item.isFavorite { return true }
                kept += 1
                return kept <= limit
            }
        }
    }

    func toggleFavorite(_ item: HistoryItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].isFavorite.toggle()
        save()
    }

    func delete(_ ids: [UUID]) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func clear() {
        items.removeAll { !$0.isFavorite }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
