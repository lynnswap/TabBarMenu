import UIKit

/// More-list rows select navigation content without a tab-bar selection callback.
@MainActor
final class TabBarMenuMoreNavigationDelegateProxy: NSObject, UINavigationControllerDelegate {
    weak var coordinator: TabBarMenuCoordinator?
    nonisolated(unsafe) weak var forwardedDelegate: NSObject?
    weak var originalDelegate: (NSObject & UINavigationControllerDelegate)? {
        didSet { unsafe forwardedDelegate = originalDelegate }
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (unsafe forwardedDelegate)?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        let delegate = unsafe forwardedDelegate
        if let delegate, delegate.responds(to: selector) { return delegate }
        return super.forwardingTarget(for: selector)
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        coordinator?.willShowMoreContent(viewController, in: navigationController)
        originalDelegate?.navigationController?(navigationController, willShow: viewController, animated: animated)
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        let recipient = originalDelegate
        let coordinator = coordinator
        coordinator?.didShowMoreContent(viewController)
        let forward: @MainActor () -> Void = {
            recipient?.navigationController?(navigationController, didShow: viewController, animated: animated)
        }
        if let coordinator { coordinator.forwardUIKitCompletion(forward) } else { forward() }
    }
}
