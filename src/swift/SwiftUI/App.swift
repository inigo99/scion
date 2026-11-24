// Apps and scenes, commands, the AppKit bridges (NSHostingView, NSHostingController, NSViewRepresentable) and the
// hosting view's presentation helpers (alerts, sheets, popovers, onAppear/onChange/onReceive bookkeeping).
import Foundation
import AppKit
import Combine
import os

// MARK: - scenes

public struct _SceneInputs {}
public struct _SceneOutputs {}
public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }
    static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs
}
extension Scene {
    public static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs { _SceneOutputs() }
}
extension Never: Scene {}

/// what the app opens: windows, the settings window and menus
final class _MWSceneList {
    var windows: [(title: String, style: Int, make: () -> AnyView)] = []
    var settings: (() -> AnyView)?
    var menus: [_MWCommandMenu] = []
    var hiddenTitleBar = false
}
protocol _MWScene { func _mwCollect(_ l: _MWSceneList) }
func _mwCollectScene<S: Scene>(_ s: S, _ l: _MWSceneList) {
    if let p = s as? _MWScene { p._mwCollect(l); return }
    if S.Body.self == Never.self { return }
    _mwCollectScene(s.body, l)
}

@resultBuilder public struct SceneBuilder {
    public static func buildBlock() -> _EmptyScene { _EmptyScene() }
    public static func buildBlock<Content>(_ content: Content) -> Content where Content: Scene { content }
    @_alwaysEmitIntoClient public static func buildExpression<Content>(_ content: Content) -> Content where Content: Scene { content }
    @_alwaysEmitIntoClient public static func buildBlock<each Content>(_ content: repeat each Content) -> _TupleScene<(repeat each Content)> where repeat each Content: Scene {
        _TupleScene((repeat each content))
    }
}
@frozen public struct _EmptyScene: Scene, _MWScene {
    @inlinable public init() {}
    public typealias Body = Never
    public var body: Never { _primitive("_EmptyScene") }
    func _mwCollect(_ l: _MWSceneList) {}
}
@frozen public struct _TupleScene<T>: Scene, _MWScene {
    public var value: T
    public init(_ value: T) { self.value = value }
    public typealias Body = Never
    public var body: Never { _primitive("_TupleScene") }
    func _mwCollect(_ l: _MWSceneList) {
        for ch in Mirror(reflecting: value).children { if let s = ch.value as? any Scene { _mwCollectScene(s, l) } }
    }
}

public struct WindowGroup<Content>: Scene, _MWScene where Content: View {
    let title: String, content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) { title = ""; self.content = content }
    public init(_ title: Text, @ViewBuilder content: @escaping () -> Content) { self.title = title._mwPlain; self.content = content }
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) { title = Text(titleKey)._mwPlain; self.content = content }
    public init<S>(_ title: S, @ViewBuilder content: @escaping () -> Content) where S: StringProtocol { self.title = String(title); self.content = content }
    public init(id: String, @ViewBuilder content: @escaping () -> Content) { title = ""; self.content = content }
    public init<S>(_ title: S, id: String, @ViewBuilder content: @escaping () -> Content) where S: StringProtocol { self.title = String(title); self.content = content }
    public typealias Body = Never
    public var body: Never { _primitive("WindowGroup") }
    func _mwCollect(_ l: _MWSceneList) { let c = content; l.windows.append((title, 0, { AnyView(c()) })) }
}

public struct Settings<Content>: Scene, _MWScene where Content: View {
    let content: () -> Content
    public init(@ViewBuilder content: () -> Content) { let c = content(); self.content = { c } }
    public typealias Body = Never
    public var body: Never { _primitive("Settings") }
    func _mwCollect(_ l: _MWSceneList) { let c = content; l.settings = { AnyView(c()) } }
}

public struct MenuBarExtra<Label, Content>: Scene, _MWScene where Label: View, Content: View {
    let title: String, image: String?, content: () -> Content
    public typealias Body = Never
    public var body: Never { _primitive("MenuBarExtra") }
    func _mwCollect(_ l: _MWSceneList) {
        let item = NSStatusBar.system.statusItem(withLength: -1)
        if let i = image { item.button?.image = NSImage(systemSymbolName: i, accessibilityDescription: title) } else { item.button?.title = title }
        let c = content
        let target = _MWMenuTarget {
            guard let b = item.button, let w = b.window else { return }
            _MWPopoverWindow.toggle(key: "menubarextra", near: w.frame) { AnyView(c()) }
        }
        _mwKeepAlive.append(target)
        item.button?.target = target
        item.button?.action = #selector(_MWMenuTarget.fire(_:))
        _mwKeepAlive.append(item)
    }
}
extension MenuBarExtra where Label == Text {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: @escaping () -> Content) { title = Text(titleKey)._mwPlain; image = systemImage; self.content = content }
    public init<S>(_ title: S, systemImage: String, @ViewBuilder content: @escaping () -> Content) where S: StringProtocol { self.title = String(title); image = systemImage; self.content = content }
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) { title = Text(titleKey)._mwPlain; image = nil; self.content = content }
}
nonisolated(unsafe) var _mwKeepAlive: [AnyObject] = []

public protocol WindowStyle {}
public struct DefaultWindowStyle: WindowStyle { public init() {} }
public struct HiddenTitleBarWindowStyle: WindowStyle { public init() {} }
public struct TitleBarWindowStyle: WindowStyle { public init() {} }
extension WindowStyle where Self == HiddenTitleBarWindowStyle { public static var hiddenTitleBar: HiddenTitleBarWindowStyle { HiddenTitleBarWindowStyle() } }

struct _MWModifiedScene<Content: Scene>: Scene, _MWScene {
    let content: Content
    let apply: (_MWSceneList) -> Void
    typealias Body = Never
    var body: Never { _primitive("scene") }
    func _mwCollect(_ l: _MWSceneList) { _mwCollectScene(content, l); apply(l) }
}
extension Scene {
    public func windowStyle<S>(_ style: S) -> some Scene where S: WindowStyle {
        _MWModifiedScene(content: self) { $0.hiddenTitleBar = style is HiddenTitleBarWindowStyle }
    }
    public func commands<Content>(@CommandsBuilder content: () -> Content) -> some Scene where Content: Commands {
        let c = content()
        return _MWModifiedScene(content: self) { l in var r = _ResolvedCommands(); c._resolve(into: &r); l.menus += r.menus }
    }
    public func defaultSize(width: CGFloat, height: CGFloat) -> some Scene { self }
    public func windowResizability(_ r: WindowResizability) -> some Scene { self }
}
public struct WindowResizability: Sendable {
    public static let automatic = WindowResizability(), contentSize = WindowResizability(), contentMinSize = WindowResizability()
}

// MARK: - commands

public struct _CommandsInputs {}
public struct _CommandsOutputs {}
final class _MWCommandMenu {
    let title: String, items: () -> AnyView
    init(_ t: String, _ i: @escaping () -> AnyView) { title = t; items = i }
}
public struct _ResolvedCommands {
    var menus: [_MWCommandMenu] = []
}
public protocol Commands {
    associatedtype Body: Commands
    @CommandsBuilder var body: Self.Body { get }
    static func _makeCommands(content: _GraphValue<Self>, inputs: _CommandsInputs) -> _CommandsOutputs
    func _resolve(into resolved: inout _ResolvedCommands)
}
extension Commands {
    public static func _makeCommands(content: _GraphValue<Self>, inputs: _CommandsInputs) -> _CommandsOutputs { _CommandsOutputs() }
    public func _resolve(into resolved: inout _ResolvedCommands) {
        if Body.self != Never.self { body._resolve(into: &resolved) }
    }
}
extension Never: Commands {}
@resultBuilder public struct CommandsBuilder {
    public static func buildBlock() -> EmptyCommands { EmptyCommands() }
    public static func buildBlock<C>(_ c: C) -> C where C: Commands { c }
    @_alwaysEmitIntoClient public static func buildBlock<each C>(_ c: repeat each C) -> _MWTupleCommands<(repeat each C)> where repeat each C: Commands {
        _MWTupleCommands((repeat each c))
    }
}
public struct _MWTupleCommands<T>: Commands {
    let value: T
    public init(_ v: T) { value = v }
    public typealias Body = Never
    public var body: Never { _primitive("commands") }
    public func _resolve(into r: inout _ResolvedCommands) {
        for ch in Mirror(reflecting: value).children { (ch.value as? any Commands)?._resolve(into: &r) }
    }
}
public struct EmptyCommands: Commands {
    public init() {}
    public typealias Body = Never
    public var body: Never { _primitive("EmptyCommands") }
    public func _resolve(into resolved: inout _ResolvedCommands) {}
}
public struct CommandMenu<Content>: Commands where Content: View {
    let name: String, content: () -> Content
    public init(_ name: Text, @ViewBuilder content: () -> Content) { self.name = name._mwPlain; let c = content(); self.content = { c } }
    public init(_ nameKey: LocalizedStringKey, @ViewBuilder content: () -> Content) { self.init(Text(nameKey), content: content) }
    public init<S>(_ name: S, @ViewBuilder content: () -> Content) where S: StringProtocol { self.init(Text(name), content: content) }
    public typealias Body = Never
    public var body: Never { _primitive("CommandMenu") }
    public func _resolve(into r: inout _ResolvedCommands) { let c = content; r.menus.append(_MWCommandMenu(name) { AnyView(c()) }) }
}
public struct CommandGroupPlacement {
    let name: String
    public static let appInfo = CommandGroupPlacement(name: "appInfo"), appSettings = CommandGroupPlacement(name: "appSettings")
    public static let systemServices = CommandGroupPlacement(name: "systemServices"), appVisibility = CommandGroupPlacement(name: "appVisibility")
    public static let appTermination = CommandGroupPlacement(name: "appTermination"), newItem = CommandGroupPlacement(name: "newItem")
    public static let saveItem = CommandGroupPlacement(name: "saveItem"), importExport = CommandGroupPlacement(name: "importExport")
    public static let printItem = CommandGroupPlacement(name: "printItem"), undoRedo = CommandGroupPlacement(name: "undoRedo")
    public static let pasteboard = CommandGroupPlacement(name: "pasteboard"), textEditing = CommandGroupPlacement(name: "textEditing")
    public static let textFormatting = CommandGroupPlacement(name: "textFormatting"), toolbar = CommandGroupPlacement(name: "toolbar")
    public static let sidebar = CommandGroupPlacement(name: "sidebar"), windowSize = CommandGroupPlacement(name: "windowSize")
    public static let windowArrangement = CommandGroupPlacement(name: "windowArrangement"), help = CommandGroupPlacement(name: "help")
}
public struct CommandGroup<Content>: Commands where Content: View {
    let content: () -> Content
    public init(before group: CommandGroupPlacement, @ViewBuilder addition: () -> Content) { let c = addition(); content = { c } }
    public init(after group: CommandGroupPlacement, @ViewBuilder addition: () -> Content) { let c = addition(); content = { c } }
    public init(replacing group: CommandGroupPlacement, @ViewBuilder addition: () -> Content) { let c = addition(); content = { c } }
    public typealias Body = Never
    public var body: Never { _primitive("CommandGroup") }
    public func _resolve(into r: inout _ResolvedCommands) {}   // ponytail: additions to the standard menus are not shown
}
public struct SidebarCommands: Commands { public init() {}; public typealias Body = Never; public var body: Never { _primitive("SidebarCommands") }; public func _resolve(into r: inout _ResolvedCommands) {} }
public struct TextEditingCommands: Commands { public init() {}; public typealias Body = Never; public var body: Never { _primitive("TextEditingCommands") }; public func _resolve(into r: inout _ResolvedCommands) {} }

// MARK: - App

public protocol App {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }
    @MainActor @preconcurrency init()
}
nonisolated(unsafe) var _mwAppDelegate: NSObject?
extension App {
    @MainActor @preconcurrency public static func main() {
        let nsApp = NSApplication.shared
        let app = Self()
        if let d = _mwAppDelegate as? NSApplicationDelegate { nsApp.delegate = d }
        let scenes = _MWSceneList()
        _mwCollectScene(app.body, scenes)
        _mwInstallMenus(scenes)
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(forName: NSNotification.Name("NSApplicationDidFinishLaunchingNotification"), object: nil, queue: nil) { _ in
            if let t = token { NotificationCenter.default.removeObserver(t) }
            for w in scenes.windows { _mwOpenWindow(w.title, hiddenTitleBar: scenes.hiddenTitleBar, w.make()) }
        }
        _mwKeepAlive.append(scenes)
        nsApp.run()
    }
}
@discardableResult func _mwOpenWindow(_ title: String, hiddenTitleBar: Bool, _ v: AnyView) -> NSWindow {
    let host = NSHostingView(rootView: v)
    let size = host.fittingSize
    let w: NSWindow = NSWindow(contentRect: NSRect(x: 200, y: 200, width: max(size.width, 200), height: max(size.height, 100)),
                     styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    w.title = title.isEmpty ? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "") : title
    w.contentView = host
    w.center()
    w.makeKeyAndOrderFront(nil)
    _mwKeepAlive.append(w)
    return w
}
func _mwInstallMenus(_ s: _MWSceneList) {
    guard !s.menus.isEmpty || s.settings != nil else { return }
    let main = NSApplication.shared.mainMenu ?? NSMenu(title: "")
    if let settings = s.settings {
        _mwSettings = settings
        let t = _MWMenuTarget { _mwOpenSettings() }
        _mwKeepAlive.append(t)
        let it: NSMenuItem = NSMenuItem(title: "Settings…", action: #selector(_MWMenuTarget.fire(_:)), keyEquivalent: ",")
        it.target = t
        if let app = main.items.first?.submenu { app.insertItem(it, at: min(2, app.numberOfItems)) } else {
            let appItem: NSMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: ""); appItem.submenu = NSMenu(title: ""); appItem.submenu?.addItem(it); main.addItem(appItem)
        }
    }
    for m in s.menus {
        let host = NSHostingView(rootView: m.items())
        let it: NSMenuItem = NSMenuItem(title: m.title, action: nil, keyEquivalent: "")
        it.submenu = _mwMenu(host.host.root.map { [$0] } ?? [])
        it.submenu?.title = m.title
        main.addItem(it)
        _mwKeepAlive.append(host)
    }
    NSApplication.shared.mainMenu = main
}

@propertyWrapper public struct NSApplicationDelegateAdaptor<DelegateType>: DynamicProperty where DelegateType: NSObject, DelegateType: NSApplicationDelegate {
    public var wrappedValue: DelegateType { _mwAppDelegate as! DelegateType }
    public init(_ delegateType: DelegateType.Type = DelegateType.self) {
        if _mwAppDelegate == nil { _mwAppDelegate = delegateType.init() }
    }

}


// MARK: - logging (apps' inlined SwiftUI code warns through it)

@usableFromInline enum Log {
    @usableFromInline static var runtimeIssuesLog: OSLog { OSLog(subsystem: "com.apple.SwiftUI", category: "RuntimeIssues") }
}

// MARK: - hosting

@MainActor @preconcurrency open class NSHostingView<Content>: NSView where Content: View {
    let host: _MWHostView
    private var _rootView: Content
    public var rootView: Content {
        get { _rootView }
        set { _rootView = newValue; host.update() }
    }
    public required init(rootView: Content) {
        _rootView = rootView
        host = _MWHostView(frame: .zero)
        super.init(frame: .zero)
        _mwSetUp()
    }
    /// a view presented by another (sheet, popover): it sees its presenter's environment
    init(rootView: Content, environment: EnvironmentValues) {
        _rootView = rootView
        host = _MWHostView(frame: .zero)
        host.environment = environment
        super.init(frame: .zero)
        _mwSetUp()
    }
    private func _mwSetUp() {
        host.resolveRoot = { [unowned self] c in _mwResolve(self._rootView, c) }
        host.autoresizingMask = NSAutoresizingMaskOptions(rawValue: 18)
        addSubview(host)
        host.update()
        let s = host.idealSize
        setFrameSize(NSSize(width: ceil(s.width), height: ceil(s.height)))
        host.frame = bounds
        host.onSizeChange = { [weak self] _ in self?.invalidateIntrinsicContentSize() }
        if ProcessInfo.processInfo.environment["SCION_SWIFTUI_DUMP"] != nil, let r = host.root { print(_mwDump(r), terminator: "") }
    }
    open override var isFlipped: Bool { true }
    open override var intrinsicContentSize: NSSize { host.idealSize }
    open override var fittingSize: NSSize { host.idealSize }
    open override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); host.frame = bounds }
    public func sizeThatFits(in size: CGSize) -> CGSize { host.sizeThatFits(size) }
}

@MainActor @preconcurrency open class NSHostingController<Content>: NSViewController where Content: View {
    let hosting: NSHostingView<Content>
    public var rootView: Content {
        get { hosting.rootView }
        set { hosting.rootView = newValue; preferredContentSize = hosting.fittingSize }
    }
    public init(rootView: Content) {
        hosting = NSHostingView(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
        view = hosting
        preferredContentSize = hosting.fittingSize
        hosting.host.onSizeChange = { [weak self] s in
            self?.hosting.invalidateIntrinsicContentSize()
            self?.preferredContentSize = s
        }
    }
    public func sizeThatFits(in size: CGSize) -> CGSize { hosting.sizeThatFits(in: size) }
}

// MARK: - AppKit views inside SwiftUI

public enum _IdentifiedViewTree {
    case empty
}
public struct NSViewRepresentableContext<Representable> where Representable: NSViewRepresentable {
    public let coordinator: Representable.Coordinator
    public var transaction: Transaction
    public var environment: EnvironmentValues
}
public protocol NSViewRepresentable: View where Self.Body == Never {
    associatedtype NSViewType: NSView
    associatedtype Coordinator = Void
    typealias Context = NSViewRepresentableContext<Self>
    @MainActor @preconcurrency func makeNSView(context: Self.Context) -> Self.NSViewType
    @MainActor @preconcurrency func updateNSView(_ nsView: Self.NSViewType, context: Self.Context)
    @MainActor @preconcurrency static func dismantleNSView(_ nsView: Self.NSViewType, coordinator: Self.Coordinator)
    @MainActor @preconcurrency func makeCoordinator() -> Self.Coordinator
    func _identifiedViewTree(in nsView: Self.NSViewType) -> _IdentifiedViewTree
    func _overrideSizeThatFits(_ size: inout CGSize, in proposedSize: _ProposedSize, nsView: Self.NSViewType)
    func _overrideLayoutTraits(_ layoutTraits: inout _LayoutTraits, for nsView: Self.NSViewType)
    static func _modifyBridgedViewInputs(_ inputs: inout _ViewInputs)
    @MainActor @preconcurrency func sizeThatFits(_ proposal: ProposedViewSize, nsView: Self.NSViewType, context: Self.Context) -> CGSize?
    static func _layoutOptions(_ provider: Self.NSViewType) -> _PlatformViewRepresentableLayoutOptions
    static var _invalidatesSizeOnConstraintChanges: Bool { get }
}
extension NSViewRepresentable {
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: Self.NSViewType, context: Self.Context) -> CGSize? { nil }
    public static func _layoutOptions(_ provider: Self.NSViewType) -> _PlatformViewRepresentableLayoutOptions { [] }
    public static var _invalidatesSizeOnConstraintChanges: Bool { true }
    public static func dismantleNSView(_ nsView: Self.NSViewType, coordinator: Self.Coordinator) {}
    public func _identifiedViewTree(in nsView: Self.NSViewType) -> _IdentifiedViewTree { .empty }
    public func _overrideSizeThatFits(_ size: inout CGSize, in proposedSize: _ProposedSize, nsView: Self.NSViewType) {}
    public func _overrideLayoutTraits(_ layoutTraits: inout _LayoutTraits, for nsView: Self.NSViewType) {}
    public static func _modifyBridgedViewInputs(_ inputs: inout _ViewInputs) {}
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs { _ViewOutputs() }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs { _ViewListOutputs() }
    public var body: Never { _primitive("NSViewRepresentable") }
}
extension NSViewRepresentable where Self.Coordinator == () {
    public func makeCoordinator() -> Self.Coordinator { () }
}
func _mwRepresent<R: NSViewRepresentable>(_ r: R, _ c: _MWContext) -> [_MWNode] {
    var rep = r
    _mwBindProperties(&rep, c)
    let coordKey = c.path + "#coordinator"
    let coordinator: R.Coordinator
    if let co = c.host.store[coordKey] as? R.Coordinator { coordinator = co } else { coordinator = rep.makeCoordinator(); c.host.store[coordKey] = coordinator }
    let ctx = NSViewRepresentableContext<R>(coordinator: coordinator, transaction: Transaction(), environment: c.env)
    let v = c.host.embeddedView(c.path) { rep.makeNSView(context: ctx) }
    rep.updateNSView(v, context: ctx)
    let n = _MWAppKitNode(v)
    n.sizer = { p in
        if let s = rep.sizeThatFits(ProposedViewSize(width: p.width, height: p.height), nsView: v, context: ctx) { return s }
        let ic = v.intrinsicContentSize
        var s = CGSize(width: ic.width > 0 ? ic.width : _mwFinite(p.width, 10), height: ic.height > 0 ? ic.height : _mwFinite(p.height, 10))
        rep._overrideSizeThatFits(&s, in: _ProposedSize(width: p.width, height: p.height), nsView: v)
        return s
    }
    return [n]
}

public struct NSViewControllerRepresentableContext<Representable> where Representable: NSViewControllerRepresentable {
    public let coordinator: Representable.Coordinator
    public var transaction: Transaction
    public var environment: EnvironmentValues
}
public protocol NSViewControllerRepresentable: View where Self.Body == Never {
    associatedtype NSViewControllerType: NSViewController
    associatedtype Coordinator = Void
    typealias Context = NSViewControllerRepresentableContext<Self>
    func makeNSViewController(context: Self.Context) -> Self.NSViewControllerType
    func updateNSViewController(_ nsViewController: Self.NSViewControllerType, context: Self.Context)
    static func dismantleNSViewController(_ nsViewController: Self.NSViewControllerType, coordinator: Self.Coordinator)
    func makeCoordinator() -> Self.Coordinator
}
extension NSViewControllerRepresentable {
    public static func dismantleNSViewController(_ nsViewController: Self.NSViewControllerType, coordinator: Self.Coordinator) {}
    public var body: Never { _primitive("NSViewControllerRepresentable") }
}
extension NSViewControllerRepresentable where Self.Coordinator == () {
    public func makeCoordinator() -> Self.Coordinator { () }
}
func _mwRepresentController<R: NSViewControllerRepresentable>(_ r: R, _ c: _MWContext) -> [_MWNode] {
    let coordKey = c.path + "#coordinator", vcKey = c.path + "#vc"
    let coordinator: R.Coordinator
    if let co = c.host.store[coordKey] as? R.Coordinator { coordinator = co } else { coordinator = r.makeCoordinator(); c.host.store[coordKey] = coordinator }
    let ctx = NSViewControllerRepresentableContext<R>(coordinator: coordinator, transaction: Transaction(), environment: c.env)
    let vc: R.NSViewControllerType
    if let v = c.host.store[vcKey] as? R.NSViewControllerType { vc = v } else { vc = r.makeNSViewController(context: ctx); c.host.store[vcKey] = vc }
    r.updateNSViewController(vc, context: ctx)
    return [_MWAppKitNode(c.host.embeddedView(c.path) { vc.view })]
}

// MARK: - the host's bookkeeping for modifiers

extension _MWHostView {
    nonisolated(unsafe) static var current: _MWHostView?
    func appeared(_ path: String, _ action: @escaping () -> Void) {
        let k = path + "#appeared"
        guard store[k] == nil else { return }
        store[k] = true
        DispatchQueue.main.async(execute: action)
    }
    func changed<V: Equatable>(_ path: String, _ value: V, _ action: @escaping (V) -> Void) {
        let k = path + "#changed"
        if let old = store[k] as? V, old != value { DispatchQueue.main.async { action(value) } }
        store[k] = value
    }
    func subscribe<P: Publisher>(_ path: String, _ p: P, _ action: @escaping (P.Output) -> Void) where P.Failure == Never {
        let k = path + "#sub"
        if let box = store[k] as? _MWActionBox<P.Output> { box.action = action; return }
        let box = _MWActionBox(action)
        box.cancellable = p.sink { [weak box] v in box?.action(v) }
        store[k] = box
    }
    func presentOnce(_ path: String, _ f: @escaping () -> Void) {
        let k = path + "#presented"
        guard store[k] == nil else { return }
        store[k] = true
        DispatchQueue.main.async(execute: f)
    }
    func dismissed(_ path: String) { store[path + "#presented"] = nil }
    func sheet(_ path: String, _ shown: Binding<Bool>, _ onDismiss: (() -> Void)?, env: EnvironmentValues, _ content: @escaping () -> AnyView) {
        let k = path + "#sheet"
        if shown.wrappedValue {
            guard store[k] == nil, let parent = window else { return }
            let host = NSHostingView(rootView: content(), environment: env)
            let s = host.fittingSize
            let w: NSWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: max(s.width, 200), height: max(s.height, 80)), styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = host
            store[k] = w
            DispatchQueue.main.async { parent.beginSheet(w, completionHandler: nil) }
        } else if let w = store[k] as? NSWindow {
            store[k] = nil
            window?.endSheet(w)
            w.orderOut(nil)
            onDismiss?()
        }
    }
    func popover(_ path: String, _ shown: Binding<Bool>, anchor: _MWNode, env: EnvironmentValues, _ content: @escaping () -> AnyView) {
        let k = path + "#popover"
        if shown.wrappedValue {
            guard store[k] == nil else { return }
            store[k] = true
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let w = self.window else { return }
                let r = self.convert(anchor.frame, to: nil)
                let screen = w.convertToScreen(r)
                _MWPopoverWindow.show(key: k, near: screen, env: env, onClose: { shown.wrappedValue = false }, content)
            }
        } else if store[k] != nil {
            store[k] = nil
            _MWPopoverWindow.close(key: k)
        }
    }
}
final class _MWActionBox<T> {
    var action: (T) -> Void
    var cancellable: AnyCancellable?
    init(_ a: @escaping (T) -> Void) { action = a }
}

/// a borderless window under a point on screen (SwiftUI popovers, MenuBarExtra)
enum _MWPopoverWindow {
    nonisolated(unsafe) static var open: [String: NSWindow] = [:]
    static func show(key: String, near r: CGRect, env: EnvironmentValues = EnvironmentValues(), onClose: (() -> Void)? = nil, _ content: () -> AnyView) {
        let host = NSHostingView(rootView: AnyView(content().padding(10).background(Color(nsColor: .windowBackgroundColor))), environment: env)
        let s = host.fittingSize
        let w: NSWindow = NSWindow(contentRect: NSRect(x: r.midX - s.width / 2, y: r.minY - s.height - 4, width: s.width, height: s.height),
                         styleMask: [], backing: .buffered, defer: false)
        w.contentView = host
        w.makeKeyAndOrderFront(nil)
        open[key] = w
    }
    static func close(key: String) { open[key]?.orderOut(nil); open[key] = nil }
    static func toggle(key: String, near r: CGRect, _ content: () -> AnyView) {
        if open[key] != nil { close(key: key) } else { show(key: key, near: r, content) }
    }
}
