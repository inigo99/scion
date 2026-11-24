// SwiftUI for scion: the public API of Apple's SwiftUI (same declarations, so the same mangled names that compiled
// apps import), implemented from scratch on scion's AppKit. Views are resolved into a tree of nodes (Engine.swift)
// that is laid out and drawn by a hosting NSView; state lives in the host, keyed by the view's place in the tree.
//
// Core: View, the builders, modifiers and the internal graph types that appear in the protocols' signatures.
@_exported import Foundation
@_exported import AppKit
@_exported import Combine

// MARK: - graph placeholders (Apple's attribute graph; only their names matter here: they are in the protocols' ABI)

public struct _Graph {}
public struct _GraphInputs {}
public struct _GraphValue<Value>: Equatable {
    public static func == (a: _GraphValue<Value>, b: _GraphValue<Value>) -> Bool { true }
    public subscript<U>(keyPath: KeyPath<Value, U>) -> _GraphValue<U> { _GraphValue<U>() }
}
public struct _ViewInputs {}
public struct _ViewOutputs {}
public struct _ViewListInputs {}
public struct _ViewListOutputs {}
public struct _ViewListCountInputs {}

// MARK: - View

public protocol View {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency var body: Self.Body { get }
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs
    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs
    static func _viewListCount(inputs: _ViewListCountInputs) -> Int?
}
extension View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs { _ViewOutputs() }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs { _ViewListOutputs() }
    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? { nil }
}

extension Never: View {
    public typealias Body = Never
    public var body: Never { fatalError() }
}

/// a view drawn by the engine itself (its body is never asked for)
func _primitive(_ name: String) -> Never { fatalError("\(name) has no body") }

// MARK: - builders

@resultBuilder public struct ViewBuilder {
    @_alwaysEmitIntoClient public static func buildExpression<Content: View>(_ content: Content) -> Content { content }
    @_alwaysEmitIntoClient public static func buildBlock() -> EmptyView { EmptyView() }
    @_alwaysEmitIntoClient public static func buildBlock<Content: View>(_ content: Content) -> Content { content }
    @_alwaysEmitIntoClient public static func buildBlock<each Content: View>(_ content: repeat each Content) -> TupleView<(repeat each Content)> {
        TupleView((repeat each content))
    }
    @_alwaysEmitIntoClient public static func buildIf<Content: View>(_ content: Content?) -> Content? { content }
    @_alwaysEmitIntoClient public static func buildEither<TrueContent: View, FalseContent: View>(first: TrueContent) -> _ConditionalContent<TrueContent, FalseContent> {
        _ConditionalContent(storage: .trueContent(first))
    }
    @_alwaysEmitIntoClient public static func buildEither<TrueContent: View, FalseContent: View>(second: FalseContent) -> _ConditionalContent<TrueContent, FalseContent> {
        _ConditionalContent(storage: .falseContent(second))
    }
    @_alwaysEmitIntoClient public static func buildLimitedAvailability<Content: View>(_ content: Content) -> AnyView { AnyView(content) }
}

@frozen public struct EmptyView: View {
    @inlinable public init() {}
    public typealias Body = Never
    public var body: Never { _primitive("EmptyView") }
}

@frozen public struct TupleView<T>: View {
    public var value: T
    public init(_ value: T) { self.value = value }
    public typealias Body = Never
    public var body: Never { _primitive("TupleView") }
}

@frozen public struct _ConditionalContent<TrueContent, FalseContent> {
    @usableFromInline @frozen internal enum Storage {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }
    @usableFromInline internal let storage: Storage
    @usableFromInline internal init(storage: Storage) { self.storage = storage }
}
extension _ConditionalContent: View where TrueContent: View, FalseContent: View {
    public typealias Body = Never
    public var body: Never { _primitive("_ConditionalContent") }
}

extension Optional: View where Wrapped: View {
    public typealias Body = Never
    public var body: Never { _primitive("Optional") }
}

@frozen public struct AnyView: View {
    @usableFromInline internal var storage: _AnyViewStorage
    public init<V>(_ view: V) where V: View {
        if let a = view as? AnyView { storage = a.storage } else { storage = _AnyViewStorage(view) }
    }
    public init<V>(erasing view: V) where V: View { self.init(view) }
    public init?(_fromValue value: Any) {
        guard let v = value as? any View else { return nil }
        storage = _AnyViewStorage(v)
    }
    public typealias Body = Never
    public var body: Never { _primitive("AnyView") }
}
@usableFromInline internal final class _AnyViewStorage {
    let view: any View
    init(_ v: any View) { view = v }
}

@frozen public struct Group<Content> {
    public typealias Body = Never
    @usableFromInline internal var content: Content
}
extension Group: View where Content: View {
    @inlinable public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: Never { _primitive("Group") }
}

// MARK: - modifiers

public protocol ViewModifier {
    associatedtype Body: View
    typealias Content = _ViewModifier_Content<Self>
    @ViewBuilder @MainActor @preconcurrency func body(content: Self.Content) -> Self.Body
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs
    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs
    static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int?
}
extension ViewModifier {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs { _ViewOutputs() }
    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs { _ViewListOutputs() }
    public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? { body(inputs) }
}
extension ViewModifier where Self.Body == Never {
    public func body(content: Self.Content) -> Self.Body { _primitive("\(Self.self)") }
}
extension ViewModifier {
    @inlinable public func concat<T>(_ modifier: T) -> ModifiedContent<Self, T> { ModifiedContent(content: self, modifier: modifier) }
}

public struct _ViewModifier_Content<Modifier>: View where Modifier: ViewModifier {
    public typealias Body = Never
    public var body: Never { _primitive("_ViewModifier_Content") }
}

@frozen public struct EmptyModifier: ViewModifier {
    public static let identity = EmptyModifier()
    public typealias Body = Never
    @inlinable public init() {}
}

@frozen public struct ModifiedContent<Content, Modifier> {
    public typealias Body = Never
    public var content: Content
    public var modifier: Modifier
    @inlinable public init(content: Content, modifier: Modifier) { self.content = content; self.modifier = modifier }
}
extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
    public var body: Never { _primitive("ModifiedContent") }
}
extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {}
extension ModifiedContent: Equatable where Content: Equatable, Modifier: Equatable {}

extension View {
    @inlinable public func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> { ModifiedContent(content: self, modifier: modifier) }
}

// MARK: - identity and lists

public struct ForEach<Data, ID, Content> where Data: RandomAccessCollection, ID: Hashable {
    public var data: Data
    public var content: (Data.Element) -> Content
    @usableFromInline internal var idGenerator: (Data.Element) -> ID
}
extension ForEach: View where Content: View {
    public typealias Body = Never
    public var body: Never { _primitive("ForEach") }
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data; self.content = content; idGenerator = { $0[keyPath: id] }
    }
}
extension ForEach where ID == Data.Element.ID, Content: View, Data.Element: Identifiable {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data; self.content = content; idGenerator = { $0.id }
    }
}
extension ForEach where Data == Range<Int>, ID == Int, Content: View {
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.data = data; self.content = content; idGenerator = { $0 }
    }
}

extension View {
    @inlinable public func id<ID>(_ id: ID) -> some View where ID: Hashable { IDView(self, id: id) }
}
@usableFromInline @frozen internal struct IDView<Content, ID>: View where Content: View, ID: Hashable {
    @usableFromInline var content: Content
    @usableFromInline var id: ID
    @inlinable public init(_ content: Content, id: ID) { self.content = content; self.id = id }
    @usableFromInline typealias Body = Never
    @usableFromInline var body: Never { _primitive("IDView") }
}

public protocol DynamicProperty {
    mutating func update()
}
extension DynamicProperty {
    public mutating func update() {}
}

// MARK: - preview / misc protocols apps declare conformances to

public protocol PreviewProvider {
    associatedtype Previews: View
    @ViewBuilder static var previews: Self.Previews { get }
}
