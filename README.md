# TestBridge

**이 앱, Apple 휴먼 인터페이스 가이드라인(HIG)을 위배하지 않았나?** — iOS · iPadOS · watchOS · macOS 앱을 실제로 띄워 화면마다 검사하고, 그 판단을 **Claude Code와 함께** 내리는 macOS 앱입니다.

기준: https://developer.apple.com/kr/design/human-interface-guidelines

TestBridge가 하는 일은 세 겹입니다.

1. **자동 측정.** XCUITest로 대상 앱을 띄우고 화면의 모든 요소(타입 · 라벨 · 식별자 · 프레임 · 활성 상태)를 스냅샷한 뒤, HIG에서 수치로 확인할 수 있는 규칙을 돌립니다 — 44×44pt 미만 터치 영역, 접근성 라벨 없는 컨트롤, 11pt 미만으로 보이는 텍스트, 겹치거나 화면 밖에 걸친 컨트롤, 버튼 안의 버튼, 5개 넘는 탭, 버튼이 너무 많은 알림창, 44pt 미만 목록 행, 제목 없는 macOS 윈도우 등. 각 결과에는 해당 HIG 페이지 링크가 붙습니다(`testbridge rules`).
2. **Claude의 판단.** 자동 결과와 요소 목록, 스크린샷을 Claude Code에 넘기면 오탐을 걸러내고, 규칙이 못 재는 것(문구, 계층, 컨트롤 선택, 플랫폼 관례)을 HIG 페이지를 인용해 지적하며, 아직 안 본 화면을 검사할 플랜을 돌려줍니다. 정보가 모자라면 질문이 오고 앱이 입력 폼을 띄웁니다.
3. **터미널에서도 똑같이.** `testbridge hig --bundle-id … --json` 한 줄로 첫 화면을 검사하고, `higAudit` 스텝이 든 JSON 플랜으로 깊은 화면까지 들어갑니다. CLAUDE.md 스니펫을 붙이면 프로젝트 안의 Claude Code가 GUI 없이 검사 → 판단 → 수정 루프를 돕니다.

사용자 프로젝트는 건드리지 않습니다. 번들 ID만 있으면 됩니다.

---

## 아키텍처

```
┌──────────────────────────────┐          ┌──────────────────────────────┐
│  TestBridge.app (SwiftUI)    │  prompt  │  Claude Code                 │
│  · Claude Code 탭            │ ───────▶ │  (claude -p 헤드리스, 또는    │
│  · Plans / Runs / Devices    │ ◀─────── │   개발자가 붙여넣기)          │
│  · Inbox 폴더 감시           │  JSON    └──────────────┬───────────────┘
└──────────────┬───────────────┘   reply                 │ testbridge CLI
               │ TestPlan JSON (base64 env)              │ snapshot / run / import
               ▼                                         ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  xcodebuild test  -project Runner/TestBridgeRunner.xcodeproj             │
│  scheme: Runner-iOS | Runner-watchOS | Runner-macOS                      │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ PlanRunnerTests (XCUITest)                                        │   │
│  │  PlanInterpreter: JSON 스텝 → XCUIElement 조작                     │   │
│  │  XCUIApplication(bundleIdentifier:) → 대상 앱을 그대로 띄움        │   │
│  │  결과: report.json + 스크린샷 + 접근성 트리 덤프                   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘
```

**왜 이렇게 했나**

- UI 자동화 엔진으로 XCUITest 외의 선택지는 4개 플랫폼을 다 커버하지 못합니다. 접근성 API를 직접 두드리는 방식은 macOS에서만 되고, 시뮬레이터 내부 앱에는 닿지 않습니다.
- 테스트 코드를 생성하는 대신 **JSON 플랜을 런타임에 해석**합니다. `XCUIApplication(bundleIdentifier:)`로 어떤 앱이든 띄울 수 있어서 **사용자 프로젝트를 전혀 건드리지 않습니다.** 매 플랜마다 컴파일도 없습니다(첫 Runner 빌드 한 번뿐).
- LLM이 쓰기 쉬운 포맷이 곧 사람이 읽기 쉬운 포맷입니다. Swift 코드보다 JSON 플랜이 Claude에게 훨씬 안정적으로 나옵니다.

---

## 설치

요구사항: macOS 14+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), (선택) Claude Code CLI

```zsh
./bootstrap.sh
```

이 스크립트가 하는 일:
- `Runner/TestBridgeRunner.xcodeproj`, `TestBridge.xcodeproj` 재생성 (둘 다 저장소에 포함되어 있어 Xcode에서 바로 열어도 됩니다. `project.yml`을 고쳤을 때만 재생성이 필요합니다)
- `testbridge` CLI를 `~/.local/bin`에 설치
- 앱의 Runner 경로 기본값 설정

유닛 테스트: `TestBridgeCoreTests` 스킴(HIG 규칙 엔진, 플랜 DSL, Claude 응답 파서) 또는 `swift test`.

이후 `TestBridge.xcodeproj`를 열고 `TestBridge` 스킴을 실행하세요. CLI는 `export TESTBRIDGE_RUNNER_PROJECT=<repo>/Runner/TestBridgeRunner.xcodeproj` 후 `testbridge doctor`.

> macOS 앱을 테스트하려면 Xcode(정확히는 xcodebuild의 테스트 러너)에 **손쉬운 사용 → 접근성** 권한을 줘야 합니다. 첫 실행에서 시스템이 물어봅니다.

---

## HIG 검사 루프 (GUI)

1. 사이드바 하단 **Target**에서 플랫폼 · 번들 ID · 디바이스를 고릅니다. `~/Library/Application Support/TestBridge/Apps.json`에 내 앱 목록(`[{"name": "…", "bundleIdentifier": "…", "platform": "ios"}]`)을 두면 번들 ID 옆 메뉴에서 이름으로 고를 수 있습니다.
2. **HIG** 탭 → **Audit first screen** (⇧⌘H). 앱이 뜨고 첫 화면의 모든 요소가 측정됩니다. 결과는 심각도별로 나뉘고, 항목마다 HIG 페이지 링크가 있습니다.
3. **Ask Claude to review** → Claude Code 탭이 "Review HIG compliance" 모드로 열립니다. **Send to Claude Code**(headless) 또는 **Copy prompt**로 보내면 `higReview` 응답이 옵니다: 판정(pass / needs-work / fail), 요약, HIG 링크가 붙은 항목들, 그리고 다음 화면들을 검사할 플랜.
4. 플랜이 왔으면 **Save and run**. 플랜은 화면을 돌며 `higAudit`을 실행하고, 결과는 Runs 탭과 HIG 탭에 화면별로 쌓입니다.

### Claude가 돌려주는 HIG 리뷰 형식

```json
{"kind":"higReview","verdict":"needs-work","summary":"...",
 "findings":[{"rule":"target-size","severity":"error","element":"button \"Close\"","issue":"...","hig":"https://developer.apple.com/kr/design/human-interface-guidelines/layout","fix":"..."}],
 "nextPlan":{ ...higAudit 스텝이 든 플랜... }}
```

### 터미널에서

```zsh
testbridge hig --bundle-id com.you.App --platform ios --json        # 첫 화면 검사, 위배 시 exit 1
testbridge rules --platform ios                                     # 규칙 목록 + HIG 링크
testbridge run Examples/hig-audit-ios.json --json                   # 여러 화면 검사
testbridge prompt --mode hig --hig-report <run-dir>/hig-home.json   # Claude에게 줄 프롬프트
testbridge claude-md --bundle-id com.you.App --platform ios         # CLAUDE.md 스니펫
```

---

## Claude Code 루프 (GUI)

1. 사이드바 하단 **Target**에서 플랫폼 · 번들 ID · 디바이스를 고릅니다. Devices 탭에서 시뮬레이터에 설치된 앱 목록을 클릭해 번들 ID를 채울 수 있습니다.
2. **Capture snapshot** (⇧⌘S) — 앱을 띄우고 접근성 트리를 덤프합니다. 이게 있어야 Claude가 존재하는 identifier만 씁니다.
3. **Claude Code** 탭, 모드 선택:
   - **Ask how to test** — "이 앱을 TestBridge로 어떻게 테스트하면 좋을까?" Claude가 접근 방식, 앱이 노출해야 할 identifier, 그리고 다음 단계에 붙여넣을 프롬프트를 돌려줍니다.
   - **Generate a plan** — 실행 가능한 플랜 JSON. 정보가 모자라면 **질문 목록**이 옵니다 → 왼쪽에 입력 폼이 생기고, 답하면 같은 세션(`--resume`)으로 이어갑니다.
   - **Diagnose a failed run** — Runs 탭에서 실패한 실행의 **Ask Claude to diagnose**를 누르면 스텝 결과와 실패 시점의 접근성 트리가 프롬프트에 들어갑니다.
4. **Send to Claude Code** (`claude -p` 헤드리스) 또는 **Copy prompt** → 터미널의 Claude Code에 붙여넣기 → 답을 오른쪽 **Paste a reply**에 붙여넣기.
5. 플랜이 오면 **Save and run**. 결과는 Runs 탭에 스텝별 상태, 스크린샷, 트리 덤프로 나옵니다.

### Claude Code에게 직접 요청하고 붙여넣기

앱이 Claude를 직접 부르지 않아도 됩니다. 요청은 내가 Claude Code 터미널에서 하고, 답(JSON)을 앱에 붙여넣으면 그대로 테스트가 돕니다. 앱 안에도 같은 가이드가 있습니다 (Claude Code 탭 Mode 아래 링크, 플랜 탭 빈 화면 버튼).

1. **요청 쓰고 복사** — "What do you want to test?"에 목표를 적고 **Copy prompt**. 복사본에는 플랜 형식, Target(플랫폼·번들 ID·기기), 캡처한 접근성 스냅샷, 답변 형식이 이미 들어 있습니다. `claude` CLI 없이도 됩니다.
2. **Claude Code에 붙여넣기** — 프로젝트 터미널이 제일 좋습니다. Claude가 앱 코드를 읽고 빠진 identifier를 직접 추가할 수 있으니까요.
3. **답을 붙여넣고 실행** — 오른쪽 **Paste a reply from Claude Code** → **Parse reply** → **Save and run**. 맨몸의 플랜 JSON도 인식합니다.

좋은 요청에는 다섯 가지가 들어갑니다.

1. **어떤 화면·흐름인지, 순서대로** — "실행 → 일반 → 정보". 플랜 하나에 흐름 하나, 15스텝 안쪽.
2. **시작 상태** — 로그인 여부, 테스트 계정, 있어야 하는 데이터. 앱이 `-uiTesting` 인자로 상태를 세팅한다면 그것도.
3. **무엇을 확인해야 하는지** — HIG 검사를 할 화면, 보여야 하는 텍스트·요소, `failOn` 수준.
4. **알고 있는 식별자** — 먼저 **Capture snapshot**, **Include accessibility snapshot** 켜 두기, 명명 규칙(`screen.element`) 적기.
5. **플랫폼과 기기** — 사이드바 Target에서 들어갑니다. iPad·Mac에서도 돌아야 하면 명시.

예시 (Extra context까지):

```text
앱을 실행해서 첫 화면 → 일반 → 정보 순서로 이동하면서 각 화면을 HIG 기준으로 검사해 줘.
화면마다 higAudit과 screenshot을 넣어 줘. 정보 화면에서는 "소프트웨어 버전" 텍스트가 보이는지 확인해 줘. failOn은 "error"로.

식별자 규칙: screen.element (예: settings.general). 로그인 불필요. 기기: 사이드바에서 선택한 시뮬레이터.
```

앱 없이 요청을 직접 타이핑할 때는 Claude가 플랜 형식을 알아야 하므로, 가이드의 **플랜 형식 포함해서 템플릿 복사**를 쓰거나 `testbridge schema` 출력을 함께 붙여 주세요.

```text
아래 플랜 형식에 맞춰 ios용 com.you.App 앱의 TestBridge 플랜 JSON을 딱 하나 작성해 줘.
목표: <어떤 흐름인지, HIG 검사할 화면, 보여야 하는 것>
시작 상태: <로그인 여부, 테스트 계정, 시드 데이터>
앱에 실제로 있는 식별자만 써 (소스나 스냅샷으로 확인). 식별자가 없는 요소는 tapCoordinate 대신 앱 코드에 식별자를 추가해서 써.
TestBridge에 바로 붙여넣을 수 있게 {"kind":"plan","plan":{...},"notes":"..."} JSON만 답해 줘.
```

피할 것: 화면 이름 없는 "전부 테스트해 줘", 좌표 탭 요청, 한 플랜에 여러 흐름, Claude가 테스트 계정을 안다고 가정하기, JSON 앞뒤 설명문까지 붙여넣기.
답이 플랜 대신 **질문**이면 터미널에서 바로 답하고 다음 답을 붙여넣으면 됩니다. 실행이 실패하면 Runs 탭 → **Ask Claude to diagnose** → **Copy prompt** → 붙여넣기 → 수정된 플랜 붙여넣기.

### Claude가 지켜야 하는 응답 프로토콜

앱이 프롬프트 끝에 붙이는 규격입니다. 파서(`ClaudeCLI.parse`)는 코드펜스·앞뒤 잡담을 걷어내고 첫 JSON 객체를 찾습니다.

```json
{"kind":"plan","plan":{...},"notes":"..."}
{"kind":"questions","questions":[{"id":"test_account","question":"...","why":"...","example":"..."}]}
{"kind":"explanation","approach":"...","suggestedPrompt":"...","questions":[]}
{"kind":"unsupported","reason":"...","alternative":"..."}
```

맨몸의 플랜 JSON을 붙여넣어도 인식합니다.

---

## Claude Code 루프 (터미널, GUI 없이)

프로젝트의 `CLAUDE.md`에 아래를 붙이면(`testbridge claude-md --bundle-id com.you.App --platform ios`로 생성) Claude Code가 혼자 돕니다.

```zsh
testbridge doctor
testbridge devices --json
testbridge snapshot --bundle-id com.you.App --platform ios          # 접근성 트리 출력
testbridge schema                                                   # DSL 레퍼런스
testbridge run UITests/plans/login.json --json                      # 종료코드 0/1 + 리포트 JSON
testbridge import UITests/plans/login.json                          # 실행 중인 GUI로 넘기기
```

`import`는 `~/Library/Application Support/TestBridge/Inbox/`에 파일을 떨어뜨리고, 앱이 폴더를 감시하다가 Plans에 추가합니다. Claude Code가 그 폴더에 JSON을 직접 써도 됩니다.

---

## 플랜 DSL 한눈에

```json
{
  "name": "Login happy path",
  "platform": "ios",
  "bundleIdentifier": "com.example.MyApp",
  "launchArguments": ["-uiTesting"],
  "steps": [
    { "action": "typeText", "target": { "id": "login.email" }, "text": "qa@example.com" },
    { "action": "tap", "target": { "type": "button", "label": "Sign In" } },
    { "action": "assertExists", "target": { "labelContains": "Welcome" }, "timeout": 10 },
    { "action": "screenshot", "name": "home" }
  ]
}
```

액션: `launch terminate activate tap doubleTap longPress typeText swipe scrollTo tapCoordinate wait assertExists assertNotExists assertText assertEnabled pressKey(macOS) rotate(iOS) screenshot dumpTree higAudit`

`higAudit`은 `{ "action": "higAudit", "name": "<화면 이름>", "failOn": "error" | "warning" | "info" | "none" }` — 화면마다 다른 이름을 주고, 여러 화면을 검사하는 플랜은 `"stopOnFailure": false`로 두세요.
타겟 매처: `id label labelContains text type index` — 전체 표는 `testbridge schema` 또는 `Sources/TestBridgeCore/Claude/PlanSchema.swift`.

`Examples/`에 iOS · macOS · watchOS 예제와 Claude 질문 응답 예시가 있습니다.

---

## 솔직한 한계 (읽고 시작하세요)

- **첫 실행은 느립니다.** Runner를 플랫폼별로 한 번 컴파일합니다(1–3분). 이후엔 플랜마다 수 초 + 테스트 시간.
- **실기기**는 서명이 필요합니다. `Runner/project.yml`의 `DEVELOPMENT_TEAM`을 채우고 `-destination 'platform=iOS,id=…'`를 쓰면 되지만, 리포트/스크린샷을 호스트 파일시스템에 바로 못 쓰므로 `.xcresult` 첨부에서 꺼내는 폴백 경로를 탑니다. 현재 CLI/앱의 디바이스 목록은 시뮬레이터만 보여줍니다.
- **watchOS `typeText`는 신뢰하지 마세요.** 하드웨어 키보드가 없습니다. 상태는 `launchEnvironment`로 주입하는 편이 맞습니다.
- **접근성 identifier가 없는 앱은 테스트하기 어렵습니다.** 이건 도구 한계가 아니라 앱 문제이고, Claude의 "Ask how to test" 모드가 어떤 identifier를 추가해야 하는지 알려주도록 설계했습니다. `tapCoordinate`는 도망갈 구멍이지 해결책이 아닙니다.
- **자동 규칙은 HIG의 일부만 잽니다.** 접근성 트리로 확인 가능한 것(크기, 라벨, 겹침, 개수)만 자동이고, 색 대비 · Dynamic Type · 다크 모드 · 모션 · 문구는 Claude가 스크린샷과 요소 목록을 보고 판단합니다. 자동 결과도 오탐이 있을 수 있으니(예: 행 전체가 탭 영역인 목록 안의 작은 버튼) Claude 리뷰나 사람 확인을 거치세요.
- **tvOS · visionOS 미지원.** Runner에 호스트 타깃과 스킴만 추가하면 되지만 검증하지 않았습니다.
- `claude -p --output-format json`의 출력 형식(`result`, `session_id`)은 Claude Code 버전에 따라 바뀔 수 있습니다. 바뀌면 `ClaudeCLI.CLIOutput`만 고치면 됩니다.

---

## 레이아웃

```
TestBridge/
├── project.yml                 # 앱 + CLI (XcodeGen)
├── Package.swift               # CLI만 SwiftPM으로 빌드
├── bootstrap.sh
├── Sources/
│   ├── TestBridgeCore/         # 앱·CLI·Runner가 공유
│   │   ├── Models/             # TestPlan DSL, RunReport, HIGAudit(규칙 카탈로그) + HIGAuditor(규칙 엔진) ← Runner도 이 폴더만 포함
│   │   ├── Services/           # ShellRunner, simctl, xcodebuild, xcresult
│   │   └── Claude/             # PromptBuilder, ClaudeCLI(파서/전송), HIGReview, PlanInbox, CLAUDE.md 스니펫, DSL 스키마
│   ├── TestBridgeApp/          # SwiftUI macOS 앱 (HIG · Claude Code · Plans · Runs · Devices) + Localizable.xcstrings(en/ko)
│   └── testbridge-cli/         # 터미널 진입점
├── Tests/TestBridgeCoreTests/  # HIG 규칙 엔진 · DSL · 파서 유닛 테스트
├── Runner/
│   ├── project.yml             # Runner-iOS / -macOS / -watchOS 스킴
│   ├── Shared/                 # PlanInterpreter(XCUITest, higAudit 포함), PlanRunnerTests
│   └── Hosts/                  # 플랫폼별 빈 호스트 앱
└── Examples/                   # hig-audit-ios.json 등
```
