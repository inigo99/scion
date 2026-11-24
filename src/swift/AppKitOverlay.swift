// The AppKit overlay (libswiftAppKit): the Swift-only AppKit API that compiled apps import. ponytail: only what apps
// have asked for (NSApplicationMain, NSEvent.SpecialKey, NSSound.beep); Apple's overlay has much more.
@_exported import AppKit

@_silgen_name("NSApplicationMain")
private func _NSApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

public func NSApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32 {
    _NSApplicationMain(argc, argv)
}

extension NSSound {
    public static func beep() { NSBeep() }
}

extension NSEvent {
    /// the function keys and the keys with a special meaning, by their character (NSUpArrowFunctionKey, ...)
    public struct SpecialKey: RawRepresentable, Equatable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public var unicodeScalar: Unicode.Scalar { Unicode.Scalar(UInt32(rawValue)) ?? " " }
        public static var upArrow: SpecialKey { .init(rawValue: 0xF700) }
        public static var downArrow: SpecialKey { .init(rawValue: 0xF701) }
        public static var leftArrow: SpecialKey { .init(rawValue: 0xF702) }
        public static var rightArrow: SpecialKey { .init(rawValue: 0xF703) }
        public static var f1: SpecialKey { .init(rawValue: 0xF704) }
        public static var f2: SpecialKey { .init(rawValue: 0xF705) }
        public static var f3: SpecialKey { .init(rawValue: 0xF706) }
        public static var f4: SpecialKey { .init(rawValue: 0xF707) }
        public static var f5: SpecialKey { .init(rawValue: 0xF708) }
        public static var f6: SpecialKey { .init(rawValue: 0xF709) }
        public static var f7: SpecialKey { .init(rawValue: 0xF70A) }
        public static var f8: SpecialKey { .init(rawValue: 0xF70B) }
        public static var f9: SpecialKey { .init(rawValue: 0xF70C) }
        public static var f10: SpecialKey { .init(rawValue: 0xF70D) }
        public static var f11: SpecialKey { .init(rawValue: 0xF70E) }
        public static var f12: SpecialKey { .init(rawValue: 0xF70F) }
        public static var f13: SpecialKey { .init(rawValue: 0xF710) }
        public static var f14: SpecialKey { .init(rawValue: 0xF711) }
        public static var f15: SpecialKey { .init(rawValue: 0xF712) }
        public static var f16: SpecialKey { .init(rawValue: 0xF713) }
        public static var f17: SpecialKey { .init(rawValue: 0xF714) }
        public static var f18: SpecialKey { .init(rawValue: 0xF715) }
        public static var f19: SpecialKey { .init(rawValue: 0xF716) }
        public static var f20: SpecialKey { .init(rawValue: 0xF717) }
        public static var f21: SpecialKey { .init(rawValue: 0xF718) }
        public static var f22: SpecialKey { .init(rawValue: 0xF719) }
        public static var f23: SpecialKey { .init(rawValue: 0xF71A) }
        public static var f24: SpecialKey { .init(rawValue: 0xF71B) }
        public static var f25: SpecialKey { .init(rawValue: 0xF71C) }
        public static var f26: SpecialKey { .init(rawValue: 0xF71D) }
        public static var f27: SpecialKey { .init(rawValue: 0xF71E) }
        public static var f28: SpecialKey { .init(rawValue: 0xF71F) }
        public static var f29: SpecialKey { .init(rawValue: 0xF720) }
        public static var f30: SpecialKey { .init(rawValue: 0xF721) }
        public static var f31: SpecialKey { .init(rawValue: 0xF722) }
        public static var f32: SpecialKey { .init(rawValue: 0xF723) }
        public static var f33: SpecialKey { .init(rawValue: 0xF724) }
        public static var f34: SpecialKey { .init(rawValue: 0xF725) }
        public static var f35: SpecialKey { .init(rawValue: 0xF726) }
        public static var insert: SpecialKey { .init(rawValue: 0xF727) }
        public static var deleteForward: SpecialKey { .init(rawValue: 0xF728) }
        public static var home: SpecialKey { .init(rawValue: 0xF729) }
        public static var end: SpecialKey { .init(rawValue: 0xF72B) }
        public static var pageUp: SpecialKey { .init(rawValue: 0xF72C) }
        public static var pageDown: SpecialKey { .init(rawValue: 0xF72D) }
        public static var clearLine: SpecialKey { .init(rawValue: 0xF739) }
        public static var help: SpecialKey { .init(rawValue: 0xF746) }
        public static var enter: SpecialKey { .init(rawValue: 0x03) }
        public static var backspace: SpecialKey { .init(rawValue: 0x08) }
        public static var tab: SpecialKey { .init(rawValue: 0x09) }
        public static var newline: SpecialKey { .init(rawValue: 0x0A) }
        public static var formFeed: SpecialKey { .init(rawValue: 0x0C) }
        public static var carriageReturn: SpecialKey { .init(rawValue: 0x0D) }
        public static var backTab: SpecialKey { .init(rawValue: 0x19) }
        public static var delete: SpecialKey { .init(rawValue: 0x7F) }
    }
    /// the key of a key event when it is one of the special keys
    public var specialKey: SpecialKey? {
        guard let c = charactersIgnoringModifiers?.unicodeScalars.first?.value else { return nil }
        switch c {
        case 0x03, 0x08, 0x09, 0x0A, 0x0C, 0x0D, 0x19, 0x7F, 0xF700...0xF8FF: return SpecialKey(rawValue: Int(c))
        default: return nil
        }
    }
}
