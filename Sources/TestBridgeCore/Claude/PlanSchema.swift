import Foundation

/// Human/LLM-readable reference for the plan DSL. This text is embedded in every prompt
/// sent to Claude Code, so keep it in sync with `Step`.
public enum PlanSchema {
    public static let version = "1"

    public static let reference: String = """
    # TestBridge plan format (v\(version))

    A plan is one JSON object:

    ```json
    {
      "name": "Login happy path",
      "platform": "ios",                      // "ios" | "ipados" | "watchos" | "macos"
      "bundleIdentifier": "com.example.MyApp",
      "destination": { "udid": "<simulator UDID>" },   // optional; omit for macOS host or to use the selected device
      "launchArguments": ["-uiTesting"],      // optional
      "launchEnvironment": { "MOCK_API": "1" }, // optional
      "stopOnFailure": true,                  // optional, default true
      "steps": [ ... ]
    }
    ```

    ## Targeting elements
    Every step that touches an element takes a `"target"` object. Use the most specific matcher available:
    - `"id"` — accessibilityIdentifier (most reliable; ask the developer to add them if missing)
    - `"label"` — exact accessibility label (what VoiceOver reads; usually the visible text)
    - `"labelContains"` — case-insensitive substring of the label
    - `"text"` — matches label OR value OR title OR placeholder exactly (good for text fields by placeholder)
    - `"type"` — narrows by element type: any, button, textField, secureTextField, staticText, textView, searchField,
      cell, table, collectionView, scrollView, switch, slider, stepper, segmentedControl, picker, pickerWheel, datePicker,
      image, link, webView, map, navigationBar, tabBar, toolbar, menuItem, menuBarItem, popUpButton, checkBox, radioButton,
      window, sheet, alert, dialog, popover, other
    - `"index"` — pick the N-th match (0-based) when several elements match

    ## Steps (`"action"` field)
    | action | fields | notes |
    |---|---|---|
    | launch | — | implicit at start if omitted |
    | terminate / activate | — | |
    | tap | target | click on macOS |
    | doubleTap | target | |
    | longPress | target, seconds (1.0) | |
    | typeText | target, text, clearFirst (false) | taps the field first. Unreliable on watchOS |
    | swipe | target (optional, defaults to whole app), direction: up/down/left/right | scroll on macOS |
    | scrollTo | target, direction (up), maxSwipes (10) | swipes until target is hittable |
    | tapCoordinate | x, y (normalized 0–1 of the app window) | last resort |
    | wait | seconds | |
    | assertExists | target, timeout (5) | |
    | assertNotExists | target, timeout (5) | |
    | assertText | target, equals OR contains | checks value, falling back to label |
    | assertEnabled | target, enabled (true) | |
    | pressKey | key, modifiers [cmd, shift, option, control] | macOS only. key: a letter or return/escape/tab/space/delete/up/down/left/right |
    | rotate | orientation: portrait/landscapeLeft/landscapeRight/portraitUpsideDown | iOS/iPadOS only |
    | screenshot | name | saved as <name>.png |
    | dumpTree | name (optional) | saves the accessibility hierarchy; use it to discover identifiers |
    | higAudit | name, failOn: error (default) / warning / info / none | snapshots every element on screen and checks it against the HIG rule catalog; one per screen, distinct names |

    ## Rules of thumb
    - A HIG check plan = navigate to a screen → `wait` 1s → `screenshot` → `higAudit` with that screen's name, repeated per screen. Set `"stopOnFailure": false` so every screen is audited even if one fails.
    - Functional plans finish with at least one assert*. A plan without assertions or audits proves nothing.
    - Prefer `id`, then `label`, then `text`. Never use `tapCoordinate` when an element matcher works.
    - If you don't know identifiers, emit a short discovery plan first: launch → wait → dumpTree, then write the real plan from the tree.
    - Keep plans small (one user journey each). Several small plans beat one giant plan.
    - On macOS, modal dialogs are `type: "dialog"` or `"sheet"`; menu items are `type: "menuItem"` with `label`.
    """

    /// A compact example Claude can copy.
    public static let example: String = """
    {
      "name": "HIG audit: onboarding and settings",
      "platform": "ios",
      "bundleIdentifier": "com.example.MyApp",
      "launchArguments": ["-uiTesting"],
      "stopOnFailure": false,
      "steps": [
        { "action": "wait", "seconds": 1 },
        { "action": "screenshot", "name": "home" },
        { "action": "higAudit", "name": "home", "failOn": "error" },
        { "action": "tap", "target": { "type": "button", "label": "Settings" } },
        { "action": "assertExists", "target": { "type": "navigationBar", "label": "Settings" } },
        { "action": "screenshot", "name": "settings" },
        { "action": "higAudit", "name": "settings", "failOn": "error" }
      ]
    }
    """
}
