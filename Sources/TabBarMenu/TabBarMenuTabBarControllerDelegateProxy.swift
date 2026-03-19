import UIKit

final class TabBarMenuTabBarControllerDelegateProxy: NSObject, UITabBarControllerDelegate {
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

    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelectTab tab: UITab,
        previousTab: UITab?
    ) {
        originalDelegate?.tabBarController?(tabBarController, didSelectTab: tab, previousTab: previousTab)
        tabBarController.tabBarMenuDidSelectTab(tab, previousTab: previousTab)
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect viewController: UIViewController
    ) {
        originalDelegate?.tabBarController?(tabBarController, didSelect: viewController)
        tabBarController.tabBarMenuDidSelectViewController(viewController)
    }
}
