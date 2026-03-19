import UIKit

public extension UITab {
    var resolvedMoreSelectionViewController: UIViewController? {
        if let viewController {
            return viewController
        }
        return ObjectiveCInterop.performObjectSelector(
            Self.tabBarMenuDisplayedViewControllerSelectorName,
            on: self
        ) as? UIViewController
    }
}

private extension UITab {
    static let tabBarMenuDisplayedViewControllerSelectorName: String = {
        let parts = ["Controller", "View", "displayed", "_"]
        return parts.reversed().joined()
    }()
}
