import Testing
import UIKit
@testable import TabBarMenu

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
        await drainMainQueue()

        #expect(didSelect == true)
        expectUITabOverflowSelection(
            in: context.controller,
            targetTab: targetTab,
            targetViewController: targetViewController,
            preservedMoreItem: preservedMoreItem
        )
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

    #expect(targetViewController != nil)
    #expect(preservedMoreItem != nil)

    if let targetViewController, let preservedMoreItem {
        #expect(requestMoreMenu(in: context.controller, delegate: delegate) != nil)
        delegate.performSelection(titled: targetTab.title)
        await drainMainQueue()

        expectUITabOverflowSelection(
            in: context.controller,
            targetTab: targetTab,
            targetViewController: targetViewController,
            preservedMoreItem: preservedMoreItem
        )
    }
}

@Test("first More UITab selection shows overflow content")
@MainActor
func firstMoreTabSelectionShowsOverflowContent() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabSelectionDelegate()

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let targetTab = context.tabs[5]
    let targetViewController = targetTab.resolvedMoreSelectionViewController

    #expect(targetViewController != nil)

    if let targetViewController {
        #expect(requestMoreMenu(in: context.controller, delegate: delegate) != nil)
        delegate.performSelection(titled: targetTab.title)
        await drainMainQueue()

        #expect(visibleContentTitles(in: context.controller) == [targetViewController.title].compactMap { $0 })
        if usesUITabDisplayedViewControllersOverflowPath() {
            #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == true)
            #expect(transientViewController(in: context.controller) == nil)
        } else {
            #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == false)
            #expect(selectedViewControllerInTabBar(in: context.controller) === context.controller.moreNavigationController)
            #expect(transientViewController(in: context.controller) == nil)
        }
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

    #expect(preservedMoreItem != nil)

    if preservedMoreItem != nil {
        #expect(requestMoreMenu(in: context.controller, delegate: delegate) != nil)
        delegate.performSelection(titled: targetViewController.title ?? targetViewController.tabBarItem.title ?? "Untitled")

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

    #expect(preservedMoreItem != nil)

    if let preservedMoreItem {
        #expect(requestMoreMenu(in: context.controller, delegate: delegate) != nil)
        #expect(delegate.requestedViewControllers.last?.map(ObjectIdentifier.init) == [
            ObjectIdentifier(context.viewControllers[4]),
            ObjectIdentifier(context.viewControllers[5]),
        ])

        let targetTitle = context.viewControllers[5].title ?? context.viewControllers[5].tabBarItem.title ?? "Untitled"
        delegate.performSelection(titled: targetTitle)

        #expect(requestMoreMenu(in: context.controller, delegate: delegate) != nil)

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
    let moreTab = resolvedMoreTab(in: context.controller)

    #expect(overflowViewController != nil)
    #expect(visibleViewController != nil)
    #expect(moreTab != nil)

    if let overflowViewController, let visibleViewController, let moreTab {
        let originalOverflowDisplayedIdentifiers = displayedViewControllers(in: overflowTab).map(ObjectIdentifier.init)
        let originalMoreDisplayedIdentifiers = displayedViewControllers(in: moreTab).map(ObjectIdentifier.init)

        _ = context.controller.selectTabContent(overflowTab)
        await drainMainQueue()
        let overrideBeforeDismiss = context.controller.tabBarMenuDisplayedViewControllersOverride(
            for: overflowTab,
            proposedViewControllers: []
        )

        if usesUITabDisplayedViewControllersOverflowPath() {
            #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == true)
            #expect(transientViewController(in: context.controller) == nil)
            #expect(overrideBeforeDismiss?.contains { containsViewController($0, descendant: overflowViewController) } == true)
        } else {
            #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == false)
            #expect(selectedViewControllerInTabBar(in: context.controller) === context.controller.moreNavigationController)
            #expect(transientViewController(in: context.controller) == nil)
            #expect(overrideBeforeDismiss == nil)
        }

        _ = context.controller.selectTabContent(visibleTab)

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
        #expect(displayedViewControllers(in: overflowTab).map(ObjectIdentifier.init) == originalOverflowDisplayedIdentifiers)
        #expect(displayedViewControllers(in: moreTab).map(ObjectIdentifier.init) == originalMoreDisplayedIdentifiers)
    }
}

@Test("UITab overflow cleanup restores app navigation pop gestures")
@MainActor
func uitabOverflowCleanupRestoresAppNavigationPopGestures() async {
    let navigationController = makeNavigationContentViewController(
        title: "Recorded Navigation",
        itemTitle: "Recorded Navigation",
        tag: 0
    )
    let detailViewController = navigationController.viewControllers.last
    let initialInteractivePopEnabled = navigationController.interactivePopGestureRecognizer?.isEnabled

    #expect(detailViewController != nil)
    #expect(initialInteractivePopEnabled != nil)

    if let detailViewController, let initialInteractivePopEnabled {
        let firstPass = tabBarMenuRecordDisabledInteractivePopGestures(
            for: [detailViewController],
            excluding: nil
        )

        #expect(firstPass.count == 1)
        #expect(firstPass.first?.wasEnabled == initialInteractivePopEnabled)
        #expect(navigationController.interactivePopGestureRecognizer?.isEnabled == false)

        let secondPass = tabBarMenuRecordDisabledInteractivePopGestures(
            for: [detailViewController],
            excluding: nil,
            preserving: firstPass
        )

        #expect(secondPass.count == 1)
        #expect(secondPass.first?.wasEnabled == initialInteractivePopEnabled)

        tabBarMenuRestoreInteractivePopGestures(from: secondPass)

        #expect(navigationController.interactivePopGestureRecognizer?.isEnabled == initialInteractivePopEnabled)
    }
}

@Test("More default control selection clears active UITab overflow state")
@MainActor
func moreDefaultControlSelectionClearsActiveUITabOverflowState() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let selectionDelegate = MoreTabSelectionDelegate()

    context.controller.menuDelegate = selectionDelegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let overflowTab = context.tabs[5]
    let overflowViewController = overflowTab.resolvedMoreSelectionViewController
    let moreTab = resolvedMoreTab(in: context.controller)
    let moreControl = moreTabBarControl(in: context.controller)

    #expect(overflowViewController != nil)
    #expect(moreTab != nil)
    #expect(moreControl != nil)

    if let overflowViewController, let moreTab, let moreControl {
        let originalOverflowDisplayedIdentifiers = displayedViewControllers(in: overflowTab).map(ObjectIdentifier.init)
        let originalMoreDisplayedIdentifiers = displayedViewControllers(in: moreTab).map(ObjectIdentifier.init)

        #expect(requestMoreMenu(in: context.controller, delegate: selectionDelegate) != nil)
        selectionDelegate.performSelection(titled: overflowTab.title)
        await drainMainQueue()

        if usesUITabDisplayedViewControllersOverflowPath() {
            #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == true)
            #expect(context.controller.tabBarMenuDisplayedViewControllersOverride(
                for: overflowTab,
                proposedViewControllers: []
            )?.contains { containsViewController($0, descendant: overflowViewController) } == true)
        } else {
            #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == false)
            #expect(context.controller.tabBarMenuDisplayedViewControllersOverride(
                for: overflowTab,
                proposedViewControllers: []
            ) == nil)
            #expect(selectedViewControllerInTabBar(in: context.controller) === context.controller.moreNavigationController)
            #expect(transientViewController(in: context.controller) == nil)
        }

        let fallbackDelegate = MoreTabMenuDelegate(menu: nil)
        context.controller.menuDelegate = fallbackDelegate

        let controlHandler = context.controller.tabBar.tabBarMenuControlSelectionHandler

        #expect(controlHandler != nil)

        if let controlHandler {
            context.controller.tabBar.tabBarMenuControlSelectionDidHandle = false
            let shouldCallDefault = controlHandler(context.controller.tabBar, moreControl)
            #expect(shouldCallDefault == true)
            #expect(context.controller.tabBar.tabBarMenuControlSelectionDidHandle == true)
        }

        #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == false)
        #expect(context.controller.tabBarMenuDisplayedViewControllersOverride(
            for: overflowTab,
            proposedViewControllers: []
        ) == nil)
        #expect(context.controller.tabBarMenuDisplayedViewControllersOverride(
            for: moreTab,
            proposedViewControllers: []
        ) == nil)
        #expect(navigationStack(of: context.controller.moreNavigationController).count == 1)
        #expect(navigationStack(of: context.controller.moreNavigationController).first === moreListController(in: context.controller.moreNavigationController))
        #expect(displayedViewControllers(in: overflowTab).map(ObjectIdentifier.init) == originalOverflowDisplayedIdentifiers)
        #expect(displayedViewControllers(in: moreTab).map(ObjectIdentifier.init) == originalMoreDisplayedIdentifiers)
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
        #expect(requestMoreMenu(in: context.controller, delegate: delegate) != nil)
        #expect(delegate.requestedTabs.count == requestedCountBeforeFirstTap + 1)
        delegate.performSelection(titled: targetTab.title)
        await drainMainQueue()
        context.host.window.layoutIfNeeded()

        let requestedCountBeforeSecondTap = delegate.requestedTabs.count
        #expect(requestMoreMenu(in: context.controller, delegate: delegate) != nil)
        #expect(delegate.requestedTabs.count == requestedCountBeforeSecondTap + 1)
        delegate.performSelection(titled: targetTab.title)
        await drainMainQueue()
        context.host.window.layoutIfNeeded()

        #expect(visibleContentTitles(in: context.controller) == [targetViewController.title].compactMap { $0 })
        #expect(title(of: selectedTabBarItem(in: context.controller)) == title(of: originalMoreItem))
        #expect(tabBarButtonTitles(in: context.controller).last == title(of: originalMoreItem))
        if usesUITabDisplayedViewControllersOverflowPath() {
            #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == true)
            #expect(navigationStack(of: context.controller.moreNavigationController).count == 2)
            #expect(navigationStack(of: context.controller.moreNavigationController).first === moreListController(in: context.controller.moreNavigationController))
            #expect(navigationStack(of: context.controller.moreNavigationController).last.map { containsViewController($0, descendant: targetViewController) } == true)
            #expect(displayedViewController(in: context.controller.moreNavigationController) === targetViewController)
            #expect(context.controller.moreNavigationController.interactivePopGestureRecognizer?.isEnabled == false)
            #expect(context.controller.tabBarMenuDisplayedViewControllersOverride(
                for: targetTab,
                proposedViewControllers: []
            )?.contains { containsViewController($0, descendant: targetViewController) } == true)
        } else {
            #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == false)
            #expect(navigationStack(of: context.controller.moreNavigationController).isEmpty == false)
            #expect(navigationStack(of: context.controller.moreNavigationController).last.map { containsViewController($0, descendant: targetViewController) } == true)
            #expect(displayedViewController(in: context.controller.moreNavigationController) === targetViewController)
            #expect(selectedViewControllerInTabBar(in: context.controller) === context.controller.moreNavigationController)
            #expect(transientViewController(in: context.controller) == nil)
            #expect(context.controller.tabBarMenuDisplayedViewControllersOverride(
                for: targetTab,
                proposedViewControllers: []
            ) == nil)
        }
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
        #expect(requestMoreMenu(in: context.controller, delegate: delegate) != nil)
        #expect(delegate.requestedTabs.count == requestedCountBeforeFirstTap + 1)
        delegate.performSelection(titled: firstTab.title)
        await drainMainQueue()
        context.host.window.layoutIfNeeded()

        let requestedCountBeforeSecondTap = delegate.requestedTabs.count
        #expect(requestMoreMenu(in: context.controller, delegate: delegate) != nil)
        #expect(delegate.requestedTabs.count == requestedCountBeforeSecondTap + 1)
        delegate.performSelection(titled: secondTab.title)
        await drainMainQueue()
        context.host.window.layoutIfNeeded()

        #expect(visibleContentTitles(in: context.controller) == [secondViewController.title].compactMap { $0 })
        #expect(title(of: selectedTabBarItem(in: context.controller)) == title(of: originalMoreItem))
        #expect(tabBarButtonTitles(in: context.controller).last == title(of: originalMoreItem))
        if usesUITabDisplayedViewControllersOverflowPath() {
            #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == true)
            #expect(navigationStack(of: context.controller.moreNavigationController).count == 2)
            #expect(navigationStack(of: context.controller.moreNavigationController).first === moreListController(in: context.controller.moreNavigationController))
            #expect(navigationStack(of: context.controller.moreNavigationController).last.map { containsViewController($0, descendant: secondViewController) } == true)
            #expect(navigationStack(of: context.controller.moreNavigationController).last.map { containsViewController($0, descendant: firstViewController) } == false)
            #expect(displayedViewController(in: context.controller.moreNavigationController) === secondViewController)
            #expect(context.controller.moreNavigationController.interactivePopGestureRecognizer?.isEnabled == false)
            #expect(context.controller.tabBarMenuDisplayedViewControllersOverride(
                for: secondTab,
                proposedViewControllers: []
            )?.contains { containsViewController($0, descendant: secondViewController) } == true)
        } else {
            #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == false)
            #expect(navigationStack(of: context.controller.moreNavigationController).isEmpty == false)
            #expect(navigationStack(of: context.controller.moreNavigationController).last.map { containsViewController($0, descendant: secondViewController) } == true)
            #expect(navigationStack(of: context.controller.moreNavigationController).last.map { containsViewController($0, descendant: firstViewController) } == false)
            #expect(displayedViewController(in: context.controller.moreNavigationController) === secondViewController)
            #expect(selectedViewControllerInTabBar(in: context.controller) === context.controller.moreNavigationController)
            #expect(transientViewController(in: context.controller) == nil)
            #expect(context.controller.tabBarMenuDisplayedViewControllersOverride(
                for: secondTab,
                proposedViewControllers: []
            ) == nil)
        }
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

    if let visibleItem, let handler {
        #expect(requestMoreMenu(in: context.controller, delegate: delegate) != nil)
        delegate.performSelection(titled: overflowTab.title)
        await drainMainQueue()

        if usesUITabDisplayedViewControllersOverflowPath() {
            #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == true)
        } else {
            #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == false)
            #expect(selectedViewControllerInTabBar(in: context.controller) === context.controller.moreNavigationController)
            #expect(transientViewController(in: context.controller) == nil)
        }

        let shouldCallDefaultForVisibleItem = handler(context.controller.tabBar, visibleItem)
        #expect(shouldCallDefaultForVisibleItem == true)
        if usesUITabDisplayedViewControllersOverflowPath() {
            #expect(context.controller.tabBarMenuHasActiveUITabMoreSelection == true)
        } else {
            #expect(transientViewController(in: context.controller) == nil)
        }
    }
}

@Test("active UITab overflow keeps the More control resolvable")
@MainActor
func activeUITabOverflowKeepsMoreControlResolvable() async {
    let context = makeTabBarTestContext(tabCount: 7)
    let delegate = MoreTabSelectionDelegate()

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let overflowTab = context.tabs[5]
    let controlHandler = context.controller.tabBar.tabBarMenuControlSelectionHandler
    let moreControl = moreTabBarControl(in: context.controller)
    let firstControl = firstVisibleTabControl(in: context.controller)

    #expect(controlHandler != nil)
    #expect(moreControl != nil)
    #expect(firstControl != nil)

    if let controlHandler, let moreControl, let firstControl {
        #expect(requestMoreMenu(in: context.controller, delegate: delegate) != nil)
        delegate.performSelection(titled: overflowTab.title)
        await drainMainQueue()

        #expect(controlHandler(context.controller.tabBar, firstControl) == true)
        #expect(moreTabBarControl(in: context.controller) === moreControl)
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
    #expect(transientViewController(in: context.controller) === overflowViewController)

    _ = context.controller.selectTabContent(visibleViewController)

    #expect(transientViewController(in: context.controller) == nil)
    #expect(selectedViewControllerInTabBar(in: context.controller) === visibleViewController)
    #expect(navigationStack(of: context.controller.moreNavigationController).count == 1)
    #expect(navigationStack(of: context.controller.moreNavigationController).first === moreListController(in: context.controller.moreNavigationController))
    #expect(displayedViewController(in: context.controller.moreNavigationController) === context.controller.moreNavigationController)
}
