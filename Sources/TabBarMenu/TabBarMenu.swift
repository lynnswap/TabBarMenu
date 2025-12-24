// The Swift Programming Language
// https://docs.swift.org/swift-book

import SwiftUI
import ObjectiveC


/// Defines where the menu anchor should be placed within the container view.
public enum TabBarMenuAnchorPlacement: Equatable {
    /// Uses the default anchor point inside the tab bar.
    case inside
    /// Places the anchor above the tab bar, offset from the tab's top edge.
    /// Defaults to 8 when omitted.
    case above(offset: CGFloat = 8)
    /// Uses a custom point in the container view's coordinate space.
    case custom(CGPoint)
    /// Delegate handles `menuHostButton` positioning manually.
    case manual
}

@MainActor
/// A delegate that provides contextual menus for tabs in a `UITabBarController`.
/// - Important: Return `nil` to disable the menu for a given tab.
public protocol TabBarMenuDelegate: AnyObject {
    /// Asks the delegate for the menu to present for the specified tab.
    /// - Parameters:
    ///   - tabBarController: The tab bar controller requesting the menu.
    ///   - tab: The tab associated with the long-pressed item.
    /// - Returns: A `UIMenu` to present, or `nil` to skip presenting a menu.
    func tabBarController(_ tabBarController: UITabBarController, tab: UITab) -> UIMenu?

    /// Asks the delegate for the anchor placement for the menu.
    /// - Parameters:
    ///   - tabBarController: The tab bar controller requesting the anchor placement.
    ///   - tab: The tab associated with the long-pressed item.
    ///   - tabFrame: The tab bar item frame in `containerView` coordinates.
    ///   - containerView: The view hosting the menu.
    ///   - menuHostButton: The internal button used to present the menu.
    /// - Returns: The placement to use, or `nil` to use the default placement.
    func tabBarController(
        _ tabBarController: UITabBarController,
        anchorPlacementFor tab: UITab,
        tabFrame: CGRect,
        in containerView: UIView,
        menuHostButton: UIButton
    ) -> TabBarMenuAnchorPlacement?
}

@MainActor
public extension TabBarMenuDelegate {
    func tabBarController(
        _ tabBarController: UITabBarController,
        anchorPlacementFor tab: UITab,
        tabFrame: CGRect,
        in containerView: UIView,
        menuHostButton: UIButton
    ) -> TabBarMenuAnchorPlacement? {
        nil
    }
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
}


@MainActor
private enum TabBarMenuAssociatedKeys {
    static var coordinator = UInt8(0)
}

#if DEBUG

private final class TabBarMenuPreviewController: UITabBarController, TabBarMenuDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()

        tabs = [
            makeTab(title: "Home", systemImageName: "house", identifier: "home"),
            makeTab(title: "Profile", systemImageName: "person", identifier: "profile")
        ]
        menuDelegate = self
    }

    func tabBarController(_ tabBarController: UITabBarController, tab: UITab) -> UIMenu? {
        let rename = UIAction(title: "Rename") { _ in }
        let delete = UIAction(title: "Delete", attributes: .destructive) { _ in }
        return UIMenu(title: tab.title, children: [rename, delete])
    }

    private func makeTab(title: String, systemImageName: String, identifier: String) -> UITab {
        UITab(title: title, image: UIImage(systemName: systemImageName), identifier: identifier) { _ in
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            controller.title = title
            return controller
        }
    }
}

private struct TabBarMenuPreview: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UITabBarController {
        TabBarMenuPreviewController()
    }
    func updateUIViewController(_ uiViewController: UITabBarController, context: Context) {}
}

#Preview("TabBarMenu") {
    TabBarMenuPreview()
        .ignoresSafeArea()
}

#endif
