import Testing
import UIKit
@testable import TabBarMenu

@Test("More preparation receives the current overflow tabs")
@MainActor
func morePreparationReceivesOverflowTabs() {
    let controller = UITabBarController()
    #expect(setMaximumNumberOfItems(4, in: controller))
    controller.tabs = makeTabs(count: 6)
    let host = WindowHost(rootViewController: controller)
    defer { withExtendedLifetime(host) {} }
    guard case .more(let tabs, let selected) = controller.tabBarMenuItem(at: 3) else {
        Issue.record("Expected the More item")
        return
    }
    #expect(tabs.map(\.identifier) == ["tab.3", "tab.4", "tab.5"])
    #expect(selected == nil)
}

@Test("Item resolution follows the controller's content API")
@MainActor
func itemResolutionFollowsContentAPI() {
    let tabs = makeTabBarTestContext(tabCount: 6)
    let controllers = makeViewControllerTabBarTestContext(viewControllerCount: 6)
    defer { withExtendedLifetime((tabs, controllers)) {} }
    guard case .tab(let tab) = tabs.controller.tabBarMenuItem(at: 1),
          case .viewController(let controller) = controllers.controller.tabBarMenuItem(at: 1),
          case .moreViewControllers(let more, let selected) = controllers.controller.tabBarMenuItem(at: 4) else {
        Issue.record("Expected UITab and classic view-controller item cases")
        return
    }
    #expect(tab === tabs.tabs[1])
    #expect(controller === controllers.viewControllers[1])
    #expect(more.map(ObjectIdentifier.init) == controllers.viewControllers.suffix(2).map(ObjectIdentifier.init))
    #expect(selected == nil)
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
