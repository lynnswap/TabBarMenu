import Foundation
import ObjectiveC

@MainActor
package enum ObjectiveCInterop {
    @safe
    package static func associatedObject<Value>(
        for object: AnyObject,
        key: inout UInt8
    ) -> Value? {
        unsafe objc_getAssociatedObject(object, &key) as? Value
    }

    @safe
    package static func setAssociatedObject(
        _ value: Any?,
        for object: AnyObject,
        key: inout UInt8,
        policy: objc_AssociationPolicy
    ) {
        unsafe objc_setAssociatedObject(object, &key, value, policy)
    }

    @safe
    package static func performObjectSelector(
        _ name: String,
        on object: NSObject
    ) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else {
            return nil
        }
        return unsafe object.perform(selector)?.takeUnretainedValue()
    }

    @safe
    package static func performObjectSelector(
        _ name: String,
        on object: NSObject,
        with argument: AnyObject?
    ) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else {
            return nil
        }
        return unsafe object.perform(selector, with: argument)?.takeUnretainedValue()
    }

    @safe
    package static func performObjectSelector(
        _ name: String,
        on object: NSObject,
        with firstArgument: AnyObject?,
        with secondArgument: AnyObject?,
        with thirdArgument: AnyObject?
    ) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else {
            return nil
        }

        typealias Function = @convention(c) (
            AnyObject,
            Selector,
            AnyObject?,
            AnyObject?,
            AnyObject?
        ) -> Unmanaged<AnyObject>?
        let implementation = unsafe unsafeBitCast(
            object.method(for: selector),
            to: Function.self
        )
        return unsafe implementation(object, selector, firstArgument, secondArgument, thirdArgument)?
            .takeUnretainedValue()
    }

    @safe
    package static func performBoolSelector(
        _ name: String,
        on object: NSObject
    ) -> Bool? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else {
            return nil
        }

        typealias Function = @convention(c) (AnyObject, Selector) -> Bool
        let implementation = unsafe unsafeBitCast(
            object.method(for: selector),
            to: Function.self
        )
        return implementation(object, selector)
    }

    @safe
    package static func performVoidSelector(
        _ name: String,
        on object: NSObject
    ) -> Bool {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else {
            return false
        }
        unsafe _ = object.perform(selector)
        return true
    }

    @safe
    package static func performVoidSelector(
        _ name: String,
        on object: NSObject,
        with argument: AnyObject?
    ) -> Bool {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else {
            return false
        }
        unsafe _ = object.perform(selector, with: argument)
        return true
    }

    @safe
    package static func performVoidSelector(
        _ name: String,
        on object: NSObject,
        with firstArgument: AnyObject?,
        with secondArgument: AnyObject?
    ) -> Bool {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else {
            return false
        }

        typealias Function = @convention(c) (
            AnyObject,
            Selector,
            AnyObject?,
            AnyObject?
        ) -> Void
        let implementation = unsafe unsafeBitCast(
            object.method(for: selector),
            to: Function.self
        )
        implementation(object, selector, firstArgument, secondArgument)
        return true
    }

    @safe
    package static func performVoidSelector(
        _ name: String,
        on object: NSObject,
        object argument: AnyObject?,
        bool flag: Bool
    ) -> Bool {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else {
            return false
        }

        typealias Function = @convention(c) (AnyObject, Selector, AnyObject?, Bool) -> Void
        let implementation = unsafe unsafeBitCast(
            object.method(for: selector),
            to: Function.self
        )
        implementation(object, selector, argument, flag)
        return true
    }

    @safe
    package static func performVoidSelector(
        _ name: String,
        on object: NSObject,
        block: @escaping @convention(block) () -> Void
    ) -> Bool {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else {
            return false
        }

        typealias Function = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let implementation = unsafe unsafeBitCast(
            object.method(for: selector),
            to: Function.self
        )
        let blockObject = unsafe unsafeBitCast(block, to: AnyObject.self)
        implementation(object, selector, blockObject)
        return true
    }

    @safe
    package static func performVoidSelector(
        _ name: String,
        on object: NSObject,
        bool flag: Bool,
        block: @escaping @convention(block) () -> Void
    ) -> Bool {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else {
            return false
        }

        typealias Function = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        let implementation = unsafe unsafeBitCast(
            object.method(for: selector),
            to: Function.self
        )
        let blockObject = unsafe unsafeBitCast(block, to: AnyObject.self)
        implementation(object, selector, flag, blockObject)
        return true
    }
}
