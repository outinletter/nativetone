import SwiftUI
import UIKit

/// History on its own page: converted sentences only, swipe left to delete.
struct HistoryPage: View {
    @ObservedObject var history: HistoryStore
    @State private var toastVisible = false
    @State private var toastTask: Task<Void, Never>?
    @State private var expanded: Set<Date> = []   // every day starts closed

    /// Items grouped by calendar day, newest day first.
    private var groups: [(day: Date, items: [HistoryItem])] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: history.items) { cal.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { day in
            (day, byDay[day]!.sorted { $0.date > $1.date })
        }
    }

    /// Small pill at the bottom that confirms a copy, then fades away.
    private func showToast() {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.3)) { toastVisible = true }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { toastVisible = false }
        }
    }

    private func title(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return L("오늘", "Today") }
        if cal.isDateInYesterday(day) { return L("어제", "Yesterday") }
        let locale = Locale(identifier: AppSettings.uiLanguage == .ko ? "ko_KR" : "en_US")
        return day.formatted(.dateTime.year().month().day().weekday().locale(locale))
    }

    var body: some View {
        List {
            Text(L("변환된 문장만 이 기기에 저장돼요. 왼쪽으로 밀어 삭제할 수 있어요.", "Only converted sentences are saved, on this device. Swipe left to delete."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if history.items.isEmpty {
                Text(L("아직 기록이 없어요.", "No history yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                // Flat rows (a header row per day, then that day's items when open) so every row
                // has exactly one swipe action of its own.
                ForEach(groups, id: \.day) { group in
                    let open = expanded.contains(group.day)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if open { expanded.remove(group.day) } else { expanded.insert(group.day) }
                        }
                    } label: {
                        HStack {
                            Text(title(for: group.day)).font(.headline)
                            Spacer()
                            Text("\(group.items.count)").font(.subheadline).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.gold)
                                .rotationEffect(.degrees(open ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    // Swipe left on a date to delete everything saved that day.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { history.delete(group.items.map(\.id)) } label: {
                            Label(L("삭제", "Delete"), systemImage: "trash")
                        }
                    }

                    if open {
                        ForEach(group.items) { item in
                            row(item)
                                // Indented, on a tinted background with a gold guide line: reads as part of the day above.
                                .padding(.leading, 12)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(Theme.gold.opacity(0.7)).frame(width: 2)
                                }
                                .listRowBackground(Theme.surface)
                                .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 16))
                                .listRowSeparator(.visible)
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
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if toastVisible {
                Label(L("복사됨", "Copied"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Theme.primary, in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(L("기록", "History"))
        .navigationBarTitleDisplayMode(.inline)
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
        VStack(alignment: .leading, spacing: 3) {
            if !item.original.isEmpty {
                Text(item.original)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(alignment: .top) {
                Text(item.result.best)
                    .font(.body)
                    .lineSpacing(1)
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) {
            UIPasteboard.general.string = item.result.best
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showToast()
        }
        .padding(.vertical, 0)
    }
}
