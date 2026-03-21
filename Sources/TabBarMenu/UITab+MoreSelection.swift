import UIKit

public extension UITab {
    var resolvedMoreSelectionViewController: UIViewController? {
        if let viewController {
            return viewController
        }
        return ObjectiveCInterop.performObjectSelector(
            UITabRuntimeMethodNames.displayedViewController,
            on: self
        ) as? UIViewController
    }
}
