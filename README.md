# TabBarMenu

TabBarMenu adds long-press context menus to `UITabBarController` tabs on iOS 18+.

## Requirements

- iOS 18.0+
- Swift 6.2 (Swift tools version in `Package.swift`)

## Installation

Add the package via Swift Package Manager in Xcode:

1. File > Add Packages...
2. Enter the repository URL
3. Add the `TabBarMenu` product to your target

## Usage

Conform to `TabBarMenuDelegate` and set `menuDelegate` on your tab bar controller.

```swift
import UIKit
import TabBarMenu

final class MainTabBarController: UITabBarController, TabBarMenuDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        menuDelegate = self
    }

    func tabBarController(_ tabBarController: UITabBarController, tab: UITab) -> UIMenu? {
        let rename = UIAction(title: "Rename") { _ in
            // Handle rename
        }
        let delete = UIAction(title: "Delete", attributes: .destructive) { _ in
            // Handle delete
        }
        return UIMenu(title: "", children: [rename, delete])
    }
}
```

Return `nil` to disable the menu for a given tab. Set `menuDelegate = nil` to remove menu handling.

## Anchor placement

To customize the menu anchor point, implement the optional delegate method that returns
`TabBarMenuAnchorPlacement`. Return `nil` to keep the default placement (inside the tab bar).

```swift
final class MainTabBarController: UITabBarController, TabBarMenuDelegate {
    func tabBarController(
        _ tabBarController: UITabBarController,
        anchorPlacementFor tab: UITab,
        tabFrame: CGRect,
        in containerView: UIView,
        menuHostButton: UIButton
    ) -> TabBarMenuAnchorPlacement? {
        .aboveTabBar()
    }
}
```

## TabBarMenuAnchorPlacement

- `.insideTabBar`: uses the default anchor point inside the tab bar.
- `.aboveTabBar(offset:)`: places the anchor above the tab bar. The default offset is 8.
- `.custom(CGPoint)`: uses a custom point in the container view's coordinate space.
- `.manual`: delegate sets `menuHostButton.frame` manually in `anchorPlacementFor`.

## License

MIT. See [LICENSE](LICENSE).
