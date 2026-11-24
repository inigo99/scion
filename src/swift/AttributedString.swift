// AttributedString (Foundation, macOS 12) for scion's Foundation overlay: a value wrapper around an immutable
// NSAttributedString. ponytail: runs, attribute scopes and Markdown are not implemented; add them when an app needs them.
public struct AttributedString: Equatable, Hashable, CustomStringConvertible {
    var ns: NSAttributedString
    public init() { ns = NSAttributedString(string: "") }
    public init(_ string: String) { ns = NSAttributedString(string: string) }
    public init(_ nsStr: NSAttributedString) { ns = nsStr.copy() as! NSAttributedString }
    public var description: String { ns.string }
    public static func == (a: AttributedString, b: AttributedString) -> Bool { a.ns.isEqual(b.ns) }
    public func hash(into h: inout Hasher) { h.combine(ns.string) }
    public static func + (a: AttributedString, b: AttributedString) -> AttributedString {
        let m = NSMutableAttributedString(attributedString: a.ns)
        m.append(b.ns)
        return AttributedString(m)
    }
    public static func += (a: inout AttributedString, b: AttributedString) { a = a + b }
    public mutating func append(_ s: AttributedString) { self += s }
}
extension NSAttributedString {
    public convenience init(_ attrStr: AttributedString) { self.init(attributedString: attrStr.ns) }
}
