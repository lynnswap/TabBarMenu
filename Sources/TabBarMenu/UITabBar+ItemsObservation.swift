import UIKit
import Combine
import ObjectiveC.runtime
import TabBarMenuObjC

@MainActor
extension UITabBar {
    var itemsDidChangePublisher: AnyPublisher<[UITabBarItem], Never> {
        TBMInstallItemsOverrides(self)
        TBMSetItemsDidChangeHandler(self) { [weak self] _ in
            guard let self else { return }
            self.itemsDidChangeSubject.send(self.items ?? [])
        }
        return itemsDidChangeSubject.eraseToAnyPublisher()
    }

    typealias TabBarMenuSelectionHandler = (UITabBar, UITabBarItem) -> Bool

    var tabBarMenuSelectionHandler: TabBarMenuSelectionHandler? {
        get {
            objc_getAssociatedObject(self, &ItemsAssociatedKeys.selectionHandler) as? TabBarMenuSelectionHandler
        }
        set {
            TBMInstallSelectionOverride(self)
            objc_setAssociatedObject(
                self,
                &ItemsAssociatedKeys.selectionHandler,
                newValue,
                .OBJC_ASSOCIATION_COPY_NONATOMIC
            )
            TBMSetSelectionHandler(self, newValue)
        }
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
}

@MainActor
private enum ItemsAssociatedKeys {
    static var subject = UInt8(0)
    static var selectionHandler = UInt8(1)
}
