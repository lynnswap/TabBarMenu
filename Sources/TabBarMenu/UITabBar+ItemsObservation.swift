import ABIBridge
import OSLog
import UIKit

@MainActor
extension UITabBar {
    typealias TabBarMenuLayoutHandler = (UITabBar) -> Void
    typealias TabBarMenuSelectionHandler = (UITabBar, UITabBarItem) -> Bool
    // nil leaves an unresolved control to UIKit's item-based selection path.
    typealias TabBarMenuControlSelectionHandler = (UITabBar, UIControl) -> Bool?

    var tabBarMenuLayoutHandler: TabBarMenuLayoutHandler? {
        get { tabBarMenuHooks.layoutHandler }
        set {
            let hooks = tabBarMenuHooks
            hooks.layoutHandler = newValue
            hooks.updateLayoutHook(on: self)
        }
    }

    var tabBarMenuSelectionHandler: TabBarMenuSelectionHandler? {
        get { tabBarMenuHooks.selectionHandler }
        set {
            let hooks = tabBarMenuHooks
            hooks.selectionHandler = newValue
            hooks.updateSelectionHooks(on: self)
        }
    }

    var tabBarMenuControlSelectionHandler: TabBarMenuControlSelectionHandler? {
        get { tabBarMenuHooks.controlSelectionHandler }
        set {
            let hooks = tabBarMenuHooks
            hooks.controlSelectionHandler = newValue
            hooks.updateSelectionHooks(on: self)
        }
    }

    var tabBarMenuInstalledSelectionOverrideKind: TabBarMenuSelectionOverrideKind {
        tabBarMenuHooks.installedSelectionOverrideKind
    }

    var tabBarMenuPreferredSelectionOverrideKind: TabBarMenuSelectionOverrideKind {
        get { tabBarMenuHooks.preferredSelectionOverrideKind }
        set {
            let hooks = tabBarMenuHooks
            hooks.preferredSelectionOverrideKind = newValue
            hooks.itemHook = nil
            hooks.controlHook = nil
            hooks.updateSelectionHooks(on: self)
        }
    }

    private var tabBarMenuHooks: TabBarMenuHooks {
        if let hooks: TabBarMenuHooks = ObjectiveCInterop.associatedObject(for: self, key: &ItemsAssociatedKeys.hooks) {
            return hooks
        }
        let hooks = TabBarMenuHooks()
        ObjectiveCInterop.setAssociatedObject(hooks, for: self, key: &ItemsAssociatedKeys.hooks, policy: .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return hooks
    }
}

enum TabBarMenuSelectionOverrideKind {
    case none, didSelectButtonForItem, buttonUp, didSelectButtonForItemAndButtonUp
}

@MainActor
private final class TabBarMenuHooks {
    var layoutHandler: UITabBar.TabBarMenuLayoutHandler?
    var selectionHandler: UITabBar.TabBarMenuSelectionHandler?
    var controlSelectionHandler: UITabBar.TabBarMenuControlSelectionHandler?
    var preferredSelectionOverrideKind: TabBarMenuSelectionOverrideKind = .none
    var layoutHook: NativeObjCMethodHook?
    var itemHook: NativeObjCMethodHook?
    var controlHook: NativeObjCMethodHook?
    private var bypassItemHook = false

    var installedSelectionOverrideKind: TabBarMenuSelectionOverrideKind {
        switch (itemHook != nil, controlHook != nil) {
        case (true, true): .didSelectButtonForItemAndButtonUp
        case (true, false): .didSelectButtonForItem
        case (false, true): .buttonUp
        case (false, false): .none
        }
    }

    func updateLayoutHook(on tabBar: UITabBar) {
        guard layoutHandler != nil else {
            layoutHook = nil
            return
        }
        guard layoutHook == nil else { return }
        layoutHook = install(on: tabBar, selector: "layoutSubviews", as: (() -> Void).self) { [weak self, weak tabBar] call in
            try call.proceed()
            if let tabBar { self?.layoutHandler?(tabBar) }
        }
    }

    func updateSelectionHooks(on tabBar: UITabBar) {
        guard selectionHandler != nil || controlSelectionHandler != nil else {
            itemHook = nil
            controlHook = nil
            return
        }
        if itemHook == nil, preferredSelectionOverrideKind != .buttonUp {
            itemHook = install(
                on: tabBar, selector: UITabBarRuntimeMethodNames.didSelectButtonForItem,
                as: ((AnyObject?) -> Void).self
            ) { [weak self, weak tabBar] call, item in
                guard let self, let tabBar else { return try call.proceed(item) }
                if self.bypassItemHook {
                    self.bypassItemHook = false
                } else if let item = item as? UITabBarItem, self.selectionHandler?(tabBar, item) == false {
                    return
                }
                try call.proceed(item)
            }
        }
        if controlHook == nil, preferredSelectionOverrideKind != .didSelectButtonForItem {
            controlHook = install(
                on: tabBar, selector: UITabBarRuntimeMethodNames.buttonUp,
                as: ((AnyObject?) -> Void).self
            ) { [weak self, weak tabBar] call, sender in
                guard let self, let tabBar,
                      let control = sender as? UIControl,
                      let shouldCallDefault = self.controlSelectionHandler?(tabBar, control) else {
                    return try call.proceed(sender)
                }
                guard shouldCallDefault else { return }
                self.bypassItemHook = true
                defer { self.bypassItemHook = false }
                try call.proceed(sender)
            }
        }
    }

    @safe
    private func install<each Argument>(
        on tabBar: UITabBar,
        selector: String,
        as signature: ((repeat each Argument) -> Void).Type,
        body: @escaping @MainActor @Sendable (NativeObjCMethodInvocation<Void, repeat each Argument>, repeat each Argument) throws -> Void
    ) -> NativeObjCMethodHook? {
        guard tabBar.responds(to: NSSelectorFromString(selector)) else { return nil }
        do {
            // Swift's dynamic type excludes KVO's temporary subclass. Keep the hook
            // reachable after observation ends, and filter to this tab bar ourselves.
            return try unsafe ABIRuntime.shared.hookMainActorMethod(
                on: type(of: tabBar), selector: selector, as: signature,
                onFailure: { error in
                    runtimeHookLogger.error("\(selector, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            ) { [weak tabBar] (call: NativeObjCMethodInvocation<Void, repeat each Argument>, arguments: repeat each Argument) in
                guard let tabBar, try call.receiver === tabBar else {
                    return try call.proceed(repeat each arguments)
                }
                try body(call, repeat each arguments)
            }
        } catch {
            runtimeHookLogger.error("Installing \(selector, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

private let runtimeHookLogger = Logger(subsystem: "TabBarMenu", category: "RuntimeHooks")

@MainActor
private enum ItemsAssociatedKeys {
    static var hooks = UInt8(0)
}
