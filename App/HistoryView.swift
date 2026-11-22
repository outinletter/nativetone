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
                Picker("필터", selection: $favoritesOnly) {
                    Text("전체").tag(false)
                    Text("즐겨찾기").tag(true)
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                if shown.isEmpty {
                    ContentUnavailableView(
                        favoritesOnly ? "즐겨찾기가 없어요" : "아직 기록이 없어요",
                        systemImage: favoritesOnly ? "star" : "clock",
                        description: Text("교정한 문장이 이 기기에만 저장돼요.")
                    )
                } else {
                    List {
                        ForEach(shown) { item in
                            row(item)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { history.delete([item.id]) } label: {
                                        Label("삭제", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("기록")
            .toolbar {
                if !history.items.isEmpty {
                    Button("비우기", role: .destructive) { history.clear() }
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
                Text(copiedID == item.id ? "복사됨" : "탭하여 복사")
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
