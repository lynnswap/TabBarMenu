import Testing
import UIKit
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
private final class MoreTabSelectionDelegate: NSObject, TabBarMenuDelegate {
    private(set) var requestedTabs: [[UITab]] = []
    private var selectionHandlers: [String: @MainActor () -> Void] = [:]

    func tabBarController(_ tabBarController: UITabBarController, menuForMoreTabWith tabs: [UITab]) -> UIMenu? {
        requestedTabs.append(tabs)
        selectionHandlers = [:]
        let actions = tabs.map { tab in
            let title = tab.title
            selectionHandlers[title] = { [weak tabBarController] in
                guard let tabBarController else {
                    return
                }
                _ = tabBarController.selectTabContent(tab)
            }
            return UIAction(title: title, image: tab.image) { _ in
                self.selectionHandlers[title]?()
            }
        }
        return UIMenu(children: actions)
    }

    func performSelection(titled title: String) {
        selectionHandlers[title]?()
    }
}

@MainActor
private final class MoreViewControllerSelectionDelegate: NSObject, TabBarMenuDelegate {
    private(set) var requestedViewControllers: [[UIViewController]] = []
    private var selectionHandlers: [String: @MainActor () -> Void] = [:]

    func tabBarController(
        _ tabBarController: UITabBarController,
        menuForMoreTabWith viewControllers: [UIViewController]
    ) -> UIMenu? {
        requestedViewControllers.append(viewControllers)
        selectionHandlers = [:]
        let actions = viewControllers.map { viewController in
            let title = viewController.title ?? viewController.tabBarItem.title ?? "Untitled"
            selectionHandlers[title] = { [weak tabBarController] in
                guard let tabBarController else {
                    return
                }
                _ = tabBarController.selectTabContent(viewController)
            }
            return UIAction(title: title, image: viewController.tabBarItem.image) { _ in
                self.selectionHandlers[title]?()
            }
        }
        return UIMenu(children: actions)
    }

    func performSelection(titled title: String) {
        selectionHandlers[title]?()
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
    private(set) var configuredTabs: [UITab?] = []
    private let menu: UIMenu

    init(menu: UIMenu = UIMenu(children: [])) {
        self.menu = menu
    }

    func tabBarController(_ tabBarController: UITabBarController, menuForMoreTabWith tabs: [UITab]) -> UIMenu? {
        menu
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        configureMenuPresentationFor tab: UITab?,
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
        if let selector = aSelector, selector == UITabBarItemRuntimeMethods.view {
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
private struct ViewControllerTabBarTestContext {
    let controller: UITabBarController
    let host: WindowHost
    let viewControllers: [UIViewController]
}

@MainActor
private final class StandaloneTabBarHost {
    let containerView: UIView
    let tabBar: UITabBar

    init(size: CGSize = CGSize(width: 320, height: 49)) {
        containerView = UIView(frame: CGRect(origin: .zero, size: size))
        tabBar = UITabBar(frame: containerView.bounds)
        tabBar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addSubview(tabBar)
        layoutIfNeeded()
    }

    func layoutIfNeeded() {
        containerView.setNeedsLayout()
        tabBar.setNeedsLayout()
        containerView.layoutIfNeeded()
        tabBar.layoutIfNeeded()
    }
}

@MainActor
private final class TabBarLayoutRecorder {
    private(set) var events: [[Int]] = []

    init(tabBar: UITabBar) {
        tabBar.tabBarMenuLayoutHandler = { [weak self] tabBar in
            self?.events.append(tabBar.items?.map(\.tag) ?? [])
        }
    }
}

@MainActor
private func makeTabs(count: Int) -> [UITab] {
    (0..<count).map { index in
        UITab(
            title: "Tab \(index)",
            image: nil,
            identifier: "tab.\(index)",
            viewControllerProvider: { _ in
                makeContentViewController(
                    title: "Tab \(index)",
                    itemTitle: "Tab \(index)"
                )
            }
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
        makeContentViewController(
            title: "View \(index)",
            itemTitle: "Item \(index)",
            tag: index
        )
    }
}

@MainActor
private func makeViewControllersWithNoViewItems(count: Int) -> [UIViewController] {
    (0..<count).map { index in
        let controller = makeContentViewController(
            title: "View \(index)",
            itemTitle: "Item \(index)",
            tag: index
        )
        controller.tabBarItem = NoViewTabBarItem(title: "Item \(index)", image: nil, tag: index)
        return controller
    }
}

@MainActor
private func makeContentViewController(
    title: String,
    itemTitle: String,
    tag: Int = 0
) -> UIViewController {
    let controller = UIViewController()
    controller.title = title
    controller.view.backgroundColor = .systemBackground
    controller.tabBarItem = UITabBarItem(title: itemTitle, image: nil, tag: tag)

    let label = UILabel()
    label.text = title
    label.accessibilityIdentifier = "content-title-\(title)"
    label.translatesAutoresizingMaskIntoConstraints = false
    controller.view.addSubview(label)
    NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
    ])
    return controller
}

@MainActor
private func makeTabBarTestContext(tabCount: Int) -> TabBarTestContext {
    let tabs = makeTabs(count: tabCount)
    let controller = UITabBarController(tabs: tabs)
    let host = WindowHost(rootViewController: controller)
    return TabBarTestContext(controller: controller, host: host, tabs: tabs)
}

@MainActor
private func makeViewControllerTabBarTestContext(viewControllerCount: Int) -> ViewControllerTabBarTestContext {
    let viewControllers = makeViewControllers(count: viewControllerCount)
    let controller = UITabBarController()
    controller.setViewControllers(viewControllers, animated: false)
    let host = WindowHost(rootViewController: controller)
    return ViewControllerTabBarTestContext(
        controller: controller,
        host: host,
        viewControllers: viewControllers
    )
}

@Test("UITab resolves a More-selection view controller")
@MainActor
func uitabResolvesMoreSelectionViewController() async {
    let tab = UITab(
        title: "Resolved",
        image: nil,
        identifier: "resolved.tab",
        viewControllerProvider: { _ in
            let controller = UIViewController()
            controller.title = "Resolved"
            return controller
        }
    )

    let viewController = tab.resolvedMoreSelectionViewController

    #expect(viewController != nil)
    #expect(viewController?.title == "Resolved")
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
    ObjectiveCInterop.performObjectSelector(UITabBarItemRuntimeMethodNames.view, on: item) as? UIView
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
private func menuRecognizerIdentityCount(in tabBar: UITabBar) -> Int {
    Set(menuLongPressRecognizers(in: tabBar).map(ObjectIdentifier.init)).count
}
@MainActor
private func menuRecognizerIdentitySet(in tabBar: UITabBar) -> Set<ObjectIdentifier> {
    Set(menuLongPressRecognizers(in: tabBar).map(ObjectIdentifier.init))
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

@MainActor
private func tabBarOrderedControls(in tabBar: UITabBar) -> [UIControl] {
    let controls = tabBarFallbackControls(in: tabBar)
    return controls.sorted { left, right in
        let leftFrame = left.convert(left.bounds, to: tabBar)
        let rightFrame = right.convert(right.bounds, to: tabBar)
        return leftFrame.minX < rightFrame.minX
    }
}

@MainActor
private func moreTabBarControl(in tabBarController: UITabBarController) -> UIControl? {
    let maxVisibleCount = tabBarController.menuConfiguration.maxVisibleTabCount
    guard maxVisibleCount > 0 else {
        return nil
    }
    let controls = tabBarOrderedControls(in: tabBarController.tabBar)
    let moreIndex = maxVisibleCount - 1
    guard controls.indices.contains(moreIndex) else {
        return nil
    }
    return controls[moreIndex]
}

@MainActor
private func firstVisibleTabControl(in tabBarController: UITabBarController) -> UIControl? {
    tabBarOrderedControls(in: tabBarController.tabBar).first
}

@MainActor
private func invokeRuntimeMethodNamed(
    _ name: String,
    on object: NSObject,
    argument: AnyObject?
) {
    unsafe _ = object.perform(NSSelectorFromString(name), with: argument)
}

@MainActor
private func displayedViewController(in navigationController: UINavigationController) -> UIViewController? {
    ObjectiveCInterop.performObjectSelector(
        UIMoreNavigationControllerRuntimeMethodNames.displayedViewController,
        on: navigationController
    ) as? UIViewController
}

@MainActor
private func transientViewController(in tabBarController: UITabBarController) -> UIViewController? {
    ObjectiveCInterop.performObjectSelector(
        UITabBarControllerRuntimeMethodNames.transientViewController,
        on: tabBarController
    ) as? UIViewController
}

@MainActor
private func selectedTabElement(in tabBarController: UITabBarController) -> UITab? {
    ObjectiveCInterop.performObjectSelector(
        UITabBarControllerRuntimeMethodNames.selectedTabElement,
        on: tabBarController
    ) as? UITab
}

@MainActor
private func resolvedMoreTab(in tabBarController: UITabBarController) -> UITab? {
    ObjectiveCInterop.performObjectSelector(
        UIMoreNavigationControllerRuntimeMethodNames.resolvedTab,
        on: tabBarController.moreNavigationController
    ) as? UITab
}

@MainActor
private func displayedViewControllers(in tab: UITab) -> [UIViewController] {
    (ObjectiveCInterop.performObjectSelector(
        UITabRuntimeMethodNames.displayedViewControllers,
        on: tab
    ) as? [UIViewController]) ?? []
}

@MainActor
private func moreListController(in navigationController: UINavigationController) -> UIViewController? {
    ObjectiveCInterop.performObjectSelector(
        UIMoreNavigationControllerRuntimeMethodNames.moreListController,
        on: navigationController
    ) as? UIViewController
}

@MainActor
private func setDisplayedViewController(
    _ viewController: UIViewController?,
    in navigationController: UINavigationController
) {
    _ = ObjectiveCInterop.performVoidSelector(
        UIMoreNavigationControllerRuntimeMethodNames.setDisplayedViewController,
        on: navigationController,
        with: viewController
    )
}

@MainActor
private func selectedViewController(in tabBarController: UITabBarController) -> UIViewController? {
    unsafe tabBarController.selectedViewController
}

@MainActor
private func selectedViewControllerInTabBar(in tabBarController: UITabBarController) -> UIViewController? {
    if let viewController = ObjectiveCInterop.performObjectSelector(
        UITabBarControllerRuntimeMethodNames.selectedViewControllerInTabBar,
        on: tabBarController
    ) as? UIViewController {
        return viewController
    }
    return selectedViewController(in: tabBarController)
}

@MainActor
private func navigationStack(of navigationController: UINavigationController) -> [UIViewController] {
    navigationController.viewControllers
}

@MainActor
private func canPopFromNavigationController(_ navigationController: UINavigationController) -> Bool {
    navigationController.viewControllers.count > 1
}

@MainActor
private func selectedTabBarItem(in tabBarController: UITabBarController) -> UITabBarItem? {
    tabBarController.tabBar.selectedItem
}

@MainActor
private func title(of item: UITabBarItem?) -> String? {
    item?.title
}

@MainActor
private func labelTexts(in view: UIView) -> [String] {
    var result: [String] = []
    if let label = view as? UILabel, let text = label.text, !text.isEmpty {
        result.append(text)
    }
    for subview in view.subviews {
        result.append(contentsOf: labelTexts(in: subview))
    }
    return result
}

@MainActor
private func tabBarButtonTitles(in tabBarController: UITabBarController) -> [String] {
    tabBarOrderedControls(in: tabBarController.tabBar).compactMap { control in
        labelTexts(in: control).last
    }
}

@MainActor
private func visibleContentTitles(in tabBarController: UITabBarController) -> [String] {
    contentLabelTexts(in: tabBarController.view, excluding: tabBarController.tabBar)
}

@MainActor
private func containsViewController(
    _ rootViewController: UIViewController,
    descendant targetViewController: UIViewController
) -> Bool {
    if rootViewController === targetViewController {
        return true
    }
    if let navigationController = rootViewController as? UINavigationController {
        return navigationController.viewControllers.contains { viewController in
            containsViewController(viewController, descendant: targetViewController)
        }
    }
    return rootViewController.children.contains { viewController in
        containsViewController(viewController, descendant: targetViewController)
    }
}

@MainActor
private func contentLabelTexts(in view: UIView, excluding excludedRoot: UIView) -> [String] {
    guard view !== excludedRoot else {
        return []
    }

    var result: [String] = []
    if let label = view as? UILabel,
       let identifier = label.accessibilityIdentifier,
       identifier.hasPrefix("content-title-"),
       let text = label.text,
       !text.isEmpty {
        result.append(text)
    }
    for subview in view.subviews {
        result.append(contentsOf: contentLabelTexts(in: subview, excluding: excludedRoot))
    }
    return result
}

@MainActor
private func waitForSelectionPropagation() async {
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(150))
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(250))
}

@MainActor
@discardableResult
private func simulateMoreControlTap(in tabBarController: UITabBarController) -> Bool {
    let tabBar = tabBarController.tabBar
    if let controlHandler = tabBar.tabBarMenuControlSelectionHandler,
       let moreControl = moreTabBarControl(in: tabBarController) {
        tabBar.tabBarMenuControlSelectionDidHandle = false
        let shouldCallDefault = controlHandler(tabBar, moreControl)
        if tabBar.tabBarMenuControlSelectionDidHandle {
            return shouldCallDefault == false
        }
    }

    guard let itemHandler = tabBar.tabBarMenuSelectionHandler,
          let moreItem = moreTabBarItem(in: tabBarController) else {
        return false
    }
    return itemHandler(tabBar, moreItem) == false
}

@MainActor
@discardableResult
private func invokeMoreControlTap(in tabBarController: UITabBarController) -> Bool {
    guard let moreControl = moreTabBarControl(in: tabBarController) else {
        return simulateMoreControlTap(in: tabBarController)
    }

    tabBarController.tabBar.tabBarMenuControlSelectionDidHandle = false
    invokeRuntimeMethodNamed(
        UITabBarRuntimeMethodNames.buttonUp,
        on: tabBarController.tabBar,
        argument: moreControl
    )
    if tabBarController.tabBar.tabBarMenuControlSelectionDidHandle {
        return true
    }
    return simulateMoreControlTap(in: tabBarController)
}

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

@Test("more tab selection configures menu presentation with nil")
@MainActor
func moreTabSelectionConfiguresMenuPresentationWithNil() async {
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

    #expect(delegate.configuredTabs.count == 1)
    if let configuredTab = delegate.configuredTabs.first {
        #expect(configuredTab == nil)
    }
}

@Test("selection override installs an available runtime path")
@MainActor
func selectionOverrideInstallsAvailableRuntimePath() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabMenuDelegate(menu: UIMenu(children: []))

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    #expect(context.controller.tabBar.tabBarMenuInstalledSelectionOverrideKind != .none)
}

@Test("selectTabContent resolves a visible UITab")
@MainActor
func selectTabContentResolvesVisibleTab() async {
    let context = makeTabBarTestContext(tabCount: 6)
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let targetTab = context.tabs[2]
    let targetViewController = targetTab.resolvedMoreSelectionViewController
    #expect(targetViewController != nil)
    let didSelect = context.controller.selectTabContent(targetTab)
    await waitForSelectionPropagation()

    #expect(didSelect == true)
    if let targetViewController {
        #expect(selectedViewControllerInTabBar(in: context.controller) === targetViewController)
    }
    if #available(iOS 26.0, *) {
        #expect(context.controller.selectedTab === targetTab)
    }
}

@Test("selectTabContent stores a delegate-driven overflow override for UITab")
@MainActor
func selectTabContentResolvesOverflowTab() async {
    let context = makeTabBarTestContext(tabCount: 6)
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let targetTab = context.tabs[5]
    let targetViewController = targetTab.resolvedMoreSelectionViewController
    let preservedMoreItem = moreTabBarItem(in: context.controller)
    #expect(targetViewController != nil)
    #expect(preservedMoreItem != nil)

    if let targetViewController {
        let didSelect = context.controller.selectTabContent(targetTab)
        await waitForSelectionPropagation()
        let override = context.controller.tabBarMenuDisplayedViewControllersOverride(
            for: targetTab,
            proposedViewControllers: []
        )

        #expect(didSelect == true)
        #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == true)
        #expect(transientViewController(in: context.controller) == nil)
        #expect(override?.count == 1)
        #expect(override?.contains { containsViewController($0, descendant: targetViewController) } == true)
        #expect(navigationStack(of: context.controller.moreNavigationController).count == 2)
        #expect(navigationStack(of: context.controller.moreNavigationController).first === moreListController(in: context.controller.moreNavigationController))
        #expect(navigationStack(of: context.controller.moreNavigationController).last.map { containsViewController($0, descendant: targetViewController) } == true)
        #expect(displayedViewController(in: context.controller.moreNavigationController) === targetViewController)
        #expect(context.controller.moreNavigationController.interactivePopGestureRecognizer?.isEnabled == false)
        #expect(title(of: selectedTabBarItem(in: context.controller)) == title(of: preservedMoreItem))
        #expect(tabBarButtonTitles(in: context.controller).last == title(of: preservedMoreItem))
    }
}

@Test("selectTabContent resolves a visible view controller")
@MainActor
func selectTabContentResolvesVisibleViewController() async {
    let context = makeViewControllerTabBarTestContext(viewControllerCount: 6)
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let targetViewController = context.viewControllers[2]
    let didSelect = context.controller.selectTabContent(targetViewController)
    await waitForSelectionPropagation()

    #expect(didSelect == true)
    #expect(selectedViewControllerInTabBar(in: context.controller) === targetViewController)
}

@Test("selectTabContent resolves an overflow view controller with transient presentation")
@MainActor
func selectTabContentResolvesOverflowViewController() async {
    let context = makeViewControllerTabBarTestContext(viewControllerCount: 6)
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let targetViewController = context.viewControllers[5]
    let preservedMoreItem = moreTabBarItem(in: context.controller)
    setDisplayedViewController(targetViewController, in: context.controller.moreNavigationController)

    let didSelect = context.controller.selectTabContent(targetViewController)
    await waitForSelectionPropagation()

    #expect(didSelect == true)
    #expect(selectedViewController(in: context.controller) === targetViewController)
    #expect(selectedViewControllerInTabBar(in: context.controller) === targetViewController)
    #expect(transientViewController(in: context.controller) === targetViewController)
    #expect(targetViewController.navigationController !== context.controller.moreNavigationController)
    #expect(targetViewController.parent === context.controller)
    #expect(navigationStack(of: context.controller.moreNavigationController).count == 1)
    #expect(navigationStack(of: context.controller.moreNavigationController).first === moreListController(in: context.controller.moreNavigationController))
    #expect(canPopFromNavigationController(context.controller.moreNavigationController) == false)
    #expect(displayedViewController(in: context.controller.moreNavigationController) === context.controller.moreNavigationController)
    #expect(title(of: selectedTabBarItem(in: context.controller)) == title(of: preservedMoreItem))
    #expect(tabBarButtonTitles(in: context.controller).last == title(of: preservedMoreItem))
}

@Test("selectTabContent rejects detached targets")
@MainActor
func selectTabContentRejectsDetachedTargets() async {
    let tabContext = makeTabBarTestContext(tabCount: 6)
    tabContext.controller.view.setNeedsLayout()
    tabContext.host.window.layoutIfNeeded()

    let initialTabSelection = selectedViewControllerInTabBar(in: tabContext.controller)
    let detachedTabDidSelect = tabContext.controller.selectTabContent(
        UITab(title: "Detached", image: nil, identifier: "detached") { _ in UIViewController() }
    )
    await waitForSelectionPropagation()

    #expect(detachedTabDidSelect == false)
    #expect(selectedViewControllerInTabBar(in: tabContext.controller) === initialTabSelection)
    #expect(transientViewController(in: tabContext.controller) == nil)

    let firstViewControllerContext = makeViewControllerTabBarTestContext(viewControllerCount: 6)
    let secondViewControllerContext = makeViewControllerTabBarTestContext(viewControllerCount: 6)
    firstViewControllerContext.controller.view.setNeedsLayout()
    firstViewControllerContext.host.window.layoutIfNeeded()

    let initialViewControllerSelection = selectedViewControllerInTabBar(in: firstViewControllerContext.controller)
    let detachedViewControllerDidSelect = firstViewControllerContext.controller.selectTabContent(
        secondViewControllerContext.viewControllers[5]
    )
    await waitForSelectionPropagation()

    #expect(detachedViewControllerDidSelect == false)
    #expect(selectedViewControllerInTabBar(in: firstViewControllerContext.controller) === initialViewControllerSelection)
    #expect(transientViewController(in: firstViewControllerContext.controller) == nil)
}

@Test("More menu action stores a delegate-driven overflow override for UITab")
@MainActor
func moreMenuActionKeepsMoreSelectedForOverflowTab() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabSelectionDelegate()

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let targetTab = context.tabs[5]
    let targetViewController = targetTab.resolvedMoreSelectionViewController
    let preservedMoreItem = moreTabBarItem(in: context.controller)
    let handler = context.controller.tabBar.tabBarMenuSelectionHandler

    #expect(targetViewController != nil)
    #expect(preservedMoreItem != nil)
    #expect(handler != nil)

    if let targetViewController, let preservedMoreItem, let handler {
        let shouldCallDefault = handler(context.controller.tabBar, preservedMoreItem)
        #expect(shouldCallDefault == false)
        delegate.performSelection(titled: targetTab.title)
        await waitForSelectionPropagation()
        let override = context.controller.tabBarMenuDisplayedViewControllersOverride(
            for: targetTab,
            proposedViewControllers: []
        )

        #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == true)
        #expect(transientViewController(in: context.controller) == nil)
        #expect(override?.count == 1)
        #expect(override?.contains { containsViewController($0, descendant: targetViewController) } == true)
        #expect(navigationStack(of: context.controller.moreNavigationController).count == 2)
        #expect(navigationStack(of: context.controller.moreNavigationController).first === moreListController(in: context.controller.moreNavigationController))
        #expect(navigationStack(of: context.controller.moreNavigationController).last.map { containsViewController($0, descendant: targetViewController) } == true)
        #expect(displayedViewController(in: context.controller.moreNavigationController) === targetViewController)
        #expect(context.controller.moreNavigationController.interactivePopGestureRecognizer?.isEnabled == false)
        #expect(title(of: selectedTabBarItem(in: context.controller)) == title(of: preservedMoreItem))
        #expect(tabBarButtonTitles(in: context.controller).last == title(of: preservedMoreItem))
    }
}

@Test("More menu action presents an overflow view controller transiently")
@MainActor
func moreMenuActionKeepsMoreSelectedForOverflowViewController() async {
    let context = makeViewControllerTabBarTestContext(viewControllerCount: 6)
    let delegate = MoreViewControllerSelectionDelegate()

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let targetViewController = context.viewControllers[5]
    let preservedMoreItem = moreTabBarItem(in: context.controller)
    let handler = context.controller.tabBar.tabBarMenuSelectionHandler

    #expect(preservedMoreItem != nil)
    #expect(handler != nil)

    if let preservedMoreItem, let handler {
        let shouldCallDefault = handler(context.controller.tabBar, preservedMoreItem)
        #expect(shouldCallDefault == false)
        delegate.performSelection(titled: targetViewController.title ?? targetViewController.tabBarItem.title ?? "Untitled")
        await waitForSelectionPropagation()

        #expect(selectedViewController(in: context.controller) === targetViewController)
        #expect(selectedViewControllerInTabBar(in: context.controller) === targetViewController)
        #expect(transientViewController(in: context.controller) === targetViewController)
        #expect(targetViewController.navigationController !== context.controller.moreNavigationController)
        #expect(targetViewController.parent === context.controller)
        #expect(navigationStack(of: context.controller.moreNavigationController).count == 1)
        #expect(navigationStack(of: context.controller.moreNavigationController).first === moreListController(in: context.controller.moreNavigationController))
        #expect(canPopFromNavigationController(context.controller.moreNavigationController) == false)
        #expect(displayedViewController(in: context.controller.moreNavigationController) === context.controller.moreNavigationController)
        #expect(title(of: selectedTabBarItem(in: context.controller)) == title(of: preservedMoreItem))
        #expect(tabBarButtonTitles(in: context.controller).last == title(of: preservedMoreItem))
    }
}

@Test("More menu request deduplicates overflow view controllers while transient content is active")
@MainActor
func moreMenuRequestDeduplicatesOverflowViewControllers() async {
    let context = makeViewControllerTabBarTestContext(viewControllerCount: 6)
    let delegate = MoreViewControllerSelectionDelegate()

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let preservedMoreItem = moreTabBarItem(in: context.controller)
    let handler = context.controller.tabBar.tabBarMenuSelectionHandler

    #expect(preservedMoreItem != nil)
    #expect(handler != nil)

    if let preservedMoreItem, let handler {
        let firstShouldCallDefault = handler(context.controller.tabBar, preservedMoreItem)
        #expect(firstShouldCallDefault == false)
        #expect(delegate.requestedViewControllers.last?.map(ObjectIdentifier.init) == [
            ObjectIdentifier(context.viewControllers[4]),
            ObjectIdentifier(context.viewControllers[5]),
        ])

        let targetTitle = context.viewControllers[5].title ?? context.viewControllers[5].tabBarItem.title ?? "Untitled"
        delegate.performSelection(titled: targetTitle)
        await waitForSelectionPropagation()

        let secondShouldCallDefault = handler(context.controller.tabBar, preservedMoreItem)
        #expect(secondShouldCallDefault == false)

        let latestOverflowItems = delegate.requestedViewControllers.last ?? []
        #expect(latestOverflowItems.map(ObjectIdentifier.init) == [
            ObjectIdentifier(context.viewControllers[4]),
            ObjectIdentifier(context.viewControllers[5]),
        ])
    }
}

@Test("visible UITab selection dismisses transient overflow content")
@MainActor
func visibleTabSelectionDismissesTransientOverflowContent() async {
    let context = makeTabBarTestContext(tabCount: 6)
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let overflowTab = context.tabs[5]
    let overflowViewController = overflowTab.resolvedMoreSelectionViewController
    let visibleTab = context.tabs[1]
    let visibleViewController = visibleTab.resolvedMoreSelectionViewController

    #expect(overflowViewController != nil)
    #expect(visibleViewController != nil)

    if let overflowViewController, let visibleViewController {
        _ = context.controller.selectTabContent(overflowTab)
        await waitForSelectionPropagation()
        let overrideBeforeDismiss = context.controller.tabBarMenuDisplayedViewControllersOverride(
            for: overflowTab,
            proposedViewControllers: []
        )

        #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == true)
        #expect(transientViewController(in: context.controller) == nil)
        #expect(overrideBeforeDismiss?.contains { containsViewController($0, descendant: overflowViewController) } == true)

        _ = context.controller.selectTabContent(visibleTab)
        await waitForSelectionPropagation()

        #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == false)
        #expect(transientViewController(in: context.controller) == nil)
        #expect(context.controller.tabBarMenuDisplayedViewControllersOverride(
            for: overflowTab,
            proposedViewControllers: []
        ) == nil)
        #expect(selectedViewControllerInTabBar(in: context.controller) === visibleViewController)
        #expect(navigationStack(of: context.controller.moreNavigationController).count == 1)
        #expect(navigationStack(of: context.controller.moreNavigationController).first === moreListController(in: context.controller.moreNavigationController))
        #expect(displayedViewController(in: context.controller.moreNavigationController) !== overflowViewController)
    }
}

@Test("reselecting the same More UITab keeps overflow content active")
@MainActor
func reselectingSameMoreTabKeepsOverflowContentActive() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabSelectionDelegate()

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let targetTab = context.tabs[5]
    let targetViewController = targetTab.resolvedMoreSelectionViewController
    let originalMoreItem = moreTabBarItem(in: context.controller)

    #expect(targetViewController != nil)
    #expect(originalMoreItem != nil)

    if let targetViewController, let originalMoreItem {
        let requestedCountBeforeFirstTap = delegate.requestedTabs.count
        #expect(invokeMoreControlTap(in: context.controller) == true)
        #expect(delegate.requestedTabs.count == requestedCountBeforeFirstTap + 1)
        delegate.performSelection(titled: targetTab.title)
        await waitForSelectionPropagation()
        context.host.window.layoutIfNeeded()

        let requestedCountBeforeSecondTap = delegate.requestedTabs.count
        #expect(invokeMoreControlTap(in: context.controller) == true)
        #expect(delegate.requestedTabs.count == requestedCountBeforeSecondTap + 1)
        delegate.performSelection(titled: targetTab.title)
        await waitForSelectionPropagation()
        context.host.window.layoutIfNeeded()

        #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == true)
        #expect(navigationStack(of: context.controller.moreNavigationController).count == 2)
        #expect(navigationStack(of: context.controller.moreNavigationController).first === moreListController(in: context.controller.moreNavigationController))
        #expect(navigationStack(of: context.controller.moreNavigationController).last.map { containsViewController($0, descendant: targetViewController) } == true)
        #expect(displayedViewController(in: context.controller.moreNavigationController) === targetViewController)
        #expect(context.controller.moreNavigationController.interactivePopGestureRecognizer?.isEnabled == false)
        #expect(visibleContentTitles(in: context.controller) == [targetViewController.title].compactMap { $0 })
        #expect(title(of: selectedTabBarItem(in: context.controller)) == title(of: originalMoreItem))
        #expect(tabBarButtonTitles(in: context.controller).last == title(of: originalMoreItem))
        #expect(context.controller.tabBarMenuDisplayedViewControllersOverride(
            for: targetTab,
            proposedViewControllers: []
        )?.contains { containsViewController($0, descendant: targetViewController) } == true)
    }
}

@Test("reselecting a different More UITab replaces overflow content without restoring the list")
@MainActor
func reselectingDifferentMoreTabKeepsOverflowContentActive() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabSelectionDelegate()

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let firstTab = context.tabs[4]
    let secondTab = context.tabs[5]
    let firstViewController = firstTab.resolvedMoreSelectionViewController
    let secondViewController = secondTab.resolvedMoreSelectionViewController
    let originalMoreItem = moreTabBarItem(in: context.controller)

    #expect(firstViewController != nil)
    #expect(secondViewController != nil)
    #expect(originalMoreItem != nil)

    if let firstViewController, let secondViewController, let originalMoreItem {
        let requestedCountBeforeFirstTap = delegate.requestedTabs.count
        #expect(invokeMoreControlTap(in: context.controller) == true)
        #expect(delegate.requestedTabs.count == requestedCountBeforeFirstTap + 1)
        delegate.performSelection(titled: firstTab.title)
        await waitForSelectionPropagation()
        context.host.window.layoutIfNeeded()

        let requestedCountBeforeSecondTap = delegate.requestedTabs.count
        #expect(invokeMoreControlTap(in: context.controller) == true)
        #expect(delegate.requestedTabs.count == requestedCountBeforeSecondTap + 1)
        delegate.performSelection(titled: secondTab.title)
        await waitForSelectionPropagation()
        context.host.window.layoutIfNeeded()

        #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == true)
        #expect(navigationStack(of: context.controller.moreNavigationController).count == 2)
        #expect(navigationStack(of: context.controller.moreNavigationController).first === moreListController(in: context.controller.moreNavigationController))
        #expect(navigationStack(of: context.controller.moreNavigationController).last.map { containsViewController($0, descendant: secondViewController) } == true)
        #expect(navigationStack(of: context.controller.moreNavigationController).last.map { containsViewController($0, descendant: firstViewController) } == false)
        #expect(displayedViewController(in: context.controller.moreNavigationController) === secondViewController)
        #expect(context.controller.moreNavigationController.interactivePopGestureRecognizer?.isEnabled == false)
        #expect(visibleContentTitles(in: context.controller) == [secondViewController.title].compactMap { $0 })
        #expect(title(of: selectedTabBarItem(in: context.controller)) == title(of: originalMoreItem))
        #expect(tabBarButtonTitles(in: context.controller).last == title(of: originalMoreItem))
        #expect(context.controller.tabBarMenuDisplayedViewControllersOverride(
            for: secondTab,
            proposedViewControllers: []
        )?.contains { containsViewController($0, descendant: secondViewController) } == true)
    }
}

@Test("visible UITab tap keeps overflow state alive until UIKit completes selection")
@MainActor
func visibleTabTapDefersOverflowCleanupUntilSelectionCompletes() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabSelectionDelegate()

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let overflowTab = context.tabs[5]
    let moreItem = moreTabBarItem(in: context.controller)
    let visibleItem = context.controller.tabBar.items?[1]
    let handler = context.controller.tabBar.tabBarMenuSelectionHandler

    #expect(moreItem != nil)
    #expect(visibleItem != nil)
    #expect(handler != nil)

    if let moreItem, let visibleItem, let handler {
        let shouldSuppressMoreDefault = handler(context.controller.tabBar, moreItem)
        #expect(shouldSuppressMoreDefault == false)
        delegate.performSelection(titled: overflowTab.title)
        await waitForSelectionPropagation()

        #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == true)

        let shouldCallDefaultForVisibleItem = handler(context.controller.tabBar, visibleItem)
        #expect(shouldCallDefaultForVisibleItem == true)
        #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == true)
    }
}

@Test("active UITab overflow still suppresses More default on control tap")
@MainActor
func activeUITabOverflowSuppressesMoreDefaultOnControlTap() async {
    let context = makeTabBarTestContext(tabCount: 7)
    let delegate = MoreTabSelectionDelegate()

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let overflowTab = context.tabs[5]
    let moreItem = moreTabBarItem(in: context.controller)
    let itemHandler = context.controller.tabBar.tabBarMenuSelectionHandler
    let controlHandler = context.controller.tabBar.tabBarMenuControlSelectionHandler
    let moreControl = moreTabBarControl(in: context.controller)

    #expect(moreItem != nil)
    #expect(itemHandler != nil)
    #expect(controlHandler != nil)
    #expect(moreControl != nil)

    if let moreItem, let itemHandler, let controlHandler, let moreControl {
        #expect(itemHandler(context.controller.tabBar, moreItem) == false)
        delegate.performSelection(titled: overflowTab.title)
        await waitForSelectionPropagation()

        let shouldCallDefault = controlHandler(context.controller.tabBar, moreControl)
        #expect(shouldCallDefault == false)
        #expect(context.controller.tabBar.tabBarMenuControlSelectionDidHandle == true)
    }
}

@Test("visible view controller selection dismisses transient overflow content")
@MainActor
func visibleViewControllerSelectionDismissesTransientOverflowContent() async {
    let context = makeViewControllerTabBarTestContext(viewControllerCount: 6)
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let overflowViewController = context.viewControllers[5]
    let visibleViewController = context.viewControllers[1]

    _ = context.controller.selectTabContent(overflowViewController)
    await waitForSelectionPropagation()
    #expect(transientViewController(in: context.controller) === overflowViewController)

    _ = context.controller.selectTabContent(visibleViewController)
    await waitForSelectionPropagation()

    #expect(transientViewController(in: context.controller) == nil)
    #expect(selectedViewControllerInTabBar(in: context.controller) === visibleViewController)
    #expect(navigationStack(of: context.controller.moreNavigationController).count == 1)
    #expect(navigationStack(of: context.controller.moreNavigationController).first === moreListController(in: context.controller.moreNavigationController))
    #expect(displayedViewController(in: context.controller.moreNavigationController) === context.controller.moreNavigationController)
}

@Test("dual runtime hooks do not duplicate More delegate requests")
@MainActor
func dualRuntimeHooksDoNotDuplicateMoreDelegateRequests() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabMenuDelegate(menu: nil)

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let installedKind = context.controller.tabBar.tabBarMenuInstalledSelectionOverrideKind
    guard installedKind == .didSelectButtonForItemAndButtonUp else {
        #expect(installedKind != .none)
        return
    }

    let moreControl = moreTabBarControl(in: context.controller)
    #expect(moreControl != nil)
    if let moreControl {
        invokeRuntimeMethodNamed(UITabBarRuntimeMethodNames.buttonUp, on: context.controller.tabBar, argument: moreControl)
    }

    #expect(delegate.requestedTabsCount == 1)
}

@Test("forced buttonUp fallback suppresses More default when menu is provided")
@MainActor
func forcedButtonUpFallbackSuppressesMoreDefaultWhenMenuIsProvided() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabMenuDelegate(menu: UIMenu(children: []))
    context.controller.tabBar.tabBarMenuPreferredSelectionOverrideKind = .buttonUp

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    #expect(context.controller.tabBar.tabBarMenuInstalledSelectionOverrideKind == .buttonUp)
    let handler = context.controller.tabBar.tabBarMenuControlSelectionHandler
    #expect(handler != nil)
    let moreControl = moreTabBarControl(in: context.controller)
    #expect(moreControl != nil)
    if let handler, let moreControl {
        let shouldCallDefault = handler(context.controller.tabBar, moreControl)
        #expect(shouldCallDefault == false)
    }
    #expect(delegate.requestedTabsCount == 1)
}

@Test("combined preferred hook kind installs both runtime paths")
@MainActor
func combinedPreferredHookKindInstallsBothRuntimePaths() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabMenuDelegate(menu: UIMenu(children: []))
    context.controller.tabBar.tabBarMenuPreferredSelectionOverrideKind = .didSelectButtonForItemAndButtonUp

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let installedKind = context.controller.tabBar.tabBarMenuInstalledSelectionOverrideKind
    #expect(installedKind == .didSelectButtonForItemAndButtonUp || installedKind == .buttonUp)
    #expect(context.controller.tabBar.tabBarMenuSelectionHandler != nil)
    #expect(context.controller.tabBar.tabBarMenuControlSelectionHandler != nil)
}

@Test("forced buttonUp fallback allows More default when menu is absent")
@MainActor
func forcedButtonUpFallbackAllowsMoreDefaultWhenMenuIsAbsent() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabMenuDelegate(menu: nil)
    context.controller.tabBar.tabBarMenuPreferredSelectionOverrideKind = .buttonUp

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    #expect(context.controller.tabBar.tabBarMenuInstalledSelectionOverrideKind == .buttonUp)
    let handler = context.controller.tabBar.tabBarMenuControlSelectionHandler
    #expect(handler != nil)
    let moreControl = moreTabBarControl(in: context.controller)
    #expect(moreControl != nil)
    if let handler, let moreControl {
        let shouldCallDefault = handler(context.controller.tabBar, moreControl)
        #expect(shouldCallDefault == true)
    }
    #expect(delegate.requestedTabsCount == 1)
}

@Test("forced buttonUp fallback does not intercept non-more tab taps")
@MainActor
func forcedButtonUpFallbackDoesNotInterceptNonMoreTabTaps() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabMenuDelegate(menu: UIMenu(children: []))
    context.controller.tabBar.tabBarMenuPreferredSelectionOverrideKind = .buttonUp

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    #expect(context.controller.tabBar.tabBarMenuInstalledSelectionOverrideKind == .buttonUp)
    let handler = context.controller.tabBar.tabBarMenuControlSelectionHandler
    #expect(handler != nil)
    let firstControl = firstVisibleTabControl(in: context.controller)
    #expect(firstControl != nil)
    if let handler, let firstControl {
        let shouldCallDefault = handler(context.controller.tabBar, firstControl)
        #expect(shouldCallDefault == true)
    }
    #expect(delegate.requestedTabsCount == 0)
}

@Test("unhandled buttonUp path preserves item-based More fallback")
@MainActor
func unhandledButtonUpPathPreservesItemBasedMoreFallback() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabMenuDelegate(menu: UIMenu(children: []))

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let controlHandler = context.controller.tabBar.tabBarMenuControlSelectionHandler
    let itemHandler = context.controller.tabBar.tabBarMenuSelectionHandler
    #expect(controlHandler != nil)
    #expect(itemHandler != nil)

    let firstControl = firstVisibleTabControl(in: context.controller)
    let moreItem = moreTabBarItem(in: context.controller)
    #expect(firstControl != nil)
    #expect(moreItem != nil)

    if let controlHandler, let itemHandler, let firstControl, let moreItem {
        let shouldCallDefaultForControl = controlHandler(context.controller.tabBar, firstControl)
        #expect(shouldCallDefaultForControl == true)

        let shouldCallDefault = itemHandler(context.controller.tabBar, moreItem)
        #expect(shouldCallDefault == false)
    }

    #expect(delegate.requestedTabsCount == 1)
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
