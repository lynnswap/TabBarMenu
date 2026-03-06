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
            ObjectiveCInterop.associatedObject(for: self, key: &ItemsAssociatedKeys.selectionHandler)
        }
        set {
            TBMInstallSelectionOverride(self)
            ObjectiveCInterop.setAssociatedObject(
                newValue,
                for: self,
                key: &ItemsAssociatedKeys.selectionHandler,
                policy: .OBJC_ASSOCIATION_COPY_NONATOMIC
            )
            TBMSetSelectionHandler(self, newValue)
        }
    }

    private var itemsDidChangeSubject: PassthroughSubject<[UITabBarItem], Never> {
        if let subject: PassthroughSubject<[UITabBarItem], Never> = ObjectiveCInterop.associatedObject(
            for: self,
            key: &ItemsAssociatedKeys.subject
        ) {
            return subject
        }
        let subject = PassthroughSubject<[UITabBarItem], Never>()
        ObjectiveCInterop.setAssociatedObject(
            subject,
            for: self,
            key: &ItemsAssociatedKeys.subject,
            policy: .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return subject
    }
}

@MainActor
private enum ItemsAssociatedKeys {
    static var subject = UInt8(0)
    static var selectionHandler = UInt8(1)
}
