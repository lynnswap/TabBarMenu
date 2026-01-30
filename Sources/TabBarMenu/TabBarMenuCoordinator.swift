import UIKit
import Combine

@MainActor
final class TabBarMenuCoordinator: NSObject, UIGestureRecognizerDelegate {
    private struct MoreMenuPresentation {
        let menu: UIMenu
        let sourceView: UIView
    }

    private final class MenuPresentationRequest {
        weak var tabBarController: UITabBarController?
        weak var sourceView: UIView?
        let menu: UIMenu
        let placementProvider: (PresentationContext, UIButton) -> TabBarMenuAnchorPlacement?

        init(
            tabBarController: UITabBarController?,
            sourceView: UIView?,
            menu: UIMenu,
            placementProvider: @escaping (PresentationContext, UIButton) -> TabBarMenuAnchorPlacement?
        ) {
            self.tabBarController = tabBarController
            self.sourceView = sourceView
            self.menu = menu
            self.placementProvider = placementProvider
        }
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
    private var menuPresentationTask: Task<Void, Never>?

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
            resetMenuPresentationState()
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
        resetMenuPresentationState()
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
            let requestCore = self.makeRequestCore()
            guard let request = self.moreMenuRequest(using: requestCore) else {
                return true
            }
            // Return false to cancel system selection when we presented a More menu.
            return self.handleMoreSelection(item, in: tabBarController, request: request) == false
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

    // Present the menu only when no tab transition is active.
    private func scheduleMenuPresentation(_ request: MenuPresentationRequest) {
        cancelMenuPresentationTasks()
        menuPresentationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            presentMenuWhenStable(request)
        }
    }

    private func presentMenuWhenStable(_ request: MenuPresentationRequest) {
        guard !Task.isCancelled,
              let tabBarController = request.tabBarController,
              let sourceView = request.sourceView else {
            return
        }
        guard let context = makePresentationContext(for: sourceView, in: tabBarController),
              context.containerView.window != nil else {
            return
        }
        guard !Task.isCancelled else {
            return
        }
        let hostButton = makeMenuHostButton(in: context.containerView)
        let placement = request.placementProvider(context, hostButton)
        guard !Task.isCancelled else {
            return
        }
        guard tabBarController.transitionCoordinator == nil else {
            hostButton.removeFromSuperview()
            if menuHostButton === hostButton {
                menuHostButton = nil
            }
            return
        }
        presentMenu(
            request.menu,
            tabFrame: context.tabFrame,
            in: context.containerView,
            placement: placement,
            hostButton: hostButton,
            sourceView: sourceView
        )
    }

    private func resetMenuPresentationState() {
        cancelMenuPresentationTasks()
    }

    private func cancelMenuPresentationTasks() {
        menuPresentationTask?.cancel()
        menuPresentationTask = nil
    }

    private func makeMenuPlan(
        for tabIndex: Int,
        in tabBarController: UITabBarController
    ) -> MenuPlan? {
        guard let delegate else {
            return nil
        }
        let requestCore = makeRequestCore()
        if let request = moreMenuRequest(using: requestCore),
           let plan = makeMoreMenuPlan(
            for: tabIndex,
            in: tabBarController,
            request: request,
            delegate: delegate
           ) {
            return plan
        }
        guard let request = itemMenuRequest(using: requestCore) else {
            return nil
        }
        return makeItemMenuPlan(
            for: tabIndex,
            in: tabBarController,
            request: request,
            delegate: delegate
        )
    }

    private func makeMoreMenuPlan(
        for tabIndex: Int,
        in tabBarController: UITabBarController,
        request: MoreMenuRequest,
        delegate: TabBarMenuDelegate
    ) -> MenuPlan? {
        guard request.isMoreTabIndex(tabIndex, in: tabBarController),
              let menu = request.menu(in: tabBarController, delegate: delegate) else {
            return nil
        }
        let placementProvider: (PresentationContext, UIButton) -> TabBarMenuAnchorPlacement? = { [weak delegate, weak tabBarController] context, hostButton in
            guard let delegate, let tabBarController else { return nil }
            return request.menuPresentationPlacement(
                in: tabBarController,
                presentationContext: context,
                hostButton: hostButton,
                delegate: delegate
            )
        }
        return MenuPlan(menu: menu, placementProvider: placementProvider)
    }

    private func makeItemMenuPlan(
        for tabIndex: Int,
        in tabBarController: UITabBarController,
        request: ItemMenuRequest,
        delegate: TabBarMenuDelegate
    ) -> MenuPlan? {
        guard let menu = request.menu(
            forItemAt: tabIndex,
            in: tabBarController,
            delegate: delegate
        ) else {
            return nil
        }
        let placementProvider: (PresentationContext, UIButton) -> TabBarMenuAnchorPlacement? = { [weak delegate, weak tabBarController] context, hostButton in
            guard let delegate, let tabBarController else { return nil }
            return request.menuPresentationPlacement(
                forItemAt: tabIndex,
                in: tabBarController,
                presentationContext: context,
                hostButton: hostButton,
                delegate: delegate
            )
        }
        return MenuPlan(menu: menu, placementProvider: placementProvider)
    }

    private func presentPlannedMenu(_ plan: MenuPlan, sourceView: UIView, in tabBarController: UITabBarController) {
        let request = MenuPresentationRequest(
            tabBarController: tabBarController,
            sourceView: sourceView,
            menu: plan.menu,
            placementProvider: plan.placementProvider
        )
        scheduleMenuPresentation(request)
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

    // MARK: - Request helpers

    private func makeRequestCore() -> TabBarMenuRequestCore {
        TabBarMenuRequestCore(configuration: configuration)
    }

    private func longPressDuration(for _: Int, in _: UITabBarController) -> TimeInterval {
        configuration.minimumPressDuration
    }

    private func moreTabView(in tabBarController: UITabBarController, moreTabIndex: Int) -> UIView? {
        let indexedViews = tabBarIndexedViews(in: tabBarController.tabBar)
        return indexedViews.first { $0.0 == moreTabIndex }?.1
    }

    private func moreMenuRequest(using requestCore: TabBarMenuRequestCore) -> MoreMenuRequest? {
        MoreMenuRequest.make(delegate: delegate, core: requestCore)
    }

    private func itemMenuRequest(using requestCore: TabBarMenuRequestCore) -> ItemMenuRequest? {
        ItemMenuRequest.make(delegate: delegate, core: requestCore)
    }

    // MARK: - More tab selection

    private func makeMoreMenuPresentation(
        in tabBarController: UITabBarController,
        request: MoreMenuRequest,
        delegate: TabBarMenuContentDelegate
    ) -> MoreMenuPresentation? {
        guard let menu = request.menu(in: tabBarController, delegate: delegate),
              let moreTabIndex = request.moreTabStartIndex(in: tabBarController),
              let sourceView = moreTabView(in: tabBarController, moreTabIndex: moreTabIndex) else {
            return nil
        }
        return MoreMenuPresentation(
            menu: menu,
            sourceView: sourceView
        )
    }

    private func scheduleMoreMenuPresentation(request: MoreMenuRequest, in tabBarController: UITabBarController) -> Bool {
        guard let delegate else {
            return false
        }
        guard let presentation = makeMoreMenuPresentation(
            in: tabBarController,
            request: request,
            delegate: delegate
        ) else {
            return false
        }
        let placementProvider: (PresentationContext, UIButton) -> TabBarMenuAnchorPlacement? = { [weak delegate, weak tabBarController] context, hostButton in
            guard let delegate, let tabBarController else { return nil }
            return request.menuPresentationPlacement(
                in: tabBarController,
                presentationContext: context,
                hostButton: hostButton,
                delegate: delegate
            )
        }
        let menuRequest = MenuPresentationRequest(
            tabBarController: tabBarController,
            sourceView: presentation.sourceView,
            menu: presentation.menu,
            placementProvider: placementProvider
        )
        scheduleMenuPresentation(menuRequest)
        return true
    }

    private func handleMoreSelection(
        _ item: UITabBarItem,
        in tabBarController: UITabBarController,
        request: MoreMenuRequest? = nil
    ) -> Bool {
        guard let request = request ?? moreMenuRequest(using: makeRequestCore()) else {
            return false
        }
        guard request.matches(item: item, in: tabBarController) else {
            return false
        }
        return scheduleMoreMenuPresentation(request: request, in: tabBarController)
    }

    // MARK: - Long press

    private func handleMenuTrigger(tabIndex: Int, sourceView: UIView, in tabBarController: UITabBarController) {
        guard let plan = makeMenuPlan(for: tabIndex, in: tabBarController) else {
            return
        }
        presentPlannedMenu(plan, sourceView: sourceView, in: tabBarController)
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
