import Testing
import UIKit
@testable import TabBarMenu

@MainActor
private final class MutationMenuDelegate: TabBarMenuDelegate {
    var prepare: ((UITabBarController) -> Void)?
    var didSelect: ((UITabBarController) -> Void)?
    var selections: [(content: TabBarContent, previous: TabBarContent?, isOverflow: Bool)] = []

    func tabBarController(_ controller: UITabBarController, prepareFor interaction: TabBarInteraction, on item: TabBarItem) -> TabBarMenuPresentation? {
        prepare?(controller)
        return nil
    }

    func tabBarController(_ controller: UITabBarController, didSelect tab: UITab, previousTab: UITab?, isOverflow: Bool) {
        selections.append((.tab(tab), previousTab.map(TabBarContent.tab), isOverflow))
        didSelect?(controller)
    }

    func tabBarController(_ controller: UITabBarController, didSelect viewController: UIViewController, previousViewController: UIViewController?, isOverflow: Bool) {
        selections.append((.viewController(viewController), previousViewController.map(TabBarContent.viewController), isOverflow))
        didSelect?(controller)
    }
}

@MainActor
private final class MutationUIKitDelegate: NSObject, UITabBarControllerDelegate {
    var allowsSelection = true
    var permissionCalls = 0
    var selectionCalls = 0
    var onSelection: ((UITabBarController) -> Void)?

    func tabBarController(_ controller: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        permissionCalls += 1
        return allowsSelection
    }

    func tabBarController(_ controller: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        permissionCalls += 1
        return allowsSelection
    }

    func tabBarController(_ controller: UITabBarController, didSelectTab tab: UITab, previousTab: UITab?) {
        selected(in: controller)
    }

    func tabBarController(_ controller: UITabBarController, didSelect viewController: UIViewController) {
        selected(in: controller)
    }

    private func selected(in controller: UITabBarController) {
        selectionCalls += 1
        let action = onSelection
        onSelection = nil
        action?(controller)
    }
}

@MainActor
private struct DelegateMutationContext {
    let controller: UITabBarController
    let tabs: [UITab]
    let viewControllers: [UIViewController]
    let host: WindowHost
    let usesUITab: Bool

    init(usesUITab: Bool, count: Int = 3) {
        self.usesUITab = usesUITab
        viewControllers = makeViewControllers(count: count)
        tabs = viewControllers.enumerated().map { index, viewController in
            UITab(title: "Tab \(index)", image: nil, identifier: "tab.\(index)") { _ in viewController }
        }
        controller = UITabBarController()
        if usesUITab {
            controller.tabs = tabs
        } else {
            controller.setViewControllers(viewControllers, animated: false)
        }
        host = WindowHost(rootViewController: controller)
    }

    func content(at index: Int) -> TabBarContent {
        usesUITab ? .tab(tabs[index]) : .viewController(viewControllers[index])
    }

    func selectionAction(at index: Int) -> UIAction {
        usesUITab ? controller.selectionAction(for: tabs[index]) : controller.selectionAction(for: viewControllers[index])
    }

    func selectProgrammatically(at index: Int) {
        if usesUITab {
            #expect(controller.selectTabContent(tabs[index]))
        } else {
            #expect(controller.selectTabContent(viewControllers[index]))
        }
    }

    func replaceContent() {
        if usesUITab {
            controller.setTabs([tabs[0]], animated: false)
        } else {
            controller.setViewControllers([viewControllers[0]], animated: false)
        }
    }

    /// Supplies the UIKit selection callbacks after the real tab-bar interception boundary.
    func tap(at index: Int) throws {
        let control = tabBarOrderedControls(in: controller.tabBar)[index]
        let handler = try #require(controller.tabBar.tabBarMenuControlSelectionHandler)
        #expect(handler(controller.tabBar, control))
        let delegate = try #require(controller.delegate as? TabBarMenuTabBarControllerDelegateProxy)
        let recipient = try #require(delegate.originalDelegate as? MutationUIKitDelegate)
        if usesUITab {
            let previous = controller.selectedTab
            guard delegate.tabBarController(controller, shouldSelectTab: tabs[index]) else { return }
            let callsBeforeSelection = recipient.selectionCalls
            controller.selectedTab = tabs[index]
            // Some runtimes deliver completion from the property assignment itself.
            if recipient.selectionCalls == callsBeforeSelection {
                delegate.tabBarController(controller, didSelectTab: tabs[index], previousTab: previous)
            }
        } else {
            guard delegate.tabBarController(controller, shouldSelect: viewControllers[index]) else { return }
            let callsBeforeSelection = recipient.selectionCalls
            unsafe controller.selectedViewController = viewControllers[index]
            if recipient.selectionCalls == callsBeforeSelection {
                delegate.tabBarController(controller, didSelect: viewControllers[index])
            }
        }
    }
}

@Test("Menu actions consult a replacement UIKit delegate without a layout pass", arguments: [false, true])
@MainActor
func replacementDelegateForMenuActions(usesUITab: Bool) async {
    let context = DelegateMutationContext(usesUITab: usesUITab, count: 6)
    defer { withExtendedLifetime(context) {} }
    let original = MutationUIKitDelegate()
    let replacement = MutationUIKitDelegate()
    replacement.allowsSelection = false
    let menuDelegate = MutationMenuDelegate()
    context.controller.delegate = original
    context.controller.menuDelegate = menuDelegate
    let action = context.selectionAction(at: 5)
    context.controller.delegate = replacement

    UIControl().sendAction(action)
    #expect(replacement.permissionCalls == 1)
    #expect(original.permissionCalls == 0)
    #expect(menuDelegate.selections.isEmpty)
    #expect(context.controller.tabBarMenuSelectedContent == context.content(at: 0))

    replacement.allowsSelection = true
    UIControl().sendAction(action)
    await drainMainQueue()
    #expect(replacement.permissionCalls == 2)
    #expect(menuDelegate.selections.count == 1)
    #expect(menuDelegate.selections.first?.content == context.content(at: 5))
    #expect(menuDelegate.selections.first?.previous == context.content(at: 0))
    #expect(menuDelegate.selections.first?.isOverflow == true)
    context.controller.menuDelegate = nil
    #expect(context.controller.delegate === replacement)
}

@Test("Native taps reconnect a delegate replaced before or during preparation", arguments: [false, true], [false, true])
@MainActor
func replacementDelegateForNativeTaps(usesUITab: Bool, duringPreparation: Bool) throws {
    let context = DelegateMutationContext(usesUITab: usesUITab)
    defer { withExtendedLifetime(context) {} }
    let original = MutationUIKitDelegate()
    let replacement = MutationUIKitDelegate()
    replacement.allowsSelection = false
    let menuDelegate = MutationMenuDelegate()
    context.controller.delegate = original
    context.controller.menuDelegate = menuDelegate
    if duringPreparation {
        menuDelegate.prepare = { $0.delegate = replacement }
    } else {
        context.controller.delegate = replacement
    }
    try context.tap(at: 1)
    #expect(replacement.permissionCalls == 1)
    #expect(original.permissionCalls == 0)
    #expect(menuDelegate.selections.isEmpty)
    #expect(context.controller.tabBarMenuSelectedContent == context.content(at: 0))

    replacement.allowsSelection = true
    try context.tap(at: 1)
    #expect(menuDelegate.selections.count == 1)
    #expect(menuDelegate.selections.first?.content == context.content(at: 1))
    #expect(menuDelegate.selections.first?.previous == context.content(at: 0))
    #expect(menuDelegate.selections.first?.isOverflow == false)
    #expect(replacement.selectionCalls == 1)
}

@Test("Selection completion precedes synchronous changes in the forwarded UIKit delegate", arguments: [false, true], [false, true])
@MainActor
func forwardedDelegateMutatesSelection(usesUITab: Bool, replacesContent: Bool) async throws {
    let context = DelegateMutationContext(usesUITab: usesUITab)
    defer { withExtendedLifetime(context) {} }
    let original = MutationUIKitDelegate()
    let menuDelegate = MutationMenuDelegate()
    context.controller.delegate = original
    context.controller.menuDelegate = menuDelegate
    original.onSelection = { _ in
        #expect(menuDelegate.selections.count == 1)
        if replacesContent {
            context.replaceContent()
        } else {
            context.selectProgrammatically(at: 2)
        }
    }
    try context.tap(at: 1)
    await drainMainQueue()
    #expect(menuDelegate.selections.count == 1)
    #expect(menuDelegate.selections.first?.content == context.content(at: 1))
    #expect(menuDelegate.selections.first?.previous == context.content(at: 0))
    #expect(menuDelegate.selections.first?.isOverflow == false)
}

@Test("Forwarding retains the recipient of the completed event", arguments: [false, true])
@MainActor
func selectionCallbackReplacesForwardedDelegate(usesUITab: Bool) throws {
    let context = DelegateMutationContext(usesUITab: usesUITab)
    defer { withExtendedLifetime(context) {} }
    let original = MutationUIKitDelegate()
    let replacement = MutationUIKitDelegate()
    let menuDelegate = MutationMenuDelegate()
    context.controller.delegate = original
    context.controller.menuDelegate = menuDelegate
    menuDelegate.didSelect = { controller in
        controller.delegate = replacement
        controller.tabBarMenuCoordinator?.refreshInteractions()
    }
    try context.tap(at: 1)
    #expect(menuDelegate.selections.count == 1)
    #expect(original.selectionCalls == 1)
    #expect(replacement.selectionCalls == 0)
}

@MainActor
private final class MutationNavigationDelegate: NSObject, UINavigationControllerDelegate {
    var didShow: (() -> Void)?
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        let action = didShow
        didShow = nil
        action?()
    }
}

@Test("More selection completion precedes changes in the forwarded navigation delegate", arguments: [false, true], [false, true])
@MainActor
func forwardedMoreDelegateMutatesSelection(usesUITab: Bool, replacesContent: Bool) async throws {
    let context = DelegateMutationContext(usesUITab: usesUITab, count: 6)
    defer { withExtendedLifetime(context) {} }
    let navigation = context.controller.moreNavigationController
    let original = MutationNavigationDelegate()
    navigation.delegate = original
    let menuDelegate = MutationMenuDelegate()
    context.controller.menuDelegate = menuDelegate
    navigation.loadViewIfNeeded()
    let proxy = try #require(navigation.delegate)
    let target = context.viewControllers[5]
    proxy.navigationController?(navigation, willShow: target, animated: false)
    navigation.delegate = nil
    navigation.setViewControllers([try #require(moreListController(in: navigation)), target], animated: false)
    #expect(ObjectiveCInterop.performVoidSelector(
        UITabBarControllerRuntimeMethodNames.setSelectedViewControllerAndNotify,
        on: context.controller, with: navigation
    ))
    #expect(ObjectiveCInterop.performVoidSelector(
        UITabBarControllerRuntimeMethodNames.setSelectedTabBarItem,
        on: context.controller, with: try #require(moreTabBarItem(in: context.controller))
    ))
    setDisplayedViewController(target, in: navigation)
    navigation.delegate = proxy
    original.didShow = {
        #expect(menuDelegate.selections.count == 1)
        if replacesContent {
            context.replaceContent()
        } else {
            context.selectProgrammatically(at: 0)
        }
    }
    proxy.navigationController?(navigation, didShow: target, animated: false)
    await drainMainQueue()
    #expect(menuDelegate.selections.count == 1)
    #expect(menuDelegate.selections.first?.content == context.content(at: 5))
    #expect(menuDelegate.selections.first?.previous == nil)
    #expect(menuDelegate.selections.first?.isOverflow == true)
}

@Test("Detaching during preparation does not reconnect an abandoned proxy", arguments: [false, true])
@MainActor
func detachDuringPreparation(usesUITab: Bool) throws {
    let context = DelegateMutationContext(usesUITab: usesUITab)
    defer { withExtendedLifetime(context) {} }
    let original = MutationUIKitDelegate()
    let menuDelegate = MutationMenuDelegate()
    context.controller.delegate = original
    context.controller.menuDelegate = menuDelegate
    menuDelegate.prepare = { $0.menuDelegate = nil }
    let handler = try #require(context.controller.tabBar.tabBarMenuControlSelectionHandler)
    #expect(handler(context.controller.tabBar, tabBarOrderedControls(in: context.controller.tabBar)[1]))
    #expect(context.controller.menuDelegate == nil)
    #expect(context.controller.delegate === original)
    #expect(menuDelegate.selections.isEmpty)
}
