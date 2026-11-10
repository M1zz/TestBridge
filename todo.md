# TestBridge todo

## Xcode 프로젝트 생성 (2026-11-09)
- [x] `TestBridge.xcodeproj` 생성 (앱 + CLI + Core 유닛 테스트)
- [x] `Runner/TestBridgeRunner.xcodeproj` 생성 (iOS / macOS / watchOS 러너)
- [x] TestBridge 앱 빌드 통과
- [x] testbridge CLI 빌드 통과
- [x] Runner 3개 플랫폼 build-for-testing 통과
- [x] .gitignore에서 `*.xcodeproj` 제외 해제 (프로젝트 파일을 저장소에 포함)

## 테스트 영역을 "HIG 위배 검사"로 전환 (2026-11-09)
- [x] HIG 규칙 카탈로그 + 규칙 엔진 (`HIGAudit.swift`, `HIGAuditor.swift`, 14개 규칙, 한국어 HIG 링크)
- [x] Runner `higAudit` 스텝 (XCUIElementSnapshot 한 번으로 전체 요소 수집)
- [x] RunReport에 `higAudits` 추가 (구버전 리포트 호환)
- [x] Claude 프롬프트: HIG 규칙 표 + "Review HIG compliance" 모드 + `higReview` 응답 파싱
- [x] 앱: HIG 탭(검사 실행 · 심각도 필터 · HIG 링크 · Claude 검토 요청), Runs 탭 요약, ⇧⌘H
- [x] CLI: `testbridge hig`, `testbridge rules`, `run` 출력에 HIG 결과, `prompt --mode hig --hig-report`
- [x] 유닛 테스트 13개 통과 (`TestBridgeCoreTests`)
- [x] 새 화면 문자열 String Catalog(en/ko) 적용
- [x] README / CLAUDE.md 스니펫 / Examples 갱신
- [x] 실제 시뮬레이터 앱 대상 end-to-end 검사 확인 (iOS 설정 앱: 164개 요소, 받아쓰기 버튼 17×22pt 오류 검출)
- [x] 창 콘텐츠 잘림 수정: NavigationSplitView detail의 HSplitView를 실제 컬럼 크기로 고정, Claude 탭 모드 피커를 세그먼트→메뉴로 변경(고정 폭 670pt가 원인)
- [x] 앱 내 가이드 "Claude Code에게 직접 요청하고 플랜 붙여넣기" (Copy prompt → Claude Code → Paste reply → Save and run 흐름, 예시 채우기+프롬프트 복사, 플랜 형식 포함 템플릿 복사, en/ko) + README 섹션
- [x] Runner가 플랜 실패를 XCTFail로 올리지 않게 변경 (실패 시 xcodebuild가 시뮬레이터 진단 수집에 600초 멈춤, Xcode 27) — 합격/불합격은 report.json으로
- [x] 클립키보드 시나리오 4개 (`Examples/clipkeyboard/`, 앱 플랜 탭에 import): 탭 4개 HIG · 단축어 만들기 · 설정 하위 5화면 HIG · 키보드 미리보기. 시뮬레이터에서 전부 끝까지 실행 확인

## 버전 높은 앱부터 테스트 (2026-11-11)
- [x] 클립키보드 5.1.20: 플랜 4개를 최신 빌드에 맞춰 고치고 전부 실행 (백지 첫 실행 · 탭 숨김 인자, 뒤로 버튼, 실제 페이월 추가). 결과는 `Examples/clipkeyboard/README.md`
- [x] CLI SwiftPM 빌드 오류 수정 (`ShellError` public init)
- [ ] 다음 차례: 탭클립키보드 5.1.9(macOS) → 달빛 4.1.2 → 골드위크 2.4.5 → 두번알림 2.3.6

## 후속
- [ ] HIG 검사: 같은 탭 안에 겹쳐 둔 비가시 화면(클립키보드 목록 밑 키보드 미리보기)의 요소가 함께 잡힘 — 불투명한 형제 뷰에 완전히 덮인 요소 제외 검토
- [ ] HIG 검사: SwiftUI Toggle의 스위치 요소 `missing-label` 거짓 양성 가능성 확인
- [ ] 기존 화면(Claude Code · Plans · Runs · Devices) 문자열도 String Catalog로 이전 (현재 영어 하드코딩)
- [ ] 기존 화면의 `.caption` / `.caption2` 폰트를 `.body` 이상으로 정리
- [ ] HIG 규칙 추가 후보: 내비게이션 바 제목 없음, 토글 라벨, 세그먼트 항목 수, 스크롤 가능한 콘텐츠 표시
- [ ] 색 대비 검사(스크린샷 픽셀 분석) — 트리로는 불가능, 별도 접근 필요
