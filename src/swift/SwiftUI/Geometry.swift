// Geometry types: alignments, edges, insets, axes, unit points, angles, view dimensions, coordinate spaces, anchors.
import Foundation
import CoreGraphics

// MARK: - alignment

public protocol AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat
    static func _combineExplicit(childValue: CGFloat, _ n: Int, into parentValue: inout CGFloat?)
}
extension AlignmentID {
    public static func _combineExplicit(childValue: CGFloat, _ n: Int, into parentValue: inout CGFloat?) {
        if parentValue == nil { parentValue = childValue }
    }
}

/// alignments are one word, as Apple's (an index into the registered AlignmentID types, and the axis)
nonisolated(unsafe) private var _mwAlignmentTypes: [AlignmentID.Type] = []
private let _mwAlignmentLock = NSLock()
@usableFromInline @frozen internal struct AlignmentKey: Hashable, Comparable {
    private let bits: UInt
    init(id: AlignmentID.Type, vertical: Bool) {
        _mwAlignmentLock.lock(); defer { _mwAlignmentLock.unlock() }
        let i = _mwAlignmentTypes.firstIndex { $0 == id } ?? { _mwAlignmentTypes.append(id); return _mwAlignmentTypes.count - 1 }()
        bits = UInt(i) << 1 | (vertical ? 1 : 0)
    }
    var id: AlignmentID.Type { _mwAlignmentLock.lock(); defer { _mwAlignmentLock.unlock() }; return _mwAlignmentTypes[Int(bits >> 1)] }
    @usableFromInline static func < (a: AlignmentKey, b: AlignmentKey) -> Bool { a.bits < b.bits }
}
enum _MWLeading: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { 0 } }
enum _MWHCenter: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d.width / 2 } }
enum _MWTrailing: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d.width } }
enum _MWTop: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { 0 } }
enum _MWVCenter: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height / 2 } }
enum _MWBottom: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height } }
enum _MWFirstBaseline: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d.baseline ?? d.height } }
enum _MWLastBaseline: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height } }

@frozen public struct HorizontalAlignment: Equatable {
    @usableFromInline internal let key: AlignmentKey
    public init(_ id: AlignmentID.Type) { key = AlignmentKey(id: id, vertical: false) }
    public static let leading = HorizontalAlignment(_MWLeading.self)
    public static let center = HorizontalAlignment(_MWHCenter.self)
    public static let trailing = HorizontalAlignment(_MWTrailing.self)
    public static let listRowSeparatorLeading = HorizontalAlignment(_MWLeading.self)
    public static let listRowSeparatorTrailing = HorizontalAlignment(_MWTrailing.self)
    /// where the guide sits in a width (custom guides ask their AlignmentID)
    func offset(_ d: ViewDimensions) -> CGFloat { d[self] }
}
@frozen public struct VerticalAlignment: Equatable {
    @usableFromInline internal let key: AlignmentKey
    public init(_ id: AlignmentID.Type) { key = AlignmentKey(id: id, vertical: true) }
    public static let top = VerticalAlignment(_MWTop.self)
    public static let center = VerticalAlignment(_MWVCenter.self)
    public static let bottom = VerticalAlignment(_MWBottom.self)
    public static let firstTextBaseline = VerticalAlignment(_MWFirstBaseline.self)
    public static let lastTextBaseline = VerticalAlignment(_MWLastBaseline.self)
}

@frozen public struct Alignment: Equatable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment
    @inlinable public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) { self.horizontal = horizontal; self.vertical = vertical }
    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}

@frozen public enum TextAlignment: Hashable, CaseIterable, Sendable {
    case leading
    case center
    case trailing
}

// MARK: - view dimensions

public struct ViewDimensions: Equatable {
    var size: CGSize
    var explicitH: [AlignmentKey: CGFloat] = [:]
    var explicitV: [AlignmentKey: CGFloat] = [:]
    var baseline: CGFloat?
    init(size: CGSize, baseline: CGFloat? = nil) { self.size = size; self.baseline = baseline }
    public var width: CGFloat { size.width }
    public var height: CGFloat { size.height }
    public subscript(guide: HorizontalAlignment) -> CGFloat { explicitH[guide.key] ?? guide.key.id.defaultValue(in: self) }
    public subscript(guide: VerticalAlignment) -> CGFloat { explicitV[guide.key] ?? guide.key.id.defaultValue(in: self) }
    public subscript(explicit guide: HorizontalAlignment) -> CGFloat? { explicitH[guide.key] }
    public subscript(explicit guide: VerticalAlignment) -> CGFloat? { explicitV[guide.key] }
    public static func == (a: ViewDimensions, b: ViewDimensions) -> Bool { a.size == b.size && a.explicitH == b.explicitH && a.explicitV == b.explicitV }
}

// MARK: - edges, insets, axes

@frozen public enum Edge: Int8, CaseIterable {
    case top, leading, bottom, trailing
    @frozen public struct Set: OptionSet {
        public typealias Element = Edge.Set
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let top = Set(.top)
        public static let leading = Set(.leading)
        public static let bottom = Set(.bottom)
        public static let trailing = Set(.trailing)
        public static let all: Set = [.top, .leading, .bottom, .trailing]
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
        public init(_ e: Edge) { rawValue = 1 << e.rawValue }
    }
}
@frozen public enum HorizontalEdge: Int8, CaseIterable {
    case leading, trailing
    @frozen public struct Set: OptionSet {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let leading = Set(.leading)
        public static let trailing = Set(.trailing)
        public static let all: Set = [.leading, .trailing]
        public init(_ e: HorizontalEdge) { rawValue = 1 << e.rawValue }
    }
}
@frozen public enum VerticalEdge: Int8, CaseIterable {
    case top, bottom
    @frozen public struct Set: OptionSet {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let top = Set(.top)
        public static let bottom = Set(.bottom)
        public static let all: Set = [.top, .bottom]
        public init(_ e: VerticalEdge) { rawValue = 1 << e.rawValue }
    }
}

@frozen public struct EdgeInsets: Equatable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat
    @inlinable public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
    @inlinable public init() { self.init(top: 0, leading: 0, bottom: 0, trailing: 0) }
    @usableFromInline init(_all: CGFloat) { self.init(top: _all, leading: _all, bottom: _all, trailing: _all) }
    init(_ edges: Edge.Set, _ v: CGFloat) {
        self.init(top: edges.contains(.top) ? v : 0, leading: edges.contains(.leading) ? v : 0,
                  bottom: edges.contains(.bottom) ? v : 0, trailing: edges.contains(.trailing) ? v : 0)
    }
}

@frozen public enum Axis: Int8, CaseIterable {
    case horizontal, vertical
    @frozen public struct Set: OptionSet {
        public typealias Element = Axis.Set
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let horizontal = Set(rawValue: 1)
        public static let vertical = Set(rawValue: 2)
    }
}

@frozen public struct UnitPoint: Hashable {
    public var x: CGFloat
    public var y: CGFloat
    @inlinable public init() { self.init(x: 0, y: 0) }
    @inlinable public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
    public static let zero = UnitPoint(x: 0, y: 0)
    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public static let leading = UnitPoint(x: 0, y: 0.5)
    public static let trailing = UnitPoint(x: 1, y: 0.5)
    public static let top = UnitPoint(x: 0.5, y: 0)
    public static let bottom = UnitPoint(x: 0.5, y: 1)
    public static let topLeading = UnitPoint(x: 0, y: 0)
    public static let topTrailing = UnitPoint(x: 1, y: 0)
    public static let bottomLeading = UnitPoint(x: 0, y: 1)
    public static let bottomTrailing = UnitPoint(x: 1, y: 1)
}

@frozen public struct Angle: Hashable, Comparable {
    public var radians: Double
    @inlinable public var degrees: Double { get { radians * (180 / .pi) } set { radians = newValue * (.pi / 180) } }
    @inlinable public init() { radians = 0 }
    @inlinable public init(radians: Double) { self.radians = radians }
    @inlinable public init(degrees: Double) { radians = degrees * (.pi / 180) }
    @inlinable public static func radians(_ radians: Double) -> Angle { Angle(radians: radians) }
    @inlinable public static func degrees(_ degrees: Double) -> Angle { Angle(degrees: degrees) }
    public static let zero = Angle()
    @inlinable public static func < (a: Angle, b: Angle) -> Bool { a.radians < b.radians }
}

public enum CoordinateSpace {
    case global
    case local
    case named(AnyHashable)
}
extension CoordinateSpace: Equatable, Hashable {}

// MARK: - proposed sizes and anchors

public struct _ProposedSize: Hashable {
    var width: CGFloat?
    var height: CGFloat?
    init(width: CGFloat?, height: CGFloat?) { self.width = width; self.height = height }
}
public struct _LayoutTraits: Equatable {}

@frozen public struct Anchor<Value> {
    @usableFromInline let box: _MWAnchorBox<Value>
    @frozen public struct Source {
        @usableFromInline let box: _MWAnchorBox<Value>
    }
}
@usableFromInline final class _MWAnchorBox<Value> {
    let resolve: (CGRect) -> Value
    init(_ r: @escaping (CGRect) -> Value) { resolve = r }
}
extension Anchor.Source where Value == CGRect {
    public static var bounds: Anchor<CGRect>.Source { Anchor<CGRect>.Source(box: _MWAnchorBox { CGRect(origin: .zero, size: $0.size) }) }
    public static func rect(_ r: CGRect) -> Anchor<CGRect>.Source { Anchor<CGRect>.Source(box: _MWAnchorBox { _ in r }) }
}
extension Anchor.Source where Value == CGPoint {
    public static func point(_ p: CGPoint) -> Anchor<CGPoint>.Source { Anchor<CGPoint>.Source(box: _MWAnchorBox { _ in p }) }
    public static func unitPoint(_ p: UnitPoint) -> Anchor<CGPoint>.Source {
        Anchor<CGPoint>.Source(box: _MWAnchorBox { CGPoint(x: $0.width * p.x, y: $0.height * p.y) })
    }
}
