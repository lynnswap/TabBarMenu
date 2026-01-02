import UIKit

@MainActor
enum MoreSelection {
    case item(UITabBarItem)
    case tab(UITab)
    case viewController(UIViewController)
}

@MainActor
enum ItemMenuTarget {
    case tab(UITab)
    case viewController(UIViewController)
}

@MainActor
struct ItemMenuResolution {
    let menu: UIMenu
    let target: ItemMenuTarget
}

@MainActor
struct PresentationContext {
    let containerView: UIView
    let tabFrame: CGRect
}

@MainActor
struct MenuPlan {
    let menu: UIMenu
    let placement: TabBarMenuAnchorPlacement?
    let hostButton: UIButton
}

@MainActor
struct TabBarMenuRequestCore {
    let configuration: TabBarMenuConfiguration

    init(configuration: TabBarMenuConfiguration) {
        self.configuration = configuration
    }

    func moreTabStartIndex(totalCount: Int) -> Int? {
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

    func itemForMenu<T>(at index: Int, in items: [T]) -> T? {
        guard !items.isEmpty else {
            return nil
        }
        guard items.indices.contains(index), isMoreTabIndex(index, totalCount: items.count) == false else {
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
        core.moreItems(from: items(in: tabBarController))
    }

    func itemForMenu(at index: Int, in tabBarController: UITabBarController) -> Item? {
        core.itemForMenu(at: index, in: items(in: tabBarController))
    }

    func matchesItem(_ item: UITabBarItem, in tabBarController: UITabBarController) -> Bool {
        guard let items = tabBarController.tabBar.items,
              let index = items.firstIndex(where: { $0 === item }) else {
            return false
        }
        return core.isMoreTabIndex(index, totalCount: totalCount(in: tabBarController))
    }
}

@MainActor
struct TabBarMenuTabRequestContext: TabBarMenuRequestContext {
    let core: TabBarMenuRequestCore

    func items(in tabBarController: UITabBarController) -> [UITab] {
        tabBarController.tabs
    }

    fileprivate func isMoreTab(_ tab: UITab, in tabBarController: UITabBarController) -> Bool {
        let tabs = tabBarController.tabs
        guard let moreIndex = core.moreTabStartIndex(totalCount: tabs.count) else {
            return false
        }
        if let index = tabs.firstIndex(where: { $0 === tab }) {
            return index == moreIndex
        }
        // If we can't find it, be conservative and treat it as the More tab.
        return true
    }
}

@MainActor
struct TabBarMenuViewControllerRequestContext: TabBarMenuRequestContext {
    let core: TabBarMenuRequestCore

    func items(in tabBarController: UITabBarController) -> [UIViewController] {
        tabBarController.viewControllers ?? []
    }

    fileprivate func isMoreViewController(
        _ viewController: UIViewController,
        in tabBarController: UITabBarController
    ) -> Bool {
        let moreNavigationController = tabBarController.moreNavigationController
        if viewController === moreNavigationController {
            return true
        }
        if viewController.tabBarItem === moreNavigationController.tabBarItem {
            return true
        }
        let totalCount = items(in: tabBarController).count
        guard let moreIndex = core.moreTabStartIndex(totalCount: totalCount),
              let items = tabBarController.tabBar.items,
              items.indices.contains(moreIndex) else {
            return false
        }
        return viewController.tabBarItem === items[moreIndex]
    }
}

@MainActor
enum MoreMenuRequest {
    case tabs(TabBarMenuTabRequestContext)
    case viewControllers(TabBarMenuViewControllerRequestContext)

    func totalCount(in tabBarController: UITabBarController) -> Int {
        switch self {
        case .tabs(let context):
            return context.totalCount(in: tabBarController)
        case .viewControllers(let context):
            return context.totalCount(in: tabBarController)
        }
    }

    func moreTabStartIndex(in tabBarController: UITabBarController) -> Int? {
        switch self {
        case .tabs(let context):
            return context.core.moreTabStartIndex(totalCount: context.totalCount(in: tabBarController))
        case .viewControllers(let context):
            return context.core.moreTabStartIndex(totalCount: context.totalCount(in: tabBarController))
        }
    }

    func menu(in tabBarController: UITabBarController, delegate: TabBarMenuMenuDelegate) -> UIMenu? {
        switch self {
        case .tabs(let context):
            let items = context.moreItems(in: tabBarController)
            guard !items.isEmpty else {
                return nil
            }
            return delegate.tabBarController?(tabBarController, menuForMoreTabWith: items)
        case .viewControllers(let context):
            let items = context.moreItems(in: tabBarController)
            guard !items.isEmpty else {
                return nil
            }
            return delegate.tabBarController?(tabBarController, menuForMoreTabWith: items)
        }
    }

    func matches(_ selection: MoreSelection, in tabBarController: UITabBarController) -> Bool {
        switch self {
        case .tabs(let context):
            switch selection {
            case .item(let item):
                return context.matchesItem(item, in: tabBarController)
            case .tab(let tab):
                return context.isMoreTab(tab, in: tabBarController)
            case .viewController:
                return false
            }
        case .viewControllers(let context):
            switch selection {
            case .item(let item):
                return context.matchesItem(item, in: tabBarController)
            case .tab:
                return false
            case .viewController(let viewController):
                return context.isMoreViewController(viewController, in: tabBarController)
            }
        }
    }

    func isMoreTabIndex(_ index: Int, in tabBarController: UITabBarController) -> Bool {
        switch self {
        case .tabs(let context):
            return context.core.isMoreTabIndex(index, totalCount: context.totalCount(in: tabBarController))
        case .viewControllers(let context):
            return context.core.isMoreTabIndex(index, totalCount: context.totalCount(in: tabBarController))
        }
    }
}

extension MoreMenuRequest {
    static func make(delegate: TabBarMenuMenuDelegate?, core: TabBarMenuRequestCore) -> MoreMenuRequest? {
        guard let delegate else {
            return nil
        }

        let tabsMethod: ((UITabBarController, [UITab]) -> UIMenu?)? = delegate.tabBarController
        if tabsMethod != nil {
            return .tabs(TabBarMenuTabRequestContext(core: core))
        }

        let viewControllersMethod: ((UITabBarController, [UIViewController]) -> UIMenu?)? = delegate.tabBarController
        if viewControllersMethod != nil {
            return .viewControllers(TabBarMenuViewControllerRequestContext(core: core))
        }

        return nil
    }
}

@MainActor
enum ItemMenuRequest {
    case tabs(TabBarMenuTabRequestContext)
    case viewControllers(TabBarMenuViewControllerRequestContext)

    func resolveMenu(
        for tabIndex: Int,
        in tabBarController: UITabBarController,
        delegate: TabBarMenuDelegate
    ) -> ItemMenuResolution? {
        switch self {
        case .tabs(let requestContext):
            guard let tab = requestContext.itemForMenu(at: tabIndex, in: tabBarController),
                  let menu = delegate.tabBarController?(tabBarController, tab: tab) else {
                return nil
            }
            return ItemMenuResolution(menu: menu, target: .tab(tab))
        case .viewControllers(let requestContext):
            guard let viewController = requestContext.itemForMenu(at: tabIndex, in: tabBarController),
                  let menu = delegate.tabBarController?(tabBarController, viewController: viewController) else {
                return nil
            }
            return ItemMenuResolution(menu: menu, target: .viewController(viewController))
        }
    }
}

extension ItemMenuTarget {
    func placement(
        in tabBarController: UITabBarController,
        context: PresentationContext,
        hostButton: UIButton,
        delegate: TabBarMenuPresentationDelegate
    ) -> TabBarMenuAnchorPlacement? {
        switch self {
        case .tab(let tab):
            return delegate.tabBarController(
                tabBarController,
                configureMenuPresentationFor: tab,
                tabFrame: context.tabFrame,
                in: context.containerView,
                menuHostButton: hostButton
            )
        case .viewController(let viewController):
            return delegate.tabBarController(
                tabBarController,
                configureMenuPresentationFor: viewController,
                tabFrame: context.tabFrame,
                in: context.containerView,
                menuHostButton: hostButton
            )
        }
    }
}

extension ItemMenuRequest {
    static func make(delegate: TabBarMenuDelegate?, core: TabBarMenuRequestCore) -> ItemMenuRequest? {
        guard let delegate else {
            return nil
        }

        let tabsMethod: ((UITabBarController, UITab?) -> UIMenu?)? = delegate.tabBarController
        if tabsMethod != nil {
            return .tabs(TabBarMenuTabRequestContext(core: core))
        }

        let viewControllersMethod: ((UITabBarController, UIViewController?) -> UIMenu?)? = delegate.tabBarController
        if viewControllersMethod != nil {
            return .viewControllers(TabBarMenuViewControllerRequestContext(core: core))
        }

        return nil
    }
}
