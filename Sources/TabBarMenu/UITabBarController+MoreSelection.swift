import UIKit
import ObjectiveC

@MainActor
public extension UITabBarController {
    /// Selects tab content programmatically, without a `TabBarMenuDelegate.didSelect` notification.
    /// - Note: Overflow `UITab` items use the private displayed-view path on iOS 26+ and fall back to selecting the More navigation stack directly on iOS 18 to keep selection reliable.
    /// - Parameter tab: The `UITab` whose content should become active.
    /// - Returns: Whether the content selection succeeded.
    @discardableResult
    func selectTabContent(_ tab: UITab) -> Bool {
        guard let index = tabs.firstIndex(where: { $0 === tab }),
              let resolvedViewController = resolvedMoreSelectionViewController(for: tab) else {
            return false
        }

        tabBarMenuCoordinator?.beginProgrammaticSelection()
        defer { tabBarMenuCoordinator?.endProgrammaticSelection() }
        if isOverflowItemIndex(index, totalCount: tabs.count) {
            return selectOverflowTabContent(
                resolvedViewController,
                syncedMoreItem: syncedMoreTabBarItemForOverflowSelection(),
                sourceTab: tab
            )
        }
        return selectResolvedTabContent(resolvedViewController, syncedTab: tab)
    }

    /// Selects view-controller content programmatically, without a `TabBarMenuDelegate.didSelect` notification.
    /// - Note: Overflow view controllers are presented with `UITabBarController`'s transient private API and keep the More item visually selected.
    /// - Parameter viewController: The view controller whose tab content should become active.
    /// - Returns: Whether the content selection succeeded.
    @discardableResult
    func selectTabContent(_ viewController: UIViewController) -> Bool {
        guard let viewControllers,
              let index = viewControllers.firstIndex(where: { $0 === viewController }) else {
            return false
        }

        let syncedTab = isOverflowItemIndex(index, totalCount: viewControllers.count)
            ? nil
            : matchingTab(for: viewController)

        tabBarMenuCoordinator?.beginProgrammaticSelection()
        defer { tabBarMenuCoordinator?.endProgrammaticSelection() }
        if isOverflowItemIndex(index, totalCount: viewControllers.count) {
            return selectOverflowTabContent(
                viewController,
                syncedMoreItem: syncedMoreTabBarItemForOverflowSelection(),
                sourceTab: matchingTab(for: viewController)
            )
        }
        return selectResolvedTabContent(viewController, syncedTab: syncedTab)
    }

}

@MainActor
extension UITabBarController {
    func tabBarMenuIsMoreList(_ viewController: UIViewController?) -> Bool {
        guard let viewController else { return false }
        return viewController === moreListControllerObject()
    }

    func tabBarMenuContent(for viewController: UIViewController) -> TabBarContent? {
        if !tabs.isEmpty {
            if let tab = matchingTab(for: viewController) { return .tab(tab) }
            let resolved = ObjectiveCInterop.performObjectSelector(
                UIViewControllerRuntimeMethodNames.resolvedTab, on: viewController
            ) as? UITab
            if let resolved, tabs.contains(where: { $0 === resolved }) { return .tab(resolved) }
        } else if let owner = owningTabViewController(for: viewController) {
            return .viewController(owner)
        }
        return nil
    }

    var tabBarMenuSelectedTab: UITab? {
        // WORKAROUND: On iOS 18 the selected tab element can still name the previous visible tab
        // while More is displaying the content selected through its navigation stack.
        if let state = uiTabOverflowPresentationState,
           tabBar.selectedItem === state.preservedMoreItem {
            return state.sourceTab
        }
        if let moreItem = currentMoreTabBarItem(), tabBar.selectedItem === moreItem {
            if let top = moreNavigationController.topViewController,
               case .tab(let tab) = tabBarMenuContent(for: top) { return tab }
            return tabBarMenuSelectedViewController.flatMap { matchingTab(for: $0) }
        }
        if let tab = currentSelectedTabElement(), tabs.contains(where: { $0 === tab }) {
            return tab
        }
        return tabBarMenuSelectedViewController.flatMap { matchingTab(for: $0) }
    }

    var tabBarMenuSelectedViewController: UIViewController? {
        if let transient = currentTransientViewController() { return transient }
        let current = currentSelectedViewControllerInTabBar()
        if let current, current !== moreNavigationController,
           ownsTabContentViewController(current) { return current }
        if let state = uiTabOverflowPresentationState,
           tabBar.selectedItem === state.preservedMoreItem {
            return state.targetViewController
        }
        guard current === moreNavigationController else { return nil }
        let displayed = ObjectiveCInterop.performObjectSelector(
            UIMoreNavigationControllerRuntimeMethodNames.displayedViewController,
            on: moreNavigationController
        ) as? UIViewController
        let candidate = displayed === moreNavigationController
            ? moreNavigationController.topViewController : displayed
        guard let candidate, candidate !== moreListControllerObject() else { return nil }
        return owningTabViewController(for: candidate)
    }

    private func owningTabViewController(for displayedViewController: UIViewController) -> UIViewController? {
        let owners = tabs.isEmpty
            ? (viewControllers ?? [])
            : tabs.compactMap { resolvedMoreSelectionViewController(for: $0) }
        return owners.first { containsLegacyMoreTarget($0, descendant: displayedViewController) }
    }

    nonisolated private var usesUITabDisplayedViewControllersOverflowPath: Bool {
        // WORKAROUND: iOS 18 lacks _selectTabElementIfPossible: and the selection-update
        // suppression path used on iOS 26+. Its overflow selection must go through More.
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    var tabBarMenuIsPresentingTransientOverflowContent: Bool {
        currentTransientViewController() != nil || uiTabOverflowPresentationState != nil
    }

    var tabBarMenuHasViewControllerTransientOverflowContent: Bool {
        currentTransientViewController() != nil
    }

    nonisolated var tabBarMenuHasActiveUITabMoreSelection: Bool {
        guard usesUITabDisplayedViewControllersOverflowPath else {
            return false
        }
        return unsafe objc_getAssociatedObject(
            self,
            &MoreSelectionAssociatedKeys.uiTabOverflowPresentationState
        ) != nil
    }

    func tabBarMenuDisplayedViewControllersOverride(
        for tab: UITab,
        proposedViewControllers: [UIViewController]
    ) -> [UIViewController]? {
        guard usesUITabDisplayedViewControllersOverflowPath else {
            return nil
        }
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
        // UIKit may already own this presentation after the selected tab moves into More.
        if !tabBarMenuIsPresentingTransientOverflowContent,
           unsafe selectedViewController === viewController {
            return true
        }

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
        // UIKit can populate More before the helper records a presentation.
        let isReplacingLegacyMoreContent = isReplacingActiveUITabOverflow
            || moreNavigationController.viewControllers.count > 1
        let previousState = uiTabOverflowPresentationState

        if currentTransientViewController() != nil {
            _ = setTransientViewControllerPrivately(nil, animated: false)
            cleanupMoreNavigationControllerState()
        } else if !isReplacingActiveUITabOverflow {
            cleanupMoreNavigationControllerState()
        }

        guard let moreTabElement = resolvedMoreTabElement() else {
            return false
        }
        let preparedViewController: UIViewController
        if let previousState, previousState.targetViewController === viewController,
           let prepared = previousState.preparedDisplayedViewControllers.first {
            preparedViewController = prepared
        } else if usesUITabDisplayedViewControllersOverflowPath {
            if previousState?.targetViewController is UINavigationController {
                isReplacingUITabOverflowSelection = true
                cleanupMoreNavigationControllerState()
            }
            preparedViewController = preparedMoreViewController(for: viewController)
        } else {
            preparedViewController = (viewController as? UINavigationController)?.viewControllers.first
                ?? viewController
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
            preservedMoreItem: syncedMoreItem,
            originalInteractivePopGestureStates: previousState?.originalInteractivePopGestureStates ?? []
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
            // The displayed controller is the original owner, not its borrowed root.
            _ = ObjectiveCInterop.performVoidSelector(
                UIMoreNavigationControllerRuntimeMethodNames.setDisplayedViewController,
                on: self.moreNavigationController,
                with: state.targetViewController
            )
            self.disableInteractivePopForUITabOverflow(using: state)
            self.restoreMoreTabSelectionIfNeeded(with: syncedMoreItem)
        }

        let finishOverflowReplacement: @MainActor () -> Void = {
            self.isReplacingUITabOverflowSelection = false
        }

        if !usesUITabDisplayedViewControllersOverflowPath {
            let shouldFinishReplacement = isReplacingLegacyMoreContent
            if shouldFinishReplacement {
                isReplacingUITabOverflowSelection = true
            }
            let didSelectLegacyOverflow: Bool
            if shouldFinishReplacement {
                didSelectLegacyOverflow = replaceLegacyUITabOverflowContent(
                    targetViewController: viewController,
                    preparedViewController: preparedViewController,
                    syncedMoreItem: syncedMoreItem
                )
            } else {
                didSelectLegacyOverflow = selectLegacyUITabOverflowViaMoreList(
                    targetViewController: viewController,
                    sourceTab: sourceTab,
                    syncedMoreItem: syncedMoreItem
                )
            }
            if !didSelectLegacyOverflow {
                self.uiTabOverflowPresentationState = nil
                finishLegacyMoreNavigationControllerSelection()
                if shouldFinishReplacement {
                    finishOverflowReplacement()
                }
                return false
            }
            scheduleLegacyMoreNavigationControllerSelectionCompletion {
                self.finishLegacyMoreNavigationControllerSelection()
                if shouldFinishReplacement {
                    finishOverflowReplacement()
                }
            }
            return true
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

    private func selectLegacyUITabOverflowContainer(with preservedMoreItem: UITabBarItem) -> Bool {
        let targetViewController = moreNavigationController

        let didForceSelection = ObjectiveCInterop.performVoidSelector(
            UITabBarControllerRuntimeMethodNames.setSelectedViewControllerAndNotify,
            on: self,
            with: targetViewController
        )
        if !didForceSelection || currentSelectedViewControllerInTabBar() !== targetViewController {
            unsafe selectedViewController = targetViewController
        }
        if unsafe selectedViewController !== targetViewController {
            _ = ObjectiveCInterop.performVoidSelector(
                UITabBarControllerRuntimeMethodNames.setSelectedViewController,
                on: self,
                with: targetViewController
            )
        }

        restoreMoreTabSelectionIfNeeded(with: preservedMoreItem)
        return currentSelectedViewControllerInTabBar() === targetViewController
    }

    private func selectLegacyUITabOverflowViaMoreList(
        targetViewController: UIViewController,
        sourceTab: UITab,
        syncedMoreItem: UITabBarItem
    ) -> Bool {
        let shouldHideVisibleMoreContent = currentSelectedViewControllerInTabBar() === moreNavigationController
        if shouldHideVisibleMoreContent {
            prepareLegacyMoreNavigationControllerForSelection()
        }

        cleanupMoreNavigationControllerState(preservingViewAlpha: shouldHideVisibleMoreContent)

        guard let moreListController = moreListControllerObject(),
              let tableView = moreListTableView(in: moreListController),
              let rowIndex = legacyMoreListRowIndex(
                for: targetViewController,
                sourceTab: sourceTab
              ) else {
            return false
        }

        if !shouldHideVisibleMoreContent {
            prepareLegacyMoreNavigationControllerForSelection()
        }
        guard selectLegacyUITabOverflowContainer(with: syncedMoreItem) else {
            return false
        }

        let indexPath = IndexPath(row: rowIndex, section: 0)
        var didRequestSelection = false
        UIView.performWithoutAnimation {
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            didRequestSelection = ObjectiveCInterop.performVoidSelector(
                UIMoreListControllerRuntimeMethodNames.didSelectRowAtIndexPath,
                on: moreListController,
                with: tableView,
                with: indexPath as NSIndexPath
            )
            moreNavigationController.view.layoutIfNeeded()
        }

        if let state = uiTabOverflowPresentationState {
            disableInteractivePopForUITabOverflow(using: state)
        }
        restoreMoreTabSelectionIfNeeded(with: syncedMoreItem)

        return didRequestSelection
    }

    private func replaceLegacyUITabOverflowContent(
        targetViewController: UIViewController,
        preparedViewController: UIViewController,
        syncedMoreItem: UITabBarItem
    ) -> Bool {
        let currentTopViewController = moreNavigationController.topViewController
        if currentTopViewController === preparedViewController
            || currentTopViewController === targetViewController
            || currentTopViewController.map({ containsLegacyMoreTarget($0, descendant: targetViewController) }) == true {
            if let state = uiTabOverflowPresentationState {
                disableInteractivePopForUITabOverflow(using: state)
            }
            restoreMoreTabSelectionIfNeeded(with: syncedMoreItem)
            return true
        }

        prepareLegacyMoreNavigationControllerForSelection()
        cleanupMoreNavigationControllerState(
            preservingViewAlpha: true
        )
        guard let moreListController = moreListControllerObject() as? UIViewController else {
            return false
        }
        guard selectLegacyUITabOverflowContainer(with: syncedMoreItem) else {
            return false
        }

        moreNavigationController.setViewControllers([moreListController], animated: false)
        if moreNavigationController.topViewController !== preparedViewController {
            // More records the original navigation owner while borrowing its root.
            moreNavigationController.pushViewController(targetViewController, animated: false)
        }
        moreNavigationController.view.layoutIfNeeded()

        if let state = uiTabOverflowPresentationState {
            disableInteractivePopForUITabOverflow(using: state)
        }
        restoreMoreTabSelectionIfNeeded(with: syncedMoreItem)

        let topViewController = moreNavigationController.topViewController
        return topViewController === preparedViewController
            || topViewController === targetViewController
            || topViewController.map { containsLegacyMoreTarget($0, descendant: targetViewController) } == true
    }

    private func moreListControllerObject() -> NSObject? {
        ObjectiveCInterop.performObjectSelector(
            UIMoreNavigationControllerRuntimeMethodNames.moreListController,
            on: moreNavigationController
        ) as? NSObject
    }

    private func moreListTableView(in controller: NSObject) -> UITableView? {
        ObjectiveCInterop.performObjectSelector(
            UIMoreListControllerRuntimeMethodNames.table,
            on: controller
        ) as? UITableView
    }

    private func legacyMoreListRowIndex(
        for targetViewController: UIViewController,
        sourceTab: UITab
    ) -> Int? {
        guard let moreViewControllers = ObjectiveCInterop.performObjectSelector(
            UIMoreNavigationControllerRuntimeMethodNames.moreViewControllers,
            on: moreNavigationController
        ) as? [UIViewController] else {
            return nil
        }

        if let directIndex = moreViewControllers.firstIndex(where: { $0 === targetViewController }) {
            return directIndex
        }

        if let tabIndex = moreViewControllers.firstIndex(where: {
            (ObjectiveCInterop.performObjectSelector(
                UIViewControllerRuntimeMethodNames.tab,
                on: $0
            ) as? UITab) === sourceTab
        }) {
            return tabIndex
        }

        if let resolvedTabIndex = moreViewControllers.firstIndex(where: {
            let resolvedTab = ObjectiveCInterop.performObjectSelector(
                UIViewControllerRuntimeMethodNames.resolvedTab,
                on: $0
            )
            return (resolvedTab as? UITab) === sourceTab || resolvedTab === sourceTab
        }) {
            return resolvedTabIndex
        }

        return nil
    }

    private func containsLegacyMoreTarget(
        _ rootViewController: UIViewController,
        descendant targetViewController: UIViewController
    ) -> Bool {
        if rootViewController === targetViewController {
            return true
        }
        if let navigationController = rootViewController as? UINavigationController {
            return navigationController.viewControllers.contains {
                containsLegacyMoreTarget($0, descendant: targetViewController)
            }
        }
        return rootViewController.children.contains {
            containsLegacyMoreTarget($0, descendant: targetViewController)
        }
    }

    private func prepareLegacyMoreNavigationControllerForSelection() {
        moreNavigationController.loadViewIfNeeded()
        moreNavigationController.view.alpha = 0
    }

    private func finishLegacyMoreNavigationControllerSelection() {
        moreNavigationController.view.alpha = 1
    }

    private func scheduleLegacyMoreNavigationControllerSelectionCompletion(
        _ completion: @escaping @MainActor () -> Void
    ) {
        func schedule(using coordinator: UIViewControllerTransitionCoordinator) -> Bool {
            coordinator.animate(alongsideTransition: nil) { _ in
                MainActor.assumeIsolated {
                    completion()
                }
            }
        }

        func attemptRestore(remainingDeferrals: Int) {
            if let coordinator = moreNavigationController.transitionCoordinator,
               schedule(using: coordinator) {
                return
            }
            if let coordinator = moreNavigationController.topViewController?.transitionCoordinator,
               schedule(using: coordinator) {
                return
            }
            if remainingDeferrals > 0 {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        attemptRestore(remainingDeferrals: remainingDeferrals - 1)
                    }
                }
                return
            }
            completion()
        }

        attemptRestore(remainingDeferrals: 2)
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

    private func isOverflowItemIndex(_ index: Int, totalCount: Int) -> Bool {
        let requestCore = TabBarMenuRequestCore(configuration: menuConfiguration)
        guard let startIndex = requestCore.moreTabStartIndex(totalCount: totalCount, in: self) else {
            return false
        }
        return index >= startIndex
    }

    private func matchingTab(for viewController: UIViewController) -> UITab? {
        tabs.first { tab in
            guard let owner = resolvedMoreSelectionViewController(for: tab) else { return false }
            return containsLegacyMoreTarget(owner, descendant: viewController)
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

    private func cleanupMoreNavigationControllerState(
        restoringMoreListController: Bool = true,
        preservingViewAlpha: Bool = false
    ) {
        let moreNavigationController = moreNavigationController
        let moreNavigationControllerObject = moreNavigationController as NSObject
        if !preservingViewAlpha {
            moreNavigationController.viewIfLoaded?.alpha = 1
        }
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
              let moreIndex = requestCore.moreTabStartIndex(totalCount: totalCount, in: self),
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
        restoreUITabOverflowInteractivePopGesturesIfNeeded()
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

        state.originalInteractivePopGestureStates = tabBarMenuRecordDisabledInteractivePopGestures(
            for: candidates,
            excluding: moreNavigationController,
            preserving: state.originalInteractivePopGestureStates
        )
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

    private func preparedMoreViewController(for viewController: UIViewController) -> UIViewController {
        // WORKAROUND: UIKit can return nil after borrowing the navigation controller's root.
        let navigationRoot = (viewController as? UINavigationController)?.viewControllers.first
        if let preparedViewController = ObjectiveCInterop.performObjectSelector(
            UIMoreNavigationControllerRuntimeMethodNames.preparedViewController,
            on: moreNavigationController,
            with: viewController
        ) as? UIViewController {
            return preparedViewController
        }
        return navigationRoot ?? viewController
    }

    private func restoreDisplayedViewControllers(
        from originalDisplayedViewControllers: NSArray,
        to tab: UITab
    ) {
        let originalViewControllers = originalDisplayedViewControllers.compactMap { $0 as? UIViewController }
        setDisplayedViewControllers(originalViewControllers, for: tab)
    }

    private func restoreUITabOverflowInteractivePopGesturesIfNeeded() {
        guard let state = uiTabOverflowPresentationState else {
            return
        }
        tabBarMenuRestoreInteractivePopGestures(from: state.originalInteractivePopGestureStates)
        state.originalInteractivePopGestureStates = []
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
    var originalInteractivePopGestureStates: [InteractivePopGestureState]

    init(
        sourceTab: UITab,
        moreTabElement: UITab,
        targetViewController: UIViewController,
        preparedDisplayedViewControllers: [UIViewController],
        originalDisplayedViewControllers: NSArray,
        originalMoreDisplayedViewControllers: NSArray,
        preservedMoreItem: UITabBarItem,
        originalInteractivePopGestureStates: [InteractivePopGestureState] = []
    ) {
        self.sourceTab = sourceTab
        self.moreTabElement = moreTabElement
        self.targetViewController = targetViewController
        self.preparedDisplayedViewControllers = preparedDisplayedViewControllers
        self.originalDisplayedViewControllers = originalDisplayedViewControllers
        self.originalMoreDisplayedViewControllers = originalMoreDisplayedViewControllers
        self.preservedMoreItem = preservedMoreItem
        self.originalInteractivePopGestureStates = originalInteractivePopGestureStates
    }
}

package struct InteractivePopGestureState {
    let navigationController: UINavigationController
    let wasEnabled: Bool

    var identifier: ObjectIdentifier {
        ObjectIdentifier(navigationController)
    }
}

@MainActor
package func tabBarMenuRecordDisabledInteractivePopGestures(
    for candidates: [UIViewController],
    excluding excludedNavigationController: UINavigationController?,
    preserving existingStates: [InteractivePopGestureState] = []
) -> [InteractivePopGestureState] {
    var recordedNavigationControllers = existingStates
    var visited = Set(recordedNavigationControllers.map(\.identifier))

    for viewController in candidates {
        let navigationControllers = [
            viewController as? UINavigationController,
            viewController.navigationController,
        ].compactMap { $0 }

        for navigationController in navigationControllers where navigationController !== excludedNavigationController {
            let identifier = ObjectIdentifier(navigationController)
            if visited.insert(identifier).inserted {
                recordedNavigationControllers.append(
                    InteractivePopGestureState(
                        navigationController: navigationController,
                        wasEnabled: navigationController.interactivePopGestureRecognizer?.isEnabled ?? false
                    )
                )
            }
            navigationController.interactivePopGestureRecognizer?.isEnabled = false
        }
    }

    return recordedNavigationControllers
}

@MainActor
package func tabBarMenuRestoreInteractivePopGestures(
    from states: [InteractivePopGestureState]
) {
    for gestureState in states {
        gestureState.navigationController.interactivePopGestureRecognizer?.isEnabled = gestureState.wasEnabled
    }
}

private enum MoreSelectionAssociatedKeys {
    nonisolated(unsafe)
    static var uiTabOverflowPresentationState = UInt8(0)
    nonisolated(unsafe)
    static var isReplacingUITabOverflowSelection = UInt8(0)
}
