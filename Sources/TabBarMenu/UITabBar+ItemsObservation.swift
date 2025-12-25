import UIKit
import Combine
import ObjectiveC.runtime

@MainActor
extension UITabBar {
    var itemsDidChangePublisher: AnyPublisher<[UITabBarItem], Never> {
        Self.swizzleItemsSetterIfNeeded()
        Self.swizzleSetItemsIfNeeded()
        return itemsDidChangeSubject.eraseToAnyPublisher()
    }

    private static var hasSwizzledItemsSetter = false
    private static var itemsSetterIMP: IMP?
    private static var hasSwizzledSetItems = false
    private static var setItemsIMP: IMP?

    private static func swizzleItemsSetterIfNeeded() {
        guard !hasSwizzledItemsSetter else { return }
        let selector = #selector(setter: UITabBar.items)
        guard let method = class_getInstanceMethod(UITabBar.self, selector) else {
            return
        }
        hasSwizzledItemsSetter = true
        let originalImp = method_getImplementation(method)
        itemsSetterIMP = originalImp
        let block: @convention(block) (UITabBar, [UITabBarItem]?) -> Void = { tabBar, items in
            tabBar.performItemsMutation {
                if let imp = UITabBar.itemsSetterIMP {
                    typealias Setter = @convention(c) (AnyObject, Selector, [UITabBarItem]?) -> Void
                    let original = unsafeBitCast(imp, to: Setter.self)
                    original(tabBar, selector, items)
                }
            }
        }
        let newImp = imp_implementationWithBlock(block)
        method_setImplementation(method, newImp)
    }

    private static func swizzleSetItemsIfNeeded() {
        guard !hasSwizzledSetItems else { return }
        let selector = #selector(UITabBar.setItems(_:animated:))
        guard let method = class_getInstanceMethod(UITabBar.self, selector) else {
            return
        }
        hasSwizzledSetItems = true
        let originalImp = method_getImplementation(method)
        setItemsIMP = originalImp
        let block: @convention(block) (UITabBar, [UITabBarItem]?, Bool) -> Void = { tabBar, items, animated in
            tabBar.performItemsMutation {
                if let imp = UITabBar.setItemsIMP {
                    typealias Setter = @convention(c) (AnyObject, Selector, [UITabBarItem]?, Bool) -> Void
                    let original = unsafeBitCast(imp, to: Setter.self)
                    original(tabBar, selector, items, animated)
                }
            }
        }
        let newImp = imp_implementationWithBlock(block)
        method_setImplementation(method, newImp)
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
}
