import UIKit
import TabBarMenuObjC

@MainActor
extension UITabBar {
    typealias TabBarMenuLayoutHandler = (UITabBar) -> Void
    typealias TabBarMenuSelectionHandler = (UITabBar, UITabBarItem) -> Bool
    typealias TabBarMenuControlSelectionHandler = (UITabBar, UIControl) -> Bool

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
                installSelectionOverrideIfNeeded()
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

    var tabBarMenuControlSelectionHandler: TabBarMenuControlSelectionHandler? {
        get {
            ObjectiveCInterop.associatedObject(for: self, key: &ItemsAssociatedKeys.controlSelectionHandler)
        }
        set {
            if newValue != nil {
                installSelectionOverrideIfNeeded()
            }
            ObjectiveCInterop.setAssociatedObject(
                newValue,
                for: self,
                key: &ItemsAssociatedKeys.controlSelectionHandler,
                policy: .OBJC_ASSOCIATION_COPY_NONATOMIC
            )
            TBMSetControlSelectionDidHandle(self, false)
            TBMSetControlSelectionHandler(self, newValue)
        }
    }

    var tabBarMenuInstalledSelectionOverrideKind: TBMSelectionOverrideKind {
        get {
            (ObjectiveCInterop.associatedObject(for: self, key: &ItemsAssociatedKeys.selectionOverrideKind) as NSNumber?)
                .map { TBMSelectionOverrideKind(rawValue: $0.intValue) ?? .none }
                ?? .none
        }
        set {
            ObjectiveCInterop.setAssociatedObject(
                NSNumber(value: newValue.rawValue),
                for: self,
                key: &ItemsAssociatedKeys.selectionOverrideKind,
                policy: .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    var tabBarMenuPreferredSelectionOverrideKind: TBMSelectionOverrideKind {
        get {
            (ObjectiveCInterop.associatedObject(for: self, key: &ItemsAssociatedKeys.preferredSelectionOverrideKind) as NSNumber?)
                .map { TBMSelectionOverrideKind(rawValue: $0.intValue) ?? .none }
                ?? .none
        }
        set {
            ObjectiveCInterop.setAssociatedObject(
                NSNumber(value: newValue.rawValue),
                for: self,
                key: &ItemsAssociatedKeys.preferredSelectionOverrideKind,
                policy: .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            tabBarMenuInstalledSelectionOverrideKind = .none
            TBMSetPreferredSelectionOverrideKind(self, newValue)
        }
    }

    private func installSelectionOverrideIfNeeded() {
        if tabBarMenuInstalledSelectionOverrideKind == .none {
            let installedKind = TBMInstallSelectionOverride(self)
            tabBarMenuInstalledSelectionOverrideKind = installedKind
        }
    }

    var tabBarMenuControlSelectionDidHandle: Bool {
        get {
            (ObjectiveCInterop.associatedObject(for: self, key: &ItemsAssociatedKeys.controlSelectionDidHandle) as NSNumber?)?.boolValue ?? false
        }
        set {
            ObjectiveCInterop.setAssociatedObject(
                NSNumber(value: newValue),
                for: self,
                key: &ItemsAssociatedKeys.controlSelectionDidHandle,
                policy: .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            TBMSetControlSelectionDidHandle(self, newValue)
        }
    }
}

@MainActor
private enum ItemsAssociatedKeys {
    static var layoutHandler = UInt8(0)
    static var selectionHandler = UInt8(1)
    static var controlSelectionHandler = UInt8(2)
    static var selectionOverrideKind = UInt8(3)
    static var preferredSelectionOverrideKind = UInt8(4)
    static var controlSelectionDidHandle = UInt8(5)
}
