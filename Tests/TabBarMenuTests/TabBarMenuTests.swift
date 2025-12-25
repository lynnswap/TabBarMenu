import Testing
import UIKit
import Combine
@testable import TabBarMenu

@MainActor
private final class TestMenuDelegate: TabBarMenuDelegate {
    private(set) var requestedIdentifiers: [String] = []
    private let menu: UIMenu

    init(menu: UIMenu = UIMenu(children: [])) {
        self.menu = menu
    }

    func tabBarController(_ tabBarController: UITabBarController, tab: UITab) -> UIMenu? {
        requestedIdentifiers.append(tab.identifier)
        return menu
    }
}

@MainActor
private final class SelfDelegatingTabBarController: UITabBarController, TabBarMenuDelegate {
    func tabBarController(_ tabBarController: UITabBarController, tab: UITab) -> UIMenu? {
        UIMenu(children: [])
    }
}

@MainActor
private final class TabBarItemsChangeRecorder {
    private(set) var events: [[UITabBarItem]] = []
    private var cancellable: AnyCancellable?

    init(tabBar: UITabBar) {
        cancellable = tabBar.itemsDidChangePublisher
            .sink { [weak self] items in
                self?.events.append(items)
            }
    }
}

@MainActor
private final class WindowHost {
    let window: UIWindow

    init(rootViewController: UIViewController) {
        window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        rootViewController.loadViewIfNeeded()
        window.layoutIfNeeded()
    }
}

@MainActor
private struct TabBarTestContext {
    let controller: UITabBarController
    let host: WindowHost
    let tabs: [UITab]
}

@MainActor
private func makeTabs(count: Int) -> [UITab] {
    (0..<count).map { index in
        UITab(
            title: "Tab \(index)",
            image: nil,
            identifier: "tab.\(index)",
            viewControllerProvider: { _ in UIViewController() }
        )
    }
}

@MainActor
private func makeTabBarItems(count: Int) -> [UITabBarItem] {
    (0..<count).map { index in
        UITabBarItem(title: "Item \(index)", image: nil, tag: index)
    }
}

@MainActor
private func makeTabBarTestContext(tabCount: Int) -> TabBarTestContext {
    let tabs = makeTabs(count: tabCount)
    let controller = UITabBarController(tabs: tabs)
    let host = WindowHost(rootViewController: controller)
    return TabBarTestContext(controller: controller, host: host, tabs: tabs)
}
@MainActor
private func tabBarControls(in view: UIView) -> [UIControl] {
    var result: [UIControl] = []
    for subview in view.subviews {
        if let control = subview as? UIControl {
            result.append(control)
        }
        result.append(contentsOf: tabBarControls(in: subview))
    }
    return result
}
@MainActor
private func tabBarItemView(_ item: UITabBarItem) -> UIView? {
    let selector = NSSelectorFromString("view")
    guard item.responds(to: selector) else {
        return nil
    }
    return item.perform(selector)?.takeUnretainedValue() as? UIView
}
@MainActor
private func tabBarButtonViews(in tabBar: UITabBar) -> [UIView] {
    guard let items = tabBar.items, !items.isEmpty else {
        return []
    }
    return items.compactMap { tabBarItemView($0) }
}
@MainActor
private func menuLongPressRecognizers(in tabBar: UITabBar) -> [TabBarMenuLongPressGestureRecognizer] {
    let controls = tabBarControls(in: tabBar)
    return controls.flatMap { control in
        (control.gestureRecognizers ?? []).compactMap { recognizer in
            recognizer as? TabBarMenuLongPressGestureRecognizer
        }
    }
}
@MainActor
private func menuRecognizerIndices(in tabBar: UITabBar) -> Set<Int> {
    Set(menuLongPressRecognizers(in: tabBar).map(\.tabIndex))
}
@MainActor
private func menuMinimumPressDurations(in tabBar: UITabBar) -> [TimeInterval] {
    menuLongPressRecognizers(in: tabBar).map(\.minimumPressDuration)
}

@Test("itemsDidChangePublisher emits when items are assigned")
@MainActor
func itemsDidChangePublisherEmitsOnAssignment() async {
    let tabBar = UITabBar()
    let recorder = TabBarItemsChangeRecorder(tabBar: tabBar)
    let updatedItems = makeTabBarItems(count: 3)
    let baseCount = recorder.events.count

    tabBar.items = updatedItems
    await Task.yield()

    #expect(recorder.events.count == baseCount + 1)
    #expect(recorder.events.last?.map(\.tag) == updatedItems.map(\.tag))
}

@Test("itemsDidChangePublisher emits when setItems is called")
@MainActor
func itemsDidChangePublisherEmitsOnSetItems() async {
    let tabBar = UITabBar()
    let recorder = TabBarItemsChangeRecorder(tabBar: tabBar)
    let updatedItems = makeTabBarItems(count: 1)
    let baseCount = recorder.events.count

    tabBar.setItems(updatedItems, animated: false)
    await Task.yield()

    #expect(recorder.events.count == baseCount + 1)
    #expect(recorder.events.last?.map(\.tag) == updatedItems.map(\.tag))
}

@Test("itemsDidChangePublisher emits for in-place mutations")
@MainActor
func itemsDidChangePublisherEmitsForInPlaceMutations() async {
    let tabBar = UITabBar()
    let recorder = TabBarItemsChangeRecorder(tabBar: tabBar)
    tabBar.items = makeTabBarItems(count: 2)
    var expectedCount = recorder.events.count

    tabBar.items?.append(UITabBarItem(title: "Append", image: nil, tag: 99))
    expectedCount += 1
    await Task.yield()
    #expect(recorder.events.count == expectedCount)

    if var items = tabBar.items, !items.isEmpty {
        items[0] = UITabBarItem(title: "Replace", image: nil, tag: 100)
        tabBar.items = items
        expectedCount += 1
        await Task.yield()
        #expect(recorder.events.count == expectedCount)
    }

    tabBar.items?.insert(UITabBarItem(title: "Insert", image: nil, tag: 101), at: 1)
    expectedCount += 1
    await Task.yield()
    #expect(recorder.events.count == expectedCount)

    _ = tabBar.items?.removeLast()
    expectedCount += 1
    await Task.yield()
    #expect(recorder.events.count == expectedCount)
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
