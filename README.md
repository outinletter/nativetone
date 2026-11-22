# NativeTone

비영어권 사용자가 쓴 영어를 자연스러운 문장으로 바꿔주는 iOS 앱 + 키보드 확장.

- Bundle ID: `com.addvalue.nativetone` (키보드: `com.addvalue.nativetone.keyboard`)
- App Group: `group.com.addvalue.nativetone`
- iOS 17+, SwiftUI, 키보드는 UIKit

## 구조
```
App/        본 앱 (교정 / 기록 / 설정 / 키보드 안내)
Keyboard/   키보드 확장 (QWERTY + ✨ 제안 바 + 톤 전환)
Shared/     앱·키보드 공용 (모델, 설정, 서버 클라이언트)
server/     Claude 프록시 (API 키와 프롬프트는 서버에만 둠)
Tools/      generate_project.rb  → NativeTone.xcodeproj 생성
```

## 실행
1. 프록시 서버
   ```bash
   cd server
   MOCK=1 node server.mjs                     # API 키 없이 테스트
   ANTHROPIC_API_KEY=sk-... node server.mjs   # 실제 Claude 호출 (기본 claude-haiku-5-5)
   ```
2. 프로젝트 파일은 폴더 구조를 바꾼 뒤 `ruby Tools/generate_project.rb` 로 다시 생성합니다.
3. Xcode에서 `NativeTone` 스킴 실행. 실기기는 Signing & Capabilities 에서 Team 을 지정하고 두 타깃 모두 App Groups 를 켜세요.
4. 앱 설정 → 서버 주소 (시뮬레이터 기본값 `http://localhost:8787`, 실기기는 Mac의 LAN 주소 또는 배포 URL).

## 키보드 켜기
설정 → 일반 → 키보드 → 키보드 → 새로운 키보드 추가 → NativeTone → **전체 접근 허용** 켜기.
입력창에서 🌐 로 전환 → 영어 입력 → ✨ 탭 → 제안 탭하면 문장이 교체됩니다.

## 프라이버시 원칙
- ✨ 를 누른(또는 자동 제안이 켜진) 순간의 현재 줄만 전송
- 서버는 사용자 텍스트를 저장·로그하지 않음
- 기록은 기기 로컬에만 저장

## 남은 작업
- 앱 아이콘, App Store 개인정보 항목, 프록시 배포(Cloudflare Workers 등)와 인증
- 키보드: 변경점 팝업, 키 팝업/햅틱, 더블 스페이스 마침표
- v2: 다국어 설명 확장, 표현 퀴즈, 내 말투 학습
