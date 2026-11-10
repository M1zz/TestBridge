import Foundation

/// Text the developer pastes into their project's CLAUDE.md so Claude Code knows how to drive TestBridge
/// directly from the terminal — no GUI round-trip needed.
public enum ClaudeMDSnippet {
    public static func render(bundleIdentifier: String?, platform: Platform?) -> String {
        let bid = bundleIdentifier?.isEmpty == false ? bundleIdentifier! : "<bundle-id>"
        let plat = platform?.rawValue ?? "ios"
        return """
        ## HIG compliance checks with TestBridge

        This project's UI is checked against Apple's Human Interface Guidelines (\(HIGRules.baseURL))
        with **TestBridge**, a declarative XCUITest runner for iOS/iPadOS/watchOS/macOS. You (Claude Code) drive it from
        the shell with the `testbridge` CLI. Plans are JSON files; the format and the HIG rule catalog are printed by `testbridge schema`.

        ### Workflow
        1. `testbridge doctor` — verify Xcode, the Runner project and simulators are ready.
        2. `testbridge devices --json` — pick a destination UDID for platform `\(plat)`.
        3. `testbridge hig --bundle-id \(bid) --platform \(plat) [--destination <udid>] --json`
           → launches the app and audits the first screen: automatic HIG findings (rule id, severity, element, HIG URL) plus every element with its frame.
           Read the findings, decide which are real, and check the element list against the HIG yourself (wording, hierarchy, control choice).
        4. To audit deeper screens, write a plan (e.g. `UITests/hig/settings.json`) that navigates there and runs `higAudit` per screen
           (`testbridge snapshot` shows which identifiers exist to tap). Set `"stopOnFailure": false`.
        5. `testbridge run UITests/hig/settings.json --json` → report with `higAudits[]`. Non-zero exit = a `failOn` threshold was hit.
           Fix the app (not the thresholds), then re-run.
        6. `testbridge import <plan.json>` — hand a plan to the TestBridge GUI if the developer wants to inspect it.

        ### Conventions
        - Add `accessibilityIdentifier`s to interactive views using the `<screen>.<element>` scheme (e.g. `login.email`).
          If a plan needs an element with no identifier, add one in the app code instead of using `tapCoordinate`.
        - Put plans under `UITests/hig/` and keep the file name equal to the plan `name`, kebab-cased.
        - When reporting, cite the HIG page for each issue and separate "violates the HIG" from "could be nicer".
        - Pass `"launchArguments": ["-uiTesting"]` and have the app seed deterministic state when it sees that flag.
        - Do not loop more than 3 run/fix cycles without reporting back to the developer.
        """
    }
}
