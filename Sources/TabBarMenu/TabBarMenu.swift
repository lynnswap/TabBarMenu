// The Swift Programming Language
// https://docs.swift.org/swift-book

import UIKit
import ObjectiveC


/// Defines where the menu anchor should be placed within the container view.
public enum TabBarMenuAnchorPlacement: Equatable {
    /// Default offset for `above(offset:)` when omitted.
    public static var defaultAboveOffset: CGFloat {
        if #available(iOS 26.0, *) {
            return 8
        }
        return -12
    }
    /// Uses the default anchor point inside the tab bar.
    case inside
    /// Places the anchor above the tab bar, offset from the tab's top edge.
    /// Defaults to `defaultAboveOffset` when omitted.
    case above(offset: CGFloat = TabBarMenuAnchorPlacement.defaultAboveOffset)
    /// Uses a custom point in the container view's coordinate space.
    case custom(CGPoint)
}

/// Configuration for TabBarMenu behaviors.
public struct TabBarMenuConfiguration: Equatable {
    /// The minimum press duration required to trigger the menu.
    public var minimumPressDuration: TimeInterval
    /// Fallback maximum number of visible tabs before the system shows the More tab. Defaults to 5.
    /// UIKit's runtime value is preferred when available; this value is used when the runtime value cannot be resolved.
    public var maxVisibleTabCount: Int

    public init(
        minimumPressDuration: TimeInterval = 0.35,
        maxVisibleTabCount: Int = 5
    ) {
        self.minimumPressDuration = minimumPressDuration
        self.maxVisibleTabCount = maxVisibleTabCount
    }
}

/// The recognized gesture, before menu presentation or tab selection begins.
public enum TabBarInteraction: Equatable, Sendable {
    case tap
    case longPress
}

/// The tab bar item that received an interaction.
///
/// More is a presentation of a group of tabs, not a selectable content tab.
/// Its selected content is non-nil only while that content is active.
@MainActor
public enum TabBarItem {
    case tab(UITab)
    case more(tabs: [UITab], selectedTab: UITab?)
    /// A tab configured through `UITabBarController.viewControllers`.
    case viewController(UIViewController)
    case moreViewControllers(viewControllers: [UIViewController], selectedViewController: UIViewController?)
}

/// A menu and the presentation choices for one interaction.
@MainActor
public struct TabBarMenuPresentation {
    public var menu: UIMenu
    public var anchorPlacement: TabBarMenuAnchorPlacement
    /// Defaults to UIKit's automatic ordering. Use `.fixed` to preserve the children array order.
    public var preferredMenuElementOrder: UIContextMenuConfiguration.ElementOrder

    public init(
        menu: UIMenu,
        anchorPlacement: TabBarMenuAnchorPlacement = .above(),
        preferredMenuElementOrder: UIContextMenuConfiguration.ElementOrder = .automatic
    ) {
        self.menu = menu
        self.anchorPlacement = anchorPlacement
        self.preferredMenuElementOrder = preferredMenuElementOrder
    }
}

/// Prepares tab bar interactions and receives completed user selections.
@MainActor
public protocol TabBarMenuDelegate: AnyObject {
    /// Called once after recognizing a tap or long press, before changing selection or showing a menu.
    ///
    /// Return a presentation to consume the interaction by showing its menu. Return nil to
    /// allow a tap to select its tab, or to leave a long press without a menu.
    /// A nil presentation for a More tap reselects its active content. If there is no active
    /// More content, UIKit's More list opens instead. Opening a menu never sends `didSelect`.
    /// This method is not called for layout, programmatic selection, or menu action execution.
    func tabBarController(
        _ tabBarController: UITabBarController,
        prepareFor interaction: TabBarInteraction,
        on item: TabBarItem
    ) -> TabBarMenuPresentation?

    /// Called once after a user selects or reselects actual tab content.
    ///
    /// Compare identities with `previousTab` to recognize a reselection. `isOverflow` describes
    /// whether the selected tab is in More at selection time, not the origin of the interaction.
    /// Programmatic `selectTabContent` calls are silent; use `selectionAction(for:)` in menus.
    /// This notification precedes the forwarded UIKit `didSelect` / `didSelectTab` or More-navigation
    /// `didShow` callback, so synchronous changes there cannot discard the completed selection.
    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect selectedTab: UITab,
        previousTab: UITab?,
        isOverflow: Bool
    )

    /// The selection notification for a controller configured with `viewControllers`.
    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect selectedViewController: UIViewController,
        previousViewController: UIViewController?,
        isOverflow: Bool
    )
}

public extension TabBarMenuDelegate {
    func tabBarController(
        _ tabBarController: UITabBarController,
        prepareFor interaction: TabBarInteraction,
        on item: TabBarItem
    ) -> TabBarMenuPresentation? { nil }

    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect selectedTab: UITab,
        previousTab: UITab?,
        isOverflow: Bool
    ) {}

    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect selectedViewController: UIViewController,
        previousViewController: UIViewController?,
        isOverflow: Bool
    ) {}
}

@MainActor
public extension UITabBarController {
    /// The delegate that supplies menus for tab bar items.
    /// Set this to automatically attach menu handling to the tab bar controller.
    /// Set to `nil` to remove menu handling and associated gestures.
    var menuDelegate: TabBarMenuDelegate? {
        get {
            tabBarMenuCoordinator?.delegate
        }
        set {
            if let delegate = newValue {
                let coordinator = tabBarMenuCoordinator ?? TabBarMenuCoordinator()
                coordinator.delegate = delegate
                coordinator.configuration = tabBarMenuConfiguration
                coordinator.attach(to: self)
                tabBarMenuCoordinator = coordinator
            } else {
                if let coordinator = tabBarMenuCoordinator {
                    coordinator.delegate = nil
                    coordinator.detach()
                }
                tabBarMenuCoordinator = nil
            }
        }
    }

    /// Configuration for TabBarMenu behaviors.
    var menuConfiguration: TabBarMenuConfiguration {
        get {
            tabBarMenuConfiguration
        }
        set {
            tabBarMenuConfiguration = newValue
        }
    }

    /// Updates the configuration using an inout block.
    func updateMenuConfiguration(_ update: (inout TabBarMenuConfiguration) -> Void) {
        var configuration = menuConfiguration
        update(&configuration)
        menuConfiguration = configuration
    }

    /// Updates the presented tab bar menu, if available.
    /// - Parameter update: Receives the current menu (if any) and returns the new menu.
    /// - Returns: `true` when a menu host button exists and the update was applied.
    @discardableResult
    func updateTabBarMenu(_ update: (UIMenu?) -> UIMenu?) -> Bool {
        tabBarMenuCoordinator?.updateVisibleMenu(update) ?? false
    }

    /// Makes an action that selects this tab and sends one user-selection notification.
    /// Membership and the UIKit delegate's selection permission are checked when the action runs.
    func selectionAction(for tab: UITab) -> UIAction {
        UIAction(title: tab.title, image: tab.image, state: tabBarMenuSelectedTab === tab ? .on : .off) { [weak self, weak tab] _ in
            guard let self, let tab else { return }
            self.tabBarMenuCoordinator?.selectFromUser(.tab(tab))
        }
    }

    /// Makes a user-selection action for a `viewControllers`-based tab bar.
    func selectionAction(for viewController: UIViewController) -> UIAction {
        UIAction(
            title: viewController.tabBarItem.title ?? viewController.title ?? "",
            image: viewController.tabBarItem.image,
            state: tabBarMenuSelectedViewController === viewController ? .on : .off
        ) { [weak self, weak viewController] _ in
            guard let self, let viewController else { return }
            self.tabBarMenuCoordinator?.selectFromUser(.viewController(viewController))
        }
    }

    internal var tabBarMenuCoordinator: TabBarMenuCoordinator? {
        get {
            ObjectiveCInterop.associatedObject(for: self, key: &TabBarMenuAssociatedKeys.coordinator)
        }
        set {
            ObjectiveCInterop.setAssociatedObject(
                newValue,
                for: self,
                key: &TabBarMenuAssociatedKeys.coordinator,
                policy: .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    private var tabBarMenuConfiguration: TabBarMenuConfiguration {
        get {
            if let box: TabBarMenuConfigurationBox = ObjectiveCInterop.associatedObject(
                for: self,
                key: &TabBarMenuAssociatedKeys.configuration
            ) {
                return box.value
            }
            let defaultValue = TabBarMenuConfiguration()
            ObjectiveCInterop.setAssociatedObject(
                TabBarMenuConfigurationBox(defaultValue),
                for: self,
                key: &TabBarMenuAssociatedKeys.configuration,
                policy: .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            return defaultValue
        }
        set {
            let box = (ObjectiveCInterop.associatedObject(
                for: self,
                key: &TabBarMenuAssociatedKeys.configuration
            ) as TabBarMenuConfigurationBox?) ?? TabBarMenuConfigurationBox(newValue)
            box.value = newValue
            ObjectiveCInterop.setAssociatedObject(
                box,
                for: self,
                key: &TabBarMenuAssociatedKeys.configuration,
                policy: .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            tabBarMenuCoordinator?.configuration = newValue
        }
    }
}


@MainActor
private enum TabBarMenuAssociatedKeys {
    static var coordinator = UInt8(0)
    static var configuration = UInt8(1)
}

private final class TabBarMenuConfigurationBox {
    var value: TabBarMenuConfiguration

    init(_ value: TabBarMenuConfiguration) {
        self.value = value
    }
}
