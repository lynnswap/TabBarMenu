import Testing
import UIKit
import Combine
@testable import TabBarMenu

@MainActor
private final class TestMenuDelegate: NSObject, TabBarMenuDelegate {
    private(set) var requestedIdentifiers: [String?] = []
    private let menu: UIMenu

    init(menu: UIMenu = UIMenu(children: [])) {
        self.menu = menu
    }

    func tabBarController(_ tabBarController: UITabBarController, tab: UITab?) -> UIMenu? {
        requestedIdentifiers.append(tab?.identifier)
        return menu
    }
}

@MainActor
private final class MoreTabMenuDelegate: NSObject, TabBarMenuDelegate {
    private(set) var requestedTabsCount = 0
    private let menu: UIMenu?

    init(menu: UIMenu?) {
        self.menu = menu
    }

    func tabBarController(_ tabBarController: UITabBarController, menuForMoreTabWith tabs: [UITab]) -> UIMenu? {
        requestedTabsCount += 1
        return menu
    }
}

@MainActor
private final class DualMoreTabMenuDelegate: NSObject, TabBarMenuDelegate {
    private(set) var requestedTabsCount = 0
    private(set) var requestedViewControllersCount = 0
    private let tabsMenu: UIMenu?
    private let viewControllersMenu: UIMenu?

    init(tabsMenu: UIMenu?, viewControllersMenu: UIMenu?) {
        self.tabsMenu = tabsMenu
        self.viewControllersMenu = viewControllersMenu
    }

    func tabBarController(_ tabBarController: UITabBarController, menuForMoreTabWith tabs: [UITab]) -> UIMenu? {
        requestedTabsCount += 1
        return tabsMenu
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        menuForMoreTabWith viewControllers: [UIViewController]
    ) -> UIMenu? {
        requestedViewControllersCount += 1
        return viewControllersMenu
    }
}

@MainActor
private final class MoreTabPresentationDelegate: NSObject, TabBarMenuDelegate {
    private(set) var configuredTabs: [UITab] = []
    private let menu: UIMenu

    init(menu: UIMenu = UIMenu(children: [])) {
        self.menu = menu
    }

    func tabBarController(_ tabBarController: UITabBarController, menuForMoreTabWith tabs: [UITab]) -> UIMenu? {
        menu
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        configureMenuPresentationFor tab: UITab,
        tabFrame: CGRect,
        in containerView: UIView,
        menuHostButton: UIButton
    ) -> TabBarMenuAnchorPlacement? {
        configuredTabs.append(tab)
        return nil
    }
}

@MainActor
private final class ViewControllerMenuDelegate: NSObject, TabBarMenuDelegate {
    private(set) var requestedTitles: [String?] = []
    private let menu: UIMenu

    init(menu: UIMenu = UIMenu(children: [])) {
        self.menu = menu
    }

    func tabBarController(_ tabBarController: UITabBarController, viewController: UIViewController?) -> UIMenu? {
        requestedTitles.append(viewController?.title)
        return menu
    }
}

@MainActor
private final class NoViewTabBarItem: UITabBarItem {
    override func responds(to aSelector: Selector!) -> Bool {
        if let selector = aSelector, selector == NSSelectorFromString("view") {
            return false
        }
        return super.responds(to: aSelector)
    }
}

@MainActor
private final class SelfDelegatingTabBarController: UITabBarController, TabBarMenuDelegate {
    func tabBarController(_ tabBarController: UITabBarController, tab: UITab?) -> UIMenu? {
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
private func makeViewControllers(count: Int) -> [UIViewController] {
    (0..<count).map { index in
        let controller = UIViewController()
        controller.title = "View \(index)"
        controller.tabBarItem = UITabBarItem(title: "Item \(index)", image: nil, tag: index)
        return controller
    }
}

@MainActor
private func makeViewControllersWithNoViewItems(count: Int) -> [UIViewController] {
    (0..<count).map { index in
        let controller = UIViewController()
        controller.title = "View \(index)"
        controller.tabBarItem = NoViewTabBarItem(title: "Item \(index)", image: nil, tag: index)
        return controller
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
    let itemViews = items.compactMap { tabBarItemView($0) }
    if itemViews.count == items.count {
        return itemViews
    }
    let controls = tabBarFallbackControls(in: tabBar)
    guard !controls.isEmpty else {
        return itemViews
    }
    let sortedControls = controls.sorted { left, right in
        let leftFrame = left.convert(left.bounds, to: tabBar)
        let rightFrame = right.convert(right.bounds, to: tabBar)
        return leftFrame.minX < rightFrame.minX
    }
    let count = min(sortedControls.count, items.count)
    return Array(sortedControls.prefix(count))
}

@MainActor
private func tabBarFallbackControls(in tabBar: UITabBar) -> [UIControl] {
    let controls = tabBarControls(in: tabBar)
    let topLevelControls = controls.filter { $0.superview === tabBar }
    if !topLevelControls.isEmpty {
        return topLevelControls
    }
    return controls
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
@MainActor
private func menuLongPressDurationsByIndex(in tabBar: UITabBar) -> [Int: TimeInterval] {
    Dictionary(uniqueKeysWithValues: menuLongPressRecognizers(in: tabBar).map { ($0.tabIndex, $0.minimumPressDuration) })
}
@MainActor
private func menuRecognizerMinXAndIndices(in tabBar: UITabBar) -> [(minX: CGFloat, index: Int)] {
    let controls = tabBarControls(in: tabBar)
    return controls.compactMap { control in
        guard let recognizer = (control.gestureRecognizers ?? []).compactMap({ $0 as? TabBarMenuLongPressGestureRecognizer }).first else {
            return nil
        }
        let frame = control.convert(control.bounds, to: tabBar)
        return (frame.minX, recognizer.tabIndex)
    }
}
@MainActor
private func moreTabBarItem(in tabBarController: UITabBarController) -> UITabBarItem? {
    let maxVisibleCount = tabBarController.menuConfiguration.maxVisibleTabCount
    guard maxVisibleCount > 0 else {
        return nil
    }
    let moreIndex = maxVisibleCount - 1
    guard let items = tabBarController.tabBar.items, items.indices.contains(moreIndex) else {
        return nil
    }
    return items[moreIndex]
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

@Test("more tab selection allows default when menu is absent")
@MainActor
func moreTabSelectionAllowsDefaultWhenMenuIsAbsent() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabMenuDelegate(menu: nil)

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let handler = context.controller.tabBar.tabBarMenuSelectionHandler
    #expect(handler != nil)
    let moreItem = moreTabBarItem(in: context.controller)
    #expect(moreItem != nil)
    if let handler, let moreItem {
        let shouldCallDefault = handler(context.controller.tabBar, moreItem)
        #expect(shouldCallDefault == true)
    }
    #expect(delegate.requestedTabsCount == 1)
}

@Test("more tab selection prefers tabs method when implemented")
@MainActor
func moreTabSelectionPrefersTabsMethodWhenImplemented() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = DualMoreTabMenuDelegate(
        tabsMenu: nil,
        viewControllersMenu: UIMenu(children: [])
    )

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let handler = context.controller.tabBar.tabBarMenuSelectionHandler
    #expect(handler != nil)
    let moreItem = moreTabBarItem(in: context.controller)
    #expect(moreItem != nil)
    if let handler, let moreItem {
        let shouldCallDefault = handler(context.controller.tabBar, moreItem)
        #expect(shouldCallDefault == true)
    }
    #expect(delegate.requestedTabsCount == 1)
    #expect(delegate.requestedViewControllersCount == 0)
}

@Test("more tab selection suppresses default when menu is provided")
@MainActor
func moreTabSelectionSuppressesDefaultWhenMenuIsProvided() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabMenuDelegate(menu: UIMenu(children: []))

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let handler = context.controller.tabBar.tabBarMenuSelectionHandler
    #expect(handler != nil)
    let moreItem = moreTabBarItem(in: context.controller)
    #expect(moreItem != nil)
    if let handler, let moreItem {
        let shouldCallDefault = handler(context.controller.tabBar, moreItem)
        #expect(shouldCallDefault == false)
    }
    #expect(delegate.requestedTabsCount == 1)
}

@Test("more tab selection configures menu presentation")
@MainActor
func moreTabSelectionConfiguresMenuPresentation() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabPresentationDelegate(menu: UIMenu(children: []))

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let handler = context.controller.tabBar.tabBarMenuSelectionHandler
    #expect(handler != nil)
    let moreItem = moreTabBarItem(in: context.controller)
    #expect(moreItem != nil)
    if let handler, let moreItem {
        _ = handler(context.controller.tabBar, moreItem)
    }

    let expectedIndex = context.controller.menuConfiguration.maxVisibleTabCount - 1
    #expect(delegate.configuredTabs.count == 1)
    #expect(delegate.configuredTabs.first === context.tabs[expectedIndex])
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
