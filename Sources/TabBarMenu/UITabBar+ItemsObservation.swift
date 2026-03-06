import UIKit
import TabBarMenuObjC

@MainActor
extension UITabBar {
    typealias TabBarMenuLayoutHandler = (UITabBar) -> Void
    typealias TabBarMenuSelectionHandler = (UITabBar, UITabBarItem) -> Bool

    var tabBarMenuLayoutHandler: TabBarMenuLayoutHandler? {
        get {
            ObjectiveCInterop.associatedObject(for: self, key: &ItemsAssociatedKeys.layoutHandler)
        }
        set {
            if newValue != nil {
                TBMInstallLayoutOverride(self)
            }
            ObjectiveCInterop.setAssociatedObject(
                newValue,
                for: self,
                key: &ItemsAssociatedKeys.layoutHandler,
                policy: .OBJC_ASSOCIATION_COPY_NONATOMIC
            )
            TBMSetLayoutHandler(self, newValue)
        }
    }

    var tabBarMenuSelectionHandler: TabBarMenuSelectionHandler? {
        get {
            ObjectiveCInterop.associatedObject(for: self, key: &ItemsAssociatedKeys.selectionHandler)
        }
        set {
            if newValue != nil {
                TBMInstallSelectionOverride(self)
            }
            ObjectiveCInterop.setAssociatedObject(
                newValue,
                for: self,
                key: &ItemsAssociatedKeys.selectionHandler,
                policy: .OBJC_ASSOCIATION_COPY_NONATOMIC
            )
            TBMSetSelectionHandler(self, newValue)
        }
    }
}

@MainActor
private enum ItemsAssociatedKeys {
    static var layoutHandler = UInt8(0)
    static var selectionHandler = UInt8(1)
}
