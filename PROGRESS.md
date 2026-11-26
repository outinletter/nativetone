# PROGRESS — NativeTone

> 새 세션에서 "PROGRESS.md 읽고 이어서 해줘" 라고 하면 이 파일부터 읽고 작업을 이어갑니다.
> **세션을 마칠 때마다 아래 '현재 상태 / 다음 할 일 / 최근 세션 로그'를 갱신하세요.**

_최초 생성: 2026-11-26 (자동 수집 정보 기반)_

## 프로젝트 개요
- **설명:** NativeTone  _(출처: README.md)_
- **유형:** iOS
- **경로:** `/Volumes/Data/Project/NativeTone`
- **먼저 읽을 문서:** `README.md`

## 현재 상태
- App Store 1.0(빌드 9) 심사 통과. 키보드: 2행 상단 바(위 변환 결과·아래 입력 미러), 스타일·되돌리기·↑적용 버튼.
- 이번 세션: 숫자 키 줄 옵션(설정, 기본 꺼짐), 키보드 AI 버튼 삭제(AI 켜기/끄기는 앱 설정에만), 숫자 줄은 글자 줄의 80% 높이·바 아래 8pt 여백, 키 줄 간격 10→7pt, 키 진동은 가장 약하고 짧은 선택 틱(UISelectionFeedbackGenerator). Release 빌드를 아이폰에 설치함(동작은 사용자 확인 전).
- 커밋·푸시함(main).

## 다음 할 일
- [ ] 숫자 줄 높이·짧은 진동이 기기에서 괜찮은지 사용자 확인 받기 — Keyboard/KeyboardViewController.swift `currentHeight`, Keyboard/KeyButton.swift `Haptics`
- [ ] App Store Connect "앱이 수집하는 개인정보"를 '기타 사용자 콘텐츠 / 앱 기능 / 연결 안 됨 / 추적 안 함'으로 게시 (현재 '수집 안 함'으로 게시돼 실제와 다름)
- [ ] 구독 그룹 NativeTone-Free 정리(앱에 구독 기능 없음, 제품 ID monthly인데 기간 3개월)

## 주의사항 / 결정된 사항
- 입력은 항상 호스트 입력창에 직접 들어가고, 상단 바는 미러와 제안만 보여 준다(바 전용 버퍼 방식은 글 유실 문제로 폐기).
- 설치·TestFlight 업로드는 Release 빌드(`-configuration Release`, derivedData `/tmp/claude-501/nt-rel`). 업로드용 ExportOptions.plist는 임시 폴더에서 자주 사라지므로 매번 새로 만든다.
- 빌드 번호는 Tools/generate_project.rb의 CURRENT_PROJECT_VERSION. 파일 추가·삭제 후 `ruby Tools/generate_project.rb` 실행.
- 처리방침: https://outinletter.github.io/privacy-policy/nativetone.html, 지원: …/nativetone-support.html

## 최근 세션 로그
<!-- 최신이 위로. 형식: YYYY-MM-DD — 한 일 / 남은 일 -->
- 2026-11-26 — 숫자 줄 위 여백, 키 줄 간격 축소 / 기기 확인 남음
- 2026-11-26 — 숫자 줄 높이 축소(72%), 진동을 약한 선택 틱으로 / 기기 확인 남음
- 2026-11-26 — 숫자 키 줄 옵션, AI 버튼 삭제, 짧은 키 진동 / 푸시·설치 완료, 기기 확인·개인정보 답변 게시 남음
- 2026-11-26 — PROGRESS.md 생성
