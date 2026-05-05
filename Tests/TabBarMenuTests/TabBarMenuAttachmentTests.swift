import Testing
import UIKit
@testable import TabBarMenu

@Test("layout handler runs when items are assigned and laid out")
@MainActor
func layoutHandlerRunsOnItemsAssignment() {
    let host = StandaloneTabBarHost()
    let recorder = TabBarLayoutRecorder(tabBar: host.tabBar)
    let updatedItems = makeTabBarItems(count: 3)
    let baseCount = recorder.events.count

    host.tabBar.items = updatedItems
    host.layoutIfNeeded()

    #expect(recorder.events.count == baseCount + 1)
    #expect(recorder.events.last == updatedItems.map(\.tag))
}

@Test("layout handler runs when setItems is called and laid out")
@MainActor
func layoutHandlerRunsOnSetItems() {
    let host = StandaloneTabBarHost()
    let recorder = TabBarLayoutRecorder(tabBar: host.tabBar)
    let updatedItems = makeTabBarItems(count: 1)
    let baseCount = recorder.events.count

    host.tabBar.setItems(updatedItems, animated: false)
    host.layoutIfNeeded()

    #expect(recorder.events.count == baseCount + 1)
    #expect(recorder.events.last == updatedItems.map(\.tag))
}

@Test("layout handler runs for in-place item mutations after layout")
@MainActor
func layoutHandlerRunsForInPlaceItemMutations() {
    let host = StandaloneTabBarHost()
    let recorder = TabBarLayoutRecorder(tabBar: host.tabBar)
    host.tabBar.items = makeTabBarItems(count: 2)
    host.layoutIfNeeded()
    var expectedCount = recorder.events.count

    host.tabBar.items?.append(UITabBarItem(title: "Append", image: nil, tag: 99))
    host.layoutIfNeeded()
    expectedCount += 1
    #expect(recorder.events.count == expectedCount)
    #expect(recorder.events.last == [0, 1, 99])

    if var items = host.tabBar.items, !items.isEmpty {
        items[0] = UITabBarItem(title: "Replace", image: nil, tag: 100)
        host.tabBar.items = items
        host.layoutIfNeeded()
        expectedCount += 1
        #expect(recorder.events.count == expectedCount)
        #expect(recorder.events.last == [100, 1, 99])
    }

    host.tabBar.items?.insert(UITabBarItem(title: "Insert", image: nil, tag: 101), at: 1)
    host.layoutIfNeeded()
    expectedCount += 1
    #expect(recorder.events.count == expectedCount)
    #expect(recorder.events.last == [100, 101, 1, 99])

    _ = host.tabBar.items?.removeLast()
    host.layoutIfNeeded()
    expectedCount += 1
    #expect(recorder.events.count == expectedCount)
    #expect(recorder.events.last == [100, 101, 1])
}

@Test("menuDelegate attaches long-press gestures")
@MainActor
func menuDelegateAttachesLongPressGestures() async {
    let context = makeTabBarTestContext(tabCount: 3)
    let delegate = TestMenuDelegate()

    context.controller.menuDelegate = delegate

    #expect(context.controller.menuDelegate === delegate)
    let indices = menuRecognizerIndices(in: context.controller.tabBar)
    let buttonViews = tabBarButtonViews(in: context.controller.tabBar)
    let expectedCount = min(context.tabs.count, buttonViews.count)
    let expectedIndices = Set(0..<expectedCount)

    #expect(indices.count == expectedCount)
    #expect(indices == expectedIndices)
    #expect(context.host.window.rootViewController === context.controller)
}

@Test("menuDelegate attaches long-press gestures for viewControllers")
@MainActor
func menuDelegateAttachesLongPressGesturesForViewControllers() async {
    let controller = UITabBarController()
    let viewControllers = makeViewControllers(count: 3)
    controller.setViewControllers(viewControllers, animated: false)
    let host = WindowHost(rootViewController: controller)
    let delegate = ViewControllerMenuDelegate()

    controller.menuDelegate = delegate

    #expect(controller.menuDelegate === delegate)
    let indices = menuRecognizerIndices(in: controller.tabBar)
    let buttonViews = tabBarButtonViews(in: controller.tabBar)
    let expectedCount = min(viewControllers.count, buttonViews.count)
    let expectedIndices = Set(0..<expectedCount)

    #expect(indices.count == expectedCount)
    #expect(indices == expectedIndices)
    #expect(host.window.rootViewController === controller)
}

@Test("RTL fallback ordering maps indices to right-to-left controls")
@MainActor
func rtlFallbackOrderingMapsIndicesToRightToLeftControls() async {
    let controller = UITabBarController()
    let viewControllers = makeViewControllersWithNoViewItems(count: 3)
    controller.setViewControllers(viewControllers, animated: false)
    controller.tabBar.semanticContentAttribute = .forceRightToLeft
    let host = WindowHost(rootViewController: controller)
    let delegate = ViewControllerMenuDelegate()

    controller.menuDelegate = delegate
    controller.view.setNeedsLayout()
    host.window.layoutIfNeeded()

    #expect(controller.tabBar.effectiveUserInterfaceLayoutDirection == .rightToLeft)
    let itemViews = controller.tabBar.items?.compactMap { tabBarItemView($0) } ?? []
    #expect(itemViews.isEmpty)

    let entries = menuRecognizerMinXAndIndices(in: controller.tabBar)
    #expect(entries.count == viewControllers.count)
    let sortedEntries = entries.sorted { $0.minX > $1.minX }
    #expect(sortedEntries.map(\.index) == Array(0..<entries.count))
}

@Test("LTR fallback ordering maps indices to left-to-right controls")
@MainActor
func ltrFallbackOrderingMapsIndicesToLeftToRightControls() async {
    let controller = UITabBarController()
    let viewControllers = makeViewControllersWithNoViewItems(count: 3)
    controller.setViewControllers(viewControllers, animated: false)
    controller.tabBar.semanticContentAttribute = .forceLeftToRight
    let host = WindowHost(rootViewController: controller)
    let delegate = ViewControllerMenuDelegate()

    controller.menuDelegate = delegate
    controller.view.setNeedsLayout()
    host.window.layoutIfNeeded()

    #expect(controller.tabBar.effectiveUserInterfaceLayoutDirection == .leftToRight)
    let itemViews = controller.tabBar.items?.compactMap { tabBarItemView($0) } ?? []
    #expect(itemViews.isEmpty)

    let entries = menuRecognizerMinXAndIndices(in: controller.tabBar)
    #expect(entries.count == viewControllers.count)
    let sortedEntries = entries.sorted { $0.minX < $1.minX }
    #expect(sortedEntries.map(\.index) == Array(0..<entries.count))
}

@Test("menuDelegate supports self assignment")
@MainActor
func menuDelegateSupportsSelfAssignment() async {
    let controller = SelfDelegatingTabBarController()
    controller.tabs = makeTabs(count: 2)
    let host = WindowHost(rootViewController: controller)

    controller.menuDelegate = controller

    #expect(controller.menuDelegate === controller)
    let indices = menuRecognizerIndices(in: controller.tabBar)
    let buttonViews = tabBarButtonViews(in: controller.tabBar)
    let expectedCount = min(controller.tabs.count, buttonViews.count)
    let expectedIndices = Set(0..<expectedCount)

    #expect(indices == expectedIndices)
    #expect(host.window.rootViewController === controller)
}

@Test("menuDelegate refreshes long-press gestures when tabs change")
@MainActor
func menuDelegateRefreshesLongPressGesturesWhenTabsChange() async {
    let context = makeTabBarTestContext(tabCount: 2)
    let delegate = TestMenuDelegate()

    context.controller.menuDelegate = delegate

    let initialIndices = menuRecognizerIndices(in: context.controller.tabBar)

    let updatedTabs = (0..<3).map { index in
        UITab(
            title: "Updated \(index)",
            image: nil,
            identifier: "updated.\(index)",
            viewControllerProvider: { _ in UIViewController() }
        )
    }

    context.controller.tabs = updatedTabs
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()
    await Task.yield()

    let updatedIndices = menuRecognizerIndices(in: context.controller.tabBar)
    let buttonViews = tabBarButtonViews(in: context.controller.tabBar)
    let expectedCount = min(updatedTabs.count, buttonViews.count)
    let expectedIndices = Set(0..<expectedCount)

    #expect(updatedIndices == expectedIndices)
    if expectedCount > 0 {
        #expect(updatedIndices != initialIndices)
    }
}

@Test("menuDelegate refreshes long-press gestures when viewControllers change")
@MainActor
func menuDelegateRefreshesLongPressGesturesWhenViewControllersChange() async {
    let controller = UITabBarController()
    controller.setViewControllers(makeViewControllers(count: 2), animated: false)
    let host = WindowHost(rootViewController: controller)
    let delegate = ViewControllerMenuDelegate()

    controller.menuDelegate = delegate
    let initialIndices = menuRecognizerIndices(in: controller.tabBar)

    controller.setViewControllers(makeViewControllers(count: 4), animated: false)
    controller.view.setNeedsLayout()
    host.window.layoutIfNeeded()
    await Task.yield()

    let updatedIndices = menuRecognizerIndices(in: controller.tabBar)
    let buttonViews = tabBarButtonViews(in: controller.tabBar)
    let expectedCount = min(4, buttonViews.count)
    let expectedIndices = Set(0..<expectedCount)

    #expect(updatedIndices == expectedIndices)
    if expectedCount > 0 {
        #expect(updatedIndices != initialIndices)
    }
}

@Test("menuDelegate clears long-press gestures when unset")
@MainActor
func menuDelegateClearsLongPressGesturesWhenUnset() async {
    let context = makeTabBarTestContext(tabCount: 2)
    let delegate = TestMenuDelegate()

    context.controller.menuDelegate = delegate
    let buttonViews = tabBarButtonViews(in: context.controller.tabBar)
    let expectedCount = min(context.tabs.count, buttonViews.count)
    #expect(menuRecognizerIndices(in: context.controller.tabBar).count == expectedCount)

    context.controller.menuDelegate = nil
    #expect(menuRecognizerIndices(in: context.controller.tabBar).isEmpty)
}

@Test("menuDelegate does not duplicate long-press gestures")
@MainActor
func menuDelegateDoesNotDuplicateLongPressGestures() async {
    let context = makeTabBarTestContext(tabCount: 2)
    let delegate = TestMenuDelegate()

    context.controller.menuDelegate = delegate
    let initialIndices = menuRecognizerIndices(in: context.controller.tabBar)

    context.controller.menuDelegate = delegate
    let updatedIndices = menuRecognizerIndices(in: context.controller.tabBar)

    #expect(updatedIndices == initialIndices)
}

@Test("repeated layout passes do not duplicate long-press gestures")
@MainActor
func repeatedLayoutPassesDoNotDuplicateLongPressGestures() async {
    let context = makeTabBarTestContext(tabCount: 3)
    let delegate = TestMenuDelegate()

    context.controller.menuDelegate = delegate
    let initialRecognizers = menuLongPressRecognizers(in: context.controller.tabBar)
    let initialIdentityCount = menuRecognizerIdentityCount(in: context.controller.tabBar)
    let initialIdentitySet = menuRecognizerIdentitySet(in: context.controller.tabBar)

    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()
    await Task.yield()

    let updatedRecognizers = menuLongPressRecognizers(in: context.controller.tabBar)
    let updatedIdentityCount = menuRecognizerIdentityCount(in: context.controller.tabBar)
    let updatedIdentitySet = menuRecognizerIdentitySet(in: context.controller.tabBar)

    #expect(updatedRecognizers.count == initialRecognizers.count)
    #expect(initialIdentityCount == initialRecognizers.count)
    #expect(updatedIdentityCount == updatedRecognizers.count)
    #expect(updatedIdentitySet == initialIdentitySet)
}

@Test("coordinator resolves current tab index from the source view")
@MainActor
func coordinatorResolvesCurrentTabIndexFromSourceView() async {
    let context = makeTabBarTestContext(tabCount: 3)
    let coordinator = TabBarMenuCoordinator()
    let delegate = TestMenuDelegate()
    coordinator.delegate = delegate
    coordinator.attach(to: context.controller)

    guard let recognizer = menuLongPressRecognizers(in: context.controller.tabBar).first,
          let sourceView = recognizer.view else {
        Issue.record("Expected a long-press recognizer attached to a tab view")
        return
    }

    recognizer.tabIndex = 999
    let resolvedIndex = coordinator.resolvedTabIndex(
        for: recognizer,
        sourceView: sourceView,
        in: context.controller
    )

    #expect(resolvedIndex == 0)
    #expect(recognizer.tabIndex == 0)
}

@Test("menuConfiguration applies minimumPressDuration")
@MainActor
func menuConfigurationAppliesMinimumPressDuration() async {
    let context = makeTabBarTestContext(tabCount: 2)
    let delegate = TestMenuDelegate()

    context.controller.menuConfiguration = TabBarMenuConfiguration(minimumPressDuration: 0.5)
    context.controller.menuDelegate = delegate

    let buttonViews = tabBarButtonViews(in: context.controller.tabBar)
    let expectedCount = min(context.tabs.count, buttonViews.count)
    let durations = menuMinimumPressDurations(in: context.controller.tabBar)

    #expect(durations.count == expectedCount)
    if expectedCount > 0 {
        #expect(durations.allSatisfy { abs($0 - 0.5) < 0.001 })
    }
}

@Test("menuConfiguration updates minimumPressDuration")
@MainActor
func menuConfigurationUpdatesMinimumPressDuration() async {
    let context = makeTabBarTestContext(tabCount: 2)
    let delegate = TestMenuDelegate()

    context.controller.menuDelegate = delegate
    let buttonViews = tabBarButtonViews(in: context.controller.tabBar)
    let expectedCount = min(context.tabs.count, buttonViews.count)
    let initialDurations = menuMinimumPressDurations(in: context.controller.tabBar)

    context.controller.updateMenuConfiguration { configuration in
        configuration.minimumPressDuration = 0.6
    }

    let updatedDurations = menuMinimumPressDurations(in: context.controller.tabBar)

    #expect(initialDurations.count == expectedCount)
    #expect(updatedDurations.count == expectedCount)
    if expectedCount > 0 {
        #expect(updatedDurations.allSatisfy { abs($0 - 0.6) < 0.001 })
    }
}

@Test("coordinator reattaches to a different tab bar controller")
@MainActor
func coordinatorReattachesToDifferentTabBarController() async {
    let firstContext = makeTabBarTestContext(tabCount: 2)
    let secondContext = makeTabBarTestContext(tabCount: 2)
    let delegate = TestMenuDelegate()
    let coordinator = TabBarMenuCoordinator()

    coordinator.delegate = delegate
    coordinator.attach(to: firstContext.controller)

    let firstButtonViews = tabBarButtonViews(in: firstContext.controller.tabBar)
    let firstExpectedCount = min(firstContext.tabs.count, firstButtonViews.count)
    #expect(menuRecognizerIndices(in: firstContext.controller.tabBar).count == firstExpectedCount)

    coordinator.attach(to: secondContext.controller)

    #expect(menuRecognizerIndices(in: firstContext.controller.tabBar).isEmpty)
    let secondButtonViews = tabBarButtonViews(in: secondContext.controller.tabBar)
    let secondExpectedCount = min(secondContext.tabs.count, secondButtonViews.count)
    #expect(menuRecognizerIndices(in: secondContext.controller.tabBar).count == secondExpectedCount)
}

@Test("gesture count matches the available button views")
@MainActor
func gestureCountMatchesAvailableButtonViews() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = TestMenuDelegate()

    context.controller.menuDelegate = delegate

    let buttonViews = tabBarButtonViews(in: context.controller.tabBar)
    let expectedCount = min(context.tabs.count, buttonViews.count)
    let indices = menuRecognizerIndices(in: context.controller.tabBar)

    #expect(indices.count == expectedCount)
}
