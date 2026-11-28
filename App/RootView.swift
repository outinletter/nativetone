import SwiftUI
import UIKit

/// Two pages in a tab bar (Liquid Glass on iOS 26+): settings and history.
struct RootView: View {
    @StateObject private var history = HistoryStore()
    @Environment(\.scenePhase) private var scenePhase

    @State private var uiLanguage = AppSettings.uiLanguage
    @State private var tone = AppSettings.tone
    @State private var autoSuggest = AppSettings.autoSuggest
    @State private var inputLanguages = AppSettings.inputLanguages
    @State private var japaneseLayout = AppSettings.japaneseLayout
    @State private var keyboardHeight = AppSettings.keyboardHeight
    @State private var haptics = AppSettings.haptics
    @State private var hapticStrength = AppSettings.hapticStrength
    @State private var keyPopup = AppSettings.keyPopup
    @State private var doubleSpacePeriod = AppSettings.doubleSpacePeriod
    @State private var showNumberRow = AppSettings.showNumberRow
    @State private var autoCapitalize = AppSettings.autoCapitalize
    @State private var saveHistory = AppSettings.saveHistory
    @State private var aiEnabled = AppSettings.aiEnabled
    @State private var targetLanguage = AppSettings.targetLanguage

    var body: some View {
        TabView {
            NavigationStack {
                content
                    .toolbar(.hidden, for: .navigationBar)
            }
            .tabItem { Label(L("설정", "Settings"), systemImage: "gearshape") }

            NavigationStack {
                HistoryPage(history: history)
            }
            .tabItem { Label(L("기록", "History"), systemImage: "clock.arrow.circlepath") }
        }
    }

    private var content: some View {
        List {
            header
            setupSection
            generalSection
            keyboardSection
            historySection
            privacySection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .listStyle(.insetGrouped)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { history.importKeyboardResults() }
        }
        .onChange(of: uiLanguage) {
            AppSettings.uiLanguage = $1
            NotificationCenter.default.post(name: .uiLanguageChanged, object: nil)
        }
        .onChange(of: tone) { AppSettings.tone = $1 }
        .onChange(of: targetLanguage) { AppSettings.targetLanguage = $1 }
        .onChange(of: autoSuggest) { AppSettings.autoSuggest = $1 }
        .onChange(of: japaneseLayout) { AppSettings.japaneseLayout = $1 }
        .onChange(of: keyboardHeight) { AppSettings.keyboardHeight = $1 }
        .onChange(of: haptics) { AppSettings.haptics = $1 }
        .onChange(of: hapticStrength) { AppSettings.hapticStrength = $1 }
        .onChange(of: keyPopup) { AppSettings.keyPopup = $1 }
        .onChange(of: doubleSpacePeriod) { AppSettings.doubleSpacePeriod = $1 }
        .onChange(of: showNumberRow) { AppSettings.showNumberRow = $1 }
        .onChange(of: autoCapitalize) { AppSettings.autoCapitalize = $1 }
        .onChange(of: saveHistory) { AppSettings.saveHistory = $1 }
        .onChange(of: aiEnabled) { AppSettings.aiEnabled = $1 }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Theme.eyebrow("NativeTone")
            Text(L("문장의 품격을 높입니다", "Precision in every sentence."))
                .font(Theme.serif(30, .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Theme.gold).frame(width: 36, height: 2)
            Text(L("어떤 앱에서든 한국어·일본어·중국어·영어로 입력하면 자연스러운 원어민 영어로 바꿔 드려요.", "Type in Korean, Japanese, Chinese or English in any app and get natural, native-sounding English."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var setupSection: some View {
        Section {
            step(1, L("설정 앱 열기", "Open Settings"), L("아래 버튼으로 NativeTone 설정을 열어요.", "Use the button below to open NativeTone's settings."))
            step(2, L("키보드 추가", "Add the keyboard"), L("키보드 → NativeTone 을 켜세요.", "Go to Keyboards and turn on NativeTone."))
            step(3, L("전체 접근 허용", "Allow Full Access"), L("교정하려면 인터넷 연결이 필요해서 '전체 접근 허용'을 켜야 해요.", "Rewriting needs the internet, so turn on 'Allow Full Access'."))
            step(4, L("키보드 전환", "Switch keyboards"), L("입력창에서 지구본 키를 길게 눌러 NativeTone 을 선택하세요.", "In a text field, press and hold the globe key and choose NativeTone."))
            step(5, L("음성 입력(마이크)", "Voice input (mic)"),
                 "한국어: 설정 → 일반 → 키보드 → 키보드 → 새로운 키보드 추가에서 한국어를 추가하고, 받아쓰기 켜기가 켜져 있는지 확인하세요. 그다음 NativeTone의 마이크를 누르세요.\n\n" +
                 "日本語: 設定 → 一般 → キーボード → キーボード → 新しいキーボードを追加で日本語を追加し、音声入力をオンにしてください。その後、NativeToneのマイクをタップします。\n\n" +
                 "中文: 设置 → 通用 → 键盘 → 键盘 → 添加新键盘，添加中文键盘，并确认已开启“听写”。然后点击 NativeTone 的麦克风。")
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Text(L("설정 열기", "Open Settings"))
            }
            .buttonStyle(PrimaryButtonStyle())
            .listRowBackground(Color.clear)
        } header: {
            Theme.eyebrow(L("키보드 설정", "Keyboard setup"))
        }
        .listRowBackground(Theme.surface)
    }

    private var generalSection: some View {
        Section {
            Picker(L("앱 언어", "App language"), selection: $uiLanguage) {
                ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
            }
            Picker(L("교정 언어", "Rewrite language"), selection: $targetLanguage) {
                ForEach(TargetLanguage.allCases) { Text($0.nativeName).tag($0) }
            }
            Picker(L("기본 톤", "Default tone"), selection: $tone) {
                ForEach(Tone.allCases) { Text($0.label).tag($0) }
            }
        } header: {
            Theme.eyebrow(L("일반", "General"))
        } footer: {
            Text(L("입력한 문장이 선택한 언어의 자연스러운 원어민 표현으로 바뀌어요.", "Your text is rewritten as natural, native-sounding text in the selected language."))
        }
        .listRowBackground(Theme.surface)
    }

    private var keyboardSection: some View {
        Section {
            ForEach(InputLanguage.allCases) { lang in
                Toggle(lang.nativeName, isOn: Binding(
                    get: { inputLanguages.contains(lang) },
                    set: { on in
                        if on { inputLanguages.insert(lang) } else { inputLanguages.remove(lang) }
                        AppSettings.inputLanguages = inputLanguages
                    }
                ))
            }
            Picker(L("일본어 자판", "Japanese layout"), selection: $japaneseLayout) {
                ForEach(JapaneseLayout.allCases) { Text($0.label).tag($0) }
            }
            Toggle(L("AI 교정", "AI rewriting"), isOn: $aiEnabled)
            Toggle(L("입력하면 자동으로 교정", "Auto-suggest while typing"), isOn: $autoSuggest)
            Picker(L("키보드 높이", "Keyboard height"), selection: $keyboardHeight) {
                ForEach(KeyboardHeight.allCases) { Text($0.label).tag($0) }
            }
            Toggle(L("숫자 키 줄 보이기", "Show number row"), isOn: $showNumberRow)
            Toggle(L("키 입력 진동", "Key haptics"), isOn: $haptics)
            if haptics {
                Picker(L("진동 세기", "Haptic strength"), selection: $hapticStrength) {
                    ForEach(HapticStrength.allCases) { Text($0.label).tag($0) }
                }
            }
            Toggle(L("키 누를 때 크게 보기", "Key press preview"), isOn: $keyPopup)
            Toggle(L("스페이스 두 번으로 마침표", "Double-space period"), isOn: $doubleSpacePeriod)
            Toggle(L("문장 시작 자동 대문자", "Auto-capitalize sentences"), isOn: $autoCapitalize)
        } header: {
            Theme.eyebrow(L("키보드", "Keyboard"))
        } footer: {
            Text(L("영어는 항상 사용할 수 있어요. 켠 언어는 키보드의 언어 키로 전환해요. 일본어는 가나(플릭) 또는 로마자, 중국어는 병음(예: nihao)으로 입력해요. 자동 교정을 켜면 입력을 멈출 때 현재 문장이 서버로 전송돼요. 블루투스 키보드를 연결하면 iOS가 서드파티 키보드로 키 입력을 보내지 않아서, 언어는 설정 → 일반 → 키보드에 추가한 Apple 키보드(예: 한국어) 사이에서만 바뀌어요.", "English is always available. Enabled languages are switched with the language key. Type Japanese in kana (flick) or romaji and Chinese in pinyin (e.g. nihao). With auto-suggest on, the current sentence is sent to the server when you pause. With a Bluetooth keyboard, iOS doesn't send keystrokes to third-party keyboards, so you can only switch between the Apple keyboards added in Settings → General → Keyboard (e.g. Korean)."))
        }
        .listRowBackground(Theme.surface)
    }

    private var historySection: some View {
        Section {
            Toggle(L("기록 저장", "Save history"), isOn: $saveHistory)
        } header: {
            Theme.eyebrow(L("기록", "History"))
        } footer: {
            Text(L("변환된 문장만 이 기기에 저장해요. 입력한 원문은 저장하지 않아요.", "Only the converted sentence is saved, on this device. Your original text is never saved."))
        }
        .listRowBackground(Theme.surface)
    }

    private var privacySection: some View {
        Section {
            Text(L("교정을 요청한 순간의 현재 문장만 서버로 전송해요. 키 입력은 저장하거나 기록하지 않고, 비밀번호 입력창에서는 키보드가 자동으로 꺼져요.", "Only the current sentence is sent for rewriting. Keystrokes are never stored, and the keyboard turns off automatically in password fields."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link(L("개인정보 처리방침", "Privacy policy"), destination: URL(string: "https://outinletter.github.io/privacy-policy/nativetone.html")!)
            Link(L("지원", "Support"), destination: URL(string: "https://outinletter.github.io/privacy-policy/nativetone-support.html")!)
        } header: {
            Theme.eyebrow(L("개인정보", "Privacy"))
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Rows

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(Theme.serif(16, .semibold))
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.gold, lineWidth: 1))
                .foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
