// Combine for scion: the public API of Apple's Combine (same declarations, so the same mangled names that compiled
// apps import), implemented from scratch. Publishers, subscribers, subjects, the common operators, schedulers,
// ObservableObject and @Published.
// ponytail: back-pressure is simplified (operators forward demand; merging operators ask their upstreams for
// .unlimited); add per-operator demand accounting when a custom subscriber needs it.
import Darwin

// MARK: - identity and cancellation

@frozen public struct CombineIdentifier: Hashable, CustomStringConvertible {
    private let rawValue: UInt64
    private static var next: UInt64 = 0
    public init() { CombineIdentifier.next &+= 1; rawValue = CombineIdentifier.next }
    public init(_ obj: AnyObject) { rawValue = UInt64(UInt(bitPattern: ObjectIdentifier(obj).hashValue)) }
    public var description: String { "0x" + String(rawValue, radix: 16) }
}

public protocol CustomCombineIdentifierConvertible {
    var combineIdentifier: CombineIdentifier { get }
}
extension CustomCombineIdentifierConvertible where Self: AnyObject {
    public var combineIdentifier: CombineIdentifier { CombineIdentifier(self) }
}

public protocol Cancellable {
    func cancel()
}
extension Cancellable {
    public func store<C>(in collection: inout C) where C: RangeReplaceableCollection, C.Element == AnyCancellable {
        AnyCancellable(self).store(in: &collection)
    }
    public func store(in set: inout Set<AnyCancellable>) { AnyCancellable(self).store(in: &set) }
}

final public class AnyCancellable: Cancellable, Hashable {
    private var action: (() -> Void)?
    public init(_ cancel: @escaping () -> Void) { action = cancel }
    public init<C>(_ canceller: C) where C: Cancellable { action = canceller.cancel }
    deinit { action?() }
    public func cancel() { let a = action; action = nil; a?() }
    public func store<C>(in collection: inout C) where C: RangeReplaceableCollection, C.Element == AnyCancellable {
        collection.append(self)
    }
    public func store(in set: inout Set<AnyCancellable>) { set.insert(self) }
    public static func == (lhs: AnyCancellable, rhs: AnyCancellable) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

// MARK: - the protocols

public protocol Subscription: Cancellable, CustomCombineIdentifierConvertible {
    func request(_ demand: Subscribers.Demand)
}

public protocol Subscriber<Input, Failure>: CustomCombineIdentifierConvertible {
    associatedtype Input
    associatedtype Failure: Error
    func receive(subscription: Subscription)
    func receive(_ input: Self.Input) -> Subscribers.Demand
    func receive(completion: Subscribers.Completion<Self.Failure>)
}

public protocol Publisher<Output, Failure> {
    associatedtype Output
    associatedtype Failure: Error
    func receive<S>(subscriber: S) where S: Subscriber, Self.Failure == S.Failure, Self.Output == S.Input
}
extension Publisher {
    public func subscribe<S>(_ subscriber: S) where S: Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
        receive(subscriber: subscriber)
    }
}

public protocol Subject<Output, Failure>: AnyObject, Publisher {
    func send(_ value: Self.Output)
    func send(completion: Subscribers.Completion<Self.Failure>)
    func send(subscription: Subscription)
}
extension Subject where Self.Output == Void {
    public func send() { send(()) }
}
extension Publisher {
    public func subscribe<S>(_ subject: S) -> AnyCancellable where S: Subject, Self.Failure == S.Failure, Self.Output == S.Output {
        let s = Subscribers.Sink<Output, Failure>(receiveCompletion: { subject.send(completion: $0) }, receiveValue: { subject.send($0) })
        receive(subscriber: s)
        return AnyCancellable(s)
    }
}

public protocol ConnectablePublisher<Output, Failure>: Publisher {
    func connect() -> Cancellable
}

public enum Subscriptions {
    public static var empty: Subscription { _Empty.shared }
    private final class _Empty: Subscription {
        static let shared = _Empty()
        func request(_ demand: Subscribers.Demand) {}
        func cancel() {}
    }
}

// MARK: - subscribers

public enum Subscribers {
    @frozen public struct Demand: Equatable, Comparable, Hashable, Codable, CustomStringConvertible {
        @usableFromInline internal let rawValue: UInt
        @inlinable internal init(rawValue: UInt) { self.rawValue = min(UInt(Int.max) + 1, rawValue) }
        public static let unlimited = Demand(rawValue: UInt(Int.max) + 1)
        public static let none = Demand(rawValue: 0)
        @inlinable public static func max(_ value: Int) -> Demand { precondition(value >= 0); return Demand(rawValue: UInt(value)) }
        public var description: String { self == .unlimited ? "unlimited" : "max(\(rawValue))" }
        public var max: Int? { self == .unlimited ? nil : Int(rawValue) }
        @inlinable public static func + (lhs: Demand, rhs: Demand) -> Demand {
            lhs == .unlimited || rhs == .unlimited ? .unlimited : Demand(rawValue: lhs.rawValue + rhs.rawValue)
        }
        @inlinable public static func += (lhs: inout Demand, rhs: Demand) { lhs = lhs + rhs }
        @inlinable public static func + (lhs: Demand, rhs: Int) -> Demand { lhs + .max(rhs) }
        @inlinable public static func += (lhs: inout Demand, rhs: Int) { lhs = lhs + rhs }
        public static func * (lhs: Demand, rhs: Int) -> Demand { lhs == .unlimited ? .unlimited : Demand(rawValue: lhs.rawValue * UInt(rhs)) }
        public static func *= (lhs: inout Demand, rhs: Int) { lhs = lhs * rhs }
        @inlinable public static func - (lhs: Demand, rhs: Demand) -> Demand {
            lhs == .unlimited ? .unlimited : rhs == .unlimited ? .none : Demand(rawValue: lhs.rawValue > rhs.rawValue ? lhs.rawValue - rhs.rawValue : 0)
        }
        @inlinable public static func -= (lhs: inout Demand, rhs: Demand) { lhs = lhs - rhs }
        @inlinable public static func - (lhs: Demand, rhs: Int) -> Demand { lhs - .max(rhs) }
        @inlinable public static func -= (lhs: inout Demand, rhs: Int) { lhs = lhs - rhs }
        public static func > (lhs: Demand, rhs: Int) -> Bool { lhs == .unlimited || lhs.rawValue > UInt(rhs) }
        public static func >= (lhs: Demand, rhs: Int) -> Bool { lhs == .unlimited || lhs.rawValue >= UInt(rhs) }
        public static func > (lhs: Int, rhs: Demand) -> Bool { rhs != .unlimited && UInt(lhs) > rhs.rawValue }
        public static func >= (lhs: Int, rhs: Demand) -> Bool { rhs != .unlimited && UInt(lhs) >= rhs.rawValue }
        public static func < (lhs: Demand, rhs: Int) -> Bool { lhs != .unlimited && lhs.rawValue < UInt(rhs) }
        public static func < (lhs: Int, rhs: Demand) -> Bool { rhs == .unlimited || UInt(lhs) < rhs.rawValue }
        public static func <= (lhs: Demand, rhs: Int) -> Bool { lhs != .unlimited && lhs.rawValue <= UInt(rhs) }
        public static func <= (lhs: Int, rhs: Demand) -> Bool { rhs == .unlimited || UInt(lhs) <= rhs.rawValue }
        public static func < (lhs: Demand, rhs: Demand) -> Bool { lhs.rawValue < rhs.rawValue }
        public static func == (lhs: Demand, rhs: Int) -> Bool { lhs != .unlimited && lhs.rawValue == UInt(rhs) }
        public static func != (lhs: Demand, rhs: Int) -> Bool { !(lhs == rhs) }
        public static func == (lhs: Int, rhs: Demand) -> Bool { rhs == lhs }
        public static func != (lhs: Int, rhs: Demand) -> Bool { !(rhs == lhs) }
        public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(UInt.self) }
        public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
    }

    @frozen public enum Completion<Failure: Error> {
        case finished
        case failure(Failure)
    }

    final public class Sink<Input, Failure: Error>: Subscriber, Cancellable, CustomStringConvertible, CustomReflectable, CustomPlaygroundDisplayConvertible {
        final public var receiveValue: (Input) -> Void
        final public var receiveCompletion: (Subscribers.Completion<Failure>) -> Void
        private var subscription: Subscription?
        public var description: String { "Sink" }
        public var customMirror: Mirror { Mirror(self, children: [:]) }
        public var playgroundDescription: Any { description }
        public init(receiveCompletion: @escaping ((Subscribers.Completion<Failure>) -> Void), receiveValue: @escaping ((Input) -> Void)) {
            self.receiveCompletion = receiveCompletion; self.receiveValue = receiveValue
        }
        final public func receive(subscription: Subscription) {
            guard self.subscription == nil else { subscription.cancel(); return }
            self.subscription = subscription
            subscription.request(.unlimited)
        }
        final public func receive(_ value: Input) -> Subscribers.Demand { receiveValue(value); return .none }
        final public func receive(completion: Subscribers.Completion<Failure>) { receiveCompletion(completion); subscription = nil }
        final public func cancel() { subscription?.cancel(); subscription = nil }
    }

    final public class Assign<Root, Input>: Subscriber, Cancellable, CustomStringConvertible, CustomReflectable, CustomPlaygroundDisplayConvertible {
        public typealias Failure = Never
        final public private(set) var object: Root?
        final public let keyPath: ReferenceWritableKeyPath<Root, Input>
        private var subscription: Subscription?
        public var description: String { "Assign" }
        public var customMirror: Mirror { Mirror(self, children: [:]) }
        public var playgroundDescription: Any { description }
        public init(object: Root, keyPath: ReferenceWritableKeyPath<Root, Input>) { self.object = object; self.keyPath = keyPath }
        final public func receive(subscription: Subscription) {
            guard self.subscription == nil else { subscription.cancel(); return }
            self.subscription = subscription
            subscription.request(.unlimited)
        }
        final public func receive(_ value: Input) -> Subscribers.Demand { object?[keyPath: keyPath] = value; return .none }
        final public func receive(completion: Subscribers.Completion<Never>) { object = nil; subscription = nil }
        final public func cancel() { subscription?.cancel(); subscription = nil; object = nil }
    }
}
extension Subscribers.Completion: Equatable where Failure: Equatable {}
extension Subscribers.Completion: Hashable where Failure: Hashable {}
extension Subscribers.Completion: Sendable where Failure: Sendable {}

extension Publisher {
    public func sink(receiveCompletion: @escaping ((Subscribers.Completion<Self.Failure>) -> Void), receiveValue: @escaping ((Self.Output) -> Void)) -> AnyCancellable {
        let s = Subscribers.Sink<Output, Failure>(receiveCompletion: receiveCompletion, receiveValue: receiveValue)
        receive(subscriber: s)
        return AnyCancellable(s)
    }
}
extension Publisher where Self.Failure == Never {
    public func sink(receiveValue: @escaping ((Self.Output) -> Void)) -> AnyCancellable {
        sink(receiveCompletion: { _ in }, receiveValue: receiveValue)
    }
    public func assign<Root>(to keyPath: ReferenceWritableKeyPath<Root, Self.Output>, on object: Root) -> AnyCancellable {
        let s = Subscribers.Assign(object: object, keyPath: keyPath)
        receive(subscriber: s)
        return AnyCancellable(s)
    }
    /// keeps the subscription for the lifetime of the @Published property
    public func assign(to published: inout Published<Self.Output>.Publisher) {
        let box = published.box
        box.keep.append(sink { [weak box] v in box?.set(v) })
    }
}

// MARK: - type erasure

@frozen public struct AnySubscriber<Input, Failure: Error>: Subscriber, CustomStringConvertible, CustomReflectable, CustomPlaygroundDisplayConvertible {
    @usableFromInline internal let box: _AnySubscriberBox<Input, Failure>
    @usableFromInline internal let descriptionThunk: () -> String
    @usableFromInline internal let customMirrorThunk: () -> Mirror
    @usableFromInline internal let playgroundDescriptionThunk: () -> Any
    public let combineIdentifier: CombineIdentifier
    public var description: String { descriptionThunk() }
    public var customMirror: Mirror { customMirrorThunk() }
    public var playgroundDescription: Any { playgroundDescriptionThunk() }
    public init<S>(_ s: S) where Input == S.Input, Failure == S.Failure, S: Subscriber {
        if let a = s as? AnySubscriber<Input, Failure> { self = a; return }
        box = _AnySubscriberBox(s.receive(subscription:), s.receive(_:), s.receive(completion:))
        combineIdentifier = s.combineIdentifier
        descriptionThunk = { String(describing: s) }; customMirrorThunk = { Mirror(reflecting: s) }; playgroundDescriptionThunk = { s }
    }
    public init<S>(_ s: S) where Input == S.Output, Failure == S.Failure, S: Subject {
        self.init(receiveSubscription: { s.send(subscription: $0) }, receiveValue: { s.send($0); return .none }, receiveCompletion: { s.send(completion: $0) })
    }
    public init(receiveSubscription: ((Subscription) -> Void)? = nil, receiveValue: ((Input) -> Subscribers.Demand)? = nil, receiveCompletion: ((Subscribers.Completion<Failure>) -> Void)? = nil) {
        box = _AnySubscriberBox({ receiveSubscription?($0) }, { receiveValue?($0) ?? .none }, { receiveCompletion?($0) })
        combineIdentifier = CombineIdentifier()
        descriptionThunk = { "Anonymous AnySubscriber" }; customMirrorThunk = { Mirror(reflecting: "Anonymous AnySubscriber") }; playgroundDescriptionThunk = { "Anonymous AnySubscriber" }
    }
    public func receive(subscription: Subscription) { box.sub(subscription) }
    public func receive(_ value: Input) -> Subscribers.Demand { box.value(value) }
    public func receive(completion: Subscribers.Completion<Failure>) { box.completion(completion) }
}
@usableFromInline internal final class _AnySubscriberBox<Input, Failure: Error> {
    let sub: (Subscription) -> Void, value: (Input) -> Subscribers.Demand, completion: (Subscribers.Completion<Failure>) -> Void
    init(_ s: @escaping (Subscription) -> Void, _ v: @escaping (Input) -> Subscribers.Demand, _ c: @escaping (Subscribers.Completion<Failure>) -> Void) {
        sub = s; value = v; completion = c
    }
}

@frozen public struct AnyPublisher<Output, Failure: Error>: CustomStringConvertible, CustomPlaygroundDisplayConvertible {
    @usableFromInline internal let box: PublisherBoxBase<Output, Failure>   // one reference, like Apple's (apps store it inline)
    public var description: String { "AnyPublisher" }
    public var playgroundDescription: Any { description }
    public init<P>(_ publisher: P) where Output == P.Output, Failure == P.Failure, P: Publisher {
        if let a = publisher as? AnyPublisher<Output, Failure> { self = a; return }
        box = PublisherBox(publisher)
    }
}
@usableFromInline internal class PublisherBoxBase<Output, Failure: Error> {
    init() {}
    func receive(_ s: AnySubscriber<Output, Failure>) {}
}
@usableFromInline internal final class PublisherBox<P: Publisher>: PublisherBoxBase<P.Output, P.Failure> {
    let base: P
    init(_ base: P) { self.base = base }
    override func receive(_ s: AnySubscriber<P.Output, P.Failure>) { base.receive(subscriber: s) }
}
extension AnyPublisher: Publisher {
    public func receive<S>(subscriber: S) where Output == S.Input, Failure == S.Failure, S: Subscriber { box.receive(AnySubscriber(subscriber)) }
}
extension Publisher {
    public func eraseToAnyPublisher() -> AnyPublisher<Self.Output, Self.Failure> { AnyPublisher(self) }
}
extension Subscriber {
    public func eraseToAnySubscriber() -> AnySubscriber<Self.Input, Self.Failure> { AnySubscriber(self) }
}

// MARK: - plumbing shared by the operators

final class _Lock {
    private var m = pthread_mutex_t()
    init() { pthread_mutex_init(&m, nil) }
    deinit { pthread_mutex_destroy(&m) }
    func run<T>(_ f: () throws -> T) rethrows -> T { pthread_mutex_lock(&m); defer { pthread_mutex_unlock(&m) }; return try f() }
}

/// One upstream subscription forwarding to one downstream subscriber; `body` handles each value and says whether it
/// was passed on (a value dropped asks the upstream for one more).
final class _Pipe<Input, UpFailure: Error, Down: Subscriber>: Subscriber, Subscription {
    typealias Failure = UpFailure
    let down: Down
    var upstream: Subscription?
    var done = false
    var body: (_Pipe, Input) -> Bool = { _, _ in false }
    var mapFailure: (UpFailure) -> Down.Failure
    var onCancel: () -> Void = {}
    init(_ down: Down, mapFailure: @escaping (UpFailure) -> Down.Failure) { self.down = down; self.mapFailure = mapFailure }
    func receive(subscription: Subscription) {
        guard upstream == nil, !done else { subscription.cancel(); return }
        upstream = subscription
        down.receive(subscription: self)
    }
    func receive(_ input: Input) -> Subscribers.Demand { done ? .none : (body(self, input) ? .none : .max(1)) }
    /// set by operators that delay the completion too (delay, receive(on:))
    var completionHook: ((Subscribers.Completion<UpFailure>) -> Void)?
    func receive(completion: Subscribers.Completion<UpFailure>) {
        if let h = completionHook, !done { completionHook = nil; h(completion); return }
        guard !done else { return }
        done = true; upstream = nil
        switch completion {
        case .finished: down.receive(completion: .finished)
        case .failure(let e): down.receive(completion: .failure(mapFailure(e)))
        }
    }
    func emit(_ v: Down.Input) { if !done { _ = down.receive(v) } }
    func finish(_ c: Subscribers.Completion<Down.Failure> = .finished) {
        guard !done else { return }
        done = true; upstream?.cancel(); upstream = nil; onCancel()
        down.receive(completion: c)
    }
    func request(_ demand: Subscribers.Demand) { upstream?.request(demand) }
    func cancel() { done = true; upstream?.cancel(); upstream = nil; onCancel() }
}
extension _Pipe where UpFailure == Down.Failure {
    convenience init(_ down: Down) { self.init(down, mapFailure: { $0 }) }
}

/// Several upstreams into one downstream (merge, combineLatest): asks each upstream for .unlimited.
final class _Fan<Down: Subscriber>: Subscription {
    let down: Down
    let lock = _Lock()
    var subs: [Subscription?]
    var finished: [Bool]
    var done = false
    init(_ down: Down, count: Int) { self.down = down; subs = Array(repeating: nil, count: count); finished = Array(repeating: false, count: count) }
    func attach<P: Publisher>(_ p: P, _ i: Int, _ value: @escaping (P.Output) -> Void) where P.Failure == Down.Failure {
        p.receive(subscriber: AnySubscriber<P.Output, P.Failure>(
            receiveSubscription: { [self] s in subs[i] = s; s.request(.unlimited) },
            receiveValue: { [self] v in if !done { value(v) }; return .none },
            receiveCompletion: { [self] c in
                guard !done else { return }
                if case .failure = c { done = true; cancelAll(); down.receive(completion: c); return }
                finished[i] = true
                if !finished.contains(false) { done = true; down.receive(completion: .finished) }
            }))
    }
    func emit(_ v: Down.Input) { if !done { _ = down.receive(v) } }
    func request(_ demand: Subscribers.Demand) {}
    func cancelAll() { for s in subs { s?.cancel() }; subs = subs.map { _ in nil } }
    func cancel() { done = true; cancelAll() }
}

// MARK: - publishers

public struct Just<Output>: Publisher {
    public typealias Failure = Never
    public let output: Output
    public init(_ output: Output) { self.output = output }
    public func receive<S>(subscriber: S) where Output == S.Input, S: Subscriber, S.Failure == Never {
        let p = _Pipe<Output, Never, S>(subscriber)
        subscriber.receive(subscription: p)
        if !p.done { _ = subscriber.receive(output); p.done = true; subscriber.receive(completion: .finished) }
    }
}
extension Just: Equatable where Output: Equatable {}

public struct Empty<Output, Failure: Error>: Publisher, Equatable {
    public let completeImmediately: Bool
    public init(completeImmediately: Bool = true) { self.completeImmediately = completeImmediately }
    public init(completeImmediately: Bool = true, outputType: Output.Type, failureType: Failure.Type) { self.completeImmediately = completeImmediately }
    public func receive<S>(subscriber: S) where Output == S.Input, Failure == S.Failure, S: Subscriber {
        subscriber.receive(subscription: Subscriptions.empty)
        if completeImmediately { subscriber.receive(completion: .finished) }
    }
    public static func == (lhs: Empty, rhs: Empty) -> Bool { lhs.completeImmediately == rhs.completeImmediately }
}

public struct Fail<Output, Failure: Error>: Publisher {
    public let error: Failure
    public init(error: Failure) { self.error = error }
    public init(outputType: Output.Type, failure: Failure) { error = failure }
    public func receive<S>(subscriber: S) where Output == S.Input, Failure == S.Failure, S: Subscriber {
        subscriber.receive(subscription: Subscriptions.empty)
        subscriber.receive(completion: .failure(error))
    }
}

public struct Future<Output, Failure: Error>: Publisher {
    public typealias Promise = (Result<Output, Failure>) -> Void
    final class State {
        let lock = _Lock()
        var result: Result<Output, Failure>?
        var waiting: [AnySubscriber<Output, Failure>] = []
        func fulfil(_ r: Result<Output, Failure>) {
            let w: [AnySubscriber<Output, Failure>] = lock.run { if result != nil { return [] }; result = r; defer { waiting = [] }; return waiting }
            for s in w { deliver(s, r) }
        }
        func deliver(_ s: AnySubscriber<Output, Failure>, _ r: Result<Output, Failure>) {
            switch r {
            case .success(let v): _ = s.receive(v); s.receive(completion: .finished)
            case .failure(let e): s.receive(completion: .failure(e))
            }
        }
    }
    let state = State()
    public init(_ attemptToFulfill: @escaping (@escaping Future<Output, Failure>.Promise) -> Void) {
        let s = state
        attemptToFulfill { s.fulfil($0) }
    }
    public func receive<S>(subscriber: S) where Output == S.Input, Failure == S.Failure, S: Subscriber {
        let a = AnySubscriber(subscriber)
        subscriber.receive(subscription: Subscriptions.empty)
        let r: Result<Output, Failure>? = state.lock.run { if state.result == nil { state.waiting.append(a) }; return state.result }
        if let r = r { state.deliver(a, r) }
    }
}

public struct Deferred<DeferredPublisher: Publisher>: Publisher {
    public typealias Output = DeferredPublisher.Output
    public typealias Failure = DeferredPublisher.Failure
    public let createPublisher: () -> DeferredPublisher
    public init(createPublisher: @escaping () -> DeferredPublisher) { self.createPublisher = createPublisher }
    public func receive<S>(subscriber: S) where S: Subscriber, DeferredPublisher.Failure == S.Failure, DeferredPublisher.Output == S.Input {
        createPublisher().receive(subscriber: subscriber)
    }
}

extension Sequence {
    public var publisher: Publishers.Sequence<Self, Never> { Publishers.Sequence(sequence: self) }
}
extension Optional {
    public var publisher: Optional<Wrapped>.Publisher { Optional<Wrapped>.Publisher(self) }
    public struct Publisher: Combine.Publisher {
        public typealias Output = Wrapped
        public typealias Failure = Never
        public let output: Wrapped?
        public init(_ output: Output?) { self.output = output }
        public func receive<S>(subscriber: S) where Wrapped == S.Input, S: Subscriber, S.Failure == Never {
            if let o = output { Just(o).receive(subscriber: subscriber) } else { Empty().receive(subscriber: subscriber) }
        }
    }
}

// MARK: - subjects

final class _Conduits<Output, Failure: Error> {
    final class Conduit: Subscription {
        weak var owner: _Conduits?
        var down: AnySubscriber<Output, Failure>?
        init(_ o: _Conduits, _ d: AnySubscriber<Output, Failure>) { owner = o; down = d }
        func request(_ demand: Subscribers.Demand) {}
        func cancel() { down = nil; owner?.remove(self) }
    }
    let lock = _Lock()
    var list: [Conduit] = []
    var completion: Subscribers.Completion<Failure>?
    var upstreams: [Subscription] = []
    func add(_ s: AnySubscriber<Output, Failure>, then: ((AnySubscriber<Output, Failure>) -> Void)? = nil) {
        let c = Conduit(self, s)
        let done: Subscribers.Completion<Failure>? = lock.run { if completion == nil { list.append(c) }; return completion }
        s.receive(subscription: c)
        if let d = done { s.receive(completion: d); return }
        then?(s)
    }
    func remove(_ c: Conduit) { lock.run { list.removeAll { $0 === c } } }
    func send(_ v: Output) { for c in lock.run({ list }) { _ = c.down?.receive(v) } }
    func finish(_ c: Subscribers.Completion<Failure>) {
        let l: [Conduit] = lock.run { if completion != nil { return [] }; completion = c; defer { list = [] }; return list }
        for x in l { x.down?.receive(completion: c) }
    }
}

final public class PassthroughSubject<Output, Failure: Error>: Subject {
    let conduits = _Conduits<Output, Failure>()
    public init() {}
    final public func send(subscription: Subscription) { conduits.upstreams.append(subscription); subscription.request(.unlimited) }
    final public func receive<S>(subscriber: S) where Output == S.Input, Failure == S.Failure, S: Subscriber { conduits.add(AnySubscriber(subscriber)) }
    final public func send(_ input: Output) { conduits.send(input) }
    final public func send(completion: Subscribers.Completion<Failure>) { conduits.finish(completion) }
}

final public class CurrentValueSubject<Output, Failure: Error>: Subject {
    let conduits = _Conduits<Output, Failure>()
    private var current: Output
    final public var value: Output {
        get { conduits.lock.run { current } }
        set { send(newValue) }
    }
    public init(_ value: Output) { current = value }
    final public func send(subscription: Subscription) { conduits.upstreams.append(subscription); subscription.request(.unlimited) }
    final public func receive<S>(subscriber: S) where Output == S.Input, Failure == S.Failure, S: Subscriber {
        conduits.add(AnySubscriber(subscriber)) { [unowned self] s in _ = s.receive(self.value) }
    }
    final public func send(_ input: Output) { conduits.lock.run { current = input }; conduits.send(input) }
    final public func send(completion: Subscribers.Completion<Failure>) { conduits.finish(completion) }
}

// MARK: - ObservableObject and @Published

final public class ObservableObjectPublisher: Publisher {
    public typealias Output = Void
    public typealias Failure = Never
    let subject = PassthroughSubject<Void, Never>()
    public init() {}
    final public func receive<S>(subscriber: S) where S: Subscriber, S.Failure == Never, S.Input == Void { subject.receive(subscriber: subscriber) }
    final public func send() { subject.send(()) }
}

public protocol ObservableObject: AnyObject {
    associatedtype ObjectWillChangePublisher: Publisher = ObservableObjectPublisher where Self.ObjectWillChangePublisher.Failure == Never
    var objectWillChange: Self.ObjectWillChangePublisher { get }
}

/// the default objectWillChange of each object (Apple's finds it through the object's @Published storage)
/// ponytail: entries are never removed; key them weakly if long-lived apps create many observable objects
private let _publishersLock = _Lock()
private var _publishers: [ObjectIdentifier: ObservableObjectPublisher] = [:]
func _objectWillChange(_ o: AnyObject) -> ObservableObjectPublisher {
    _publishersLock.run {
        if let p = _publishers[ObjectIdentifier(o)] { return p }
        let p = ObservableObjectPublisher(); _publishers[ObjectIdentifier(o)] = p; return p
    }
}
extension ObservableObject where Self.ObjectWillChangePublisher == ObservableObjectPublisher {
    public var objectWillChange: ObservableObjectPublisher { _objectWillChange(self) }
}

@propertyWrapper public struct Published<Value> {
    final class Box {
        var value: Value
        let subject: CurrentValueSubject<Value, Never>
        var keep: [AnyCancellable] = []
        init(_ v: Value) { value = v; subject = CurrentValueSubject(v) }
        func set(_ v: Value) { value = v; subject.send(v) }
    }
    var box: Box
    public init(wrappedValue: Value) { box = Box(wrappedValue) }
    public init(initialValue: Value) { box = Box(initialValue) }
    @available(*, unavailable, message: "@Published is only available on properties of classes")
    public var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }
    public var projectedValue: Published<Value>.Publisher {
        mutating get { Publisher(box) }
        set { box = newValue.box }
    }
    public static subscript<EnclosingSelf: AnyObject>(_enclosingInstance object: EnclosingSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Published<Value>>) -> Value {
        get { object[keyPath: storageKeyPath].box.value }
        set {
            if object is any ObservableObject { _objectWillChange(object).send() }
            object[keyPath: storageKeyPath].box.set(newValue)
        }
    }
    public struct Publisher: Combine.Publisher {
        public typealias Output = Value
        public typealias Failure = Never
        let box: Box
        init(_ b: Box) { box = b }
        public func receive<S>(subscriber: S) where Value == S.Input, S: Subscriber, S.Failure == Never { box.subject.receive(subscriber: subscriber) }
    }
}

// MARK: - operators

public enum Publishers {}

extension Publishers {
    public struct Sequence<Elements: Swift.Sequence, Failure: Error>: Publisher {
        public typealias Output = Elements.Element
        public let sequence: Elements
        public init(sequence: Elements) { self.sequence = sequence }
        public func receive<S>(subscriber: S) where Failure == S.Failure, S: Subscriber, Elements.Element == S.Input {
            let p = _Pipe<Output, Failure, S>(subscriber)
            subscriber.receive(subscription: p)
            for v in sequence { if p.done { return }; p.emit(v) }
            p.finish()
        }
    }

    public struct Map<Upstream: Publisher, Output>: Publisher {
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let transform: (Upstream.Output) -> Output
        public init(upstream: Upstream, transform: @escaping (Upstream.Output) -> Output) { self.upstream = upstream; self.transform = transform }
        public func receive<S>(subscriber: S) where Output == S.Input, S: Subscriber, Upstream.Failure == S.Failure {
            let p = _Pipe<Upstream.Output, Failure, S>(subscriber); let t = transform
            p.body = { p, v in p.emit(t(v)); return true }
            upstream.receive(subscriber: p)
        }
    }

    public struct CompactMap<Upstream: Publisher, Output>: Publisher {
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let transform: (Upstream.Output) -> Output?
        public init(upstream: Upstream, transform: @escaping (Upstream.Output) -> Output?) { self.upstream = upstream; self.transform = transform }
        public func receive<S>(subscriber: S) where Output == S.Input, S: Subscriber, Upstream.Failure == S.Failure {
            let p = _Pipe<Upstream.Output, Failure, S>(subscriber); let t = transform
            p.body = { p, v in if let o = t(v) { p.emit(o); return true }; return false }
            upstream.receive(subscriber: p)
        }
    }

    public struct Filter<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let isIncluded: (Upstream.Output) -> Bool
        public init(upstream: Upstream, isIncluded: @escaping (Upstream.Output) -> Bool) { self.upstream = upstream; self.isIncluded = isIncluded }
        public func receive<S>(subscriber: S) where S: Subscriber, Upstream.Failure == S.Failure, Upstream.Output == S.Input {
            let p = _Pipe<Output, Failure, S>(subscriber); let f = isIncluded
            p.body = { p, v in if f(v) { p.emit(v); return true }; return false }
            upstream.receive(subscriber: p)
        }
    }

    public struct Drop<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let count: Int
        public init(upstream: Upstream, count: Int) { self.upstream = upstream; self.count = count }
        public func receive<S>(subscriber: S) where S: Subscriber, Upstream.Failure == S.Failure, Upstream.Output == S.Input {
            let p = _Pipe<Output, Failure, S>(subscriber); var left = count
            p.body = { p, v in if left > 0 { left -= 1; return false }; p.emit(v); return true }
            upstream.receive(subscriber: p)
        }
    }

    public struct First<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public init(upstream: Upstream) { self.upstream = upstream }
        public func receive<S>(subscriber: S) where S: Subscriber, Upstream.Failure == S.Failure, Upstream.Output == S.Input {
            let p = _Pipe<Output, Failure, S>(subscriber)
            p.body = { p, v in p.emit(v); p.finish(); return true }
            upstream.receive(subscriber: p)
        }
    }

    public struct RemoveDuplicates<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let predicate: (Output, Output) -> Bool
        public init(upstream: Upstream, predicate: @escaping (Publishers.RemoveDuplicates<Upstream>.Output, Publishers.RemoveDuplicates<Upstream>.Output) -> Bool) {
            self.upstream = upstream; self.predicate = predicate
        }
        public func receive<S>(subscriber: S) where S: Subscriber, Upstream.Failure == S.Failure, Upstream.Output == S.Input {
            let p = _Pipe<Output, Failure, S>(subscriber); let same = predicate; var last: Output?
            p.body = { p, v in if let l = last, same(l, v) { return false }; last = v; p.emit(v); return true }
            upstream.receive(subscriber: p)
        }
    }

    public struct Merge<A: Publisher, B: Publisher>: Publisher where A.Failure == B.Failure, A.Output == B.Output {
        public typealias Output = A.Output
        public typealias Failure = A.Failure
        public let a: A
        public let b: B
        public init(_ a: A, _ b: B) { self.a = a; self.b = b }
        public func receive<S>(subscriber: S) where S: Subscriber, B.Failure == S.Failure, B.Output == S.Input {
            let f = _Fan(subscriber, count: 2)
            subscriber.receive(subscription: f)
            f.attach(a, 0) { f.emit($0) }; f.attach(b, 1) { f.emit($0) }
        }
    }

    public struct MergeMany<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let publishers: [Upstream]
        public init(_ upstream: Upstream...) { publishers = upstream }
        public init<S: Swift.Sequence>(_ upstream: S) where Upstream == S.Element { publishers = Array(upstream) }
        public func receive<S>(subscriber: S) where S: Subscriber, Upstream.Failure == S.Failure, Upstream.Output == S.Input {
            let f = _Fan(subscriber, count: publishers.count)
            subscriber.receive(subscription: f)
            for (i, p) in publishers.enumerated() { f.attach(p, i) { f.emit($0) } }
            if publishers.isEmpty { subscriber.receive(completion: .finished) }
        }
        public func merge(with other: Upstream) -> Publishers.MergeMany<Upstream> { MergeMany(publishers + [other]) }
    }

    public struct CombineLatest<A: Publisher, B: Publisher>: Publisher where A.Failure == B.Failure {
        public typealias Output = (A.Output, B.Output)
        public typealias Failure = A.Failure
        public let a: A
        public let b: B
        public init(_ a: A, _ b: B) { self.a = a; self.b = b }
        public func receive<S>(subscriber: S) where S: Subscriber, B.Failure == S.Failure, S.Input == (A.Output, B.Output) {
            let f = _Fan(subscriber, count: 2)
            var la: A.Output?, lb: B.Output?
            subscriber.receive(subscription: f)
            f.attach(a, 0) { v in la = v; if let y = lb { f.emit((v, y)) } }
            f.attach(b, 1) { v in lb = v; if let x = la { f.emit((x, v)) } }
        }
    }

    final public class Autoconnect<Upstream: ConnectablePublisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        final public let upstream: Upstream
        private let lock = _Lock()
        private var connection: Cancellable?
        private var count = 0
        public init(upstream: Upstream) { self.upstream = upstream }
        final public func receive<S>(subscriber: S) where S: Subscriber, Upstream.Failure == S.Failure, Upstream.Output == S.Input {
            let p = _Pipe<Output, Failure, S>(subscriber)
            p.body = { p, v in p.emit(v); return true }
            p.onCancel = { [self] in
                let c: Cancellable? = lock.run { count -= 1; if count == 0 { defer { connection = nil }; return connection }; return nil }
                c?.cancel()
            }
            upstream.receive(subscriber: p)
            let connect: Bool = lock.run { count += 1; return connection == nil }
            if connect { let c = upstream.connect(); lock.run { connection = c } }
        }
    }

    public struct Debounce<Upstream: Publisher, Context: Scheduler>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let dueTime: Context.SchedulerTimeType.Stride
        public let scheduler: Context
        public let options: Context.SchedulerOptions?
        public init(upstream: Upstream, dueTime: Context.SchedulerTimeType.Stride, scheduler: Context, options: Context.SchedulerOptions?) {
            self.upstream = upstream; self.dueTime = dueTime; self.scheduler = scheduler; self.options = options
        }
        public func receive<S>(subscriber: S) where S: Subscriber, Upstream.Failure == S.Failure, Upstream.Output == S.Input {
            let p = _Pipe<Output, Failure, S>(subscriber); let sch = scheduler, due = dueTime, opt = options
            var generation = 0
            p.body = { p, v in
                generation += 1; let g = generation
                sch.schedule(after: sch.now.advanced(by: due), tolerance: sch.minimumTolerance, options: opt) { if g == generation { p.emit(v) } }
                return true
            }
            upstream.receive(subscriber: p)
        }
    }

    public struct Delay<Upstream: Publisher, Context: Scheduler>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let interval: Context.SchedulerTimeType.Stride
        public let tolerance: Context.SchedulerTimeType.Stride
        public let scheduler: Context
        public let options: Context.SchedulerOptions?
        public init(upstream: Upstream, interval: Context.SchedulerTimeType.Stride, tolerance: Context.SchedulerTimeType.Stride, scheduler: Context, options: Context.SchedulerOptions? = nil) {
            self.upstream = upstream; self.interval = interval; self.tolerance = tolerance; self.scheduler = scheduler; self.options = options
        }
        public func receive<S>(subscriber: S) where S: Subscriber, Upstream.Failure == S.Failure, Upstream.Output == S.Input {
            let p = _Pipe<Output, Failure, S>(subscriber); let sch = scheduler, iv = interval, tol = tolerance, opt = options
            p.body = { p, v in sch.schedule(after: sch.now.advanced(by: iv), tolerance: tol, options: opt) { p.emit(v) }; return true }
            p.completionHook = { c in sch.schedule(after: sch.now.advanced(by: iv), tolerance: tol, options: opt) { p.receive(completion: c) } }
            upstream.receive(subscriber: p)
        }
    }

    public struct Timeout<Upstream: Publisher, Context: Scheduler>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let interval: Context.SchedulerTimeType.Stride
        public let scheduler: Context
        public let options: Context.SchedulerOptions?
        public let customError: (() -> Upstream.Failure)?
        public init(upstream: Upstream, interval: Context.SchedulerTimeType.Stride, scheduler: Context, options: Context.SchedulerOptions?, customError: (() -> Publishers.Timeout<Upstream, Context>.Failure)?) {
            self.upstream = upstream; self.interval = interval; self.scheduler = scheduler; self.options = options; self.customError = customError
        }
        public func receive<S>(subscriber: S) where S: Subscriber, Upstream.Failure == S.Failure, Upstream.Output == S.Input {
            let p = _Pipe<Output, Failure, S>(subscriber); let sch = scheduler, iv = interval, opt = options, err = customError
            var generation = 0
            func arm() {
                generation += 1; let g = generation
                sch.schedule(after: sch.now.advanced(by: iv), tolerance: sch.minimumTolerance, options: opt) {
                    if g == generation { p.finish(err.map { .failure($0()) } ?? .finished) }
                }
            }
            p.body = { p, v in p.emit(v); arm(); return true }
            upstream.receive(subscriber: p)
            arm()
        }
    }

    public struct ReceiveOn<Upstream: Publisher, Context: Scheduler>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let scheduler: Context
        public let options: Context.SchedulerOptions?
        public init(upstream: Upstream, scheduler: Context, options: Context.SchedulerOptions?) { self.upstream = upstream; self.scheduler = scheduler; self.options = options }
        public func receive<S>(subscriber: S) where S: Subscriber, Upstream.Failure == S.Failure, Upstream.Output == S.Input {
            let p = _Pipe<Output, Failure, S>(subscriber); let sch = scheduler, opt = options
            p.body = { p, v in sch.schedule(options: opt) { p.emit(v) }; return true }
            p.completionHook = { c in sch.schedule(options: opt) { p.receive(completion: c) } }
            upstream.receive(subscriber: p)
        }
    }

    public struct HandleEvents<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public var receiveSubscription: ((Subscription) -> Void)?
        public var receiveOutput: ((Upstream.Output) -> Void)?
        public var receiveCompletion: ((Subscribers.Completion<Upstream.Failure>) -> Void)?
        public var receiveCancel: (() -> Void)?
        public var receiveRequest: ((Subscribers.Demand) -> Void)?
        public init(upstream: Upstream, receiveSubscription: ((Subscription) -> Void)? = nil, receiveOutput: ((Upstream.Output) -> Void)? = nil,
                    receiveCompletion: ((Subscribers.Completion<Upstream.Failure>) -> Void)? = nil, receiveCancel: (() -> Void)? = nil,
                    receiveRequest: ((Subscribers.Demand) -> Void)?) {
            self.upstream = upstream; self.receiveSubscription = receiveSubscription; self.receiveOutput = receiveOutput
            self.receiveCompletion = receiveCompletion; self.receiveCancel = receiveCancel; self.receiveRequest = receiveRequest
        }
        public func receive<S>(subscriber: S) where S: Subscriber, Upstream.Failure == S.Failure, Upstream.Output == S.Input {
            let out = receiveOutput, done = receiveCompletion
            upstream.receive(subscriber: AnySubscriber<Output, Failure>(
                receiveSubscription: { [receiveSubscription] s in receiveSubscription?(s); subscriber.receive(subscription: s) },
                receiveValue: { v in out?(v); return subscriber.receive(v) },
                receiveCompletion: { c in done?(c); subscriber.receive(completion: c) }))
        }
    }
}

extension Publisher {
    public func map<T>(_ transform: @escaping (Self.Output) -> T) -> Publishers.Map<Self, T> { Publishers.Map(upstream: self, transform: transform) }
    public func compactMap<T>(_ transform: @escaping (Self.Output) -> T?) -> Publishers.CompactMap<Self, T> { Publishers.CompactMap(upstream: self, transform: transform) }
    public func filter(_ isIncluded: @escaping (Self.Output) -> Bool) -> Publishers.Filter<Self> { Publishers.Filter(upstream: self, isIncluded: isIncluded) }
    public func dropFirst(_ count: Int = 1) -> Publishers.Drop<Self> { Publishers.Drop(upstream: self, count: count) }
    public func first() -> Publishers.First<Self> { Publishers.First(upstream: self) }
    public func removeDuplicates(by predicate: @escaping (Self.Output, Self.Output) -> Bool) -> Publishers.RemoveDuplicates<Self> {
        Publishers.RemoveDuplicates(upstream: self, predicate: predicate)
    }
    public func merge<P>(with other: P) -> Publishers.Merge<Self, P> where P: Publisher, Self.Failure == P.Failure, Self.Output == P.Output { Publishers.Merge(self, other) }
    public func combineLatest<P>(_ other: P) -> Publishers.CombineLatest<Self, P> where P: Publisher, Self.Failure == P.Failure { Publishers.CombineLatest(self, other) }
    public func debounce<S>(for dueTime: S.SchedulerTimeType.Stride, scheduler: S, options: S.SchedulerOptions? = nil) -> Publishers.Debounce<Self, S> where S: Scheduler {
        Publishers.Debounce(upstream: self, dueTime: dueTime, scheduler: scheduler, options: options)
    }
    public func delay<S>(for interval: S.SchedulerTimeType.Stride, tolerance: S.SchedulerTimeType.Stride? = nil, scheduler: S, options: S.SchedulerOptions? = nil) -> Publishers.Delay<Self, S> where S: Scheduler {
        Publishers.Delay(upstream: self, interval: interval, tolerance: tolerance ?? scheduler.minimumTolerance, scheduler: scheduler, options: options)
    }
    public func timeout<S>(_ interval: S.SchedulerTimeType.Stride, scheduler: S, options: S.SchedulerOptions? = nil, customError: (() -> Self.Failure)? = nil) -> Publishers.Timeout<Self, S> where S: Scheduler {
        Publishers.Timeout(upstream: self, interval: interval, scheduler: scheduler, options: options, customError: customError)
    }
    public func receive<S>(on scheduler: S, options: S.SchedulerOptions? = nil) -> Publishers.ReceiveOn<Self, S> where S: Scheduler {
        Publishers.ReceiveOn(upstream: self, scheduler: scheduler, options: options)
    }
    public func handleEvents(receiveSubscription: ((Subscription) -> Void)? = nil, receiveOutput: ((Self.Output) -> Void)? = nil,
                             receiveCompletion: ((Subscribers.Completion<Self.Failure>) -> Void)? = nil, receiveCancel: (() -> Void)? = nil,
                             receiveRequest: ((Subscribers.Demand) -> Void)? = nil) -> Publishers.HandleEvents<Self> {
        Publishers.HandleEvents(upstream: self, receiveSubscription: receiveSubscription, receiveOutput: receiveOutput,
                                receiveCompletion: receiveCompletion, receiveCancel: receiveCancel, receiveRequest: receiveRequest)
    }
}
extension Publisher where Self.Output: Equatable {
    public func removeDuplicates() -> Publishers.RemoveDuplicates<Self> { Publishers.RemoveDuplicates(upstream: self, predicate: ==) }
}
extension ConnectablePublisher {
    public func autoconnect() -> Publishers.Autoconnect<Self> { Publishers.Autoconnect(upstream: self) }
}

// MARK: - schedulers

public protocol SchedulerTimeIntervalConvertible {
    static func seconds(_ s: Int) -> Self
    static func seconds(_ s: Double) -> Self
    static func milliseconds(_ ms: Int) -> Self
    static func microseconds(_ us: Int) -> Self
    static func nanoseconds(_ ns: Int) -> Self
}

public protocol Scheduler<SchedulerTimeType> {
    associatedtype SchedulerTimeType: Strideable where Self.SchedulerTimeType.Stride: SchedulerTimeIntervalConvertible
    associatedtype SchedulerOptions
    var now: Self.SchedulerTimeType { get }
    var minimumTolerance: Self.SchedulerTimeType.Stride { get }
    func schedule(options: Self.SchedulerOptions?, _ action: @escaping () -> Void)
    func schedule(after date: Self.SchedulerTimeType, tolerance: Self.SchedulerTimeType.Stride, options: Self.SchedulerOptions?, _ action: @escaping () -> Void)
    func schedule(after date: Self.SchedulerTimeType, interval: Self.SchedulerTimeType.Stride, tolerance: Self.SchedulerTimeType.Stride,
                  options: Self.SchedulerOptions?, _ action: @escaping () -> Void) -> Cancellable
}
extension Scheduler {
    public func schedule(after date: Self.SchedulerTimeType, tolerance: Self.SchedulerTimeType.Stride, _ action: @escaping () -> Void) {
        schedule(after: date, tolerance: tolerance, options: nil, action)
    }
    public func schedule(after date: Self.SchedulerTimeType, _ action: @escaping () -> Void) { schedule(after: date, tolerance: minimumTolerance, action) }
    public func schedule(_ action: @escaping () -> Void) { schedule(options: nil, action) }
    public func schedule(after date: Self.SchedulerTimeType, interval: Self.SchedulerTimeType.Stride, tolerance: Self.SchedulerTimeType.Stride,
                         _ action: @escaping () -> Void) -> Cancellable {
        schedule(after: date, interval: interval, tolerance: tolerance, options: nil, action)
    }
    public func schedule(after date: Self.SchedulerTimeType, interval: Self.SchedulerTimeType.Stride, _ action: @escaping () -> Void) -> Cancellable {
        schedule(after: date, interval: interval, tolerance: minimumTolerance, action)
    }
}

public struct ImmediateScheduler: Scheduler {
    public struct SchedulerTimeType: Strideable {
        public struct Stride: ExpressibleByFloatLiteral, Comparable, SignedNumeric, Codable, SchedulerTimeIntervalConvertible {
            public typealias FloatLiteralType = Double
            public typealias IntegerLiteralType = Int
            public typealias Magnitude = Int
            public var magnitude: Int
            public init(_ value: Int) { magnitude = value }
            public init(integerLiteral value: Int) { magnitude = value }
            public init(floatLiteral value: Double) { magnitude = Int(value) }
            public init?<T>(exactly source: T) where T: BinaryInteger { guard let v = Int(exactly: source) else { return nil }; magnitude = v }
            public static func < (lhs: Stride, rhs: Stride) -> Bool { lhs.magnitude < rhs.magnitude }
            public static func * (lhs: Stride, rhs: Stride) -> Stride { Stride(lhs.magnitude * rhs.magnitude) }
            public static func + (lhs: Stride, rhs: Stride) -> Stride { Stride(lhs.magnitude + rhs.magnitude) }
            public static func - (lhs: Stride, rhs: Stride) -> Stride { Stride(lhs.magnitude - rhs.magnitude) }
            public static func -= (lhs: inout Stride, rhs: Stride) { lhs = lhs - rhs }
            public static func *= (lhs: inout Stride, rhs: Stride) { lhs = lhs * rhs }
            public static func += (lhs: inout Stride, rhs: Stride) { lhs = lhs + rhs }
            public static func seconds(_ s: Int) -> Stride { Stride(0) }
            public static func seconds(_ s: Double) -> Stride { Stride(0) }
            public static func milliseconds(_ ms: Int) -> Stride { Stride(0) }
            public static func microseconds(_ us: Int) -> Stride { Stride(0) }
            public static func nanoseconds(_ ns: Int) -> Stride { Stride(0) }
        }
        public func distance(to other: SchedulerTimeType) -> Stride { Stride(0) }
        public func advanced(by n: Stride) -> SchedulerTimeType { self }
    }
    public typealias SchedulerOptions = Never
    public static let shared = ImmediateScheduler()
    public var now: SchedulerTimeType { SchedulerTimeType() }
    public var minimumTolerance: SchedulerTimeType.Stride { SchedulerTimeType.Stride(0) }
    public func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) { action() }
    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?, _ action: @escaping () -> Void) { action() }
    public func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride,
                         options: SchedulerOptions?, _ action: @escaping () -> Void) -> Cancellable { action(); return AnyCancellable {} }
}
