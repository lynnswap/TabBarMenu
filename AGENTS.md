# AGENTS

## Test Commands
- Run test commands from the `TabBarMenu` repository root.
- Required local validation should mirror CI: run package tests on the latest available iOS 18.x runtime and the latest available iOS 26.x runtime.
- CI resolves the latest available runtime for each major version dynamically:
  - iOS 18.x on `macos-15` with `iPhone 16`
  - iOS 26.x on `macos-26` with `iPhone 17`
- Local example commands, after replacing `OS=<version>` with your latest available major runtime:
  - `xcodebuild test -scheme TabBarMenu-Package -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.x' -enableCodeCoverage NO -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`
  - `xcodebuild test -scheme TabBarMenu-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.x' -enableCodeCoverage NO -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`
- If the simulator name or OS version does not match your local environment:
  - `xcrun simctl list devices available`
- If you need to confirm Xcode destinations for the package scheme:
  - `xcodebuild -showdestinations -scheme TabBarMenu-Package`
- If you need to confirm available schemes:
  - `xcodebuild -list -json`
- Do not rely on plain `swift test` for validation on macOS hosts. This package depends on `UIKit`, so verification should run against an iOS Simulator.

## Testing Policy
- `TabBarMenu` tests use Swift Testing (`import Testing`, `@Test`, `#expect`).
- When changing behavior, add or update tests for the affected public behavior or bug fix.
- Focus automated coverage on package-level behavior, controller-level behavior, and tab interaction flows.
- This package does not have a dedicated UI test target. Use `Tests/TabBarMenuTests` for automated verification, and use the demo app only for manual checks when needed.
- Demo app UI tests are not part of the required self-check for package changes unless the user explicitly asks for demo UI validation.
