import UIKit
import Combine
import ObjectiveC.runtime

@MainActor
extension UITabBarController {
    var tabsDidChangePublisher: AnyPublisher<[UITab], Never> {
        Self.swizzleTabsSetterIfNeeded()
        Self.swizzleSetTabsIfNeeded()
        return tabsDidChangeSubject.eraseToAnyPublisher()
    }

    private static var hasSwizzledTabsSetter = false
    private static var tabsSetterIMP: IMP?
    private static var hasSwizzledSetTabs = false
    private static var setTabsIMP: IMP?

    private static func swizzleTabsSetterIfNeeded() {
        guard !hasSwizzledTabsSetter else { return }
        let selector = #selector(setter: UITabBarController.tabs)
        guard let method = class_getInstanceMethod(UITabBarController.self, selector) else {
            return
        }
        hasSwizzledTabsSetter = true
        let originalImp = method_getImplementation(method)
        tabsSetterIMP = originalImp
        let block: @convention(block) (UITabBarController, [UITab]) -> Void = { controller, tabs in
            controller.performTabsMutation {
                if let imp = UITabBarController.tabsSetterIMP {
                    typealias Setter = @convention(c) (AnyObject, Selector, [UITab]) -> Void
                    let original = unsafeBitCast(imp, to: Setter.self)
                    original(controller, selector, tabs)
                }
            }
        }
        let newImp = imp_implementationWithBlock(block)
        method_setImplementation(method, newImp)
    }
    
    private static func swizzleSetTabsIfNeeded() {
        guard !hasSwizzledSetTabs else { return }
        let selector = #selector(UITabBarController.setTabs(_:animated:))
        guard let method = class_getInstanceMethod(UITabBarController.self, selector) else {
            return
        }
        hasSwizzledSetTabs = true
        let originalImp = method_getImplementation(method)
        setTabsIMP = originalImp
        let block: @convention(block) (UITabBarController, [UITab], Bool) -> Void = { controller, tabs, animated in
            controller.performTabsMutation {
                if let imp = UITabBarController.setTabsIMP {
                    typealias Setter = @convention(c) (AnyObject, Selector, [UITab], Bool) -> Void
                    let original = unsafeBitCast(imp, to: Setter.self)
                    original(controller, selector, tabs, animated)
                }
            }
        }
        let newImp = imp_implementationWithBlock(block)
        method_setImplementation(method, newImp)
    }

    private var tabsDidChangeSubject: PassthroughSubject<[UITab], Never> {
        if let subject = objc_getAssociatedObject(self, &TabsAssociatedKeys.subject) as? PassthroughSubject<[UITab], Never> {
            return subject
        }
        let subject = PassthroughSubject<[UITab], Never>()
        objc_setAssociatedObject(
            self,
            &TabsAssociatedKeys.subject,
            subject,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return subject
    }

    private func performTabsMutation(_ body: () -> Void) {
        tabsMutationDepth += 1
        body()
        tabsMutationDepth = max(tabsMutationDepth - 1, 0)
        if tabsMutationDepth == 0 {
            tabsDidChangeSubject.send(tabs)
        }
    }
    
    private var tabsMutationDepth: Int {
        get {
            (objc_getAssociatedObject(self, &TabsAssociatedKeys.mutationDepth) as? Int) ?? 0
        }
        set {
            objc_setAssociatedObject(
                self,
                &TabsAssociatedKeys.mutationDepth,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}
@MainActor
private enum TabsAssociatedKeys {
    static var subject = UInt8(0)
    static var mutationDepth = UInt8(1)
}
