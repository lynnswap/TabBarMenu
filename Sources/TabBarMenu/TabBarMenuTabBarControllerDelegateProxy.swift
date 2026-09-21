import UIKit

final class TabBarMenuTabBarControllerDelegateProxy: NSObject, UITabBarControllerDelegate {
    weak var coordinator: TabBarMenuCoordinator?
    nonisolated(unsafe) weak var forwardedTabBarController: UITabBarController?
    weak var tabBarController: UITabBarController? {
        didSet {
            unsafe forwardedTabBarController = tabBarController
        }
    }
    // Objective-C selector introspection reaches these NSObject overrides outside Swift actor isolation.
    nonisolated(unsafe) weak var forwardedDelegate: NSObject?
    weak var originalDelegate: (NSObject & UITabBarControllerDelegate)? {
        didSet {
            unsafe forwardedDelegate = originalDelegate
        }
    }

    override func responds(to aSelector: Selector!) -> Bool {
        guard let aSelector else {
            return false
        }
        let superResponds = super.responds(to: aSelector)
        let delegate = unsafe forwardedDelegate
        let delegateResponds = delegate?.responds(to: aSelector) ?? false
        if aSelector == UITabBarControllerDelegateRuntimeMethods.displayedViewControllersForTab {
            let controller = unsafe forwardedTabBarController
            let hasActiveMoreSelection = controller?.tabBarMenuHasActiveUITabMoreSelection ?? false
            return hasActiveMoreSelection || delegateResponds || superResponds
        }
        return superResponds || delegateResponds
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        guard let aSelector else {
            return super.forwardingTarget(for: aSelector)
        }
        if aSelector == UITabBarControllerDelegateRuntimeMethods.displayedViewControllersForTab {
            return nil
        }
        let delegate = unsafe forwardedDelegate
        if let delegate, delegate.responds(to: aSelector) {
            return delegate
        }
        return super.forwardingTarget(for: aSelector)
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        displayedViewControllersFor tab: UITab,
        proposedViewControllers: [UIViewController]
    ) -> [UIViewController] {
        if let override = tabBarController.tabBarMenuDisplayedViewControllersOverride(
            for: tab,
            proposedViewControllers: proposedViewControllers
        ) {
            return override
        }

        if let originalDelegate,
           let originalResult = ObjectiveCInterop.performObjectSelector(
               UITabBarControllerDelegateRuntimeMethodNames.displayedViewControllersForTab,
               on: originalDelegate,
               with: tabBarController,
               with: tab,
               with: proposedViewControllers as NSArray
           ) as? [UIViewController] {
            return originalResult
        }

        return proposedViewControllers
    }

    func allowsSelection(of content: TabBarContent, in controller: UITabBarController) -> Bool {
        guard let originalDelegate else { return true }
        switch content {
        case .tab(let tab):
            if let allowed = originalDelegate.tabBarController?(controller, shouldSelectTab: tab) {
                return allowed
            }
            let permission: ((UITabBarController, UIViewController) -> Bool)? = originalDelegate.tabBarController
            guard let permission, let viewController = tab.resolvedMoreSelectionViewController else { return true }
            return permission(controller, viewController)
        case .viewController(let viewController):
            return originalDelegate.tabBarController?(controller, shouldSelect: viewController) ?? true
        }
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        if coordinator?.isSelectingProgrammatically == true { return true }
        coordinator?.willSelectNativeContent(.tab(tab))
        let allowed = allowsSelection(of: .tab(tab), in: tabBarController)
        if !allowed { coordinator?.cancelNativeSelection() }
        return allowed
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if coordinator?.isSelectingProgrammatically == true { return true }
        if tabBarController.tabs.isEmpty {
            coordinator?.willSelectNativeContent(.viewController(viewController))
        }
        let allowed = allowsSelection(of: .viewController(viewController), in: tabBarController)
        if !allowed { coordinator?.cancelNativeSelection() }
        return allowed
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelectTab tab: UITab,
        previousTab: UITab?
    ) {
        let recipient = originalDelegate
        tabBarController.tabBarMenuDidSelectTab(tab, previousTab: previousTab)
        coordinator?.didSelectNativeContent(.tab(tab))
        recipient?.tabBarController?(tabBarController, didSelectTab: tab, previousTab: previousTab)
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect viewController: UIViewController
    ) {
        let recipient = originalDelegate
        tabBarController.tabBarMenuDidSelectViewController(viewController)
        if tabBarController.tabs.isEmpty {
            coordinator?.didSelectNativeContent(.viewController(viewController))
        }
        recipient?.tabBarController?(tabBarController, didSelect: viewController)
    }
}
