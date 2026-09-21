import Testing
import UIKit
@testable import TabBarMenu

@MainActor
private final class InteractionDelegate: TabBarMenuDelegate {
    var prepare: (TabBarInteraction, TabBarItem) -> TabBarMenuPresentation? = { _, _ in nil }
    var interactions: [TabBarInteraction] = []
    var items: [TabBarItem] = []
    var selections: [(UITab, UITab?, Bool)] = []
    var viewControllerSelections: [(UIViewController, UIViewController?, Bool)] = []

    func tabBarController(_ controller: UITabBarController, prepareFor interaction: TabBarInteraction, on item: TabBarItem) -> TabBarMenuPresentation? {
        interactions.append(interaction)
        items.append(item)
        return prepare(interaction, item)
    }

    func tabBarController(_ controller: UITabBarController, didSelect tab: UITab, previousTab: UITab?, isOverflow: Bool) {
        selections.append((tab, previousTab, isOverflow))
    }

    func tabBarController(_ controller: UITabBarController, didSelect viewController: UIViewController, previousViewController: UIViewController?, isOverflow: Bool) {
        viewControllerSelections.append((viewController, previousViewController, isOverflow))
    }
}

@MainActor
private final class SelectionPermissionDelegate: NSObject, UITabBarControllerDelegate {
    var allowsSelection = false
    func tabBarController(_ controller: UITabBarController, shouldSelectTab tab: UITab) -> Bool { allowsSelection }
    func tabBarController(_ controller: UITabBarController, shouldSelect viewController: UIViewController) -> Bool { allowsSelection }
}

@Test("A More tap reselects current content once without rebuilding its navigation stack")
@MainActor
func moreTapReselectsCurrentContent() async throws {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = InteractionDelegate()
    context.controller.menuDelegate = delegate
    let tab = context.tabs[5]
    #expect(context.controller.selectTabContent(tab))
    await drainMainQueue()
    #expect(delegate.selections.isEmpty)
    let stack = context.controller.moreNavigationController.viewControllers
    let control = try #require(moreTabBarControl(in: context.controller))
    invokeRuntimeMethodNamed(UITabBarRuntimeMethodNames.buttonUp, on: context.controller.tabBar, argument: control)
    await drainMainQueue()

    #expect(delegate.interactions == [.tap])
    guard case .more(let tabs, let selected) = try #require(delegate.items.first) else {
        Issue.record("Expected More preparation")
        return
    }
    #expect(tabs.contains { $0 === tab })
    #expect(selected === tab)
    #expect(delegate.selections.count == 1)
    let selection = try #require(delegate.selections.first)
    #expect(selection.0 === tab)
    #expect(selection.1 === tab)
    #expect(selection.2)
    #expect(context.controller.moreNavigationController.viewControllers.map(ObjectIdentifier.init) == stack.map(ObjectIdentifier.init))
    #expect(visibleContentTitles(in: context.controller) == [tab.title])
}

@Test("Long press presents the prepared menu, placement, and element order without selecting", arguments: [UIContextMenuConfiguration.ElementOrder.automatic, .fixed])
@MainActor
func longPressUsesPreparedPresentation(order: UIContextMenuConfiguration.ElementOrder) async throws {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = InteractionDelegate()
    let menu = UIMenu(children: [UIAction(title: "First") { _ in }, UIAction(title: "Second") { _ in }])
    delegate.prepare = { interaction, _ in
        interaction == .longPress ? .init(menu: menu, anchorPlacement: .inside, preferredMenuElementOrder: order) : nil
    }
    context.controller.menuDelegate = delegate
    #expect(context.controller.selectTabContent(context.tabs[5]))
    await drainMainQueue()
    let control = try #require(moreTabBarControl(in: context.controller))
    let coordinator = try #require(context.controller.tabBarMenuCoordinator)
    let index = try #require(resolvedMoreTabIndex(in: context.controller))
    #expect(coordinator.handleInteraction(.longPress, at: index, sourceView: control) == false)

    let host = try #require(context.controller.view.subviews.compactMap { $0 as? UIButton }.first)
    #expect(host.menu?.children.map(\.title) == ["First", "Second"])
    #expect(host.preferredMenuElementOrder == order)
    let frame = control.convert(control.bounds, to: context.controller.view)
    #expect(host.frame == tabBarMenuAnchorFrame(tabFrame: frame, placement: .inside))
    #expect(delegate.interactions == [.longPress])
    #expect(delegate.selections.isEmpty)
    #expect(context.controller.tabBarMenuSelectedTab === context.tabs[5])
}

@Test("A nil long-press preparation performs no selection")
@MainActor
func nilLongPressDoesNotSelect() throws {
    let context = makeTabBarTestContext(tabCount: 3)
    let delegate = InteractionDelegate()
    context.controller.menuDelegate = delegate
    let coordinator = try #require(context.controller.tabBarMenuCoordinator)
    let controls = tabBarOrderedControls(in: context.controller.tabBar)
    #expect(coordinator.handleInteraction(.longPress, at: 1, sourceView: controls[1]) == false)
    #expect(context.controller.tabBarMenuSelectedTab === context.tabs[0])
    #expect(delegate.interactions == [.longPress])
    #expect(delegate.selections.isEmpty)
}

@Test("Prepared native taps report selection and reselection from UIKit callbacks")
@MainActor
func nativeTapSelectionNotifications() async throws {
    let context = makeTabBarTestContext(tabCount: 3)
    let delegate = InteractionDelegate()
    context.controller.menuDelegate = delegate
    let controls = tabBarOrderedControls(in: context.controller.tabBar)
    for _ in 0..<2 {
        let previous = context.controller.selectedTab
        let handler = try #require(context.controller.tabBar.tabBarMenuControlSelectionHandler)
        #expect(handler(context.controller.tabBar, controls[1]))
        #expect(context.controller.delegate?.tabBarController?(context.controller, shouldSelectTab: context.tabs[1]) == true)
        context.controller.selectedTab = context.tabs[1]
        context.controller.delegate?.tabBarController?(context.controller, didSelectTab: context.tabs[1], previousTab: previous)
        await drainMainQueue()
    }
    #expect(context.controller.tabBarMenuSelectedTab === context.tabs[1])
    #expect(delegate.interactions == [.tap, .tap])
    #expect(delegate.selections.count == 2)
    guard delegate.selections.count == 2 else { return }
    #expect(delegate.selections[0].0 === context.tabs[1])
    #expect(delegate.selections[0].1 === context.tabs[0])
    #expect(delegate.selections[1].1 === context.tabs[1])
    #expect(delegate.selections.allSatisfy { !$0.2 })
}

@Test("Menu actions report one selection; programmatic selection and layout are silent")
@MainActor
func menuActionsAndSilentProgrammaticSelections() async throws {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = InteractionDelegate()
    context.controller.menuDelegate = delegate
    let action = context.controller.selectionAction(for: context.tabs[5])
    #expect(context.controller.selectTabContent(context.tabs[1]))
    await drainMainQueue()
    context.host.window.layoutIfNeeded()
    #expect(delegate.interactions.isEmpty)
    #expect(delegate.selections.isEmpty)
    UIControl().sendAction(action)
    await drainMainQueue()
    #expect(delegate.interactions.isEmpty)
    #expect(delegate.selections.count == 1)
    let selection = try #require(delegate.selections.first)
    #expect(selection.0 === context.tabs[5])
    #expect(selection.1 === context.tabs[1])
    #expect(selection.2)
    #expect(context.controller.tabBarMenuSelectedTab === context.tabs[5])

    // Moving the same object out of More changes the event's overflow flag.
    context.controller.setTabs([context.tabs[5], context.tabs[0]], animated: false)
    await drainMainQueue()
    UIControl().sendAction(action)
    #expect(delegate.selections.last?.2 == false)
}

@Test("Selection actions respect disabled, removed, and vetoed tabs")
@MainActor
func menuActionSelectionPermissions() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = InteractionDelegate()
    let permissions = SelectionPermissionDelegate()
    context.controller.delegate = permissions
    context.controller.menuDelegate = delegate
    let tab = context.tabs[5]
    let action = context.controller.selectionAction(for: tab)
    UIControl().sendAction(action)
    #expect(delegate.selections.isEmpty)
    permissions.allowsSelection = true
    if #available(iOS 18.4, *) {
        tab.isEnabled = false
        UIControl().sendAction(action)
        #expect(delegate.selections.isEmpty)
        tab.isEnabled = true
    }
    context.controller.setTabs(Array(context.tabs.prefix(5)), animated: false)
    UIControl().sendAction(action)
    await drainMainQueue()
    #expect(delegate.selections.isEmpty)
}

@Test("Classic More content supports the same preparation and selection lifecycle")
@MainActor
func classicMoreInteractionLifecycle() async throws {
    let context = makeViewControllerTabBarTestContext(viewControllerCount: 6)
    let delegate = InteractionDelegate()
    context.controller.menuDelegate = delegate
    let target = context.viewControllers[5]
    UIControl().sendAction(context.controller.selectionAction(for: target))
    await drainMainQueue()
    let selection = try #require(delegate.viewControllerSelections.first)
    #expect(selection.0 === target)
    #expect(selection.1 === context.viewControllers[0])
    #expect(selection.2)
    let control = try #require(moreTabBarControl(in: context.controller))
    invokeRuntimeMethodNamed(UITabBarRuntimeMethodNames.buttonUp, on: context.controller.tabBar, argument: control)
    await drainMainQueue()
    #expect(delegate.viewControllerSelections.count == 2)
    #expect(delegate.viewControllerSelections.last?.1 === target)
    #expect(context.controller.tabBarMenuSelectedViewController === target)
    guard case .moreViewControllers(_, let selected) = try #require(delegate.items.last) else {
        Issue.record("Expected classic More preparation")
        return
    }
    #expect(selected === target)
}

@Test("Presentation defaults retain automatic UIKit ordering")
@MainActor
func presentationDefaults() {
    let presentation = TabBarMenuPresentation(menu: UIMenu(children: []))
    #expect(presentation.preferredMenuElementOrder == .automatic)
    #expect(presentation.anchorPlacement == .above())
}

@Test("Native More navigation reports the displayed content")
@MainActor
func nativeMoreNavigationSelectionNotification() async throws {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = InteractionDelegate()
    context.controller.menuDelegate = delegate
    let navigationController = context.controller.moreNavigationController
    let target = try #require(context.tabs[5].resolvedMoreSelectionViewController)
    let moreItem = try #require(moreTabBarItem(in: context.controller))
    let navigationDelegate = try #require(navigationController.delegate)
    navigationController.loadViewIfNeeded()
    navigationDelegate.navigationController?(navigationController, willShow: target, animated: false)
    navigationController.delegate = nil
    navigationController.setViewControllers([try #require(moreListController(in: navigationController)), target], animated: false)
    #expect(ObjectiveCInterop.performVoidSelector(
        UITabBarControllerRuntimeMethodNames.setSelectedTabBarItem,
        on: context.controller, with: moreItem
    ))
    navigationController.delegate = navigationDelegate
    navigationDelegate.navigationController?(navigationController, didShow: target, animated: false)
    #expect(delegate.selections.count == 1)
    #expect(delegate.selections.first?.0 === context.tabs[5])
    #expect(delegate.selections.first?.1 == nil)
    #expect(delegate.selections.first?.2 == true)
}

@Test("Long-press item identity remains correct while More is active")
@MainActor
func overflowLongPressUsesItemIdentity() async throws {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = InteractionDelegate()
    context.controller.menuDelegate = delegate
    #expect(context.controller.selectTabContent(context.tabs[5]))
    await drainMainQueue()
    let extraControl = UIControl(frame: CGRect(x: -10, y: 0, width: 1, height: 1))
    context.controller.tabBar.addSubview(extraControl)
    defer { extraControl.removeFromSuperview() }
    let coordinator = try #require(context.controller.tabBarMenuCoordinator)
    for (index, item) in (context.controller.tabBar.items ?? []).enumerated() {
        let view = try #require(tabBarItemView(item))
        #expect(coordinator.resolvedTabIndex(for: view, in: context.controller) == index)
    }
}

@MainActor
private final class LegacySelectionPermission: NSObject, UITabBarControllerDelegate {
    var requests = 0
    var allowsSelection = false
    func tabBarController(_ controller: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        requests += 1
        return allowsSelection
    }
}

@Test("UITab actions honor a legacy permission delegate exactly once")
@MainActor
func legacySelectionPermissionForUITab() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = InteractionDelegate()
    let permission = LegacySelectionPermission()
    context.controller.delegate = permission
    context.controller.menuDelegate = delegate
    let action = context.controller.selectionAction(for: context.tabs[5])
    UIControl().sendAction(action)
    #expect(permission.requests == 1)
    #expect(delegate.selections.isEmpty)
    permission.allowsSelection = true
    UIControl().sendAction(action)
    await drainMainQueue()
    #expect(permission.requests == 2)
    #expect(delegate.selections.count == 1)
}

@MainActor
private final class MoreNavigationDelegate: NSObject, UINavigationControllerDelegate {
    var shown: [UIViewController] = []
    func navigationController(_ controller: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        shown.append(viewController)
    }
}

@Test("More navigation delegates are forwarded and restored on detach")
@MainActor
func moreNavigationDelegateLifetime() throws {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = InteractionDelegate()
    let navigationDelegate = MoreNavigationDelegate()
    let navigation = context.controller.moreNavigationController
    navigation.delegate = navigationDelegate
    context.controller.menuDelegate = delegate
    let proxy = try #require(navigation.delegate)
    let content = UIViewController()
    proxy.navigationController?(navigation, didShow: content, animated: false)
    #expect(navigationDelegate.shown.last === content)
    context.controller.menuDelegate = nil
    #expect(navigation.delegate === navigationDelegate)
}
