// APIs of macOS 13-14 (and the few newer ones an Xcode 26 build imports unconditionally): ProposedViewSize, Window,
// LimitedAvailabilityScene (SceneBuilder's `if #available`), LabeledContent, OpenSettingsAction, LazyState.
import Foundation
import AppKit

@frozen public struct ProposedViewSize: Equatable {
    public var width: CGFloat?
    public var height: CGFloat?
    public static let zero = ProposedViewSize(width: 0, height: 0)
    public static let unspecified = ProposedViewSize(width: nil, height: nil)
    public static let infinity = ProposedViewSize(width: .infinity, height: .infinity)
    @inlinable public init(width: CGFloat?, height: CGFloat?) { (self.width, self.height) = (width, height) }
    @inlinable public init(_ size: CGSize) { self.init(width: size.width, height: size.height) }
    @inlinable public func replacingUnspecifiedDimensions(by size: CGSize = CGSize(width: 10, height: 10)) -> CGSize {
        CGSize(width: width ?? size.width, height: height ?? size.height)
    }
}

public enum LayoutDirectionBehavior: Hashable, Sendable {
    case fixed
    case mirrors(in: LayoutDirection)
}

public struct _PlatformViewRepresentableLayoutOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
}

// MARK: - scenes

/// a single window scene; ponytail: not opened at launch (openWindow(id:) is not implemented yet)
public struct Window<Content>: Scene, _MWScene where Content: View {
    let title: String, id: String, content: () -> Content
    public init(_ title: Text, id: String, @ViewBuilder content: () -> Content) { let c = content(); self.title = title._mwPlain; self.id = id; self.content = { c } }
    public init(_ titleKey: LocalizedStringKey, id: String, @ViewBuilder content: () -> Content) { let c = content(); title = Text(titleKey)._mwPlain; self.id = id; self.content = { c } }
    public init<S>(_ title: S, id: String, @ViewBuilder content: () -> Content) where S: StringProtocol { let c = content(); self.title = String(title); self.id = id; self.content = { c } }
    public typealias Body = Never
    public var body: Never { _primitive("Window") }
    func _mwCollect(_ l: _MWSceneList) {}
}

@usableFromInline internal class LimitedAvailabilitySceneStorageBase {
    let collect: (_MWSceneList) -> Void
    init(_ collect: @escaping (_MWSceneList) -> Void) { self.collect = collect }
}
@usableFromInline @frozen internal struct LimitedAvailabilityScene: Scene, _MWScene {
    @usableFromInline internal var storage: LimitedAvailabilitySceneStorageBase
    @usableFromInline internal init<S>(_ scene: S) where S: Scene { storage = LimitedAvailabilitySceneStorageBase { _mwCollectScene(scene, $0) } }
    @usableFromInline internal typealias Body = Never
    @usableFromInline internal var body: Never { _primitive("LimitedAvailabilityScene") }
    func _mwCollect(_ l: _MWSceneList) { storage.collect(l) }
}
extension SceneBuilder {
    @_alwaysEmitIntoClient public static func buildLimitedAvailability(_ scene: some Scene) -> some Scene { LimitedAvailabilityScene(scene) }
}

// MARK: - settings

var _mwSettings: (() -> AnyView)?
weak var _mwSettingsWindow: NSWindow?
func _mwOpenSettings() {
    if let w = _mwSettingsWindow { w.makeKeyAndOrderFront(nil); return }
    guard let s = _mwSettings else { return }
    _mwSettingsWindow = _mwOpenWindow("Settings", hiddenTitleBar: false, s())
}
public struct OpenSettingsAction {
    init() {}
    @MainActor @preconcurrency public func callAsFunction() { _mwOpenSettings() }
}
extension EnvironmentValues {
    public var openSettings: OpenSettingsAction { OpenSettingsAction() }
}

// MARK: - views

public struct LabeledContent<Label, Content> {
    let label: Label, content: Content
}
extension LabeledContent: View where Label: View, Content: View {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) { self.content = content(); self.label = label() }
    public var body: some View { HStack { label; Spacer(); content } }
}
extension LabeledContent where Label == Text, Content: View {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) { self.init(content: content, label: { Text(titleKey) }) }
    public init<S>(_ title: S, @ViewBuilder content: () -> Content) where S: StringProtocol { self.init(content: content, label: { Text(title) }) }
}
extension LabeledContent where Label == Text, Content == Text {
    public init<S>(_ titleKey: LocalizedStringKey, value: S) where S: StringProtocol { self.init(content: { Text(value) }, label: { Text(titleKey) }) }
}

// MARK: - LazyState: a @State whose initial value is computed on first use (Xcode 26 builds use it on every macOS)

@propertyWrapper @frozen public struct LazyState<Value>: DynamicProperty {
    @usableFromInline internal enum Storage {
        case thunk(() -> Value)
        case value(Value)
    }
    @usableFromInline internal var _storage: Storage
    @usableFromInline internal var _location: AnyLocation<Value>?
    public init(wrappedValue: @autoclosure @escaping () -> Value) { _storage = .thunk(wrappedValue); _location = nil }
    var _initial: Value { switch _storage { case .thunk(let f): return f(); case .value(let v): return v } }
    public var wrappedValue: Value {
        get { _location?.get() ?? _initial }
        nonmutating set { _location?.set(newValue, transaction: Transaction()) }
    }
    public var projectedValue: Binding<Value> {
        let loc = _location ?? _MWConstantLocation(_initial)
        return Binding(transaction: Transaction(), location: loc, _value: loc.get())
    }
}
extension LazyState: _MWDynamic {
    mutating func _mwBind(_ c: _MWContext, key: String) {
        if let l = c.host.store[key] as? _MWStoredLocation<Value> { _location = l; return }
        let l = _MWStoredLocation(_initial, host: c.host)
        c.host.store[key] = l
        _location = l
    }
}
