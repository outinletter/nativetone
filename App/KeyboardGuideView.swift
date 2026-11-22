import SwiftUI
import UIKit

struct KeyboardGuideView: View {
    let isSheet: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Theme.eyebrow(L("키보드 설정", "Keyboard setup"))
                Text(L("어디서든 바로 교정하세요", "Fix your English anywhere"))
                    .font(Theme.serif(28, .semibold))
                Text(L("NativeTone 키보드를 켜면 카카오톡·메시지·WhatsApp 등 모든 앱에서 영어를 쓰다가 한 번의 탭으로 자연스러운 문장으로 바꿀 수 있어요.", "Turn on the NativeTone keyboard and make your English sound natural in any app — Messages, WhatsApp, KakaoTalk — with one tap."))
                    .foregroundStyle(.secondary)

                step(1, L("설정 앱 열기", "Open Settings"), L("아래 버튼으로 NativeTone 설정을 열어요.", "Use the button below to open NativeTone's settings."))
                step(2, L("키보드 추가", "Add the keyboard"), L("키보드 → NativeTone 을 켜세요.", "Go to Keyboards and turn on NativeTone."))
                step(3, L("전체 접근 허용", "Allow Full Access"), L("교정하려면 인터넷 연결이 필요해서 '전체 접근 허용'을 켜야 해요.", "Rewriting needs the internet, so turn on 'Allow Full Access'."))
                step(4, L("키보드 전환", "Switch keyboards"), L("입력창에서 지구본 키를 길게 눌러 NativeTone 을 선택하세요.", "In a text field, press and hold the globe key and choose NativeTone."))

                VStack(alignment: .leading, spacing: 6) {
                    Theme.eyebrow(L("개인정보 안내", "Privacy"))
                    Text(L("교정을 요청한 순간의 현재 문장만 교정을 위해 전송해요. 키 입력은 저장하거나 기록하지 않고, 비밀번호 입력창에서는 키보드가 자동으로 꺼져요.", "Only the current sentence is sent for rewriting. Keystrokes are never stored, and the keyboard turns off automatically in password fields."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(L("설정 열기", "Open Settings"))
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle(L("키보드 설정", "Keyboard Setup"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("나중에", "Later")) { dismiss() }
                }
            }
        }
    }

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
    }
}
