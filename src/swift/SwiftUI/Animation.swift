// Animations and transitions, with the declarations of Apple's SwiftUI.
// An update made in an animation (withAnimation, a binding's transaction, animation(_:value:) seeing its value change)
// starts an animator in the host (_MWAnimator): every node of the new tree whose view was on screen before (the same
// path: _MWNode.id) goes from what was showing (its frame, its opacity, its rotation and scale) to its new place, on
// the animation's curve; a view that appears comes in with its transition, and one that goes away stays drawn (a
// ghost) while its transition takes it out. A timer redraws the host until the animation is over.
// ponytail: an animation covers the whole host (not only the views under animation(_:value:)), and colors, shapes
// and text do not blend (they take their new look at once); CustomAnimation, Transition, Spring and UnitCurve (macOS
// 14) are not declared yet.
import Foundation
import AppKit

// MARK: - timing

/// an animation's curve: a cubic bezier over a duration, or a spring; then delay, speed and repeats
struct _MWTiming: Hashable {
    var isSpring: Bool
    var duration: Double            // a bezier's duration; a spring's settling time
    var p: [Double]                 // bezier: x1, y1, x2, y2; spring: angular frequency, damping ratio, initial velocity
    var delay = 0.0, speed = 1.0
    var repeats = 1                 // 0: forever
    var autoreverses = false
    var name: String

    static func bezier(_ name: String, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ d: Double) -> _MWTiming {
        _MWTiming(isSpring: false, duration: max(0, d), p: [x1, y1, x2, y2], name: name)
    }
    static func spring(_ name: String, omega: Double, zeta: Double, v0: Double = 0) -> _MWTiming {
        guard omega.isFinite, omega > 0 else { return .bezier(name, 0, 0, 1, 1, 0) }
        let z = max(zeta, 0.01)
        // the slowest decay rate: the motion is within 0.1% of its end after ln(1000) / rate
        let rate = z < 1 ? z * omega : (z == 1 ? 0.75 * omega : omega * (z - (z * z - 1).squareRoot()))
        return _MWTiming(isSpring: true, duration: min(10, 6.9 / rate), p: [omega, z, v0], name: name)
    }
    /// the eased progress (0 to 1; a spring overshoots) `elapsed` seconds after the start, and whether it is over
    func progress(_ elapsed: Double) -> (Double, Bool) {
        let e = max(0, elapsed - delay) * speed
        guard duration > 0 else { return (1, elapsed >= delay) }
        let cycle = e / duration
        if repeats > 0 && cycle >= Double(repeats) { return (1, true) }
        let k = cycle.rounded(.down)
        var f = cycle - k
        if autoreverses && Int(k) % 2 == 1 { f = 1 - f }
        return (ease(f), false)
    }
    /// how long it runs (nil: forever)
    var total: Double? { repeats == 0 ? nil : delay + duration * Double(repeats) / max(speed, 0.0001) }
    func ease(_ f: Double) -> Double {
        if isSpring {
            let w = p[0], z = p[1], v0 = p[2], t = f * duration
            let d: Double   // the displacement from the end (-1 at the start)
            if z < 1 {
                let wd = w * (1 - z * z).squareRoot()
                d = (-cos(wd * t) + (v0 - z * w) / wd * sin(wd * t)) * exp(-z * w * t)
            } else if z == 1 {
                d = (-1 + (v0 - w) * t) * exp(-w * t)
            } else {
                let s = (z * z - 1).squareRoot(), r1 = -w * (z - s), r2 = -w * (z + s)
                let c2 = (v0 + r1) / (r2 - r1), c1 = -1 - c2
                d = c1 * exp(r1 * t) + c2 * exp(r2 * t)
            }
            return 1 + d
        }
        let x1 = p[0], y1 = p[1], x2 = p[2], y2 = p[3]
        if x1 == y1 && x2 == y2 { return f }   // linear
        // the bezier's parameter u where x(u) = f (bisection; x grows with u), then y(u)
        func b(_ u: Double, _ a: Double, _ c: Double) -> Double { let v = 1 - u; return 3 * v * v * u * a + 3 * v * u * u * c + u * u * u }
        var lo = 0.0, hi = 1.0, u = f
        for _ in 0..<40 { u = (lo + hi) / 2; if b(u, x1, x2) < f { lo = u } else { hi = u } }
        return b(u, y1, y2)
    }
}

@usableFromInline internal final class AnimationBoxBase: @unchecked Sendable {
    let timing: _MWTiming
    init(_ t: _MWTiming) { timing = t }
}

// MARK: - Animation

@frozen public struct Animation: Equatable, Sendable {
    @usableFromInline internal var box: AnimationBoxBase
    init(_ t: _MWTiming) { box = AnimationBoxBase(t) }
    var timing: _MWTiming { box.timing }
    func with(_ f: (inout _MWTiming) -> Void) -> Animation { var t = timing; f(&t); return Animation(t) }
    public static func == (lhs: Animation, rhs: Animation) -> Bool { lhs.box === rhs.box || lhs.timing == rhs.timing }
}
extension Animation: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(timing) }
}
extension Animation: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "\(timing.name)(duration: \(timing.duration))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["curve": timing.name, "duration": timing.duration]) }
}
extension Animation {
    public static let `default` = Animation.easeInOut(duration: 0.35)
    public static func easeInOut(duration: TimeInterval) -> Animation { Animation(.bezier("easeInOut", 0.42, 0, 0.58, 1, duration)) }
    public static var easeInOut: Animation { easeInOut(duration: 0.35) }
    public static func easeIn(duration: TimeInterval) -> Animation { Animation(.bezier("easeIn", 0.42, 0, 1, 1, duration)) }
    public static var easeIn: Animation { easeIn(duration: 0.35) }
    public static func easeOut(duration: TimeInterval) -> Animation { Animation(.bezier("easeOut", 0, 0, 0.58, 1, duration)) }
    public static var easeOut: Animation { easeOut(duration: 0.35) }
    public static func linear(duration: TimeInterval) -> Animation { Animation(.bezier("linear", 0, 0, 1, 1, duration)) }
    public static var linear: Animation { linear(duration: 0.35) }
    public static func timingCurve(_ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double, duration: TimeInterval = 0.35) -> Animation {
        Animation(.bezier("timingCurve", p1x, p1y, p2x, p2y, duration))
    }
}
extension Animation {
    public static func interpolatingSpring(mass: Double = 1.0, stiffness: Double, damping: Double, initialVelocity: Double = 0.0) -> Animation {
        let m = max(mass, 0.0001), k = max(stiffness, 0.0001)
        return Animation(.spring("interpolatingSpring", omega: (k / m).squareRoot(), zeta: damping / (2 * (k * m).squareRoot()), v0: initialVelocity))
    }
    @_alwaysEmitIntoClient public static func interpolatingSpring(duration: TimeInterval = 0.5, bounce: Double = 0.0, initialVelocity: Double = 0.0) -> Animation {
        let stiffness = springStiffness(response: duration)
        let fraction = springDampingFraction(bounce: bounce)
        let damping = springDamping(fraction: fraction, stiffness: stiffness)
        return interpolatingSpring(stiffness: stiffness, damping: damping, initialVelocity: initialVelocity)
    }
    @_alwaysEmitIntoClient public static var interpolatingSpring: Animation { .interpolatingSpring() }
}
extension Animation {
    @_alwaysEmitIntoClient public static func spring(duration: TimeInterval = 0.5, bounce: Double = 0.0, blendDuration: Double = 0) -> Animation {
        spring(response: duration, dampingFraction: springDampingFraction(bounce: bounce), blendDuration: blendDuration)
    }
    @_disfavoredOverload public static func spring(response: Double = 0.5, dampingFraction: Double = 0.825, blendDuration: TimeInterval = 0) -> Animation {
        Animation(.spring("spring", omega: response > 0 ? 2 * .pi / response : .infinity, zeta: dampingFraction))
    }
    @_alwaysEmitIntoClient public static var spring: Animation { spring() }
    @_disfavoredOverload public static func interactiveSpring(response: Double = 0.15, dampingFraction: Double = 0.86, blendDuration: TimeInterval = 0.25) -> Animation {
        spring(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
    }
    @_alwaysEmitIntoClient public static var interactiveSpring: Animation { interactiveSpring() }
    @_alwaysEmitIntoClient public static func interactiveSpring(duration: TimeInterval = 0.15, extraBounce: Double = 0.0, blendDuration: TimeInterval = 0.25) -> Animation {
        spring(duration: duration, bounce: 0.15 + extraBounce, blendDuration: blendDuration)
    }
    @_alwaysEmitIntoClient public static var smooth: Animation { smooth() }
    @_alwaysEmitIntoClient public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation {
        spring(duration: duration, bounce: extraBounce)
    }
    @_alwaysEmitIntoClient public static var snappy: Animation { snappy() }
    @_alwaysEmitIntoClient public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation {
        spring(duration: duration, bounce: 0.15 + extraBounce)
    }
    @_alwaysEmitIntoClient public static var bouncy: Animation { bouncy() }
    @_alwaysEmitIntoClient public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation {
        spring(duration: duration, bounce: 0.3 + extraBounce)
    }
}
@_alwaysEmitIntoClient internal func springStiffness(response: Double) -> Double {
    if response <= 0 { return .infinity } else { let freq = (2.0 * Double.pi) / response; return freq * freq }
}
@_alwaysEmitIntoClient internal func springDamping(fraction: Double, stiffness: Double) -> Double {
    let criticalDamping = 2 * stiffness.squareRoot()
    return criticalDamping * fraction
}
@_alwaysEmitIntoClient internal func springDampingFraction(bounce: Double) -> Double {
    (bounce < 0.0) ? 1.0 / (bounce + 1.0) : 1.0 - bounce
}
extension Animation {
    public func delay(_ delay: TimeInterval) -> Animation { with { $0.delay += delay } }
    public func speed(_ speed: Double) -> Animation { with { $0.speed *= speed } }
    public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation { with { $0.repeats = max(1, repeatCount); $0.autoreverses = autoreverses } }
    public func repeatForever(autoreverses: Bool = true) -> Animation { with { $0.repeats = 0; $0.autoreverses = autoreverses } }
    public func logicallyComplete(after duration: TimeInterval) -> Animation { self }
}

// MARK: - transactions

public struct AnimationCompletionCriteria: Hashable, Sendable {
    let r: Bool
    public static let logicallyComplete = AnimationCompletionCriteria(r: false)
    public static let removed = AnimationCompletionCriteria(r: true)
}
/// the transactions of the withTransaction / withAnimation calls running now (innermost last)
nonisolated(unsafe) var _mwTransactions: [Transaction] = []
/// the animation of a change made now
func _mwCurrentAnimation() -> Animation? {
    for t in _mwTransactions.reversed() {
        if t.disablesAnimations { return nil }
        if let a = t.animation { return a }
    }
    return nil
}
public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
    _mwTransactions.append(transaction)
    defer { _mwTransactions.removeLast() }
    return try body()
}
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    var t = Transaction(animation: animation)
    if animation == nil { t.disablesAnimations = true }   // (no animation, even inside an outer one)
    return try withTransaction(t, body)
}
public func withAnimation<Result>(_ animation: Animation? = .default, completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
                                  _ body: () throws -> Result, completion: @escaping () -> Void) rethrows -> Result {
    let r = try withAnimation(animation, body)
    // ponytail: the completion runs when the animation's time is up, whether or not anything changed
    let wait: Double? = animation == nil ? 0 : animation!.timing.total
    if let w = wait { DispatchQueue.main.asyncAfter(deadline: .now() + w) { completion() } }
    return r
}

/// transaction(_:): changes made under it (in this host) get the transaction's animation
@frozen public struct _TransactionModifier: ViewModifier {
    public var transform: (inout Transaction) -> Void
    @inlinable public init(transform: @escaping (inout Transaction) -> Void) { self.transform = transform }
    public typealias Body = Never
}
extension _TransactionModifier: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        var t = Transaction(animation: c.host.updateAnimation)
        transform(&t)
        c.host.updateAnimation = t.disablesAnimations ? nil : t.animation
        return content(c)
    }
}
@frozen public struct _ValueTransactionModifier<Value>: ViewModifier where Value: Equatable {
    public var value: Value
    public var transform: (inout Transaction) -> Void
    @inlinable public init(value: Value, transform: @escaping (inout Transaction) -> Void) { self.value = value; self.transform = transform }
    public typealias Body = Never
}
extension _ValueTransactionModifier: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        if c.host.valueChanged(c.path + "#txv", value) {
            var t = Transaction(animation: c.host.updateAnimation)
            transform(&t)
            c.host.updateAnimation = t.disablesAnimations ? nil : t.animation
        }
        return content(c)
    }
}
extension View {
    @inlinable public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some View {
        modifier(_TransactionModifier(transform: transform))
    }
    @_alwaysEmitIntoClient public func transaction(value: some Equatable, _ transform: @escaping (inout Transaction) -> Void) -> some View {
        modifier(_ValueTransactionModifier(value: value, transform: transform))
    }
    @_disfavoredOverload @inlinable public func animation(_ animation: Animation?) -> some View {
        transaction { t in if !t.disablesAnimations { t.animation = animation } }
    }
}

// MARK: - animation(_:value:)

@frozen public struct _AnimationModifier<Value>: ViewModifier where Value: Equatable {
    public var animation: Animation?
    public var value: Value
    @inlinable public init(animation: Animation?, value: Value) { self.animation = animation; self.value = value }
    public typealias Body = Never
}
extension _AnimationModifier: Equatable {
    public static func == (a: _AnimationModifier<Value>, b: _AnimationModifier<Value>) -> Bool { a.animation == b.animation && a.value == b.value }
}
extension _AnimationModifier: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        if c.host.valueChanged(c.path + "#anim", value), let a = animation { c.host.updateAnimation = a }
        return content(c)
    }
}
@frozen public struct _AnimationView<Content>: View where Content: Equatable, Content: View {
    public var content: Content
    public var animation: Animation?
    @inlinable public init(content: Content, animation: Animation?) { self.content = content; self.animation = animation }
    public typealias Body = Never
    public var body: Never { _primitive("_AnimationView") }
}
extension _AnimationView: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        if c.host.valueChanged(c.path + "#anim", content), let a = animation { c.host.updateAnimation = a }
        return _mwResolve(content, c.child("av"))
    }
}
extension View {
    @inlinable public func animation<V>(_ animation: Animation?, value: V) -> some View where V: Equatable {
        modifier(_AnimationModifier(animation: animation, value: value))
    }
}
extension View where Self: Equatable {
    @inlinable public func animation(_ animation: Animation?) -> some View { _AnimationView(content: self, animation: animation) }
}

// MARK: - rotation and scale

@frozen public struct _RotationEffect: ViewModifier, Equatable {
    public var angle: Angle
    public var anchor: UnitPoint
    @inlinable public init(angle: Angle, anchor: UnitPoint = .center) { self.angle = angle; self.anchor = anchor }
    public typealias Body = Never
}
@frozen public struct _ScaleEffect: ViewModifier, Equatable {
    public var scale: CGSize
    public var anchor: UnitPoint
    @inlinable public init(scale: CGSize, anchor: UnitPoint = .center) { self.scale = scale; self.anchor = anchor }
    public typealias Body = Never
}
extension _RotationEffect: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        content(c).map { _MWTransformNode($0, angle: CGFloat(angle.radians), scale: CGSize(width: 1, height: 1), anchor: anchor) }
    }
}
extension _ScaleEffect: _MWModifier {
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        content(c).map { _MWTransformNode($0, angle: 0, scale: scale, anchor: anchor) }
    }
}
extension View {
    @inlinable public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View {
        modifier(_RotationEffect(angle: angle, anchor: anchor))
    }
    @inlinable public func scaleEffect(_ scale: CGSize, anchor: UnitPoint = .center) -> some View {
        modifier(_ScaleEffect(scale: scale, anchor: anchor))
    }
    @inlinable public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> some View {
        scaleEffect(CGSize(width: s, height: s), anchor: anchor)
    }
    @inlinable public func scaleEffect(x: CGFloat = 1.0, y: CGFloat = 1.0, anchor: UnitPoint = .center) -> some View {
        scaleEffect(CGSize(width: x, height: y), anchor: anchor)
    }
}
/// rotationEffect / scaleEffect: draws its content turned and scaled about the anchor (its layout is the content's)
final class _MWTransformNode: _MWNode, _MWAnimatableNode {
    var angle: CGFloat, sx: CGFloat, sy: CGFloat
    let anchor: UnitPoint
    init(_ n: _MWNode, angle: CGFloat, scale: CGSize, anchor: UnitPoint) {
        self.angle = angle; sx = scale.width; sy = scale.height; self.anchor = anchor
        super.init([n])
    }
    var animValues: [CGFloat] { get { [angle, sx, sy] } set { angle = newValue[0]; sx = newValue[1]; sy = newValue[2] } }
    override func size(_ p: _MWProposal) -> CGSize { children[0].size(p) }
    override func place(_ r: CGRect) { frame = r; children[0].place(r) }
    override func draw(_ g: CGContext) {
        if angle == 0 && sx == 1 && sy == 1 { super.draw(g); return }
        let ax = frame.minX + anchor.x * frame.width, ay = frame.minY + anchor.y * frame.height
        CGContextSaveGState(g)
        CGContextTranslateCTM(g, ax, ay); CGContextRotateCTM(g, angle); CGContextScaleCTM(g, sx, sy); CGContextTranslateCTM(g, -ax, -ay)
        super.draw(g)
        CGContextRestoreGState(g)
    }
    override var isSpacer: Bool { children[0].isSpacer }
}

// MARK: - transitions

/// one effect of a transition, at full strength
enum _MWFx {
    case opacity
    case scale(CGFloat, UnitPoint)
    case offset(CGSize)
    case move(Edge)
}
/// how a transitioning node is drawn: faded, moved and scaled about an anchor
struct _MWFxState {
    var alpha: CGFloat = 1, dx: CGFloat = 0, dy: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1
    var anchor = UnitPoint.center
    /// the effects at strength `a` (0: none, 1: full) for a node in `frame`
    init(_ fx: [_MWFx], _ a: CGFloat, _ frame: CGRect) {
        for f in fx {
            switch f {
            case .opacity: alpha *= 1 - a
            case .scale(let s, let p): sx *= 1 + (s - 1) * a; sy *= 1 + (s - 1) * a; anchor = p
            case .offset(let d): dx += d.width * a; dy += d.height * a
            case .move(let e):
                switch e {
                case .leading: dx -= frame.width * a
                case .trailing: dx += frame.width * a
                case .top: dy -= frame.height * a
                case .bottom: dy += frame.height * a
                }
            }
        }
    }
}

@frozen public struct AnyTransition {
    @usableFromInline internal let box: AnyTransitionBox
    init(_ insertion: [_MWFx], _ removal: [_MWFx]) { box = AnyTransitionBox(insertion, removal) }
    var insertion: [_MWFx] { box.insertion }
    var removal: [_MWFx] { box.removal }
    public static let identity = AnyTransition([], [])
    public static let opacity = AnyTransition([.opacity], [.opacity])
    public static var slide: AnyTransition { AnyTransition([.move(.leading)], [.move(.trailing)]) }
    public static var scale: AnyTransition { scale(scale: 0) }
    public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition {
        AnyTransition([.scale(scale, anchor)], [.scale(scale, anchor)])
    }
    public static func offset(_ offset: CGSize) -> AnyTransition { AnyTransition([.offset(offset)], [.offset(offset)]) }
    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition { offset(CGSize(width: x, height: y)) }
    public static func move(edge: Edge) -> AnyTransition { AnyTransition([.move(edge)], [.move(edge)]) }
    public static func push(from edge: Edge) -> AnyTransition {
        let opposite: [Edge: Edge] = [.top: .bottom, .bottom: .top, .leading: .trailing, .trailing: .leading]
        return AnyTransition([.move(edge), .opacity], [.move(opposite[edge] ?? edge), .opacity])
    }
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition(insertion.insertion, removal.removal)
    }
    public func combined(with other: AnyTransition) -> AnyTransition {
        AnyTransition(insertion + other.insertion, removal + other.removal)
    }
    /// ponytail: a transition's own animation is not used (it goes with the update's)
    public func animation(_ animation: Animation?) -> AnyTransition { self }
    /// ponytail: the modifiers are not applied; the view fades
    public static func modifier<E>(active: E, identity: E) -> AnyTransition where E: ViewModifier { .opacity }
    public static func blur(radius: CGFloat) -> AnyTransition { .opacity }
}
@usableFromInline internal final class AnyTransitionBox {
    let insertion: [_MWFx], removal: [_MWFx]
    init(_ i: [_MWFx], _ r: [_MWFx]) { insertion = i; removal = r }
}
/// the transition set on a node (or the one view it wraps); views fade by default
func _mwTransition(_ n: _MWNode) -> AnyTransition {
    var m: _MWNode? = n
    while let x = m {
        if let t = x.traits[String(describing: TransitionTraitKey.self)] as? AnyTransition { return t }
        m = x.children.count == 1 ? x.children[0] : nil
    }
    return .opacity
}

// MARK: - the animator

/// a node's animated values: its frame, and its own (opacity, rotation and scale)
struct _MWAnimValues {
    var frame: CGRect
    var extra: [CGFloat]
    init(_ n: _MWNode) { frame = n.frame; extra = (n as? _MWAnimatableNode)?.animValues ?? [] }
    func apply(_ n: _MWNode) {
        n.frame = frame
        if !extra.isEmpty, let a = n as? _MWAnimatableNode { a.animValues = extra }
    }
    static func mix(_ a: _MWAnimValues, _ b: _MWAnimValues, _ p: CGFloat) -> _MWAnimValues {
        func m(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * p }
        var r = b
        r.frame = CGRect(x: m(a.frame.minX, b.frame.minX), y: m(a.frame.minY, b.frame.minY),
                         width: max(0, m(a.frame.width, b.frame.width)), height: max(0, m(a.frame.height, b.frame.height)))
        if a.extra.count == b.extra.count { r.extra = zip(a.extra, b.extra).map { m($0, $1) } }
        return r
    }
}
/// nodes with values of their own that animate
protocol _MWAnimatableNode: AnyObject {
    var animValues: [CGFloat] { get set }
}

/// the clock (seconds); tests can stop it
nonisolated(unsafe) var _mwClockOverride: Double?
func _mwNow() -> Double { _mwClockOverride ?? Date().timeIntervalSinceReferenceDate }

final class _MWAnimator {
    let timing: _MWTiming
    let start: Double
    /// what was showing, by view (node id)
    let from: [String: _MWAnimValues]
    /// views that appear (by id) with their insertion effects
    let inserted: [String: [_MWFx]]
    /// views that went away, drawn on top while their removal effects take them out
    let ghosts: [(node: _MWNode, fx: [_MWFx])]
    /// where the nodes of the current tree end up (after each layout)
    var targets: [ObjectIdentifier: _MWAnimValues] = [:]

    /// an animation from the tree `old` (as it shows now) to `new` (laid out)
    init(_ timing: _MWTiming, old: _MWNode, new: _MWNode) {
        self.timing = timing
        start = _mwNow()
        var from: [String: _MWAnimValues] = [:]
        old.all { n in if let id = n.id, from[id] == nil { from[id] = _MWAnimValues(n) } }
        var ids = Set<String>()
        new.all { n in if let id = n.id { ids.insert(id) } }
        var ghosts: [(node: _MWNode, fx: [_MWFx])] = []
        func gone(_ n: _MWNode) {
            if let id = n.id, !ids.contains(id) { n.fx = nil; ghosts.append((n, _mwTransition(n).removal)); return }
            n.children.forEach(gone)
        }
        gone(old)
        var inserted: [String: [_MWFx]] = [:]
        func came(_ n: _MWNode) {
            if let id = n.id, from[id] == nil { inserted[id] = _mwTransition(n).insertion; return }
            n.children.forEach(came)
        }
        came(new)
        self.from = from; self.ghosts = ghosts; self.inserted = inserted
    }
    /// after a layout of `root`: its nodes' places are where they go
    func capture(_ root: _MWNode) {
        targets = [:]
        root.all { targets[ObjectIdentifier($0)] = _MWAnimValues($0) }
    }
    /// puts the nodes of `root` where they are at `now`; false once the animation is over (everything at its place)
    func apply(_ root: _MWNode, now: Double) -> Bool {
        let (v, done) = timing.progress(now - start)
        let p = CGFloat(done ? 1 : v)
        root.all { n in
            guard let to = targets[ObjectIdentifier(n)] else { return }
            if let id = n.id, let f = from[id] { _MWAnimValues.mix(f, to, p).apply(n) } else { to.apply(n) }
            if let id = n.id, let fx = inserted[id] { n.fx = done ? nil : _MWFxState(fx, 1 - p, n.frame) }
        }
        for g in ghosts { g.node.fx = _MWFxState(g.fx, done ? 1 : p, g.node.frame) }
        return !done
    }
}

extension _MWHostView {
    /// the value of an animation(_:value:) (and the like) at `key`, kept for the next update: whether it changed
    func valueChanged<V: Equatable>(_ key: String, _ value: V) -> Bool {
        defer { store[key] = value }
        guard let old = store[key] as? V else { return false }
        return old != value
    }
}

// MARK: - test hooks (tests/swift/animation.swift)

/// stops the animations' clock at `t` seconds (nil: the real clock again)
@_spi(ScionTest) public func _mwTestAnimationTime(_ t: Double?) { _mwClockOverride = t }
