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
                .padding(.bottom, 8)

                if shown.isEmpty {
                    ContentUnavailableView(
                        favoritesOnly ? L("즐겨찾기가 없어요", "No favorites yet") : L("아직 기록이 없어요", "No history yet"),
                        systemImage: favoritesOnly ? "bookmark" : "text.quote",
                        description: Text(L("교정한 문장이 이 기기에만 저장돼요.", "Corrected sentences are stored only on this device."))
                    )
                } else {
                    List {
                        ForEach(shown) { item in
                            row(item)
                                .listRowBackground(Theme.paper)
                                .listRowSeparatorTint(Theme.hairline)
                                // Swipe left to delete; a full swipe deletes immediately.
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { history.delete([item.id]) } label: {
                                        Label(L("삭제", "Delete"), systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle(L("기록", "History"))
            .toolbar {
                if !history.items.isEmpty {
                    Button(L("비우기", "Clear"), role: .destructive) { history.clear() }
                        .font(.subheadline)
                }
            }
        }
    }

    private func row(_ item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !item.original.isEmpty {
                Text(item.original)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(alignment: .top) {
                Text(item.result.best)
                    .font(Theme.serif(18))
                    .lineSpacing(3)
                Spacer()
                Button { history.toggleFavorite(item) } label: {
                    Image(systemName: item.isFavorite ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(item.isFavorite ? Theme.gold : .secondary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Text(item.tone.label.uppercased())
                    .tracking(1.2)
                Text(item.date, style: .date)
                Spacer()
                Text(copiedID == item.id ? L("복사됨", "Copied") : L("탭하여 복사", "Tap to copy"))
                    .foregroundStyle(copiedID == item.id ? Theme.gold : Color.secondary)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIPasteboard.general.string = item.result.best
            copiedID = item.id
        }
        .padding(.vertical, 6)
    }
}
