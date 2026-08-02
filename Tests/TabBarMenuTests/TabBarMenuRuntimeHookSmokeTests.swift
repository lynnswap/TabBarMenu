import Testing
import UIKit
@testable import TabBarMenu

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

@Test("transient overflow animated selector matches Objective-C signature")
func transientOverflowAnimatedSelectorMatchesObjectiveCSignature() {
    #expect(
        UITabBarControllerRuntimeMethodNames.setTransientViewControllerAnimated
            == "setTransientViewController:animated:"
    )
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

@Test("buttonUp runtime hook survives KVO subclassing")
@MainActor
func buttonUpRuntimeHookSurvivesKVOAddedSubclass() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabMenuDelegate(menu: nil)
    context.controller.tabBar.tabBarMenuPreferredSelectionOverrideKind = .buttonUp

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    #expect(context.controller.tabBar.tabBarMenuInstalledSelectionOverrideKind == .buttonUp)
    let observation = context.controller.tabBar.observe(\.frame, options: [.new]) { _, _ in }
    let moreControl = moreTabBarControl(in: context.controller)
    #expect(moreControl != nil)

    defer { observation.invalidate() }

    if let moreControl {
        invokeRuntimeMethodNamed(
            UITabBarRuntimeMethodNames.buttonUp,
            on: context.controller.tabBar,
            argument: moreControl
        )
    }

    #expect(delegate.requestedTabsCount == 1)
}

@Test("available didSelect runtime hook survives KVO subclassing")
@MainActor
func didSelectRuntimeHookSurvivesKVOAddedSubclass() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = MoreTabMenuDelegate(menu: nil)
    context.controller.tabBar.tabBarMenuPreferredSelectionOverrideKind = .didSelectButtonForItem

    context.controller.menuDelegate = delegate
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()

    let installedKind = context.controller.tabBar.tabBarMenuInstalledSelectionOverrideKind
    guard installedKind == .didSelectButtonForItem else {
        #expect(installedKind == .none)
        return
    }

    let observation = context.controller.tabBar.observe(\.frame, options: [.new]) { _, _ in }
    let moreItem = moreTabBarItem(in: context.controller)
    #expect(moreItem != nil)

    defer { observation.invalidate() }

    if let moreItem {
        let methodName = ["Item:", "For", "Button", "Select", "did", "_"]
            .reversed()
            .joined()
        invokeRuntimeMethodNamed(
            methodName,
            on: context.controller.tabBar,
            argument: moreItem
        )
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
