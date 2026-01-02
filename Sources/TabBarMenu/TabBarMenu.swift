// The Swift Programming Language
// https://docs.swift.org/swift-book

import SwiftUI
import Observation
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
    /// Delegate handles `menuHostButton` positioning manually.
    case manual
}

/// Configuration for TabBarMenu behaviors.
public struct TabBarMenuConfiguration: Equatable {
    /// The minimum press duration required to trigger the menu.
    public var minimumPressDuration: TimeInterval
    /// The maximum number of visible tabs before the system shows the More tab. Defaults to 5.
    /// When the total tab count exceeds this value, the trailing visible item is treated as the More tab.
    public var maxVisibleTabCount: Int

    public init(
        minimumPressDuration: TimeInterval = 0.35,
        maxVisibleTabCount: Int = 5
    ) {
        self.minimumPressDuration = minimumPressDuration
        self.maxVisibleTabCount = maxVisibleTabCount
    }
}

/// Objective-C-compatible delegate methods for menu content.
///
/// Prefer conforming to `TabBarMenuDelegate` instead of this protocol directly.
@MainActor @objc public protocol TabBarMenuContentDelegate: NSObjectProtocol {
    /// Asks the delegate for the menu to present for the specified tab.
    /// - Parameters:
    ///   - tabBarController: The tab bar controller requesting the menu.
    ///   - tab: The tab associated with the long-pressed item.
    /// - Note: Use `tabBarController(_:menuForMoreTabWith:)` to provide a menu for the system More tab.
    /// - Returns: A `UIMenu` to present, or `nil` to skip presenting a menu.
    @objc optional func tabBarController(
        _ tabBarController: UITabBarController,
        tab: UITab?
    ) -> UIMenu?

    /// Asks the delegate for the menu to present for the specified view controller.
    /// - Parameters:
    ///   - tabBarController: The tab bar controller requesting the menu.
    ///   - viewController: The view controller associated with the long-pressed item.
    /// - Returns: A `UIMenu` to present, or `nil` to skip presenting a menu.
    @objc optional func tabBarController(
        _ tabBarController: UITabBarController,
        viewController: UIViewController?
    ) -> UIMenu?

    /// Asks the delegate for the menu to present for the system More tab.
    /// - Parameters:
    ///   - tabBarController: The tab bar controller requesting the menu.
    ///   - tabs: The tabs that would appear in the More list, in display order.
    /// - Returns: A `UIMenu` to present, or `nil` to skip presenting a menu.
    @objc(tabBarController:menuForMoreTabWithTabs:)
    optional func tabBarController(
        _ tabBarController: UITabBarController,
        menuForMoreTabWith tabs: [UITab]
    ) -> UIMenu?

    /// Asks the delegate for the menu to present for the system More tab.
    /// - Parameters:
    ///   - tabBarController: The tab bar controller requesting the menu.
    ///   - viewControllers: The view controllers that would appear in the More list, in display order.
    /// - Returns: A `UIMenu` to present, or `nil` to skip presenting a menu.
    @objc(tabBarController:menuForMoreTabWithViewControllers:)
    optional func tabBarController(
        _ tabBarController: UITabBarController,
        menuForMoreTabWith viewControllers: [UIViewController]
    ) -> UIMenu?
}

/// A Swift-only delegate that customizes menu anchor placement.
@MainActor public protocol TabBarMenuPresentationDelegate: AnyObject {
    /// Asks the delegate to configure menu presentation and anchor placement.
    /// - Parameters:
    ///   - tabBarController: The tab bar controller requesting the anchor placement.
    ///   - tab: The tab associated with the long-pressed item.
    ///   - tabFrame: The tab bar item frame in `containerView` coordinates.
    ///   - containerView: The view hosting the menu.
    ///   - menuHostButton: The internal button used to present the menu. Configure properties like
    ///     `preferredMenuElementOrder` here.
    /// - Returns: The placement to use, or `nil` to use the default placement.
    func tabBarController(
        _ tabBarController: UITabBarController,
        configureMenuPresentationFor tab: UITab,
        tabFrame: CGRect,
        in containerView: UIView,
        menuHostButton: UIButton
    ) -> TabBarMenuAnchorPlacement?

    /// Asks the delegate to configure menu presentation and anchor placement.
    /// - Parameters:
    ///   - tabBarController: The tab bar controller requesting the anchor placement.
    ///   - viewController: The view controller associated with the long-pressed item.
    ///   - tabFrame: The tab bar item frame in `containerView` coordinates.
    ///   - containerView: The view hosting the menu.
    ///   - menuHostButton: The internal button used to present the menu.
    /// - Returns: The placement to use, or `nil` to use the default placement.
    func tabBarController(
        _ tabBarController: UITabBarController,
        configureMenuPresentationFor viewController: UIViewController,
        tabFrame: CGRect,
        in containerView: UIView,
        menuHostButton: UIButton
    ) -> TabBarMenuAnchorPlacement?
}

/// A delegate that provides contextual menus for a `UITabBarController`.
///
/// Implement either the `UITab`-based delegate methods (iOS 18+) or the `UIViewController`-based delegate methods,
/// depending on how you configure your `UITabBarController`.
///
/// - Important: Return `nil` to disable the menu for a given item.
/// - Note: Conforming types should be Objective-C compatible (for example, subclass `NSObject`) so `responds(to:)` works.
@MainActor public protocol TabBarMenuDelegate: TabBarMenuContentDelegate, TabBarMenuPresentationDelegate {}

@MainActor
public extension TabBarMenuPresentationDelegate {
    func tabBarController(
        _ tabBarController: UITabBarController,
        configureMenuPresentationFor tab: UITab,
        tabFrame: CGRect,
        in containerView: UIView,
        menuHostButton: UIButton
    ) -> TabBarMenuAnchorPlacement? {
        nil
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        configureMenuPresentationFor viewController: UIViewController,
        tabFrame: CGRect,
        in containerView: UIView,
        menuHostButton: UIButton
    ) -> TabBarMenuAnchorPlacement? {
        nil
    }
}

/// Deprecated. Use `TabBarMenuDelegate` and implement the view-controller-based delegate methods instead.
@available(*, deprecated, message: "Use TabBarMenuDelegate instead.")
@MainActor public protocol TabBarMenuViewControllerDelegate: TabBarMenuDelegate {}

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

    private var tabBarMenuCoordinator: TabBarMenuCoordinator? {
        get {
            objc_getAssociatedObject(self, &TabBarMenuAssociatedKeys.coordinator) as? TabBarMenuCoordinator
        }
        set {
            objc_setAssociatedObject(
                self,
                &TabBarMenuAssociatedKeys.coordinator,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    private var tabBarMenuConfiguration: TabBarMenuConfiguration {
        get {
            if let box = objc_getAssociatedObject(self, &TabBarMenuAssociatedKeys.configuration) as? TabBarMenuConfigurationBox {
                return box.value
            }
            let defaultValue = TabBarMenuConfiguration()
            objc_setAssociatedObject(
                self,
                &TabBarMenuAssociatedKeys.configuration,
                TabBarMenuConfigurationBox(defaultValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            return defaultValue
        }
        set {
            let box = (objc_getAssociatedObject(self, &TabBarMenuAssociatedKeys.configuration) as? TabBarMenuConfigurationBox)
                ?? TabBarMenuConfigurationBox(newValue)
            box.value = newValue
            objc_setAssociatedObject(
                self,
                &TabBarMenuAssociatedKeys.configuration,
                box,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
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
