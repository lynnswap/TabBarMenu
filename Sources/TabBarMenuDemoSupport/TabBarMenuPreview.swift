import SwiftUI
import Observation
import TabBarMenu

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
    var isSearchTabEnabled = false {
        didSet {
            applyTabs()
        }
    }
    private var previewController: TabBarMenuPreviewBaseController?
    private weak var containerController: TabBarMenuPreviewContainerController?
    private var currentMode: TabBarMenuPreviewMode?

    init(tabs: [PreviewTab] = PreviewTabDefaults.initialTabs) {
        self.tabs = tabs
    }

    func register(_ container: TabBarMenuPreviewContainerController) {
        containerController = container
        if let previewController {
            container.setContent(previewController)
        }
    }

    func updateMode(_ mode: TabBarMenuPreviewMode) {
        guard currentMode != mode || previewController == nil else {
            return
        }
        currentMode = mode
        let controller: TabBarMenuPreviewBaseController
        switch mode {
        case .uiTab:
            controller = TabBarMenuPreviewTabsController()
        case .uiTabBarItem:
            controller = TabBarMenuPreviewItemsController()
        }
        previewController = controller
        configure(controller)
        controller.applyPreviewTabs(tabs, showsSearchTab: isSearchTabEnabled)
        containerController?.setContent(controller)
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

    func deleteTab(_ viewController: UIViewController) {
        let identifier = viewController.restorationIdentifier ?? ""
        let title = viewController.title ?? viewController.tabBarItem.title ?? ""
        tabs.removeAll { previewTab in
            if !identifier.isEmpty, previewTab.identifier == identifier {
                return true
            }
            return !title.isEmpty && previewTab.title == title
        }
    }

    private func applyTabs() {
        previewController?.applyPreviewTabs(tabs, showsSearchTab: isSearchTabEnabled)
    }

    private func configure(_ controller: TabBarMenuPreviewBaseController) {
        controller.updateMenuConfiguration { configuration in
            configuration.moreTabMenuTrigger = .tap
        }
        controller.menuDelegate = controller
        controller.viewModel = self
    }
}

public enum TabBarMenuPreviewMode: String {
    case uiTab
    case uiTabBarItem
}

@MainActor
private class TabBarMenuPreviewBaseController: UITabBarController, TabBarMenuDelegate {
    weak var viewModel: TabBarMenuPreviewViewModel?

    func applyPreviewTabs(_ previewTabs: [PreviewTab], showsSearchTab: Bool) {}

    func tabBarController(_ tabBarController: UITabBarController, tab: UITab?) -> UIMenu? {
        guard let tab else {
            return nil
        }
        return makeMenu(title: tab.title) { [weak self] in
            self?.viewModel?.deleteTab(tab)
        }
    }

    func tabBarController(_ tabBarController: UITabBarController, menuForMoreTabWith tabs: [UITab]) -> UIMenu? {
        guard !tabs.isEmpty else {
            return nil
        }
        let actions = tabs.map { tab in
            let title = tab.title.isEmpty ? "Untitled" : tab.title
            return UIAction(title: title, image: tab.image) { [weak tab] _ in
                guard let tab ,let tabBarController = tab.tabBarController else {
                    return
                }
                if !tabBarController.moreNavigationController.navigationBar.isHidden{
                    tabBarController.moreNavigationController.navigationBar.isHidden = true
                }
                tabBarController.selectedTab = tab
            }
        }
        return UIMenu(children: actions)
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        configureMenuPresentationFor tab: UITab,
        tabFrame: CGRect,
        in containerView: UIView,
        menuHostButton: UIButton
    ) -> TabBarMenuAnchorPlacement?{
        menuHostButton.preferredMenuElementOrder = .fixed
        return nil
    }

    fileprivate func makeMenu(title: String, deleteHandler: @escaping () -> Void) -> UIMenu {
        let rename = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in }
        let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
            deleteHandler()
        }
        return UIMenu(title: title, children: [rename, delete])
    }
}

@MainActor
private final class TabBarMenuPreviewContainerController: UIViewController {
    private var currentController: UIViewController?

    func setContent(_ controller: UIViewController) {
        guard currentController !== controller else {
            return
        }
        if let currentController {
            currentController.willMove(toParent: nil)
            currentController.view.removeFromSuperview()
            currentController.removeFromParent()
        }
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        currentController = controller
    }
}

private final class TabBarMenuPreviewTabsController: TabBarMenuPreviewBaseController {
    private var hasAppliedTabs = false

    override func applyPreviewTabs(_ previewTabs: [PreviewTab], showsSearchTab: Bool) {
        var updatedTabs = previewTabs.map { makeTab($0) }
        if showsSearchTab {
            updatedTabs.append(makeSearchTab())
        }
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

    private func makeSearchTab() -> UISearchTab {
        UISearchTab { _ in
            let controller = UIHostingController(
                rootView: SampleTabView(title: "Search", systemImage: "magnifyingglass")
            )
            controller.title = "Search"
            return controller
        }
    }
}

private final class TabBarMenuPreviewItemsController: TabBarMenuPreviewBaseController, TabBarMenuViewControllerDelegate {
    private var hasAppliedTabs = false

    func tabBarController(_ tabBarController: UITabBarController, viewController: UIViewController?) -> UIMenu? {
        guard let viewController else {
            return nil
        }
        let title = viewController.title ?? viewController.tabBarItem.title ?? ""
        return makeMenu(title: title) { [weak self] in
            self?.viewModel?.deleteTab(viewController)
        }
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        menuForMoreTabWith viewControllers: [UIViewController]
    ) -> UIMenu? {
        guard !viewControllers.isEmpty else {
            return nil
        }
        let actions = viewControllers.map { viewController in
            let title = viewController.title ?? viewController.tabBarItem.title ?? "Untitled"
            return UIAction(title: title, image: viewController.tabBarItem.image) { [weak viewController] _ in
                guard let viewController, let tabBarController = viewController.tabBarController else {
                    return
                }
                if !tabBarController.moreNavigationController.navigationBar.isHidden{
                    tabBarController.moreNavigationController.navigationBar.isHidden = true
                }
                tabBarController.selectedViewController = viewController
            }
        }
        return UIMenu(children: actions)
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        configureMenuPresentationFor viewController: UIViewController,
        tabFrame: CGRect,
        in containerView: UIView,
        menuHostButton: UIButton
    ) -> TabBarMenuAnchorPlacement? {
        menuHostButton.preferredMenuElementOrder = .fixed
        return nil
    }

    override func applyPreviewTabs(_ previewTabs: [PreviewTab], showsSearchTab: Bool) {
        var updatedViewControllers = previewTabs.map { makeTab($0) }
        if showsSearchTab {
            updatedViewControllers.append(makeSearchTab())
        }
        let shouldAnimate = hasAppliedTabs
        setViewControllers(updatedViewControllers, animated: shouldAnimate)
        hasAppliedTabs = true
    }
    func makeTab(_ tab: PreviewTab) -> UIViewController {
        let controller = UIHostingController(
            rootView: SampleTabView(title: tab.title, systemImage: tab.systemImageName)
        )
        controller.title = tab.title
        controller.restorationIdentifier = tab.identifier
        controller.tabBarItem = UITabBarItem(
            title: tab.title,
            image: UIImage(systemName: tab.systemImageName),
            selectedImage: UIImage(systemName: "\(tab.systemImageName).fill")
        )
        return controller
    }

    func makeSearchTab() -> UIViewController {
        let controller = UIHostingController(
            rootView: SampleTabView(title: "Search", systemImage: "magnifyingglass")
        )
        controller.title = "Search"
        controller.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: 0)
        return controller
    }
}
private struct SampleTabView: View {
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
    }
}
private struct TabBarMenuPreviewRepresentable: UIViewControllerRepresentable {
    let mode: TabBarMenuPreviewMode
    let viewModel: TabBarMenuPreviewViewModel

    func makeUIViewController(context: Context) -> TabBarMenuPreviewContainerController {
        let container = TabBarMenuPreviewContainerController()
        viewModel.register(container)
        viewModel.updateMode(mode)
        return container
    }

    func updateUIViewController(_ uiViewController: TabBarMenuPreviewContainerController, context: Context) {}
}

public struct TabBarMenuPreviewScreen: View {
    private var mode: TabBarMenuPreviewMode
    @State private var viewModel = TabBarMenuPreviewViewModel()

    public init(mode: TabBarMenuPreviewMode) {
        self.mode = mode
    }

    public var body: some View {
        TabBarMenuPreviewRepresentable(mode: mode, viewModel: viewModel)
            .ignoresSafeArea()
            .toolbar{
                ToolbarItem(placement: .navigation) {
                    Toggle("Search Tab", isOn: Bindable(viewModel).isSearchTabEnabled)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") {
                        viewModel.addTab()
                    }
                }
            }
            .onChange(of: mode) {
                viewModel.updateMode(mode)
            }
    }
}

#if DEBUG
#Preview("TabBarMenu UITab") {
    NavigationStack{
        TabBarMenuPreviewScreen(mode: .uiTab)
    }
}

#Preview("TabBarMenu UITabBarItem") {
    NavigationStack{
        TabBarMenuPreviewScreen(mode: .uiTabBarItem)
    }
}
#endif
