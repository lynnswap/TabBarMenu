#import "TabBarMenuObjC.h"

#import <objc/message.h>
#import <objc/runtime.h>

static const char kMenuSubclassKey;
static const char kLayoutHandlerKey;
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
