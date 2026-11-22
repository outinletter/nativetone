import SwiftUI
import UIKit

struct KeyboardGuideView: View {
    let isSheet: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("어디서든 바로 교정하세요")
                    .font(.title2.bold())
                Text("NativeTone 키보드를 켜면 카카오톡·메시지·WhatsApp 등 모든 앱에서 영어를 쓰다가 ✨ 한 번으로 자연스러운 문장으로 바꿀 수 있어요.")
                    .foregroundStyle(.secondary)

                step(1, "설정 앱 열기", "아래 버튼으로 NativeTone 설정을 열어요.")
                step(2, "키보드 추가", "키보드 → NativeTone 을 켜세요.")
                step(3, "전체 접근 허용", "교정하려면 인터넷 연결이 필요해서 '전체 접근 허용'을 켜야 해요.")
                step(4, "키보드 전환", "입력창에서 🌐 를 길게 눌러 NativeTone 을 선택하세요.")

                VStack(alignment: .leading, spacing: 6) {
                    Label("개인정보 안내", systemImage: "lock.shield")
                        .font(.headline)
                    Text("✨ 를 누른 순간의 현재 문장만 교정을 위해 전송해요. 키 입력은 저장하거나 기록하지 않고, 비밀번호 입력창에서는 키보드가 자동으로 꺼져요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("설정 열기").fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            }
            .padding()
        }
        .navigationTitle("키보드 설정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("나중에") { dismiss() }
                }
            }
        }
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.subheadline.bold())
                .frame(width: 26, height: 26)
                .background(Color.accentColor, in: Circle())
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
