#import "TabBarMenuObjC.h"

#import <objc/message.h>
#import <objc/runtime.h>

static const char kMenuSubclassKey;
static const char kItemsMutationDepthKey;
static const char kItemsDidChangeHandlerKey;
static const char kSelectionHandlerKey;

static NSString *const kSubclassPrefix = @"TabBarMenu_";

static SEL TBMDidSelectButtonForItemSelector(void)
{
    static SEL selector;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *parts = @[ @"Item:", @"For", @"Button", @"Select", @"did", @"_" ];
        NSString *name = [[[parts reverseObjectEnumerator] allObjects] componentsJoinedByString:@""];
        selector = NSSelectorFromString(name);
    });
    return selector;
}

static NSInteger TBMItemsMutationDepth(UITabBar *tabBar)
{
    NSNumber *value = objc_getAssociatedObject(tabBar, &kItemsMutationDepthKey);
    return value ? value.integerValue : 0;
}

static void TBMSetItemsMutationDepth(UITabBar *tabBar, NSInteger depth)
{
    NSInteger clamped = depth < 0 ? 0 : depth;
    objc_setAssociatedObject(tabBar, &kItemsMutationDepthKey, @(clamped), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void TBMPerformItemsMutation(UITabBar *tabBar, void (^block)(void))
{
    TBMSetItemsMutationDepth(tabBar, TBMItemsMutationDepth(tabBar) + 1);
    block();
    TBMSetItemsMutationDepth(tabBar, TBMItemsMutationDepth(tabBar) - 1);
    if (TBMItemsMutationDepth(tabBar) == 0) {
        TBMItemsDidChangeHandler handler = objc_getAssociatedObject(tabBar, &kItemsDidChangeHandlerKey);
        if (handler) {
            handler(tabBar);
        }
    }
}

static void TBMCallSuperSetItems(id self, SEL _cmd, NSArray *items)
{
    Class superClass = class_getSuperclass(object_getClass(self));
    if (!superClass) {
        return;
    }
    struct objc_super superInfo = {
        .receiver = self,
        .super_class = superClass
    };
    ((void (*)(struct objc_super *, SEL, NSArray *))objc_msgSendSuper)(&superInfo, _cmd, items);
}

static void TBMCallSuperSetItemsAnimated(id self, SEL _cmd, NSArray *items, BOOL animated)
{
    Class superClass = class_getSuperclass(object_getClass(self));
    if (!superClass) {
        return;
    }
    struct objc_super superInfo = {
        .receiver = self,
        .super_class = superClass
    };
    ((void (*)(struct objc_super *, SEL, NSArray *, BOOL))objc_msgSendSuper)(&superInfo, _cmd, items, animated);
}

static void TBMCallSuperDidSelectButtonForItem(id self, SEL _cmd, id item)
{
    Class superClass = class_getSuperclass(object_getClass(self));
    if (!superClass) {
        return;
    }
    struct objc_super superInfo = {
        .receiver = self,
        .super_class = superClass
    };
    ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&superInfo, _cmd, item);
}

static void TBM_setItems(id self, SEL _cmd, NSArray *items)
{
    TBMPerformItemsMutation((UITabBar *)self, ^{
        TBMCallSuperSetItems(self, _cmd, items);
    });
}

static void TBM_setItemsAnimated(id self, SEL _cmd, NSArray *items, BOOL animated)
{
    TBMPerformItemsMutation((UITabBar *)self, ^{
        TBMCallSuperSetItemsAnimated(self, _cmd, items, animated);
    });
}

static void TBM_didSelectButtonForItem(id self, SEL _cmd, id item)
{
    UITabBar *tabBar = (UITabBar *)self;
    if ([item isKindOfClass:[UITabBarItem class]]) {
        TBMSelectionHandler handler = objc_getAssociatedObject(tabBar, &kSelectionHandlerKey);
        if (handler && handler(tabBar, (UITabBarItem *)item) == NO) {
            return;
        }
    }
    TBMCallSuperDidSelectButtonForItem(self, _cmd, item);
}

static Class TBMEnsureSubclass(UITabBar *tabBar)
{
    Class subclass = objc_getAssociatedObject(tabBar, &kMenuSubclassKey);
    if (subclass) {
        if (object_getClass(tabBar) != subclass) {
            object_setClass(tabBar, subclass);
        }
        return subclass;
    }

    Class baseClass = object_getClass(tabBar);
    if (!baseClass) {
        return Nil;
    }
    NSString *baseClassName = [NSString stringWithUTF8String:class_getName(baseClass)];
    if ([baseClassName hasPrefix:kSubclassPrefix]) {
        objc_setAssociatedObject(tabBar, &kMenuSubclassKey, baseClass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return baseClass;
    }

    NSString *subclassName = [NSString stringWithFormat:@"%@%@_%p", kSubclassPrefix, baseClassName, tabBar];
    subclass = objc_allocateClassPair(baseClass, subclassName.UTF8String, 0);
    if (!subclass) {
        static uint64_t counter = 0;
        counter += 1;
        NSString *fallbackName = [NSString stringWithFormat:@"%@%@_%p_%llu", kSubclassPrefix, baseClassName, tabBar, counter];
        subclass = objc_allocateClassPair(baseClass, fallbackName.UTF8String, 0);
    }
    if (!subclass) {
        return Nil;
    }

    objc_registerClassPair(subclass);
    objc_setAssociatedObject(tabBar, &kMenuSubclassKey, subclass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    object_setClass(tabBar, subclass);
    return subclass;
}

static void TBMAddItemsOverrides(Class subclass)
{
    Class baseClass = class_getSuperclass(subclass);
    if (!baseClass) {
        return;
    }
    SEL itemsSelector = @selector(setItems:);
    Method itemsMethod = class_getInstanceMethod(baseClass, itemsSelector);
    if (itemsMethod) {
        class_addMethod(subclass, itemsSelector, (IMP)TBM_setItems, method_getTypeEncoding(itemsMethod));
    }
    SEL setItemsAnimatedSelector = @selector(setItems:animated:);
    Method setItemsAnimatedMethod = class_getInstanceMethod(baseClass, setItemsAnimatedSelector);
    if (setItemsAnimatedMethod) {
        class_addMethod(subclass, setItemsAnimatedSelector, (IMP)TBM_setItemsAnimated, method_getTypeEncoding(setItemsAnimatedMethod));
    }
}

static void TBMAddSelectionOverride(Class subclass)
{
    Class baseClass = class_getSuperclass(subclass);
    if (!baseClass) {
        return;
    }
    SEL selector = TBMDidSelectButtonForItemSelector();
    Method method = class_getInstanceMethod(baseClass, selector);
    if (!method) {
        return;
    }
    class_addMethod(subclass, selector, (IMP)TBM_didSelectButtonForItem, method_getTypeEncoding(method));
}

void TBMInstallItemsOverrides(UITabBar *tabBar)
{
    if (!tabBar) {
        return;
    }
    Class subclass = TBMEnsureSubclass(tabBar);
    if (!subclass) {
        return;
    }
    TBMAddItemsOverrides(subclass);
}

void TBMSetItemsDidChangeHandler(UITabBar *tabBar, TBMItemsDidChangeHandler handler)
{
    if (!tabBar) {
        return;
    }
    objc_setAssociatedObject(tabBar, &kItemsDidChangeHandlerKey, handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

void TBMInstallSelectionOverride(UITabBar *tabBar)
{
    if (!tabBar) {
        return;
    }
    Class subclass = TBMEnsureSubclass(tabBar);
    if (!subclass) {
        return;
    }
    TBMAddSelectionOverride(subclass);
}

void TBMSetSelectionHandler(UITabBar *tabBar, TBMSelectionHandler handler)
{
    if (!tabBar) {
        return;
    }
    objc_setAssociatedObject(tabBar, &kSelectionHandlerKey, handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
