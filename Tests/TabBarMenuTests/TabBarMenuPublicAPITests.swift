import Testing
import UIKit
@testable import TabBarMenu

@Test("anchor placement computes host button frames")
@MainActor
func anchorPlacementComputesHostButtonFrames() {
    let tabFrame = CGRect(x: 10, y: 20, width: 80, height: 40)

    #expect(tabBarMenuAnchorFrame(
        tabFrame: tabFrame,
        placement: .inside,
        defaultPlacement: .above(offset: 0)
    ) == CGRect(x: 49, y: 49, width: 2, height: 2))
    #expect(tabBarMenuAnchorFrame(
        tabFrame: tabFrame,
        placement: .above(offset: 8),
        defaultPlacement: .inside
    ) == CGRect(x: 49, y: 11, width: 2, height: 2))
    #expect(tabBarMenuAnchorFrame(
        tabFrame: tabFrame,
        placement: .custom(CGPoint(x: 7, y: 9)),
        defaultPlacement: .inside
    ) == CGRect(x: 6, y: 8, width: 2, height: 2))
    #expect(tabBarMenuAnchorFrame(
        tabFrame: tabFrame,
        placement: .manual,
        defaultPlacement: .inside
    ) == nil)
    #expect(tabBarMenuAnchorFrame(
        tabFrame: tabFrame,
        placement: nil,
        defaultPlacement: .above(offset: -12)
    ) == CGRect(x: 49, y: 31, width: 2, height: 2))
}

@Test("default above offset follows the runtime major version")
@MainActor
func defaultAboveOffsetFollowsRuntimeMajorVersion() {
    let expectedOffset: CGFloat = {
        if #available(iOS 26.0, *) {
            return 8
        }
        return -12
    }()

    #expect(TabBarMenuAnchorPlacement.defaultAboveOffset == expectedOffset)
}

@Test("updateTabBarMenu returns false when no menu host exists")
@MainActor
func updateTabBarMenuReturnsFalseWhenNoMenuHostExists() {
    let controller = UITabBarController()
    var updateCallCount = 0

    let didUpdate = controller.updateTabBarMenu { currentMenu in
        updateCallCount += 1
        return currentMenu
    }

    #expect(didUpdate == false)
    #expect(updateCallCount == 0)
}
