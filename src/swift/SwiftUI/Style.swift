// Text, Font, Color, Image and shape styles.
import Foundation
import AppKit

// MARK: - Font

@frozen public struct Font: Hashable {
    @usableFromInline internal var provider: _MWFontBox
    init(_ p: _MWFontBox) { provider = p }
    public static func == (a: Font, b: Font) -> Bool { a.provider.key == b.provider.key }
    public func hash(into h: inout Hasher) { h.combine(provider.key) }

    public enum TextStyle: CaseIterable, Hashable, Sendable {
        case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2
        var size: CGFloat {
            switch self {
            case .largeTitle: return 26
            case .title: return 22
            case .title2: return 17
            case .title3: return 15
            case .headline, .body: return 13
            case .callout: return 12
            case .subheadline: return 11
            case .footnote, .caption: return 10
            case .caption2: return 10
            }
        }
    }
    public enum Design: Hashable, Sendable {
        case `default`, serif, rounded, monospaced
    }
    @frozen public struct Weight: Hashable {
        @usableFromInline internal var value: CGFloat
        @usableFromInline init(value: CGFloat) { self.value = value }
        public static let ultraLight = Weight(value: -0.8)
        public static let thin = Weight(value: -0.6)
        public static let light = Weight(value: -0.4)
        public static let regular = Weight(value: 0)
        public static let medium = Weight(value: 0.23)
        public static let semibold = Weight(value: 0.3)
        public static let bold = Weight(value: 0.4)
        public static let heavy = Weight(value: 0.56)
        public static let black = Weight(value: 0.62)
    }
    public static let largeTitle = Font.system(.largeTitle)
    public static let title = Font.system(.title)
    public static let title2 = Font.system(.title2)
    public static let title3 = Font.system(.title3)
    public static let headline = Font(_MWFontBox(size: 13, weight: .bold, design: .default, key: "headline"))
    public static let subheadline = Font.system(.subheadline)
    public static let body = Font.system(.body)
    public static let callout = Font.system(.callout)
    public static let footnote = Font.system(.footnote)
    public static let caption = Font.system(.caption)
    public static let caption2 = Font.system(.caption2)
    public static func system(_ style: Font.TextStyle, design: Font.Design = .default) -> Font {
        Font(_MWFontBox(size: style.size, weight: style == .headline ? .bold : .regular, design: design, key: "\(style)\(design)"))
    }
    public static func system(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> Font {
        Font(_MWFontBox(size: style.size, weight: weight ?? (style == .headline ? .bold : .regular), design: design ?? .default, key: "\(style)\(String(describing: design))\(String(describing: weight))"))
    }
    public static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        Font(_MWFontBox(size: size, weight: weight, design: design, key: "\(size)\(weight.value)\(design)"))
    }
    public static func system(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        system(size: size, weight: weight ?? .regular, design: design ?? .default)
    }
    public static func custom(_ name: String, size: CGFloat) -> Font {
        let b = _MWFontBox(size: size, weight: .regular, design: .default, key: "\(name)\(size)"); b.name = name; return Font(b)
    }
    public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font { custom(name, size: size) }
    public static func custom(_ name: String, fixedSize: CGFloat) -> Font { custom(name, size: fixedSize) }
    public init(_ font: CTFont) { let f = font as NSFont; let b = _MWFontBox(size: f.pointSize, weight: .regular, design: .default, key: f.fontName); b.name = f.fontName; provider = b }
    func modified(_ f: (_MWFontBox) -> Void) -> Font {
        let b = _MWFontBox(size: provider.size, weight: provider.weight, design: provider.design, key: provider.key)
        b.name = provider.name; b.italic = provider.italic
        f(b)
        b.key = "\(b.name ?? "")\(b.size)\(b.weight.value)\(b.design)\(b.italic)"
        return Font(b)
    }
    public func weight(_ weight: Font.Weight) -> Font { modified { $0.weight = weight } }
    public func bold() -> Font { weight(.bold) }
    public func italic() -> Font { modified { $0.italic = true } }
    public func monospacedDigit() -> Font { self }
    public func monospaced() -> Font { modified { $0.design = .monospaced } }
    public func smallCaps() -> Font { self }
    public func leading(_ leading: Font.Leading) -> Font { self }
    public enum Leading: Hashable, Sendable { case standard, tight, loose }
    var nsFont: NSFont { provider.nsFont }
}
public typealias CTFont = NSFont

@usableFromInline internal final class _MWFontBox {
    var size: CGFloat, weight: Font.Weight, design: Font.Design, key: String
    var name: String?
    var italic = false
    init(size: CGFloat, weight: Font.Weight, design: Font.Design, key: String) { self.size = size; self.weight = weight; self.design = design; self.key = key }
    var nsFont: NSFont {
        if let n = name, let f = NSFont(name: n, size: size) { return f }
        if design == .monospaced { return NSFont.userFixedPitchFont(ofSize: size) ?? NSFont.systemFont(ofSize: size) }
        return weight.value >= 0.3 ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    }
}

// MARK: - Color

@frozen public struct Color: Hashable, CustomStringConvertible {
    @usableFromInline internal var provider: _MWColorBox
    init(_ p: _MWColorBox) { provider = p }
    init(ns: @escaping () -> NSColor, key: String) { provider = _MWColorBox(key, ns) }
    public static func == (a: Color, b: Color) -> Bool { a.provider.key == b.provider.key }
    public func hash(into h: inout Hasher) { h.combine(provider.key) }
    public var description: String { provider.key }
    var nsColor: NSColor { provider.make() }

    public enum RGBColorSpace: Hashable, Sendable { case sRGB, sRGBLinear, displayP3 }
    public init(_ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.init(ns: { NSColor(srgbRed: red, green: green, blue: blue, alpha: opacity) }, key: "rgb\(red),\(green),\(blue),\(opacity)")
    }
    public init(_ colorSpace: Color.RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) {
        self.init(ns: { NSColor(white: white, alpha: opacity) }, key: "w\(white),\(opacity)")
    }
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) { self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity) }
    public init(white: Double, opacity: Double = 1) { self.init(.sRGB, white: white, opacity: opacity) }
    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) {
        self.init(ns: { NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: opacity) }, key: "hsb\(hue),\(saturation),\(brightness),\(opacity)")
    }
    public init(_ color: NSColor) { self.init(ns: { color }, key: "ns\(ObjectIdentifier(color))") }
    public init(nsColor color: NSColor) { self.init(color) }
    public init(_ name: String, bundle: Bundle? = nil) {
        self.init(ns: { NSColor(named: name, bundle: bundle) ?? .labelColor }, key: "named:\(name)")
    }
    public init(cgColor: CGColor) { self.init(ns: { NSColor(cgColor: cgColor) ?? .black }, key: "cg") }
    public func opacity(_ opacity: Double) -> Color {
        let base = provider
        return Color(ns: { base.make().withAlphaComponent(base.make().alphaComponent * opacity) }, key: "\(base.key)*\(opacity)")
    }
    public static let black = Color(ns: { .black }, key: "black")
    public static let white = Color(ns: { .white }, key: "white")
    public static let gray = Color(ns: { .systemGray }, key: "gray")
    public static let red = Color(ns: { .systemRed }, key: "red")
    public static let green = Color(ns: { .systemGreen }, key: "green")
    public static let blue = Color(ns: { .systemBlue }, key: "blue")
    public static let orange = Color(ns: { .systemOrange }, key: "orange")
    public static let yellow = Color(ns: { .systemYellow }, key: "yellow")
    public static let pink = Color(ns: { .systemPink }, key: "pink")
    public static let purple = Color(ns: { .systemPurple }, key: "purple")
    public static let mint = Color(ns: { .systemGreen }, key: "mint")
    public static let teal = Color(ns: { .systemTeal }, key: "teal")
    public static let cyan = Color(ns: { .systemTeal }, key: "cyan")
    public static let indigo = Color(ns: { .systemIndigo }, key: "indigo")
    public static let brown = Color(ns: { .systemBrown }, key: "brown")
    public static let clear = Color(ns: { .clear }, key: "clear")
    public static let primary = Color(ns: { .labelColor }, key: "primary")
    public static let secondary = Color(ns: { .secondaryLabelColor }, key: "secondary")
    public static let accentColor = Color(ns: { .controlAccentColor }, key: "accent")
}
@usableFromInline internal final class _MWColorBox {
    let key: String
    let make: () -> NSColor
    init(_ k: String, _ m: @escaping () -> NSColor) { key = k; make = m }
}
extension NSColor {
    public convenience init(_ color: Color) {
        let c = color.nsColor.usingColorSpace(.sRGB) ?? color.nsColor
        self.init(srgbRed: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
    }
}

// MARK: - shape styles

public protocol ShapeStyle {
    static func _makeView<S>(view: _GraphValue<_ShapeView<S, Self>>, inputs: _ViewInputs) -> _ViewOutputs where S: Shape
}
extension ShapeStyle {
    public static func _makeView<S>(view: _GraphValue<_ShapeView<S, Self>>, inputs: _ViewInputs) -> _ViewOutputs where S: Shape { _ViewOutputs() }
}
/// what a style paints with, in an environment
protocol _MWPaint {
    func _mwColor(_ env: EnvironmentValues) -> NSColor
}
extension Color: ShapeStyle, _MWPaint {
    func _mwColor(_ env: EnvironmentValues) -> NSColor { nsColor }
}
@frozen public struct ForegroundStyle: ShapeStyle, _MWPaint {
    @inlinable public init() {}
    func _mwColor(_ env: EnvironmentValues) -> NSColor { env.foregroundColor?.nsColor ?? .labelColor }
}
@frozen public struct BackgroundStyle: ShapeStyle, _MWPaint {
    @inlinable public init() {}
    func _mwColor(_ env: EnvironmentValues) -> NSColor { .windowBackgroundColor }
}
@frozen public struct SeparatorShapeStyle: ShapeStyle, _MWPaint {
    public init() {}
    func _mwColor(_ env: EnvironmentValues) -> NSColor { .separatorColor }
}
@frozen public struct HierarchicalShapeStyle: ShapeStyle, _MWPaint {
    @usableFromInline internal var id: UInt32
    init(id: UInt32) { self.id = id }
    var level: Int { Int(id) }
    public static let primary = HierarchicalShapeStyle(id: 0)
    public static let secondary = HierarchicalShapeStyle(id: 1)
    public static let tertiary = HierarchicalShapeStyle(id: 2)
    public static let quaternary = HierarchicalShapeStyle(id: 3)
    func _mwColor(_ env: EnvironmentValues) -> NSColor {
        let base = env.foregroundColor?.nsColor ?? .labelColor
        return level == 0 ? base : base.withAlphaComponent([1, 0.55, 0.3, 0.18][min(level, 3)])
    }
}
public struct Material: ShapeStyle, _MWPaint {
    let alpha: CGFloat
    public static let regular = Material(alpha: 0.85)
    public static let thick = Material(alpha: 0.92)
    public static let thin = Material(alpha: 0.75)
    public static let ultraThin = Material(alpha: 0.6)
    public static let ultraThick = Material(alpha: 0.97)
    public static let bar = Material(alpha: 0.9)
    func _mwColor(_ env: EnvironmentValues) -> NSColor { NSColor.windowBackgroundColor.withAlphaComponent(alpha) }
}
@frozen public struct AnyShapeStyle: ShapeStyle, _MWPaint {
    @usableFromInline @frozen internal struct Storage {
        @usableFromInline internal var box: AnyShapeStyleBox
    }
    @usableFromInline internal var storage: Storage
    public init<S>(_ style: S) where S: ShapeStyle { storage = Storage(box: AnyShapeStyleBox { (style as? _MWPaint)?._mwColor($0) ?? .labelColor }) }
    func _mwColor(_ env: EnvironmentValues) -> NSColor { storage.box.paint(env) }
}
@usableFromInline internal class AnyShapeStyleBox {
    let paint: (EnvironmentValues) -> NSColor
    init(_ p: @escaping (EnvironmentValues) -> NSColor) { paint = p }
}
extension ShapeStyle where Self == ForegroundStyle {
    public static var foreground: ForegroundStyle { ForegroundStyle() }
}
extension ShapeStyle where Self == Color {
    public static var accentColor: Color { .accentColor }
}
extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var primary: HierarchicalShapeStyle { .primary }
    public static var secondary: HierarchicalShapeStyle { .secondary }
    public static var tertiary: HierarchicalShapeStyle { .tertiary }
}
func _mwColor<S: ShapeStyle>(_ s: S, _ env: EnvironmentValues) -> NSColor { (s as? _MWPaint)?._mwColor(env) ?? .labelColor }

// MARK: - Text

@frozen public struct LocalizedStringKey: Equatable, ExpressibleByStringInterpolation {
    @usableFromInline internal var key: String
    @usableFromInline internal var hasFormatting: Bool = false
    @usableFromInline internal var arguments: [_MWFormatArgument] = []
    public init(_ value: String) { key = value }
    public init(stringLiteral value: String) { key = value }
    public init(stringInterpolation: LocalizedStringKey.StringInterpolation) {
        key = stringInterpolation.format; hasFormatting = true; arguments = stringInterpolation.arguments
    }
    public static func == (a: LocalizedStringKey, b: LocalizedStringKey) -> Bool { a.key == b.key }
    public struct StringInterpolation: StringInterpolationProtocol {
        var format = "", arguments: [_MWFormatArgument] = []
        public init(literalCapacity: Int, interpolationCount: Int) {}
        public mutating func appendLiteral(_ literal: String) { format += literal.replacingOccurrences(of: "%", with: "%%") }
        public mutating func appendInterpolation(_ string: String) { format += "%@"; arguments.append(_MWFormatArgument(string)) }
        public mutating func appendInterpolation<Subject>(_ subject: Subject, formatter: Formatter? = nil) where Subject: ReferenceConvertible {
            format += "%@"; arguments.append(_MWFormatArgument(formatter?.string(for: subject._bridgeToObjectiveC()) ?? "\(subject)"))
        }
        public mutating func appendInterpolation<Subject>(_ subject: Subject, formatter: Formatter? = nil) where Subject: NSObject {
            format += "%@"; arguments.append(_MWFormatArgument(formatter?.string(for: subject) ?? subject.description))
        }
        public mutating func appendInterpolation<T>(_ value: T) where T: _FormatSpecifiable {
            format += value._specifier; arguments.append(_MWFormatArgument("\(value._arg)"))
        }
        public mutating func appendInterpolation<T>(_ value: T, specifier: String) where T: _FormatSpecifiable {
            format += "%@"; arguments.append(_MWFormatArgument(String(format: specifier, value._arg as! CVarArg)))
        }
        public mutating func appendInterpolation(_ text: Text) { format += "%@"; arguments.append(_MWFormatArgument(text._mwPlain)) }
        public mutating func appendInterpolation(_ image: Image) {}
    }
    /// the text after looking up the key and filling its arguments
    func resolved(_ table: String?, _ bundle: Bundle?) -> String {
        let s = (bundle ?? .main).localizedString(forKey: key, value: key, table: table)
        guard hasFormatting else { return s }
        var out = "", args = arguments.makeIterator(), i = s.startIndex
        while i < s.endIndex {
            if s[i] == "%" , s.index(after: i) < s.endIndex {
                let n = s.index(after: i)
                if s[n] == "%" { out += "%"; i = s.index(after: n); continue }
                var j = n
                while j < s.endIndex, !s[j].isLetter, s[j] != "@" { j = s.index(after: j) }
                while j < s.endIndex, "hlqLztj".contains(s[j]) { j = s.index(after: j) }   // (length modifiers: %lld)
                if j < s.endIndex { out += args.next()?.text ?? ""; i = s.index(after: j); continue }
            }
            out.append(s[i]); i = s.index(after: i)
        }
        return out
    }
}
@usableFromInline internal struct _MWFormatArgument: Equatable {
    let text: String
    init(_ t: String) { text = t }
}
public protocol _FormatSpecifiable: Equatable {
    associatedtype _Arg: CVarArg
    var _arg: Self._Arg { get }
    var _specifier: String { get }
}
extension Int: _FormatSpecifiable { public var _arg: Int { self }; public var _specifier: String { "%lld" } }
extension Int32: _FormatSpecifiable { public var _arg: Int32 { self }; public var _specifier: String { "%d" } }
extension Int64: _FormatSpecifiable { public var _arg: Int64 { self }; public var _specifier: String { "%lld" } }
extension UInt: _FormatSpecifiable { public var _arg: UInt { self }; public var _specifier: String { "%llu" } }
extension Double: _FormatSpecifiable { public var _arg: Double { self }; public var _specifier: String { "%lf" } }
extension Float: _FormatSpecifiable { public var _arg: Float { self }; public var _specifier: String { "%f" } }

@frozen public struct Text: Equatable {
    @usableFromInline @frozen internal enum Storage: Equatable {
        case verbatim(String)
        case anyTextStorage(_MWTextStorage)
        @usableFromInline static func == (a: Storage, b: Storage) -> Bool {
            switch (a, b) {
            case (.verbatim(let x), .verbatim(let y)): return x == y
            case (.anyTextStorage(let x), .anyTextStorage(let y)): return x === y
            default: return false
            }
        }
    }
    @usableFromInline @frozen internal enum Modifier: Equatable {
        case color(Color?)
        case font(Font?)
        case italic
        case weight(Font.Weight?)
        case kerning(CGFloat)
        case tracking(CGFloat)
        case baseline(CGFloat)
        case rounded
        case anyTextModifier(_MWTextModifier)
        @usableFromInline static func == (a: Modifier, b: Modifier) -> Bool { false }
    }
    @usableFromInline internal var storage: Text.Storage
    @usableFromInline internal var modifiers: [Text.Modifier] = [Text.Modifier]()

    @inlinable public init(verbatim content: String) { storage = .verbatim(content) }
    public init<S>(_ content: S) where S: StringProtocol { storage = .verbatim(String(content)) }
    public init(_ key: LocalizedStringKey, tableName: String? = nil, bundle: Bundle? = nil, comment: StaticString? = nil) {
        storage = .anyTextStorage(_MWLocalizedStorage(key, tableName, bundle))
    }
    public init(_ image: Image) { storage = .anyTextStorage(_MWImageTextStorage(image)) }
    public init(_ attributedContent: AttributedString) { storage = .anyTextStorage(_MWAttributedStorage(NSAttributedString(attributedContent))) }
    public init<Subject>(_ subject: Subject, formatter: Formatter) where Subject: ReferenceConvertible {
        storage = .verbatim(formatter.string(for: subject._bridgeToObjectiveC()) ?? "")
    }
    public init(_ date: Date, style: Text.DateStyle) {
        let f = DateFormatter()
        switch style.kind { case 0: f.timeStyle = .short; f.dateStyle = .none; default: f.dateStyle = .medium; f.timeStyle = .none }
        storage = .verbatim(f.string(from: date))
    }
    public static func + (lhs: Text, rhs: Text) -> Text { Text(storage: .anyTextStorage(_MWConcatStorage(lhs, rhs))) }
    init(storage: Storage) { self.storage = storage }

    public struct DateStyle: Sendable {
        let kind: Int
        public static let time = DateStyle(kind: 0)
        public static let date = DateStyle(kind: 1)
        public static let relative = DateStyle(kind: 2)
        public static let offset = DateStyle(kind: 3)
        public static let timer = DateStyle(kind: 4)
    }
    public enum TruncationMode: Sendable { case head, tail, middle }
    public enum Case: Sendable { case uppercase, lowercase }

    func adding(_ m: Modifier) -> Text { var t = self; t.modifiers.append(m); return t }
    public func foregroundColor(_ color: Color?) -> Text { adding(.color(color)) }
    public func foregroundStyle<S>(_ style: S) -> Text where S: ShapeStyle { adding(.color((style as? Color))) }
    public func font(_ font: Font?) -> Text { adding(.font(font)) }
    public func fontWeight(_ weight: Font.Weight?) -> Text { adding(.weight(weight)) }
    public func bold() -> Text { adding(.weight(.bold)) }
    public func bold(_ isActive: Bool) -> Text { isActive ? bold() : self }
    public func italic() -> Text { adding(.italic) }
    public func italic(_ isActive: Bool) -> Text { isActive ? italic() : self }
    public func kerning(_ kerning: CGFloat) -> Text { adding(.kerning(kerning)) }
    public func tracking(_ tracking: CGFloat) -> Text { adding(.tracking(tracking)) }
    public func baselineOffset(_ baselineOffset: CGFloat) -> Text { adding(.baseline(baselineOffset)) }
    public func strikethrough(_ active: Bool = true, color: Color? = nil) -> Text { self }
    public func underline(_ active: Bool = true, color: Color? = nil) -> Text { self }
    public func monospacedDigit() -> Text { self }
    public func monospaced(_ isActive: Bool = true) -> Text { self }

    /// the plain characters
    var _mwPlain: String {
        switch storage {
        case .verbatim(let s): return s
        case .anyTextStorage(let s): return s.plain
        }
    }
    /// the attributed string in an environment
    func _mwAttributed(_ env: EnvironmentValues) -> NSAttributedString {
        var font = env.font ?? .body, color = env.foregroundColor
        for m in modifiers {
            switch m {
            case .color(let c): color = c ?? color
            case .font(let f): font = f ?? font
            case .weight(let w): if let w = w { font = font.weight(w) }
            case .italic: font = font.italic()
            default: break
            }
        }
        var e = env; e.font = font; e.foregroundColor = color
        switch storage {
        case .verbatim(let s): return _mwAttr(s, e)
        case .anyTextStorage(let s): return s.attributed(e)
        }
    }
}
func _mwAttr(_ s: String, _ env: EnvironmentValues) -> NSAttributedString {
    let p = NSMutableParagraphStyle()
    p.alignment = env.multilineTextAlignment == .center ? .center : env.multilineTextAlignment == .trailing ? .right : .left
    let color = env.isEnabled ? (env.foregroundColor?.nsColor ?? .labelColor) : .disabledControlTextColor
    return NSAttributedString(string: s, attributes: [.font: (env.font ?? .body).nsFont, .foregroundColor: color, .paragraphStyle: p])
}
@usableFromInline internal class _MWTextStorage {
    var plain: String { "" }
    func attributed(_ env: EnvironmentValues) -> NSAttributedString { _mwAttr(plain, env) }
}
@usableFromInline internal class _MWTextModifier {}
final class _MWLocalizedStorage: _MWTextStorage {
    let key: LocalizedStringKey, table: String?, bundle: Bundle?
    init(_ k: LocalizedStringKey, _ t: String?, _ b: Bundle?) { key = k; table = t; bundle = b }
    override var plain: String { key.resolved(table, bundle) }
}
final class _MWConcatStorage: _MWTextStorage {
    let a: Text, b: Text
    init(_ a: Text, _ b: Text) { self.a = a; self.b = b }
    override var plain: String { a._mwPlain + b._mwPlain }
    override func attributed(_ env: EnvironmentValues) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: a._mwAttributed(env))
        m.append(b._mwAttributed(env))
        return m
    }
}
final class _MWAttributedStorage: _MWTextStorage {
    let ns: NSAttributedString
    init(_ s: NSAttributedString) { ns = s }
    override var plain: String { ns.string }
    /// the string's own attributes win; the environment fills in font and color where it has none
    override func attributed(_ env: EnvironmentValues) -> NSAttributedString {
        let base = _mwAttr(ns.string, env)
        let m = NSMutableAttributedString(attributedString: base)
        if ns.length > 0 { ns.enumerateAttributes(in: NSRange(location: 0, length: ns.length), options: 0) { a, r, _ in m.addAttributes(a, range: r) } }
        return m
    }
}
final class _MWImageTextStorage: _MWTextStorage {
    let image: Image
    init(_ i: Image) { image = i }
    override var plain: String { "" }   // ponytail: images inside Text are not drawn
}

extension Text: View, _MWResolvable {
    public typealias Body = Never
    public var body: Never { _primitive("Text") }
    func _mwNodes(_ c: _MWContext) -> [_MWNode] { [_MWTextNode(_mwAttributed(c.env), lineLimit: c.env.lineLimit)] }
}

final class _MWTextNode: _MWNode {
    let string: NSAttributedString
    let font: NSFont
    let lineLimit: Int?
    init(_ s: NSAttributedString, lineLimit: Int?) {
        string = s
        font = (s.length > 0 ? s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil) ?? NSFont.systemFont(ofSize: 13)
        self.lineLimit = lineLimit
        super.init()
    }
    private lazy var single: CGSize = {
        if string.length == 0 { return CGSize(width: 0, height: ceil(font.ascender - font.descender)) }
        let s = string.size()
        return CGSize(width: ceil(s.width) + 1, height: ceil(max(s.height, font.ascender - font.descender)))
    }()
    override func size(_ p: _MWProposal) -> CGSize {
        guard let w = p.width, w.isFinite, w < single.width else { return single }
        if lineLimit == 1 || string.string.isEmpty { return CGSize(width: max(0, w), height: single.height) }
        let r = string.boundingRect(with: CGSize(width: max(w, 1), height: 100000), options: [.usesLineFragmentOrigin])
        var h = ceil(r.height)
        if let l = lineLimit { h = min(h, single.height * CGFloat(l)) }
        if let ph = p.height, ph.isFinite { h = min(h, max(ph, single.height)) }
        return CGSize(width: min(w, ceil(r.width) + 1), height: max(h, single.height))
    }
    override func draw(_ g: CGContext) {
        guard !isHidden else { return }
        string.draw(with: frame, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
    override var text: String? { string.string }
    override var ownBaseline: CGFloat? { font.ascender + 1 }
}

// MARK: - Image

@frozen public struct Image: Equatable {
    @usableFromInline internal var provider: _MWImageBox
    init(_ p: _MWImageBox) { provider = p }
    public static func == (a: Image, b: Image) -> Bool { a.provider === b.provider }
    public init(nsImage: NSImage) { provider = _MWImageBox(nsImage, template: nsImage.isTemplate) }
    public init(systemName: String) {
        provider = _MWImageBox(NSImage(systemSymbolName: systemName, accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 16, height: 16)), template: true)
        provider.symbol = true
    }
    public init(_ name: String, bundle: Bundle? = nil) {
        let img = (bundle == nil ? NSImage(named: name) : bundle!.image(forResource: name)) ?? NSImage(size: NSSize(width: 16, height: 16))
        provider = _MWImageBox(img, template: img.isTemplate)
    }
    public init(_ name: String, bundle: Bundle? = nil, label: Text) { self.init(name, bundle: bundle) }
    public init(decorative name: String, bundle: Bundle? = nil) { self.init(name, bundle: bundle) }
    public init(_ cgImage: CGImage, scale: CGFloat, orientation: Image.Orientation = .up, label: Text) {
        provider = _MWImageBox(NSImage(cgImage: cgImage, size: .zero), template: false)
    }
    public enum ResizingMode: Hashable, Sendable { case tile, stretch }
    public enum TemplateRenderingMode: Hashable, Sendable { case template, original }
    public enum Interpolation: Hashable, Sendable { case none, low, medium, high }
    @frozen public enum Orientation: UInt8, CaseIterable, Hashable { case up = 0, upMirrored = 2, down = 6, downMirrored = 4, left = 1, leftMirrored = 3, right = 7, rightMirrored = 5 }
    public enum Scale: Hashable, Sendable { case small, medium, large }
    func copy(_ f: (_MWImageBox) -> Void) -> Image {
        let b = _MWImageBox(provider.image, template: provider.template)
        b.resizable = provider.resizable; b.symbol = provider.symbol
        f(b)
        return Image(b)
    }
    public func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: Image.ResizingMode = .stretch) -> Image { copy { $0.resizable = true } }
    public func renderingMode(_ renderingMode: Image.TemplateRenderingMode?) -> Image { copy { $0.template = renderingMode == .template ? true : renderingMode == .original ? false : $0.template } }
    public func interpolation(_ interpolation: Image.Interpolation) -> Image { self }
    public func antialiased(_ isAntialiased: Bool) -> Image { self }
}
@usableFromInline internal final class _MWImageBox {
    let image: NSImage
    var template: Bool
    var resizable = false
    var symbol = false
    init(_ i: NSImage, template: Bool) { image = i; self.template = template }
}
extension Image: View, _MWResolvable {
    public typealias Body = Never
    public var body: Never { _primitive("Image") }
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let b = provider, env = c.env
        let fontSize = (env.font ?? .body).nsFont.pointSize
        let natural = b.symbol ? CGSize(width: ceil(fontSize * 1.25), height: ceil(fontSize * 1.25)) : b.image.size
        let tint = env.isEnabled ? (env.foregroundColor?.nsColor ?? .labelColor) : .disabledControlTextColor
        let img = (b.template || b.symbol) ? _mwTinted(b.image, tint, natural) : b.image
        let n = _MWDrawNode(ideal: b.resizable ? nil : natural) { _, r in
            img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        n.traits["aspect"] = natural.height > 0 ? natural.width / natural.height : 1
        return [n]
    }
}

/// a template image painted in one color: its alpha filled with the tint, drawn offscreen at 2x
func _mwTinted(_ img: NSImage, _ tint: NSColor, _ size: CGSize) -> NSImage {
    let w = max(1, Int(ceil(size.width * 2))), h = max(1, Int(ceil(size.height * 2)))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: "NSDeviceRGBColorSpace", bytesPerRow: 0, bitsPerPixel: 32)
    rep.size = size
    let saved = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = CGRect(origin: .zero, size: size)
    img.draw(in: r)
    if let g = NSGraphicsContext.current?.cgContext {
        CGContextSetBlendMode(g, .sourceAtop)
        CGContextSetFillColorWithColor(g, tint.cgColor)
        CGContextFillRect(g, r)
    }
    NSGraphicsContext.current = saved
    let out = NSImage(size: size)
    out.addRepresentation(rep)
    return out
}

// Color is a view too: a rectangle filled with it that takes all the space offered
extension Color: View, _MWResolvable {
    public typealias Body = Never
    public var body: Never { _primitive("Color") }
    func _mwNodes(_ c: _MWContext) -> [_MWNode] { _ShapeView(shape: Rectangle(), style: self)._mwNodes(c) }
}
