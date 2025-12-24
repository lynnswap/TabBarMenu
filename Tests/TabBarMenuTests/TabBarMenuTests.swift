import Testing
import UIKit
@testable import TabBarMenu

private enum TestConstants {
    static let menuGesturePrefix = "tabbar.menu."
}

@MainActor
private final class TestMenuDelegate: TabBarMenuDelegate {
    private(set) var requestedIdentifiers: [String] = []
    private let menu: UIMenu

    init(menu: UIMenu = UIMenu(children: [])) {
        self.menu = menu
    }

    func tabBarController(_ tabBarController: UITabBarController, tab: UITab) -> UIMenu? {
        requestedIdentifiers.append(tab.identifier)
        return menu
    }
}

@MainActor
private final class SelfDelegatingTabBarController: UITabBarController, TabBarMenuDelegate {
    func tabBarController(_ tabBarController: UITabBarController, tab: UITab) -> UIMenu? {
        UIMenu(children: [])
    }
}

@MainActor
private final class WindowHost {
    let window: UIWindow

    init(rootViewController: UIViewController) {
        window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        rootViewController.loadViewIfNeeded()
        window.layoutIfNeeded()
    }
}

@MainActor
private struct TabBarTestContext {
    let controller: UITabBarController
    let host: WindowHost
    let tabs: [UITab]
}

@MainActor
private func makeTabs(count: Int) -> [UITab] {
    (0..<count).map { index in
        UITab(
            title: "Tab \(index)",
            image: nil,
            identifier: "tab.\(index)",
            viewControllerProvider: { _ in UIViewController() }
        )
    }
}

@MainActor
private func makeTabBarTestContext(tabCount: Int) -> TabBarTestContext {
    let tabs = makeTabs(count: tabCount)
    let controller = UITabBarController(tabs: tabs)
    let host = WindowHost(rootViewController: controller)
    return TabBarTestContext(controller: controller, host: host, tabs: tabs)
}
@MainActor
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
@MainActor
private func tabBarItemView(_ item: UITabBarItem) -> UIView? {
    let selector = NSSelectorFromString("view")
    guard item.responds(to: selector) else {
        return nil
    }
    return item.perform(selector)?.takeUnretainedValue() as? UIView
}
@MainActor
private func tabBarButtonViews(in tabBar: UITabBar) -> [UIView] {
    if let items = tabBar.items, !items.isEmpty {
        let itemViews = items.compactMap { tabBarItemView($0) }
        if !itemViews.isEmpty {
            return itemViews
        }
    }
    return tabBarControls(in: tabBar)
}
@MainActor
private func menuLongPressRecognizers(in tabBar: UITabBar) -> [UILongPressGestureRecognizer] {
    let controls = tabBarControls(in: tabBar)
    return controls.flatMap { control in
        (control.gestureRecognizers ?? []).compactMap { recognizer in
            guard let longPress = recognizer as? UILongPressGestureRecognizer,
                  let name = longPress.name,
                  name.hasPrefix(TestConstants.menuGesturePrefix) else {
                return nil
            }
            return longPress
        }
    }
}
@MainActor
private func menuRecognizerNames(in tabBar: UITabBar) -> Set<String> {
    Set(menuLongPressRecognizers(in: tabBar).compactMap(\.name))
}

@Test("menuDelegate attaches long-press gestures")
@MainActor
func menuDelegateAttachesLongPressGestures() async {
    let context = makeTabBarTestContext(tabCount: 3)
    let delegate = TestMenuDelegate()

    context.controller.menuDelegate = delegate

    #expect(context.controller.menuDelegate === delegate)
    let names = menuRecognizerNames(in: context.controller.tabBar)
    let buttonViews = tabBarButtonViews(in: context.controller.tabBar)
    let expectedCount = min(context.tabs.count, buttonViews.count)
    let expectedNames = Set(
        context.tabs.prefix(expectedCount).map { TestConstants.menuGesturePrefix + $0.identifier }
    )

    #expect(names.count == expectedCount)
    #expect(names == expectedNames)
    #expect(context.host.window.rootViewController === context.controller)
}

@Test("menuDelegate supports self assignment")
@MainActor
func menuDelegateSupportsSelfAssignment() async {
    let controller = SelfDelegatingTabBarController()
    controller.tabs = makeTabs(count: 2)
    let host = WindowHost(rootViewController: controller)

    controller.menuDelegate = controller

    #expect(controller.menuDelegate === controller)
    let names = menuRecognizerNames(in: controller.tabBar)
    let buttonViews = tabBarButtonViews(in: controller.tabBar)
    let expectedCount = min(controller.tabs.count, buttonViews.count)
    let expectedNames = Set(
        controller.tabs.prefix(expectedCount).map { TestConstants.menuGesturePrefix + $0.identifier }
    )

    #expect(names == expectedNames)
    #expect(host.window.rootViewController === controller)
}

@Test("menuDelegate refreshes long-press gestures when tabs change")
@MainActor
func menuDelegateRefreshesLongPressGesturesWhenTabsChange() async {
    let context = makeTabBarTestContext(tabCount: 2)
    let delegate = TestMenuDelegate()

    context.controller.menuDelegate = delegate

    let initialNames = menuRecognizerNames(in: context.controller.tabBar)

    let updatedTabs = (0..<3).map { index in
        UITab(
            title: "Updated \(index)",
            image: nil,
            identifier: "updated.\(index)",
            viewControllerProvider: { _ in UIViewController() }
        )
    }

    context.controller.tabs = updatedTabs
    context.controller.view.setNeedsLayout()
    context.host.window.layoutIfNeeded()
    await Task.yield()

    let updatedNames = menuRecognizerNames(in: context.controller.tabBar)
    let buttonViews = tabBarButtonViews(in: context.controller.tabBar)
    let expectedCount = min(updatedTabs.count, buttonViews.count)
    let expectedNames = Set(
        updatedTabs.prefix(expectedCount).map { TestConstants.menuGesturePrefix + $0.identifier }
    )

    #expect(updatedNames == expectedNames)
    #expect(updatedNames != initialNames)
}

@Test("menuDelegate clears long-press gestures when unset")
@MainActor
func menuDelegateClearsLongPressGesturesWhenUnset() async {
    let context = makeTabBarTestContext(tabCount: 2)
    let delegate = TestMenuDelegate()

    context.controller.menuDelegate = delegate
    #expect(!menuRecognizerNames(in: context.controller.tabBar).isEmpty)

    context.controller.menuDelegate = nil
    #expect(menuRecognizerNames(in: context.controller.tabBar).isEmpty)
}

@Test("menuDelegate does not duplicate long-press gestures")
@MainActor
func menuDelegateDoesNotDuplicateLongPressGestures() async {
    let context = makeTabBarTestContext(tabCount: 2)
    let delegate = TestMenuDelegate()

    context.controller.menuDelegate = delegate
    let initialNames = menuRecognizerNames(in: context.controller.tabBar)

    context.controller.menuDelegate = delegate
    let updatedNames = menuRecognizerNames(in: context.controller.tabBar)

    #expect(updatedNames == initialNames)
}

@Test("coordinator reattaches to a different tab bar controller")
@MainActor
func coordinatorReattachesToDifferentTabBarController() async {
    let firstContext = makeTabBarTestContext(tabCount: 2)
    let secondContext = makeTabBarTestContext(tabCount: 2)
    let delegate = TestMenuDelegate()
    let coordinator = TabBarMenuCoordinator()

    coordinator.delegate = delegate
    coordinator.attach(to: firstContext.controller)

    #expect(!menuRecognizerNames(in: firstContext.controller.tabBar).isEmpty)

    coordinator.attach(to: secondContext.controller)

    #expect(menuRecognizerNames(in: firstContext.controller.tabBar).isEmpty)
    #expect(!menuRecognizerNames(in: secondContext.controller.tabBar).isEmpty)
}

@Test("gesture count matches the available button views")
@MainActor
func gestureCountMatchesAvailableButtonViews() async {
    let context = makeTabBarTestContext(tabCount: 6)
    let delegate = TestMenuDelegate()

    context.controller.menuDelegate = delegate

    let buttonViews = tabBarButtonViews(in: context.controller.tabBar)
    let expectedCount = min(context.tabs.count, buttonViews.count)
    let names = menuRecognizerNames(in: context.controller.tabBar)

    #expect(names.count == expectedCount)
}
