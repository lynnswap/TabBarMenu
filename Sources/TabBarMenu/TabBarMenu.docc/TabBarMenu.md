# ``TabBarMenu``

Prepare tab bar interactions and receive completed selections, including More content.

## Overview

Set your tab bar controller's `menuDelegate` to a ``TabBarMenuDelegate``.
Its `prepareFor:on:` method runs once after recognizing a tap or long press,
before selection or menu presentation. Return a ``TabBarMenuPresentation`` to
show a menu and consume the interaction.

Returning `nil` permits a tap to select its content, or leaves a long press
without an action. A More tap reselects its active content; if More has no active
content, UIKit opens its More list. Merely showing a menu never selects content.

```swift
func tabBarController(
    _ controller: UITabBarController,
    prepareFor interaction: TabBarInteraction,
    on item: TabBarItem
) -> TabBarMenuPresentation? {
    switch item {
    case .more(let tabs, let selectedTab):
        if interaction == .tap, selectedTab != nil { return nil }
        return TabBarMenuPresentation(
            menu: UIMenu(children: tabs.map { controller.selectionAction(for: $0) }),
            anchorPlacement: .above(),
            preferredMenuElementOrder: .fixed
        )
    case .tab, .viewController, .moreViewControllers:
        return nil
    }
}
```

The presentation's element order defaults to `.automatic`. Set `.fixed` to keep
the order of the menu's children. Anchor placement defaults to `.above()`;
custom points use the tab bar controller's view coordinate system.

Use the delegate's `didSelect` callback for user selections and reselections.
It supplies the actual content, the previous content (if any), and whether the
selected content is in More. Compare the selected and previous objects by
identity to detect a reselection. The view-controller overload provides the same
contract for controllers configured with `viewControllers`.

Menu entries made with `selectionAction(for:)` follow this notification path and
respect the existing UIKit delegate's selection permission. Programmatic
`selectTabContent(_:)` is silent, as are menu preparation and layout.

Set `menuDelegate` to `nil` to remove interaction handling. The existing UIKit
delegate is restored. Keep menu delegates alive for as long as they are needed;
the controller holds them weakly.

> Important: TabBarMenu relies on undocumented UIKit APIs and runtime behavior.
> Evaluate that constraint before using it in an App Store-bound app.

## Topics

### Preparing Interactions

- ``TabBarMenuDelegate``
- ``TabBarInteraction``
- ``TabBarItem``

### Configuring Presentation

- ``TabBarMenuPresentation``
- ``TabBarMenuAnchorPlacement``
- ``TabBarMenuConfiguration``
