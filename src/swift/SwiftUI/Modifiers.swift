// The modifier types that Apple's inlinable view modifiers build inside apps (.opacity, .background, .overlay,
// .clipShape, .onAppear, .onChange, .task, .onHover, .contentShape, .alignmentGuide, .allowsHitTesting...): same
// names and stored properties as Apple's (apps lay them out at compile time), interpreted by the engine.
import Foundation
import AppKit

@frozen public struct _OpacityEffect: ViewModifier, _MWModifier {
    public var opacity: Double
    @inlinable public init(opacity: Double) { self.opacity = opacity }
    public typealias Body = Never
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] { content(c).map { _MWAlphaNode($0, opacity) } }
}
@frozen public struct _ClipEffect<ClipShape>: ViewModifier, _MWModifier where ClipShape: Shape {
    public var shape: ClipShape
    public var style: FillStyle
    @inlinable public init(shape: ClipShape, style: FillStyle = FillStyle()) { self.shape = shape; self.style = style }
    public typealias Body = Never
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        let s = shape
        return content(c).map { _MWClipNode($0) { s.path(in: $0) } }
    }
}
@frozen public struct _BackgroundModifier<Background>: ViewModifier, _MWModifier where Background: View {
    public var background: Background
    public var alignment: Alignment
    @inlinable public init(background: Background, alignment: Alignment = .center) { self.background = background; self.alignment = alignment }
    public typealias Body = Never
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        content(c).enumerated().map { i, n in _MWDecorNode(n, below: _mwResolve(background, c.child("bg\(i)")), above: [], alignment: alignment) }
    }
}
@frozen public struct _OverlayModifier<Overlay>: ViewModifier, _MWModifier where Overlay: View {
    public var overlay: Overlay
    public var alignment: Alignment
    @inlinable public init(overlay: Overlay, alignment: Alignment = .center) { self.overlay = overlay; self.alignment = alignment }
    public typealias Body = Never
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        content(c).enumerated().map { i, n in _MWDecorNode(n, below: [], above: _mwResolve(overlay, c.child("ov\(i)")), alignment: alignment) }
    }
}
@frozen public struct _BackgroundStyleModifier<Style>: ViewModifier, _MWModifier where Style: ShapeStyle {
    public var style: Style
    public var ignoresSafeAreaEdges: Edge.Set
    @inlinable public init(style: Style, ignoresSafeAreaEdges: Edge.Set) { self.style = style; self.ignoresSafeAreaEdges = ignoresSafeAreaEdges }
    public typealias Body = Never
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        let bg = _ShapeView(shape: Rectangle(), style: style)
        return content(c).enumerated().map { i, n in _MWDecorNode(n, below: _mwResolve(bg, c.child("bs\(i)")), above: [], alignment: .center) }
    }
}
@frozen public struct _InsettableBackgroundShapeModifier<Style, S>: ViewModifier, _MWModifier where Style: ShapeStyle, S: InsettableShape {
    public var style: Style
    public var shape: S
    public var fillStyle: FillStyle
    @inlinable public init(style: Style, shape: S, fillStyle: FillStyle) { self.style = style; self.shape = shape; self.fillStyle = fillStyle }
    public typealias Body = Never
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        let bg = _ShapeView(shape: shape, style: style, fillStyle: fillStyle)
        return content(c).enumerated().map { i, n in _MWDecorNode(n, below: _mwResolve(bg, c.child("ib\(i)")), above: [], alignment: .center) }
    }
}
@frozen public struct _ContentShapeModifier<ContentShape>: ViewModifier, _MWModifier where ContentShape: Shape {
    public var shape: ContentShape
    public var eoFill: Bool
    @inlinable public init(shape: ContentShape, eoFill: Bool = false) { self.shape = shape; self.eoFill = eoFill }
    public typealias Body = Never
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] { content(c) }
}
@frozen public struct _AllowsHitTestingModifier: ViewModifier, _MWModifier {
    public var allowsHitTesting: Bool
    @inlinable public init(allowsHitTesting: Bool) { self.allowsHitTesting = allowsHitTesting }
    public typealias Body = Never
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        allowsHitTesting ? content(c) : content(c).map { _MWNoHitNode([$0]) }
    }
}
final class _MWNoHitNode: _MWNode {
    override func size(_ p: _MWProposal) -> CGSize { children[0].size(p) }
    override func place(_ r: CGRect) { frame = r; children[0].place(r) }
    override func hit(_ p: CGPoint) -> _MWNode? { nil }
    override var isSpacer: Bool { children[0].isSpacer }
}
@frozen public struct _AlignmentWritingModifier: ViewModifier, _MWModifier {
    @usableFromInline let key: AlignmentKey
    @usableFromInline let computeValue: (ViewDimensions) -> CGFloat
    @inlinable init(key: AlignmentKey, computeValue: @escaping (ViewDimensions) -> CGFloat) { self.key = key; self.computeValue = computeValue }
    public typealias Body = Never
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] { content(c) }   // ponytail: explicit guides not applied
}
@frozen public struct _AppearanceActionModifier: ViewModifier, _MWModifier {
    public var appear: (() -> Void)?
    public var disappear: (() -> Void)?
    @inlinable public init(appear: (() -> Void)? = nil, disappear: (() -> Void)? = nil) { self.appear = appear; self.disappear = disappear }
    public typealias Body = Never
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        if let a = appear { c.host.appeared(c.path, a) }
        return content(c)
    }
}
@frozen public struct _ValueActionModifier<Value>: ViewModifier, _MWModifier where Value: Equatable {
    public var value: Value
    public var action: (Value) -> Void
    @inlinable public init(value: Value, action: @escaping (Value) -> Void) { self.value = value; self.action = action }
    public typealias Body = Never
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        c.host.changed(c.path, value, action)
        return content(c)
    }
}
@frozen @usableFromInline internal struct _TaskModifier: ViewModifier, _MWModifier {
    @usableFromInline internal var action: @Sendable () async -> Void
    @usableFromInline internal var priority: TaskPriority
    @inlinable internal init(priority: TaskPriority, action: @escaping @Sendable () async -> Void) { self.priority = priority; self.action = action }
    @usableFromInline typealias Body = Never
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        let a = action, p = priority
        c.host.appeared(c.path) { Task(priority: p) { await a() } }
        return content(c)
    }
}
@frozen public struct _HoverRegionModifier: ViewModifier, _MWModifier {
    public let callback: (Bool) -> Void
    @inlinable public init(_ callback: @escaping (Bool) -> Void) { self.callback = callback }
    public typealias Body = Never
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] { content(c) }   // ponytail: no hover tracking
}

// MARK: - insettable shapes

public protocol InsettableShape: Shape {
    associatedtype InsetShape: InsettableShape
    func inset(by amount: CGFloat) -> Self.InsetShape
}
extension InsettableShape {
    @inlinable public func strokeBorder<S>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> some View where S: ShapeStyle {
        inset(by: style.lineWidth / 2).stroke(style: style).fill(content)
    }
    @inlinable public func strokeBorder(style: StrokeStyle, antialiased: Bool = true) -> some View {
        inset(by: style.lineWidth / 2).stroke(style: style)
    }
}
extension RoundedRectangle: InsettableShape {
    @frozen public struct _Inset: InsettableShape {
        @usableFromInline var base: RoundedRectangle
        @usableFromInline var amount: CGFloat
        @inlinable init(base: RoundedRectangle, amount: CGFloat) { self.base = base; self.amount = amount }
        public func path(in rect: CGRect) -> Path {
            Path(roundedRect: rect.insetBy(dx: amount, dy: amount), cornerSize: CGSize(width: max(0, base.cornerSize.width - amount), height: max(0, base.cornerSize.height - amount)), style: base.style)
        }
        public func inset(by amount: CGFloat) -> RoundedRectangle._Inset { _Inset(base: base, amount: self.amount + amount) }
    }
    @inlinable public func inset(by amount: CGFloat) -> RoundedRectangle._Inset { _Inset(base: self, amount: amount) }
}
extension Rectangle: InsettableShape {
    @frozen public struct _Inset: InsettableShape {
        @usableFromInline var amount: CGFloat
        @inlinable init(amount: CGFloat) { self.amount = amount }
        public func path(in rect: CGRect) -> Path { Path(rect.insetBy(dx: amount, dy: amount)) }
        public func inset(by amount: CGFloat) -> Rectangle._Inset { _Inset(amount: self.amount + amount) }
    }
    @inlinable public func inset(by amount: CGFloat) -> Rectangle._Inset { _Inset(amount: amount) }
}
extension Circle: InsettableShape {
    @frozen public struct _Inset: InsettableShape {
        @usableFromInline var amount: CGFloat
        @inlinable init(amount: CGFloat) { self.amount = amount }
        public func path(in rect: CGRect) -> Path { Circle().path(in: rect.insetBy(dx: amount, dy: amount)) }
        public func inset(by amount: CGFloat) -> Circle._Inset { _Inset(amount: self.amount + amount) }
    }
    @inlinable public func inset(by amount: CGFloat) -> Circle._Inset { _Inset(amount: amount) }
}
extension Capsule: InsettableShape {
    @frozen public struct _Inset: InsettableShape {
        @usableFromInline var base: Capsule
        @usableFromInline var amount: CGFloat
        @inlinable init(base: Capsule, amount: CGFloat) { self.base = base; self.amount = amount }
        public func path(in rect: CGRect) -> Path { base.path(in: rect.insetBy(dx: amount, dy: amount)) }
        public func inset(by amount: CGFloat) -> Capsule._Inset { _Inset(base: base, amount: self.amount + amount) }
    }
    @inlinable public func inset(by amount: CGFloat) -> Capsule._Inset { _Inset(base: self, amount: amount) }
}

/// a shape drawn as its outline (`.stroke(style:)`)
@frozen public struct _StrokedShape<S>: Shape where S: Shape {
    public var shape: S
    public var style: StrokeStyle
    @inlinable public init(shape: S, style: StrokeStyle) { self.shape = shape; self.style = style }
    public func path(in rect: CGRect) -> Path { shape.path(in: rect) }
    public var body: _MWStrokeView<S, ForegroundStyle> { _MWStrokeView(shape: shape, style: ForegroundStyle(), stroke: style) }
}


// MARK: - the view methods that build them (inlinable, as Apple's)

extension View {
    @inlinable public func opacity(_ opacity: Double) -> some View { modifier(_OpacityEffect(opacity: opacity)) }
    @inlinable public func clipShape<S>(_ shape: S, style: FillStyle = FillStyle()) -> some View where S: Shape { modifier(_ClipEffect(shape: shape, style: style)) }
    @inlinable public func clipped(antialiased: Bool = false) -> some View { clipShape(Rectangle(), style: FillStyle(eoFill: false, antialiased: antialiased)) }
    @inlinable public func cornerRadius(_ radius: CGFloat, antialiased: Bool = true) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius), style: FillStyle(eoFill: false, antialiased: antialiased))
    }
    @_disfavoredOverload public func background<Background>(_ background: Background, alignment: Alignment = .center) -> some View where Background: View {
        modifier(_BackgroundModifier(background: background, alignment: alignment))
    }
    @inlinable public func background<V>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View where V: View {
        modifier(_BackgroundModifier(background: content(), alignment: alignment))
    }
    @inlinable public func background<S>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View where S: ShapeStyle {
        modifier(_BackgroundStyleModifier(style: style, ignoresSafeAreaEdges: edges))
    }
    @inlinable public func background<S, T>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View where S: ShapeStyle, T: InsettableShape {
        modifier(_InsettableBackgroundShapeModifier(style: style, shape: shape, fillStyle: fillStyle))
    }
    public func overlay<Overlay>(_ overlay: Overlay, alignment: Alignment = .center) -> some View where Overlay: View {
        modifier(_OverlayModifier(overlay: overlay, alignment: alignment))
    }
    @inlinable public func overlay<V>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View where V: View {
        modifier(_OverlayModifier(overlay: content(), alignment: alignment))
    }
    @inlinable public func contentShape<S>(_ shape: S, eoFill: Bool = false) -> some View where S: Shape {
        modifier(_ContentShapeModifier(shape: shape, eoFill: eoFill))
    }
    @inlinable public func allowsHitTesting(_ enabled: Bool) -> some View { modifier(_AllowsHitTestingModifier(allowsHitTesting: enabled)) }
    @inlinable public func alignmentGuide(_ g: HorizontalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View {
        modifier(_AlignmentWritingModifier(key: g.key, computeValue: computeValue))
    }
    @inlinable public func alignmentGuide(_ g: VerticalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View {
        modifier(_AlignmentWritingModifier(key: g.key, computeValue: computeValue))
    }
    @inlinable public func onAppear(perform action: (() -> Void)? = nil) -> some View { modifier(_AppearanceActionModifier(appear: action, disappear: nil)) }
    @inlinable public func onDisappear(perform action: (() -> Void)? = nil) -> some View { modifier(_AppearanceActionModifier(appear: nil, disappear: action)) }
    @inlinable public func onChange<V>(of value: V, perform action: @escaping (_ newValue: V) -> Void) -> some View where V: Equatable {
        modifier(_ValueActionModifier(value: value, action: action))
    }
    @inlinable public func task(priority: TaskPriority = .userInitiated, _ action: @escaping @Sendable () async -> Void) -> some View {
        modifier(_TaskModifier(priority: priority, action: action))
    }
    @inlinable public func onHover(perform action: @escaping (Bool) -> Void) -> some View { modifier(_HoverRegionModifier(action)) }
}
