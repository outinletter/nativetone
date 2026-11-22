import SwiftUI

struct SettingsView: View {
    @State private var explainLanguage = AppSettings.explainLanguage
    @State private var tone = AppSettings.tone
    @State private var uiLanguage = AppSettings.uiLanguage
    @State private var autoSuggest = AppSettings.autoSuggest
    @State private var keyboardHeight = AppSettings.keyboardHeight
    @State private var haptics = AppSettings.haptics
    @State private var autoCapitalize = AppSettings.autoCapitalize

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
                    Text(L("켜두면 3단어 이상 입력하고 잠시 멈출 때 현재 문장이 서버로 전송돼 자연스러운 문장이 키보드 위에 떠요. 끄면 ✨ 버튼을 누를 때만 전송돼요.", "When on, the current sentence is sent to the server after you type 3+ words and pause, and a natural version appears above the keys. When off, it is sent only when you tap ✨."))
                }

                Section(L("개인정보", "Privacy")) {
                    Text(L("입력한 문장은 교정을 위해서만 서버로 전송되며 서버에 저장하거나 로그로 남기지 않아요. 기록은 이 기기에만 보관돼요.", "Text is sent to the server only to be rewritten, and is never stored or logged there. History stays on this device."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
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
