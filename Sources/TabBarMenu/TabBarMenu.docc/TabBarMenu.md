# ``TabBarMenu``

Add contextual menus to the tabs of a `UITabBarController`.

## Overview

TabBarMenu presents a `UIMenu` when someone long-presses a tab. It supports both
`UITab`-based and view-controller-based tab bars, including the system More tab.

Conform your tab bar controller to ``TabBarMenuDelegate``, assign it to
`menuDelegate`, and return the menu for each tab:

```swift
import TabBarMenu
import UIKit

final class MainTabBarController: UITabBarController, TabBarMenuDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        menuDelegate = self
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        tab: UITab?
    ) -> UIMenu? {
        guard let tab else { return nil }
        return UIMenu(
            title: tab.title,
            children: [UIAction(title: "Rename") { _ in }]
        )
    }
}
```

Return `nil` to disable the menu for a tab. Set `menuDelegate` to `nil` when the
tab bar controller should stop providing menus.

> Important: TabBarMenu relies on undocumented UIKit APIs and runtime behavior.
> Evaluate that constraint before using it in an App Store-bound app.

## Topics

### Providing Menus

- ``TabBarMenuDelegate``
- ``TabBarMenuContentDelegate``
- ``TabBarMenuPresentationDelegate``

### Configuring Behavior

- ``TabBarMenuConfiguration``
- ``TabBarMenuAnchorPlacement``
