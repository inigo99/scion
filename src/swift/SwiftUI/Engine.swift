// The engine: views are resolved into a tree of nodes (_MWNode) every time something changes; nodes are laid out
// with SwiftUI's rule (the parent proposes a size, the child picks its own, the parent places it) and drawn by the
// hosting view (_MWHostView, an NSView). State (@State, @StateObject) lives in the host keyed by the view's path.
// ponytail: the whole tree is rebuilt on each change (no diffing); fine for the window-sized UIs of apps.
import Foundation
import AppKit
import Combine
@_spi(Reflection) import Swift

// MARK: - resolution

final class _MWContext {
    let host: _MWHostView
    var env: EnvironmentValues
    var path: String
    /// the content each enclosing ViewModifier's body(content:) stands for (innermost last)
    var modifierContent: [(_MWContext) -> [_MWNode]] = []
    init(host: _MWHostView, env: EnvironmentValues, path: String) { self.host = host; self.env = env; self.path = path }
    func child(_ p: String) -> _MWContext {
        let c = _MWContext(host: host, env: env, path: path + "/" + p)
        c.modifierContent = modifierContent
        return c
    }
    func with(env e: EnvironmentValues) -> _MWContext {
        let c = _MWContext(host: host, env: e, path: path)
        c.modifierContent = modifierContent
        return c
    }
}

/// views the engine draws itself
protocol _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode]
}
/// modifiers the engine applies itself
protocol _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode]
}

func _mwResolve<V: View>(_ view: V, _ c: _MWContext) -> [_MWNode] {
    let nodes = _mwResolveNodes(view, c)
    for n in nodes where n.id == nil { n.id = c.path }   // (the innermost view's path: resolution goes outwards)
    return nodes
}
private func _mwResolveNodes<V: View>(_ view: V, _ c: _MWContext) -> [_MWNode] {
    if _mwTraceResolve { fputs("[resolve] \(c.path) \(V.self)\n".prefix(300) + "\n", stderr) }
    if let r = view as? _MWResolvable { return r._mwNodes(c) }
    if let r = view as? any NSViewRepresentable { return _mwRepresent(r, c) }
    if let r = view as? any NSViewControllerRepresentable { return _mwRepresentController(r, c) }
    if V.Body.self == Never.self { _mwUnsupported(V.self); return [] }
    var v = view
    _mwBindProperties(&v, c)
    return _mwResolve(v.body, c.child("b"))
}
/// a primitive view scion does not draw yet: said once per type on stderr
nonisolated(unsafe) var _mwUnsupportedSeen = Set<ObjectIdentifier>()
func _mwUnsupported(_ t: Any.Type) {
    if _mwUnsupportedSeen.insert(ObjectIdentifier(t)).inserted { fputs("[scion] SwiftUI: unsupported view: \(t)\n", stderr) }
}
func _mwResolveAny(_ v: Any, _ c: _MWContext) -> [_MWNode] {
    guard let v = v as? any View else { _mwUnsupported(type(of: v)); return [] }
    return _mwResolve(v, c)
}

/// binds every dynamic property of a view (state, environment, observed objects) before its body runs
func _mwBindProperties<V>(_ v: inout V, _ c: _MWContext) {
    withUnsafeMutablePointer(to: &v) { p in _mwBindFields(V.self, UnsafeMutableRawPointer(p), c, c.path) }
}
private func _mwBindFields(_ t: Any.Type, _ base: UnsafeMutableRawPointer, _ c: _MWContext, _ key: String) {
    _forEachField(of: t, options: []) { _, offset, ft, _ in
        let k = "\(key)#\(offset)"
        if let d = ft as? _MWDynamic.Type { _mwBindOne(d, base + offset, c, k) }
        else if ft is DynamicProperty.Type { _mwBindFields(ft, base + offset, c, k) }
        return true
    }
}
private func _mwBindOne<T: _MWDynamic>(_ t: T.Type, _ p: UnsafeMutableRawPointer, _ c: _MWContext, _ key: String) {
    p.assumingMemoryBound(to: T.self).pointee._mwBind(c, key: key)
}

extension EmptyView: _MWResolvable { func _mwNodes(_ c: _MWContext) -> [_MWNode] { [] } }
extension Never: _MWResolvable { func _mwNodes(_ c: _MWContext) -> [_MWNode] { [] } }
extension TupleView: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let m = Mirror(reflecting: value)
        if m.displayStyle != .tuple { return _mwResolveAny(value, c.child("0")) }
        var out: [_MWNode] = []
        for (i, ch) in m.children.enumerated() { out += _mwResolveAny(ch.value, c.child("\(i)")) }
        return out
    }
}
extension _ConditionalContent: _MWResolvable where TrueContent: View, FalseContent: View {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        switch storage {
        case .trueContent(let v): return _mwResolve(v, c.child("t"))
        case .falseContent(let v): return _mwResolve(v, c.child("f"))
        }
    }
}
extension Optional: _MWResolvable where Wrapped: View {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] { self.map { _mwResolve($0, c.child("s")) } ?? [] }
}
extension AnyView: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] { _mwResolve(storage.view, c.child(String(describing: type(of: storage.view)))) }
}
extension Group: _MWResolvable where Content: View {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] { _mwResolve(content, c) }
}
extension IDView: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] { _mwResolve(content, c.child("id:\(id)")) }
}
extension ForEach: _MWResolvable where Content: View {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        var out: [_MWNode] = []
        for e in data {
            let id = idGenerator(e)
            let nodes = _mwResolve(content(e), c.child("e:\(id)"))
            for n in nodes where n.tag == nil { n.tag = AnyHashable(id) }   // Picker/TabView rows default to their id
            out += nodes
        }
        return out
    }
}
extension ModifiedContent: _MWResolvable where Content: View, Modifier: ViewModifier {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let content = self.content
        let inner: (_MWContext) -> [_MWNode] = { _mwResolve(content, $0.child("c")) }
        if let m = modifier as? _MWModifier { return m._mwModify(c, inner) }
        if Modifier.Body.self == Never.self { _mwUnsupported(Modifier.self); return inner(c) }
        // a ViewModifier written by the app: its body(content:) stands for the content
        var m = modifier
        _mwBindProperties(&m, c)
        let mc = c.child("m")
        mc.modifierContent.append({ cc in inner(cc) })
        return _mwResolve(m.body(content: _ViewModifier_Content<Modifier>()), mc)
    }
}
extension _ViewModifier_Content: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        guard let f = c.modifierContent.last else { return [] }
        let cc = c.child("mc")
        cc.modifierContent.removeLast()
        return f(cc)
    }
}
extension _EnvironmentKeyWritingModifier: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        var e = c.env; e[keyPath: keyPath] = value
        return content(c.with(env: e))
    }
}
extension _EnvironmentKeyTransformModifier: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        var e = c.env; transform(&e[keyPath: keyPath])
        return content(c.with(env: e))
    }
}
extension EmptyModifier: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] { content(c) }
}

/// a modifier that wraps each node of its content (padding, frame, background...)
struct _MWWrap: ViewModifier, _MWModifier {
    typealias Body = Never
    let make: (_MWNode, _MWContext) -> _MWNode
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        content(c).map { make($0, c) }
    }
}

// MARK: - nodes and layout

struct _MWProposal {
    var width: CGFloat?
    var height: CGFloat?
    static let ideal = _MWProposal(width: nil, height: nil)
    init(width: CGFloat?, height: CGFloat?) { self.width = width; self.height = height }
    init(_ s: CGSize) { width = s.width; height = s.height }
    func main(_ a: Axis) -> CGFloat? { a == .horizontal ? width : height }
    func cross(_ a: Axis) -> CGFloat? { a == .horizontal ? height : width }
    static func along(_ a: Axis, main: CGFloat?, cross: CGFloat?) -> _MWProposal {
        a == .horizontal ? _MWProposal(width: main, height: cross) : _MWProposal(width: cross, height: main)
    }
    func inset(_ w: CGFloat, _ h: CGFloat) -> _MWProposal {
        _MWProposal(width: width.map { max(0, $0 - w) }, height: height.map { max(0, $0 - h) })
    }
}
extension CGSize {
    func main(_ a: Axis) -> CGFloat { a == .horizontal ? width : height }
    func cross(_ a: Axis) -> CGFloat { a == .horizontal ? height : width }
    static func along(_ a: Axis, main: CGFloat, cross: CGFloat) -> CGSize {
        a == .horizontal ? CGSize(width: main, height: cross) : CGSize(width: cross, height: main)
    }
}

/// a node of the resolved tree; the base class lays its children on top of each other (like ZStack)
class _MWNode {
    var frame = CGRect.zero        // host coordinates (flipped: y down)
    var children: [_MWNode]
    var tag: AnyHashable?           // .tag(_:) / ForEach id: Picker and TabView selection
    var priority: Double = 0        // .layoutPriority(_:)
    var help: String?
    var isHidden = false
    var traits: [String: Any] = [:]  // tabItem, listRowInsets...
    var alignment = Alignment.center
    /// the path of the view that made the node: an animation matches the nodes of two trees by it
    var id: String?
    /// a transition in progress (Animation.swift)
    var fx: _MWFxState?
    init(_ children: [_MWNode] = []) { self.children = children }
    /// draws the node, with its transition if it has one
    final func render(_ g: CGContext) {
        guard let f = fx else { draw(g); return }
        guard f.alpha > 0.001 else { return }
        let ax = frame.minX + f.anchor.x * frame.width, ay = frame.minY + f.anchor.y * frame.height
        CGContextSaveGState(g)
        if f.alpha < 0.999 { CGContextSetAlpha(g, f.alpha) }
        CGContextTranslateCTM(g, ax + f.dx, ay + f.dy); CGContextScaleCTM(g, max(f.sx, 0.001), max(f.sy, 0.001)); CGContextTranslateCTM(g, -ax, -ay)
        draw(g)
        CGContextRestoreGState(g)
    }

    func size(_ p: _MWProposal) -> CGSize {
        var w: CGFloat = 0, h: CGFloat = 0
        for ch in children { let s = ch.size(p); w = max(w, s.width); h = max(h, s.height) }
        return CGSize(width: w, height: h)
    }
    func place(_ r: CGRect) {
        frame = r
        for ch in children { ch.place(_mwAlign(ch.size(_MWProposal(r.size)), in: r, alignment)) }
    }
    func draw(_ g: CGContext) {
        guard !isHidden else { return }
        for ch in children { ch.render(g) }
    }
    /// the node under `p` that handles mouse events, deepest first
    func hit(_ p: CGPoint) -> _MWNode? {
        guard !isHidden else { return nil }
        for ch in children.reversed() { if let h = ch.hit(p) { return h } }
        return handlesMouse && frame.contains(p) ? self : nil
    }
    var handlesMouse: Bool { false }
    func mouseDown(_ p: CGPoint, _ e: NSEvent) {}
    func mouseDragged(_ p: CGPoint, _ e: NSEvent) {}
    func mouseUp(_ p: CGPoint, _ e: NSEvent) {}
    func scroll(_ p: CGPoint, dx: CGFloat, dy: CGFloat) -> Bool {
        for ch in children.reversed() where ch.frame.contains(p) { if ch.scroll(p, dx: dx, dy: dy) { return true } }
        return false
    }
    /// first text baseline from the node's top
    var baseline: CGFloat? { children.first?.baseline.map { $0 + (children.first!.frame.minY - frame.minY) } ?? children.first?.ownBaseline }
    var ownBaseline: CGFloat? { nil }
    /// walks the tree (keyboard shortcuts, text of a row, ...)
    func all(_ f: (_MWNode) -> Void) { f(self); for ch in children { ch.all(f) } }
    var text: String? { for ch in children { if let t = ch.text { return t } }; return nil }
    /// a stack asks its spacers and dividers for its axis
    var stackAxis: Axis? { didSet { if !(self is _MWStackNode) { for ch in children { ch.stackAxis = stackAxis } } } }
    var isSpacer: Bool { children.count == 1 && children[0].isSpacer }
}

/// places a child of size `s` in `r`: the child's guide on the container's guide
func _mwAlign(_ s: CGSize, in r: CGRect, _ a: Alignment, baseline: CGFloat? = nil) -> CGRect {
    let child = ViewDimensions(size: s, baseline: baseline), box = ViewDimensions(size: r.size, baseline: baseline)
    let x = r.minX + box[a.horizontal] - child[a.horizontal]
    let y = r.minY + box[a.vertical] - child[a.vertical]
    return CGRect(x: x.rounded(), y: y.rounded(), width: s.width, height: s.height)
}

/// HStack / VStack
final class _MWStackNode: _MWNode {
    let axis: Axis
    let spacing: CGFloat?
    let cross: Alignment   // only the axis across the stack counts
    init(_ axis: Axis, spacing: CGFloat?, cross: Alignment, _ children: [_MWNode]) {
        self.axis = axis; self.spacing = spacing; self.cross = cross
        super.init(children)
        for ch in children { ch.stackAxis = axis }
    }
    private var visible: [_MWNode] { children.filter { !$0.isHidden } }
    private func gap(_ a: _MWNode, _ b: _MWNode) -> CGFloat {
        if let s = spacing { return s }
        return a.isSpacer || b.isSpacer ? 0 : 8
    }
    private func sizes(_ p: _MWProposal) -> [CGSize] {
        let ch = visible
        guard !ch.isEmpty else { return [] }
        var gaps: CGFloat = 0
        for i in 1..<max(ch.count, 1) { gaps += gap(ch[i - 1], ch[i]) }
        guard let total = p.main(axis) else { return ch.map { $0.size(.along(axis, main: nil, cross: p.cross(axis))) } }
        // the least flexible first, higher layout priority before lower; each gets an equal share of what is left
        let flex: [CGFloat] = ch.map {
            let lo = $0.size(.along(axis, main: 0, cross: p.cross(axis))).main(axis)
            let hi = $0.size(.along(axis, main: .infinity, cross: p.cross(axis))).main(axis)
            return hi - lo
        }
        let order = ch.indices.sorted { ch[$0].priority != ch[$1].priority ? ch[$0].priority > ch[$1].priority : flex[$0] < flex[$1] }
        var out = [CGSize](repeating: .zero, count: ch.count)
        var left = max(0, total - gaps)
        for (k, i) in order.enumerated() {
            let share = left / CGFloat(order.count - k)
            let s = ch[i].size(.along(axis, main: share, cross: p.cross(axis)))
            out[i] = s
            left = max(0, left - s.main(axis))
        }
        return out
    }
    override func size(_ p: _MWProposal) -> CGSize {
        let ch = visible, ss = sizes(p)
        var main: CGFloat = 0, cr: CGFloat = 0
        for (i, s) in ss.enumerated() { main += s.main(axis) + (i > 0 ? gap(ch[i - 1], ch[i]) : 0); cr = max(cr, s.cross(axis)) }
        return .along(axis, main: main, cross: cr)
    }
    override func place(_ r: CGRect) {
        frame = r
        let ch = visible, ss = sizes(_MWProposal(r.size))
        var pos = axis == .horizontal ? r.minX : r.minY
        let base = ch.indices.compactMap { i -> CGFloat? in ch[i].measuredBaseline(ss[i]) }.max() ?? 0
        for (i, n) in ch.enumerated() {
            if i > 0 { pos += gap(ch[i - 1], n) }
            let s = ss[i]
            var o: CGFloat
            let crossStart = axis == .horizontal ? r.minY : r.minX
            if axis == .horizontal && (cross.vertical == .firstTextBaseline || cross.vertical == .lastTextBaseline) {
                o = crossStart + base - (n.measuredBaseline(s) ?? s.height)
            } else {
                let dc = ViewDimensions(size: s), dbox = ViewDimensions(size: r.size)
                o = axis == .horizontal ? crossStart + dbox[cross.vertical] - dc[cross.vertical] : crossStart + dbox[cross.horizontal] - dc[cross.horizontal]
            }
            o = o.rounded()
            n.place(axis == .horizontal ? CGRect(x: pos, y: o, width: s.width, height: s.height) : CGRect(x: o, y: pos, width: s.width, height: s.height))
            pos += s.main(axis)
        }
        for n in children where n.isHidden { n.place(.zero) }
    }
}
extension _MWNode {
    /// baseline for a size the node was given (before placing)
    func measuredBaseline(_ s: CGSize) -> CGFloat? {
        if let t = self as? _MWTextNode { return t.font.ascender + 1 }
        return children.first?.measuredBaseline(s)
    }
}

/// ZStack and overlays: all children in the same rectangle, aligned
final class _MWZStackNode: _MWNode {
    init(_ a: Alignment, _ children: [_MWNode]) { super.init(children); alignment = a }
}

final class _MWSpacerNode: _MWNode {
    let minLength: CGFloat?
    init(_ m: CGFloat?) { minLength = m; super.init() }
    override var isSpacer: Bool { true }
    override func size(_ p: _MWProposal) -> CGSize {
        let m = minLength ?? 8
        switch stackAxis {
        case .horizontal?: return CGSize(width: max(m, p.width ?? m), height: 0)
        case .vertical?: return CGSize(width: 0, height: max(m, p.height ?? m))
        case nil: return CGSize(width: max(m, p.width ?? m), height: max(m, p.height ?? m))
        }
    }
}

final class _MWPaddingNode: _MWNode {
    let insets: EdgeInsets
    init(_ i: EdgeInsets, _ child: _MWNode) { insets = i; super.init([child]) }
    override func size(_ p: _MWProposal) -> CGSize {
        let s = children[0].size(p.inset(insets.leading + insets.trailing, insets.top + insets.bottom))
        return CGSize(width: s.width + insets.leading + insets.trailing, height: s.height + insets.top + insets.bottom)
    }
    override func place(_ r: CGRect) {
        frame = r
        children[0].place(CGRect(x: r.minX + insets.leading, y: r.minY + insets.top,
                                 width: max(0, r.width - insets.leading - insets.trailing), height: max(0, r.height - insets.top - insets.bottom)))
    }
    override var isSpacer: Bool { false }
}

/// .frame(width:height:) and .frame(minWidth:...maxHeight:)
final class _MWFrameNode: _MWNode {
    var minW, idealW, maxW, minH, idealH, maxH: CGFloat?
    var fixedW, fixedH: CGFloat?
    init(_ child: _MWNode, alignment a: Alignment) { super.init([child]); alignment = a }
    private func dim(_ p: CGFloat?, _ fixed: CGFloat?, _ mn: CGFloat?, _ ideal: CGFloat?, _ mx: CGFloat?, _ child: () -> CGFloat) -> CGFloat {
        if let f = fixed { return f }
        guard let p = p else { return Swift.min(Swift.max(ideal ?? child(), mn ?? 0), mx ?? .infinity) }
        if mn == nil && mx == nil { return child() }
        var v = mx != nil ? Swift.min(p, mx!) : Swift.max(p, child())
        if mx != nil && mn == nil { v = Swift.max(Swift.min(v, p), Swift.min(child(), v)) }
        if let m = mn { v = Swift.max(v, m) }
        return v.isFinite ? v : child()
    }
    private func childProposal(_ p: _MWProposal) -> _MWProposal {
        func d(_ p: CGFloat?, _ fixed: CGFloat?, _ mn: CGFloat?, _ ideal: CGFloat?, _ mx: CGFloat?) -> CGFloat? {
            if let f = fixed { return f }
            guard let v = p ?? ideal else { return nil }
            return Swift.min(Swift.max(v, mn ?? -.infinity), mx ?? .infinity)
        }
        return _MWProposal(width: d(p.width, fixedW, minW, idealW, maxW), height: d(p.height, fixedH, minH, idealH, maxH))
    }
    override func size(_ p: _MWProposal) -> CGSize {
        let cp = childProposal(p)
        var cs: CGSize?
        func child() -> CGSize { if cs == nil { cs = children[0].size(cp) }; return cs! }
        return CGSize(width: dim(p.width, fixedW, minW, idealW, maxW) { child().width },
                      height: dim(p.height, fixedH, minH, idealH, maxH) { child().height })
    }
    override func place(_ r: CGRect) {
        frame = r
        let s = children[0].size(childProposal(_MWProposal(r.size)))
        children[0].place(_mwAlign(CGSize(width: Swift.min(s.width, r.width), height: Swift.min(s.height, r.height)), in: r, alignment))
    }
}

/// .fixedSize(): the child gets its ideal size on the fixed axes
final class _MWFixedSizeNode: _MWNode {
    let h: Bool, v: Bool
    init(_ child: _MWNode, h: Bool, v: Bool) { self.h = h; self.v = v; super.init([child]) }
    private func prop(_ p: _MWProposal) -> _MWProposal { _MWProposal(width: h ? nil : p.width, height: v ? nil : p.height) }
    override func size(_ p: _MWProposal) -> CGSize { children[0].size(prop(p)) }
    override func place(_ r: CGRect) {
        frame = r
        let s = children[0].size(prop(_MWProposal(r.size)))
        children[0].place(_mwAlign(s, in: r, .center))
    }
}

/// .background(_:) / .overlay(_:): the extra views take the main node's size
final class _MWDecorNode: _MWNode {
    let main: _MWNode
    let below: [_MWNode], above: [_MWNode]
    init(_ main: _MWNode, below: [_MWNode], above: [_MWNode], alignment a: Alignment) {
        self.main = main; self.below = below; self.above = above
        super.init(below + [main] + above)
        alignment = a
    }
    override func size(_ p: _MWProposal) -> CGSize { main.size(p) }
    override func place(_ r: CGRect) {
        frame = r
        main.place(r)
        for n in below + above { n.place(_mwAlign(n.size(_MWProposal(r.size)), in: r, alignment)) }
    }
    override var isSpacer: Bool { main.isSpacer }
    override var stackAxis: Axis? { didSet { main.stackAxis = stackAxis } }
}

/// a node that draws with a closure (shapes, colors, images, control chrome)
class _MWDrawNode: _MWNode {
    var ideal: CGSize?            // nil: takes whatever is proposed (shapes, colors)
    var paint: ((CGContext, CGRect) -> Void)?
    init(ideal: CGSize?, paint: ((CGContext, CGRect) -> Void)?) { self.ideal = ideal; self.paint = paint; super.init() }
    override func size(_ p: _MWProposal) -> CGSize {
        if let i = ideal { return i }
        return CGSize(width: _mwFinite(p.width, 10), height: _mwFinite(p.height, 10))
    }
    override func draw(_ g: CGContext) { if !isHidden { paint?(g, frame); super.draw(g) } }
}
func _mwFinite(_ v: CGFloat?, _ d: CGFloat) -> CGFloat { guard let v = v, v.isFinite else { return d }; return v }

/// clicks and drags: buttons, tap gestures, toggles...
class _MWTapNode: _MWNode {
    var onTap: ((Int) -> Void)?      // click count
    var onPress: ((Bool) -> Void)?
    var onDrag: ((CGPoint, CGPoint, Bool) -> Void)?   // start, current, ended
    var requiredCount = 1
    var enabled = true
    var pressed = false
    private var start = CGPoint.zero
    override init(_ child: [_MWNode]) { super.init(child) }
    override var handlesMouse: Bool { enabled }
    override func hit(_ p: CGPoint) -> _MWNode? {
        if isHidden { return nil }
        if onDrag != nil, frame.contains(p) { return self }
        if let h = super.hit(p), h !== self, !(onTap != nil && h is _MWTapNode && (h as! _MWTapNode).onTap == nil) { return h }
        return enabled && frame.contains(p) ? self : nil
    }
    override func mouseDown(_ p: CGPoint, _ e: NSEvent) { pressed = true; start = p; onPress?(true) }
    override func mouseDragged(_ p: CGPoint, _ e: NSEvent) {
        if let d = onDrag { d(start, p, false); return }
        let inside = frame.contains(p)
        if inside != pressed { pressed = inside; onPress?(inside) }
    }
    override func mouseUp(_ p: CGPoint, _ e: NSEvent) {
        if let d = onDrag { d(start, p, true) }
        let was = pressed
        pressed = false; onPress?(false)
        if was && frame.contains(p), e.clickCount >= requiredCount { onTap?(e.clickCount) }
    }
    override var isSpacer: Bool { children.count == 1 && children[0].isSpacer }
}

/// an AppKit view inside the SwiftUI tree (text fields, NSViewRepresentable)
final class _MWAppKitNode: _MWNode {
    let view: NSView
    var sizer: ((_MWProposal) -> CGSize)?
    init(_ v: NSView) { view = v; super.init() }
    override func size(_ p: _MWProposal) -> CGSize {
        if let s = sizer { return s(p) }
        let fit = view.fittingSize
        let ic = view.intrinsicContentSize
        let w = ic.width > 0 ? ic.width : (fit.width > 0 ? fit.width : _mwFinite(p.width, 100))
        let h = ic.height > 0 ? ic.height : (fit.height > 0 ? fit.height : _mwFinite(p.height, 100))
        return CGSize(width: ic.width > 0 ? w : _mwFinite(p.width, w), height: ic.height > 0 ? h : _mwFinite(p.height, h))
    }
    override func place(_ r: CGRect) { frame = r; view.frame = r }
}

// MARK: - the hosting view

final class _MWHostView: NSView {
    final class Weak { weak var host: _MWHostView?; init(_ h: _MWHostView) { host = h } }
    nonisolated(unsafe) static var hosts: [Weak] = []
    static func updateAll() { hosts.removeAll { $0.host == nil }; for h in hosts { h.host?.setNeedsUpdate() } }

    var resolveRoot: ((_MWContext) -> [_MWNode])?
    var root: _MWNode?
    var store: [String: Any] = [:]
    var environment = EnvironmentValues()
    private var observers: [String: (ObjectIdentifier, AnyCancellable)] = [:]
    private var embedded: [String: NSView] = [:]
    private var usedEmbedded = Set<String>()
    private var pending = false
    private var tracking: _MWNode?
    var onSizeChange: ((CGSize) -> Void)?
    private var lastIdeal = CGSize.zero
    /// the animation of the next update (a change made in withAnimation, or through a binding with an animation)
    private var pendingAnimation: Animation?
    /// while an update resolves: its animation (animation(_:value:) and transaction modifiers change it)
    var updateAnimation: Animation?
    private(set) var animator: _MWAnimator?
    private var timer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        _MWHostView.hosts.append(Weak(self))
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func setNeedsUpdate() {
        if let a = _mwCurrentAnimation() { pendingAnimation = a }
        if pending { return }
        pending = true
        DispatchQueue.main.async { [weak self] in self?.update() }
    }
    func update() {
        pending = false
        guard let r = resolveRoot else { return }
        usedEmbedded = []
        updateAnimation = pendingAnimation; pendingAnimation = nil
        let c = _MWContext(host: self, env: environment, path: "")
        let nodes = r(c)
        let old = root
        root = nodes.count == 1 ? nodes[0] : _MWStackNode(.vertical, spacing: nil, cross: .center, nodes)
        for (k, v) in embedded where !usedEmbedded.contains(k) { v.removeFromSuperview(); embedded[k] = nil }
        let anim = updateAnimation
        updateAnimation = nil
        if let a = anim, let old = old, let new = root {   // from what shows now to the new tree
            animator = _MWAnimator(a.timing, old: old, new: new)
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            }
        }
        layoutNodes()
        needsDisplay = true
        let ideal = idealSize
        if _mwDumpUpdates, let r = root { print("-- update \(ideal)\n" + _mwDump(r), terminator: "") }
        if ideal != lastIdeal { lastIdeal = ideal; invalidateIntrinsicContentSize(); onSizeChange?(ideal) }
        _mwApplyTitle(self)
    }
    /// an AppKit view kept across updates at `key`
    func embeddedView<V: NSView>(_ key: String, make: () -> V) -> V {
        usedEmbedded.insert(key)
        if let v = embedded[key] as? V { return v }
        let v = make()
        embedded[key] = v
        addSubview(v)
        return v
    }
    func observe<O: ObservableObject>(_ o: O, key: String) {
        let id = ObjectIdentifier(o)
        if let e = observers[key], e.0 == id { return }
        observers[key] = (id, o.objectWillChange.sink { [weak self] _ in self?.setNeedsUpdate() })
    }
    var idealSize: CGSize { root?.size(.ideal) ?? .zero }
    func sizeThatFits(_ s: CGSize) -> CGSize { root?.size(_MWProposal(s)) ?? .zero }
    private func placeNodes() {
        guard let root = root else { return }
        let s = root.size(_MWProposal(bounds.size))
        root.place(_mwAlign(CGSize(width: min(s.width, bounds.width), height: min(s.height, bounds.height)), in: bounds, .center))
    }
    /// lays the tree out (then puts it where a running animation has it now)
    func layoutNodes() {
        placeNodes()
        if let a = animator, let root = root { a.capture(root); _ = applyAnimation() }
    }
    /// moves the nodes to where the animation has them now; at its end drops it
    private func applyAnimation() -> Bool {
        guard let a = animator, let root = root else { return false }
        if a.apply(root, now: _mwNow()) { return true }
        animator = nil
        timer?.invalidate(); timer = nil
        needsDisplay = true
        return false
    }
    private func tick() {
        if !applyAnimation() { timer?.invalidate(); timer = nil }
        needsDisplay = true
    }
    override var intrinsicContentSize: NSSize { idealSize }
    override var fittingSize: NSSize { idealSize }
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); layoutNodes(); needsDisplay = true }
    override func draw(_ dirty: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext else { return }
        root?.render(g)
        for gh in animator?.ghosts ?? [] { gh.node.render(g) }
    }
    private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }
    override func mouseDown(with e: NSEvent) {
        _MWHostView.current = self
        let p = point(e)
        tracking = root?.hit(p)
        tracking?.mouseDown(p, e)
        needsDisplay = true
    }
    override func mouseDragged(with e: NSEvent) { tracking?.mouseDragged(point(e), e); needsDisplay = true }
    override func mouseUp(with e: NSEvent) {
        let t = tracking
        tracking = nil
        t?.mouseUp(point(e), e)
        needsDisplay = true
    }
    override func scrollWheel(with e: NSEvent) {
        if root?.scroll(point(e), dx: e.scrollingDeltaX, dy: e.scrollingDeltaY) == true { needsDisplay = true } else { super.scrollWheel(with: e) }
    }
    override func keyDown(with e: NSEvent) {
        if _mwPerformShortcut(root, e) { needsDisplay = true } else { super.keyDown(with: e) }
    }
    override func performKeyEquivalent(with e: NSEvent) -> Bool { _mwPerformShortcut(root, e) || super.performKeyEquivalent(with: e) }
}

/// the test report: SCION_SWIFTUI_DUMP=1 prints each host's tree after its first layout
func _mwDump(_ n: _MWNode, _ depth: Int = 0) -> String {
    var s = String(repeating: "  ", count: depth) + "\(type(of: n)) \(Int(n.frame.minX)),\(Int(n.frame.minY)) \(Int(n.frame.width))x\(Int(n.frame.height))"
    func f(_ v: CGFloat) -> String { String(format: "%.2f", Double(v)) }
    if let a = n as? _MWAlphaNode { s += " alpha=" + f(CGFloat(a.alpha)) }
    if let t = n as? _MWTransformNode { s += " rot=" + f(t.angle * 180 / .pi) + " scale=" + f(t.sx) }
    if let x = n.fx { s += " fx=" + f(x.alpha) + "," + f(x.dx) + "," + f(x.dy) + "," + f(x.sx) }
    if let t = n as? _MWTextNode { s += " \"\(t.string.string)\"" }
    s += "\n"
    for c in n.children { s += _mwDump(c, depth + 1) }
    return s
}

// MARK: - test hooks (tests/swift/swiftui.swift)

/// the hosting view's tree after layout, one node per line
@_spi(ScionTest) public func _mwTestDump(_ v: NSView) -> String {
    guard let h = _mwFindHost(v), let r = h.root else { return "" }
    h.layoutNodes()
    var s = _mwDump(r)
    for g in h.animator?.ghosts ?? [] { s += "ghost\n" + _mwDump(g.node, 1) }   // (views going away)
    return s
}
/// clicks the control whose text is `text` (the deepest clickable node around it)
@_spi(ScionTest) public func _mwTestTap(_ v: NSView, _ text: String, index: Int = 0) -> Bool {
    guard let h = _mwFindHost(v), let r = h.root else { return false }
    var found: _MWTapNode?
    func walk(_ n: _MWNode, _ tap: _MWTapNode?) {
        let t = (n as? _MWTapNode) ?? tap
        if found == nil, let tn = n as? _MWTextNode, tn.string.string == text { found = t }
        for c in n.children { walk(c, t) }
    }
    walk(r, nil)
    guard let t = found else { return false }
    if let p = t as? _MWPickerNode, p.kind != 0 { _ = p; return false }
    t.onTap?(1)
    return true
}
/// picks option `index` of the first picker
@_spi(ScionTest) public func _mwTestPick(_ v: NSView, _ index: Int) -> Bool {
    guard let h = _mwFindHost(v), let r = h.root else { return false }
    var picker: _MWPickerNode?
    r.all { if picker == nil, let p = $0 as? _MWPickerNode { picker = p } }
    picker?.choose(index)
    return picker != nil
}
@_spi(ScionTest) public func _mwTestUpdate(_ v: NSView) { _mwFindHost(v)?.update() }
func _mwFindHost(_ v: NSView) -> _MWHostView? {
    if let h = v as? _MWHostView { return h }
    for s in v.subviews { if let h = _mwFindHost(s) { return h } }
    return nil
}

/// SCION_SWIFTUI_DUMP=2: print the node tree after every update
let _mwDumpUpdates = getenv("SCION_SWIFTUI_DUMP").map { String(cString: $0) == "2" } ?? false
/// SCION_SWIFTUI_TRACE=1: every view the engine resolves (its path and type) on stderr
let _mwTraceResolve = getenv("SCION_SWIFTUI_TRACE") != nil
