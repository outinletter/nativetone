import SwiftUI
import UIKit

@MainActor
final class RewriteViewModel: ObservableObject {
    @Published var input = ""
    @Published var context = ""
    @Published var tone: Tone = AppSettings.tone {
        didSet { AppSettings.tone = tone }
    }
    @Published var result: RewriteResult?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func run(history: HistoryStore) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let r = try await NativeToneClient.shared.rewrite(
                text: input,
                tone: tone,
                context: context,
                explainLanguage: AppSettings.explainLanguage
            )
            result = r
            history.add(original: input.trimmingCharacters(in: .whitespacesAndNewlines), result: r, tone: tone)
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }
}

struct RewriteView: View {
    @EnvironmentObject private var history: HistoryStore
    @StateObject private var vm = RewriteViewModel()
    @State private var showContext = false
    @State private var toast: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    inputCard
                    toneTabs
                    convertButton

                    if let message = vm.errorMessage {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.danger)
                    }

                    if let result = vm.result {
                        ResultCard(result: result, original: vm.input, copy: copy)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Theme.paper.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) { toastView }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Theme.eyebrow("NativeTone")
            Text(L("문장의 품격을 높입니다", "Precision in every sentence."))
                .font(Theme.serif(30, .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Theme.gold).frame(width: 36, height: 2)
        }
        .padding(.top, 12)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $vm.input)
                    .focused($focused)
                    .font(Theme.serif(18))
                    .frame(minHeight: 130)
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.sentences)
                if vm.input.isEmpty {
                    Text(L("영어, 한국어, 일본어, 중국어 문장을 입력하거나 붙여넣으세요", "Type or paste a sentence in English, Korean, Japanese or Chinese"))
                        .font(Theme.serif(18))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack {
                Button {
                    if let s = UIPasteboard.general.string { vm.input = s }
                } label: {
                    Text(L("붙여넣기", "Paste"))
                }
                Spacer()
                Text("\(vm.input.count) / \(AppConfig.maxInputLength)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(vm.input.count > AppConfig.maxInputLength ? Theme.danger : .secondary)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.primary)

            DisclosureGroup(L("상대방 메시지 (선택)", "Message you're replying to (optional)"), isExpanded: $showContext) {
                TextField(L("답장하려는 메시지를 넣으면 맥락에 맞게 고쳐요", "Add the message you're replying to and I'll fit the context"), text: $vm.context, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline, lineWidth: 1))
                    .padding(.top, 6)
            }
            .font(.footnote)
            .tint(Theme.primary)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))
    }

    private var toneTabs: some View {
        VStack(alignment: .leading, spacing: 8) {
            Theme.eyebrow(L("톤", "Tone"))
            HStack(spacing: 22) {
                ForEach(Tone.allCases) { tone in
                    Button {
                        vm.tone = tone
                    } label: {
                        VStack(spacing: 6) {
                            Text(tone.label)
                                .font(.system(size: 15, weight: vm.tone == tone ? .semibold : .regular))
                                .foregroundStyle(vm.tone == tone ? Theme.primary : .secondary)
                            Rectangle()
                                .fill(vm.tone == tone ? Theme.gold : .clear)
                                .frame(height: 2)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var convertButton: some View {
        Button {
            focused = false
            Task { await vm.run(history: history) }
        } label: {
            HStack(spacing: 8) {
                if vm.isLoading { ProgressView().tint(Theme.onPrimary) }
                Text(vm.isLoading ? L("교정 중…", "Rewriting…") : L("자연스럽게 바꾸기", "Make it natural"))
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canRun)
    }

    private var canRun: Bool {
        !vm.isLoading && !vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Theme.onPrimary)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        withAnimation { toast = L("복사했어요", "Copied") }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation { toast = nil }
        }
    }
}

struct ResultCard: View {
    let result: RewriteResult
    let original: String
    let copy: (String) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Theme.eyebrow(L("교정 결과", "Rewritten"))
                Text(result.best)
                    .font(Theme.serif(22))
                    .lineSpacing(4)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    Button { copy(result.best) } label: { Text(L("복사", "Copy")) }
                        .buttonStyle(OutlineButtonStyle())
                    ShareLink(item: result.best) { Text(L("공유", "Share")) }
                        .buttonStyle(OutlineButtonStyle())
                }

                if !result.changes.isEmpty {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    Theme.eyebrow(L("바뀐 점", "What changed"))
                    ForEach(result.changes) { change in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(change.from)
                                    .strikethrough()
                                    .foregroundStyle(.secondary)
                                Text("→").foregroundStyle(Theme.gold)
                                Text(change.to)
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                            Text(change.why)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !result.alternatives.isEmpty {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    DisclosureGroup(L("다른 표현 보기", "Other options")) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(result.alternatives, id: \.self) { alt in
                                Button { copy(alt) } label: {
                                    Text(alt)
                                        .font(Theme.serif(16))
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                            Text(L("탭하면 복사돼요", "Tap to copy")).font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.top, 8)
                    }
                    .font(.subheadline.weight(.medium))
                    .tint(Theme.primary)
                }
            }
        }
    }
}
