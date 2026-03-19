import UIKit

final class TabBarMenuTabBarControllerDelegateProxy: NSObject, UITabBarControllerDelegate {
    weak var tabBarController: UITabBarController?
    weak var originalDelegate: (NSObject & UITabBarControllerDelegate)?

    override func responds(to aSelector: Selector!) -> Bool {
        guard let aSelector else {
            return false
        }
        if aSelector == UITabBarControllerDelegateRuntimeMethods.displayedViewControllersForTab {
            return (tabBarController?.tabBarMenuHasActiveUITabMoreSelection ?? false)
                || (originalDelegate?.responds(to: aSelector) ?? false)
                || super.responds(to: aSelector)
        }
        return super.responds(to: aSelector) || (originalDelegate?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        guard let aSelector else {
            return super.forwardingTarget(for: aSelector)
        }
        if aSelector == UITabBarControllerDelegateRuntimeMethods.displayedViewControllersForTab {
            return nil
        }
        if let originalDelegate, originalDelegate.responds(to: aSelector) {
            return originalDelegate
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
