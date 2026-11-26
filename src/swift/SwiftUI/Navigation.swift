// Navigation: NavigationStack, NavigationPath, NavigationLink, navigationDestination, NavigationSplitView, the older
// NavigationView, styles and titles, with the declarations of Apple's SwiftUI.
// A navigation container puts a navigator (_MWNavigator) in the environment of what it shows; links push entries on it
// (a destination view, or a value for a navigationDestination(for:)). A stack shows its top entry under a bar with a
// back button; a split view shows what a column's link chose in the next column. navigationTitle sets the window's
// title (_mwApplyTitle, after each update).
import Foundation
import AppKit

// MARK: - the navigator

/// what a link pushes: the link's destination view (keyed by the link's place), or a value
enum _MWNavEntry {
    case view(String, () -> AnyView)
    case value(AnyHashable)
    var key: String? { if case .view(let k, _) = self { return k }; return nil }
    var value: AnyHashable? { if case .value(let v) = self { return v }; return nil }
}
/// the destinations registered with navigationDestination(for:), shared by the columns of a split view
final class _MWNavRegistry {
    var destinations: [ObjectIdentifier: (AnyHashable) -> AnyView] = [:]
    func view(_ e: _MWNavEntry) -> AnyView? {
        switch e {
        case .view(_, let v): return v()
        case .value(let v): return destinations[ObjectIdentifier(type(of: v.base))]?(v)
        }
    }
}
final class _MWNavigator {
    let registry: _MWNavRegistry
    let push: (_MWNavEntry) -> Void
    /// destinations shown while a binding says so (navigationDestination(isPresented:), (item:), NavigationLink(isActive:))
    var presented: [(key: String, view: () -> AnyView, dismiss: () -> Void)] = []
    /// in a split view: the entry the column's links chose (drawn as selected)
    var chosen: _MWNavEntry?
    init(_ registry: _MWNavRegistry, push: @escaping (_MWNavEntry) -> Void) { self.registry = registry; self.push = push }
    func isChosen(key: String, value: AnyHashable?) -> Bool {
        guard let c = chosen else { return false }
        if let v = value { return c.value == v }
        return c.key == key
    }
}
private struct _MWNavigatorKey: EnvironmentKey { static var defaultValue: _MWNavigator? { nil } }
private struct _MWInListKey: EnvironmentKey { static var defaultValue: Bool { false } }
private struct _MWNavStackStyleKey: EnvironmentKey { static var defaultValue: Bool { false } }
extension EnvironmentValues {
    var _mwNavigator: _MWNavigator? { get { self[_MWNavigatorKey.self] } set { self[_MWNavigatorKey.self] = newValue } }
    /// rows of a List: links are drawn as rows
    var _mwInList: Bool { get { self[_MWInListKey.self] } set { self[_MWInListKey.self] = newValue } }
    /// navigationViewStyle(.stack)
    var _mwNavStackStyle: Bool { get { self[_MWNavStackStyleKey.self] } set { self[_MWNavStackStyleKey.self] = newValue } }
}

/// a stack: `root`, then what was pushed. `values`/`setValues` hold the values of a bound path (nil: the stack keeps its
/// own entries in the host's store under `key`).
func _mwNavStack(_ c: _MWContext, key: String, registry: _MWNavRegistry = _MWNavRegistry(),
                 values: [AnyHashable]? = nil, setValues: (([AnyHashable]) -> Void)? = nil,
                 root: (_MWContext) -> [_MWNode]) -> [_MWNode] {
    let host = c.host
    let own = host.store[key] as? [_MWNavEntry] ?? []   // all entries (own path), or the views pushed over a bound path
    let entries = (values ?? []).map { _MWNavEntry.value($0) } + own
    let nav = _MWNavigator(registry) { [weak host] e in
        guard let host = host else { return }
        if case .value(let v) = e, let vs = values, let set = setValues { set(vs + [v]) }
        else { host.store[key] = (host.store[key] as? [_MWNavEntry] ?? []) + [e] }
        host.setNeedsUpdate()
    }
    var env = c.env
    env._mwNavigator = nav
    env._mwInList = false
    var layers: [[_MWNode]] = [root(c.child("root").with(env: env))]
    for (i, e) in entries.enumerated() {
        let v = registry.view(e)
        if v == nil, let x = e.value { _mwUnsupported(type(of: x.base)) }   // no navigationDestination for its type
        layers.append(v.map { _mwResolve($0, c.child("nav\(i)").with(env: env)) } ?? [])
    }
    var k = 0
    var pops: [() -> Void] = entries.map { _ in { () -> Void in } }
    while k < nav.presented.count {   // (a presented view may present more)
        let p = nav.presented[k]
        layers.append(_mwResolve(p.view(), c.child("pres:\(p.key)").with(env: env)))
        pops.append(p.dismiss)
        k += 1
    }
    guard layers.count > 1 else { return layers[0] }
    let depth = layers.count - 1
    let pop: () -> Void = { [weak host] in
        guard let host = host else { return }
        if depth > entries.count { pops[depth - 1]() }
        else if !own.isEmpty { host.store[key] = Array(own.dropLast()) }
        else if let vs = values, let set = setValues, !vs.isEmpty { set(Array(vs.dropLast())) }
        host.setNeedsUpdate()
    }
    let back = _MWButtonNode(_mwTextNode("‹ " + (_mwNavTitle(layers[depth - 1]) ?? "Back"), size: 13, color: .controlAccentColor), kind: .plain, action: pop)
    back.shortcut = ("[", .command)
    var barItems: [_MWNode] = [back, _MWSpacerNode(nil)]
    if let t = _mwNavTitle(layers[depth]) { barItems += [_mwTextNode(t, size: 13, bold: true), _MWSpacerNode(nil)] }
    let bar = _MWPaddingNode(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10), _MWStackNode(.horizontal, spacing: 8, cross: .center, barItems))
    let page = _MWFrameNode(_mwOne(layers[depth], axis: .vertical), alignment: .top); page.maxW = .infinity; page.maxH = .infinity
    let barRow = _MWFrameNode(bar, alignment: .leading); barRow.maxW = .infinity
    let divider = _MWDividerNode(); divider.stackAxis = .vertical
    return [_MWStackNode(.vertical, spacing: 0, cross: .center, [barRow, divider, page])]
}
func _mwTextNode(_ s: String, size: CGFloat, bold: Bool = false, color: NSColor = .labelColor) -> _MWNode {
    let f = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    return _MWTextNode(NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color]), lineLimit: 1)
}
/// the navigationTitle in a resolved tree (the last one: the innermost container's)
func _mwNavTitle(_ nodes: [_MWNode]) -> String? {
    var t: String?
    for n in nodes { n.all { if let s = $0.traits["navTitle"] as? String { t = s } } }
    return t
}
/// after an update: the window takes the title of what it shows
func _mwApplyTitle(_ host: _MWHostView) {
    guard let r = host.root, let t = _mwNavTitle([r]), let w = host.window, w.contentView === host || host.superview === w.contentView else { return }
    if w.title != t { w.title = t }
}

// MARK: - NavigationPath

public struct NavigationPath {
    var items: [AnyHashable]
    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }
    /// ponytail: paths are not encoded (nil, as for a path holding values that are not Codable)
    public var codable: NavigationPath.CodableRepresentation? { nil }
    public init() { items = [] }
    public init<S>(_ elements: S) where S: Sequence, S.Element: Hashable { items = elements.map { AnyHashable($0) } }
    public init<S>(_ elements: S) where S: Sequence, S.Element: Decodable, S.Element: Encodable, S.Element: Hashable { items = elements.map { AnyHashable($0) } }
    public init(_ codable: NavigationPath.CodableRepresentation) { items = [] }
    public mutating func append<V>(_ value: V) where V: Hashable { items.append(AnyHashable(value)) }
    public mutating func append<V>(_ value: V) where V: Decodable, V: Encodable, V: Hashable { items.append(AnyHashable(value)) }
    public mutating func removeLast(_ k: Int = 1) { items.removeLast(k) }
    public struct CodableRepresentation: Codable {
        public init(from decoder: any Decoder) throws {}
        public func encode(to encoder: any Encoder) throws {}
    }
}
extension NavigationPath: Equatable {
    public static func == (lhs: NavigationPath, rhs: NavigationPath) -> Bool { lhs.items == rhs.items }
}
extension NavigationPath.CodableRepresentation: Equatable {
    public static func == (lhs: NavigationPath.CodableRepresentation, rhs: NavigationPath.CodableRepresentation) -> Bool { true }
}

// MARK: - NavigationStack

enum _MWNavPath {
    case own
    case bound(get: () -> [AnyHashable], set: ([AnyHashable]) -> Void)
}
public struct NavigationStack<Data, Root>: View where Root: View {
    let root: Root
    let path: _MWNavPath
    public init(@ViewBuilder root: () -> Root) where Data == NavigationPath { self.root = root(); path = .own }
    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) where Data == NavigationPath {
        self.root = root()
        self.path = .bound(get: { path.wrappedValue.items }, set: { path.wrappedValue.items = $0 })
    }
    public init(path: Binding<Data>, @ViewBuilder root: () -> Root) where Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection, Data.Element: Hashable {
        self.root = root()
        self.path = .bound(get: { path.wrappedValue.map { AnyHashable($0) } },
                           set: { path.wrappedValue = Data($0.compactMap { $0.base as? Data.Element }) })
    }
    public var body: some View { EmptyView() }   // (drawn by the engine)
}
extension NavigationStack: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let root = self.root
        switch path {
        case .own: return _mwNavStack(c, key: c.path + "#nav") { _mwResolve(root, $0) }
        case .bound(let get, let set): return _mwNavStack(c, key: c.path + "#nav", values: get(), setValues: set) { _mwResolve(root, $0) }
        }
    }
}

// MARK: - NavigationLink

enum _MWLinkTarget {
    case view(() -> AnyView)
    case value(AnyHashable?)
    case active(Binding<Bool>, () -> AnyView)
}
public struct NavigationLink<Label, Destination>: View where Label: View, Destination: View {
    let label: Label
    let target: _MWLinkTarget
    init(label: Label, target: _MWLinkTarget) { self.label = label; self.target = target }
    @_alwaysEmitIntoClient public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.init(destination: destination(), label: label)
    }
    @_alwaysEmitIntoClient public init(isActive: Binding<Bool>, @ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.init(destination: destination(), isActive: isActive, label: label)
    }
    @_alwaysEmitIntoClient public init<V>(tag: V, selection: Binding<V?>, @ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) where V: Hashable {
        self.init(destination: destination(), tag: tag, selection: selection, label: label)
    }
    public var body: some View { EmptyView() }   // (drawn by the engine)
    public init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.init(label: label(), target: .view({ AnyView(destination) }))
    }
    public init(destination: Destination, isActive: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self.init(label: label(), target: .active(isActive, { AnyView(destination) }))
    }
    public init<V>(destination: Destination, tag: V, selection: Binding<V?>, @ViewBuilder label: () -> Label) where V: Hashable {
        let active = Binding<Bool>(get: { selection.wrappedValue == tag }, set: { selection.wrappedValue = $0 ? tag : nil })
        self.init(label: label(), target: .active(active, { AnyView(destination) }))
    }
}
extension NavigationLink where Label == Text {
    @_alwaysEmitIntoClient public init(_ titleKey: LocalizedStringKey, @ViewBuilder destination: () -> Destination) {
        self.init(titleKey, destination: destination())
    }
    @_disfavoredOverload @_alwaysEmitIntoClient public init<S>(_ title: S, @ViewBuilder destination: () -> Destination) where S: StringProtocol {
        self.init(title, destination: destination())
    }
    @_alwaysEmitIntoClient public init(_ titleKey: LocalizedStringKey, isActive: Binding<Bool>, @ViewBuilder destination: () -> Destination) {
        self.init(titleKey, destination: destination(), isActive: isActive)
    }
    @_disfavoredOverload @_alwaysEmitIntoClient public init<S>(_ title: S, isActive: Binding<Bool>, @ViewBuilder destination: () -> Destination) where S: StringProtocol {
        self.init(title, destination: destination(), isActive: isActive)
    }
    @_alwaysEmitIntoClient public init<V>(_ titleKey: LocalizedStringKey, tag: V, selection: Binding<V?>, @ViewBuilder destination: () -> Destination) where V: Hashable {
        self.init(titleKey, destination: destination(), tag: tag, selection: selection)
    }
    @_disfavoredOverload @_alwaysEmitIntoClient public init<S, V>(_ title: S, tag: V, selection: Binding<V?>, @ViewBuilder destination: () -> Destination) where S: StringProtocol, V: Hashable {
        self.init(title, destination: destination(), tag: tag, selection: selection)
    }
    public init(_ titleKey: LocalizedStringKey, destination: Destination) { self.init(destination: destination) { Text(titleKey) } }
    @_disfavoredOverload public init<S>(_ title: S, destination: Destination) where S: StringProtocol { self.init(destination: destination) { Text(title) } }
    public init(_ titleKey: LocalizedStringKey, destination: Destination, isActive: Binding<Bool>) {
        self.init(destination: destination, isActive: isActive) { Text(titleKey) }
    }
    @_disfavoredOverload public init<S>(_ title: S, destination: Destination, isActive: Binding<Bool>) where S: StringProtocol {
        self.init(destination: destination, isActive: isActive) { Text(title) }
    }
    public init<V>(_ titleKey: LocalizedStringKey, destination: Destination, tag: V, selection: Binding<V?>) where V: Hashable {
        self.init(destination: destination, tag: tag, selection: selection) { Text(titleKey) }
    }
    @_disfavoredOverload public init<S, V>(_ title: S, destination: Destination, tag: V, selection: Binding<V?>) where S: StringProtocol, V: Hashable {
        self.init(destination: destination, tag: tag, selection: selection) { Text(title) }
    }
}
extension NavigationLink where Destination == Never {
    public init<P>(value: P?, @ViewBuilder label: () -> Label) where P: Hashable { self.init(label: label(), target: .value(value.map { AnyHashable($0) })) }
    public init<P>(_ titleKey: LocalizedStringKey, value: P?) where Label == Text, P: Hashable { self.init(value: value) { Text(titleKey) } }
    @_disfavoredOverload public init<S, P>(_ title: S, value: P?) where Label == Text, S: StringProtocol, P: Hashable { self.init(value: value) { Text(title) } }
    public init<P>(value: P?, @ViewBuilder label: () -> Label) where P: Decodable, P: Encodable, P: Hashable { self.init(label: label(), target: .value(value.map { AnyHashable($0) })) }
    public init<P>(_ titleKey: LocalizedStringKey, value: P?) where Label == Text, P: Decodable, P: Encodable, P: Hashable { self.init(value: value) { Text(titleKey) } }
    @_disfavoredOverload public init<S, P>(_ title: S, value: P?) where Label == Text, S: StringProtocol, P: Decodable, P: Encodable, P: Hashable { self.init(value: value) { Text(title) } }
}
extension NavigationLink {
    public func isDetailLink(_ isDetailLink: Bool) -> some View { self }
}
extension NavigationLink: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let label = self.label
        // outside a navigation container a link only shows its label (SwiftUI draws it disabled)
        guard let nav = c.env._mwNavigator else { return _mwResolve(label, c.child("l")) }
        let key = c.path
        let activate: () -> Void
        var value: AnyHashable?
        switch target {
        case .view(let v): activate = { nav.push(.view(key, v)) }
        case .value(let v): value = v; activate = { if let v = v { nav.push(.value(v)) } }
        case .active(let b, let v):
            if b.wrappedValue { nav.presented.append((key: key, view: v, dismiss: { b.wrappedValue = false })) }
            activate = { b.wrappedValue = true }
        }
        if c.env._mwInList {   // a row of a list: the row is the link, and it is selected while its destination shows
            let row = _MWTapNode([_mwOne(_mwResolve(label, c.child("l")))])
            row.onTap = { _ in activate() }
            if nav.isChosen(key: key, value: value) { row.traits["selected"] = true }
            return [row]
        }
        return _mwResolve(Button(action: activate) { label }, c.child("b"))
    }
}

// MARK: - destinations and titles

struct _MWNavDestination: ViewModifier, _MWModifier {
    typealias Body = Never
    let register: (_MWNavigator, String) -> Void
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
        if let nav = c.env._mwNavigator { register(nav, c.path) }
        return content(c)
    }
}
extension View {
    public func navigationDestination<D, C>(for data: D.Type, @ViewBuilder destination: @escaping (D) -> C) -> some View where D: Hashable, C: View {
        modifier(_MWNavDestination { nav, _ in nav.registry.destinations[ObjectIdentifier(D.self)] = { AnyView(destination($0.base as! D)) } })
    }
    public func navigationDestination<V>(isPresented: Binding<Bool>, @ViewBuilder destination: () -> V) -> some View where V: View {
        let v = destination()
        return modifier(_MWNavDestination { nav, key in
            if isPresented.wrappedValue { nav.presented.append((key: key, view: { AnyView(v) }, dismiss: { isPresented.wrappedValue = false })) }
        })
    }
    public func navigationDestination<D, C>(item: Binding<Optional<D>>, @ViewBuilder destination: @escaping (D) -> C) -> some View where D: Hashable, C: View {
        modifier(_MWNavDestination { nav, key in
            if let d = item.wrappedValue { nav.presented.append((key: key, view: { AnyView(destination(d)) }, dismiss: { item.wrappedValue = nil })) }
        })
    }
    public func navigationTitle(_ title: Text) -> some View { modifier(_MWWrap { n, _ in n.traits["navTitle"] = title._mwPlain; return n }) }
    public func navigationTitle(_ titleKey: LocalizedStringKey) -> some View { navigationTitle(Text(titleKey)) }
    @_disfavoredOverload public func navigationTitle<S>(_ title: S) -> some View where S: StringProtocol { navigationTitle(Text(title)) }
    public func navigationTitle<V>(@ViewBuilder _ title: () -> V) -> some View where V: View {
        let t = title()
        return modifier(_MWWrap { n, c in n.traits["navTitle"] = _mwOne(_mwResolve(t, c.child("title"))).text ?? ""; return n })
    }
    public func navigationTitle(_ title: Binding<String>) -> some View { navigationTitle(Text(title.wrappedValue)) }
    /// ponytail: subtitles are not shown
    public func navigationSubtitle(_ subtitle: Text) -> some View { self }
    public func navigationSubtitle(_ subtitleKey: LocalizedStringKey) -> some View { self }
    @_disfavoredOverload public func navigationSubtitle<S>(_ subtitle: S) -> some View where S: StringProtocol { self }
    public func navigationSplitViewColumnWidth(_ width: CGFloat) -> some View {
        modifier(_MWWrap { n, _ in n.traits["navColumnWidth"] = width; return n })
    }
    public func navigationSplitViewColumnWidth(min: CGFloat? = nil, ideal: CGFloat, max: CGFloat? = nil) -> some View {
        modifier(_MWWrap { n, _ in n.traits["navColumnWidth"] = ideal; return n })
    }
    public func navigationSplitViewStyle<S>(_ style: S) -> some View where S: NavigationSplitViewStyle { self }
    public func navigationViewStyle<S>(_ style: S) -> some View where S: NavigationViewStyle {
        transformEnvironment(\._mwNavStackStyle) { $0 = style is StackNavigationViewStyle }
    }
}

// MARK: - split views

public struct NavigationSplitViewVisibility: Equatable, Codable, Sendable {
    let role: Int   // 0 automatic, 1 all, 2 double column, 3 detail only
    public static var detailOnly: NavigationSplitViewVisibility { NavigationSplitViewVisibility(role: 3) }
    public static var doubleColumn: NavigationSplitViewVisibility { NavigationSplitViewVisibility(role: 2) }
    public static var all: NavigationSplitViewVisibility { NavigationSplitViewVisibility(role: 1) }
    public static var automatic: NavigationSplitViewVisibility { NavigationSplitViewVisibility(role: 0) }
    init(role: Int) { self.role = role }
    public static func == (lhs: NavigationSplitViewVisibility, rhs: NavigationSplitViewVisibility) -> Bool { lhs.role == rhs.role }
    public func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(role) }
    public init(from decoder: any Decoder) throws { role = try decoder.singleValueContainer().decode(Int.self) }
}
public struct NavigationSplitViewColumn: Hashable, Sendable {
    let column: Int
    public static var sidebar: NavigationSplitViewColumn { NavigationSplitViewColumn(column: 0) }
    public static var content: NavigationSplitViewColumn { NavigationSplitViewColumn(column: 1) }
    public static var detail: NavigationSplitViewColumn { NavigationSplitViewColumn(column: 2) }
    init(column: Int) { self.column = column }
    public static func == (a: NavigationSplitViewColumn, b: NavigationSplitViewColumn) -> Bool { a.column == b.column }
    public func hash(into hasher: inout Hasher) { hasher.combine(column) }
    public var hashValue: Int { column.hashValue }
}

public struct NavigationSplitView<Sidebar, Content, Detail>: View where Sidebar: View, Content: View, Detail: View {
    let sidebar: Sidebar, content: Content?, detail: Detail
    let visibility: Binding<NavigationSplitViewVisibility>?
    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar(); self.content = content(); self.detail = detail(); visibility = nil
    }
    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar(); self.content = content(); self.detail = detail(); visibility = columnVisibility
    }
    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.sidebar = sidebar(); content = nil; self.detail = detail(); visibility = nil
    }
    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.sidebar = sidebar(); content = nil; self.detail = detail(); visibility = columnVisibility
    }
    public var body: some View { EmptyView() }   // (drawn by the engine)
}
extension NavigationSplitView {
    /// (the compact column matters on iPhone only)
    public init(preferredCompactColumn: Binding<NavigationSplitViewColumn>, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.init(sidebar: sidebar, content: content, detail: detail)
    }
    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, preferredCompactColumn: Binding<NavigationSplitViewColumn>, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.init(columnVisibility: columnVisibility, sidebar: sidebar, content: content, detail: detail)
    }
    public init(preferredCompactColumn: Binding<NavigationSplitViewColumn>, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.init(sidebar: sidebar, detail: detail)
    }
    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, preferredCompactColumn: Binding<NavigationSplitViewColumn>, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.init(columnVisibility: columnVisibility, sidebar: sidebar, detail: detail)
    }
}
extension NavigationSplitView: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let sidebar = self.sidebar, content = self.content, detail = self.detail
        return _mwSplit(c, visibility: visibility?.wrappedValue ?? .automatic,
                        sidebar: { _mwResolve(sidebar, $0) },
                        content: content.map { v -> (_MWContext) -> [_MWNode] in { _mwResolve(v, $0) } },
                        detail: { _mwResolve(detail, $0) })
    }
}
/// columns side by side: a link in a column shows its destination in the next one; the detail column is a stack
func _mwSplit(_ c: _MWContext, visibility: NavigationSplitViewVisibility, sidebar: (_MWContext) -> [_MWNode],
              content: ((_MWContext) -> [_MWNode])?, detail: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] {
    let host = c.host, key = c.path + "#split"
    let registry = _MWNavRegistry()
    let sideChoice = host.store[key + "s"] as? _MWNavEntry, contentChoice = host.store[key + "c"] as? _MWNavEntry
    func navigator(_ store: String, resets: [String]) -> _MWNavigator {
        _MWNavigator(registry) { [weak host] e in
            guard let host = host else { return }
            host.store[store] = e
            for r in resets { host.store[r] = nil }
            host.setNeedsUpdate()
        }
    }
    var env = c.env
    env._mwInList = false
    // the sidebar's links choose what the content column (or, with two columns, the detail column) shows
    let sideNav = navigator(key + "s", resets: [key + "c", key + "#detail"])
    sideNav.chosen = sideChoice
    env._mwNavigator = sideNav
    let sideNodes = sidebar(c.child("sidebar").with(env: env))
    let sidePick: _MWNavEntry? = sideNav.presented.last.map { p in _MWNavEntry.view(p.key, p.view) } ?? sideChoice
    var columns: [(nodes: [_MWNode], width: CGFloat?)] = []
    let all = visibility.role == 0 || visibility.role == 1
    let showSidebar = all || (visibility.role == 2 && content == nil)
    if showSidebar { columns.append((sideNodes, _mwColumnWidth(sideNodes) ?? 200)) }
    var detailPick = sidePick
    if let content = content {
        let contentNav = navigator(key + "c", resets: [key + "#detail"])
        contentNav.chosen = contentChoice
        env._mwNavigator = contentNav
        let cc = c.child("content").with(env: env)
        let nodes = sidePick.flatMap { registry.view($0) }.map { _mwResolve($0, cc) } ?? content(cc)
        detailPick = contentNav.presented.last.map { p in _MWNavEntry.view(p.key, p.view) } ?? contentChoice
        if visibility.role != 3 { columns.append((nodes, _mwColumnWidth(nodes) ?? 260)) }
    }
    env._mwNavigator = nil
    let detailNodes = _mwNavStack(c.child("detail").with(env: env), key: key + "#detail", registry: registry) { dc in
        detailPick.flatMap { registry.view($0) }.map { _mwResolve($0, dc) } ?? detail(dc)
    }
    var row: [_MWNode] = []
    for col in columns {
        let f = _MWFrameNode(_mwOne(col.nodes, axis: .vertical), alignment: .topLeading)
        f.fixedW = col.width; f.maxH = .infinity
        let shade = _MWDrawNode(ideal: nil) { g, r in CGContextSetFillColorWithColor(g, NSColor(white: 0.5, alpha: 0.08).cgColor); CGContextFillRect(g, r) }
        row.append(_MWDecorNode(f, below: [shade], above: [], alignment: .center))
        let d = _MWDividerNode(); row.append(d)
    }
    let main = _MWFrameNode(_mwOne(detailNodes, axis: .vertical), alignment: .center)
    main.maxW = .infinity; main.maxH = .infinity
    row.append(main)
    return [_MWStackNode(.horizontal, spacing: 0, cross: .center, row)]
}
func _mwColumnWidth(_ nodes: [_MWNode]) -> CGFloat? {
    var w: CGFloat?
    for n in nodes { n.all { if w == nil, let x = $0.traits["navColumnWidth"] as? CGFloat { w = x } } }
    return w
}

// MARK: - NavigationView (before macOS 13): a split view with its views as columns, or a stack

public struct NavigationView<Content>: View where Content: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public typealias Body = Never
    public var body: Never { _primitive("NavigationView") }
}
extension NavigationView: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        var views: [Any] = [content]
        if let t = content as? _MWTupleValue { views = t._mwElements }
        if views.count < 2 || c.env._mwNavStackStyle {
            let content = self.content
            return _mwNavStack(c, key: c.path + "#nav") { _mwResolve(content, $0) }
        }
        let first = views[0], last = views[views.count - 1]
        let middle: Any? = views.count > 2 ? views[1] : nil
        return _mwSplit(c, visibility: .automatic, sidebar: { _mwResolveAny(first, $0) },
                        content: middle.map { m -> (_MWContext) -> [_MWNode] in { _mwResolveAny(m, $0) } }, detail: { _mwResolveAny(last, $0) })
    }
}
/// the views of a TupleView
protocol _MWTupleValue { var _mwElements: [Any] { get } }
extension TupleView: _MWTupleValue {
    var _mwElements: [Any] {
        let m = Mirror(reflecting: value)
        return m.displayStyle == .tuple ? m.children.map { $0.value } : [value]
    }
}

// MARK: - styles

public protocol NavigationSplitViewStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = NavigationSplitViewStyleConfiguration
}
public struct NavigationSplitViewStyleConfiguration {}
public struct AutomaticNavigationSplitViewStyle: NavigationSplitViewStyle {
    public init() {}
    public func makeBody(configuration: AutomaticNavigationSplitViewStyle.Configuration) -> some View { EmptyView() }
}
public struct BalancedNavigationSplitViewStyle: NavigationSplitViewStyle {
    public init() {}
    public func makeBody(configuration: BalancedNavigationSplitViewStyle.Configuration) -> some View { EmptyView() }
}
public struct ProminentDetailNavigationSplitViewStyle: NavigationSplitViewStyle {
    public init() {}
    public func makeBody(configuration: ProminentDetailNavigationSplitViewStyle.Configuration) -> some View { EmptyView() }
}
extension NavigationSplitViewStyle where Self == AutomaticNavigationSplitViewStyle {
    public static var automatic: AutomaticNavigationSplitViewStyle { AutomaticNavigationSplitViewStyle() }
}
extension NavigationSplitViewStyle where Self == BalancedNavigationSplitViewStyle {
    public static var balanced: BalancedNavigationSplitViewStyle { BalancedNavigationSplitViewStyle() }
}
extension NavigationSplitViewStyle where Self == ProminentDetailNavigationSplitViewStyle {
    public static var prominentDetail: ProminentDetailNavigationSplitViewStyle { ProminentDetailNavigationSplitViewStyle() }
}

public struct _NavigationViewStyleConfiguration {
    public struct Content: View {
        public typealias Body = Never
        public var body: Never { _primitive("_NavigationViewStyleConfiguration.Content") }
    }
    public let content: _NavigationViewStyleConfiguration.Content
}
public protocol NavigationViewStyle {
    associatedtype _Body: View
    @ViewBuilder func _body(configuration: _NavigationViewStyleConfiguration) -> Self._Body
    associatedtype _Body2: View = EmptyView
    @ViewBuilder func _columnBasedBody(configuration: _NavigationViewStyleConfiguration) -> Self._Body2
}
extension NavigationViewStyle {
    public func _columnBasedBody(configuration: _NavigationViewStyleConfiguration) -> Self._Body2 { fatalError("_columnBasedBody") }
}
public struct DefaultNavigationViewStyle: NavigationViewStyle {
    public init() {}
    public func _body(configuration: _NavigationViewStyleConfiguration) -> some View { configuration.content }
    public func _columnBasedBody(configuration: _NavigationViewStyleConfiguration) -> some View { configuration.content }
}
public struct ColumnNavigationViewStyle: NavigationViewStyle {
    @usableFromInline internal init() {}
    public func _body(configuration: _NavigationViewStyleConfiguration) -> some View { configuration.content }
    public func _columnBasedBody(configuration: _NavigationViewStyleConfiguration) -> some View { configuration.content }
}
public struct DoubleColumnNavigationViewStyle: NavigationViewStyle {
    public init() {}
    public func _body(configuration: _NavigationViewStyleConfiguration) -> some View { configuration.content }
    public func _columnBasedBody(configuration: _NavigationViewStyleConfiguration) -> some View { configuration.content }
}
public struct StackNavigationViewStyle: NavigationViewStyle {
    public init() {}
    public func _body(configuration: _NavigationViewStyleConfiguration) -> some View { configuration.content }
    public func _columnBasedBody(configuration: _NavigationViewStyleConfiguration) -> some View { configuration.content }
}
extension NavigationViewStyle where Self == DefaultNavigationViewStyle {
    @_alwaysEmitIntoClient public static var automatic: DefaultNavigationViewStyle { .init() }
}
extension NavigationViewStyle where Self == ColumnNavigationViewStyle {
    @_alwaysEmitIntoClient public static var columns: ColumnNavigationViewStyle { .init() }
}
extension NavigationViewStyle where Self == StackNavigationViewStyle {
    @_alwaysEmitIntoClient public static var stack: StackNavigationViewStyle { .init() }
}
