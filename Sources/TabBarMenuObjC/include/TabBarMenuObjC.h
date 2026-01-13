#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TBMItemsDidChangeHandler)(UITabBar *tabBar);
typedef BOOL (^TBMSelectionHandler)(UITabBar *tabBar, UITabBarItem *item);

FOUNDATION_EXPORT void TBMInstallItemsOverrides(UITabBar *tabBar);
FOUNDATION_EXPORT void TBMSetItemsDidChangeHandler(UITabBar *tabBar, TBMItemsDidChangeHandler _Nullable handler);

FOUNDATION_EXPORT void TBMInstallSelectionOverride(UITabBar *tabBar);
FOUNDATION_EXPORT void TBMSetSelectionHandler(UITabBar *tabBar, TBMSelectionHandler _Nullable handler);

NS_ASSUME_NONNULL_END
