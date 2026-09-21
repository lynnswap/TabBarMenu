import UIKit

func tabBarMenuAnchorFrame(
    tabFrame: CGRect,
    placement: TabBarMenuAnchorPlacement?
) -> CGRect? {
    let anchorPoint: CGPoint?
    switch placement ?? .above() {
    case .inside:
        anchorPoint = CGPoint(x: tabFrame.midX, y: (tabFrame.maxY + tabFrame.midY) * 0.5)
    case .above(let offset):
        anchorPoint = CGPoint(x: tabFrame.midX, y: tabFrame.minY - offset)
    case .custom(let point):
        anchorPoint = point
    }

    guard let anchorPoint else {
        return nil
    }

    let anchorSize: CGFloat = 2
    return CGRect(
        x: anchorPoint.x - anchorSize / 2,
        y: anchorPoint.y - anchorSize / 2,
        width: anchorSize,
        height: anchorSize
    )
}

@MainActor
final class TabBarMenuCoordinator: NSObject, UIGestureRecognizerDelegate {
    private struct GestureSyncEntry: Equatable {
        let viewID: ObjectIdentifier
        let tabIndex: Int
        let minimumPressDuration: TimeInterval
    }

    weak var delegate: TabBarMenuDelegate?
    var configuration: TabBarMenuConfiguration = .init() {
        didSet {
            guard oldValue != configuration else { return }
            refreshInteractions()
        }
    }

    private weak var tabBarController: UITabBarController?
    private var tabBarControllerDelegateProxy: TabBarMenuTabBarControllerDelegateProxy?
    private var moreNavigationDelegateProxy: TabBarMenuMoreNavigationDelegateProxy?
    private var pendingMoreSelection: (viewController: UIViewController, content: TabBarContent, previous: TabBarContent?)?
    private var menuHostButton: UIButton?
    private var lastGestureSyncEntries: [GestureSyncEntry] = []
    private var programmaticSelectionDepth = 0
    private var pendingSelection: (content: TabBarContent?, previous: TabBarContent?)?

    @MainActor deinit {
        detach()
    }

    func attach(to tabBarController: UITabBarController) {
        if self.tabBarController !== tabBarController {
            if let previousController = self.tabBarController {
                let tabBar = previousController.tabBar
                tabBar.tabBarMenuLayoutHandler = nil
                removeMenuGestures(from: tabBar)
                uninstallSelectionHandler(from: previousController)
                uninstallDelegateProxy(from: previousController)
                _ = previousController.dismissTabBarMenuTransientOverflowIfNeeded()
            }
            lastGestureSyncEntries = []
            menuHostButton?.removeFromSuperview()
            menuHostButton = nil
            self.tabBarController = tabBarController
        }
        installRuntimeBridges(on: tabBarController)
        refreshInteractions()
    }

    func detach() {
        if let tabBar = tabBarController?.tabBar {
            tabBar.tabBarMenuLayoutHandler = nil
            removeMenuGestures(from: tabBar)
        }
        if let tabBarController {
            uninstallSelectionHandler(from: tabBarController)
            uninstallDelegateProxy(from: tabBarController)
            _ = tabBarController.dismissTabBarMenuTransientOverflowIfNeeded()
        }
        lastGestureSyncEntries = []
        menuHostButton?.removeFromSuperview()
        menuHostButton = nil
        tabBarController = nil
        pendingSelection = nil
        pendingMoreSelection = nil
    }

    func refreshInteractions() {
        guard let tabBarController else {
            return
        }
        installDelegateProxy(on: tabBarController)
        tabBarController.dismissInvalidTabBarMenuTransientOverflowIfNeeded()
        synchronizeMenuGestures(in: tabBarController)
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

    // MARK: - Selection handling

    private func installRuntimeBridges(on tabBarController: UITabBarController) {
        installDelegateProxy(on: tabBarController)
        let tabBar = tabBarController.tabBar
        tabBar.tabBarMenuLayoutHandler = { [weak self] tabBar in
            guard let self,
                  let currentTabBarController = self.tabBarController,
                  currentTabBarController.tabBar === tabBar else {
                return
            }
            self.refreshInteractions()
        }
        tabBar.tabBarMenuSelectionHandler = { [weak self, weak tabBarController] _, item in
            guard let self, let tabBarController,
                  let index = tabBarController.tabBar.items?.firstIndex(where: { $0 === item }),
                  let sourceView = self.tabBarIndexedViews(in: tabBarController.tabBar)
                    .first(where: { $0.0 == index })?.1 else { return true }
            return self.handleInteraction(.tap, at: index, sourceView: sourceView)
        }
        tabBar.tabBarMenuControlSelectionHandler = { [weak self, weak tabBarController] tabBar, control in
            guard let self, let tabBarController,
                  let index = self.resolvedTabIndex(for: control, in: tabBarController) else {
                tabBar.tabBarMenuControlSelectionDidHandle = false
                return true
            }
            tabBar.tabBarMenuControlSelectionDidHandle = true
            return self.handleInteraction(.tap, at: index, sourceView: control)
        }
    }

    /// Returns whether UIKit should continue processing the original tap.
    func handleInteraction(_ interaction: TabBarInteraction, at index: Int, sourceView: UIView) -> Bool {
        guard let tabBarController, let delegate,
              let item = tabBarController.tabBarMenuItem(at: index) else { return true }
        pendingSelection = nil
        let presentation = delegate.tabBarController(tabBarController, prepareFor: interaction, on: item)
        guard self.tabBarController === tabBarController else { return true }
        if interaction == .longPress {
            cancelTabBarTracking(for: sourceView)
        }
        if let presentation {
            if let context = makePresentationContext(for: sourceView, in: tabBarController) {
                let hostButton = makeMenuHostButton(in: context.containerView)
                hostButton.preferredMenuElementOrder = presentation.preferredMenuElementOrder
                presentMenu(
                    presentation.menu,
                    tabFrame: context.tabFrame,
                    in: context.containerView,
                    placement: presentation.anchorPlacement,
                    hostButton: hostButton,
                    sourceView: sourceView
                )
            }
            return false
        }
        guard interaction == .tap else { return false }
        installDelegateProxy(on: tabBarController)
        if item.isMore, let content = item.content {
            selectFromUser(content)
            return false
        }
        pendingSelection = (item.content, tabBarController.tabBarMenuSelectedContent)
        if tabBarController.tabBarMenuHasViewControllerTransientOverflowContent {
            _ = tabBarController.dismissTabBarMenuTransientOverflowIfNeeded()
        }
        return true
    }

    var isSelectingProgrammatically: Bool { programmaticSelectionDepth > 0 }

    func beginProgrammaticSelection() {
        programmaticSelectionDepth += 1
        pendingSelection = nil
        pendingMoreSelection = nil
    }

    func endProgrammaticSelection() {
        programmaticSelectionDepth -= 1
    }

    func willSelectNativeContent(_ content: TabBarContent) {
        guard programmaticSelectionDepth == 0,
              let tabBarController,
              tabBarController.tabBarMenuOwns(content) else { return }
        if pendingSelection?.content != content {
            pendingSelection = (content, tabBarController.tabBarMenuSelectedContent)
        }
    }

    func cancelNativeSelection() {
        pendingSelection = nil
    }

    func didSelectNativeContent(_ content: TabBarContent) {
        guard programmaticSelectionDepth == 0,
              let pendingSelection, pendingSelection.content == content else { return }
        self.pendingSelection = nil
        notifySelection(content, previous: pendingSelection.previous)
    }

    func willShowMoreContent(_ viewController: UIViewController, in navigationController: UINavigationController) {
        pendingMoreSelection = nil
        guard programmaticSelectionDepth == 0, let tabBarController,
              !tabBarController.tabBarMenuIsPresentingTransientOverflowContent else { return }
        guard let content = tabBarController.tabBarMenuContent(for: viewController) else {
            if pendingSelection?.content == nil { pendingSelection = nil }
            return
        }
        let previous: TabBarContent?
        if let pendingSelection {
            previous = pendingSelection.previous
        } else {
            let from = navigationController.transitionCoordinator?.viewController(forKey: .from)
                ?? navigationController.visibleViewController
            // Only a row selection from the More list is a new tab selection.
            // Navigating back within that tab's content must remain a navigation event.
            guard tabBarController.tabBarMenuIsMoreList(from) else { return }
            previous = nil
        }
        pendingMoreSelection = (viewController, content, previous)
    }

    func didShowMoreContent(_ viewController: UIViewController) {
        guard let pending = pendingMoreSelection else { return }
        pendingMoreSelection = nil
        guard pending.viewController === viewController,
              let controller = tabBarController,
              controller.tabBarMenuSelectedContent == pending.content else { return }
        notifySelection(pending.content, previous: pending.previous)
    }

    func selectFromUser(_ content: TabBarContent) {
        guard let tabBarController, tabBarController.tabBarMenuOwns(content),
              delegate != nil else { return }
        installDelegateProxy(on: tabBarController)
        let previous = tabBarController.tabBarMenuSelectedContent
        switch content {
        case .tab(let tab):
            if #available(iOS 18.4, *), !tab.isEnabled { return }
        case .viewController(let controller):
            guard controller.tabBarItem.isEnabled else { return }
        }
        guard tabBarControllerDelegateProxy?.allowsSelection(of: content, in: tabBarController) ?? true else { return }
        // Reselection is a notification, not a reconstruction of More's navigation stack.
        if previous != content {
            let didSelect: Bool
            switch content {
            case .tab(let tab): didSelect = tabBarController.selectTabContent(tab)
            case .viewController(let controller): didSelect = tabBarController.selectTabContent(controller)
            }
            guard didSelect else { return }
        }
        notifySelection(content, previous: previous)
    }

    private func notifySelection(_ content: TabBarContent, previous: TabBarContent?) {
        guard let tabBarController, tabBarController.tabBarMenuOwns(content) else { return }
        if pendingSelection?.content == nil || pendingSelection?.content == content {
            pendingSelection = nil
        }
        if pendingMoreSelection?.content == content { pendingMoreSelection = nil }
        let isOverflow = tabBarController.tabBarMenuIsOverflow(content)
        switch content {
        case .tab(let tab):
            let previousTab: UITab? = if case .tab(let tab) = previous { tab } else { nil }
            delegate?.tabBarController(tabBarController, didSelect: tab, previousTab: previousTab, isOverflow: isOverflow)
        case .viewController(let controller):
            let previousController: UIViewController? = if case .viewController(let controller) = previous { controller } else { nil }
            delegate?.tabBarController(
                tabBarController, didSelect: controller,
                previousViewController: previousController, isOverflow: isOverflow
            )
        }
    }

    private func uninstallSelectionHandler(from tabBarController: UITabBarController) {
        tabBarController.tabBar.tabBarMenuSelectionHandler = nil
        tabBarController.tabBar.tabBarMenuControlSelectionHandler = nil
    }

    private func installDelegateProxy(on tabBarController: UITabBarController) {
        let proxy = tabBarControllerDelegateProxy ?? TabBarMenuTabBarControllerDelegateProxy()
        proxy.tabBarController = tabBarController
        proxy.coordinator = self

        if tabBarController.delegate !== proxy {
            proxy.originalDelegate = tabBarController.delegate as? (NSObject & UITabBarControllerDelegate)
            tabBarController.delegate = proxy
        }

        tabBarControllerDelegateProxy = proxy
        let navigationProxy = moreNavigationDelegateProxy ?? TabBarMenuMoreNavigationDelegateProxy()
        navigationProxy.coordinator = self
        let navigationController = tabBarController.moreNavigationController
        if navigationController.delegate !== navigationProxy {
            navigationProxy.originalDelegate = navigationController.delegate as? (NSObject & UINavigationControllerDelegate)
            navigationController.delegate = navigationProxy
        }
        moreNavigationDelegateProxy = navigationProxy
    }

    private func uninstallDelegateProxy(from tabBarController: UITabBarController) {
        if let proxy = moreNavigationDelegateProxy {
            let controller = tabBarController.moreNavigationController
            if controller.delegate === proxy { controller.delegate = proxy.originalDelegate }
            proxy.originalDelegate = nil
            proxy.coordinator = nil
        }
        pendingMoreSelection = nil
        guard let proxy = tabBarControllerDelegateProxy else {
            return
        }

        if tabBarController.delegate === proxy {
            tabBarController.delegate = proxy.originalDelegate
        }

        proxy.tabBarController = nil
        proxy.coordinator = nil
        proxy.originalDelegate = nil
        if self.tabBarController !== tabBarController {
            tabBarControllerDelegateProxy = nil
        }
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

    private func synchronizeMenuGestures(in tabBarController: UITabBarController) {
        let tabBar = tabBarController.tabBar
        let indexedViews = tabBarIndexedViews(in: tabBar)
        let syncEntries = indexedViews.map { index, view in
            GestureSyncEntry(
                viewID: ObjectIdentifier(view),
                tabIndex: index,
                minimumPressDuration: configuration.minimumPressDuration
            )
        }

        if syncEntries == lastGestureSyncEntries {
            return
        }

        var existingRecognizersByView = menuRecognizersByView(in: tabBar)

        for ((index, view), entry) in zip(indexedViews, syncEntries) {
            let viewID = entry.viewID
            let minimumPressDuration = entry.minimumPressDuration
            let recognizers = existingRecognizersByView.removeValue(forKey: viewID) ?? []

            if let recognizer = recognizers.first {
                recognizer.tabIndex = index
                recognizer.minimumPressDuration = minimumPressDuration
                recognizer.cancelsTouchesInView = true
                recognizer.delegate = self

                for duplicate in recognizers.dropFirst() {
                    view.removeGestureRecognizer(duplicate)
                }
            } else {
                addLongPress(to: view, tabIndex: index, minimumPressDuration: minimumPressDuration)
            }
        }

        for recognizers in existingRecognizersByView.values {
            for recognizer in recognizers {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
        }

        lastGestureSyncEntries = syncEntries
    }

    private func menuRecognizersByView(in tabBar: UITabBar) -> [ObjectIdentifier: [TabBarMenuLongPressGestureRecognizer]] {
        var recognizersByView: [ObjectIdentifier: [TabBarMenuLongPressGestureRecognizer]] = [:]

        for control in tabBarControls(in: tabBar) {
            let recognizers = (control.gestureRecognizers ?? []).compactMap { recognizer in
                recognizer as? TabBarMenuLongPressGestureRecognizer
            }
            guard !recognizers.isEmpty else {
                continue
            }
            recognizersByView[ObjectIdentifier(control)] = recognizers
        }

        return recognizersByView
    }

    // MARK: - Menu presentation

    private func makePresentationContext(for sourceView: UIView, in tabBarController: UITabBarController) -> PresentationContext? {
        guard let containerView = tabBarController.view ?? sourceView.window?.rootViewController?.view else {
            return nil
        }
        let tabFrame = sourceView.convert(sourceView.bounds, to: containerView)
        return PresentationContext(containerView: containerView, tabFrame: tabFrame)
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
        if let anchorFrame = tabBarMenuAnchorFrame(
            tabFrame: tabFrame,
            placement: placement
        ) {
            hostButton.frame = anchorFrame
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

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              let view = recognizer.view,
              let tabBarController,
              let longPressRecognizer = recognizer as? TabBarMenuLongPressGestureRecognizer else {
            return
        }
        if let currentTabIndex = resolvedTabIndex(for: longPressRecognizer, sourceView: view, in: tabBarController) {
            _ = handleInteraction(.longPress, at: currentTabIndex, sourceView: view)
            return
        }

        refreshInteractions()
        guard let currentTabIndex = resolvedTabIndex(for: longPressRecognizer, sourceView: view, in: tabBarController) else {
            return
        }
        _ = handleInteraction(.longPress, at: currentTabIndex, sourceView: view)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    // MARK: - Private API helpers

    private func tabBarItemView(_ item: UITabBarItem) -> UIView? {
        if let view = performSelector(UITabBarItemRuntimeMethodNames.view, on: item) as? UIView {
            return view
        }
        return nil
    }

    func resolvedTabIndex(
        for recognizer: TabBarMenuLongPressGestureRecognizer,
        sourceView: UIView,
        in tabBarController: UITabBarController
    ) -> Int? {
        guard let currentTabIndex = resolvedTabIndex(for: sourceView, in: tabBarController) else {
            return nil
        }
        recognizer.tabIndex = currentTabIndex
        return currentTabIndex
    }

    func resolvedTabIndex(for sourceView: UIView, in tabBarController: UITabBarController) -> Int? {
        if let directMatch = tabBarIndexedViews(in: tabBarController.tabBar).first(where: { $0.1 === sourceView })?.0 {
            return directMatch
        }

        guard let control = sourceView as? UIControl else {
            return nil
        }

        let fallbackControls = tabBarFallbackControls(in: tabBarController.tabBar)
        guard !fallbackControls.isEmpty else {
            return nil
        }

        let isRTL = tabBarController.tabBar.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let sortedControls = fallbackControls.sorted { left, right in
            let leftFrame = left.convert(left.bounds, to: tabBarController.tabBar)
            let rightFrame = right.convert(right.bounds, to: tabBarController.tabBar)
            if isRTL {
                return leftFrame.minX > rightFrame.minX
            }
            return leftFrame.minX < rightFrame.minX
        }

        return sortedControls.firstIndex(where: { $0 === control })
    }

    private func performSelector(_ name: String, on object: NSObject) -> AnyObject? {
        ObjectiveCInterop.performObjectSelector(name, on: object)
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
