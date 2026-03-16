#import "TabBarMenuObjC.h"

#import <objc/message.h>
#import <objc/runtime.h>

static const char kMenuSubclassKey;
static const char kLayoutHandlerKey;
static const char kSelectionHandlerKey;
static const char kControlSelectionHandlerKey;
static const char kControlSelectionDidHandleKey;
static const char kSelectionOverrideKindKey;
static const char kPreferredSelectionOverrideKindKey;
static const char kSelectionBypassItemHookKey;

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

static SEL TBMButtonUpSelector(void)
{
    static SEL selector;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *parts = @[ @"Up:", @"button", @"_" ];
        NSString *name = [[[parts reverseObjectEnumerator] allObjects] componentsJoinedByString:@""];
        selector = NSSelectorFromString(name);
    });
    return selector;
}

static void TBMCallSuperLayoutSubviews(id self, SEL _cmd)
{
    Class superClass = class_getSuperclass(object_getClass(self));
    if (!superClass) {
        return;
    }
    struct objc_super superInfo = {
        .receiver = self,
        .super_class = superClass
    };
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&superInfo, _cmd);
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

static void TBMCallSuperButtonUp(id self, SEL _cmd, id sender)
{
    Class superClass = class_getSuperclass(object_getClass(self));
    if (!superClass) {
        return;
    }
    struct objc_super superInfo = {
        .receiver = self,
        .super_class = superClass
    };
    ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&superInfo, _cmd, sender);
}

static void TBM_layoutSubviews(id self, SEL _cmd)
{
    TBMCallSuperLayoutSubviews(self, _cmd);

    UITabBar *tabBar = (UITabBar *)self;
    TBMLayoutHandler handler = objc_getAssociatedObject(tabBar, &kLayoutHandlerKey);
    if (handler) {
        handler(tabBar);
    }
}

static void TBM_didSelectButtonForItem(id self, SEL _cmd, id item)
{
    UITabBar *tabBar = (UITabBar *)self;
    NSNumber *bypassItemHook = objc_getAssociatedObject(tabBar, &kSelectionBypassItemHookKey);
    if (bypassItemHook.boolValue) {
        objc_setAssociatedObject(tabBar, &kSelectionBypassItemHookKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        TBMCallSuperDidSelectButtonForItem(self, _cmd, item);
        return;
    }
    if ([item isKindOfClass:[UITabBarItem class]]) {
        TBMSelectionHandler handler = objc_getAssociatedObject(tabBar, &kSelectionHandlerKey);
        if (handler && handler(tabBar, (UITabBarItem *)item) == NO) {
            return;
        }
    }
    TBMCallSuperDidSelectButtonForItem(self, _cmd, item);
}

static void TBM_buttonUp(id self, SEL _cmd, id sender)
{
    UITabBar *tabBar = (UITabBar *)self;
    if ([sender isKindOfClass:[UIControl class]]) {
        TBMControlSelectionHandler handler = objc_getAssociatedObject(tabBar, &kControlSelectionHandlerKey);
        if (handler) {
            BOOL shouldCallDefault = handler(tabBar, (UIControl *)sender);
            NSNumber *didHandle = objc_getAssociatedObject(tabBar, &kControlSelectionDidHandleKey);
            if (didHandle.boolValue == NO) {
                TBMCallSuperButtonUp(self, _cmd, sender);
                return;
            }
            if (shouldCallDefault == NO) {
                objc_setAssociatedObject(tabBar, &kSelectionBypassItemHookKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                return;
            }
            objc_setAssociatedObject(tabBar, &kSelectionBypassItemHookKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            TBMCallSuperButtonUp(self, _cmd, sender);
            objc_setAssociatedObject(tabBar, &kSelectionBypassItemHookKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
    }
    TBMCallSuperButtonUp(self, _cmd, sender);
}

static Class TBMEnsureSubclass(UITabBar *tabBar)
{
    Class currentClass = object_getClass(tabBar);
    if (!currentClass) {
        return Nil;
    }

    Class subclass = objc_getAssociatedObject(tabBar, &kMenuSubclassKey);
    if (subclass && currentClass == subclass) {
        return subclass;
    }

    NSString *currentClassName = [NSString stringWithUTF8String:class_getName(currentClass)];
    if ([currentClassName hasPrefix:kSubclassPrefix]) {
        objc_setAssociatedObject(tabBar, &kMenuSubclassKey, currentClass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return currentClass;
    }

    NSString *subclassName = [NSString stringWithFormat:@"%@%@_%p", kSubclassPrefix, currentClassName, tabBar];
    subclass = objc_allocateClassPair(currentClass, subclassName.UTF8String, 0);
    if (!subclass) {
        static uint64_t counter = 0;
        counter += 1;
        NSString *fallbackName = [NSString stringWithFormat:@"%@%@_%p_%llu", kSubclassPrefix, currentClassName, tabBar, counter];
        subclass = objc_allocateClassPair(currentClass, fallbackName.UTF8String, 0);
    }
    if (!subclass) {
        return Nil;
    }

    objc_registerClassPair(subclass);
    objc_setAssociatedObject(tabBar, &kMenuSubclassKey, subclass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    object_setClass(tabBar, subclass);
    return subclass;
}

static void TBMAddLayoutOverride(Class subclass)
{
    Class baseClass = class_getSuperclass(subclass);
    if (!baseClass) {
        return;
    }
    SEL selector = @selector(layoutSubviews);
    Method method = class_getInstanceMethod(baseClass, selector);
    if (method) {
        class_addMethod(subclass, selector, (IMP)TBM_layoutSubviews, method_getTypeEncoding(method));
    }
}

static BOOL TBMAddSelectionOverrideForSelector(Class subclass, SEL selector, IMP implementation)
{
    Class baseClass = class_getSuperclass(subclass);
    if (!baseClass) {
        return NO;
    }
    Method method = class_getInstanceMethod(baseClass, selector);
    if (!method) {
        return NO;
    }
    return class_addMethod(subclass, selector, implementation, method_getTypeEncoding(method));
}

static NSNumber *TBMSelectionOverrideKindNumber(TBMSelectionOverrideKind kind)
{
    return @(kind);
}

static TBMSelectionOverrideKind TBMPreferredSelectionOverrideKind(UITabBar *tabBar)
{
    NSNumber *kindNumber = objc_getAssociatedObject(tabBar, &kPreferredSelectionOverrideKindKey);
    if (!kindNumber) {
        return TBMSelectionOverrideKindNone;
    }
    return (TBMSelectionOverrideKind)kindNumber.integerValue;
}

void TBMInstallLayoutOverride(UITabBar *tabBar)
{
    if (!tabBar) {
        return;
    }
    Class subclass = TBMEnsureSubclass(tabBar);
    if (!subclass) {
        return;
    }
    TBMAddLayoutOverride(subclass);
}

void TBMSetLayoutHandler(UITabBar *tabBar, TBMLayoutHandler handler)
{
    if (!tabBar) {
        return;
    }
    objc_setAssociatedObject(tabBar, &kLayoutHandlerKey, handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

TBMSelectionOverrideKind TBMInstallSelectionOverride(UITabBar *tabBar)
{
    if (!tabBar) {
        return TBMSelectionOverrideKindNone;
    }

    NSNumber *installedKindNumber = objc_getAssociatedObject(tabBar, &kSelectionOverrideKindKey);
    if (installedKindNumber) {
        return (TBMSelectionOverrideKind)installedKindNumber.integerValue;
    }

    Class subclass = TBMEnsureSubclass(tabBar);
    if (!subclass) {
        return TBMSelectionOverrideKindNone;
    }

    TBMSelectionOverrideKind preferredKind = TBMPreferredSelectionOverrideKind(tabBar);
    TBMSelectionOverrideKind installedKind = TBMSelectionOverrideKindNone;

    BOOL installedDidSelectHook = NO;
    BOOL installedButtonUpHook = NO;

    if (preferredKind == TBMSelectionOverrideKindDidSelectButtonForItem ||
        preferredKind == TBMSelectionOverrideKindDidSelectButtonForItemAndButtonUp ||
        preferredKind == TBMSelectionOverrideKindNone) {
        installedDidSelectHook = TBMAddSelectionOverrideForSelector(
            subclass,
            TBMDidSelectButtonForItemSelector(),
            (IMP)TBM_didSelectButtonForItem
        );
    }

    if (preferredKind == TBMSelectionOverrideKindButtonUp ||
        preferredKind == TBMSelectionOverrideKindDidSelectButtonForItemAndButtonUp ||
        preferredKind == TBMSelectionOverrideKindNone) {
        installedButtonUpHook = TBMAddSelectionOverrideForSelector(
            subclass,
            TBMButtonUpSelector(),
            (IMP)TBM_buttonUp
        );
    }

    if (installedDidSelectHook && installedButtonUpHook) {
        installedKind = TBMSelectionOverrideKindDidSelectButtonForItemAndButtonUp;
    } else if (installedDidSelectHook) {
        installedKind = TBMSelectionOverrideKindDidSelectButtonForItem;
    } else if (installedButtonUpHook) {
        installedKind = TBMSelectionOverrideKindButtonUp;
    }

    objc_setAssociatedObject(
        tabBar,
        &kSelectionOverrideKindKey,
        TBMSelectionOverrideKindNumber(installedKind),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    return installedKind;
}

void TBMSetSelectionHandler(UITabBar *tabBar, TBMSelectionHandler handler)
{
    if (!tabBar) {
        return;
    }
    objc_setAssociatedObject(tabBar, &kSelectionHandlerKey, handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

void TBMSetControlSelectionHandler(UITabBar *tabBar, TBMControlSelectionHandler handler)
{
    if (!tabBar) {
        return;
    }
    objc_setAssociatedObject(tabBar, &kControlSelectionHandlerKey, handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

void TBMSetControlSelectionDidHandle(UITabBar *tabBar, BOOL didHandle)
{
    if (!tabBar) {
        return;
    }
    objc_setAssociatedObject(tabBar, &kControlSelectionDidHandleKey, @(didHandle), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void TBMSetPreferredSelectionOverrideKind(UITabBar *tabBar, TBMSelectionOverrideKind kind)
{
    if (!tabBar) {
        return;
    }
    objc_setAssociatedObject(
        tabBar,
        &kPreferredSelectionOverrideKindKey,
        TBMSelectionOverrideKindNumber(kind),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    objc_setAssociatedObject(tabBar, &kSelectionOverrideKindKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
