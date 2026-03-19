import XCTest

final class TabBarDemoUITests: XCTestCase {
    private var app: XCUIApplication!
    private enum Timing {
        static let ui: TimeInterval = 3
        static let short: TimeInterval = 2
        static let menuPress: TimeInterval = 0.8
    }

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }
    @MainActor
    func testMenuSearchAndMoreFlow() {
        launchApp()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: Timing.ui))

        let homeTab = tabBar.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: Timing.ui))

        homeTab.press(forDuration: Timing.menuPress)

        let rename = waitForMenuItem(named: "Rename", timeout: Timing.short)
        let homeDelete = waitForMenuItem(named: "Delete", timeout: Timing.short)
        XCTAssertTrue(rename.exists)
        XCTAssertTrue(homeDelete.exists)
        rename.tap()

        let initialButtonCount = tabBar.buttons.count
        setSearchTabEnabled(true)
        XCTAssertTrue(waitForTabBarButtonCount(atLeast: initialButtonCount + 1, in: tabBar, timeout: Timing.ui))

        addTabs(count: 3)

        let buttons = tabBar.buttons
        XCTAssertGreaterThanOrEqual(buttons.count, 5)

        let moreButton = buttons.element(boundBy: buttons.count - 1)
        XCTAssertTrue(moreButton.exists)
        moreButton.tap()

        let tappedOverflowItem = waitForMenuItem(named: "Extra 2", timeout: Timing.short)
        XCTAssertTrue(tappedOverflowItem.exists)
        tappedOverflowItem.tap()

        XCTAssertTrue(tabBar.waitForExistence(timeout: Timing.ui))
        assertContentTitle("Extra 2")
        assertVisibleTitleCount("Extra 2", expected: 1)
        assertLastTabBarButtonTitle("More", in: tabBar)
        performLeadingEdgeBackSwipe()
        assertContentTitle("Extra 2")
        assertVisibleTitleCount("Extra 2", expected: 1)
        assertLastTabBarButtonTitle("More", in: tabBar)
        let refreshedMoreButton = lastTabBarButton(in: tabBar)
        XCTAssertTrue(refreshedMoreButton.exists)
        refreshedMoreButton.tap()

        let overflowItem = waitForMenuItem(named: "Extra 1", timeout: Timing.short)
        XCTAssertTrue(overflowItem.exists)
        overflowItem.tap()

        XCTAssertTrue(tabBar.waitForExistence(timeout: Timing.ui))
        let visibleTab = tabBar.buttons["Profile"]
        XCTAssertTrue(visibleTab.waitForExistence(timeout: Timing.ui))

        visibleTab.press(forDuration: Timing.menuPress)
        let deleteAction = waitForMenuItem(named: "Delete", timeout: Timing.short)
        XCTAssertTrue(deleteAction.exists)
        deleteAction.tap()

        XCTAssertTrue(waitForElementToDisappear(visibleTab, timeout: Timing.ui))
    }

    @MainActor
    func testMoreFlowInViewControllerMode() {
        launchApp()
        ensureViewControllerMode()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: Timing.ui))

        addTabs(count: 3)

        let buttons = tabBar.buttons
        XCTAssertGreaterThanOrEqual(buttons.count, 5)

        let moreButton = buttons.element(boundBy: buttons.count - 1)
        XCTAssertTrue(moreButton.exists)
        moreButton.tap()

        let overflowItem = waitForMenuItem(named: "Extra 2", timeout: Timing.short)
        XCTAssertTrue(overflowItem.exists)
        overflowItem.tap()

        XCTAssertTrue(tabBar.waitForExistence(timeout: Timing.ui))
        assertContentTitle("Extra 2")
        assertVisibleTitleCount("Extra 2", expected: 1)
        assertLastTabBarButtonTitle("More", in: tabBar)
        performLeadingEdgeBackSwipe()
        assertContentTitle("Extra 2")
        assertVisibleTitleCount("Extra 2", expected: 1)
        assertLastTabBarButtonTitle("More", in: tabBar)
        let refreshedMoreButton = lastTabBarButton(in: tabBar)
        XCTAssertTrue(refreshedMoreButton.exists)
        refreshedMoreButton.tap()
        XCTAssertTrue(waitForMenuItem(named: "Extra 3", timeout: Timing.short).exists)
    }

    @MainActor
    private func launchApp() {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        ensureUITabMode()
    }

    @MainActor
    private func ensureUITabMode() {
        let segmentedControl = app.segmentedControls.firstMatch
        XCTAssertTrue(segmentedControl.waitForExistence(timeout: Timing.ui))
        let uiTabButton = segmentedControl.buttons["UITab"]
        XCTAssertTrue(uiTabButton.exists)
        if !uiTabButton.isSelected {
            uiTabButton.tap()
        }
    }

    @MainActor
    private func ensureViewControllerMode() {
        let segmentedControl = app.segmentedControls.firstMatch
        XCTAssertTrue(segmentedControl.waitForExistence(timeout: Timing.ui))
        let viewControllerButton = segmentedControl.buttons["VC"]
        XCTAssertTrue(viewControllerButton.exists)
        if !viewControllerButton.isSelected {
            viewControllerButton.tap()
        }
    }

    @MainActor
    private func addTabs(count: Int) {
        let addButton = addTabButton()
        XCTAssertTrue(addButton.waitForExistence(timeout: Timing.ui))
        for _ in 0..<count {
            addButton.tap()
        }
    }
    @MainActor
    private func addTabButton() -> XCUIElement {
        let navBarButton = app.navigationBars.buttons["Add"].firstMatch
        if navBarButton.exists {
            return navBarButton
        }
        return app.buttons["Add"].firstMatch
    }

    @MainActor
    private func lastTabBarButton(in tabBar: XCUIElement) -> XCUIElement {
        tabBar.buttons.element(boundBy: tabBar.buttons.count - 1)
    }

    @MainActor
    private func assertLastTabBarButtonTitle(_ title: String, in tabBar: XCUIElement) {
        let button = lastTabBarButton(in: tabBar)
        XCTAssertTrue(button.waitForExistence(timeout: Timing.ui))
        XCTAssertEqual(button.label, title)
    }

    @MainActor
    private func performLeadingEdgeBackSwipe() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: Timing.ui))
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func isSwitchOn(_ element: XCUIElement) -> Bool {
        guard let value = element.value as? String else {
            return false
        }
        return value == "1" || value.lowercased() == "on"
    }

    @MainActor
    private func setSearchTabEnabled(_ isEnabled: Bool) {
        let searchToggle = app.switches["Search Tab"]
        XCTAssertTrue(searchToggle.waitForExistence(timeout: Timing.ui))
        if isSwitchOn(searchToggle) != isEnabled {
            searchToggle.tap()
        }
    }

    @MainActor
    private func assertContentTitle(_ title: String) {
        let label = app.staticTexts["sample-tab-title"].firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: Timing.ui))
        XCTAssertEqual(label.label, title)
    }

    @MainActor
    private func assertVisibleTitleCount(_ title: String, expected: Int) {
        let predicate = NSPredicate(format: "label == %@", title)
        let query = app.staticTexts.matching(predicate)
        XCTAssertEqual(query.count, expected)
    }

    @MainActor
    @discardableResult
    private func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
    @MainActor
    @discardableResult
    private func waitForMenuItem(named title: String, timeout: TimeInterval) -> XCUIElement {
        let menuItem = app.menuItems[title]
        let button = app.buttons[title]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if menuItem.exists {
                return menuItem
            }
            if button.exists {
                return button
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return menuItem.exists ? menuItem : button
    }

    @MainActor
    @discardableResult
    private func waitForTabBarButtonCount(atLeast count: Int, in tabBar: XCUIElement, timeout: TimeInterval) -> Bool {
        let query = tabBar.buttons
        let predicate = NSPredicate(format: "count >= %d", count)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: query)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
