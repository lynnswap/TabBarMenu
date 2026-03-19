import UIKit
import ObjectiveC

@MainActor
public extension UITabBarController {
    /// Selects the content represented by a tab.
    /// - Note: Overflow `UITab` items are presented through the tab controller's private displayed-view path and keep the More item visually selected.
    /// - Parameter tab: The `UITab` whose content should become active.
    /// - Returns: `true` when the tab belongs to this controller and selection was requested.
    @discardableResult
    func selectTabContent(_ tab: UITab) -> Bool {
        guard let index = tabs.firstIndex(where: { $0 === tab }),
              let resolvedViewController = resolvedMoreSelectionViewController(for: tab) else {
            return false
        }

        scheduleTabContentSelection {
            if self.isOverflowItemIndex(index, totalCount: self.tabs.count) {
                _ = self.selectOverflowTabContent(
                    resolvedViewController,
                    syncedMoreItem: self.syncedMoreTabBarItemForOverflowSelection(),
                    sourceTab: tab
                )
                return
            }

            _ = self.selectResolvedTabContent(
                resolvedViewController,
                syncedTab: tab
            )
        }
        return true
    }

    /// Selects the content represented by a view controller.
    /// - Note: Overflow view controllers are presented with `UITabBarController`'s transient private API and keep the More item visually selected.
    /// - Parameter viewController: The view controller whose tab content should become active.
    /// - Returns: `true` when the view controller belongs to this controller and selection was requested.
    @discardableResult
    func selectTabContent(_ viewController: UIViewController) -> Bool {
        guard let viewControllers,
              let index = viewControllers.firstIndex(where: { $0 === viewController }) else {
            return false
        }

        let syncedTab = isOverflowItemIndex(index, totalCount: viewControllers.count)
            ? nil
            : matchingTab(for: viewController)

        scheduleTabContentSelection {
            if self.isOverflowItemIndex(index, totalCount: viewControllers.count) {
                _ = self.selectOverflowTabContent(
                    viewController,
                    syncedMoreItem: self.syncedMoreTabBarItemForOverflowSelection(),
                    sourceTab: self.matchingTab(for: viewController)
                )
                return
            }

            _ = self.selectResolvedTabContent(
                viewController,
                syncedTab: syncedTab
            )
        }
        return true
    }
}

@MainActor
extension UITabBarController {
    var tabBarMenuIsPresentingTransientOverflowContent: Bool {
        currentTransientViewController() != nil || uiTabOverflowPresentationState != nil
    }

    var tabBarMenuHasViewControllerTransientOverflowContent: Bool {
        currentTransientViewController() != nil
    }

    nonisolated var tabBarMenuHasActiveUITabMoreSelection: Bool {
        unsafe objc_getAssociatedObject(
            self,
            &MoreSelectionAssociatedKeys.uiTabOverflowPresentationState
        ) != nil
    }

    func tabBarMenuDisplayedViewControllersOverride(
        for tab: UITab,
        proposedViewControllers: [UIViewController]
    ) -> [UIViewController]? {
        guard let state = uiTabOverflowPresentationState,
              tab === state.moreTabElement || tab === state.sourceTab else {
            return nil
        }
        return state.preparedDisplayedViewControllers.isEmpty
            ? proposedViewControllers
            : state.preparedDisplayedViewControllers
    }

    func tabBarMenuDidSelectTab(_ tab: UITab, previousTab: UITab?) {
        guard !isReplacingUITabOverflowSelection else {
            return
        }
        guard let state = uiTabOverflowPresentationState else {
            return
        }
        guard tab !== state.sourceTab else {
            return
        }
        scheduleUITabOverflowCleanupAfterSelection()
    }

    func tabBarMenuDidSelectViewController(_ viewController: UIViewController) {
        guard !isReplacingUITabOverflowSelection else {
            return
        }
        guard let state = uiTabOverflowPresentationState else {
            return
        }
        guard state.targetViewController !== viewController,
              viewController !== moreNavigationController else {
            return
        }
        scheduleUITabOverflowCleanupAfterSelection()
    }

    @discardableResult
    func dismissTabBarMenuTransientOverflowIfNeeded() -> Bool {
        var didDismiss = false
        if currentTransientViewController() != nil {
            didDismiss = setTransientViewControllerPrivately(nil, animated: false)
        }
        let didCleanupUITabOverflow = cleanupUITabOverflowPresentationIfNeeded()
        didDismiss = didDismiss || didCleanupUITabOverflow

        if didDismiss && !didCleanupUITabOverflow {
            cleanupMoreNavigationControllerState()
        }
        return didDismiss
    }

    func dismissInvalidTabBarMenuTransientOverflowIfNeeded() {
        if let transientViewController = currentTransientViewController() {
            guard ownsTabContentViewController(transientViewController) else {
                _ = dismissTabBarMenuTransientOverflowIfNeeded()
                return
            }
        }

        if let state = uiTabOverflowPresentationState,
           !ownsTabContentViewController(state.targetViewController) {
            _ = dismissTabBarMenuTransientOverflowIfNeeded()
        }
    }

    private func selectResolvedTabContent(
        _ viewController: UIViewController,
        syncedTab: UITab?
    ) -> Bool {
        _ = dismissTabBarMenuTransientOverflowIfNeeded()
        cleanupMoreNavigationControllerState()

        let didForceSelection = ObjectiveCInterop.performVoidSelector(
            UITabBarControllerRuntimeMethodNames.setSelectedViewControllerAndNotify,
            on: self,
            with: viewController
        )
        if !didForceSelection || currentSelectedViewControllerInTabBar() !== viewController {
            unsafe selectedViewController = viewController
        }
        if unsafe selectedViewController !== viewController {
            _ = ObjectiveCInterop.performVoidSelector(
                UITabBarControllerRuntimeMethodNames.setSelectedViewController,
                on: self,
                with: viewController
            )
        }
        if #available(iOS 26.0, *), let syncedTab {
            selectedTab = syncedTab
        }

        cleanupMoreNavigationControllerState()
        return true
    }

    private func selectOverflowTabContent(
        _ viewController: UIViewController,
        syncedMoreItem: UITabBarItem?,
        sourceTab: UITab?
    ) -> Bool {
        guard let moreItem = syncedMoreItem
            ?? uiTabOverflowPresentationState?.preservedMoreItem
            ?? currentMoreTabBarItem() else {
            return false
        }

        if let sourceTab {
            return selectUITabOverflowTabContent(
                viewController,
                sourceTab: sourceTab,
                syncedMoreItem: moreItem
            )
        }

        return selectViewControllerOverflowTabContent(
            viewController,
            syncedMoreItem: moreItem
        )
    }

    private func selectViewControllerOverflowTabContent(
        _ viewController: UIViewController,
        syncedMoreItem: UITabBarItem
    ) -> Bool {
        _ = dismissTabBarMenuTransientOverflowIfNeeded()
        cleanupMoreNavigationControllerState()

        performWithoutSelectionSideEffects {
            _ = self.setTransientViewControllerPrivately(viewController, animated: false)
            self.restoreMoreTabSelectionIfNeeded(with: syncedMoreItem)
        }

        cleanupMoreNavigationControllerState()
        restoreMoreTabSelectionIfNeeded(with: syncedMoreItem)
        return currentTransientViewController() === viewController
    }

    private func selectUITabOverflowTabContent(
        _ viewController: UIViewController,
        sourceTab: UITab,
        syncedMoreItem: UITabBarItem
    ) -> Bool {
        let isReplacingActiveUITabOverflow = uiTabOverflowPresentationState != nil
        let previousState = uiTabOverflowPresentationState

        if currentTransientViewController() != nil {
            _ = setTransientViewControllerPrivately(nil, animated: false)
            cleanupMoreNavigationControllerState()
        } else if !isReplacingActiveUITabOverflow {
            cleanupMoreNavigationControllerState()
        }

        guard let moreTabElement = resolvedMoreTabElement(),
              let preparedViewController = preparedMoreViewController(for: viewController) else {
            return false
        }

        if let previousState, previousState.sourceTab !== sourceTab {
            restoreDisplayedViewControllers(
                from: previousState.originalDisplayedViewControllers,
                to: previousState.sourceTab
            )
        }

        uiTabOverflowPresentationState = UITabOverflowPresentationState(
            sourceTab: sourceTab,
            moreTabElement: moreTabElement,
            targetViewController: viewController,
            preparedDisplayedViewControllers: [preparedViewController],
            originalDisplayedViewControllers: previousState?.sourceTab === sourceTab
                ? (previousState?.originalDisplayedViewControllers ?? [])
                : displayedViewControllers(for: sourceTab) as NSArray,
            originalMoreDisplayedViewControllers: previousState?.originalMoreDisplayedViewControllers
                ?? displayedViewControllers(for: moreTabElement) as NSArray,
            preservedMoreItem: syncedMoreItem
        )

        let applyPreparedOverflowPresentation: @MainActor () -> Void = {
            guard let state = self.uiTabOverflowPresentationState,
                  state.sourceTab === sourceTab,
                  state.moreTabElement === moreTabElement else {
                return
            }
            self.setDisplayedViewControllers(
                state.preparedDisplayedViewControllers,
                for: state.sourceTab
            )
            self.setDisplayedViewControllers(
                state.preparedDisplayedViewControllers,
                for: state.moreTabElement
            )
            self.moreNavigationController.setViewControllers(state.preparedDisplayedViewControllers, animated: false)
            _ = ObjectiveCInterop.performVoidSelector(
                UIMoreNavigationControllerRuntimeMethodNames.setDisplayedViewController,
                on: self.moreNavigationController,
                with: state.preparedDisplayedViewControllers.last
            )
            self.disableInteractivePopForUITabOverflow(using: state)
            self.restoreMoreTabSelectionIfNeeded(with: syncedMoreItem)
        }

        let finishOverflowReplacement: @MainActor () -> Void = {
            self.isReplacingUITabOverflowSelection = false
        }

        if isReplacingActiveUITabOverflow {
            isReplacingUITabOverflowSelection = true
            applyPreparedOverflowPresentation()
            if self.currentSelectedTabElement() !== moreTabElement {
                _ = ObjectiveCInterop.performVoidSelector(
                    UITabBarControllerRuntimeMethodNames.selectTabElementIfPossible,
                    on: self,
                    with: moreTabElement
                ) || ObjectiveCInterop.performVoidSelector(
                    UITabBarControllerRuntimeMethodNames.setSelectedTab,
                    on: self,
                    with: moreTabElement
                )
            }
            DispatchQueue.main.async {
                applyPreparedOverflowPresentation()
                finishOverflowReplacement()
            }
            return true
        }

        let needsSelectionTransition = currentSelectedTabElement() !== sourceTab
        let didSelectTab: Bool
        if !needsSelectionTransition {
            didSelectTab = true
        } else {
            didSelectTab =
                ObjectiveCInterop.performVoidSelector(
                    UITabBarControllerRuntimeMethodNames.selectTabElementIfPossible,
                    on: self,
                    with: sourceTab
                ) || ObjectiveCInterop.performVoidSelector(
                    UITabBarControllerRuntimeMethodNames.setSelectedTab,
                    on: self,
                    with: sourceTab
                )
        }
        if !didSelectTab {
            uiTabOverflowPresentationState = nil
            return false
        }

        restoreMoreTabSelectionIfNeeded(with: syncedMoreItem)
        DispatchQueue.main.async {
            applyPreparedOverflowPresentation()
        }
        return true
    }

    private func performWithoutSelectionSideEffects(_ block: @escaping @MainActor () -> Void) {
        let objcBlock: @convention(block) () -> Void = {
            MainActor.assumeIsolated {
                block()
            }
        }

        if ObjectiveCInterop.performVoidSelector(
            UITabBarControllerRuntimeMethodNames.performWithIgnoringSelectionUpdate,
            on: self,
            bool: true,
            block: objcBlock
        ) {
            return
        }

        if ObjectiveCInterop.performVoidSelector(
            UITabBarControllerRuntimeMethodNames.performWithoutNotifyingSelectionChange,
            on: self,
            block: objcBlock
        ) {
            return
        }

        block()
    }

    private func setTransientViewControllerPrivately(
        _ viewController: UIViewController?,
        animated: Bool
    ) -> Bool {
        if ObjectiveCInterop.performVoidSelector(
            UITabBarControllerRuntimeMethodNames.setTransientViewControllerAnimated,
            on: self,
            object: viewController,
            bool: animated
        ) {
            return currentTransientViewController() === viewController
        }

        if ObjectiveCInterop.performVoidSelector(
            UITabBarControllerRuntimeMethodNames.setTransientViewController,
            on: self,
            with: viewController
        ) {
            return currentTransientViewController() === viewController
        }

        return false
    }

    private func currentTransientViewController() -> UIViewController? {
        ObjectiveCInterop.performObjectSelector(
            UITabBarControllerRuntimeMethodNames.transientViewController,
            on: self
        ) as? UIViewController
    }

    private func currentSelectedViewControllerInTabBar() -> UIViewController? {
        if let viewController = ObjectiveCInterop.performObjectSelector(
            UITabBarControllerRuntimeMethodNames.selectedViewControllerInTabBar,
            on: self
        ) as? UIViewController {
            return viewController
        }
        return unsafe selectedViewController
    }

    private func currentSelectedTabElement() -> UITab? {
        ObjectiveCInterop.performObjectSelector(
            UITabBarControllerRuntimeMethodNames.selectedTabElement,
            on: self
        ) as? UITab
    }

    private func resolvedMoreTabElement() -> UITab? {
        ObjectiveCInterop.performObjectSelector(
            UIMoreNavigationControllerRuntimeMethodNames.resolvedTab,
            on: moreNavigationController
        ) as? UITab
    }

    private func displayedViewControllers(for tab: UITab) -> [UIViewController] {
        (ObjectiveCInterop.performObjectSelector(
            UITabRuntimeMethodNames.displayedViewControllers,
            on: tab
        ) as? [UIViewController]) ?? []
    }

    private func setDisplayedViewControllers(
        _ viewControllers: [UIViewController],
        for tab: UITab
    ) {
        _ = ObjectiveCInterop.performVoidSelector(
            UITabRuntimeMethodNames.setDisplayedViewControllers,
            on: tab,
            with: viewControllers as NSArray
        )
    }

    private func isMoreTabElement(_ tab: UITab) -> Bool {
        ObjectiveCInterop.performBoolSelector(
            UITabRuntimeMethodNames.isMoreTab,
            on: tab
        ) ?? false
    }

    private func resolvedMoreSelectionViewController(for tab: UITab) -> UIViewController? {
        if let viewController = tab.viewController {
            return viewController
        }
        return tab.resolvedMoreSelectionViewController
    }

    private func scheduleTabContentSelection(_ action: @escaping @MainActor () -> Void) {
        action()
    }

    private func isOverflowItemIndex(_ index: Int, totalCount: Int) -> Bool {
        let requestCore = TabBarMenuRequestCore(configuration: menuConfiguration)
        guard let startIndex = requestCore.moreTabStartIndex(totalCount: totalCount) else {
            return false
        }
        return index >= startIndex
    }

    private func matchingTab(for viewController: UIViewController) -> UITab? {
        tabs.first { tab in
            if let tabViewController = tab.viewController {
                return tabViewController === viewController
            }
            return tab.resolvedMoreSelectionViewController === viewController
        }
    }

    private func ownsTabContentViewController(_ viewController: UIViewController) -> Bool {
        if viewControllers?.contains(where: { $0 === viewController }) == true {
            return true
        }
        return tabs.contains { tab in
            if let tabViewController = tab.viewController {
                return tabViewController === viewController
            }
            return tab.resolvedMoreSelectionViewController === viewController
        }
    }

    private func restoreMoreTabSelectionIfNeeded(with preservedMoreItem: UITabBarItem?) {
        let moreItem = preservedMoreItem
            ?? uiTabOverflowPresentationState?.preservedMoreItem
            ?? currentMoreTabBarItem()
        guard let moreItem else {
            return
        }
        _ = ObjectiveCInterop.performVoidSelector(
            UITabBarControllerRuntimeMethodNames.setSelectedTabBarItem,
            on: self,
            with: moreItem
        )
    }

    private func cleanupMoreNavigationControllerState(restoringMoreListController: Bool = true) {
        let moreNavigationController = moreNavigationController
        let moreNavigationControllerObject = moreNavigationController as NSObject
        moreNavigationController.interactivePopGestureRecognizer?.isEnabled = true
        moreNavigationController.setNavigationBarHidden(false, animated: false)

        _ = ObjectiveCInterop.performVoidSelector(
            UIMoreNavigationControllerRuntimeMethodNames.setDisplayedViewController,
            on: moreNavigationControllerObject,
            with: nil
        )

        if ObjectiveCInterop.performVoidSelector(
            UIMoreNavigationControllerRuntimeMethodNames.restoreOriginalNavigationController,
            on: moreNavigationControllerObject
        ) {
            if restoringMoreListController {
                restoreMoreListControllerIfNeeded(in: moreNavigationController)
            }
            return
        }

        _ = ObjectiveCInterop.performVoidSelector(
            UIMoreNavigationControllerRuntimeMethodNames.restoreOriginalNavigationControllerIfNecessary,
            on: moreNavigationControllerObject,
            with: nil
        )
        if restoringMoreListController {
            restoreMoreListControllerIfNeeded(in: moreNavigationController)
        }
    }

    private func restoreMoreListControllerIfNeeded(in navigationController: UINavigationController) {
        guard let moreListController = ObjectiveCInterop.performObjectSelector(
            UIMoreNavigationControllerRuntimeMethodNames.moreListController,
            on: navigationController
        ) as? UIViewController else {
            return
        }
        navigationController.setViewControllers([moreListController], animated: false)
    }

    private func currentMoreTabBarItem() -> UITabBarItem? {
        let totalCount = max(tabs.count, viewControllers?.count ?? 0)
        let requestCore = TabBarMenuRequestCore(configuration: menuConfiguration)
        guard let items = tabBar.items,
              let moreIndex = requestCore.moreTabStartIndex(totalCount: totalCount),
              items.indices.contains(moreIndex) else {
            return nil
        }
        return items[moreIndex]
    }

    private func syncedMoreTabBarItemForOverflowSelection() -> UITabBarItem? {
        uiTabOverflowPresentationState?.preservedMoreItem ?? currentMoreTabBarItem()
    }

    @discardableResult
    private func cleanupUITabOverflowPresentationIfNeeded() -> Bool {
        guard uiTabOverflowPresentationState != nil else {
            return false
        }
        restoreUITabOverflowDisplayedViewControllersIfNeeded()
        uiTabOverflowPresentationState = nil
        cleanupMoreNavigationControllerState()
        return true
    }

    private func restoreUITabOverflowDisplayedViewControllersIfNeeded() {
        guard let state = uiTabOverflowPresentationState else {
            return
        }
        restoreDisplayedViewControllers(from: state.originalDisplayedViewControllers, to: state.sourceTab)
        restoreDisplayedViewControllers(from: state.originalMoreDisplayedViewControllers, to: state.moreTabElement)
    }

    private func disableInteractivePopForUITabOverflow(using state: UITabOverflowPresentationState) {
        moreNavigationController.interactivePopGestureRecognizer?.isEnabled = false
        moreNavigationController.setNavigationBarHidden(true, animated: false)

        let candidates = state.preparedDisplayedViewControllers
            + displayedViewControllers(for: state.sourceTab)
            + [state.targetViewController]
            + [currentSelectedViewControllerInTabBar()].compactMap { $0 }

        var visited: Set<ObjectIdentifier> = []
        for viewController in candidates {
            let identifier = ObjectIdentifier(viewController)
            guard visited.insert(identifier).inserted else {
                continue
            }
            if let navigationController = viewController as? UINavigationController {
                navigationController.interactivePopGestureRecognizer?.isEnabled = false
            }
            viewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
    }

    private func scheduleUITabOverflowCleanupAfterSelection() {
        let cleanup: @MainActor () -> Void = {
            _ = self.cleanupUITabOverflowPresentationIfNeeded()
        }

        if let coordinator = transitionCoordinator {
            let didSchedule = coordinator.animate(alongsideTransition: nil) { _ in
                MainActor.assumeIsolated {
                    cleanup()
                }
            }
            if didSchedule {
                return
            }
        }

        if let coordinator = currentSelectedViewControllerInTabBar()?.transitionCoordinator {
            let didSchedule = coordinator.animate(alongsideTransition: nil) { _ in
                MainActor.assumeIsolated {
                    cleanup()
                }
            }
            if didSchedule {
                return
            }
        }

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                cleanup()
            }
        }
    }

    private func preparedMoreViewController(for viewController: UIViewController) -> UIViewController? {
        if let preparedViewController = ObjectiveCInterop.performObjectSelector(
            UIMoreNavigationControllerRuntimeMethodNames.preparedViewController,
            on: moreNavigationController,
            with: viewController
        ) as? UIViewController {
            return preparedViewController
        }
        return viewController
    }

    private func restoreDisplayedViewControllers(
        from originalDisplayedViewControllers: NSArray,
        to tab: UITab
    ) {
        let originalViewControllers = originalDisplayedViewControllers.compactMap { $0 as? UIViewController }
        setDisplayedViewControllers(originalViewControllers, for: tab)
    }

    private var uiTabOverflowPresentationState: UITabOverflowPresentationState? {
        get {
            unsafe ObjectiveCInterop.associatedObject(
                for: self,
                key: &MoreSelectionAssociatedKeys.uiTabOverflowPresentationState
            )
        }
        set {
            unsafe ObjectiveCInterop.setAssociatedObject(
                newValue,
                for: self,
                key: &MoreSelectionAssociatedKeys.uiTabOverflowPresentationState,
                policy: .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    private var isReplacingUITabOverflowSelection: Bool {
        get {
            unsafe (ObjectiveCInterop.associatedObject(
                for: self,
                key: &MoreSelectionAssociatedKeys.isReplacingUITabOverflowSelection
            ) as NSNumber?)?.boolValue ?? false
        }
        set {
            unsafe ObjectiveCInterop.setAssociatedObject(
                NSNumber(value: newValue),
                for: self,
                key: &MoreSelectionAssociatedKeys.isReplacingUITabOverflowSelection,
                policy: .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

private final class UITabOverflowPresentationState {
    let sourceTab: UITab
    let moreTabElement: UITab
    let targetViewController: UIViewController
    let preparedDisplayedViewControllers: [UIViewController]
    let originalDisplayedViewControllers: NSArray
    let originalMoreDisplayedViewControllers: NSArray
    let preservedMoreItem: UITabBarItem

    init(
        sourceTab: UITab,
        moreTabElement: UITab,
        targetViewController: UIViewController,
        preparedDisplayedViewControllers: [UIViewController],
        originalDisplayedViewControllers: NSArray,
        originalMoreDisplayedViewControllers: NSArray,
        preservedMoreItem: UITabBarItem
    ) {
        self.sourceTab = sourceTab
        self.moreTabElement = moreTabElement
        self.targetViewController = targetViewController
        self.preparedDisplayedViewControllers = preparedDisplayedViewControllers
        self.originalDisplayedViewControllers = originalDisplayedViewControllers
        self.originalMoreDisplayedViewControllers = originalMoreDisplayedViewControllers
        self.preservedMoreItem = preservedMoreItem
    }
}

private enum MoreSelectionAssociatedKeys {
    nonisolated(unsafe)
    static var uiTabOverflowPresentationState = UInt8(0)
    nonisolated(unsafe)
    static var isReplacingUITabOverflowSelection = UInt8(0)
}
