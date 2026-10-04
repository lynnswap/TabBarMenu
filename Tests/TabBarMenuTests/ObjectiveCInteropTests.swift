import Foundation
import ObjectiveC
import Testing
@testable import TabBarMenu

@Suite(.serialized)
@MainActor
struct ObjectiveCInteropTests {
    @Test("reused messages use each receiver without retaining earlier receivers or results")
    func messagesDoNotRetainReceiversOrResults() {
        weak var originalReceiver: ObjectiveCInteropReceiver?
        weak var originalResult: NSObject?
        autoreleasepool {
            let receiver = ObjectiveCInteropReceiver()
            receiver.payload = NSObject()
            originalReceiver = receiver
            originalResult = receiver.payload
            #expect(ObjectiveCInterop.performObjectSelector("payload", on: receiver) === receiver.payload)
        }
        #expect(originalReceiver == nil)
        #expect(originalResult == nil)

        let second = ObjectiveCInteropReceiver()
        second.payload = NSObject()
        #expect(ObjectiveCInterop.performObjectSelector("payload", on: second) === second.payload)
    }

    @Test("reused messages follow current Objective-C dispatch")
    func messagesFollowCurrentDispatch() throws {
        let receiver = ObjectiveCInteropReceiver()
        receiver.number = 42
        #expect(ObjectiveCInterop.performUnsignedIntegerSelector("number", on: receiver) == 42)

        let original = try unsafe #require(class_getInstanceMethod(
            ObjectiveCInteropReceiver.self, #selector(getter: ObjectiveCInteropReceiver.number)
        ))
        let replacement = try unsafe #require(class_getInstanceMethod(
            ObjectiveCInteropReceiver.self, #selector(ObjectiveCInteropReceiver.replacementNumber)
        ))
        unsafe method_exchangeImplementations(original, replacement)
        defer { unsafe method_exchangeImplementations(original, replacement) }

        #expect(ObjectiveCInterop.performUnsignedIntegerSelector("number", on: receiver) == 99)
    }

    @Test("reused messages remain available across KVO class changes")
    func messagesSurviveKVOClassChanges() {
        let receiver = ObjectiveCInteropReceiver()
        receiver.number = 1
        #expect(ObjectiveCInterop.performUnsignedIntegerSelector("number", on: receiver) == 1)

        let observation = receiver.observe(\.number, options: [.new]) { _, _ in }
        receiver.number = 2
        #expect(ObjectiveCInterop.performUnsignedIntegerSelector("number", on: receiver) == 2)

        observation.invalidate()
        receiver.number = 3
        #expect(ObjectiveCInterop.performUnsignedIntegerSelector("number", on: receiver) == 3)
    }

    @Test("reused messages continue to honor responds(to:)")
    func messagesHonorSelectorAvailability() {
        let receiver = ObjectiveCInteropReceiver()
        receiver.number = 42
        #expect(ObjectiveCInterop.performUnsignedIntegerSelector("number", on: receiver) == 42)

        receiver.exposesNumber = false
        #expect(ObjectiveCInterop.performUnsignedIntegerSelector("number", on: receiver) == nil)

        receiver.exposesNumber = true
        #expect(ObjectiveCInterop.performUnsignedIntegerSelector("number", on: receiver) == 42)
    }

    @Test("an incompatible signature does not prevent a later compatible call")
    func incompatibleSignaturesRemainUnavailable() {
        let receiver = ObjectiveCInteropReceiver()
        receiver.number = 42
        #expect(ObjectiveCInterop.performBoolSelector("number", on: receiver) == nil)
        #expect(ObjectiveCInterop.performUnsignedIntegerSelector("number", on: receiver) == 42)
        #expect(ObjectiveCInterop.performObjectSelector("missingSelector", on: receiver) == nil)
    }
}

private final class ObjectiveCInteropReceiver: NSObject {
    @objc dynamic var payload: NSObject?
    @objc dynamic var number: UInt = 0
    var exposesNumber = true

    @objc dynamic func replacementNumber() -> UInt { 99 }

    override func responds(to selector: Selector!) -> Bool {
        if selector == #selector(getter: ObjectiveCInteropReceiver.number) {
            return exposesNumber
        }
        return super.responds(to: selector)
    }
}


@Test("Objective-C interop preserves object identity and optional nil results")
@MainActor
func objectiveCInteropPreservesObjectResults() {
    let receiver = InteropReceiver()
    let value = NSObject()

    #expect(ObjectiveCInterop.performObjectSelector("echo:", on: receiver, arguments: value) === value)
    #expect(ObjectiveCInterop.performObjectSelector("echo:", on: receiver, arguments: Optional<NSObject>.none) == nil)
}

@Test("Objective-C interop decodes Boolean and unsigned integer results")
@MainActor
func objectiveCInteropPreservesScalarResults() {
    let receiver = InteropReceiver()

    #expect(ObjectiveCInterop.performBoolSelector("booleanValue", on: receiver) == true)
    #expect(ObjectiveCInterop.performUnsignedIntegerSelector("unsignedValue", on: receiver) == UInt.max)
}

@Test("Objective-C interop forwards mixed arguments and reports void completion")
@MainActor
func objectiveCInteropForwardsMixedArguments() {
    let receiver = InteropReceiver()
    let value = NSObject()

    #expect(ObjectiveCInterop.performVoidSelector(
        "record:animated:count:", on: receiver, arguments: value, true, UInt.max
    ))
    #expect(receiver.recordedObject === value)
    #expect(receiver.recordedAnimated == true)
    #expect(receiver.recordedCount == UInt.max)

    #expect(ObjectiveCInterop.performVoidSelector(
        "record:animated:count:", on: receiver, arguments: Optional<NSObject>.none, false, UInt(0)
    ))
    #expect(receiver.recordedObject == nil)
    #expect(receiver.recordedAnimated == false)
    #expect(receiver.recordedCount == 0)
}

@Test("Unavailable Objective-C selectors preserve fallback without invoking native code")
@MainActor
func objectiveCInteropPreservesUnavailableOperations() {
    let receiver = InteropReceiver()

    #expect(ObjectiveCInterop.performObjectSelector("missingObject", on: receiver) == nil)
    #expect(ObjectiveCInterop.performVoidSelector("missingOperation", on: receiver) == false)
    #expect(ObjectiveCInterop.performObjectSelector("hiddenObject", on: receiver) == nil)
    #expect(receiver.hiddenObjectWasInvoked == false)
    #expect(ObjectiveCInterop.performBoolSelector("unsignedValue", on: receiver) == nil)
    #expect(ObjectiveCInterop.performVoidSelector("record:animated:count:", on: receiver) == false)
    #expect(receiver.recordedCount == nil)
}

@MainActor
private final class InteropReceiver: NSObject {
    var recordedObject: NSObject?
    var recordedAnimated: Bool?
    var recordedCount: UInt?
    var hiddenObjectWasInvoked = false

    @objc func echo(_ value: NSObject?) -> NSObject? { value }
    @objc var booleanValue: Bool { true }
    @objc var unsignedValue: UInt { UInt.max }

    @objc func record(_ value: NSObject?, animated: Bool, count: UInt) {
        recordedObject = value
        recordedAnimated = animated
        recordedCount = count
    }

    @objc func hiddenObject() -> NSObject {
        hiddenObjectWasInvoked = true
        return NSObject()
    }

    override func responds(to selector: Selector!) -> Bool {
        if selector == NSSelectorFromString("hiddenObject") { return false }
        return super.responds(to: selector)
    }
}
