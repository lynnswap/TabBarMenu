// The Swift Programming Language
// https://docs.swift.org/swift-book

import SwiftUI
import ObjectiveC
import Combine


@MainActor
/// A delegate that provides contextual menus for tabs in a `UITabBarController`.
/// - Important: Return `nil` to disable the menu for a given tab.
public protocol TabBarMenuDelegate: AnyObject {
    /// Asks the delegate for the menu to present for the specified tab.
    /// - Parameters:
    ///   - tabBarController: The tab bar controller requesting the menu.
    ///   - tab: The tab associated with the long-pressed item.
    /// - Returns: A `UIMenu` to present, or `nil` to skip presenting a menu.
    func tabBarController(_ tabBarController: UITabBarController, tab: UITab) -> UIMenu?
}

@MainActor
public extension UITabBarController {
    /// The delegate that supplies menus for tab bar items.
    /// Set this to automatically attach menu handling to the tab bar controller.
    /// Set to `nil` to remove menu handling and associated gestures.
    var menuDelegate: TabBarMenuDelegate? {
        get {
            tabBarMenuCoordinator?.delegate
        }
        set {
            if let delegate = newValue {
                let coordinator = tabBarMenuCoordinator ?? TabBarMenuCoordinator()
                coordinator.delegate = delegate
                coordinator.attach(to: self)
                tabBarMenuCoordinator = coordinator
            } else {
                if let coordinator = tabBarMenuCoordinator {
                    coordinator.delegate = nil
                    coordinator.detach()
                }
                tabBarMenuCoordinator = nil
            }
        }
    }

    private var tabBarMenuCoordinator: TabBarMenuCoordinator? {
        get {
            objc_getAssociatedObject(self, &TabBarMenuAssociatedKeys.coordinator) as? TabBarMenuCoordinator
        }
        set {
            objc_setAssociatedObject(
                self,
                &TabBarMenuAssociatedKeys.coordinator,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}


@MainActor
final class TabBarMenuCoordinator: NSObject, UIGestureRecognizerDelegate {
    private static let longPressNamePrefix = "tabbar.menu."

    weak var delegate: TabBarMenuDelegate?
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

        let buttons = tabBarButtonViews(in: tabBar)
            .sorted { left, right in
                let leftFrame = left.convert(left.bounds, to: tabBar)
                let rightFrame = right.convert(right.bounds, to: tabBar)
                return leftFrame.minX < rightFrame.minX
            }

        removeLongPressGestures(from: tabBar)
        let tabs = tabBarController.tabs
        let count = min(buttons.count, tabs.count)
        for index in 0..<count {
            addLongPress(to: buttons[index], tabIdentifier: tabs[index].identifier)
        }
    }

    private func startObservingTabs() {
        guard let tabBarController = tabBarController, cancellables.isEmpty else {
            return
        }
        tabBarController.publisher(for: \.tabs)
            .removeDuplicates(by: { left, right in
                left.map(\.identifier) == right.map(\.identifier)
            })
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

    private func addLongPress(to view: UIView, tabIdentifier: String) {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        recognizer.name = Self.longPressNamePrefix + tabIdentifier
        recognizer.minimumPressDuration = 0.35
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
                guard let name = recognizer.name,
                      name.hasPrefix(Self.longPressNamePrefix) else {
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
              let tabBarController = tabBarController,
              let name = recognizer.name,
              name.hasPrefix(Self.longPressNamePrefix) else {
            return
        }
        let identifier = String(name.dropFirst(Self.longPressNamePrefix.count))
        guard !identifier.isEmpty,
              let tab = tabBarController.tab(forIdentifier: identifier),
              let menu = delegate?.tabBarController(tabBarController, tab: tab),
              let containerView = tabBarController.view ?? view.window?.rootViewController?.view else {
            return
        }
        let hostButton = makeMenuHostButton(in: containerView)
        let tabFrame = view.convert(view.bounds, to: containerView)
        let anchorPoint = CGPoint(x: tabFrame.midX, y: ( tabFrame.maxY + tabFrame.midY) * 0.5 )
        let anchorSize: CGFloat = 2
        hostButton.frame = CGRect(
            x: anchorPoint.x,
            y: anchorPoint.y,
            width: anchorSize,
            height: anchorSize
        )
        hostButton.menu = menu
        presentMenu(from: hostButton)
        cancelTabBarTracking(for: view)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    private func tabBarButtonViews(in tabBar: UITabBar) -> [UIView] {
        if let items = tabBar.items, !items.isEmpty {
            let itemViews = items.compactMap { item -> UIView? in
                tabBarItemView(item)
            }
            if !itemViews.isEmpty {
                return itemViews
            }
        }

        return tabBarControls(in: tabBar)
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
private enum TabBarMenuAssociatedKeys {
    static var coordinator = UInt8(0)
}

private final class MenuHostButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return false
    }
}

#if DEBUG

private final class TabBarMenuPreviewController: UITabBarController, TabBarMenuDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()

        tabs = [
            makeTab(title: "Home", systemImageName: "house", identifier: "home"),
            makeTab(title: "Profile", systemImageName: "person", identifier: "profile")
        ]
        menuDelegate = self
    }

    func tabBarController(_ tabBarController: UITabBarController, tab: UITab) -> UIMenu? {
        let rename = UIAction(title: "Rename") { _ in }
        let delete = UIAction(title: "Delete", attributes: .destructive) { _ in }
        return UIMenu(title: tab.title, children: [rename, delete])
    }

    private func makeTab(title: String, systemImageName: String, identifier: String) -> UITab {
        UITab(title: title, image: UIImage(systemName: systemImageName), identifier: identifier) { _ in
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            controller.title = title
            return controller
        }
    }
}

private struct TabBarMenuPreview: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UITabBarController {
        TabBarMenuPreviewController()
    }
    func updateUIViewController(_ uiViewController: UITabBarController, context: Context) {}
}

#Preview("TabBarMenu") {
    TabBarMenuPreview()
        .ignoresSafeArea()
}

#endif
