// Shapes, paths and animatable data.
import Foundation
import AppKit
import CoreGraphics

// MARK: - animatable data

public protocol VectorArithmetic: AdditiveArithmetic {
    mutating func scale(by rhs: Double)
    var magnitudeSquared: Double { get }
}
extension Double: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= rhs }
    public var magnitudeSquared: Double { self * self }
}
extension Float: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= Float(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}
extension CGFloat: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= CGFloat(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}
@frozen public struct EmptyAnimatableData: VectorArithmetic {
    @inlinable public init() {}
    @inlinable public static var zero: EmptyAnimatableData { EmptyAnimatableData() }
    @inlinable public static func + (a: EmptyAnimatableData, b: EmptyAnimatableData) -> EmptyAnimatableData { a }
    @inlinable public static func - (a: EmptyAnimatableData, b: EmptyAnimatableData) -> EmptyAnimatableData { a }
    @inlinable public mutating func scale(by rhs: Double) {}
    @inlinable public var magnitudeSquared: Double { 0 }
    public static func == (a: EmptyAnimatableData, b: EmptyAnimatableData) -> Bool { true }
}
@frozen public struct AnimatablePair<First, Second>: VectorArithmetic where First: VectorArithmetic, Second: VectorArithmetic {
    public var first: First
    public var second: Second
    @inlinable public init(_ first: First, _ second: Second) { self.first = first; self.second = second }
    public static var zero: AnimatablePair { AnimatablePair(.zero, .zero) }
    public static func + (a: AnimatablePair, b: AnimatablePair) -> AnimatablePair { AnimatablePair(a.first + b.first, a.second + b.second) }
    public static func - (a: AnimatablePair, b: AnimatablePair) -> AnimatablePair { AnimatablePair(a.first - b.first, a.second - b.second) }
    public mutating func scale(by rhs: Double) { first.scale(by: rhs); second.scale(by: rhs) }
    public var magnitudeSquared: Double { first.magnitudeSquared + second.magnitudeSquared }
}

public protocol Animatable {
    associatedtype AnimatableData: VectorArithmetic
    var animatableData: Self.AnimatableData { get set }
    static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs)
}
extension Animatable {
    public static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs) {}
}
extension Animatable where Self: VectorArithmetic {
    public var animatableData: Self { get { self } set { self = newValue } }
}
extension Animatable where Self.AnimatableData == EmptyAnimatableData {
    public var animatableData: EmptyAnimatableData { get { EmptyAnimatableData() } set {} }
    public static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs) {}
}

// MARK: - Path

/// Apple's layout (apps copy and destroy paths inline): one enum, 32 bytes of payload and a tag byte
@frozen public struct Path: Equatable, LosslessStringConvertible {
    @usableFromInline final class PathBox: Equatable {
        let p: CGMutablePath
        init(_ p: CGMutablePath) { self.p = p }
        @usableFromInline static func == (a: PathBox, b: PathBox) -> Bool { a === b }
    }
    @usableFromInline @frozen enum Storage: Equatable {
        case empty
        case rect(CGRect)
        case ellipse(CGRect)
        indirect case roundedRect(FixedRoundedRect)
        indirect case stroked(StrokedPath)
        indirect case trimmed(TrimmedPath)
        case path(PathBox)
    }
    @usableFromInline var storage: Storage
    public init() { storage = .empty }
    public init(_ path: CGPath) { storage = .path(PathBox(CGPathCreateMutableCopy(path)!)) }
    public init(_ path: CGMutablePath) { storage = .path(PathBox(CGPathCreateMutableCopy(path)!)) }
    public init(_ rect: CGRect) { storage = .rect(rect) }
    public init(roundedRect rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
        storage = .roundedRect(FixedRoundedRect(rect: rect, cornerSize: cornerSize, style: style))
    }
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.init(roundedRect: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style)
    }
    public init(ellipseIn rect: CGRect) { storage = .ellipse(rect) }
    public init(_ callback: (inout Path) -> ()) { self.init(); callback(&self) }
    public init?(_ string: String) { return nil }
    public var description: String { "Path" }
    public var cgPath: CGPath {
        switch storage {
        case .empty: return CGPathCreateMutable()
        case .rect(let r): let m: CGMutablePath = CGPathCreateMutable(); CGPathAddRect(m, nil, r); return m
        case .ellipse(let r): let m: CGMutablePath = CGPathCreateMutable(); CGPathAddEllipseInRect(m, nil, r); return m
        case .roundedRect(let f):
            let m: CGMutablePath = CGPathCreateMutable(), r = f.rect
            let w = min(f.cornerSize.width, r.width / 2), h = min(f.cornerSize.height, r.height / 2)
            CGPathAddRoundedRect(m, nil, r, max(0, w), max(0, h)); return m
        case .stroked(let s): return s.path.cgPath   // ponytail: the outline is not computed
        case .trimmed(let t): return t.path.cgPath
        case .path(let b): return b.p
        }
    }
    /// the path as a CGMutablePath this value owns alone (copy on write)
    private mutating func mutable() -> CGMutablePath {
        if case .path(var b) = storage {
            storage = .empty
            if !isKnownUniquelyReferenced(&b) { b = PathBox(CGPathCreateMutableCopy(b.p)!) }
            storage = .path(b); return b.p
        }
        let b = PathBox(CGPathCreateMutableCopy(cgPath)!)
        storage = .path(b); return b.p
    }
    public var isEmpty: Bool { if case .empty = storage { return true }; return CGPathIsEmpty(cgPath) }
    public var boundingRect: CGRect {
        switch storage { case .empty: return .zero; case .rect(let r), .ellipse(let r): return r; default: return CGPathGetPathBoundingBox(cgPath) }
    }
    public var currentPoint: CGPoint? { isEmpty ? nil : CGPathGetCurrentPoint(cgPath) }
    public func contains(_ p: CGPoint, eoFill: Bool = false) -> Bool { CGPathContainsPoint(cgPath, nil, p, eoFill) }
    public mutating func move(to p: CGPoint) { CGPathMoveToPoint(mutable(), nil, p.x, p.y) }
    public mutating func addLine(to p: CGPoint) { CGPathAddLineToPoint(mutable(), nil, p.x, p.y) }
    public mutating func addQuadCurve(to p: CGPoint, control cp: CGPoint) { CGPathAddQuadCurveToPoint(mutable(), nil, cp.x, cp.y, p.x, p.y) }
    public mutating func addCurve(to p: CGPoint, control1 a: CGPoint, control2 b: CGPoint) { CGPathAddCurveToPoint(mutable(), nil, a.x, a.y, b.x, b.y, p.x, p.y) }
    public mutating func closeSubpath() { CGPathCloseSubpath(mutable()) }
    public mutating func addRect(_ r: CGRect, transform: CGAffineTransform = .identity) { CGPathAddRect(mutable(), nil, r) }
    public mutating func addRects(_ rs: [CGRect], transform: CGAffineTransform = .identity) { for r in rs { addRect(r) } }
    public mutating func addRoundedRect(in r: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous, transform: CGAffineTransform = .identity) {
        let w = min(cornerSize.width, r.width / 2), h = min(cornerSize.height, r.height / 2)
        CGPathAddRoundedRect(mutable(), nil, r, max(0, w), max(0, h))
    }
    public mutating func addEllipse(in r: CGRect, transform: CGAffineTransform = .identity) { CGPathAddEllipseInRect(mutable(), nil, r) }
    public mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool, transform: CGAffineTransform = .identity) {
        CGPathAddArc(mutable(), nil, center.x, center.y, radius, startAngle.radians, endAngle.radians, clockwise)
    }
    public mutating func addLines(_ ps: [CGPoint]) { guard let f = ps.first else { return }; move(to: f); for p in ps.dropFirst() { addLine(to: p) } }
    public mutating func addPath(_ path: Path, transform: CGAffineTransform = .identity) { CGPathAddPath(mutable(), nil, path.cgPath) }
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path { applying(CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: dx, ty: dy)) }
    public func applying(_ t: CGAffineTransform) -> Path {
        let m: CGMutablePath = CGPathCreateMutable()
        var tt = t
        CGPathAddPath(m, &tt, cgPath)
        return Path(m)
    }
}
@usableFromInline struct FixedRoundedRect: Equatable {
    var rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle
    @usableFromInline static func == (a: FixedRoundedRect, b: FixedRoundedRect) -> Bool { a.rect == b.rect && a.cornerSize == b.cornerSize && a.style == b.style }
}
@usableFromInline struct StrokedPath: Equatable {
    var path: Path, style: StrokeStyle
    @usableFromInline static func == (a: StrokedPath, b: StrokedPath) -> Bool { a.path == b.path && a.style == b.style }
}
@usableFromInline struct TrimmedPath: Equatable {
    var path: Path, start: CGFloat, end: CGFloat
    @usableFromInline static func == (a: TrimmedPath, b: TrimmedPath) -> Bool { a.path == b.path && a.start == b.start && a.end == b.end }
}
extension Path: Shape {
    public func path(in rect: CGRect) -> Path { self }
}

public enum RoundedCornerStyle: Hashable, Sendable {
    case circular
    case continuous
}

@frozen public struct StrokeStyle: Equatable {
    public var lineWidth: CGFloat
    public var lineCap: CGLineCap
    public var lineJoin: CGLineJoin
    public var miterLimit: CGFloat
    public var dash: [CGFloat]
    public var dashPhase: CGFloat
    public init(lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter, miterLimit: CGFloat = 10, dash: [CGFloat] = [CGFloat](), dashPhase: CGFloat = 0) {
        self.lineWidth = lineWidth; self.lineCap = lineCap; self.lineJoin = lineJoin; self.miterLimit = miterLimit; self.dash = dash; self.dashPhase = dashPhase
    }
}

// MARK: - Shape

public enum ShapeRole: Hashable, Sendable {
    case fill
    case stroke
    case separator
}

public protocol Shape: Animatable, View {
    func path(in rect: CGRect) -> Path
    static var role: ShapeRole { get }
    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize
    var layoutDirectionBehavior: LayoutDirectionBehavior { get }
}
extension Shape {
    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { proposal.replacingUnspecifiedDimensions() }
    public var layoutDirectionBehavior: LayoutDirectionBehavior { .mirrors(in: .rightToLeft) }
    public static var role: ShapeRole { .fill }
    public var body: _ShapeView<Self, ForegroundStyle> { _ShapeView(shape: self, style: ForegroundStyle()) }
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs { _ViewOutputs() }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs { _ViewListOutputs() }
    public func fill<S>(_ content: S, style: FillStyle = FillStyle()) -> some View where S: ShapeStyle { _ShapeView(shape: self, style: content, fillStyle: style) }
    public func fill(style: FillStyle = FillStyle()) -> _ShapeView<Self, ForegroundStyle> { _ShapeView(shape: self, style: ForegroundStyle(), fillStyle: style) }
    public func stroke<S>(_ content: S, style: StrokeStyle) -> some View where S: ShapeStyle { _MWStrokeView(shape: self, style: content, stroke: style) }
    public func stroke<S>(_ content: S, lineWidth: CGFloat = 1) -> some View where S: ShapeStyle { stroke(content, style: StrokeStyle(lineWidth: lineWidth)) }
    public func stroke(style: StrokeStyle) -> some Shape { _StrokedShape(shape: self, style: style) }
    public func stroke(lineWidth: CGFloat = 1) -> some Shape { stroke(style: StrokeStyle(lineWidth: lineWidth)) }
    public func trim(from: CGFloat = 0, to: CGFloat = 1) -> some Shape { self }
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some Shape { _MWOffsetShape(shape: self, dx: x, dy: y) }
}
@frozen public struct FillStyle: Equatable {
    public var isEOFilled: Bool
    public var isAntialiased: Bool
    @inlinable public init(eoFill: Bool = false, antialiased: Bool = true) { isEOFilled = eoFill; isAntialiased = antialiased }
}

/// a shape filled with a style
@frozen public struct _ShapeView<Content, Style>: View where Content: Shape, Style: ShapeStyle {
    public var shape: Content
    public var style: Style
    public var fillStyle: FillStyle
    @inlinable public init(shape: Content, style: Style, fillStyle: FillStyle = FillStyle()) { self.shape = shape; self.style = style; self.fillStyle = fillStyle }
    public typealias Body = Never
    public var body: Never { _primitive("_ShapeView") }
}
extension _ShapeView: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let s = shape, color = _mwColor(style, c.env), eo = fillStyle.isEOFilled
        if let st = shape as? _MWStroked { return [_MWDrawNode(ideal: nil) { g, r in _mwStroke(g, st._mwPath(r), color, st._mwStyle) }] }
        return [_MWDrawNode(ideal: nil) { g, r in
            CGContextSaveGState(g)
            CGContextAddPath(g, s.path(in: r).cgPath)
            CGContextSetFillColorWithColor(g, color.cgColor)
            if eo { CGContextEOFillPath(g) } else { CGContextFillPath(g) }
            CGContextRestoreGState(g)
        }]
    }
}
public struct _MWStrokeView<S: Shape, Style: ShapeStyle>: View, _MWResolvable {
    let shape: S, style: Style, stroke: StrokeStyle
    var inset: CGFloat = 0
    init(shape: S, style: Style, stroke: StrokeStyle, inset: CGFloat = 0) { self.shape = shape; self.style = style; self.stroke = stroke; self.inset = inset }
    public typealias Body = Never
    public var body: Never { _primitive("stroke") }
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let s = shape, color = _mwColor(style, c.env), st = stroke, ins = inset
        return [_MWDrawNode(ideal: nil) { g, r in _mwStroke(g, s.path(in: r.insetBy(dx: ins, dy: ins)), color, st) }]
    }
}
func _mwStroke(_ g: CGContext, _ p: Path, _ color: NSColor, _ st: StrokeStyle) {
    CGContextSaveGState(g)
    CGContextAddPath(g, p.cgPath)
    CGContextSetStrokeColorWithColor(g, color.cgColor)
    CGContextSetLineWidth(g, st.lineWidth)
    CGContextSetLineCap(g, st.lineCap)
    CGContextSetLineJoin(g, st.lineJoin)
    if !st.dash.isEmpty { st.dash.withUnsafeBufferPointer { CGContextSetLineDash(g, st.dashPhase, $0.baseAddress, $0.count) } }
    CGContextStrokePath(g)
    CGContextRestoreGState(g)
}
struct _MWOffsetShape<S: Shape>: Shape {
    let shape: S, dx: CGFloat, dy: CGFloat
    func path(in rect: CGRect) -> Path { shape.path(in: rect).offsetBy(dx: dx, dy: dy) }
}

@frozen public struct Rectangle: Shape {
    @inlinable public init() {}
    public func path(in rect: CGRect) -> Path { Path(rect) }
}
@frozen public struct RoundedRectangle: Shape {
    public var cornerSize: CGSize
    public var style: RoundedCornerStyle
    @inlinable public init(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) { self.cornerSize = cornerSize; self.style = style }
    @inlinable public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) { self.init(cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style) }
    public func path(in rect: CGRect) -> Path { Path(roundedRect: rect, cornerSize: cornerSize, style: style) }
}
@frozen public struct Circle: Shape {
    @inlinable public init() {}
    public func path(in rect: CGRect) -> Path {
        let d = min(rect.width, rect.height)
        return Path(ellipseIn: CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d))
    }
}
@frozen public struct Ellipse: Shape {
    @inlinable public init() {}
    public func path(in rect: CGRect) -> Path { Path(ellipseIn: rect) }
}
@frozen public struct Capsule: Shape {
    public var style: RoundedCornerStyle
    @inlinable public init(style: RoundedCornerStyle = .circular) { self.style = style }
    public func path(in rect: CGRect) -> Path { let r = min(rect.width, rect.height) / 2; return Path(roundedRect: rect, cornerRadius: r) }
}

protocol _MWStroked { var _mwStyle: StrokeStyle { get }; func _mwPath(_ r: CGRect) -> Path }
extension _StrokedShape: _MWStroked {
    var _mwStyle: StrokeStyle { style }
    func _mwPath(_ r: CGRect) -> Path { shape.path(in: r) }
}
extension InsettableShape {
    @inlinable public func strokeBorder<S>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View where S: ShapeStyle {
        strokeBorder(content, style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
    }
    @inlinable public func strokeBorder(lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View {
        strokeBorder(style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
    }
}
