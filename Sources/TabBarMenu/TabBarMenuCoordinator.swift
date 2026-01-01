import UIKit
import Combine

@MainActor
final class TabBarMenuCoordinator: NSObject, UIGestureRecognizerDelegate {
    private enum MenuSource {
        case tabs
        case viewControllers
    }

    weak var delegate: TabBarMenuDelegate?
    var configuration: TabBarMenuConfiguration = .init() {
        didSet {
            guard oldValue != configuration else { return }
            refreshInteractions()
        }
    }
    private weak var tabBarController: UITabBarController?
    private var menuHostButton: UIButton?
    private var cancellables = Set<AnyCancellable>()

    @MainActor deinit {
        stopObservingTabs()
    }

    func attach(to tabBarController: UITabBarController) {
        if self.tabBarController !== tabBarController {
            if let previousController = self.tabBarController {
                stopObservingTabs()
                let tabBar = previousController.tabBar
                removeMenuGestures(from: tabBar)
                uninstallSelectionHandler(from: previousController)
            }
            menuHostButton?.removeFromSuperview()
            menuHostButton = nil
            self.tabBarController = tabBarController
            startObservingTabs()
        }
        refreshInteractions()
    }

    func detach() {
        stopObservingTabs()
        if let tabBar = tabBarController?.tabBar {
            removeMenuGestures(from: tabBar)
        }
        if let tabBarController {
            uninstallSelectionHandler(from: tabBarController)
        }
        menuHostButton?.removeFromSuperview()
        menuHostButton = nil
        tabBarController = nil
    }

    func refreshInteractions() {
        guard let tabBarController = tabBarController else {
            return
        }
        refreshSelectionHandler()
        let tabBar = tabBarController.tabBar
        removeMenuGestures(from: tabBar)
        for (index, view) in tabBarIndexedViews(in: tabBar) {
            let duration = longPressDuration(for: index, in: tabBarController)
            addLongPress(to: view, tabIndex: index, minimumPressDuration: duration)
        }
    }

    @discardableResult
    func updateVisibleMenu(_ update: (UIMenu?) -> UIMenu?) -> Bool {
        guard let menuHostButton else {
            return false
        }
        let updatedMenu = update(menuHostButton.menu)
        menuHostButton.menu = updatedMenu
        if let updatedMenu{
            menuHostButton.contextMenuInteraction?.updateVisibleMenu { _ in
                updatedMenu
            }
        }
        return true
    }

    private func startObservingTabs() {
        guard let tabBarController = tabBarController, cancellables.isEmpty else {
            return
        }
        tabBarController.tabBar.itemsDidChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshInteractions()
            }
            .store(in: &cancellables)
    }

    private func stopObservingTabs() {
        cancellables.removeAll()
    }

    private func refreshSelectionHandler() {
        guard let tabBarController else {
            return
        }
        let tabBar = tabBarController.tabBar
        tabBar.tabBarMenuSelectionHandler = { [weak self, weak tabBarController] _, item in
            guard let self, let tabBarController else { return true }
            return self.handleMoreSelection(item, in: tabBarController) == false
        }
    }

    private func uninstallSelectionHandler(from tabBarController: UITabBarController) {
        tabBarController.tabBar.tabBarMenuSelectionHandler = nil
    }

    private func addLongPress(to view: UIView, tabIndex: Int, minimumPressDuration: TimeInterval) {
        let recognizer = TabBarMenuLongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        recognizer.tabIndex = tabIndex
        recognizer.minimumPressDuration = minimumPressDuration
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = self
        view.addGestureRecognizer(recognizer)
    }

    private func removeMenuGestures(from tabBar: UITabBar) {
        for control in tabBarControls(in: tabBar) {
            guard let recognizers = control.gestureRecognizers else {
                continue
            }
            for recognizer in recognizers {
                guard recognizer is TabBarMenuLongPressGestureRecognizer else {
                    continue
                }
                control.removeGestureRecognizer(recognizer)
            }
        }
    }

    private func presentMenu(from button: UIButton) {
        button.performPrimaryAction()
    }

    private func presentMenu(
        _ menu: UIMenu,
        tabFrame: CGRect,
        in containerView: UIView,
        placement: TabBarMenuAnchorPlacement?,
        hostButton: UIButton,
        sourceView: UIView
    ) {
        let defaultPlacement: TabBarMenuAnchorPlacement = {
            if #available(iOS 26.0, *) {
                return .inside
            }
            return .above()
        }()
        let anchorPoint: CGPoint?
        switch placement ?? defaultPlacement {
        case .inside:
            anchorPoint = CGPoint(x: tabFrame.midX, y: ( tabFrame.maxY + tabFrame.midY) * 0.5 )
        case .above(let offset):
            anchorPoint = CGPoint(x: tabFrame.midX, y: tabFrame.minY - offset)
        case .custom(let point):
            anchorPoint = point
        case .manual:
            anchorPoint = nil
        }
        if let anchorPoint {
            let anchorSize: CGFloat = 2
            hostButton.frame = CGRect(
                x: anchorPoint.x - anchorSize / 2,
                y: anchorPoint.y - anchorSize / 2,
                width: anchorSize,
                height: anchorSize
            )
        }
        hostButton.menu = menu
        presentMenu(from: hostButton)
        cancelTabBarTracking(for: sourceView)
    }

    private func cancelTabBarTracking(for view: UIView?) {
        if let control = view as? UIControl {
            control.isHighlighted = false
            control.cancelTracking(with: nil)
            return
        }
        guard let tabBar = tabBarController?.tabBar else {
            return
        }
        let buttons = tabBarControls(in: tabBar)
        for button in buttons {
            button.isHighlighted = false
            button.cancelTracking(with: nil)
        }
    }

    private func tabBarControls(in view: UIView) -> [UIControl] {
        var result: [UIControl] = []
        for subview in view.subviews {
            if let control = subview as? UIControl {
                result.append(control)
            }
            result.append(contentsOf: tabBarControls(in: subview))
        }
        return result
    }

    private func tabBarIndexedViews(in tabBar: UITabBar) -> [(Int, UIView)] {
        guard let items = tabBar.items, !items.isEmpty else {
            return []
        }
        let indexedViews = items.enumerated().compactMap { index, item in
            tabBarItemView(item).map { (index, $0) }
        }
        if indexedViews.count == items.count {
            return indexedViews
        }
        let controls = tabBarFallbackControls(in: tabBar)
        guard !controls.isEmpty else {
            return indexedViews
        }
        let sortedControls = controls.sorted { left, right in
            let leftFrame = left.convert(left.bounds, to: tabBar)
            let rightFrame = right.convert(right.bounds, to: tabBar)
            return leftFrame.minX < rightFrame.minX
        }
        let count = min(sortedControls.count, items.count)
        return sortedControls.prefix(count).enumerated().map { index, view in
            (index, view)
        }
    }

    private func tabBarFallbackControls(in tabBar: UITabBar) -> [UIControl] {
        let controls = tabBarControls(in: tabBar)
        let topLevelControls = controls.filter { $0.superview === tabBar }
        if !topLevelControls.isEmpty {
            return topLevelControls
        }
        return controls
    }

    private func makeMenuHostButton(in containerView: UIView) -> UIButton {
        menuHostButton?.removeFromSuperview()
        let button = MenuHostButton(type: .custom)
        button.backgroundColor = .clear
        button.showsMenuAsPrimaryAction = true
        containerView.addSubview(button)
        menuHostButton = button
        return button
    }

    private func totalCount(in tabBarController: UITabBarController, source: MenuSource) -> Int {
        switch source {
        case .tabs:
            return tabBarController.tabs.count
        case .viewControllers:
            return tabBarController.viewControllers?.count ?? 0
        }
    }

    private func moreTabStartIndex(totalCount: Int) -> Int? {
        let maxVisibleCount = max(configuration.maxVisibleTabCount, 0)
        guard maxVisibleCount > 0, totalCount > maxVisibleCount else {
            return nil
        }
        return maxVisibleCount - 1
    }

    private func isMoreTabIndex(_ index: Int, totalCount: Int) -> Bool {
        guard let startIndex = moreTabStartIndex(totalCount: totalCount) else {
            return false
        }
        return index == startIndex
    }

    private func isMoreTabIndex(_ index: Int, in tabBarController: UITabBarController, source: MenuSource) -> Bool {
        guard let startIndex = moreTabIndex(in: tabBarController, source: source) else {
            return false
        }
        return index == startIndex
    }

    private func longPressDuration(for _: Int, in _: UITabBarController) -> TimeInterval {
        return configuration.minimumPressDuration
    }

    private func moreTabIndex(in tabBarController: UITabBarController, source: MenuSource) -> Int? {
        let totalCount = totalCount(in: tabBarController, source: source)
        return moreTabStartIndex(totalCount: totalCount)
    }

    private func moreTabView(in tabBarController: UITabBarController, source: MenuSource) -> UIView? {
        guard let index = moreTabIndex(in: tabBarController, source: source) else {
            return nil
        }
        let indexedViews = tabBarIndexedViews(in: tabBarController.tabBar)
        return indexedViews.first { $0.0 == index }?.1
    }

    private func isMoreViewController(_ viewController: UIViewController, in tabBarController: UITabBarController) -> Bool {
        let moreNavigationController = tabBarController.moreNavigationController
        if viewController === moreNavigationController {
            return true
        }
        if viewController.tabBarItem === moreNavigationController.tabBarItem {
            return true
        }
        guard let moreIndex = moreTabIndex(in: tabBarController, source: .viewControllers),
              let items = tabBarController.tabBar.items,
              items.indices.contains(moreIndex) else {
            return false
        }
        return viewController.tabBarItem === items[moreIndex]
    }

    private func isMoreTab(_ tab: UITab, in tabBarController: UITabBarController) -> Bool {
        let tabs = tabBarController.tabs
        guard let moreIndex = moreTabStartIndex(totalCount: tabs.count) else {
            return false
        }
        if let index = tabs.firstIndex(where: { $0 === tab }) {
            return index == moreIndex
        }
        return true
    }

    private func tabForMenu(at index: Int, in tabBarController: UITabBarController) -> UITab? {
        let tabs = tabBarController.tabs
        if isMoreTabIndex(index, totalCount: tabs.count) {
            return nil
        }
        guard tabs.indices.contains(index) else {
            return nil
        }
        return tabs[index]
    }

    private func viewControllerForMenu(at index: Int, in tabBarController: UITabBarController) -> UIViewController? {
        guard let viewControllers = tabBarController.viewControllers, !viewControllers.isEmpty else {
            return nil
        }
        if isMoreTabIndex(index, totalCount: viewControllers.count) {
            return nil
        }
        guard viewControllers.indices.contains(index) else {
            return nil
        }
        return viewControllers[index]
    }

    private func moreTabs(in tabBarController: UITabBarController) -> [UITab] {
        let tabs = tabBarController.tabs
        guard let startIndex = moreTabStartIndex(totalCount: tabs.count) else {
            return []
        }
        guard tabs.indices.contains(startIndex) else {
            return []
        }
        return Array(tabs[startIndex...])
    }

    private func moreViewControllers(in tabBarController: UITabBarController) -> [UIViewController] {
        guard let viewControllers = tabBarController.viewControllers, !viewControllers.isEmpty else {
            return []
        }
        guard let startIndex = moreTabStartIndex(totalCount: viewControllers.count) else {
            return []
        }
        guard viewControllers.indices.contains(startIndex) else {
            return []
        }
        return Array(viewControllers[startIndex...])
    }

    private func menuForMoreTab(in tabBarController: UITabBarController, source: MenuSource) -> UIMenu? {
        switch source {
        case .tabs:
            let tabs = moreTabs(in: tabBarController)
            guard !tabs.isEmpty else {
                return nil
            }
            return delegate?.tabBarController(tabBarController, menuForMoreTabWith: tabs)
        case .viewControllers:
            let viewControllers = moreViewControllers(in: tabBarController)
            guard !viewControllers.isEmpty else {
                return nil
            }
            return delegate?.tabBarController(tabBarController, menuForMoreTabWith: viewControllers)
        }
    }

    private func presentMenuForMoreTab(
        _ menu: UIMenu,
        source: MenuSource,
        in tabBarController: UITabBarController
    ) -> Bool {
        guard let sourceView = moreTabView(in: tabBarController, source: source),
              let containerView = tabBarController.view ?? sourceView.window?.rootViewController?.view else {
            return false
        }
        let tabFrame = sourceView.convert(sourceView.bounds, to: containerView)
        let hostButton = makeMenuHostButton(in: containerView)
        presentMenu(
            menu,
            tabFrame: tabFrame,
            in: containerView,
            placement: nil,
            hostButton: hostButton,
            sourceView: sourceView
        )
        return true
    }

    fileprivate func handleMoreSelection(_ viewController: UIViewController, in tabBarController: UITabBarController) -> Bool {
        guard isMoreViewController(viewController, in: tabBarController) else {
            return false
        }
        guard let menu = menuForMoreTab(in: tabBarController, source: .viewControllers) else {
            return false
        }
        return presentMenuForMoreTab(menu, source: .viewControllers, in: tabBarController)
    }

    fileprivate func handleMoreSelection(_ tab: UITab, in tabBarController: UITabBarController) -> Bool {
        guard isMoreTab(tab, in: tabBarController) else {
            return false
        }
        guard let menu = menuForMoreTab(in: tabBarController, source: .tabs) else {
            return false
        }
        return presentMenuForMoreTab(menu, source: .tabs, in: tabBarController)
    }

    fileprivate func handleMoreSelection(_ item: UITabBarItem, in tabBarController: UITabBarController) -> Bool {
        if handleMoreSelection(item, in: tabBarController, source: .tabs) {
            return true
        }
        return handleMoreSelection(item, in: tabBarController, source: .viewControllers)
    }

    private func handleMoreSelection(
        _ item: UITabBarItem,
        in tabBarController: UITabBarController,
        source: MenuSource
    ) -> Bool {
        guard let items = tabBarController.tabBar.items,
              let index = items.firstIndex(where: { $0 === item }),
              isMoreTabIndex(index, in: tabBarController, source: source) else {
            return false
        }
        guard let menu = menuForMoreTab(in: tabBarController, source: source) else {
            return false
        }
        return presentMenuForMoreTab(menu, source: source, in: tabBarController)
    }

    private func handleMenuTrigger(tabIndex: Int, sourceView: UIView, in tabBarController: UITabBarController) {
        guard let containerView = tabBarController.view ?? sourceView.window?.rootViewController?.view else {
            return
        }
        let tabFrame = sourceView.convert(sourceView.bounds, to: containerView)
        if isMoreTabIndex(tabIndex, in: tabBarController, source: .tabs),
           let menu = menuForMoreTab(in: tabBarController, source: .tabs) {
            let hostButton = makeMenuHostButton(in: containerView)
            presentMenu(
                menu,
                tabFrame: tabFrame,
                in: containerView,
                placement: nil,
                hostButton: hostButton,
                sourceView: sourceView
            )
            return
        }
        if isMoreTabIndex(tabIndex, in: tabBarController, source: .viewControllers),
           let menu = menuForMoreTab(in: tabBarController, source: .viewControllers) {
            let hostButton = makeMenuHostButton(in: containerView)
            presentMenu(
                menu,
                tabFrame: tabFrame,
                in: containerView,
                placement: nil,
                hostButton: hostButton,
                sourceView: sourceView
            )
            return
        }
        let tab = tabForMenu(at: tabIndex, in: tabBarController)
        if let tab, let menu = delegate?.tabBarController(tabBarController, tab: tab) {
            let hostButton = makeMenuHostButton(in: containerView)
            let placement = delegate?.tabBarController(
                tabBarController,
                configureMenuPresentationFor: tab,
                tabFrame: tabFrame,
                in: containerView,
                menuHostButton: hostButton
            )
            presentMenu(
                menu,
                tabFrame: tabFrame,
                in: containerView,
                placement: placement,
                hostButton: hostButton,
                sourceView: sourceView
            )
            return
        }
        let viewController = viewControllerForMenu(at: tabIndex, in: tabBarController)
        if let viewController, let menu = delegate?.tabBarController(tabBarController, viewController: viewController) {
            let hostButton = makeMenuHostButton(in: containerView)
            let placement = delegate?.tabBarController(
                tabBarController,
                configureMenuPresentationFor: viewController,
                tabFrame: tabFrame,
                in: containerView,
                menuHostButton: hostButton
            )
            presentMenu(
                menu,
                tabFrame: tabFrame,
                in: containerView,
                placement: placement,
                hostButton: hostButton,
                sourceView: sourceView
            )
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              let view = recognizer.view,
              let tabBarController = tabBarController,
              let longPressRecognizer = recognizer as? TabBarMenuLongPressGestureRecognizer else {
            return
        }
        handleMenuTrigger(tabIndex: longPressRecognizer.tabIndex, sourceView: view, in: tabBarController)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    private func tabBarItemView(_ item: UITabBarItem) -> UIView? {
        if let view = performSelector("view", on: item) as? UIView {
            return view
        }
        return nil
    }

    private func performSelector(_ name: String, on object: NSObject) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else {
            return nil
        }
        return object.perform(selector)?.takeUnretainedValue()
    }
}

@MainActor
final class TabBarMenuLongPressGestureRecognizer: UILongPressGestureRecognizer {
    var tabIndex: Int = 0
}

private final class MenuHostButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return false
    }
}
