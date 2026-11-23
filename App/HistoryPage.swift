import SwiftUI
import UIKit

/// History on its own page: converted sentences only, swipe left to delete.
struct HistoryPage: View {
    @ObservedObject var history: HistoryStore
    @State private var copiedID: UUID?

    var body: some View {
        List {
            if history.items.isEmpty {
                Text(L("아직 기록이 없어요.", "No history yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(history.items) { item in
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
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle(L("기록", "History"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Text(L("변환된 문장만 이 기기에 저장돼요. 왼쪽으로 밀어 삭제할 수 있어요.", "Only converted sentences are saved, on this device. Swipe left to delete."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Theme.paper)
        }
        .toolbar {
            if !history.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
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
                Text(item.tone.label.uppercased()).tracking(1.2)
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
