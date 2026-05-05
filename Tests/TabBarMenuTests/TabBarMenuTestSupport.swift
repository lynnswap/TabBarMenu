import Testing
import UIKit
@testable import TabBarMenu

@MainActor
final class TestMenuDelegate: NSObject, TabBarMenuDelegate {
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
final class MoreTabMenuDelegate: NSObject, TabBarMenuDelegate {
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
final class MoreTabSelectionDelegate: NSObject, TabBarMenuDelegate {
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
final class MoreViewControllerSelectionDelegate: NSObject, TabBarMenuDelegate {
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
final class DualMoreTabMenuDelegate: NSObject, TabBarMenuDelegate {
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
final class DualItemMenuDelegate: NSObject, TabBarMenuDelegate {
    private(set) var requestedTabIdentifiers: [String?] = []
    private(set) var requestedViewControllerTitles: [String?] = []
    private let tabMenu: UIMenu?
    private let viewControllerMenu: UIMenu?

    init(
        tabMenu: UIMenu? = UIMenu(children: []),
        viewControllerMenu: UIMenu? = UIMenu(children: [])
    ) {
        self.tabMenu = tabMenu
        self.viewControllerMenu = viewControllerMenu
    }

    func tabBarController(_ tabBarController: UITabBarController, tab: UITab?) -> UIMenu? {
        requestedTabIdentifiers.append(tab?.identifier)
        return tabMenu
    }

    func tabBarController(_ tabBarController: UITabBarController, viewController: UIViewController?) -> UIMenu? {
        requestedViewControllerTitles.append(viewController?.title)
        return viewControllerMenu
    }
}

@MainActor
final class MoreTabPresentationDelegate: NSObject, TabBarMenuDelegate {
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
final class ViewControllerMenuDelegate: NSObject, TabBarMenuDelegate {
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
final class RecordingTabBarControllerDelegate: NSObject, UITabBarControllerDelegate {
    private(set) var selectedViewControllers: [UIViewController] = []
    private(set) var selectedTabs: [UITab] = []
    private(set) var previousTabs: [UITab?] = []
    private(set) var displayedRequests: [(tab: UITab, proposedViewControllers: [UIViewController])] = []
    var displayedViewControllersResult: [UIViewController]?

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        selectedViewControllers.append(viewController)
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelectTab tab: UITab,
        previousTab: UITab?
    ) {
        selectedTabs.append(tab)
        previousTabs.append(previousTab)
    }

    @objc(tabBarController:displayedViewControllersForTab:proposedViewControllers:)
    func tabBarController(
        _ tabBarController: UITabBarController,
        displayedViewControllersFor tab: UITab,
        proposedViewControllers: [UIViewController]
    ) -> [UIViewController] {
        displayedRequests.append((tab, proposedViewControllers))
        return displayedViewControllersResult ?? proposedViewControllers
    }
}

@MainActor
final class NoViewTabBarItem: UITabBarItem {
    override func responds(to aSelector: Selector!) -> Bool {
        if let selector = aSelector, selector == UITabBarItemRuntimeMethods.view {
            return false
        }
        return super.responds(to: aSelector)
    }
}

@MainActor
final class SelfDelegatingTabBarController: UITabBarController, TabBarMenuDelegate {
    func tabBarController(_ tabBarController: UITabBarController, tab: UITab?) -> UIMenu? {
        UIMenu(children: [])
    }
}

@MainActor
final class WindowHost {
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
struct TabBarTestContext {
    let controller: UITabBarController
    let host: WindowHost
    let tabs: [UITab]
}

@MainActor
struct ViewControllerTabBarTestContext {
    let controller: UITabBarController
    let host: WindowHost
    let viewControllers: [UIViewController]
}

@MainActor
final class StandaloneTabBarHost {
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
final class TabBarLayoutRecorder {
    private(set) var events: [[Int]] = []

    init(tabBar: UITabBar) {
        tabBar.tabBarMenuLayoutHandler = { [weak self] tabBar in
            self?.events.append(tabBar.items?.map(\.tag) ?? [])
        }
    }
}

@MainActor
func makeTabs(count: Int) -> [UITab] {
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
func makeTabBarItems(count: Int) -> [UITabBarItem] {
    (0..<count).map { index in
        UITabBarItem(title: "Item \(index)", image: nil, tag: index)
    }
}

@MainActor
func makeViewControllers(count: Int) -> [UIViewController] {
    (0..<count).map { index in
        makeContentViewController(
            title: "View \(index)",
            itemTitle: "Item \(index)",
            tag: index
        )
    }
}

@MainActor
func makeViewControllersWithNoViewItems(count: Int) -> [UIViewController] {
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
func makeContentViewController(
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
func makeNavigationContentViewController(
    title: String,
    itemTitle: String,
    tag: Int = 0
) -> UINavigationController {
    let rootViewController = makeContentViewController(
        title: "\(title) Root",
        itemTitle: itemTitle,
        tag: tag
    )
    let detailViewController = makeContentViewController(
        title: title,
        itemTitle: itemTitle,
        tag: tag
    )
    let navigationController = UINavigationController(rootViewController: rootViewController)
    navigationController.pushViewController(detailViewController, animated: false)
    navigationController.tabBarItem = UITabBarItem(title: itemTitle, image: nil, tag: tag)
    navigationController.title = title
    return navigationController
}

@MainActor
func makeTabBarTestContext(tabCount: Int) -> TabBarTestContext {
    let tabs = makeTabs(count: tabCount)
    let controller = UITabBarController(tabs: tabs)
    let host = WindowHost(rootViewController: controller)
    return TabBarTestContext(controller: controller, host: host, tabs: tabs)
}

@MainActor
func makeViewControllerTabBarTestContext(viewControllerCount: Int) -> ViewControllerTabBarTestContext {
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

@MainActor
func tabBarControls(in view: UIView) -> [UIControl] {
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
func tabBarItemView(_ item: UITabBarItem) -> UIView? {
    ObjectiveCInterop.performObjectSelector(UITabBarItemRuntimeMethodNames.view, on: item) as? UIView
}
@MainActor
func tabBarButtonViews(in tabBar: UITabBar) -> [UIView] {
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
func tabBarFallbackControls(in tabBar: UITabBar) -> [UIControl] {
    let controls = tabBarControls(in: tabBar)
    let topLevelControls = controls.filter { $0.superview === tabBar }
    if !topLevelControls.isEmpty {
        return topLevelControls
    }
    return controls
}
@MainActor
func menuLongPressRecognizers(in tabBar: UITabBar) -> [TabBarMenuLongPressGestureRecognizer] {
    let controls = tabBarControls(in: tabBar)
    return controls.flatMap { control in
        (control.gestureRecognizers ?? []).compactMap { recognizer in
            recognizer as? TabBarMenuLongPressGestureRecognizer
        }
    }
}
@MainActor
func menuRecognizerIndices(in tabBar: UITabBar) -> Set<Int> {
    Set(menuLongPressRecognizers(in: tabBar).map(\.tabIndex))
}
@MainActor
func menuMinimumPressDurations(in tabBar: UITabBar) -> [TimeInterval] {
    menuLongPressRecognizers(in: tabBar).map(\.minimumPressDuration)
}
@MainActor
func menuRecognizerIdentityCount(in tabBar: UITabBar) -> Int {
    Set(menuLongPressRecognizers(in: tabBar).map(ObjectIdentifier.init)).count
}
@MainActor
func menuRecognizerIdentitySet(in tabBar: UITabBar) -> Set<ObjectIdentifier> {
    Set(menuLongPressRecognizers(in: tabBar).map(ObjectIdentifier.init))
}
@MainActor
func menuLongPressDurationsByIndex(in tabBar: UITabBar) -> [Int: TimeInterval] {
    Dictionary(uniqueKeysWithValues: menuLongPressRecognizers(in: tabBar).map { ($0.tabIndex, $0.minimumPressDuration) })
}
@MainActor
func menuRecognizerMinXAndIndices(in tabBar: UITabBar) -> [(minX: CGFloat, index: Int)] {
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
func moreTabBarItem(in tabBarController: UITabBarController) -> UITabBarItem? {
    guard let moreIndex = resolvedMoreTabIndex(in: tabBarController) else {
        return nil
    }
    guard let items = tabBarController.tabBar.items, items.indices.contains(moreIndex) else {
        return nil
    }
    return items[moreIndex]
}

@MainActor
func tabBarOrderedControls(in tabBar: UITabBar) -> [UIControl] {
    let controls = tabBarFallbackControls(in: tabBar)
    return controls.sorted { left, right in
        let leftFrame = left.convert(left.bounds, to: tabBar)
        let rightFrame = right.convert(right.bounds, to: tabBar)
        return leftFrame.minX < rightFrame.minX
    }
}

@MainActor
func moreTabBarControl(in tabBarController: UITabBarController) -> UIControl? {
    guard let moreIndex = resolvedMoreTabIndex(in: tabBarController) else {
        return nil
    }
    let controls = tabBarOrderedControls(in: tabBarController.tabBar)
    guard controls.indices.contains(moreIndex) else {
        return nil
    }
    return controls[moreIndex]
}

@MainActor
func resolvedMoreTabIndex(in tabBarController: UITabBarController) -> Int? {
    let totalCount = max(tabBarController.tabs.count, tabBarController.viewControllers?.count ?? 0)
    return TabBarMenuRequestCore(configuration: tabBarController.menuConfiguration).moreTabStartIndex(
        totalCount: totalCount,
        in: tabBarController
    )
}

@MainActor
func setMaximumNumberOfItems(_ count: UInt, in tabBarController: UITabBarController) -> Bool {
    let selector = NSSelectorFromString("_setMaximumNumberOfItems:")
    guard tabBarController.responds(to: selector) else {
        return false
    }

    typealias Function = @convention(c) (AnyObject, Selector, UInt) -> Void
    let implementation = unsafe unsafeBitCast(
        tabBarController.method(for: selector),
        to: Function.self
    )
    implementation(tabBarController, selector, count)
    return true
}

@MainActor
func firstVisibleTabControl(in tabBarController: UITabBarController) -> UIControl? {
    tabBarOrderedControls(in: tabBarController.tabBar).first
}

@MainActor
func invokeRuntimeMethodNamed(
    _ name: String,
    on object: NSObject,
    argument: AnyObject?
) {
    unsafe _ = object.perform(NSSelectorFromString(name), with: argument)
}

@MainActor
func displayedViewController(in navigationController: UINavigationController) -> UIViewController? {
    ObjectiveCInterop.performObjectSelector(
        UIMoreNavigationControllerRuntimeMethodNames.displayedViewController,
        on: navigationController
    ) as? UIViewController
}

@MainActor
func transientViewController(in tabBarController: UITabBarController) -> UIViewController? {
    ObjectiveCInterop.performObjectSelector(
        UITabBarControllerRuntimeMethodNames.transientViewController,
        on: tabBarController
    ) as? UIViewController
}

@MainActor
func selectedTabElement(in tabBarController: UITabBarController) -> UITab? {
    ObjectiveCInterop.performObjectSelector(
        UITabBarControllerRuntimeMethodNames.selectedTabElement,
        on: tabBarController
    ) as? UITab
}

@MainActor
func resolvedMoreTab(in tabBarController: UITabBarController) -> UITab? {
    ObjectiveCInterop.performObjectSelector(
        UIMoreNavigationControllerRuntimeMethodNames.resolvedTab,
        on: tabBarController.moreNavigationController
    ) as? UITab
}

@MainActor
func displayedViewControllers(in tab: UITab) -> [UIViewController] {
    (ObjectiveCInterop.performObjectSelector(
        UITabRuntimeMethodNames.displayedViewControllers,
        on: tab
    ) as? [UIViewController]) ?? []
}

@MainActor
func moreListController(in navigationController: UINavigationController) -> UIViewController? {
    ObjectiveCInterop.performObjectSelector(
        UIMoreNavigationControllerRuntimeMethodNames.moreListController,
        on: navigationController
    ) as? UIViewController
}

@MainActor
func setDisplayedViewController(
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
func selectedViewController(in tabBarController: UITabBarController) -> UIViewController? {
    unsafe tabBarController.selectedViewController
}

@MainActor
func selectedViewControllerInTabBar(in tabBarController: UITabBarController) -> UIViewController? {
    if let viewController = ObjectiveCInterop.performObjectSelector(
        UITabBarControllerRuntimeMethodNames.selectedViewControllerInTabBar,
        on: tabBarController
    ) as? UIViewController {
        return viewController
    }
    return selectedViewController(in: tabBarController)
}

@MainActor
func navigationStack(of navigationController: UINavigationController) -> [UIViewController] {
    navigationController.viewControllers
}

@MainActor
func canPopFromNavigationController(_ navigationController: UINavigationController) -> Bool {
    navigationController.viewControllers.count > 1
}

@MainActor
func selectedTabBarItem(in tabBarController: UITabBarController) -> UITabBarItem? {
    tabBarController.tabBar.selectedItem
}

@MainActor
func title(of item: UITabBarItem?) -> String? {
    item?.title
}

@MainActor
func labelTexts(in view: UIView) -> [String] {
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
func tabBarButtonTitles(in tabBarController: UITabBarController) -> [String] {
    tabBarOrderedControls(in: tabBarController.tabBar).compactMap { control in
        labelTexts(in: control).last
    }
}

@MainActor
func visibleContentTitles(in tabBarController: UITabBarController) -> [String] {
    contentLabelTexts(in: tabBarController.view, excluding: tabBarController.tabBar)
}

@MainActor
func containsViewController(
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
func contentLabelTexts(in view: UIView, excluding excludedRoot: UIView) -> [String] {
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
func drainMainQueue(iterations: Int = 4) async {
    for _ in 0..<iterations {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

@MainActor
func usesUITabDisplayedViewControllersOverflowPath() -> Bool {
    if #available(iOS 26.0, *) {
        return true
    }
    return false
}

@MainActor
func makeMoreMenuRequest(
    in tabBarController: UITabBarController,
    delegate: TabBarMenuContentDelegate
) -> MoreMenuRequest? {
    MoreMenuRequest.make(
        delegate: delegate,
        core: TabBarMenuRequestCore(configuration: tabBarController.menuConfiguration)
    )
}

@MainActor
@discardableResult
func requestMoreMenu(
    in tabBarController: UITabBarController,
    delegate: TabBarMenuContentDelegate
) -> UIMenu? {
    makeMoreMenuRequest(in: tabBarController, delegate: delegate)?
        .menu(in: tabBarController, delegate: delegate)
}

@MainActor
func expectUITabOverflowSelection(
    in tabBarController: UITabBarController,
    targetTab: UITab,
    targetViewController: UIViewController,
    preservedMoreItem: UITabBarItem?
) {
    let override = tabBarController.tabBarMenuDisplayedViewControllersOverride(
        for: targetTab,
        proposedViewControllers: []
    )

    #expect(visibleContentTitles(in: tabBarController) == [targetViewController.title].compactMap { $0 })
    if usesUITabDisplayedViewControllersOverflowPath() {
        #expect(tabBarController.tabBarMenuHasActiveUITabMoreSelection == true)
        #expect(transientViewController(in: tabBarController) == nil)
        #expect(override?.count == 1)
        #expect(override?.contains { containsViewController($0, descendant: targetViewController) } == true)
        #expect(navigationStack(of: tabBarController.moreNavigationController).count == 2)
        #expect(navigationStack(of: tabBarController.moreNavigationController).first === moreListController(in: tabBarController.moreNavigationController))
        #expect(navigationStack(of: tabBarController.moreNavigationController).last.map { containsViewController($0, descendant: targetViewController) } == true)
        #expect(displayedViewController(in: tabBarController.moreNavigationController) === targetViewController)
        #expect(tabBarController.moreNavigationController.interactivePopGestureRecognizer?.isEnabled == false)
    } else {
        #expect(tabBarController.tabBarMenuHasActiveUITabMoreSelection == false)
        #expect(selectedViewControllerInTabBar(in: tabBarController) === tabBarController.moreNavigationController)
        #expect(transientViewController(in: tabBarController) == nil)
        #expect(override == nil)
    }

    if let preservedMoreItem {
        #expect(title(of: selectedTabBarItem(in: tabBarController)) == title(of: preservedMoreItem))
        #expect(tabBarButtonTitles(in: tabBarController).last == title(of: preservedMoreItem))
    }
}
