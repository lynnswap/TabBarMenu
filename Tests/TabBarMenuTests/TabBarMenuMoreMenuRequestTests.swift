import Testing
import UIKit
@testable import TabBarMenu

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

@Test("more tab selection allows default when menu is absent")
@MainActor
func moreTabSelectionAllowsDefaultWhenMenuIsAbsent() async {
    let controller = UITabBarController(tabs: makeTabs(count: 6))
    let delegate = MoreTabMenuDelegate(menu: nil)

    controller.menuDelegate = delegate
    controller.loadViewIfNeeded()

    let menu = requestMoreMenu(in: controller, delegate: delegate)

    #expect(menu == nil)
    #expect(delegate.requestedTabsCount == 1)
}

@Test("more tab selection prefers tabs method when implemented")
@MainActor
func moreTabSelectionPrefersTabsMethodWhenImplemented() async {
    let controller = UITabBarController(tabs: makeTabs(count: 6))
    let delegate = DualMoreTabMenuDelegate(
        tabsMenu: nil,
        viewControllersMenu: UIMenu(children: [])
    )

    controller.menuDelegate = delegate
    controller.loadViewIfNeeded()

    let menu = requestMoreMenu(in: controller, delegate: delegate)

    #expect(menu == nil)
    #expect(delegate.requestedTabsCount == 1)
    #expect(delegate.requestedViewControllersCount == 0)
}

@Test("more tab request returns a menu when provided")
@MainActor
func moreTabRequestReturnsMenuWhenProvided() async {
    let controller = UITabBarController(tabs: makeTabs(count: 6))
    let delegate = MoreTabMenuDelegate(menu: UIMenu(children: []))

    controller.menuDelegate = delegate
    controller.loadViewIfNeeded()

    let request = makeMoreMenuRequest(in: controller, delegate: delegate)
    let moreItem = moreTabBarItem(in: controller)
    let menu = request?.menu(in: controller, delegate: delegate)

    #expect(request != nil)
    #expect(moreItem != nil)
    if let request, let moreItem {
        #expect(request.matches(item: moreItem, in: controller) == true)
    }
    #expect(menu != nil)
    #expect(delegate.requestedTabsCount == 1)
}

@Test("more tab selection configures menu presentation with nil")
@MainActor
func moreTabSelectionConfiguresMenuPresentationWithNil() async {
    let controller = UITabBarController(tabs: makeTabs(count: 6))
    let delegate = MoreTabPresentationDelegate(menu: UIMenu(children: []))

    controller.menuDelegate = delegate
    controller.loadViewIfNeeded()

    let request = makeMoreMenuRequest(in: controller, delegate: delegate)
    let hostButton = UIButton(type: .system)
    let presentationContext = PresentationContext(
        containerView: controller.view,
        tabFrame: CGRect(x: 0, y: 0, width: 44, height: 44)
    )
    if let request {
        _ = request.menuPresentationPlacement(
            in: controller,
            presentationContext: presentationContext,
            hostButton: hostButton,
            delegate: delegate
        )
    }

    #expect(request != nil)
    #expect(delegate.configuredTabs.count == 1)
    if let configuredTab = delegate.configuredTabs.first {
        #expect(configuredTab == nil)
    }
}

@Test("More tab selection follows UIKit effective maximum item count")
@MainActor
func moreTabSelectionUsesUIKitEffectiveMaximumItemCount() async {
    let tabs = makeTabs(count: 6)
    let controller = UITabBarController()
    #expect(setMaximumNumberOfItems(4, in: controller) == true)
    controller.tabs = tabs
    let delegate = MoreTabSelectionDelegate()

    controller.menuDelegate = delegate
    controller.updateMenuConfiguration { configuration in
        configuration.maxVisibleTabCount = 5
    }
    controller.loadViewIfNeeded()

    let request = makeMoreMenuRequest(in: controller, delegate: delegate)
    let moreItem = moreTabBarItem(in: controller)
    #expect(resolvedMoreTabIndex(in: controller) == 3)
    #expect(request != nil)
    #expect(moreItem != nil)
    if let request, let moreItem {
        #expect(request.matches(item: moreItem, in: controller) == true)
        #expect(request.menu(in: controller, delegate: delegate) != nil)
    }

    #expect(delegate.requestedTabs.last?.map(\.identifier) == ["tab.3", "tab.4", "tab.5"])
}

@Test("fallback More start index honors maxVisibleTabCount")
@MainActor
func fallbackMoreStartIndexHonorsMaxVisibleTabCount() {
    let core = TabBarMenuRequestCore(configuration: TabBarMenuConfiguration(maxVisibleTabCount: 5))
    let zeroCore = TabBarMenuRequestCore(configuration: TabBarMenuConfiguration(maxVisibleTabCount: 0))
    let negativeCore = TabBarMenuRequestCore(configuration: TabBarMenuConfiguration(maxVisibleTabCount: -1))

    #expect(core.moreTabStartIndex(totalCount: 5) == nil)
    #expect(core.moreTabStartIndex(totalCount: 6) == 4)
    #expect(zeroCore.moreTabStartIndex(totalCount: 6) == nil)
    #expect(negativeCore.moreTabStartIndex(totalCount: 6) == nil)
}

@Test("fallback item and More slices exclude the More tab entry")
@MainActor
func fallbackItemAndMoreSlicesExcludeMoreTabEntry() {
    let core = TabBarMenuRequestCore(configuration: TabBarMenuConfiguration(maxVisibleTabCount: 5))
    let items = Array(0..<6)

    #expect(core.itemForMenu(at: 3, in: items) == 3)
    #expect(core.itemForMenu(at: 4, in: items) == nil)
    #expect(core.itemForMenu(at: 6, in: items) == nil)
    #expect(core.moreItems(from: items) == [4, 5])
    #expect(core.moreItems(from: Array(0..<5)).isEmpty)
}

@Test("item menu request prefers UITab delegate method")
@MainActor
func itemMenuRequestPrefersUITabDelegateMethod() {
    let controller = UITabBarController(tabs: makeTabs(count: 3))
    let delegate = DualItemMenuDelegate()
    let request = ItemMenuRequest.make(
        delegate: delegate,
        core: TabBarMenuRequestCore(configuration: controller.menuConfiguration)
    )

    let menu = request?.menu(forItemAt: 1, in: controller, delegate: delegate)

    #expect(menu != nil)
    #expect(delegate.requestedTabIdentifiers == ["tab.1"])
    #expect(delegate.requestedViewControllerTitles.isEmpty)
}

@Test("item menu request falls back to view controller delegate method")
@MainActor
func itemMenuRequestFallsBackToViewControllerDelegateMethod() {
    let controller = UITabBarController()
    let viewControllers = makeViewControllers(count: 3)
    controller.setViewControllers(viewControllers, animated: false)
    let delegate = ViewControllerMenuDelegate()
    let request = ItemMenuRequest.make(
        delegate: delegate,
        core: TabBarMenuRequestCore(configuration: controller.menuConfiguration)
    )

    let menu = request?.menu(forItemAt: 2, in: controller, delegate: delegate)

    #expect(menu != nil)
    #expect(delegate.requestedTitles == ["View 2"])
}

@Test("item menu request skips the More tab index")
@MainActor
func itemMenuRequestSkipsMoreTabIndex() {
    let controller = UITabBarController(tabs: makeTabs(count: 6))
    controller.updateMenuConfiguration { configuration in
        configuration.maxVisibleTabCount = 5
    }
    let delegate = TestMenuDelegate()
    let request = ItemMenuRequest.make(
        delegate: delegate,
        core: TabBarMenuRequestCore(configuration: controller.menuConfiguration)
    )

    let menu = request?.menu(forItemAt: 4, in: controller, delegate: delegate)

    #expect(menu == nil)
    #expect(delegate.requestedIdentifiers.isEmpty)
}
