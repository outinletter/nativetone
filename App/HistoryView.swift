import SwiftUI
import UIKit

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @State private var favoritesOnly = false
    @State private var copiedID: UUID?

    private var shown: [HistoryItem] {
        favoritesOnly ? history.items.filter(\.isFavorite) : history.items
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(L("필터", "Filter"), selection: $favoritesOnly) {
                    Text(L("전체", "All")).tag(false)
                    Text(L("즐겨찾기", "Favorites")).tag(true)
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                if shown.isEmpty {
                    ContentUnavailableView(
                        favoritesOnly ? L("즐겨찾기가 없어요", "No favorites yet") : L("아직 기록이 없어요", "No history yet"),
                        systemImage: favoritesOnly ? "star" : "clock",
                        description: Text(L("교정한 문장이 이 기기에만 저장돼요.", "Corrected sentences are stored only on this device."))
                    )
                } else {
                    List {
                        ForEach(shown) { item in
                            row(item)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { history.delete([item.id]) } label: {
                                        Label(L("삭제", "Delete"), systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(L("기록", "History"))
            .toolbar {
                if !history.items.isEmpty {
                    Button(L("비우기", "Clear"), role: .destructive) { history.clear() }
                }
            }
        }
    }

    private func row(_ item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.original)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(alignment: .top) {
                Text(item.result.best)
                    .font(.body)
                Spacer()
                Button { history.toggleFavorite(item) } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(item.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }
            HStack {
                Text("\(item.tone.emoji) \(item.tone.label)")
                Text(item.date, style: .date)
                Spacer()
                Text(copiedID == item.id ? L("복사됨", "Copied") : L("탭하여 복사", "Tap to copy"))
                    .foregroundStyle(copiedID == item.id ? .green : .secondary)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIPasteboard.general.string = item.result.best
            copiedID = item.id
        }
        .padding(.vertical, 4)
    }
}
