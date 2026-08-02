import Testing
import UIKit
@testable import TabBarMenu

@Test("explicit anchor placements compute host button frames")
@MainActor
func explicitAnchorPlacementsComputeHostButtonFrames() {
    let tabFrame = CGRect(x: 10, y: 20, width: 80, height: 40)

    #expect(tabBarMenuAnchorFrame(
        tabFrame: tabFrame,
        placement: .inside
    ) == CGRect(x: 49, y: 49, width: 2, height: 2))
    #expect(tabBarMenuAnchorFrame(
        tabFrame: tabFrame,
        placement: .above(offset: 8)
    ) == CGRect(x: 49, y: 11, width: 2, height: 2))
    #expect(tabBarMenuAnchorFrame(
        tabFrame: tabFrame,
        placement: .custom(CGPoint(x: 7, y: 9))
    ) == CGRect(x: 6, y: 8, width: 2, height: 2))
    #expect(tabBarMenuAnchorFrame(
        tabFrame: tabFrame,
        placement: .manual
    ) == nil)
}

@Test("anchor placement defaults above the tab")
@MainActor
func anchorPlacementDefaultsAboveTheTab() {
    let tabFrame = CGRect(x: 10, y: 20, width: 80, height: 40)
    let expectedAnchorY = tabFrame.minY - TabBarMenuAnchorPlacement.defaultAboveOffset

    #expect(tabBarMenuAnchorFrame(
        tabFrame: tabFrame,
        placement: nil
    ) == CGRect(x: 49, y: expectedAnchorY - 1, width: 2, height: 2))
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
