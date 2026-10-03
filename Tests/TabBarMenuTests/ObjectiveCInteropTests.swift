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

        let original = try #require(unsafe class_getInstanceMethod(
            ObjectiveCInteropReceiver.self, #selector(getter: ObjectiveCInteropReceiver.number)
        ))
        let replacement = try #require(unsafe class_getInstanceMethod(
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
