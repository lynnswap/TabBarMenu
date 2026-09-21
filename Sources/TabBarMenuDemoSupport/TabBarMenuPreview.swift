import Observation
import SwiftUI
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

private enum UITestConfiguration {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    static let replacesMoreDelegate = ProcessInfo.processInfo.arguments.contains("-replace-more-delegate")
}

@MainActor
private protocol TabBarMenuPreviewContent: AnyObject {
    var viewModel: TabBarMenuPreviewViewModel? { get set }
    func applyPreviewTabs(_ previewTabs: [PreviewTab], showsSearchTab: Bool)
}

private typealias TabBarMenuPreviewContentController = UITabBarController & TabBarMenuDelegate & TabBarMenuPreviewContent

@MainActor
@Observable
private final class TabBarMenuPreviewViewModel {
    var tabs: [PreviewTab] {
        didSet {
            applyTabs()
        }
    }
    var selectionStatus = "Select a tab"
    var navigationStatus = "Waiting for More"
    private var selectionCount = 0

    func recordSelection(title: String, isReselection: Bool, isOverflow: Bool) {
        selectionCount += 1
        let action = isReselection ? "Reselected" : "Selected"
        selectionStatus = "\(selectionCount): \(action) \(title)\(isOverflow ? " (More)" : "")"
    }

    var isSearchTabEnabled = false {
        didSet {
            applyTabs()
        }
    }
    private var previewController: TabBarMenuPreviewContentController?
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
        let controller: TabBarMenuPreviewContentController
        switch mode {
        case .uiTab:
            controller = TabBarMenuPreviewUITabController()
        case .uiTabBarItem:
            controller = TabBarMenuPreviewViewControllerController()
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

    private func configure(_ controller: TabBarMenuPreviewContentController) {
        controller.menuDelegate = controller
        controller.viewModel = self
    }
}

public enum TabBarMenuPreviewMode: String {
    case uiTab
    case uiTabBarItem
}

@MainActor
private class TabBarMenuPreviewBaseController: UITabBarController, TabBarMenuDelegate, TabBarMenuPreviewContent {
    weak var viewModel: TabBarMenuPreviewViewModel?
    fileprivate var hasAppliedContent = false
    private let replacementMoreDelegate = PreviewMoreNavigationDelegate()
    private let initialMoreDelegate = PreviewMoreNavigationDelegate()

    override func viewDidLoad() {
        super.viewDidLoad()
        if UITestConfiguration.replacesMoreDelegate {
            initialMoreDelegate.willShow = { [weak self] navigation, shown in
                guard let self, shown === navigation.viewControllers.first else { return }
                navigation.delegate = self.replacementMoreDelegate
                self.viewModel?.navigationStatus = "More delegate replaced"
            }
            replacementMoreDelegate.didShow = { [weak self] shown in
                self?.viewModel?.navigationStatus = "Forwarded: \(shown.title ?? "More")"
            }
        }
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyPreviewTabs(_ previewTabs: [PreviewTab], showsSearchTab: Bool) {
        preconditionFailure("Override in subclass.")
    }

    fileprivate func prepareNativeMoreDelegateTest() {
        moreNavigationController.delegate = initialMoreDelegate
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        prepareFor interaction: TabBarInteraction,
        on item: TabBarItem
    ) -> TabBarMenuPresentation? { nil }

    func tabBarController(
        _ controller: UITabBarController,
        didSelect tab: UITab,
        previousTab: UITab?,
        isOverflow: Bool
    ) {
        viewModel?.recordSelection(title: tab.title, isReselection: tab === previousTab, isOverflow: isOverflow)
    }

    func tabBarController(
        _ controller: UITabBarController,
        didSelect viewController: UIViewController,
        previousViewController: UIViewController?,
        isOverflow: Bool
    ) {
        viewModel?.recordSelection(
            title: viewController.title ?? "Tab",
            isReselection: viewController === previousViewController,
            isOverflow: isOverflow
        )
    }

    fileprivate func makeMenu(title: String, deleteHandler: @escaping () -> Void) -> UIMenu {
        let rename = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in }
        let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
            deleteHandler()
        }
        return UIMenu(title: title, children: [rename, delete])
    }

    fileprivate func makeUITab(_ tab: PreviewTab) -> UITab {
        UITab(title: tab.title, image: UIImage(systemName: tab.systemImageName), identifier: tab.identifier) { _ in
            let controller = UIHostingController(
                rootView: SampleTabView(title: tab.title, systemImage: tab.systemImageName)
            )
            controller.title = tab.title
            return controller
        }
    }

    fileprivate func makeSearchUITab() -> UISearchTab {
        UISearchTab { _ in
            let controller = UIHostingController(
                rootView: SampleTabView(title: "Search", systemImage: "magnifyingglass")
            )
            controller.title = "Search"
            return controller
        }
    }

    fileprivate func makeViewController(_ tab: PreviewTab) -> UIViewController {
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

    fileprivate func makeSearchViewController() -> UIViewController {
        let controller = UIHostingController(
            rootView: SampleTabView(title: "Search", systemImage: "magnifyingglass")
        )
        controller.title = "Search"
        controller.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: 0)
        return controller
    }
}

@MainActor
private final class TabBarMenuPreviewUITabController: TabBarMenuPreviewBaseController {
    override func applyPreviewTabs(_ previewTabs: [PreviewTab], showsSearchTab: Bool) {
        var updatedTabs = previewTabs.map { makeUITab($0) }
        if showsSearchTab {
            updatedTabs.append(makeSearchUITab())
        }
        let shouldAnimate = hasAppliedContent && !UITestConfiguration.isEnabled
        setTabs(updatedTabs, animated: shouldAnimate)
        hasAppliedContent = true
    }

    override func tabBarController(
        _ tabBarController: UITabBarController,
        prepareFor interaction: TabBarInteraction,
        on item: TabBarItem
    ) -> TabBarMenuPresentation? {
        let menu: UIMenu
        switch item {
        case .tab(let tab):
            guard interaction == .longPress else { return nil }
            menu = makeMenu(title: tab.title) { [weak self] in
                self?.viewModel?.deleteTab(tab)
            }
        case .more(let tabs, let selectedTab):
            if UITestConfiguration.replacesMoreDelegate, interaction == .tap {
                if selectedTab == nil { prepareNativeMoreDelegateTest() }
                return nil
            }
            if interaction == .tap, selectedTab != nil { return nil }
            menu = UIMenu(children: tabs.map { tabBarController.selectionAction(for: $0) })
        case .viewController, .moreViewControllers:
            return nil
        }
        return .init(menu: menu, preferredMenuElementOrder: .fixed)
    }

}

@MainActor
private final class TabBarMenuPreviewViewControllerController: TabBarMenuPreviewBaseController {
    override func applyPreviewTabs(_ previewTabs: [PreviewTab], showsSearchTab: Bool) {
        var updatedViewControllers = previewTabs.map { makeViewController($0) }
        if showsSearchTab {
            updatedViewControllers.append(makeSearchViewController())
        }
        let shouldAnimate = hasAppliedContent && !UITestConfiguration.isEnabled
        setViewControllers(updatedViewControllers, animated: shouldAnimate)
        hasAppliedContent = true
    }

    override func tabBarController(
        _ tabBarController: UITabBarController,
        prepareFor interaction: TabBarInteraction,
        on item: TabBarItem
    ) -> TabBarMenuPresentation? {
        let menu: UIMenu
        switch item {
        case .viewController(let controller):
            guard interaction == .longPress else { return nil }
            menu = makeMenu(title: controller.title ?? controller.tabBarItem.title ?? "") { [weak self] in
                self?.viewModel?.deleteTab(controller)
            }
        case .moreViewControllers(let controllers, let selected):
            if UITestConfiguration.replacesMoreDelegate, interaction == .tap {
                if selected == nil { prepareNativeMoreDelegateTest() }
                return nil
            }
            if interaction == .tap, selected != nil { return nil }
            menu = UIMenu(children: controllers.map { tabBarController.selectionAction(for: $0) })
        case .tab, .more:
            return nil
        }
        return .init(menu: menu, preferredMenuElementOrder: .fixed)
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

@MainActor
private final class PreviewMoreNavigationDelegate: NSObject, UINavigationControllerDelegate {
    var willShow: ((UINavigationController, UIViewController) -> Void)?
    var didShow: ((UIViewController) -> Void)?

    func navigationController(_ navigation: UINavigationController, willShow controller: UIViewController, animated: Bool) {
        willShow?(navigation, controller)
    }

    func navigationController(_ navigation: UINavigationController, didShow controller: UIViewController, animated: Bool) {
        didShow?(controller)
    }
}

private struct SampleTabView: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
                    .accessibilityIdentifier("sample-tab-title")
            } icon: {
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

    func updateUIViewController(_ uiViewController: TabBarMenuPreviewContainerController, context: Context) {
        viewModel.register(uiViewController)
        viewModel.updateMode(mode)
    }
}

public struct TabBarMenuPreviewScreen: View {
    private let mode: TabBarMenuPreviewMode
    @State private var viewModel = TabBarMenuPreviewViewModel()

    public init(mode: TabBarMenuPreviewMode) {
        self.mode = mode
    }

    public var body: some View {
        TabBarMenuPreviewRepresentable(mode: mode, viewModel: viewModel)
            .ignoresSafeArea()
            .safeAreaInset(edge: .top) {
                if UITestConfiguration.replacesMoreDelegate {
                    Text(viewModel.navigationStatus)
                        .accessibilityIdentifier("navigation-status")
                }
                Text(viewModel.selectionStatus)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.background)
                    .accessibilityIdentifier("selection-status")
            }
            .toolbar {
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

#if DEBUG
#Preview("TabBarMenu UITab") {
    NavigationStack {
        TabBarMenuPreviewScreen(mode: .uiTab)
    }
}

#Preview("TabBarMenu UITabBarItem") {
    NavigationStack {
        TabBarMenuPreviewScreen(mode: .uiTabBarItem)
    }
}
#endif
