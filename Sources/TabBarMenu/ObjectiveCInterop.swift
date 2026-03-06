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
}
