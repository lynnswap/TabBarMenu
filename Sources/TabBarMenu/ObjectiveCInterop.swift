import ABIBridge
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
        guard object.responds(to: NSSelectorFromString(name)) else { return nil }
        // A missing or incompatible private selector is an unavailable operation.
        guard let method = try? ABIRuntime.shared.object(object).method(
            selector: name,
            as: ((repeat each Argument) -> Result).self
        ) else { return nil }
        return try? unsafe method.unsafeInvoke(repeat each arguments)
    }
}
