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
                VStack(alignment: .leading, spacing: 16) {
                    inputCard
                    toneChips
                    convertButton

                    if let message = vm.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }

                    if let result = vm.result {
                        ResultCard(result: result, original: vm.input, copy: copy)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("NativeTone")
            .overlay(alignment: .bottom) { toastView }
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $vm.input)
                    .focused($focused)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.sentences)
                if vm.input.isEmpty {
                    Text(L("영어 또는 한국어 문장을 입력하거나 붙여넣으세요", "Type or paste a sentence in English or Korean"))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Button {
                    if let s = UIPasteboard.general.string { vm.input = s }
                } label: {
                    Label(L("붙여넣기", "Paste"), systemImage: "doc.on.clipboard")
                }
                Spacer()
                Text("\(vm.input.count)/\(AppConfig.maxInputLength)")
                    .font(.caption)
                    .foregroundStyle(vm.input.count > AppConfig.maxInputLength ? .red : .secondary)
            }
            .font(.footnote)

            DisclosureGroup(L("상대방 메시지 (선택)", "Message you're replying to (optional)"), isExpanded: $showContext) {
                TextField(L("답장하려는 메시지를 넣으면 맥락에 맞게 고쳐요", "Add the message you're replying to and I'll fit the context"), text: $vm.context, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 4)
            }
            .font(.footnote)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var toneChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(Tone.allCases) { tone in
                    Button {
                        vm.tone = tone
                    } label: {
                        Text("\(tone.emoji) \(tone.label)")
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(vm.tone == tone ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                            .foregroundStyle(vm.tone == tone ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var convertButton: some View {
        Button {
            focused = false
            Task { await vm.run(history: history) }
        } label: {
            HStack {
                if vm.isLoading { ProgressView().tint(.white) }
                Text(vm.isLoading ? L("교정 중…", "Rewriting…") : L("자연스럽게 바꾸기", "Make it natural"))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentColor.opacity(canRun ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .disabled(!canRun)
    }

    private var canRun: Bool {
        !vm.isLoading && !vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 12)
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
        VStack(alignment: .leading, spacing: 14) {
            Text(result.best)
                .font(.title3)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                Button { copy(result.best) } label: {
                    Label(L("복사", "Copy"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                ShareLink(item: result.best) {
                    Label(L("공유", "Share"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            if !result.changes.isEmpty {
                Divider()
                Text(L("바뀐 점", "What changed")).font(.headline)
                ForEach(result.changes) { change in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(change.from)
                                .strikethrough()
                                .foregroundStyle(.red)
                            Image(systemName: "arrow.right").font(.caption)
                            Text(change.to)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        }
                        Text(change.why)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !result.alternatives.isEmpty {
                Divider()
                DisclosureGroup(L("다른 표현 보기", "Other options")) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(result.alternatives, id: \.self) { alt in
                            Button { copy(alt) } label: {
                                Text(alt)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        Text(L("탭하면 복사돼요", "Tap to copy")).font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.top, 6)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}
