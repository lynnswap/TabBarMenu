import UIKit
import Combine

@MainActor
final class TabBarMenuCoordinator: NSObject, UIGestureRecognizerDelegate {
    private enum MenuSource: CaseIterable {
        case tabs
        case viewControllers
    }

    private struct PresentationContext {
        let containerView: UIView
        let tabFrame: CGRect
    }

    private struct MenuPlan {
        let menu: UIMenu
        let placement: TabBarMenuAnchorPlacement?
        let hostButton: UIButton
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
        detach()
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
        guard let tabBarController else {
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
        if let updatedMenu {
            menuHostButton.contextMenuInteraction?.updateVisibleMenu { _ in
                updatedMenu
            }
        }
        return true
    }

    // MARK: - Observation

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

    // MARK: - Selection handling

    private func refreshSelectionHandler() {
        guard let tabBarController else {
            return
        }
        let tabBar = tabBarController.tabBar
        tabBar.tabBarMenuSelectionHandler = { [weak self, weak tabBarController] _, item in
            guard let self, let tabBarController else { return true }
            // Return false to cancel system selection when we presented a More menu.
            return self.handleMoreSelection(item, in: tabBarController) == false
        }
    }

    private func uninstallSelectionHandler(from tabBarController: UITabBarController) {
        tabBarController.tabBar.tabBarMenuSelectionHandler = nil
    }

    // MARK: - Gestures

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
            for recognizer in recognizers where recognizer is TabBarMenuLongPressGestureRecognizer {
                control.removeGestureRecognizer(recognizer)
            }
        }
    }

    // MARK: - Menu presentation

    private func makePresentationContext(for sourceView: UIView, in tabBarController: UITabBarController) -> PresentationContext? {
        guard let containerView = tabBarController.view ?? sourceView.window?.rootViewController?.view else {
            return nil
        }
        let tabFrame = sourceView.convert(sourceView.bounds, to: containerView)
        return PresentationContext(containerView: containerView, tabFrame: tabFrame)
    }

    private func makeMenuPlan(
        for tabIndex: Int,
        in tabBarController: UITabBarController,
        context: PresentationContext
    ) -> MenuPlan? {
        // 1) Prefer the system More tab menu for tabs.
        if isMoreTabIndex(tabIndex, in: tabBarController, source: .tabs),
           let menu = menuForMoreTab(in: tabBarController, source: .tabs) {
            let hostButton = makeMenuHostButton(in: context.containerView)
            return MenuPlan(menu: menu, placement: nil, hostButton: hostButton)
        }

        // 2) Prefer the system More tab menu for view controllers.
        if isMoreTabIndex(tabIndex, in: tabBarController, source: .viewControllers),
           let menu = menuForMoreTab(in: tabBarController, source: .viewControllers) {
            let hostButton = makeMenuHostButton(in: context.containerView)
            return MenuPlan(menu: menu, placement: nil, hostButton: hostButton)
        }

        // 3) Per-item menu using UITab (iOS 18+ API).
        if let tab = tabForMenu(at: tabIndex, in: tabBarController),
           let menu = delegate?.tabBarController(tabBarController, tab: tab) {
            let hostButton = makeMenuHostButton(in: context.containerView)
            let placement = delegate?.tabBarController(
                tabBarController,
                configureMenuPresentationFor: tab,
                tabFrame: context.tabFrame,
                in: context.containerView,
                menuHostButton: hostButton
            )
            return MenuPlan(menu: menu, placement: placement, hostButton: hostButton)
        }

        // 4) Per-item menu using UIViewController API.
        if let viewController = viewControllerForMenu(at: tabIndex, in: tabBarController),
           let menu = delegate?.tabBarController(tabBarController, viewController: viewController) {
            let hostButton = makeMenuHostButton(in: context.containerView)
            let placement = delegate?.tabBarController(
                tabBarController,
                configureMenuPresentationFor: viewController,
                tabFrame: context.tabFrame,
                in: context.containerView,
                menuHostButton: hostButton
            )
            return MenuPlan(menu: menu, placement: placement, hostButton: hostButton)
        }

        return nil
    }

    private func presentPlannedMenu(_ plan: MenuPlan, context: PresentationContext, sourceView: UIView) {
        presentMenu(
            plan.menu,
            tabFrame: context.tabFrame,
            in: context.containerView,
            placement: plan.placement,
            hostButton: plan.hostButton,
            sourceView: sourceView
        )
    }

    private func presentMenu(from button: UIButton) {
        button.performPrimaryAction()
    }

    private func presentMenu(
        _ menu: UIMenu,
        tabFrame: CGRect,
        in _: UIView,
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
            anchorPoint = CGPoint(x: tabFrame.midX, y: (tabFrame.maxY + tabFrame.midY) * 0.5)
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

    // MARK: - Tab bar view discovery

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

        let isRTL = tabBar.effectiveUserInterfaceLayoutDirection == .rightToLeft
        // Match the visual order so indices align with items in RTL.
        let sortedControls = controls.sorted { left, right in
            let leftFrame = left.convert(left.bounds, to: tabBar)
            let rightFrame = right.convert(right.bounds, to: tabBar)
            if isRTL {
                return leftFrame.minX > rightFrame.minX
            }
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

    // MARK: - More tab indexing & item extraction

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

    private func moreTabIndex(in tabBarController: UITabBarController, source: MenuSource) -> Int? {
        moreTabStartIndex(totalCount: totalCount(in: tabBarController, source: source))
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
        configuration.minimumPressDuration
    }

    private func itemForMenu<T>(at index: Int, in items: [T]) -> T? {
        guard !items.isEmpty else {
            return nil
        }
        guard items.indices.contains(index), isMoreTabIndex(index, totalCount: items.count) == false else {
            return nil
        }
        return items[index]
    }

    private func moreItems<T>(from items: [T]) -> [T] {
        guard let startIndex = moreTabStartIndex(totalCount: items.count),
              items.indices.contains(startIndex) else {
            return []
        }
        return Array(items[startIndex...])
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
        // If we can't find it, be conservative and treat it as the More tab.
        return true
    }

    private func tabForMenu(at index: Int, in tabBarController: UITabBarController) -> UITab? {
        itemForMenu(at: index, in: tabBarController.tabs)
    }

    private func viewControllerForMenu(at index: Int, in tabBarController: UITabBarController) -> UIViewController? {
        itemForMenu(at: index, in: tabBarController.viewControllers ?? [])
    }

    private func menuForMoreTab(in tabBarController: UITabBarController, source: MenuSource) -> UIMenu? {
        guard let delegate else {
            return nil
        }

        switch source {
        case .tabs:
            let tabs = moreItems(from: tabBarController.tabs)
            guard !tabs.isEmpty else {
                return nil
            }
            return delegate.tabBarController(tabBarController, menuForMoreTabWith: tabs)

        case .viewControllers:
            let viewControllers = moreItems(from: tabBarController.viewControllers ?? [])
            guard !viewControllers.isEmpty else {
                return nil
            }
            return delegate.tabBarController(tabBarController, menuForMoreTabWith: viewControllers)
        }
    }

    // MARK: - More tab selection

    private func presentMenuForMoreTab(
        _ menu: UIMenu,
        source: MenuSource,
        in tabBarController: UITabBarController
    ) -> Bool {
        guard let sourceView = moreTabView(in: tabBarController, source: source),
              let context = makePresentationContext(for: sourceView, in: tabBarController) else {
            return false
        }

        let hostButton = makeMenuHostButton(in: context.containerView)
        presentMenu(
            menu,
            tabFrame: context.tabFrame,
            in: context.containerView,
            placement: nil,
            hostButton: hostButton,
            sourceView: sourceView
        )
        return true
    }

    private func presentMoreMenu(source: MenuSource, in tabBarController: UITabBarController) -> Bool {
        guard let menu = menuForMoreTab(in: tabBarController, source: source) else {
            return false
        }
        return presentMenuForMoreTab(menu, source: source, in: tabBarController)
    }

    fileprivate func handleMoreSelection(_ viewController: UIViewController, in tabBarController: UITabBarController) -> Bool {
        guard isMoreViewController(viewController, in: tabBarController) else {
            return false
        }
        return presentMoreMenu(source: .viewControllers, in: tabBarController)
    }

    fileprivate func handleMoreSelection(_ tab: UITab, in tabBarController: UITabBarController) -> Bool {
        guard isMoreTab(tab, in: tabBarController) else {
            return false
        }
        return presentMoreMenu(source: .tabs, in: tabBarController)
    }

    fileprivate func handleMoreSelection(_ item: UITabBarItem, in tabBarController: UITabBarController) -> Bool {
        for source in MenuSource.allCases {
            if handleMoreSelection(item, in: tabBarController, source: source) {
                return true
            }
        }
        return false
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
        return presentMoreMenu(source: source, in: tabBarController)
    }

    // MARK: - Long press

    private func handleMenuTrigger(tabIndex: Int, sourceView: UIView, in tabBarController: UITabBarController) {
        guard let context = makePresentationContext(for: sourceView, in: tabBarController) else {
            return
        }
        guard let plan = makeMenuPlan(for: tabIndex, in: tabBarController, context: context) else {
            return
        }
        presentPlannedMenu(plan, context: context, sourceView: sourceView)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              let view = recognizer.view,
              let tabBarController,
              let longPressRecognizer = recognizer as? TabBarMenuLongPressGestureRecognizer else {
            return
        }
        handleMenuTrigger(tabIndex: longPressRecognizer.tabIndex, sourceView: view, in: tabBarController)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    // MARK: - Private API helpers

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
        false
    }
}
