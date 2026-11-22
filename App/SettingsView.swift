import SwiftUI

struct SettingsView: View {
    @State private var explainLanguage = AppSettings.explainLanguage
    @State private var tone = AppSettings.tone
    @State private var autoSuggest = AppSettings.autoSuggest
    @State private var baseURL = AppSettings.baseURL
    @State private var appToken = AppSettings.appToken

    var body: some View {
        NavigationStack {
            Form {
                Section("기본 설정") {
                    Picker("설명 언어", selection: $explainLanguage) {
                        ForEach(ExplainLanguage.allCases) { Text($0.nativeName).tag($0) }
                    }
                    Picker("기본 톤", selection: $tone) {
                        ForEach(Tone.allCases) { Text("\($0.emoji) \($0.label)").tag($0) }
                    }
                }

                Section {
                    NavigationLink("키보드 설정 방법") { KeyboardGuideView(isSheet: false) }
                    Toggle("입력하면 자동으로 교정", isOn: $autoSuggest)
                } header: {
                    Text("키보드")
                } footer: {
                    Text("켜두면 3단어 이상 입력하고 잠시 멈출 때 현재 문장이 서버로 전송돼 자연스러운 문장이 키보드 위에 떠요. 끄면 ✨ 버튼을 누를 때만 전송돼요.")
                }

                Section {
                    TextField("서버 주소", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("앱 토큰 (선택)", text: $appToken)
                } header: {
                    Text("개발자")
                } footer: {
                    Text("기본값은 이 Mac에서 실행하는 로컬 프록시(\(AppConfig.defaultBaseURL))예요.")
                }

                Section("개인정보") {
                    Text("입력한 문장은 교정을 위해서만 서버로 전송되며 서버에 저장하거나 로그로 남기지 않아요. 기록은 이 기기에만 보관돼요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("설정")
            .onChange(of: explainLanguage) { AppSettings.explainLanguage = $1 }
            .onChange(of: tone) { AppSettings.tone = $1 }
            .onChange(of: autoSuggest) { AppSettings.autoSuggest = $1 }
            .onChange(of: baseURL) { AppSettings.baseURL = $1 }
            .onChange(of: appToken) { AppSettings.appToken = $1 }
        }
    }
}
