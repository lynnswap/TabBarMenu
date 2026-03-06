#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TBMLayoutHandler)(UITabBar *tabBar);
typedef BOOL (^TBMSelectionHandler)(UITabBar *tabBar, UITabBarItem *item);

FOUNDATION_EXPORT void TBMInstallLayoutOverride(UITabBar *tabBar);
FOUNDATION_EXPORT void TBMSetLayoutHandler(UITabBar *tabBar, TBMLayoutHandler _Nullable handler);

FOUNDATION_EXPORT void TBMInstallSelectionOverride(UITabBar *tabBar);
FOUNDATION_EXPORT void TBMSetSelectionHandler(UITabBar *tabBar, TBMSelectionHandler _Nullable handler);

NS_ASSUME_NONNULL_END
