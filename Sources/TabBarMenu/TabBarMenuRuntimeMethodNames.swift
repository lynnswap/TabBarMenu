import Foundation

private extension [String] {
    var runtimeMethodName: String {
        reversed().joined()
    }
}

package enum UITabBarControllerRuntimeMethodNames {
    package static let setSelectedViewControllerAndNotify: String = {
        ["Notify:", "And", "Controller", "View", "Selected", "set", "_"].runtimeMethodName
    }()

    package static let setSelectedViewController: String = {
        ["Controller:", "View", "Selected", "set", "_"].runtimeMethodName
    }()

    package static let setSelectedTabBarItem: String = {
        ["Item:", "Bar", "Tab", "Selected", "set", "_"].runtimeMethodName
    }()

    package static let performWithIgnoringSelectionUpdate: String = {
        ["Update:block:", "Selection", "Ignoring", "With", "_perform"].runtimeMethodName
    }()

    package static let performWithoutNotifyingSelectionChange: String = {
        ["Change:", "Selection", "Notifying", "Without", "_perform"].runtimeMethodName
    }()

    package static let setTransientViewController: String = {
        ["Controller:", "View", "Transient", "set"].runtimeMethodName
    }()

    package static let setTransientViewControllerAnimated: String = {
        ["animated:", "Controller:", "View", "Transient", "set"].runtimeMethodName
    }()

    package static let transientViewController: String = {
        ["Controller", "View", "transient"].runtimeMethodName
    }()

    package static let setSelectedTab: String = {
        ["Tab:", "Selected", "set"].runtimeMethodName
    }()

    package static let selectTabElementIfPossible: String = {
        ["Possible:", "If", "Element", "Tab", "select", "_"].runtimeMethodName
    }()

    package static let selectedViewControllerInTabBar: String = {
        ["Bar", "Tab", "In", "Controller", "View", "selected", "_"].runtimeMethodName
    }()

    package static let selectedTabElement: String = {
        ["Element", "Tab", "selected", "_"].runtimeMethodName
    }()
}

package enum UITabRuntimeMethodNames {
    package static let displayedViewController: String = {
        ["Controller", "View", "displayed", "_"].runtimeMethodName
    }()

    package static let displayedViewControllers: String = {
        ["Controllers", "View", "displayed", "_"].runtimeMethodName
    }()

    package static let setDisplayedViewControllers: String = {
        ["Controllers:", "View", "Displayed", "set", "_"].runtimeMethodName
    }()

    package static let isMoreTab: String = {
        ["Tab", "More", "is", "_"].runtimeMethodName
    }()
}

package enum UIMoreNavigationControllerRuntimeMethodNames {
    package static let displayedViewController: String = {
        ["Controller", "View", "displayed"].runtimeMethodName
    }()

    package static let setDisplayedViewController: String = {
        ["Controller:", "View", "Displayed", "set"].runtimeMethodName
    }()

    package static let moreListController: String = {
        ["Controller", "List", "more"].runtimeMethodName
    }()

    package static let moreViewControllers: String = {
        ["Controllers", "View", "more"].runtimeMethodName
    }()

    package static let resolvedTab: String = {
        ["Tab", "resolved", "_"].runtimeMethodName
    }()

    package static let preparedViewController: String = {
        ["Controller:", "View", "prepared", "_"].runtimeMethodName
    }()

    package static let restoreOriginalNavigationController: String = {
        ["Controller", "Navigation", "Original", "restore", "_"].runtimeMethodName
    }()

    package static let restoreOriginalNavigationControllerIfNecessary: String = {
        ["Necessary:", "If", "Controller", "Navigation", "Original", "restore"].runtimeMethodName
    }()
}

package enum UITabBarControllerDelegateRuntimeMethodNames {
    package static let displayedViewControllersForTab: String = {
        ["proposedViewControllers:", "Tab:", "For", "Controllers", "View", "displayed", "Controller:", "Bar", "tab"].runtimeMethodName
    }()
}

package enum UITabBarControllerDelegateRuntimeMethods {
    package static let displayedViewControllersForTab = NSSelectorFromString(
        UITabBarControllerDelegateRuntimeMethodNames.displayedViewControllersForTab
    )
}

package enum UITabBarItemRuntimeMethodNames {
    package static let view: String = {
        ["view"].runtimeMethodName
    }()
}

package enum UITabBarItemRuntimeMethods {
    package static let view = NSSelectorFromString(UITabBarItemRuntimeMethodNames.view)
}

package enum UITabBarRuntimeMethodNames {
    package static let buttonUp: String = {
        ["Up:", "button", "_"].runtimeMethodName
    }()
}
