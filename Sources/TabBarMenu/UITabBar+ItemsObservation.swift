import UIKit
import Combine
import ObjectiveC.runtime

@MainActor
extension UITabBar {
    var itemsDidChangePublisher: AnyPublisher<[UITabBarItem], Never> {
        Self.installItemsOverridesIfNeeded(on: self)
        return itemsDidChangeSubject.eraseToAnyPublisher()
    }

    typealias TabBarMenuSelectionHandler = (UITabBar, UITabBarItem) -> Bool

    var tabBarMenuSelectionHandler: TabBarMenuSelectionHandler? {
        get {
            objc_getAssociatedObject(self, &ItemsAssociatedKeys.selectionHandler) as? TabBarMenuSelectionHandler
        }
        set {
            Self.installSelectionOverrideIfNeeded(on: self)
            objc_setAssociatedObject(
                self,
                &ItemsAssociatedKeys.selectionHandler,
                newValue,
                .OBJC_ASSOCIATION_COPY_NONATOMIC
            )
        }
    }

    private static let didSelectButtonForItemSelectorParts = ["Item:", "For", "Button", "Select", "did", "_"]
    private static let tabBarMenuSubclassPrefix = "TabBarMenu_"

    private static func installItemsOverridesIfNeeded(on tabBar: UITabBar) {
        guard let subclass = installSubclassIfNeeded(on: tabBar) else {
            return
        }
        addItemsSetterOverride(to: subclass)
        addSetItemsOverride(to: subclass)
    }

    private static func installSelectionOverrideIfNeeded(on tabBar: UITabBar) {
        guard let subclass = installSubclassIfNeeded(on: tabBar) else {
            return
        }
        addDidSelectButtonForItemOverride(to: subclass)
    }

    private static func installSubclassIfNeeded(on tabBar: UITabBar) -> AnyClass? {
        if let subclass = objc_getAssociatedObject(tabBar, &ItemsAssociatedKeys.menuSubclass) as? AnyClass {
            if object_getClass(tabBar) != subclass {
                object_setClass(tabBar, subclass)
            }
            return subclass
        }

        guard let baseClass = object_getClass(tabBar) else {
            return nil
        }
        let baseClassName = String(cString: class_getName(baseClass))
        if baseClassName.hasPrefix(tabBarMenuSubclassPrefix) {
            objc_setAssociatedObject(
                tabBar,
                &ItemsAssociatedKeys.menuSubclass,
                baseClass,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            return baseClass
        }

        let subclassName = "\(tabBarMenuSubclassPrefix)\(baseClassName)_\(uniqueSuffix(for: tabBar))"
        guard let subclass = objc_allocateClassPair(baseClass, subclassName, 0) else {
            return nil
        }

        objc_registerClassPair(subclass)
        objc_setAssociatedObject(
            tabBar,
            &ItemsAssociatedKeys.menuSubclass,
            subclass,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        object_setClass(tabBar, subclass)
        return subclass
    }

    private static func uniqueSuffix(for tabBar: UITabBar) -> String {
        String(UInt(bitPattern: Unmanaged.passUnretained(tabBar).toOpaque()))
    }

    private static func addItemsSetterOverride(to subclass: AnyClass) {
        guard let baseClass = class_getSuperclass(subclass) else {
            return
        }
        let selector = #selector(setter: UITabBar.items)
        guard let method = class_getInstanceMethod(baseClass, selector) else {
            return
        }
        let originalImp = method_getImplementation(method)
        let block: @convention(block) (UITabBar, [UITabBarItem]?) -> Void = { tabBar, items in
            tabBar.performItemsMutation {
                typealias Setter = @convention(c) (AnyObject, Selector, [UITabBarItem]?) -> Void
                let original = unsafeBitCast(originalImp, to: Setter.self)
                original(tabBar, selector, items)
            }
        }
        let newImp = imp_implementationWithBlock(block)
        class_addMethod(subclass, selector, newImp, method_getTypeEncoding(method))
    }

    private static func addSetItemsOverride(to subclass: AnyClass) {
        guard let baseClass = class_getSuperclass(subclass) else {
            return
        }
        let selector = #selector(UITabBar.setItems(_:animated:))
        guard let method = class_getInstanceMethod(baseClass, selector) else {
            return
        }
        let originalImp = method_getImplementation(method)
        let block: @convention(block) (UITabBar, [UITabBarItem]?, Bool) -> Void = { tabBar, items, animated in
            tabBar.performItemsMutation {
                typealias Setter = @convention(c) (AnyObject, Selector, [UITabBarItem]?, Bool) -> Void
                let original = unsafeBitCast(originalImp, to: Setter.self)
                original(tabBar, selector, items, animated)
            }
        }
        let newImp = imp_implementationWithBlock(block)
        class_addMethod(subclass, selector, newImp, method_getTypeEncoding(method))
    }

    private static func addDidSelectButtonForItemOverride(to subclass: AnyClass) {
        guard let baseClass = class_getSuperclass(subclass) else {
            return
        }
        let selector = NSSelectorFromString(Self.didSelectButtonForItemSelectorParts.reversed().joined())
        guard let method = class_getInstanceMethod(baseClass, selector) else {
            return
        }
        let originalImp = method_getImplementation(method)
        let block: @convention(block) (UITabBar, AnyObject?) -> Void = { tabBar, item in
            @MainActor
            func callOrig() {
                typealias Original = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
                let original = unsafeBitCast(originalImp, to: Original.self)
                original(tabBar, selector, item)
            }

            guard let tabBarItem = item as? UITabBarItem else {
                callOrig()
                return
            }
            if let handler = tabBar.tabBarMenuSelectionHandler, handler(tabBar, tabBarItem) == false {
                return
            }
            callOrig()
        }
        let newImp = imp_implementationWithBlock(block)
        class_addMethod(subclass, selector, newImp, method_getTypeEncoding(method))
    }

    private var itemsDidChangeSubject: PassthroughSubject<[UITabBarItem], Never> {
        if let subject = objc_getAssociatedObject(self, &ItemsAssociatedKeys.subject) as? PassthroughSubject<[UITabBarItem], Never> {
            return subject
        }
        let subject = PassthroughSubject<[UITabBarItem], Never>()
        objc_setAssociatedObject(
            self,
            &ItemsAssociatedKeys.subject,
            subject,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return subject
    }

    private func performItemsMutation(_ body: () -> Void) {
        itemsMutationDepth += 1
        body()
        itemsMutationDepth = max(itemsMutationDepth - 1, 0)
        if itemsMutationDepth == 0 {
            itemsDidChangeSubject.send(items ?? [])
        }
    }

    private var itemsMutationDepth: Int {
        get {
            (objc_getAssociatedObject(self, &ItemsAssociatedKeys.mutationDepth) as? Int) ?? 0
        }
        set {
            objc_setAssociatedObject(
                self,
                &ItemsAssociatedKeys.mutationDepth,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

@MainActor
private enum ItemsAssociatedKeys {
    static var subject = UInt8(0)
    static var mutationDepth = UInt8(1)
    static var selectionHandler = UInt8(2)
    static var menuSubclass = UInt8(3)
}
