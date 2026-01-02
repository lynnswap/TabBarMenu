# TabBarMenu

Add long-press context menus to `UITabBarController` tabs on **iOS 18+**.

![TabBarMenu preview](Docs/images/anchor-above.webp)

## Requirements

- iOS 18.0+
- Swift 6.2 (Swift tools version in `Package.swift`)

## Installation (Swift Package Manager)

In Xcode:

1. **File** → **Add Packages…**
2. Enter the repository URL
3. Add the **TabBarMenu** product to your target

## Quick start

1. Conform to `TabBarMenuDelegate`
2. Set `menuDelegate` on your tab bar controller
3. Return a `UIMenu` for the pressed tab

> Tip: You can implement the `UITab` delegate method, the `UIViewController` delegate method, or both.
> If both are implemented, TabBarMenu tries the `UITab` delegate method first (when `UITabBarController.tabs` is available)
> and falls back to the view-controller delegate method.

```swift
import UIKit
import TabBarMenu

final class MainTabBarController: UITabBarController, TabBarMenuDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        menuDelegate = self
    }

    // iOS 18+ UITab-based API
    func tabBarController(_ tabBarController: UITabBarController, tab: UITab?) -> UIMenu? {
        makeMenu(title: tab?.title)
    }

    // Classic UIKit (viewControllers-based)
    func tabBarController(_ tabBarController: UITabBarController, viewController: UIViewController?) -> UIMenu? {
        makeMenu(title: viewController?.tabBarItem.title)
    }

    private func makeMenu(title: String?) -> UIMenu? {
        guard let title else { return nil }

        let rename = UIAction(title: "Rename") { _ in
            // Handle rename
        }
        let delete = UIAction(title: "Delete", attributes: .destructive) { _ in
            // Handle delete
        }

        return UIMenu(title: title, children: [rename, delete])
    }
}
```

- Return `nil` to disable the menu for a specific tab.
- Set `menuDelegate = nil` to detach TabBarMenu.

## Optional: menu for the system “More” tab

Provide a menu for the system **More** tab (when you have many tabs).

When `menuForMoreTabWith…` returns a menu, TabBarMenu presents it **on tap** and suppresses the system More screen.
(Long-press menus are still supported.)

```swift
func tabBarController(
    _ tabBarController: UITabBarController,
    menuForMoreTabWith tabs: [UITab]
) -> UIMenu? {
    let titles = tabs.map(\.title).joined(separator: ", ")
    return UIMenu(title: "More: \(titles)", children: [])
}
```

If you don’t use `UITab`, there’s also a `menuForMoreTabWith viewControllers: [UIViewController]` delegate method.

## Optional: configuration

```swift
updateMenuConfiguration { configuration in
    configuration.minimumPressDuration = 0.5
    configuration.maxVisibleTabCount = 5
}
```

## Optional: menu anchor placement

Return a `TabBarMenuAnchorPlacement` from the optional delegate method.

```swift
func tabBarController(
    _ tabBarController: UITabBarController,
    configureMenuPresentationFor tab: UITab,
    tabFrame: CGRect,
    in containerView: UIView,
    menuHostButton: UIButton
) -> TabBarMenuAnchorPlacement? {
    .above()
}
```

Available placements:

- `.inside`
- `.above(offset:)`
- `.custom(CGPoint)`
- `.manual`

| Inside placement | Above placement |
| --- | --- |
| ![Inside placement example](Docs/images/anchor-inside.webp) | ![Above placement example](Docs/images/anchor-above.webp) |

## Optional: update a visible menu

To refresh the menu while it’s visible:

```swift
tabBarController.updateTabBarMenu { currentMenu in
    guard let currentMenu else { return currentMenu }
    let refreshed = currentMenu.replacingChildren(currentMenu.children)
    return refreshed
}
```

## Demo app

Open `Examples/TabBarDemo/TabBarDemo.xcodeproj` and run the `TabBarDemo` scheme on iOS 18+.

## License

MIT. See [LICENSE](LICENSE).
