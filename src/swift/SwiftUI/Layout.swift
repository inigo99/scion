// Stacks, spacers, scroll views, grids and the view modifiers apps use most. The @frozen types keep Apple's stored
// properties (apps build them inline).
import Foundation
import AppKit
import Combine

// MARK: - variadic views (the stacks' storage)

public protocol _VariadicView_Root {}
public protocol _VariadicView_ViewRoot: _VariadicView_Root {}
public protocol _VariadicView_UnaryViewRoot: _VariadicView_ViewRoot {}
public protocol _VariadicView_MultiViewRoot: _VariadicView_ViewRoot {}
public enum _VariadicView {
    @frozen public struct Tree<Root, Content> where Root: _VariadicView_Root {
        public var root: Root
        public var content: Content
        @inlinable internal init(root: Root, content: Content) { self.root = root; self.content = content }
        @inlinable public init(_ root: Root, @ViewBuilder content: () -> Content) { self.root = root; self.content = content() }
    }
}

@frozen public struct _HStackLayout: _VariadicView_UnaryViewRoot {
    public var alignment: VerticalAlignment
    public var spacing: CGFloat?
    @inlinable public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) { self.alignment = alignment; self.spacing = spacing }
}
@frozen public struct _VStackLayout: _VariadicView_UnaryViewRoot {
    public var alignment: HorizontalAlignment
    public var spacing: CGFloat?
    @inlinable public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) { self.alignment = alignment; self.spacing = spacing }
}
@frozen public struct _ZStackLayout: _VariadicView_UnaryViewRoot {
    public var alignment: Alignment
    @inlinable public init(alignment: Alignment = .center) { self.alignment = alignment }
}

@frozen public struct HStack<Content>: View where Content: View {
    @usableFromInline internal var _tree: _VariadicView.Tree<_HStackLayout, Content>
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        _tree = .init(root: _HStackLayout(alignment: alignment, spacing: spacing), content: content())
    }
    public typealias Body = Never
    public var body: Never { _primitive("HStack") }
}
@frozen public struct VStack<Content>: View where Content: View {
    @usableFromInline internal var _tree: _VariadicView.Tree<_VStackLayout, Content>
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        _tree = .init(root: _VStackLayout(alignment: alignment, spacing: spacing), content: content())
    }
    public typealias Body = Never
    public var body: Never { _primitive("VStack") }
}
@frozen public struct ZStack<Content>: View where Content: View {
    @usableFromInline internal var _tree: _VariadicView.Tree<_ZStackLayout, Content>
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
        _tree = .init(root: _ZStackLayout(alignment: alignment), content: content())
    }
    public typealias Body = Never
    public var body: Never { _primitive("ZStack") }
}
extension HStack: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        [_MWStackNode(.horizontal, spacing: _tree.root.spacing, cross: Alignment(horizontal: .center, vertical: _tree.root.alignment), _mwResolve(_tree.content, c.child("h")))]
    }
}
extension VStack: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        [_MWStackNode(.vertical, spacing: _tree.root.spacing, cross: Alignment(horizontal: _tree.root.alignment, vertical: .center), _mwResolve(_tree.content, c.child("v")))]
    }
}
extension ZStack: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] { [_MWZStackNode(_tree.root.alignment, _mwResolve(_tree.content, c.child("z")))] }
}
public typealias LazyHStack<Content: View> = HStack<Content>
public typealias LazyVStack<Content: View> = VStack<Content>

@frozen public struct Spacer: View {
    public var minLength: CGFloat?
    @inlinable public init(minLength: CGFloat? = nil) { self.minLength = minLength }
    public typealias Body = Never
    public var body: Never { _primitive("Spacer") }
}
extension Spacer: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] { [_MWSpacerNode(minLength)] }
}

public struct Divider: View, _MWResolvable {
    public init() {}
    public typealias Body = Never
    public var body: Never { _primitive("Divider") }
    func _mwNodes(_ c: _MWContext) -> [_MWNode] { [_MWDividerNode()] }
}
final class _MWDividerNode: _MWNode {
    override func size(_ p: _MWProposal) -> CGSize {
        stackAxis == .horizontal ? CGSize(width: 1, height: _mwFinite(p.height, 1)) : CGSize(width: _mwFinite(p.width, 1), height: 1)
    }
    override func draw(_ g: CGContext) {
        NSColor.separatorColor.setFill()
        CGContextFillRect(g, frame)
    }
}

// MARK: - scrolling

public struct ScrollView<Content>: View where Content: View {
    public var content: Content
    public var axes: Axis.Set
    public var showsIndicators: Bool
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.axes = axes; self.showsIndicators = showsIndicators; self.content = content()
    }
    public typealias Body = Never
    public var body: Never { _primitive("ScrollView") }
}
extension ScrollView: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let inner = _mwResolve(content, c.child("s"))
        let n = _MWScrollNode(inner.count == 1 ? inner[0] : _MWStackNode(axes.contains(.horizontal) ? .horizontal : .vertical, spacing: nil, cross: .center, inner),
                              axes: axes, key: c.path, host: c.host)
        return [n]
    }
}
final class _MWScrollNode: _MWNode {
    let axes: Axis.Set
    let key: String
    weak var host: _MWHostView?
    var contentSize = CGSize.zero
    var offset: CGPoint {
        get { host?.store[key + "#scroll"] as? CGPoint ?? .zero }
        set { host?.store[key + "#scroll"] = newValue }
    }
    init(_ content: _MWNode, axes: Axis.Set, key: String, host: _MWHostView) {
        self.axes = axes; self.key = key; self.host = host
        super.init([content])
        if axes.contains(.vertical) { content.stackAxis = nil }
    }
    private func contentProposal(_ p: _MWProposal) -> _MWProposal {
        _MWProposal(width: axes.contains(.horizontal) ? nil : p.width, height: axes.contains(.vertical) ? nil : p.height)
    }
    override func size(_ p: _MWProposal) -> CGSize {
        let cs = children[0].size(contentProposal(p))
        return CGSize(width: axes.contains(.horizontal) ? _mwFinite(p.width, cs.width) : cs.width,
                      height: axes.contains(.vertical) ? _mwFinite(p.height, cs.height) : cs.height)
    }
    override func place(_ r: CGRect) {
        frame = r
        let cs = children[0].size(contentProposal(_MWProposal(r.size)))
        contentSize = CGSize(width: max(cs.width, r.width), height: max(cs.height, r.height))
        var o = offset
        o.x = min(max(0, o.x), max(0, contentSize.width - r.width))
        o.y = min(max(0, o.y), max(0, contentSize.height - r.height))
        offset = o
        children[0].place(CGRect(x: r.minX - o.x, y: r.minY - o.y, width: axes.contains(.horizontal) ? cs.width : r.width,
                                 height: axes.contains(.vertical) ? cs.height : r.height))
    }
    override func draw(_ g: CGContext) {
        CGContextSaveGState(g)
        CGContextClipToRect(g, frame)
        super.draw(g)
        if contentSize.height > frame.height + 1 {   // a thin overlay scroller
            let h = max(20, frame.height * frame.height / contentSize.height)
            let y = frame.minY + (frame.height - h) * offset.y / max(1, contentSize.height - frame.height)
            NSColor.labelColor.withAlphaComponent(0.25).setFill()
            CGContextAddPath(g, Path(roundedRect: CGRect(x: frame.maxX - 6, y: y + 2, width: 4, height: h - 4), cornerRadius: 2).cgPath)
            CGContextFillPath(g)
        }
        CGContextRestoreGState(g)
    }
    override func hit(_ p: CGPoint) -> _MWNode? { frame.contains(p) ? super.hit(p) : nil }
    override func scroll(_ p: CGPoint, dx: CGFloat, dy: CGFloat) -> Bool {
        if super.scroll(p, dx: dx, dy: dy) { return true }
        guard frame.contains(p) else { return false }
        var o = offset
        if axes.contains(.vertical) { o.y -= dy }
        if axes.contains(.horizontal) { o.x -= dx }
        offset = o
        place(frame)
        return true
    }
    func scrollTo(_ n: _MWNode) {
        var o = offset
        o.y += n.frame.minY - frame.minY
        offset = o
        place(frame)
    }
}

public struct ScrollViewProxy {
    weak var host: _MWHostView?
    public func scrollTo<ID>(_ id: ID, anchor: UnitPoint? = nil) where ID: Hashable {
        guard let root = host?.root else { return }
        var target: _MWNode?, scroller: _MWScrollNode?
        func walk(_ n: _MWNode, _ s: _MWScrollNode?) {
            let s2 = (n as? _MWScrollNode) ?? s
            if target == nil, n.tag == AnyHashable(id) { target = n; scroller = s2; return }
            for c in n.children { walk(c, s2) }
        }
        walk(root, nil)
        if let t = target { scroller?.scrollTo(t); host?.needsDisplay = true }
    }
}
@frozen public struct ScrollViewReader<Content>: View where Content: View {
    public var content: (ScrollViewProxy) -> Content
    @inlinable public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) { self.content = content }
    public typealias Body = Never
    public var body: Never { _primitive("ScrollViewReader") }
}
extension ScrollViewReader: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] { _mwResolve(content(ScrollViewProxy(host: c.host)), c.child("r")) }
}

// MARK: - geometry reader and grids

public struct GeometryProxy {
    public let size: CGSize
    let origin: CGPoint
    public var safeAreaInsets: EdgeInsets { EdgeInsets() }
    public func frame(in coordinateSpace: CoordinateSpace) -> CGRect { CGRect(origin: coordinateSpace == .local ? .zero : origin, size: size) }
    public subscript<T>(anchor: Anchor<T>) -> T { anchor.box.resolve(CGRect(origin: .zero, size: size)) }
}
@frozen public struct GeometryReader<Content>: View where Content: View {
    public var content: (GeometryProxy) -> Content
    @inlinable public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) { self.content = content }
    public typealias Body = Never
    public var body: Never { _primitive("GeometryReader") }
}
extension GeometryReader: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] { [_MWGeometryNode(c, content)] }
}
/// lays out its content only when it knows its size (the content is resolved during layout)
final class _MWGeometryNode: _MWNode {
    let ctx: _MWContext
    let make: (GeometryProxy) -> [_MWNode]
    init<C: View>(_ c: _MWContext, _ f: @escaping (GeometryProxy) -> C) {
        ctx = c
        make = { g in _mwResolve(f(g), c.child("g")) }
        super.init()
        alignment = .topLeading
    }
    override func size(_ p: _MWProposal) -> CGSize { CGSize(width: _mwFinite(p.width, 10), height: _mwFinite(p.height, 10)) }
    override func place(_ r: CGRect) {
        children = make(GeometryProxy(size: r.size, origin: r.origin))
        super.place(r)
    }
}

public struct GridItem {
    public enum Size {
        case fixed(CGFloat)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }
    public var size: GridItem.Size
    public var spacing: CGFloat?
    public var alignment: Alignment?
    public init(_ size: GridItem.Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {
        self.size = size; self.spacing = spacing; self.alignment = alignment
    }
}
public struct PinnedScrollableViews: OptionSet {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1)
    public static let sectionFooters = PinnedScrollableViews(rawValue: 2)
}
public struct LazyVGrid<Content>: View where Content: View {
    let columns: [GridItem], alignment: HorizontalAlignment, spacing: CGFloat?, content: Content
    public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {
        self.columns = columns; self.alignment = alignment; self.spacing = spacing; self.content = content()
    }
    public typealias Body = Never
    public var body: Never { _primitive("LazyVGrid") }
}
extension LazyVGrid: _MWResolvable {
    /// ponytail: adaptive columns count as one flexible column
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let items = _mwResolve(content, c.child("g")), n = max(1, columns.count)
        var rows: [_MWNode] = []
        var i = 0
        while i < items.count {
            let row = Array(items[i..<min(i + n, items.count)]).enumerated().map { (k, node) -> _MWNode in
                if case .fixed(let w) = columns[k].size { let f = _MWFrameNode(node, alignment: .center); f.fixedW = w; return f }
                let f = _MWFrameNode(node, alignment: .center); f.maxW = .infinity; return f
            }
            rows.append(_MWStackNode(.horizontal, spacing: columns.first?.spacing, cross: .center, row))
            i += n
        }
        return [_MWStackNode(.vertical, spacing: spacing, cross: Alignment(horizontal: alignment, vertical: .center), rows)]
    }
}

// MARK: - layout modifiers

@frozen public struct _PaddingLayout: ViewModifier {
    public var edges: Edge.Set
    public var insets: EdgeInsets?
    @inlinable public init(edges: Edge.Set = .all, insets: EdgeInsets?) { self.edges = edges; self.insets = insets }
    public typealias Body = Never
}
extension _PaddingLayout: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        let i = insets ?? EdgeInsets(edges, 16)
        let e = EdgeInsets(top: edges.contains(.top) ? i.top : 0, leading: edges.contains(.leading) ? i.leading : 0,
                           bottom: edges.contains(.bottom) ? i.bottom : 0, trailing: edges.contains(.trailing) ? i.trailing : 0)
        return _mwWrapAll(content(c)) { _MWPaddingNode(e, $0) }
    }
}
/// a modifier applied to a list of views wraps them together when there are several (as one view)
func _mwWrapAll(_ nodes: [_MWNode], _ f: (_MWNode) -> _MWNode) -> [_MWNode] {
    nodes.map(f)
}

@frozen public struct _FrameLayout: ViewModifier {
    @usableFromInline let width: CGFloat?
    @usableFromInline let height: CGFloat?
    @usableFromInline let alignment: Alignment
    @usableFromInline init(width: CGFloat?, height: CGFloat?, alignment: Alignment) { self.width = width; self.height = height; self.alignment = alignment }
    public typealias Body = Never
}
extension _FrameLayout: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        content(c).map { let f = _MWFrameNode($0, alignment: alignment); f.fixedW = width; f.fixedH = height; return f }
    }
}
@frozen public struct _FlexFrameLayout: ViewModifier {
    @usableFromInline let minWidth: CGFloat?
    @usableFromInline let idealWidth: CGFloat?
    @usableFromInline let maxWidth: CGFloat?
    @usableFromInline let minHeight: CGFloat?
    @usableFromInline let idealHeight: CGFloat?
    @usableFromInline let maxHeight: CGFloat?
    @usableFromInline let alignment: Alignment
    @usableFromInline init(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil, minHeight: CGFloat? = nil,
                           idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil, alignment: Alignment) {
        self.minWidth = minWidth; self.idealWidth = idealWidth; self.maxWidth = maxWidth
        self.minHeight = minHeight; self.idealHeight = idealHeight; self.maxHeight = maxHeight; self.alignment = alignment
    }
    public typealias Body = Never
}
extension _FlexFrameLayout: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        content(c).map {
            let f = _MWFrameNode($0, alignment: alignment)
            f.minW = minWidth; f.idealW = idealWidth; f.maxW = maxWidth; f.minH = minHeight; f.idealH = idealHeight; f.maxH = maxHeight
            return f
        }
    }
}
@frozen public struct _FixedSizeLayout: ViewModifier {
    @usableFromInline var horizontal: Bool
    @usableFromInline var vertical: Bool
    @inlinable public init(horizontal: Bool = true, vertical: Bool = true) { self.horizontal = horizontal; self.vertical = vertical }
    public typealias Body = Never
}
extension _FixedSizeLayout: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        content(c).map { _MWFixedSizeNode($0, h: horizontal, v: vertical) }
    }
}

extension View {
    @inlinable public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        modifier(_FrameLayout(width: width, height: height, alignment: alignment))
    }
    public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil, minHeight: CGFloat? = nil,
                      idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        modifier(_FlexFrameLayout(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth, minHeight: minHeight,
                                  idealHeight: idealHeight, maxHeight: maxHeight, alignment: alignment))
    }
    public func padding(_ insets: EdgeInsets) -> some View { modifier(_PaddingLayout(edges: .all, insets: insets)) }
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        modifier(_PaddingLayout(edges: edges, insets: length.map { EdgeInsets(_all: $0) }))
    }
    public func padding(_ length: CGFloat) -> some View { padding(.all, length) }
    @inlinable public func fixedSize(horizontal: Bool, vertical: Bool) -> some View { modifier(_FixedSizeLayout(horizontal: horizontal, vertical: vertical)) }
    @inlinable public func fixedSize() -> some View { fixedSize(horizontal: true, vertical: true) }
    public func layoutPriority(_ value: Double) -> some View { modifier(_MWWrap { n, _ in n.priority = value; return n }) }
    public func offset(_ offset: CGSize) -> some View { modifier(_MWWrap { n, _ in _MWOffsetNode(n, offset) }) }
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View { offset(CGSize(width: x, height: y)) }
    public func aspectRatio(_ aspectRatio: CGFloat? = nil, contentMode: ContentMode) -> some View {
        modifier(_MWWrap { n, _ in _MWAspectNode(n, ratio: aspectRatio ?? (n.traits["aspect"] as? CGFloat) ?? 1, fit: contentMode == .fit) })
    }
    public func aspectRatio(_ aspectRatio: CGSize, contentMode: ContentMode) -> some View {
        self.aspectRatio(aspectRatio.width / max(aspectRatio.height, 1), contentMode: contentMode)
    }
    public func scaledToFit() -> some View { aspectRatio(nil, contentMode: .fit) }
    public func scaledToFill() -> some View { aspectRatio(nil, contentMode: .fill) }
}
@frozen public enum ContentMode: Hashable, CaseIterable, Sendable { case fit, fill }

final class _MWOffsetNode: _MWNode {
    let d: CGSize
    init(_ n: _MWNode, _ d: CGSize) { self.d = d; super.init([n]) }
    override func size(_ p: _MWProposal) -> CGSize { children[0].size(p) }
    override func place(_ r: CGRect) { frame = r; children[0].place(r.offsetBy(dx: d.width, dy: d.height)) }
}
final class _MWAspectNode: _MWNode {
    let ratio: CGFloat, fit: Bool
    init(_ n: _MWNode, ratio: CGFloat, fit: Bool) { self.ratio = ratio; self.fit = fit; super.init([n]) }
    override func size(_ p: _MWProposal) -> CGSize {
        let w = p.width ?? (p.height.map { $0 * ratio }), h = p.height ?? (p.width.map { $0 / ratio })
        guard var ww = w, var hh = h, ww.isFinite || hh.isFinite else { return children[0].size(p) }
        if !ww.isFinite { ww = hh * ratio }
        if !hh.isFinite { hh = ww / ratio }
        let byW = CGSize(width: ww, height: ww / ratio), byH = CGSize(width: hh * ratio, height: hh)
        return fit ? (byW.height <= hh ? byW : byH) : (byW.height >= hh ? byW : byH)
    }
    override func place(_ r: CGRect) { frame = r; children[0].place(r) }
}

// MARK: - decoration

extension View {
    public func border<S>(_ content: S, width: CGFloat = 1) -> some View where S: ShapeStyle {
        overlay(Rectangle().strokeBorder(content, lineWidth: width))
    }
    public func foregroundColor(_ color: Color?) -> some View { environment(\.foregroundColor, color) }
    public func foregroundStyle<S>(_ style: S) -> some View where S: ShapeStyle {
        transformEnvironment(\.foregroundColor) { c in
            if let col = style as? Color { c = col } else if let p = style as? _MWPaint { let ns = p._mwColor(EnvironmentValues()); c = Color(ns) }
        }
    }
    public func tint(_ tint: Color?) -> some View { self }
    public func accentColor(_ accentColor: Color?) -> some View { self }
    public func font(_ font: Font?) -> some View { environment(\.font, font) }
    public func fontWeight(_ weight: Font.Weight?) -> some View { transformEnvironment(\.font) { f in if let w = weight { f = (f ?? .body).weight(w) } } }
    public func bold(_ isActive: Bool = true) -> some View { fontWeight(isActive ? .bold : nil) }
    public func italic(_ isActive: Bool = true) -> some View { self }
    public func hidden() -> some View { modifier(_MWWrap { n, _ in n.isHidden = true; return n }) }
    public func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View { self }
    public func blur(radius: CGFloat, opaque: Bool = false) -> some View { self }
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View { self }
    public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> some View { self }
    public func scaleEffect(_ s: CGSize, anchor: UnitPoint = .center) -> some View { self }
    public func brightness(_ amount: Double) -> some View { self }
    public func saturation(_ amount: Double) -> some View { self }
    public func colorMultiply(_ color: Color) -> some View { self }
    public func compositingGroup() -> some View { self }
    public func drawingGroup(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear) -> some View { self }
    public func zIndex(_ value: Double) -> some View { self }
    public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View { self }
    public func edgesIgnoringSafeArea(_ edges: Edge.Set) -> some View { self }
    public func help<S>(_ text: S) -> some View where S: StringProtocol { modifier(_MWWrap { n, _ in n.help = String(text); return n }) }
    public func help(_ text: Text) -> some View { modifier(_MWWrap { n, _ in n.help = text._mwPlain; return n }) }
    public func help(_ textKey: LocalizedStringKey) -> some View { help(Text(textKey)) }
}
public enum ColorRenderingMode: Hashable, Sendable { case nonLinear, linear, extendedLinear }
@frozen public struct SafeAreaRegions: OptionSet {
    public let rawValue: UInt
    @inlinable public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let container = SafeAreaRegions(rawValue: 1), keyboard = SafeAreaRegions(rawValue: 2), all = SafeAreaRegions(rawValue: .max)
}

final class _MWAlphaNode: _MWNode {
    let alpha: Double
    init(_ n: _MWNode, _ a: Double) { alpha = a; super.init([n]) }
    override func size(_ p: _MWProposal) -> CGSize { children[0].size(p) }
    override func place(_ r: CGRect) { frame = r; children[0].place(r) }
    override func draw(_ g: CGContext) {
        guard alpha > 0.001 else { return }
        CGContextSaveGState(g); CGContextSetAlpha(g, alpha); super.draw(g); CGContextRestoreGState(g)
    }
    override var isSpacer: Bool { children[0].isSpacer }
}
final class _MWClipNode: _MWNode {
    let shape: (CGRect) -> Path
    init(_ n: _MWNode, _ s: @escaping (CGRect) -> Path) { shape = s; super.init([n]) }
    override func size(_ p: _MWProposal) -> CGSize { children[0].size(p) }
    override func place(_ r: CGRect) { frame = r; children[0].place(r) }
    override func draw(_ g: CGContext) {
        CGContextSaveGState(g); CGContextAddPath(g, shape(frame).cgPath); CGContextClip(g); super.draw(g); CGContextRestoreGState(g)
    }
}

// MARK: - traits (tag, list row insets, transitions)

public protocol _ViewTraitKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}
@frozen public struct _TraitWritingModifier<Trait>: ViewModifier where Trait: _ViewTraitKey {
    public let value: Trait.Value
    @inlinable public init(value: Trait.Value) { self.value = value }
    public typealias Body = Never
}
extension _TraitWritingModifier: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        let nodes = content(c)
        for n in nodes { (value as? _MWTagValue)?.apply(n); n.traits[String(describing: Trait.self)] = value }
        return nodes
    }
}
protocol _MWTagValue { func apply(_ n: _MWNode) }
extension View {
    @inlinable public func _trait<K>(_ key: K.Type, _ value: K.Value) -> some View where K: _ViewTraitKey {
        modifier(_TraitWritingModifier<K>(value: value))
    }
    @inlinable public func tag<V>(_ tag: V) -> some View where V: Hashable { _trait(TagValueTraitKey<V>.self, .tagged(tag)) }
    @inlinable public func listRowInsets(_ insets: EdgeInsets?) -> some View { _trait(ListRowInsetsTraitKey.self, insets) }
    @inlinable public func transition(_ t: AnyTransition) -> some View { _trait(TransitionTraitKey.self, t) }
}
@usableFromInline struct TagValueTraitKey<V>: _ViewTraitKey where V: Hashable {
    @usableFromInline @frozen enum Value: _MWTagValue {
        case untagged
        case tagged(V)
        func apply(_ n: _MWNode) { if case .tagged(let v) = self { n.tag = AnyHashable(v) } }
    }
    @inlinable static var defaultValue: TagValueTraitKey<V>.Value { .untagged }
}
@usableFromInline struct ListRowInsetsTraitKey: _ViewTraitKey {
    @inlinable static var defaultValue: EdgeInsets? { nil }
}
@usableFromInline struct TransitionTraitKey: _ViewTraitKey {
    @inlinable static var defaultValue: AnyTransition { .opacity }
}

// MARK: - preferences

public protocol PreferenceKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
    static func reduce(value: inout Self.Value, nextValue: () -> Self.Value)
}
@frozen public struct _PreferenceWritingModifier<Key>: ViewModifier where Key: PreferenceKey {
    public var value: Key.Value
    @inlinable public init(key: Key.Type = Key.self, value: Key.Value) { self.value = value }
    public typealias Body = Never
}
extension _PreferenceWritingModifier: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] { content(c) }
}
extension View {
    @inlinable public func preference<K>(key: K.Type = K.self, value: K.Value) -> some View where K: PreferenceKey {
        modifier(_PreferenceWritingModifier<K>(value: value))
    }
    public func onPreferenceChange<K>(_ key: K.Type = K.self, perform action: @escaping (K.Value) -> Void) -> some View where K: PreferenceKey, K.Value: Equatable { self }
}
@usableFromInline struct PreferredColorSchemeKey: PreferenceKey {
    @usableFromInline typealias Value = ColorScheme?
    @usableFromInline static var defaultValue: ColorScheme? { nil }
    @usableFromInline static func reduce(value: inout ColorScheme?, nextValue: () -> ColorScheme?) { value = value ?? nextValue() }
}

// MARK: - events and lifecycle

extension View {
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
        modifier(_MWWrap { n, _ in let t = _MWTapNode([n]); t.requiredCount = count; t.onTap = { _ in action() }; return t })
    }
    @inlinable public func onReceive<P>(_ publisher: P, perform action: @escaping (P.Output) -> Void) -> some View where P: Publisher, P.Failure == Never {
        SubscriptionView(content: self, publisher: publisher, action: action)
    }
}
@frozen public struct SubscriptionView<PublisherType, Content>: View where PublisherType: Publisher, Content: View, PublisherType.Failure == Never {
    public var content: Content
    public var publisher: PublisherType
    public var action: (PublisherType.Output) -> Void
    @inlinable public init(content: Content, publisher: PublisherType, action: @escaping (PublisherType.Output) -> Void) {
        self.content = content; self.publisher = publisher; self.action = action
    }
    public typealias Body = Never
    public var body: Never { _primitive("SubscriptionView") }
}
extension SubscriptionView: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        c.host.subscribe(c.path, publisher, action)
        return _mwResolve(content, c.child("sv"))
    }
}

// MARK: - animation (changes apply at once)

@frozen public struct Animation: Equatable {
    @usableFromInline internal var box: AnimationBoxBase
    init(duration: Double) { box = AnimationBoxBase(duration) }
    var duration: Double { box.duration }
    public static func == (a: Animation, b: Animation) -> Bool { a.box === b.box || a.box.duration == b.box.duration }
    public static let `default` = Animation(duration: 0.35)
    public static let linear = Animation(duration: 0.35)
    public static let easeIn = Animation(duration: 0.35)
    public static let easeOut = Animation(duration: 0.35)
    public static let easeInOut = Animation(duration: 0.35)
    public static let spring = Animation(duration: 0.5)
    public static func linear(duration: Double) -> Animation { Animation(duration: duration) }
    public static func easeIn(duration: Double) -> Animation { Animation(duration: duration) }
    public static func easeOut(duration: Double) -> Animation { Animation(duration: duration) }
    public static func easeInOut(duration: Double) -> Animation { Animation(duration: duration) }
    public static func spring(response: Double = 0.55, dampingFraction: Double = 0.825, blendDuration: Double = 0) -> Animation { Animation(duration: response) }
    public static func interactiveSpring(response: Double = 0.15, dampingFraction: Double = 0.86, blendDuration: Double = 0.25) -> Animation { Animation(duration: response) }
    public func delay(_ delay: Double) -> Animation { self }
    public func speed(_ speed: Double) -> Animation { self }
    public func repeatForever(autoreverses: Bool = true) -> Animation { self }
    public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation { self }
}
@usableFromInline internal class AnimationBoxBase {
    let duration: Double
    init(_ d: Double) { duration = d }
}
@frozen public struct _AnimationModifier<Value>: ViewModifier where Value: Equatable {
    public var animation: Animation?
    public var value: Value
    @inlinable public init(animation: Animation?, value: Value) { self.animation = animation; self.value = value }
    public typealias Body = Never
}
extension _AnimationModifier: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] { content(c) }
}
extension View {
    public func animation<V>(_ animation: Animation?, value: V) -> some View where V: Equatable { modifier(_AnimationModifier(animation: animation, value: value)) }
    @inlinable public func animation(_ animation: Animation?) -> some View { modifier(_AnimationModifier(animation: animation, value: 0)) }
}
@frozen public struct AnyTransition {
    @usableFromInline internal let box: AnyTransitionBox
    init() { box = AnyTransitionBox() }
    public static let identity = AnyTransition(), opacity = AnyTransition(), slide = AnyTransition()
    public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition { AnyTransition() }
    public static var scale: AnyTransition { AnyTransition() }
    public static func move(edge: Edge) -> AnyTransition { AnyTransition() }
    public static func offset(_ offset: CGSize) -> AnyTransition { AnyTransition() }
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition { AnyTransition() }
    public func combined(with other: AnyTransition) -> AnyTransition { self }
    public func animation(_ animation: Animation?) -> AnyTransition { self }
}
@usableFromInline internal class AnyTransitionBox { init() {} }
