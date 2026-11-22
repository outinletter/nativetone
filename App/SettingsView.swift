import SwiftUI

struct SettingsView: View {
    @State private var explainLanguage = AppSettings.explainLanguage
    @State private var tone = AppSettings.tone
    @State private var uiLanguage = AppSettings.uiLanguage
    @State private var autoSuggest = AppSettings.autoSuggest
    @State private var keyboardHeight = AppSettings.keyboardHeight
    @State private var haptics = AppSettings.haptics
    @State private var autoCapitalize = AppSettings.autoCapitalize
    @State private var inputLanguages = AppSettings.inputLanguages

    var body: some View {
        NavigationStack {
            Form {
                Section(L("기본 설정", "General")) {
                    Picker(L("앱 언어", "App language"), selection: $uiLanguage) {
                        ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                    }
                    Picker(L("설명 언어", "Explanation language"), selection: $explainLanguage) {
                        ForEach(ExplainLanguage.allCases) { Text($0.nativeName).tag($0) }
                    }
                    Picker(L("기본 톤", "Default tone"), selection: $tone) {
                        ForEach(Tone.allCases) { Text("\($0.emoji) \($0.label)").tag($0) }
                    }
                }

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
                } header: {
                    Text(L("입력 언어", "Input languages"))
                } footer: {
                    Text(L("영어는 항상 사용할 수 있어요. 켠 언어는 키보드의 언어 키로 전환해요. 일본어는 로마자(예: konnichiwa), 중국어는 병음(예: nihao)으로 입력해요.", "English is always available. Enabled languages are switched with the language key on the keyboard. Type Japanese in romaji (e.g. konnichiwa) and Chinese in pinyin (e.g. nihao)."))
                }

                Section {
                    NavigationLink(L("키보드 설정 방법", "How to set up the keyboard")) { KeyboardGuideView(isSheet: false) }
                    Toggle(L("입력하면 자동으로 교정", "Auto-suggest while typing"), isOn: $autoSuggest)
                    Picker(L("키보드 높이", "Keyboard height"), selection: $keyboardHeight) {
                        ForEach(KeyboardHeight.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle(L("키 입력 진동", "Key haptics"), isOn: $haptics)
                    Toggle(L("문장 시작 자동 대문자", "Auto-capitalize sentences"), isOn: $autoCapitalize)
                } header: {
                    Text(L("키보드", "Keyboard"))
                } footer: {
                    Text(L("켜두면 3단어 이상 입력하고 잠시 멈출 때 현재 문장이 서버로 전송돼 자연스러운 문장이 키보드 위에 떠요. 끄면 키보드 위 문장 영역을 탭할 때만 전송돼요.", "When on, the current sentence is sent to the server after you type 3+ words and pause, and a natural version appears above the keys. When off, it is sent only when you tap the bar above the keys."))
                }

                Section(L("사용법", "How it works")) {
                    Text(L("한국어·일본어·중국어로 입력하면 키보드 안에서 조합되고, 변환하면 자연스러운 영어로 바뀌어 입력돼요.", "Type in Korean, Japanese or Chinese. The text is composed inside the keyboard and, when you convert it, entered as natural English."))
                        .font(.footnote)
                    Text(L("영어로 쓰다가 잠시 멈추면 키보드 위에 자연스러운 문장이 떠요. 문장을 탭하면 바뀌어요.", "Type in English and pause: a natural version appears above the keys. Tap it to replace your text."))
                        .font(.footnote)
                }

                Section(L("개인정보", "Privacy")) {
                    Text(L("입력한 문장은 교정을 위해서만 서버로 전송되며 서버에 저장하거나 로그로 남기지 않아요. 기록은 이 기기에만 보관돼요.", "Text is sent to the server only to be rewritten, and is never stored or logged there. History stays on this device."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle(L("설정", "Settings"))
            .onChange(of: explainLanguage) { AppSettings.explainLanguage = $1 }
            .onChange(of: uiLanguage) {
                AppSettings.uiLanguage = $1
                NotificationCenter.default.post(name: .uiLanguageChanged, object: nil)
            }
            .onChange(of: tone) { AppSettings.tone = $1 }
            .onChange(of: autoSuggest) { AppSettings.autoSuggest = $1 }
            .onChange(of: keyboardHeight) { AppSettings.keyboardHeight = $1 }
            .onChange(of: haptics) { AppSettings.haptics = $1 }
            .onChange(of: autoCapitalize) { AppSettings.autoCapitalize = $1 }
        }
    }
}
