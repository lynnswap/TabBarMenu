#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TBMLayoutHandler)(UITabBar *tabBar);
typedef BOOL (^TBMSelectionHandler)(UITabBar *tabBar, UITabBarItem *item);
typedef BOOL (^TBMControlSelectionHandler)(UITabBar *tabBar, UIControl *control);

typedef NS_ENUM(NSInteger, TBMSelectionOverrideKind) {
    TBMSelectionOverrideKindNone = 0,
    TBMSelectionOverrideKindDidSelectButtonForItem = 1,
    TBMSelectionOverrideKindButtonUp = 2,
    TBMSelectionOverrideKindDidSelectButtonForItemAndButtonUp = 3,
};

FOUNDATION_EXPORT void TBMInstallLayoutOverride(UITabBar *tabBar);
FOUNDATION_EXPORT void TBMSetLayoutHandler(UITabBar *tabBar, TBMLayoutHandler _Nullable handler);

FOUNDATION_EXPORT TBMSelectionOverrideKind TBMInstallSelectionOverride(UITabBar *tabBar);
FOUNDATION_EXPORT void TBMSetSelectionHandler(UITabBar *tabBar, TBMSelectionHandler _Nullable handler);
FOUNDATION_EXPORT void TBMSetControlSelectionHandler(UITabBar *tabBar, TBMControlSelectionHandler _Nullable handler);
FOUNDATION_EXPORT void TBMSetPreferredSelectionOverrideKind(UITabBar *tabBar, TBMSelectionOverrideKind kind);

NS_ASSUME_NONNULL_END
