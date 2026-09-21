# Using TabBarMenu

Add menus, handle tab selections, and customize their presentation.

## Overview

Set `menuDelegate` on your `UITabBarController` to a `TabBarMenuDelegate`.
The controller holds the delegate weakly, so keep it alive for as long as it is
needed. Set `menuDelegate = nil` to detach interaction handling and restore the
UIKit delegate.

## Add a menu to a regular tab

Implement `prepareFor:on:` to choose which interactions show a menu. For example,
this implementation adds an action when someone long-presses a regular `UITab`:

```swift
func tabBarController(
    _ controller: UITabBarController,
    prepareFor interaction: TabBarInteraction,
    on item: TabBarItem
) -> TabBarMenuPresentation? {
    guard interaction == .longPress, case .tab(let tab) = item else { return nil }

    let action = UIAction(title: "About this tab") { _ in
        print(tab.identifier)
    }
    return TabBarMenuPresentation(
        menu: UIMenu(title: tab.title, children: [action])
    )
}
```

`prepareFor` runs once after recognizing the gesture, before selection or menu
presentation. Returning a presentation consumes the interaction: it shows the
menu without selecting a tab or calling `didSelect`. Returning `nil` has the
following meaning:

| Interaction | Result of returning `nil` |
| --- | --- |
| Tap a regular tab | UIKit selects or reselects that tab. |
| Tap More while its content is active | Reselect that content without rebuilding its navigation stack. |
| Tap More with no active More content | Open UIKit's More list. |
| Long press | Do nothing. |

For `.more(tabs:selectedTab:)`, build menu entries from the supplied `tabs`
using `controller.selectionAction(for:)`.

`selectedTab` is the content currently displayed through More, not
its last-used tab. It is `nil` when a regular tab or the More list is active.
Layout and programmatic selection do not call `prepareFor`.

## Handle selections and reselections

Implement `didSelect` to respond to user selections from regular tabs, More,
and actions created with `selectionAction(for:)`:

```swift
func tabBarController(
    _ controller: UITabBarController,
    didSelect selectedTab: UITab,
    previousTab: UITab?,
    isOverflow: Bool
) {
    if selectedTab === previousTab {
        // Run your re-tap action here, such as scrolling to the top.
        print("Reselected", selectedTab.identifier, "in More:", isOverflow)
    }
}
```

`didSelect` reports actual content, never a synthetic More tab. `previousTab`
is the previously active content, or `nil` when there was none. Compare object
identities to detect reselection. `isOverflow` describes the selected tab's
placement at selection time; it does not indicate which gesture selected it.

Use `selectionAction(for:)` for menu entries that select a tab. Its action checks
current membership, enabled state, and the existing UIKit delegate's
`shouldSelect` decision, then selects the content and sends one `didSelect`.
Executing a menu action does not call `prepareFor` again.

For restoration and display synchronization, use `selectTabContent(_:)`. This
programmatic operation does not send a `TabBarMenuDelegate.didSelect` notification
or request a menu. It returns whether the content selection succeeded.

### Work with an existing UIKit delegate

Your existing `UITabBarControllerDelegate` remains available for selection
permission and other UIKit behavior. Use `TabBarMenuDelegate.didSelect` as your
application's common selection handler for ordinary tabs, More reselection, and
selection actions. Native UIKit callbacks continue to be forwarded.

The package's completed-selection notification precedes the forwarded UIKit
`didSelect` / `didSelectTab` or More-navigation `didShow` callback, so synchronous
tab or selection changes there do not discard the completed event.

A UIKit delegate assigned after `menuDelegate` is picked up at the next native
tap selection or menu-action execution, without waiting for a layout pass.
Replacing or clearing `moreNavigationController.delegate` is observed immediately,
so selecting a row in the More list continues to report completion. Detaching
`menuDelegate` restores the most recently assigned navigation delegate.

## Use classic view-controller tab bars

When the controller uses `viewControllers`, preparation receives
`.viewController(UIViewController)` or
`.moreViewControllers(viewControllers:selectedViewController:)` instead.
Return presentations with the same rules and use the view-controller overload
of `selectionAction(for:)`. Selection is reported through:

```swift
func tabBarController(
    _ controller: UITabBarController,
    didSelect selectedViewController: UIViewController,
    previousViewController: UIViewController?,
    isOverflow: Bool
) {
    print(selectedViewController, previousViewController as Any, isOverflow)
}
```

## Customize menus

`TabBarMenuPresentation` holds the menu, anchor placement, and element ordering
for one interaction. Its defaults are `.above()` and `.automatic` ordering.
Use `.fixed` when the menu should preserve its `children` array order.

| Anchor placement | Position |
| --- | --- |
| `.inside` | The default anchor point inside the tab bar. |
| `.above(offset:)` | Above the tab bar, offset from the tab's top edge. |
| `.custom(CGPoint)` | A point in the tab bar controller's view coordinates. |

TabBarMenu owns the menu host button and applies these values internally.

To change gesture timing or the fallback tab count, update the controller's
configuration:

```swift
controller.updateMenuConfiguration { configuration in
    configuration.minimumPressDuration = 0.5
    configuration.maxVisibleTabCount = 5
}
```

`maxVisibleTabCount` is a fallback; UIKit's actual More position and runtime limit
are preferred. Use `updateTabBarMenu` to replace the content of an already
presented menu while retaining its presentation choices.
