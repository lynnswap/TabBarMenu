# AGENTS

## Test Commands
- Run test commands from the `TabBarMenu` repository root.
- Primary local test commands (run both):
  - `xcodebuild test -scheme TabBarMenu-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`
  - `xcodebuild test -scheme TabBarMenu-Package -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`
- If you want a latest-runtime fallback command:
  - `xcodebuild test -scheme TabBarMenu-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`
- If the simulator name does not match your local environment:
  - `xcrun simctl list devices available`
- If you need to confirm available schemes:
  - `xcodebuild -list -json`
- Do not rely on plain `swift test` for validation on macOS hosts. This package depends on `UIKit`, so verification should run against an iOS Simulator.

## Testing Policy
- `TabBarMenu` tests use Swift Testing (`import Testing`, `@Test`, `#expect`).
- When changing behavior, add or update tests for the affected public behavior or bug fix.
- Focus automated coverage on package-level behavior, controller-level behavior, and tab interaction flows.
- This package does not have a dedicated UI test target. Use `Tests/TabBarMenuTests` for automated verification, and use the demo app only for manual checks when needed.
