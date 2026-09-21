# AGENTS

## Test Commands
- Run test commands from the `TabBarMenu` repository root.
- Required local validation: run package tests on the latest available runtime of each supported major version: iOS 18.x, 26.x, and 27.x.
- CI discovers every installed, available iOS 18.x, 26.x (26.1 or later), and 27.x runtime and creates a test job for each runtime identifier. iOS 26.0.x is excluded from CI. New minor and patch runtimes within this range are included automatically when added to the runner image.
- CI uses the latest stable Xcode 26 on `macos-15` and `macos-26`, and the latest Xcode 27 (including prereleases) on `xcode-27`.
- Each CI test job creates an iPhone supported by its runtime and deletes that Simulator afterward.
- Local example commands, after replacing `OS=<version>` with your latest available major runtime:
  - `xcodebuild test -scheme TabBarMenu-Package -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.x' -enableCodeCoverage NO -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`
  - `xcodebuild test -scheme TabBarMenu-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.x' -enableCodeCoverage NO -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`
  - `xcodebuild test -scheme TabBarMenu-Package -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.x' -enableCodeCoverage NO -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`
- If the simulator name or OS version does not match your local environment:
  - `xcrun simctl list devices available`
- If you need to confirm Xcode destinations for the package scheme:
  - `xcodebuild -showdestinations -scheme TabBarMenu-Package`
- If you need to confirm available schemes:
  - `xcodebuild -list -json`
- Do not rely on plain `swift test` for validation on macOS hosts. This package depends on `UIKit`, so verification should run against an iOS Simulator.

## CI Script Validation
- Run `python3 -m unittest discover -s .github/scripts/tests -p 'test_*.py'`, `ruby -c .github/scripts/resolve-xcode.rb`, `actionlint`, and `git diff --check` when changing CI scripts or workflows.
- Runtime discovery and Simulator creation are implemented in `.github/scripts/ios-runtime-matrix.py`. It uses runtime identifiers from `simctl`, rather than reconstructing them from version numbers.

## Testing Policy
- `TabBarMenu` tests use Swift Testing (`import Testing`, `@Test`, `#expect`).
- When changing behavior, add or update tests for the affected public behavior or bug fix.
- Focus automated coverage on package-level behavior, controller-level behavior, and tab interaction flows.
- This package does not have a dedicated UI test target. Use `Tests/TabBarMenuTests` for automated verification, and use the demo app only for manual checks when needed.
- Demo app UI tests are not part of the required self-check for package changes unless the user explicitly asks for demo UI validation.
