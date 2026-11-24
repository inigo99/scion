// State, bindings, observed objects and the environment. Before a view's body is evaluated the engine binds its
// dynamic properties in place (_MWDynamic below): @State gets its storage from the host, @Environment its value, ...
// Layouts of the @frozen types follow Apple's (apps' inlined code builds them directly).
import Foundation
import Combine
import AppKit

// MARK: - locations

@usableFromInline internal class AnyLocationBase {
    init() {}
}
@usableFromInline internal class AnyLocation<Value>: AnyLocationBase {
    func get() -> Value { fatalError() }
    func set(_ value: Value, transaction: Transaction) {}
    override init() {}
}
/// the storage of one @State (or StateObject) in a host
final class _MWStoredLocation<Value>: AnyLocation<Value> {
    var value: Value
    weak var host: _MWHostView?
    init(_ v: Value, host: _MWHostView?) { value = v; self.host = host }
    override func get() -> Value { value }
    override func set(_ v: Value, transaction: Transaction) { value = v; host?.setNeedsUpdate() }
}
final class _MWFunctionLocation<Value>: AnyLocation<Value> {
    let getter: () -> Value, setter: (Value, Transaction) -> Void
    init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) { getter = get; setter = set }
    override func get() -> Value { getter() }
    override func set(_ v: Value, transaction: Transaction) { setter(v, transaction) }
}
final class _MWConstantLocation<Value>: AnyLocation<Value> {
    let value: Value
    init(_ v: Value) { value = v }
    override func get() -> Value { value }
}

@usableFromInline @frozen internal struct PropertyList {
    @usableFromInline internal var elements: _MWPropertyListElement?
    @usableFromInline init() { elements = nil }
}
@usableFromInline internal final class _MWPropertyListElement {
    var animation: Animation?
    init(_ a: Animation?) { animation = a }
}

@frozen public struct Transaction {
    @usableFromInline internal var plist: PropertyList
    @inlinable public init() { plist = PropertyList() }
    public init(animation: Animation?) { plist = PropertyList(); plist.elements = _MWPropertyListElement(animation) }
    public var animation: Animation? {
        get { plist.elements?.animation }
        set { plist.elements = _MWPropertyListElement(newValue) }
    }
    public var disablesAnimations: Bool { get { false } set {} }
}
public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result { try body() }
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result { try body() }

// MARK: - the engine's hook

protocol _MWDynamic {
    /// bind this property for the view at `key` in host `c.host` before its body runs
    mutating func _mwBind(_ c: _MWContext, key: String)
}

// MARK: - State

@frozen @propertyWrapper public struct State<Value>: DynamicProperty {
    @usableFromInline internal var _value: Value
    @usableFromInline internal var _location: AnyLocation<Value>?
    public init(wrappedValue value: Value) { _value = value; _location = nil }
    public init(initialValue value: Value) { _value = value; _location = nil }
    public var wrappedValue: Value {
        get { _location?.get() ?? _value }
        nonmutating set { _location?.set(newValue, transaction: Transaction()) }
    }
    public var projectedValue: Binding<Value> {
        let loc = _location ?? _MWConstantLocation(_value)
        return Binding(transaction: Transaction(), location: loc, _value: loc.get())
    }
}
extension State where Value: ExpressibleByNilLiteral {
    @inlinable public init() { self.init(wrappedValue: nil) }
}
extension State: _MWDynamic {
    mutating func _mwBind(_ c: _MWContext, key: String) {
        if let l = c.host.store[key] as? _MWStoredLocation<Value> { _location = l; return }
        let l = _MWStoredLocation(_value, host: c.host)
        c.host.store[key] = l
        _location = l
    }
}

// MARK: - Binding

@frozen @propertyWrapper @dynamicMemberLookup public struct Binding<Value> {
    public var transaction: Transaction
    @usableFromInline internal var location: AnyLocation<Value>
    @usableFromInline internal var _value: Value
    init(transaction: Transaction, location: AnyLocation<Value>, _value: Value) {
        self.transaction = transaction; self.location = location; self._value = _value
    }
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        let l = _MWFunctionLocation(get: get, set: { v, _ in set(v) })
        self.init(transaction: Transaction(), location: l, _value: get())
    }
    public init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) {
        let l = _MWFunctionLocation(get: get, set: set)
        self.init(transaction: Transaction(), location: l, _value: get())
    }
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(transaction: Transaction(), location: _MWConstantLocation(value), _value: value)
    }
    public var wrappedValue: Value {
        get { location.get() }
        nonmutating set { location.set(newValue, transaction: transaction) }
    }
    public var projectedValue: Binding<Value> { self }
    public init(projectedValue: Binding<Value>) { self = projectedValue }
    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        let l = location
        return Binding<Subject>(get: { l.get()[keyPath: keyPath] }, set: { v, t in var whole = l.get(); whole[keyPath: keyPath] = v; l.set(whole, transaction: t) })
    }
    public func transaction(_ transaction: Transaction) -> Binding<Value> { var b = self; b.transaction = transaction; return b }
    public func animation(_ animation: Animation? = .default) -> Binding<Value> { self }
}
extension Binding {
    public init<V>(_ base: Binding<V>) where Value == V? {
        self.init(get: { base.wrappedValue }, set: { if let v = $0 { base.wrappedValue = v } })
    }
    public init?(_ base: Binding<Value?>) {
        guard base.wrappedValue != nil else { return nil }
        self.init(get: { base.wrappedValue! }, set: { base.wrappedValue = $0 })
    }
    public init<V>(_ base: Binding<V>) where Value == AnyHashable, V: Hashable {
        self.init(get: { AnyHashable(base.wrappedValue) }, set: { if let v = $0.base as? V { base.wrappedValue = v } })
    }
}
extension Binding: DynamicProperty {}
extension Binding: Identifiable where Value: Identifiable {
    public var id: Value.ID { wrappedValue.id }
}

// MARK: - observable objects

@propertyWrapper @frozen public struct ObservedObject<ObjectType>: DynamicProperty where ObjectType: ObservableObject {
    @dynamicMemberLookup @frozen public struct Wrapper {
        let root: ObjectType
        public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
            let r = root
            return Binding(get: { r[keyPath: keyPath] }, set: { r[keyPath: keyPath] = $0 })
        }
    }
    @usableFromInline internal var _seed = 0
    public var wrappedValue: ObjectType
    public init(initialValue: ObjectType) { wrappedValue = initialValue }
    public init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { Wrapper(root: wrappedValue) }
}
extension ObservedObject: _MWDynamic {
    mutating func _mwBind(_ c: _MWContext, key: String) { c.host.observe(wrappedValue, key: key) }
}

@frozen @propertyWrapper public struct StateObject<ObjectType>: DynamicProperty where ObjectType: ObservableObject {
    @usableFromInline @frozen internal enum Storage {
        case initially(() -> ObjectType)
        case object(ObservedObject<ObjectType>)
    }
    @usableFromInline internal var storage: StateObject<ObjectType>.Storage
    @inlinable public init(wrappedValue thunk: @autoclosure @escaping () -> ObjectType) { storage = .initially(thunk) }
    public var wrappedValue: ObjectType {
        switch storage {
        case .object(let o): return o.wrappedValue
        case .initially(let f): return f()   // not bound to a view (Apple warns and makes a new object too)
        }
    }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { ObservedObject(wrappedValue: wrappedValue).projectedValue }
}
extension StateObject: _MWDynamic {
    mutating func _mwBind(_ c: _MWContext, key: String) {
        let obj: ObjectType
        if let o = c.host.store[key] as? ObjectType { obj = o } else {
            switch storage { case .object(let o): obj = o.wrappedValue; case .initially(let f): obj = f() }
            c.host.store[key] = obj
        }
        storage = .object(ObservedObject(wrappedValue: obj))
        c.host.observe(obj, key: key)
    }
}

@frozen @propertyWrapper public struct EnvironmentObject<ObjectType>: DynamicProperty where ObjectType: ObservableObject {
    @dynamicMemberLookup @frozen public struct Wrapper {
        let root: ObjectType
        public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
            let r = root
            return Binding(get: { r[keyPath: keyPath] }, set: { r[keyPath: keyPath] = $0 })
        }
    }
    @usableFromInline internal var _store: ObjectType?
    @usableFromInline internal var _seed: Int = 0
    public init() {}
    @inlinable public var wrappedValue: ObjectType {
        guard let store = _store else { error() }
        return store
    }
    public var projectedValue: EnvironmentObject<ObjectType>.Wrapper { Wrapper(root: wrappedValue) }
    @usableFromInline internal func error() -> Never {
        fatalError("No ObservableObject of type \(ObjectType.self) found. A View.environmentObject(_:) for \(ObjectType.self) may be missing as an ancestor of this view.")
    }
}
extension EnvironmentObject: _MWDynamic {
    mutating func _mwBind(_ c: _MWContext, key: String) {
        _store = c.env.objects[ObjectIdentifier(ObjectType.self)] as? ObjectType
        if let o = _store { c.host.observe(o, key: key) }
    }
}
extension ObservableObject {
    /// where `.environmentObject(_:)` keeps this type's object
    public static var environmentStore: WritableKeyPath<EnvironmentValues, Self?> { \EnvironmentValues[_mwObject: ObjectIdentifier(Self.self)] }
}
extension EnvironmentValues {
    subscript<T>(_mwObject id: ObjectIdentifier) -> T? {
        get { objects[id] as? T }
        set { objects[id] = newValue.map { $0 as AnyObject } }
    }
}
extension View {
    @inlinable public func environmentObject<T>(_ object: T) -> some View where T: ObservableObject {
        environment(T.environmentStore, object)
    }
}

// MARK: - environment

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
    static func _valuesEqual(_ lhs: Self.Value, _ rhs: Self.Value) -> Bool
}
extension EnvironmentKey {
    public static func _valuesEqual(_ lhs: Self.Value, _ rhs: Self.Value) -> Bool { false }
}
extension EnvironmentKey where Self.Value: Equatable {
    public static func _valuesEqual(_ lhs: Self.Value, _ rhs: Self.Value) -> Bool { lhs == rhs }
}

public struct EnvironmentValues: CustomStringConvertible {
    var values: [ObjectIdentifier: Any] = [:]
    var objects: [ObjectIdentifier: AnyObject] = [:]
    public init() {}
    public subscript<K>(key: K.Type) -> K.Value where K: EnvironmentKey {
        get { values[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
        set { values[ObjectIdentifier(key)] = newValue }
    }
    public var description: String { "EnvironmentValues(\(values.count))" }
}

@frozen @propertyWrapper public struct Environment<Value>: DynamicProperty {
    @usableFromInline @frozen internal enum Content {
        case keyPath(KeyPath<EnvironmentValues, Value>)
        case value(Value)
    }
    @usableFromInline internal var content: Environment<Value>.Content
    @inlinable public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { content = .keyPath(keyPath) }
    @inlinable public var wrappedValue: Value {
        switch content {
        case let .value(value): return value
        case let .keyPath(keyPath): return EnvironmentValues()[keyPath: keyPath]
        }
    }
}
extension Environment: _MWDynamic {
    mutating func _mwBind(_ c: _MWContext, key: String) {
        if case .keyPath(let kp) = content { content = .value(c.env[keyPath: kp]) }
    }
}

extension View {
    @inlinable public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        modifier(_EnvironmentKeyWritingModifier(keyPath: keyPath, value: value))
    }
    @inlinable public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, transform: @escaping (inout V) -> Void) -> some View {
        modifier(_EnvironmentKeyTransformModifier(keyPath: keyPath, transform: transform))
    }
}
@frozen public struct _EnvironmentKeyWritingModifier<Value>: ViewModifier {
    public var keyPath: WritableKeyPath<EnvironmentValues, Value>
    public var value: Value
    @inlinable public init(keyPath: WritableKeyPath<EnvironmentValues, Value>, value: Value) { self.keyPath = keyPath; self.value = value }
    public typealias Body = Never
}
@frozen public struct _EnvironmentKeyTransformModifier<Value>: ViewModifier {
    public var keyPath: WritableKeyPath<EnvironmentValues, Value>
    public var transform: (inout Value) -> Void
    @inlinable public init(keyPath: WritableKeyPath<EnvironmentValues, Value>, transform: @escaping (inout Value) -> Void) { self.keyPath = keyPath; self.transform = transform }
    public typealias Body = Never
}

// the environment values apps read and write
struct _MWKey<T>: EnvironmentKey {
    static var defaultValue: T? { nil }
}
private struct _FontKey: EnvironmentKey { static var defaultValue: Font? { nil } }
private struct _ForegroundColorKey: EnvironmentKey { static var defaultValue: Color? { nil } }
private struct _IsEnabledKey: EnvironmentKey { static var defaultValue: Bool { true } }
private struct _LineLimitKey: EnvironmentKey { static var defaultValue: Int? { nil } }
private struct _ControlSizeKey: EnvironmentKey { static var defaultValue: ControlSize { .regular } }
private struct _TruncationKey: EnvironmentKey { static var defaultValue: Text.TruncationMode { .tail } }
private struct _MultilineKey: EnvironmentKey { static var defaultValue: TextAlignment { .leading } }
private struct _ColorSchemeKey: EnvironmentKey { static var defaultValue: ColorScheme { .dark } }
private struct _LocaleKey: EnvironmentKey { static var defaultValue: Locale { .current } }
private struct _CalendarKey: EnvironmentKey { static var defaultValue: Calendar { .current } }
private struct _TimeZoneKey: EnvironmentKey { static var defaultValue: TimeZone { .current } }
private struct _LayoutDirectionKey: EnvironmentKey { static var defaultValue: LayoutDirection { .leftToRight } }
private struct _PresentationKey: EnvironmentKey { static var defaultValue: Binding<PresentationMode> { .constant(PresentationMode()) } }
private struct _DismissKey: EnvironmentKey { static var defaultValue: DismissAction { DismissAction(action: {}) } }
private struct _OpenURLKey: EnvironmentKey { static var defaultValue: OpenURLAction { OpenURLAction(handler: { NSWorkspace.shared.open($0); return .handled }) } }
private struct _ScenePhaseKey: EnvironmentKey { static var defaultValue: ScenePhase { .active } }

extension EnvironmentValues {
    public var font: Font? { get { self[_FontKey.self] } set { self[_FontKey.self] = newValue } }
    public var foregroundColor: Color? { get { self[_ForegroundColorKey.self] } set { self[_ForegroundColorKey.self] = newValue } }
    public var isEnabled: Bool { get { self[_IsEnabledKey.self] } set { self[_IsEnabledKey.self] = newValue } }
    public var lineLimit: Int? { get { self[_LineLimitKey.self] } set { self[_LineLimitKey.self] = newValue } }
    public var controlSize: ControlSize { get { self[_ControlSizeKey.self] } set { self[_ControlSizeKey.self] = newValue } }
    public var truncationMode: Text.TruncationMode { get { self[_TruncationKey.self] } set { self[_TruncationKey.self] = newValue } }
    public var multilineTextAlignment: TextAlignment { get { self[_MultilineKey.self] } set { self[_MultilineKey.self] = newValue } }
    public var colorScheme: ColorScheme { get { self[_ColorSchemeKey.self] } set { self[_ColorSchemeKey.self] = newValue } }
    public var locale: Locale { get { self[_LocaleKey.self] } set { self[_LocaleKey.self] = newValue } }
    public var calendar: Calendar { get { self[_CalendarKey.self] } set { self[_CalendarKey.self] = newValue } }
    public var timeZone: TimeZone { get { self[_TimeZoneKey.self] } set { self[_TimeZoneKey.self] = newValue } }
    public var layoutDirection: LayoutDirection { get { self[_LayoutDirectionKey.self] } set { self[_LayoutDirectionKey.self] = newValue } }
    public var presentationMode: Binding<PresentationMode> { get { self[_PresentationKey.self] } set { self[_PresentationKey.self] = newValue } }
    public var dismiss: DismissAction { get { self[_DismissKey.self] } set { self[_DismissKey.self] = newValue } }
    public var openURL: OpenURLAction { get { self[_OpenURLKey.self] } set { self[_OpenURLKey.self] = newValue } }
    public var scenePhase: ScenePhase { get { self[_ScenePhaseKey.self] } set { self[_ScenePhaseKey.self] = newValue } }
}

public enum ColorScheme: CaseIterable, Hashable, Sendable {
    case light
    case dark
}
public enum LayoutDirection: Hashable, CaseIterable, Sendable {
    case leftToRight
    case rightToLeft
}
public enum ControlSize: CaseIterable, Hashable, Sendable {
    case mini
    case small
    case regular
    case large
    case extraLarge
}
public enum ScenePhase: Comparable, Hashable, Sendable {
    case background
    case inactive
    case active
}
public struct PresentationMode {
    public private(set) var isPresented: Bool = false
    public mutating func dismiss() {}
}
public struct DismissAction {
    let action: () -> Void
    public func callAsFunction() { action() }
}
public struct OpenURLAction {
    public struct Result {
        public static let handled = Result(), discarded = Result(), systemAction = Result()
        public static func systemAction(_ url: URL) -> Result { Result() }
    }
    let handler: (URL) -> Result
    public init(handler: @escaping (URL) -> OpenURLAction.Result) { self.handler = handler }
    public func callAsFunction(_ url: URL) { _ = handler(url) }
}

extension View {
    @inlinable public func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View {
        environment(\.colorScheme, colorScheme ?? .dark)
    }
    public func disabled(_ disabled: Bool) -> some View { transformEnvironment(\.isEnabled) { $0 = $0 && !disabled } }
    public func lineLimit(_ number: Int?) -> some View { environment(\.lineLimit, number) }
    public func controlSize(_ controlSize: ControlSize) -> some View { environment(\.controlSize, controlSize) }
    public func truncationMode(_ mode: Text.TruncationMode) -> some View { environment(\.truncationMode, mode) }
    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View { environment(\.multilineTextAlignment, alignment) }
}

// MARK: - AppStorage (UserDefaults)

@frozen @propertyWrapper public struct AppStorage<Value>: DynamicProperty {
    @usableFromInline let location: AnyLocation<Value>
    public var wrappedValue: Value {
        get { location.get() }
        nonmutating set { location.set(newValue, transaction: Transaction()) }
    }
    public var projectedValue: Binding<Value> { Binding(transaction: Transaction(), location: location, _value: location.get()) }
    init(_ key: String, store: UserDefaults?, default d: Value, read: @escaping (UserDefaults) -> Value?, write: @escaping (UserDefaults, Value) -> Void) {
        let ud = store ?? .standard
        location = _MWFunctionLocation(get: { read(ud).map { $0 } ?? d }, set: { v, _ in write(ud, v); _MWHostView.updateAll() })
    }
}
extension AppStorage {
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Bool {
        self.init(key, store: store, default: wrappedValue, read: { $0.object(forKey: key) as? Bool }, write: { $0.set($1, forKey: key) })
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Int {
        self.init(key, store: store, default: wrappedValue, read: { $0.object(forKey: key) as? Int }, write: { $0.set($1, forKey: key) })
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Double {
        self.init(key, store: store, default: wrappedValue, read: { $0.object(forKey: key) as? Double }, write: { $0.set($1, forKey: key) })
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == String {
        self.init(key, store: store, default: wrappedValue, read: { $0.string(forKey: key) }, write: { $0.set($1, forKey: key) })
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Data {
        self.init(key, store: store, default: wrappedValue, read: { $0.data(forKey: key) }, write: { $0.set($1, forKey: key) })
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value: RawRepresentable, Value.RawValue == Int {
        self.init(key, store: store, default: wrappedValue, read: { ($0.object(forKey: key) as? Int).flatMap(Value.init(rawValue:)) }, write: { $0.set($1.rawValue, forKey: key) })
    }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value: RawRepresentable, Value.RawValue == String {
        self.init(key, store: store, default: wrappedValue, read: { $0.string(forKey: key).flatMap(Value.init(rawValue:)) }, write: { $0.set($1.rawValue, forKey: key) })
    }
}
