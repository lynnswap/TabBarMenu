import UIKit
import Combine

@MainActor
final class TabBarMenuCoordinator: NSObject, UIGestureRecognizerDelegate {
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
            stopObservingTabs()
            if let tabBar = self.tabBarController?.tabBar {
                removeLongPressGestures(from: tabBar)
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
            removeLongPressGestures(from: tabBar)
        }
        menuHostButton?.removeFromSuperview()
        menuHostButton = nil
        tabBarController = nil
    }

    func refreshInteractions() {
        guard let tabBarController = tabBarController else {
            return
        }
        let tabBar = tabBarController.tabBar
        removeLongPressGestures(from: tabBar)
        for (index, view) in tabBarIndexedViews(in: tabBar) {
            addLongPress(to: view, tabIndex: index)
        }
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

    private func addLongPress(to view: UIView, tabIndex: Int) {
        let recognizer = TabBarMenuLongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        recognizer.tabIndex = tabIndex
        recognizer.minimumPressDuration = configuration.minimumPressDuration
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = self
        view.addGestureRecognizer(recognizer)
    }

    private func removeLongPressGestures(from tabBar: UITabBar) {
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

    private func tabForMenu(at index: Int, in tabBarController: UITabBarController) -> UITab? {
        let tabs = tabBarController.tabs
        let maxVisibleCount = max(configuration.maxVisibleTabCount, 0)
        if maxVisibleCount > 0,
           tabs.count > maxVisibleCount,
           index == maxVisibleCount - 1 {
            return nil
        }
        guard tabs.indices.contains(index) else {
            return nil
        }
        return tabs[index]
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              let view = recognizer.view,
              let tabBarController = tabBarController,
              let longPressRecognizer = recognizer as? TabBarMenuLongPressGestureRecognizer else {
            return
        }
        let index = longPressRecognizer.tabIndex
        let tab = tabForMenu(at: index, in: tabBarController)
        let menu = delegate?.tabBarController(tabBarController, tab: tab)
        guard let tab,
              let menu,
              let containerView = tabBarController.view ?? view.window?.rootViewController?.view else {
            return
        }
        let hostButton = makeMenuHostButton(in: containerView)
        let tabFrame = view.convert(view.bounds, to: containerView)
        let placement = delegate?.tabBarController(
            tabBarController,
            configureMenuPresentationFor: tab,
            tabFrame: tabFrame,
            in: containerView,
            menuHostButton: hostButton
        )
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
        cancelTabBarTracking(for: view)
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
