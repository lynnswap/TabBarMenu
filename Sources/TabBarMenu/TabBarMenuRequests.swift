import UIKit

@MainActor
struct PresentationContext {
    let containerView: UIView
    let tabFrame: CGRect
}

@MainActor
struct TabBarMenuRequestCore {
    let configuration: TabBarMenuConfiguration

    init(configuration: TabBarMenuConfiguration) {
        self.configuration = configuration
    }

    func moreTabStartIndex(totalCount: Int) -> Int? {
        fallbackMoreTabStartIndex(totalCount: totalCount)
    }

    func moreTabStartIndex(totalCount: Int, in tabBarController: UITabBarController) -> Int? {
        if let actualMoreTabIndex = tabBarController.actualMoreTabIndexInTabElements,
           actualMoreTabIndex < totalCount {
            return actualMoreTabIndex
        }

        if let effectiveMaxItems = tabBarController.effectiveMaxTabBarItemCount,
           effectiveMaxItems > 0 {
            guard totalCount > effectiveMaxItems else {
                return nil
            }
            return effectiveMaxItems - 1
        }

        return fallbackMoreTabStartIndex(totalCount: totalCount)
    }

    private func fallbackMoreTabStartIndex(totalCount: Int) -> Int? {
        let maxVisibleCount = max(configuration.maxVisibleTabCount, 0)
        guard maxVisibleCount > 0, totalCount > maxVisibleCount else {
            return nil
        }
        return maxVisibleCount - 1
    }

    func isMoreTabIndex(_ index: Int, totalCount: Int) -> Bool {
        guard let startIndex = moreTabStartIndex(totalCount: totalCount) else {
            return false
        }
        return index == startIndex
    }

    func isMoreTabIndex(_ index: Int, totalCount: Int, in tabBarController: UITabBarController) -> Bool {
        guard let startIndex = moreTabStartIndex(totalCount: totalCount, in: tabBarController) else {
            return false
        }
        return index == startIndex
    }

    func itemForMenu<T>(at index: Int, in items: [T]) -> T? {
        guard !items.isEmpty else {
            return nil
        }
        guard items.indices.contains(index), isMoreTabIndex(index, totalCount: items.count) == false else {
            return nil
        }
        return items[index]
    }

    func itemForMenu<T>(at index: Int, in items: [T], tabBarController: UITabBarController) -> T? {
        guard !items.isEmpty else {
            return nil
        }
        guard items.indices.contains(index),
              isMoreTabIndex(index, totalCount: items.count, in: tabBarController) == false else {
            return nil
        }
        return items[index]
    }

    func moreItems<T>(from items: [T]) -> [T] {
        guard let startIndex = moreTabStartIndex(totalCount: items.count),
              items.indices.contains(startIndex) else {
            return []
        }
        return Array(items[startIndex...])
    }

    func moreItems<T>(from items: [T], tabBarController: UITabBarController) -> [T] {
        guard let startIndex = moreTabStartIndex(totalCount: items.count, in: tabBarController),
              items.indices.contains(startIndex) else {
            return []
        }
        return Array(items[startIndex...])
    }
}

@MainActor
private extension UITabBarController {
    var effectiveMaxTabBarItemCount: Int? {
        guard let value = ObjectiveCInterop.performUnsignedIntegerSelector(
            UITabBarControllerRuntimeMethodNames.effectiveMaxItems,
            on: self
        ), value <= UInt(Int.max) else {
            return nil
        }
        return Int(value)
    }

    var actualMoreTabIndexInTabElements: Int? {
        guard let elements = ObjectiveCInterop.performObjectSelector(
            UITabBarControllerRuntimeMethodNames.tabElements,
            on: self
        ) as? [NSObject] else {
            return nil
        }

        guard let index = elements.firstIndex(where: { element in
            ObjectiveCInterop.performBoolSelector(
                UITabRuntimeMethodNames.isMoreTab,
                on: element
            ) ?? false
        }) else {
            return nil
        }

        guard tabBar.items?.indices.contains(index) == true else {
            return nil
        }
        return index
    }
}

@MainActor
protocol TabBarMenuRequestContext {
    associatedtype Item

    var core: TabBarMenuRequestCore { get }
    func items(in tabBarController: UITabBarController) -> [Item]
}

extension TabBarMenuRequestContext {
    func totalCount(in tabBarController: UITabBarController) -> Int {
        items(in: tabBarController).count
    }

    func moreItems(in tabBarController: UITabBarController) -> [Item] {
        core.moreItems(from: items(in: tabBarController), tabBarController: tabBarController)
    }

    func itemForMenu(at index: Int, in tabBarController: UITabBarController) -> Item? {
        core.itemForMenu(at: index, in: items(in: tabBarController), tabBarController: tabBarController)
    }

    func matchesItem(_ item: UITabBarItem, in tabBarController: UITabBarController) -> Bool {
        guard let items = tabBarController.tabBar.items,
              let index = items.firstIndex(where: { $0 === item }) else {
            return false
        }
        return core.isMoreTabIndex(index, totalCount: totalCount(in: tabBarController), in: tabBarController)
    }
}

@MainActor
struct TabBarMenuTabRequestContext: TabBarMenuRequestContext {
    let core: TabBarMenuRequestCore

    func items(in tabBarController: UITabBarController) -> [UITab] {
        identityUniqued(tabBarController.tabs)
    }
}

@MainActor
struct TabBarMenuViewControllerRequestContext: TabBarMenuRequestContext {
    let core: TabBarMenuRequestCore

    func items(in tabBarController: UITabBarController) -> [UIViewController] {
        identityUniqued(tabBarController.viewControllers ?? [])
    }

    func moreMenuItems(in tabBarController: UITabBarController) -> [UIViewController] {
        if let moreViewControllers = ObjectiveCInterop.performObjectSelector(
            UIMoreNavigationControllerRuntimeMethodNames.moreViewControllers,
            on: tabBarController.moreNavigationController
        ) as? [UIViewController], !moreViewControllers.isEmpty {
            return identityUniqued(moreViewControllers)
        }
        return core.moreItems(from: items(in: tabBarController), tabBarController: tabBarController)
    }
}

@MainActor
private func identityUniqued<Object: AnyObject>(_ objects: [Object]) -> [Object] {
    var seen: Set<ObjectIdentifier> = []
    return objects.filter { object in
        seen.insert(ObjectIdentifier(object)).inserted
    }
}

/// A real content selection, separate from the synthetic More item.
@MainActor
enum TabBarContent: @MainActor Equatable {
    case tab(UITab)
    case viewController(UIViewController)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.tab(let lhs), .tab(let rhs)): lhs === rhs
        case (.viewController(let lhs), .viewController(let rhs)): lhs === rhs
        default: false
        }
    }
}

extension TabBarItem {
    var content: TabBarContent? {
        switch self {
        case .tab(let tab): .tab(tab)
        case .more(_, let tab): tab.map(TabBarContent.tab)
        case .viewController(let controller): .viewController(controller)
        case .moreViewControllers(_, let controller): controller.map(TabBarContent.viewController)
        }
    }

    var isMore: Bool {
        switch self {
        case .more, .moreViewControllers: true
        case .tab, .viewController: false
        }
    }
}

extension UITabBarController {
    func tabBarMenuItem(at index: Int) -> TabBarItem? {
        let core = TabBarMenuRequestCore(configuration: menuConfiguration)
        if !tabs.isEmpty {
            let context = TabBarMenuTabRequestContext(core: core)
            if core.isMoreTabIndex(index, totalCount: tabs.count, in: self) {
                let moreTabs = context.moreItems(in: self)
                let selected = tabBarMenuSelectedTab.flatMap { selected in
                    moreTabs.contains { $0 === selected } ? selected : nil
                }
                return .more(tabs: moreTabs, selectedTab: selected)
            }
            return context.itemForMenu(at: index, in: self).map(TabBarItem.tab)
        }
        let context = TabBarMenuViewControllerRequestContext(core: core)
        if core.isMoreTabIndex(index, totalCount: context.totalCount(in: self), in: self) {
            let controllers = context.moreMenuItems(in: self)
            let selected = tabBarMenuSelectedViewController.flatMap { selected in
                controllers.contains { $0 === selected } ? selected : nil
            }
            return .moreViewControllers(viewControllers: controllers, selectedViewController: selected)
        }
        return context.itemForMenu(at: index, in: self).map(TabBarItem.viewController)
    }

    var tabBarMenuSelectedContent: TabBarContent? {
        if !tabs.isEmpty {
            return tabBarMenuSelectedTab.map(TabBarContent.tab)
        }
        return tabBarMenuSelectedViewController.map(TabBarContent.viewController)
    }

    func tabBarMenuOwns(_ content: TabBarContent) -> Bool {
        switch content {
        case .tab(let tab): tabs.contains { $0 === tab }
        case .viewController(let controller): viewControllers?.contains { $0 === controller } == true
        }
    }

    func tabBarMenuIsOverflow(_ content: TabBarContent) -> Bool {
        let index: Int?
        let count: Int
        switch content {
        case .tab(let tab):
            index = tabs.firstIndex { $0 === tab }
            count = tabs.count
        case .viewController(let controller):
            index = viewControllers?.firstIndex { $0 === controller }
            count = viewControllers?.count ?? 0
        }
        guard let index,
              let start = TabBarMenuRequestCore(configuration: menuConfiguration)
                .moreTabStartIndex(totalCount: count, in: self) else { return false }
        return index >= start
    }
}
