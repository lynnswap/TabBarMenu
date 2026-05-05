import Testing
import UIKit
@testable import TabBarMenu

@Test("menuDelegate restores an existing tab bar controller delegate when unset")
@MainActor
func menuDelegateRestoresExistingTabBarControllerDelegateWhenUnset() {
    let controller = UITabBarController(tabs: makeTabs(count: 2))
    let originalDelegate = RecordingTabBarControllerDelegate()
    let menuDelegate = TestMenuDelegate()
    controller.delegate = originalDelegate

    controller.menuDelegate = menuDelegate

    #expect(controller.delegate is TabBarMenuTabBarControllerDelegateProxy)
    #expect(controller.delegate !== originalDelegate)

    controller.menuDelegate = nil

    #expect(controller.delegate === originalDelegate)
}

@Test("delegate proxy forwards selection callbacks")
@MainActor
func delegateProxyForwardsSelectionCallbacks() {
    let controller = UITabBarController(tabs: makeTabs(count: 2))
    let proxy = TabBarMenuTabBarControllerDelegateProxy()
    let originalDelegate = RecordingTabBarControllerDelegate()
    let selectedViewController = UIViewController()

    proxy.tabBarController = controller
    proxy.originalDelegate = originalDelegate

    proxy.tabBarController(controller, didSelect: selectedViewController)
    proxy.tabBarController(controller, didSelectTab: controller.tabs[1], previousTab: controller.tabs[0])

    #expect(originalDelegate.selectedViewControllers.count == 1)
    #expect(originalDelegate.selectedViewControllers.first === selectedViewController)
    #expect(originalDelegate.selectedTabs.count == 1)
    #expect(originalDelegate.selectedTabs.first === controller.tabs[1])
    #expect(originalDelegate.previousTabs.first ?? nil === controller.tabs[0])
}

@Test("delegate proxy forwards displayed view controllers when no override is active")
@MainActor
func delegateProxyForwardsDisplayedViewControllersWhenNoOverrideIsActive() {
    let controller = UITabBarController(tabs: makeTabs(count: 2))
    let proxy = TabBarMenuTabBarControllerDelegateProxy()
    let originalDelegate = RecordingTabBarControllerDelegate()
    let proposedViewController = UIViewController()
    let forwardedViewController = UIViewController()
    originalDelegate.displayedViewControllersResult = [forwardedViewController]

    proxy.tabBarController = controller
    proxy.originalDelegate = originalDelegate

    let result = proxy.tabBarController(
        controller,
        displayedViewControllersFor: controller.tabs[0],
        proposedViewControllers: [proposedViewController]
    )

    #expect(result.map(ObjectIdentifier.init) == [ObjectIdentifier(forwardedViewController)])
    #expect(originalDelegate.displayedRequests.count == 1)
    if let request = originalDelegate.displayedRequests.first {
        #expect(request.tab === controller.tabs[0])
        #expect(request.proposedViewControllers.first === proposedViewController)
    }
}

@Test("delegate proxy uses active UITab overflow override before original delegate")
@MainActor
func delegateProxyUsesActiveUITabOverflowOverrideBeforeOriginalDelegate() async {
    guard #available(iOS 26.0, *) else {
        return
    }

    let context = makeTabBarTestContext(tabCount: 6)
    let proxy = TabBarMenuTabBarControllerDelegateProxy()
    let originalDelegate = RecordingTabBarControllerDelegate()
    let fallbackViewController = UIViewController()
    originalDelegate.displayedViewControllersResult = [fallbackViewController]

    proxy.tabBarController = context.controller
    proxy.originalDelegate = originalDelegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let targetTab = context.tabs[5]
    guard let targetViewController = targetTab.resolvedMoreSelectionViewController else {
        Issue.record("Expected the overflow UITab to resolve a view controller")
        return
    }

    let didSelect = context.controller.selectTabContent(targetTab)
    await drainMainQueue()
    let result = proxy.tabBarController(
        context.controller,
        displayedViewControllersFor: targetTab,
        proposedViewControllers: []
    )

    #expect(didSelect == true)
    #expect(result.contains { containsViewController($0, descendant: targetViewController) })
    #expect(result.map(ObjectIdentifier.init) != [ObjectIdentifier(fallbackViewController)])
    #expect(originalDelegate.displayedRequests.isEmpty)
}
