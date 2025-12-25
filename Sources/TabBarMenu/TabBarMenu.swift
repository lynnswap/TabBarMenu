// The Swift Programming Language
// https://docs.swift.org/swift-book

import SwiftUI
import Observation
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

/// Configuration for TabBarMenu behaviors.
public struct TabBarMenuConfiguration: Equatable {
    /// The minimum press duration required to trigger the menu.
    public var minimumPressDuration: TimeInterval

    public init(minimumPressDuration: TimeInterval = 0.35) {
        self.minimumPressDuration = minimumPressDuration
    }
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
}

@MainActor
public extension TabBarMenuDelegate {
    func tabBarController(
        _ tabBarController: UITabBarController,
        configureMenuPresentationFor tab: UITab,
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

#if DEBUG

private struct PreviewTab: Equatable {
    let title: String
    let systemImageName: String
    let identifier: String
}

private enum PreviewTabDefaults {
    static let initialTabs: [PreviewTab] = [
        PreviewTab(title: "Home", systemImageName: "house", identifier: "home"),
        PreviewTab(title: "Notifications", systemImageName: "bell", identifier: "notifications"),
        PreviewTab(title: "Profile", systemImageName: "person", identifier: "profile")
    ]

    static func nextTab(for index: Int) -> PreviewTab {
        PreviewTab(
            title: "Extra \(index)",
            systemImageName: "star",
            identifier: "extra.\(index)"
        )
    }
}

@MainActor
@Observable
private final class TabBarMenuPreviewViewModel {
    var tabs: [PreviewTab] {
        didSet {
            applyTabs()
        }
    }
    private weak var previewController: TabBarMenuPreviewBaseController?

    init(tabs: [PreviewTab] = PreviewTabDefaults.initialTabs) {
        self.tabs = tabs
    }

    func register(_ controller: TabBarMenuPreviewBaseController) {
        previewController = controller
        configure(controller)
        controller.applyPreviewTabs(tabs)
    }

    func addTab() {
        let extraIndex = tabs.count - PreviewTabDefaults.initialTabs.count + 1
        tabs.append(PreviewTabDefaults.nextTab(for: extraIndex))
    }

    func deleteTab(_ tab: UITab) {
        let identifier = tab.identifier
        tabs.removeAll { previewTab in
            if !identifier.isEmpty, previewTab.identifier == identifier {
                return true
            }
            return previewTab.title == tab.title
        }
    }

    private func applyTabs() {
        previewController?.applyPreviewTabs(tabs)
    }

    private func configure(_ controller: TabBarMenuPreviewBaseController) {
        controller.menuDelegate = controller
        controller.viewModel = self
    }
}

private enum TabBarMenuPreviewMode {
    case uiTab
    case uiTabBarItem
}

@MainActor
private class TabBarMenuPreviewBaseController: UITabBarController, TabBarMenuDelegate {
    weak var viewModel: TabBarMenuPreviewViewModel?

    func applyPreviewTabs(_ previewTabs: [PreviewTab]) {}

    func tabBarController(_ tabBarController: UITabBarController, tab: UITab) -> UIMenu? {
        let rename = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in }
        let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.viewModel?.deleteTab(tab)
        }
        return UIMenu(title: tab.title, children: [rename, delete])
    }
    func tabBarController(
        _ tabBarController: UITabBarController,
        configureMenuPresentationFor tab: UITab,
        tabFrame: CGRect,
        in containerView: UIView,
        menuHostButton: UIButton
    ) -> TabBarMenuAnchorPlacement?{
        menuHostButton.preferredMenuElementOrder = .fixed
        return .inside
    }
    
}

private final class TabBarMenuPreviewTabsController: TabBarMenuPreviewBaseController {
    private var hasAppliedTabs = false

    override func applyPreviewTabs(_ previewTabs: [PreviewTab]) {
        let updatedTabs = previewTabs.map { makeTab($0) }
        let shouldAnimate = hasAppliedTabs
        setTabs(updatedTabs, animated: shouldAnimate)
        hasAppliedTabs = true
    }
    func makeTab(_ tab: PreviewTab) -> UITab {
        UITab(title: tab.title, image: UIImage(systemName: tab.systemImageName), identifier: tab.identifier) { _ in
            let controller = UIHostingController(
                rootView: SampleTabView(title: tab.title, systemImage: tab.systemImageName)
            )
            controller.title = tab.title
            return controller
        }
    }
}

private final class TabBarMenuPreviewItemsController: TabBarMenuPreviewBaseController {
    private var hasAppliedTabs = false

    override func applyPreviewTabs(_ previewTabs: [PreviewTab]) {
        let updatedViewControllers = previewTabs.map { makeTab($0) }
        let shouldAnimate = hasAppliedTabs
        setViewControllers(updatedViewControllers, animated: shouldAnimate)
        hasAppliedTabs = true
    }
    func makeTab(_ tab: PreviewTab) -> UIViewController {
        let controller = UIHostingController(
            rootView: SampleTabView(title: tab.title, systemImage: tab.systemImageName)
        )
        controller.title = tab.title
        controller.tabBarItem = UITabBarItem(
            title: tab.title,
            image: UIImage(systemName: tab.systemImageName),
            selectedImage: UIImage(systemName: "\(tab.systemImageName).fill")
        )
        return controller
    }
}
struct SampleTabView: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView{
            Label{
                Text(title)
            }icon:{
                Image(systemName: systemImage)
                    .symbolVariant(.fill)
            }
        }
        .background(.indigo.gradient)
    }
}
private struct TabBarMenuPreviewRepresentable: UIViewControllerRepresentable {
    let mode: TabBarMenuPreviewMode
    let viewModel: TabBarMenuPreviewViewModel

    func makeUIViewController(context: Context) -> TabBarMenuPreviewBaseController {
        let controller: TabBarMenuPreviewBaseController
        switch mode {
        case .uiTab:
            controller = TabBarMenuPreviewTabsController()
        case .uiTabBarItem:
            controller = TabBarMenuPreviewItemsController()
        }
        viewModel.register(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: TabBarMenuPreviewBaseController, context: Context) {}
}

private struct TabBarMenuPreviewScreen: View {
    let mode: TabBarMenuPreviewMode
    @State private var viewModel = TabBarMenuPreviewViewModel()

    var body: some View {
        NavigationStack {
            previewContent
                .ignoresSafeArea()
                .toolbar{
                    ToolbarItem{
                        Button("Add"){
                            viewModel.addTab()
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        TabBarMenuPreviewRepresentable(mode: mode, viewModel: viewModel)
    }
}

#Preview("TabBarMenu UITab") {
    TabBarMenuPreviewScreen(mode: .uiTab)
}

#Preview("TabBarMenu UITabBarItem") {
    TabBarMenuPreviewScreen(mode: .uiTabBarItem)
}

#endif
