import ABIBridge
import Foundation
import ObjectiveC

@MainActor
package enum ObjectiveCInterop {
    private struct MethodKey: Hashable {
        let receiverClass: ObjectIdentifier
        let selector: String
        let signature: ObjectIdentifier
    }

    private static var preparedMethods: [MethodKey: Any] = [:]

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

    package static func performObjectSelector<each Argument>(
        _ name: String,
        on object: NSObject,
        arguments: repeat each Argument
    ) -> AnyObject? {
        invoke(name, on: object, returning: AnyObject?.self, arguments: repeat each arguments) ?? nil
    }

    package static func performBoolSelector(_ name: String, on object: NSObject) -> Bool? {
        invoke(name, on: object, returning: Bool.self)
    }

    package static func performUnsignedIntegerSelector(_ name: String, on object: NSObject) -> UInt? {
        invoke(name, on: object, returning: UInt.self)
    }

    package static func performVoidSelector<each Argument>(
        _ name: String,
        on object: NSObject,
        arguments: repeat each Argument
    ) -> Bool {
        invoke(name, on: object, returning: Void.self, arguments: repeat each arguments) != nil
    }

    @safe
    private static func invoke<Result, each Argument>(
        _ name: String,
        on object: NSObject,
        returning: Result.Type,
        arguments: repeat each Argument
    ) -> Result? {
        // Signature lookup can find methods a receiver deliberately hides from
        // optional-selector clients through responds(to:).
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        // KVO changes the runtime class without changing Swift's dynamic type.
        let receiverClass: AnyClass = object_getClass(object)!
        let signature = ((repeat each Argument) -> Result).self
        let key = MethodKey(
            receiverClass: ObjectIdentifier(receiverClass),
            selector: name,
            signature: ObjectIdentifier(signature)
        )
        if let method = preparedMethods[key] as? NativeObjCMethod<Result, repeat each Argument> {
            return try? unsafe method.unsafeInvoke(on: object, repeat each arguments)
        }
        // A missing or incompatible private selector is an unavailable operation.
        guard let method = try? ABIRuntime.shared.object(object).method(
            selector: selector,
            as: signature
        ) else { return nil }
        // Forwarding signatures can depend on the receiver; only share class-declared methods.
        if unsafe class_getInstanceMethod(receiverClass, selector) != nil {
            preparedMethods[key] = method.method
        }
        return try? unsafe method.unsafeInvoke(repeat each arguments)
    }
}
