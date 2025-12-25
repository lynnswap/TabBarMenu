import SwiftUI
import Observation

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
    var isSearchTabEnabled = false {
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
        controller.applyPreviewTabs(tabs, showsSearchTab: isSearchTabEnabled)
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

    func applyPreviewTabs(_ previewTabs: [PreviewTab], showsSearchTab: Bool) {}

    func tabBarController(_ tabBarController: UITabBarController, tab: UITab?) -> UIMenu? {
        guard let tab else {
            return nil
        }
        return makeMenu(title: tab.title) { [weak self] in
            self?.viewModel?.deleteTab(tab)
        }
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
                    ToolbarItem(placement: .navigation) {
                        Toggle("Search Tab", isOn: Bindable(viewModel).isSearchTabEnabled)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add") {
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
