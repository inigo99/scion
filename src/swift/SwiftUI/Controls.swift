// Controls: buttons, toggles, pickers, text fields, sliders, menus, links, progress, labels, lists, forms, sections,
// tab views, alerts, sheets, popovers, gestures and keyboard shortcuts. Drawn in macOS's dark appearance; text fields
// are real NSTextFields and menus real NSMenus.
import Foundation
import AppKit

// MARK: - drawing helpers

func _mwRounded(_ g: CGContext, _ r: CGRect, _ radius: CGFloat, fill: NSColor?, stroke: NSColor? = nil) {
    let p = Path(roundedRect: r, cornerRadius: radius).cgPath
    if let f = fill { CGContextAddPath(g, p); CGContextSetFillColorWithColor(g, f.cgColor); CGContextFillPath(g) }
    if let s = stroke { CGContextAddPath(g, p); CGContextSetStrokeColorWithColor(g, s.cgColor); CGContextSetLineWidth(g, 1); CGContextStrokePath(g) }
}
func _mwText(_ s: String, _ env: EnvironmentValues, color: NSColor? = nil) -> _MWTextNode {
    var e = env
    if let c = color { e.foregroundColor = Color(c) }
    return _MWTextNode(_mwAttr(s, e), lineLimit: 1)
}
/// one node for a list of label nodes
func _mwOne(_ nodes: [_MWNode], axis: Axis = .horizontal) -> _MWNode {
    nodes.count == 1 ? nodes[0] : _MWStackNode(axis, spacing: nil, cross: .center, nodes)
}

// MARK: - buttons

public protocol PrimitiveButtonStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = PrimitiveButtonStyleConfiguration
}
public protocol ButtonStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ButtonStyleConfiguration
}
public struct PrimitiveButtonStyleConfiguration {
    public struct Label: View, _MWResolvable {
        let make: (_MWContext) -> [_MWNode]
        public typealias Body = Never
        public var body: Never { _primitive("Label") }
        func _mwNodes(_ c: _MWContext) -> [_MWNode] { make(c) }
    }
    public let role: ButtonRole?
    public let label: PrimitiveButtonStyleConfiguration.Label
    let action: () -> Void
    public func trigger() { action() }
}
public struct ButtonStyleConfiguration {
    public typealias Label = PrimitiveButtonStyleConfiguration.Label
    public let role: ButtonRole?
    public let label: ButtonStyleConfiguration.Label
    public let isPressed: Bool
}
public struct ButtonRole: Equatable, Sendable {
    let kind: Int
    public static let destructive = ButtonRole(kind: 1)
    public static let cancel = ButtonRole(kind: 2)
}

enum _MWButtonKind { case bordered, borderless, plain, link, prominent }
/// the button style in the environment: a built-in kind or the app's own style
enum _MWButtonStyle {
    case kind(_MWButtonKind)
    case custom((ButtonStyleConfiguration, _MWContext) -> [_MWNode])
    case primitive((PrimitiveButtonStyleConfiguration, _MWContext) -> [_MWNode])
}
private struct _ButtonStyleKey: EnvironmentKey { static var defaultValue: _MWButtonStyle { .kind(.bordered) } }
extension EnvironmentValues {
    var _mwButtonStyle: _MWButtonStyle { get { self[_ButtonStyleKey.self] } set { self[_ButtonStyleKey.self] = newValue } }
}

public struct DefaultButtonStyle: PrimitiveButtonStyle, _MWBuiltinButton {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
    var kind: _MWButtonKind { .bordered }
}
public struct PlainButtonStyle: PrimitiveButtonStyle, _MWBuiltinButton {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
    var kind: _MWButtonKind { .plain }
}
public struct BorderlessButtonStyle: PrimitiveButtonStyle, _MWBuiltinButton {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
    var kind: _MWButtonKind { .borderless }
}
public struct BorderedButtonStyle: PrimitiveButtonStyle, _MWBuiltinButton {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
    var kind: _MWButtonKind { .bordered }
}
public struct BorderedProminentButtonStyle: PrimitiveButtonStyle, _MWBuiltinButton {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
    var kind: _MWButtonKind { .prominent }
}
public struct LinkButtonStyle: PrimitiveButtonStyle, _MWBuiltinButton {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
    var kind: _MWButtonKind { .link }
}
protocol _MWBuiltinButton { var kind: _MWButtonKind { get } }
extension PrimitiveButtonStyle where Self == PlainButtonStyle { public static var plain: PlainButtonStyle { PlainButtonStyle() } }
extension PrimitiveButtonStyle where Self == BorderlessButtonStyle { public static var borderless: BorderlessButtonStyle { BorderlessButtonStyle() } }
extension PrimitiveButtonStyle where Self == DefaultButtonStyle { public static var automatic: DefaultButtonStyle { DefaultButtonStyle() } }
extension PrimitiveButtonStyle where Self == BorderedButtonStyle { public static var bordered: BorderedButtonStyle { BorderedButtonStyle() } }
extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle { public static var borderedProminent: BorderedProminentButtonStyle { BorderedProminentButtonStyle() } }
extension PrimitiveButtonStyle where Self == LinkButtonStyle { public static var link: LinkButtonStyle { LinkButtonStyle() } }

extension View {
    public func buttonStyle<S>(_ style: S) -> some View where S: PrimitiveButtonStyle {
        let st: _MWButtonStyle
        if let b = style as? _MWBuiltinButton { st = .kind(b.kind) } else {
            st = .primitive { cfg, c in _mwResolve(style.makeBody(configuration: cfg), c) }
        }
        return environment(\._mwButtonStyle, st)
    }
    public func buttonStyle<S>(_ style: S) -> some View where S: ButtonStyle {
        environment(\._mwButtonStyle, .custom { cfg, c in _mwResolve(style.makeBody(configuration: cfg), c) })
    }
}

public struct Button<Label>: View where Label: View {
    let action: () -> Void
    let label: Label
    let role: ButtonRole?
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) { self.action = action; self.label = label(); role = nil }
    public init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) { self.action = action; self.label = label(); self.role = role }
    public typealias Body = Never
    public var body: Never { _primitive("Button") }
}
extension Button where Label == Text {
    public init(_ titleKey: LocalizedStringKey, action: @escaping () -> Void) { self.init(action: action) { Text(titleKey) } }
    public init<S>(_ title: S, action: @escaping () -> Void) where S: StringProtocol { self.init(action: action) { Text(title) } }
    public init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping () -> Void) { self.init(role: role, action: action) { Text(titleKey) } }
    public init<S>(_ title: S, role: ButtonRole?, action: @escaping () -> Void) where S: StringProtocol { self.init(role: role, action: action) { Text(title) } }
}
extension Button where Label == PrimitiveButtonStyleConfiguration.Label {
    public init(_ configuration: PrimitiveButtonStyleConfiguration) { self.init(action: configuration.action) { configuration.label } }
}
extension Button: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let label = self.label, action = self.action, role = self.role
        let enabled = c.env.isEnabled
        let pressedKey = c.path + "#pressed"
        let pressed = c.host.store[pressedKey] as? Bool ?? false
        let make: (_MWContext) -> [_MWNode] = { _mwResolve(label, $0.child("l")) }
        var nodes: [_MWNode]
        var kind = _MWButtonKind.plain
        switch c.env._mwButtonStyle {
        case .kind(let k):
            kind = k
            var lc = c.child("l").with(env: c.env)
            if k == .link { var e = c.env; e.foregroundColor = .accentColor; lc = lc.with(env: e) }
            if k == .prominent { var e = c.env; e.foregroundColor = .white; lc = lc.with(env: e) }
            if role == .destructive { var e = lc.env; e.foregroundColor = .red; lc = lc.with(env: e) }
            nodes = _mwResolve(label, lc)
        case .custom(let f):
            nodes = f(ButtonStyleConfiguration(role: role, label: .init(make: make), isPressed: pressed), c.child("st"))
        case .primitive(let f):
            nodes = f(PrimitiveButtonStyleConfiguration(role: role, label: .init(make: make), action: action), c.child("st"))
            return nodes   // the style handles clicks itself
        }
        let b = _MWButtonNode(_mwOne(nodes), kind: kind, action: action)
        b.enabled = enabled
        b.pressed = pressed
        b.onPress = { [weak host = c.host] p in host?.store[pressedKey] = p; if case .custom = c.env._mwButtonStyle { host?.setNeedsUpdate() } }
        return [b]
    }
}
final class _MWButtonNode: _MWTapNode {
    let kind: _MWButtonKind
    let action: () -> Void
    var shortcut: (KeyEquivalent, EventModifiers)?
    init(_ label: _MWNode, kind: _MWButtonKind, action: @escaping () -> Void) {
        self.kind = kind; self.action = action
        let inner: _MWNode = (kind == .bordered || kind == .prominent) ? _MWPaddingNode(EdgeInsets(top: 3, leading: 9, bottom: 3, trailing: 9), label) : label
        super.init([inner])
        onTap = { _ in action() }
    }
    override func size(_ p: _MWProposal) -> CGSize {
        let s = children[0].size(p)
        return (kind == .bordered || kind == .prominent) ? CGSize(width: max(s.width, 32), height: max(s.height, 22)) : s
    }
    override func place(_ r: CGRect) { frame = r; children[0].place(_mwAlign(children[0].size(_MWProposal(r.size)), in: r, .center)) }
    override func draw(_ g: CGContext) {
        guard !isHidden else { return }
        switch kind {
        case .bordered:
            _mwRounded(g, frame.insetBy(dx: 0.5, dy: 0.5), 5, fill: pressed ? NSColor(white: 0.45, alpha: 1) : NSColor(white: 0.36, alpha: 1), stroke: NSColor(white: 0.25, alpha: 1))
        case .prominent:
            _mwRounded(g, frame.insetBy(dx: 0.5, dy: 0.5), 5, fill: pressed ? NSColor.controlAccentColor.withAlphaComponent(0.7) : .controlAccentColor)
        default: break
        }
        if !enabled || (pressed && (kind == .plain || kind == .borderless || kind == .link)) {
            CGContextSaveGState(g); CGContextSetAlpha(g, enabled ? 0.55 : 0.4); super.draw(g); CGContextRestoreGState(g)
        } else { super.draw(g) }
    }
}

// MARK: - toggles

public protocol ToggleStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ToggleStyleConfiguration
}
public struct ToggleStyleConfiguration {
    public typealias Label = PrimitiveButtonStyleConfiguration.Label
    public let label: ToggleStyleConfiguration.Label
    @Binding public var isOn: Bool
}
public struct SwitchToggleStyle: ToggleStyle, _MWBuiltinToggle {
    public init() {}
    public init(tint: Color) {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
    var isSwitch: Bool { true }
}
public struct CheckboxToggleStyle: ToggleStyle, _MWBuiltinToggle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
    var isSwitch: Bool { false }
}
public struct DefaultToggleStyle: ToggleStyle, _MWBuiltinToggle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
    var isSwitch: Bool { false }
}
protocol _MWBuiltinToggle { var isSwitch: Bool { get } }
extension ToggleStyle where Self == SwitchToggleStyle { public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() } }
extension ToggleStyle where Self == CheckboxToggleStyle { public static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() } }
extension ToggleStyle where Self == DefaultToggleStyle { public static var automatic: DefaultToggleStyle { DefaultToggleStyle() } }
private struct _ToggleSwitchKey: EnvironmentKey { static var defaultValue: Bool { false } }
private struct _LabelsHiddenKey: EnvironmentKey { static var defaultValue: Bool { false } }
extension EnvironmentValues {
    var _mwSwitch: Bool { get { self[_ToggleSwitchKey.self] } set { self[_ToggleSwitchKey.self] = newValue } }
    var _mwLabelsHidden: Bool { get { self[_LabelsHiddenKey.self] } set { self[_LabelsHiddenKey.self] = newValue } }
}
extension View {
    public func toggleStyle<S>(_ style: S) -> some View where S: ToggleStyle {
        environment(\._mwSwitch, (style as? _MWBuiltinToggle)?.isSwitch ?? false)
    }
    public func labelsHidden() -> some View { environment(\._mwLabelsHidden, true) }
}

public struct Toggle<Label>: View where Label: View {
    @Binding var isOn: Bool
    let label: Label
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) { _isOn = isOn; self.label = label() }
    public typealias Body = Never
    public var body: Never { _primitive("Toggle") }
}
extension Toggle where Label == Text {
    public init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) { self.init(isOn: isOn) { Text(titleKey) } }
    public init<S>(_ title: S, isOn: Binding<Bool>) where S: StringProtocol { self.init(isOn: isOn) { Text(title) } }
}
extension Toggle: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let b = $isOn
        let labelNodes = c.env._mwLabelsHidden ? [] : _mwResolve(label, c.child("l"))
        let mark = _MWToggleMark(on: b.wrappedValue, isSwitch: c.env._mwSwitch, enabled: c.env.isEnabled)
        let row = c.env._mwSwitch ? _MWStackNode(.horizontal, spacing: 8, cross: .center, labelNodes + [mark])
                                  : _MWStackNode(.horizontal, spacing: 6, cross: .center, [mark] + labelNodes)
        let t = _MWToggleNode([row], binding: b)
        t.enabled = c.env.isEnabled
        return [t]
    }
}
final class _MWToggleNode: _MWTapNode {
    let binding: Binding<Bool>
    init(_ ch: [_MWNode], binding: Binding<Bool>) { self.binding = binding; super.init(ch); onTap = { _ in binding.wrappedValue.toggle() } }
    override func size(_ p: _MWProposal) -> CGSize { children[0].size(p) }
    override func place(_ r: CGRect) { frame = r; children[0].place(r) }
}
final class _MWToggleMark: _MWNode {
    let on: Bool, isSwitch: Bool, enabled: Bool
    init(on: Bool, isSwitch: Bool, enabled: Bool) { self.on = on; self.isSwitch = isSwitch; self.enabled = enabled; super.init() }
    override func size(_ p: _MWProposal) -> CGSize { isSwitch ? CGSize(width: 32, height: 18) : CGSize(width: 14, height: 14) }
    override func draw(_ g: CGContext) {
        let accent = enabled ? NSColor.controlAccentColor : NSColor(white: 0.4, alpha: 1)
        if isSwitch {
            _mwRounded(g, frame, frame.height / 2, fill: on ? accent : NSColor(white: 0.3, alpha: 1))
            let d = frame.height - 4
            CGContextSetFillColorWithColor(g, NSColor.white.cgColor)
            CGContextFillEllipseInRect(g, CGRect(x: on ? frame.maxX - d - 2 : frame.minX + 2, y: frame.minY + 2, width: d, height: d))
        } else {
            _mwRounded(g, frame.insetBy(dx: 0.5, dy: 0.5), 3, fill: on ? accent : NSColor(white: 0.25, alpha: 1), stroke: on ? nil : NSColor(white: 0.45, alpha: 1))
            if on {
                var p = Path()
                p.move(to: CGPoint(x: frame.minX + 3.5, y: frame.midY))
                p.addLine(to: CGPoint(x: frame.minX + 6, y: frame.maxY - 3.5))
                p.addLine(to: CGPoint(x: frame.maxX - 3, y: frame.minY + 3.5))
                _mwStroke(g, p, .white, StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - menus (NSMenu built from the content's buttons, toggles, dividers and pickers)

final class _MWMenuTarget: NSObject {
    let action: () -> Void
    init(_ a: @escaping () -> Void) { action = a }
    @objc func fire(_ sender: Any?) { action() }
}
func _mwMenu(_ nodes: [_MWNode]) -> NSMenu {
    let m = NSMenu(title: "")
    m.autoenablesItems = false
    func add(_ n: _MWNode) {
        if let b = n as? _MWButtonNode {
            let t = _MWMenuTarget(b.action)
            let it = NSMenuItem(title: b.text ?? "", action: #selector(_MWMenuTarget.fire(_:)), keyEquivalent: b.shortcut.map { String($0.0.character) } ?? "")
            it.target = t; it.representedObject = t; it.isEnabled = b.enabled
            m.addItem(it)
        } else if let t = n as? _MWToggleNode {
            let b = t.binding
            let tg = _MWMenuTarget { b.wrappedValue.toggle() }
            let it = NSMenuItem(title: t.text ?? "", action: #selector(_MWMenuTarget.fire(_:)), keyEquivalent: "")
            it.target = tg; it.representedObject = tg; it.state = b.wrappedValue ? 1 : 0
            m.addItem(it)
        } else if n is _MWDividerNode {
            m.addItem(.separator())
        } else if let sub = n as? _MWMenuNode {
            let it = NSMenuItem(title: sub.text ?? "", action: nil, keyEquivalent: "")
            it.submenu = _mwMenu(sub.items)
            m.addItem(it)
        } else if let p = n as? _MWPickerNode {
            for (i, opt) in p.options.enumerated() {
                let tg = _MWMenuTarget { p.choose(i) }
                let it = NSMenuItem(title: opt.text ?? "", action: #selector(_MWMenuTarget.fire(_:)), keyEquivalent: "")
                it.target = tg; it.representedObject = tg; it.state = i == p.selectedIndex ? 1 : 0
                m.addItem(it)
            }
        } else if n is _MWTextNode {
            let it = NSMenuItem(title: n.text ?? "", action: nil, keyEquivalent: ""); it.isEnabled = false; m.addItem(it)
        } else {
            for ch in n.children { add(ch) }
        }
    }
    for n in nodes { add(n) }
    return m
}

public protocol MenuStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = MenuStyleConfiguration
}
public struct MenuStyleConfiguration {}
public struct DefaultMenuStyle: MenuStyle, _MWBuiltinMenu {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { EmptyView() }
    var borderless: Bool { false }
}
public struct BorderlessButtonMenuStyle: MenuStyle, _MWBuiltinMenu {
    let indicator: Bool
    public init() { indicator = true }
    public init(showsMenuIndicator: Bool) { indicator = showsMenuIndicator }
    public func makeBody(configuration: Configuration) -> some View { EmptyView() }
    var borderless: Bool { true }
}
public struct BorderedButtonMenuStyle: MenuStyle, _MWBuiltinMenu {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { EmptyView() }
    var borderless: Bool { false }
}
protocol _MWBuiltinMenu { var borderless: Bool { get } }
private struct _MenuBorderlessKey: EnvironmentKey { static var defaultValue: Bool { false } }
extension EnvironmentValues {
    var _mwMenuBorderless: Bool { get { self[_MenuBorderlessKey.self] } set { self[_MenuBorderlessKey.self] = newValue } }
}
extension View {
    public func menuStyle<S>(_ style: S) -> some View where S: MenuStyle { environment(\._mwMenuBorderless, (style as? _MWBuiltinMenu)?.borderless ?? false) }
}

public struct Menu<Label, Content>: View where Label: View, Content: View {
    let label: Label, content: Content
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) { self.content = content(); self.label = label() }
    public typealias Body = Never
    public var body: Never { _primitive("Menu") }
}
extension Menu where Label == Text {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) { self.init(content: content) { Text(titleKey) } }
    public init<S>(_ title: S, @ViewBuilder content: () -> Content) where S: StringProtocol { self.init(content: content) { Text(title) } }
}
extension Menu: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        var e = c.env; e._mwButtonStyle = .kind(.plain)
        let items = _mwResolve(content, c.child("i").with(env: e))
        let labelNodes = _mwResolve(label, c.child("l"))
        return [_MWMenuNode(_mwOne(labelNodes), items: items, borderless: c.env._mwMenuBorderless)]
    }
}
final class _MWMenuNode: _MWTapNode {
    let items: [_MWNode]
    let borderless: Bool
    weak var host: NSView?
    init(_ label: _MWNode, items: [_MWNode], borderless: Bool) {
        self.items = items; self.borderless = borderless
        super.init([borderless ? label : _MWPaddingNode(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 22), label)])
        onTap = { [unowned self] _ in self.popUp() }
    }
    override var text: String? { children[0].text }
    override func size(_ p: _MWProposal) -> CGSize { let s = children[0].size(p); return borderless ? s : CGSize(width: s.width, height: max(s.height, 22)) }
    override func place(_ r: CGRect) { frame = r; children[0].place(_mwAlign(children[0].size(_MWProposal(r.size)), in: r, .leading)) }
    override func draw(_ g: CGContext) {
        if !borderless {
            _mwRounded(g, frame.insetBy(dx: 0.5, dy: 0.5), 5, fill: NSColor(white: 0.36, alpha: 1), stroke: NSColor(white: 0.25, alpha: 1))
            _mwChevron(g, CGPoint(x: frame.maxX - 11, y: frame.midY), down: true)
        }
        super.draw(g)
    }
    func popUp() {
        guard let v = _MWHostView.current else { return }
        _mwMenu(items).popUp(positioning: nil, at: NSPoint(x: frame.minX, y: frame.maxY + 2), in: v)
    }
}
func _mwChevron(_ g: CGContext, _ c: CGPoint, down: Bool, both: Bool = false) {
    var p = Path()
    if both {
        p.move(to: CGPoint(x: c.x - 3, y: c.y - 2)); p.addLine(to: CGPoint(x: c.x, y: c.y - 5)); p.addLine(to: CGPoint(x: c.x + 3, y: c.y - 2))
        p.move(to: CGPoint(x: c.x - 3, y: c.y + 2)); p.addLine(to: CGPoint(x: c.x, y: c.y + 5)); p.addLine(to: CGPoint(x: c.x + 3, y: c.y + 2))
    } else {
        p.move(to: CGPoint(x: c.x - 3.5, y: c.y - 1.5)); p.addLine(to: CGPoint(x: c.x, y: c.y + 2)); p.addLine(to: CGPoint(x: c.x + 3.5, y: c.y - 1.5))
    }
    _mwStroke(g, p, NSColor(white: 0.9, alpha: 1), StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
}

// MARK: - pickers

public protocol PickerStyle {}
public struct DefaultPickerStyle: PickerStyle, _MWBuiltinPicker { public init() {}; var kind: Int { 0 } }
public struct MenuPickerStyle: PickerStyle, _MWBuiltinPicker { public init() {}; var kind: Int { 0 } }
public struct PopUpButtonPickerStyle: PickerStyle, _MWBuiltinPicker { public init() {}; var kind: Int { 0 } }
public struct SegmentedPickerStyle: PickerStyle, _MWBuiltinPicker { public init() {}; var kind: Int { 1 } }
public struct RadioGroupPickerStyle: PickerStyle, _MWBuiltinPicker { public init() {}; var kind: Int { 2 } }
public struct InlinePickerStyle: PickerStyle, _MWBuiltinPicker { public init() {}; var kind: Int { 2 } }
protocol _MWBuiltinPicker { var kind: Int { get } }
extension PickerStyle where Self == MenuPickerStyle { public static var menu: MenuPickerStyle { MenuPickerStyle() } }
extension PickerStyle where Self == SegmentedPickerStyle { public static var segmented: SegmentedPickerStyle { SegmentedPickerStyle() } }
extension PickerStyle where Self == RadioGroupPickerStyle { public static var radioGroup: RadioGroupPickerStyle { RadioGroupPickerStyle() } }
extension PickerStyle where Self == InlinePickerStyle { public static var inline: InlinePickerStyle { InlinePickerStyle() } }
extension PickerStyle where Self == DefaultPickerStyle { public static var automatic: DefaultPickerStyle { DefaultPickerStyle() } }
private struct _PickerKindKey: EnvironmentKey { static var defaultValue: Int { 0 } }
extension EnvironmentValues {
    var _mwPickerKind: Int { get { self[_PickerKindKey.self] } set { self[_PickerKindKey.self] = newValue } }
}
extension View {
    public func pickerStyle<S>(_ style: S) -> some View where S: PickerStyle { environment(\._mwPickerKind, (style as? _MWBuiltinPicker)?.kind ?? 0) }
}

public struct Picker<Label, SelectionValue, Content>: View where Label: View, SelectionValue: Hashable, Content: View {
    let selection: Binding<SelectionValue>, label: Label, content: Content
    public init(selection: Binding<SelectionValue>, label: Label, @ViewBuilder content: () -> Content) {
        self.selection = selection; self.label = label; self.content = content()
    }
    public init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.init(selection: selection, label: label(), content: content)
    }
    public typealias Body = Never
    public var body: Never { _primitive("Picker") }
}
extension Picker where Label == Text {
    public init(_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, label: Text(titleKey), content: content)
    }
    public init<S>(_ title: S, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) where S: StringProtocol {
        self.init(selection: selection, label: Text(title), content: content)
    }
}
extension Picker: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let options = _mwResolve(content, c.child("o"))
        let sel = selection
        let p = _MWPickerNode(options: options, kind: c.env._mwPickerKind,
                              selected: options.firstIndex { $0.tag == AnyHashable(sel.wrappedValue) } ?? -1,
                              choose: { i in if let t = options[i].tag?.base as? SelectionValue { sel.wrappedValue = t } })
        p.enabled = c.env.isEnabled
        if c.env._mwLabelsHidden { return [p] }
        let l = _mwResolve(label, c.child("l"))
        if l.isEmpty || (l.first?.text ?? "").isEmpty { return [p] }
        return [_MWStackNode(.horizontal, spacing: 8, cross: Alignment(horizontal: .center, vertical: .firstTextBaseline), l + [p])]
    }
}
final class _MWPickerNode: _MWTapNode {
    let options: [_MWNode], kind: Int, selectedIndex: Int
    let chooseIndex: (Int) -> Void
    init(options: [_MWNode], kind: Int, selected: Int, choose: @escaping (Int) -> Void) {
        self.options = options; self.kind = kind; selectedIndex = selected; chooseIndex = choose
        let shown: [_MWNode]
        switch kind {
        case 1: shown = options.map { _MWPaddingNode(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10), $0) }
        case 2: shown = options.enumerated().map { i, o in _MWStackNode(.horizontal, spacing: 6, cross: .center, [_MWRadioMark(on: i == selected), o]) }
        default: shown = [_MWPaddingNode(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 24), selected >= 0 ? options[selected] : _MWSpacerNode(40))]
        }
        super.init([kind == 1 ? _MWStackNode(.horizontal, spacing: 0, cross: .center, shown) : kind == 2 ? _MWStackNode(.vertical, spacing: 6, cross: Alignment(horizontal: .leading, vertical: .center), shown) : shown[0]])
        onTap = { [unowned self] _ in self.clicked() }
    }
    func choose(_ i: Int) { chooseIndex(i) }
    private var clickPoint = CGPoint.zero
    override func mouseUp(_ p: CGPoint, _ e: NSEvent) { clickPoint = p; super.mouseUp(p, e) }
    func clicked() {
        switch kind {
        case 1, 2:
            let rows = children[0].children
            if let i = rows.firstIndex(where: { $0.frame.contains(clickPoint) }) { choose(i) }
        default:
            guard let v = _MWHostView.current else { return }
            _mwMenu([self]).popUp(positioning: nil, at: NSPoint(x: frame.minX, y: frame.maxY + 2), in: v)
        }
    }
    override var text: String? { selectedIndex >= 0 ? options[selectedIndex].text : nil }
    override func size(_ p: _MWProposal) -> CGSize {
        let s = children[0].size(.ideal)
        return kind == 0 ? CGSize(width: max(s.width, 60), height: max(s.height, 22)) : s
    }
    override func place(_ r: CGRect) { frame = r; children[0].place(kind == 0 ? r : _mwAlign(children[0].size(.ideal), in: r, .leading)) }
    override func draw(_ g: CGContext) {
        switch kind {
        case 0:
            _mwRounded(g, frame.insetBy(dx: 0.5, dy: 0.5), 5, fill: NSColor(white: 0.36, alpha: 1), stroke: NSColor(white: 0.25, alpha: 1))
            _mwRounded(g, CGRect(x: frame.maxX - 19, y: frame.minY + 3, width: 16, height: frame.height - 6), 4, fill: .controlAccentColor)
            _mwChevron(g, CGPoint(x: frame.maxX - 11, y: frame.midY), down: true, both: true)
        case 1:
            _mwRounded(g, children[0].frame.insetBy(dx: 0.5, dy: 0.5), 5, fill: NSColor(white: 0.3, alpha: 1), stroke: NSColor(white: 0.22, alpha: 1))
            if selectedIndex >= 0 { _mwRounded(g, children[0].children[selectedIndex].frame.insetBy(dx: 1, dy: 1), 4, fill: NSColor(white: 0.45, alpha: 1)) }
        default: break
        }
        super.draw(g)
    }
}
final class _MWRadioMark: _MWNode {
    let on: Bool
    init(on: Bool) { self.on = on; super.init() }
    override func size(_ p: _MWProposal) -> CGSize { CGSize(width: 14, height: 14) }
    override func draw(_ g: CGContext) {
        CGContextSetFillColorWithColor(g, (on ? NSColor.controlAccentColor : NSColor(white: 0.25, alpha: 1)).cgColor)
        CGContextFillEllipseInRect(g, frame)
        if on { CGContextSetFillColorWithColor(g, NSColor.white.cgColor); CGContextFillEllipseInRect(g, frame.insetBy(dx: 4.5, dy: 4.5)) }
    }
}

// MARK: - text fields (NSTextField)

final class _MWFieldDelegate: NSObject {
    var binding: Binding<String>?
    var onCommit: (() -> Void)?
    weak var field: NSTextField?
    @objc func changed(_ n: Notification) { if let f = field, (n.object as? NSTextField) === f { binding?.wrappedValue = f.stringValue } }
    @objc func committed(_ sender: Any?) { if let f = field { binding?.wrappedValue = f.stringValue }; onCommit?() }
}
public struct TextField<Label>: View where Label: View {
    let text: Binding<String>, label: Label, prompt: String, onCommit: () -> Void, secure: Bool
    public typealias Body = Never
    public var body: Never { _primitive("TextField") }
}
extension TextField where Label == Text {
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) { self.init(text: text, label: Text(titleKey), prompt: Text(titleKey)._mwPlain, onCommit: {}, secure: false) }
    public init<S>(_ title: S, text: Binding<String>) where S: StringProtocol { self.init(text: text, label: Text(title), prompt: String(title), onCommit: {}, secure: false) }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void = { _ in }, onCommit: @escaping () -> Void = {}) {
        self.init(text: text, label: Text(titleKey), prompt: Text(titleKey)._mwPlain, onCommit: onCommit, secure: false)
    }
    public init<S>(_ title: S, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void = { _ in }, onCommit: @escaping () -> Void = {}) where S: StringProtocol {
        self.init(text: text, label: Text(title), prompt: String(title), onCommit: onCommit, secure: false)
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) {
        self.init(text: text, label: Text(titleKey), prompt: prompt?._mwPlain ?? "", onCommit: {}, secure: false)
    }
}
public struct SecureField<Label>: View where Label: View {
    let field: TextField<Label>
    public typealias Body = Never
    public var body: Never { _primitive("SecureField") }
}
extension SecureField where Label == Text {
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) { field = TextField(text: text, label: Text(titleKey), prompt: Text(titleKey)._mwPlain, onCommit: {}, secure: true) }
    public init<S>(_ title: S, text: Binding<String>) where S: StringProtocol { field = TextField(text: text, label: Text(title), prompt: String(title), onCommit: {}, secure: true) }
}
extension SecureField: _MWResolvable { func _mwNodes(_ c: _MWContext) -> [_MWNode] { field._mwNodes(c) } }
extension TextField: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let delegate: _MWFieldDelegate = c.host.store[c.path + "#field"] as? _MWFieldDelegate ?? {
            let d = _MWFieldDelegate(); c.host.store[c.path + "#field"] = d; return d }()
        let f = c.host.embeddedView(c.path) { () -> NSTextField in
            let f = secure ? NSSecureTextField(frame: .zero) : NSTextField(frame: .zero)
            NotificationCenter.default.addObserver(delegate, selector: #selector(_MWFieldDelegate.changed(_:)), name: NSNotification.Name("NSControlTextDidChangeNotification"), object: f)
            f.target = delegate; f.action = #selector(_MWFieldDelegate.committed(_:))
            return f
        }
        delegate.field = f; delegate.binding = text; delegate.onCommit = onCommit
        if f.stringValue != text.wrappedValue { f.stringValue = text.wrappedValue }
        f.placeholderString = prompt
        f.isEnabled = c.env.isEnabled
        if let font = c.env.font { f.font = font.nsFont }
        let n = _MWAppKitNode(f)
        n.sizer = { p in CGSize(width: _mwFinite(p.width, 100), height: max(22, f.intrinsicContentSize.height)) }
        return [n]
    }
}

// MARK: - sliders, steppers, progress

public struct Slider<Label, ValueLabel>: View where Label: View, ValueLabel: View {
    let value: Binding<Double>, range: ClosedRange<Double>, step: Double?, onEditingChanged: (Bool) -> Void
    public typealias Body = Never
    public var body: Never { _primitive("Slider") }
}
extension Slider where Label == EmptyView, ValueLabel == EmptyView {
    public init<V>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
        self.value = Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = V($0) })
        range = Double(bounds.lowerBound)...Double(bounds.upperBound); step = nil; self.onEditingChanged = onEditingChanged
    }
    public init<V>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
        self.value = Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = V($0) })
        range = Double(bounds.lowerBound)...Double(bounds.upperBound); self.step = Double(step); self.onEditingChanged = onEditingChanged
    }
}
extension Slider: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let v = value, r = range, st = step, changed = onEditingChanged
        let frac = (v.wrappedValue - r.lowerBound) / max(r.upperBound - r.lowerBound, .ulpOfOne)
        let knob = _MWDrawNode(ideal: nil) { g, f in
            _mwRounded(g, CGRect(x: f.minX, y: f.midY - 2, width: f.width, height: 4), 2, fill: NSColor(white: 0.35, alpha: 1))
            _mwRounded(g, CGRect(x: f.minX, y: f.midY - 2, width: f.width * frac, height: 4), 2, fill: .controlAccentColor)
            CGContextSetFillColorWithColor(g, NSColor(white: 0.85, alpha: 1).cgColor)
            CGContextFillEllipseInRect(g, CGRect(x: f.minX + (f.width - 16) * frac, y: f.midY - 8, width: 16, height: 16))
        }
        let t = _MWTapNode([knob])
        t.onDrag = { _, p, ended in
            var x = Double((p.x - t.frame.minX) / max(t.frame.width, 1))
            x = Swift.min(Swift.max(x, 0), 1)
            var nv = r.lowerBound + x * (r.upperBound - r.lowerBound)
            if let s = st, s > 0 { nv = (nv / s).rounded() * s }
            v.wrappedValue = nv
            changed(!ended)
        }
        let f = _MWFrameNode(t, alignment: .center)
        f.minW = 60; f.idealW = 160; f.maxW = .infinity; f.fixedH = 20
        return [f]
    }
}

public struct ProgressView<Label, CurrentValueLabel>: View where Label: View, CurrentValueLabel: View {
    let fraction: Double?
    let title: String?
    public typealias Body = Never
    public var body: Never { _primitive("ProgressView") }
}
extension ProgressView where CurrentValueLabel == EmptyView {
    public init() where Label == EmptyView { fraction = nil; title = nil }
    public init(_ titleKey: LocalizedStringKey) where Label == Text { fraction = nil; title = Text(titleKey)._mwPlain }
    public init<S>(_ title: S) where Label == Text, S: StringProtocol { fraction = nil; self.title = String(title) }
    public init<V>(value: V?, total: V = 1.0) where Label == EmptyView, V: BinaryFloatingPoint { fraction = value.map { Double($0 / total) }; title = nil }
    public init<S, V>(_ title: S, value: V?, total: V = 1.0) where Label == Text, S: StringProtocol, V: BinaryFloatingPoint {
        fraction = value.map { Double($0 / total) }; self.title = String(title)
    }
}
public protocol ProgressViewStyle {}
public struct CircularProgressViewStyle: ProgressViewStyle { public init() {} }
public struct LinearProgressViewStyle: ProgressViewStyle { public init() {} }
extension View {
    public func progressViewStyle<S>(_ style: S) -> some View where S: ProgressViewStyle { self }
}
extension ProgressView: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let fr = fraction
        let bar: _MWNode
        if let f = fr {
            let d = _MWDrawNode(ideal: nil) { g, r in
                _mwRounded(g, CGRect(x: r.minX, y: r.midY - 3, width: r.width, height: 6), 3, fill: NSColor(white: 0.3, alpha: 1))
                _mwRounded(g, CGRect(x: r.minX, y: r.midY - 3, width: r.width * CGFloat(Swift.min(Swift.max(f, 0), 1)), height: 6), 3, fill: .controlAccentColor)
            }
            let fn = _MWFrameNode(d, alignment: .center); fn.maxW = .infinity; fn.fixedH = 12; bar = fn
        } else {
            let size: CGFloat = c.env.controlSize == .small ? 16 : c.env.controlSize == .mini ? 12 : 28
            bar = _MWDrawNode(ideal: CGSize(width: size, height: size)) { g, r in
                for i in 0..<8 {
                    let a = Double(i) * .pi / 4
                    var p = Path()
                    p.move(to: CGPoint(x: r.midX + r.width * 0.22 * cos(a), y: r.midY + r.height * 0.22 * sin(a)))
                    p.addLine(to: CGPoint(x: r.midX + r.width * 0.42 * cos(a), y: r.midY + r.height * 0.42 * sin(a)))
                    _mwStroke(g, p, NSColor(white: 0.9, alpha: 0.25 + 0.09 * Double(i)), StrokeStyle(lineWidth: max(1.5, r.width / 12), lineCap: .round))
                }
            }
        }
        if let t = title { return [_MWStackNode(.vertical, spacing: 6, cross: .center, [bar, _mwText(t, c.env)])] }
        return [bar]
    }
}

// MARK: - labels and links

public protocol LabelStyle {}
public struct TitleOnlyLabelStyle: LabelStyle { public init() {} }
public struct IconOnlyLabelStyle: LabelStyle { public init() {} }
public struct TitleAndIconLabelStyle: LabelStyle { public init() {} }
public struct DefaultLabelStyle: LabelStyle { public init() {} }
extension LabelStyle where Self == TitleOnlyLabelStyle { public static var titleOnly: TitleOnlyLabelStyle { TitleOnlyLabelStyle() } }
extension LabelStyle where Self == IconOnlyLabelStyle { public static var iconOnly: IconOnlyLabelStyle { IconOnlyLabelStyle() } }
extension LabelStyle where Self == TitleAndIconLabelStyle { public static var titleAndIcon: TitleAndIconLabelStyle { TitleAndIconLabelStyle() } }
private struct _LabelStyleKey: EnvironmentKey { static var defaultValue: Int { 0 } }
extension EnvironmentValues {
    var _mwLabelStyle: Int { get { self[_LabelStyleKey.self] } set { self[_LabelStyleKey.self] = newValue } }
}
extension View {
    public func labelStyle<S>(_ style: S) -> some View where S: LabelStyle {
        environment(\._mwLabelStyle, style is TitleOnlyLabelStyle ? 1 : style is IconOnlyLabelStyle ? 2 : 0)
    }
}
public struct Label<Title, Icon>: View where Title: View, Icon: View {
    let title: Title, icon: Icon
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) { self.title = title(); self.icon = icon() }
    public typealias Body = Never
    public var body: Never { _primitive("Label") }
}
extension Label where Title == Text, Icon == Image {
    public init(_ titleKey: LocalizedStringKey, systemImage name: String) { self.init(title: { Text(titleKey) }, icon: { Image(systemName: name) }) }
    public init<S>(_ title: S, systemImage name: String) where S: StringProtocol { self.init(title: { Text(title) }, icon: { Image(systemName: name) }) }
    public init(_ titleKey: LocalizedStringKey, image name: String) { self.init(title: { Text(titleKey) }, icon: { Image(name) }) }
    public init<S>(_ title: S, image name: String) where S: StringProtocol { self.init(title: { Text(title) }, icon: { Image(name) }) }
}
extension Label: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let t = _mwResolve(title, c.child("t")), i = _mwResolve(icon, c.child("i"))
        switch c.env._mwLabelStyle {
        case 1: return t
        case 2: return i
        default: return [_MWStackNode(.horizontal, spacing: 6, cross: .center, i + t)]
        }
    }
}

public struct Link<Label>: View where Label: View {
    let destination: URL, label: Label
    public init(destination: URL, @ViewBuilder label: () -> Label) { self.destination = destination; self.label = label() }
    public typealias Body = Never
    public var body: Never { _primitive("Link") }
}
extension Link where Label == Text {
    public init(_ titleKey: LocalizedStringKey, destination: URL) { self.init(destination: destination) { Text(titleKey) } }
    public init<S>(_ title: S, destination: URL) where S: StringProtocol { self.init(destination: destination) { Text(title) } }
}
extension Link: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        var e = c.env; e.foregroundColor = .accentColor
        let url = destination
        let t = _MWTapNode([_mwOne(_mwResolve(label, c.child("l").with(env: e)))])
        t.onTap = { _ in _ = NSWorkspace.shared.open(url) }
        return [t]
    }
}

// MARK: - lists, forms, sections

public protocol ListStyle {}
public struct DefaultListStyle: ListStyle { public init() {} }
public struct PlainListStyle: ListStyle { public init() {} }
public struct SidebarListStyle: ListStyle { public init() {} }
public struct InsetListStyle: ListStyle { public init() {} }
public struct BorderedListStyle: ListStyle { public init() {} }
extension ListStyle where Self == PlainListStyle { public static var plain: PlainListStyle { PlainListStyle() } }
extension ListStyle where Self == SidebarListStyle { public static var sidebar: SidebarListStyle { SidebarListStyle() } }
extension ListStyle where Self == InsetListStyle { public static var inset: InsetListStyle { InsetListStyle() } }
extension View {
    public func listStyle<S>(_ style: S) -> some View where S: ListStyle { self }
    public func listRowBackground<V>(_ view: V?) -> some View where V: View { self }
    public func listRowSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View { self }
}
@frozen public enum Visibility: Hashable, CaseIterable, Sendable { case automatic, visible, hidden }

public struct List<SelectionValue, Content>: View where SelectionValue: Hashable, Content: View {
    let content: Content
    let selection: Binding<SelectionValue?>?
    public typealias Body = Never
    public var body: Never { _primitive("List") }
}
extension List where SelectionValue == Never {
    public init(@ViewBuilder content: () -> Content) { self.content = content(); selection = nil }
    public init<Data, RowContent>(_ data: Data, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent)
        where Content == ForEach<Data, Data.Element.ID, RowContent>, Data: RandomAccessCollection, RowContent: View, Data.Element: Identifiable {
        content = ForEach(data, content: rowContent); selection = nil
    }
    public init<Data, ID, RowContent>(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent)
        where Content == ForEach<Data, ID, RowContent>, Data: RandomAccessCollection, ID: Hashable, RowContent: View {
        content = ForEach(data, id: id, content: rowContent); selection = nil
    }
}
extension List {
    public init(selection: Binding<SelectionValue?>?, @ViewBuilder content: () -> Content) { self.content = content(); self.selection = selection }
}
extension List: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let rows = _mwResolve(content, c.child("rows")).map { n -> _MWNode in
            let insets = (n.traits["ListRowInsetsTraitKey"] as? EdgeInsets?) ?? nil
            let f = _MWFrameNode(_MWPaddingNode(insets ?? EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8), n), alignment: .leading)
            f.maxW = .infinity
            f.tag = n.tag
            return f
        }
        let stack = _MWStackNode(.vertical, spacing: 0, cross: Alignment(horizontal: .leading, vertical: .center), rows)
        let sel = selection
        if let s = sel {
            for r in rows where r.tag != nil {
                let tag = r.tag!
                if AnyHashable(s.wrappedValue) == AnyHashable(Optional(tag.base as? SelectionValue)) && s.wrappedValue != nil {
                    r.traits["selected"] = true
                }
            }
        }
        let scroll = _MWScrollNode(stack, axes: .vertical, key: c.path, host: c.host)
        let list = _MWListNode([scroll], selection: { tag in if let t = tag?.base as? SelectionValue { sel?.wrappedValue = t } }, rows: rows)
        return [list]
    }
}
final class _MWListNode: _MWTapNode {
    let rows: [_MWNode]
    init(_ ch: [_MWNode], selection: @escaping (AnyHashable?) -> Void, rows: [_MWNode]) {
        self.rows = rows
        super.init(ch)
        var last = CGPoint.zero
        onPress = { _ in }
        onTap = { [unowned self] _ in if let r = self.rows.first(where: { $0.frame.contains(last) }) { selection(r.tag) } }
        clickAt = { last = $0 }
    }
    var clickAt: (CGPoint) -> Void = { _ in }
    override func hit(_ p: CGPoint) -> _MWNode? {
        if let h = children[0].hit(p) { return h }
        return frame.contains(p) ? self : nil
    }
    override func mouseUp(_ p: CGPoint, _ e: NSEvent) { clickAt(p); super.mouseUp(p, e) }
    override func size(_ p: _MWProposal) -> CGSize { children[0].size(p) }
    override func place(_ r: CGRect) { frame = r; children[0].place(r) }
    override func draw(_ g: CGContext) {
        for r in rows where r.traits["selected"] as? Bool == true { _mwRounded(g, r.frame.insetBy(dx: 4, dy: 0), 4, fill: .controlAccentColor) }
        super.draw(g)
    }
}

public struct Form<Content>: View where Content: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public typealias Body = Never
    public var body: Never { _primitive("Form") }
}
extension Form: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        [_MWStackNode(.vertical, spacing: 10, cross: Alignment(horizontal: .leading, vertical: .center), _mwResolve(content, c.child("f")))]
    }
}
public protocol FormStyle {}
public struct GroupedFormStyle: FormStyle { public init() {} }
public struct ColumnsFormStyle: FormStyle { public init() {} }
extension View { public func formStyle<S>(_ style: S) -> some View where S: FormStyle { self } }

public struct Section<Parent, Content, Footer> {
    let header: Parent, content: Content, footer: Footer
}
extension Section: View where Parent: View, Content: View, Footer: View {
    public typealias Body = Never
    public var body: Never { _primitive("Section") }
    public init(header: Parent, footer: Footer, @ViewBuilder content: () -> Content) { self.header = header; self.footer = footer; self.content = content() }
}
extension Section where Parent: View, Content: View, Footer == EmptyView {
    public init(header: Parent, @ViewBuilder content: () -> Content) { self.init(header: header, footer: EmptyView(), content: content) }
}
extension Section where Parent == EmptyView, Content: View, Footer: View {
    public init(footer: Footer, @ViewBuilder content: () -> Content) { self.init(header: EmptyView(), footer: footer, content: content) }
}
extension Section where Parent == EmptyView, Content: View, Footer == EmptyView {
    public init(@ViewBuilder content: () -> Content) { self.init(header: EmptyView(), footer: EmptyView(), content: content) }
}
extension Section where Parent == Text, Content: View, Footer == EmptyView {
    public init<S>(_ title: S, @ViewBuilder content: () -> Content) where S: StringProtocol { self.init(header: Text(title), footer: EmptyView(), content: content) }
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) { self.init(header: Text(titleKey), footer: EmptyView(), content: content) }
}
extension Section: _MWResolvable where Parent: View, Content: View, Footer: View {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        var e = c.env; e.foregroundColor = .secondary; e.font = .system(size: 11, weight: .bold)
        let h = _mwResolve(header, c.child("h").with(env: e))
        return h + _mwResolve(content, c.child("c")) + _mwResolve(footer, c.child("f").with(env: e))
    }
}

// MARK: - tab views

public struct TabView<SelectionValue, Content>: View where SelectionValue: Hashable, Content: View {
    let selection: Binding<SelectionValue>?, content: Content
    public init(selection: Binding<SelectionValue>?, @ViewBuilder content: () -> Content) { self.selection = selection; self.content = content() }
    public typealias Body = Never
    public var body: Never { _primitive("TabView") }
}
extension TabView where SelectionValue == Int {
    public init(@ViewBuilder content: () -> Content) { self.init(selection: nil, content: content) }
}
public protocol TabViewStyle {}
public struct DefaultTabViewStyle: TabViewStyle { public init() {} }
extension View {
    public func tabItem<V>(@ViewBuilder _ label: () -> V) -> some View where V: View {
        let l = label()
        return modifier(_MWWrap { n, c in n.traits["tabItem"] = _mwOne(_mwResolve(l, c.child("tab"))).text ?? ""; return n })
    }
    public func tabViewStyle<S>(_ style: S) -> some View where S: TabViewStyle { self }
}
extension TabView: _MWResolvable {
    func _mwNodes(_ c: _MWContext) -> [_MWNode] {
        let pages = _mwResolve(content, c.child("p"))
        guard !pages.isEmpty else { return [] }
        let key = c.path + "#tab"
        let sel = selection
        var index = 0
        if let s = sel { index = pages.firstIndex { $0.tag == AnyHashable(s.wrappedValue) } ?? 0 } else { index = c.host.store[key] as? Int ?? 0 }
        index = min(index, pages.count - 1)
        let host = c.host
        let titles = pages.enumerated().map { i, p in _MWOption(text: p.traits["tabItem"] as? String ?? "\(i + 1)") }
        let bar = _MWPickerNode(options: titles, kind: 1, selected: index) { i in
            if let s = sel, let t = pages[i].tag?.base as? SelectionValue { s.wrappedValue = t } else { host.store[key] = i; host.setNeedsUpdate() }
        }
        let page = _MWFrameNode(pages[index], alignment: .top); page.maxW = .infinity; page.maxH = .infinity
        return [_MWStackNode(.vertical, spacing: 10, cross: .center, [bar, page])]
    }
}
final class _MWOption: _MWNode {
    let t: String
    init(text: String) { t = text; super.init([_MWTextNode(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]), lineLimit: 1)]) }
    override var text: String? { t }
}

// MARK: - alerts, sheets, popovers

public struct Alert {
    let title: Text, message: Text?, buttons: [Alert.Button]
    public init(title: Text, message: Text? = nil, dismissButton: Alert.Button? = nil) { self.title = title; self.message = message; buttons = [dismissButton ?? .default(Text("OK"))] }
    public init(title: Text, message: Text? = nil, primaryButton: Alert.Button, secondaryButton: Alert.Button) {
        self.title = title; self.message = message; buttons = [primaryButton, secondaryButton]
    }
    public struct Button {
        let label: Text, action: (() -> Void)?, kind: Int
        public static func `default`(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button { Button(label: label, action: action, kind: 0) }
        public static func cancel(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button { Button(label: label, action: action, kind: 1) }
        public static func cancel(_ action: (() -> Void)? = {}) -> Alert.Button { Button(label: Text("Cancel"), action: action, kind: 1) }
        public static func destructive(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button { Button(label: label, action: action, kind: 2) }
    }
}
extension View {
    public func alert(isPresented: Binding<Bool>, content: () -> Alert) -> some View {
        let a = content()
        return modifier(_MWWrap { n, c in
            if isPresented.wrappedValue { c.host.presentOnce(c.path) { _mwRunAlert(a) { isPresented.wrappedValue = false } } } else { c.host.dismissed(c.path) }
            return n
        })
    }
    public func alert<A>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View where A: View {
        alert(isPresented: isPresented) { Alert(title: Text(titleKey)) }
    }
    public func alert<A, M>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View where A: View, M: View {
        alert(isPresented: isPresented) { Alert(title: Text(titleKey)) }
    }
    public func sheet<Content>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View where Content: View {
        modifier(_MWWrap { n, c in c.host.sheet(c.path, isPresented, onDismiss, env: c.env) { AnyView(content()) }; return n })
    }
    public func sheet<Item, Content>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View where Item: Identifiable, Content: View {
        let shown = Binding<Bool>(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
        return modifier(_MWWrap { n, c in c.host.sheet(c.path, shown, onDismiss, env: c.env) { AnyView(item.wrappedValue.map(content)) }; return n })
    }
    public func popover<Content>(isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds), arrowEdge: Edge = .top,
                                 @ViewBuilder content: @escaping () -> Content) -> some View where Content: View {
        modifier(_MWWrap { n, c in c.host.popover(c.path, isPresented, anchor: n, env: c.env) { AnyView(content()) }; return n })
    }
}
public enum PopoverAttachmentAnchor {
    case rect(Anchor<CGRect>.Source)
    case point(UnitPoint)
}
func _mwRunAlert(_ a: Alert, done: @escaping () -> Void) {
    let al = NSAlert()
    al.messageText = a.title._mwPlain
    al.informativeText = a.message?._mwPlain ?? ""
    for b in a.buttons { al.addButton(withTitle: b.label._mwPlain) }
    let r = al.runModal()
    let i = Int(r) - 1000
    done()
    if i >= 0 && i < a.buttons.count { a.buttons[i].action?() }
}

// MARK: - gestures

public struct _GestureInputs {}
public struct _GestureOutputs<Value> {}
public protocol Gesture {
    associatedtype Value
    associatedtype Body: Gesture
    var body: Self.Body { get }
    static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Self.Value>
}
extension Never: Gesture {
    public typealias Value = Never
}
extension Gesture {
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Self.Value> { _GestureOutputs() }
}
extension Gesture where Body == Never {
    public var body: Never { _primitive("Gesture") }
}
/// what a gesture does with the mouse
protocol _MWGesture {
    func _mwInstall(_ t: _MWTapNode)
}
@frozen public struct GestureMask: OptionSet {
    public let rawValue: UInt32
    @inlinable public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let none = GestureMask([]), gesture = GestureMask(rawValue: 1), subviews = GestureMask(rawValue: 2), all = GestureMask(rawValue: 3)
}
public struct TapGesture: Gesture, _MWGesture {
    public var count: Int
    public init(count: Int = 1) { self.count = count }
    public typealias Value = ()
    public typealias Body = Never
    func _mwInstall(_ t: _MWTapNode) { t.requiredCount = count }
}
public struct DragGesture: Gesture, _MWGesture {
    public struct Value: Equatable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint
        public var translation: CGSize { CGSize(width: location.x - startLocation.x, height: location.y - startLocation.y) }
        public var predictedEndLocation: CGPoint { location }
        public var predictedEndTranslation: CGSize { translation }
    }
    public var minimumDistance: CGFloat
    public var coordinateSpace: CoordinateSpace
    public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace = .local) { self.minimumDistance = minimumDistance; self.coordinateSpace = coordinateSpace }
    public typealias Body = Never
    func _mwInstall(_ t: _MWTapNode) {}
}
public struct _ChangedGesture<Content>: Gesture, _MWGesture where Content: Gesture {
    let content: Content, action: (Content.Value) -> Void
    public typealias Value = Content.Value
    public typealias Body = Never
    func _mwInstall(_ t: _MWTapNode) {
        (content as? _MWGesture)?._mwInstall(t)
        if Content.self == DragGesture.self { let a = action; let prev = t.onDrag; t.onDrag = { s, p, end in prev?(s, p, end); if !end { a(DragGesture.Value(time: Date(), location: p, startLocation: s) as! Content.Value) } } }
    }
}
public struct _EndedGesture<Content>: Gesture, _MWGesture where Content: Gesture {
    let content: Content, action: (Content.Value) -> Void
    public typealias Value = Content.Value
    public typealias Body = Never
    func _mwInstall(_ t: _MWTapNode) {
        (content as? _MWGesture)?._mwInstall(t)
        let a = action
        if Content.self == DragGesture.self {
            let prev = t.onDrag; t.onDrag = { s, p, end in prev?(s, p, end); if end { a(DragGesture.Value(time: Date(), location: p, startLocation: s) as! Content.Value) } }
        } else if Content.Value.self == Void.self {
            t.onTap = { _ in a(() as! Content.Value) }
        }
    }
}
extension Gesture {
    public func onEnded(_ action: @escaping (Self.Value) -> Void) -> _EndedGesture<Self> { _EndedGesture(content: self, action: action) }
}
extension Gesture where Self.Value: Equatable {
    public func onChanged(_ action: @escaping (Self.Value) -> Void) -> _ChangedGesture<Self> { _ChangedGesture(content: self, action: action) }
}
extension View {
    public func gesture<T>(_ gesture: T, including mask: GestureMask = .all) -> some View where T: Gesture {
        modifier(_MWWrap { n, _ in
            let t = _MWTapNode([n])
            (gesture as? _MWGesture)?._mwInstall(t)
            return t
        })
    }
    public func simultaneousGesture<T>(_ gesture: T, including mask: GestureMask = .all) -> some View where T: Gesture { self.gesture(gesture, including: mask) }
    public func highPriorityGesture<T>(_ gesture: T, including mask: GestureMask = .all) -> some View where T: Gesture { self.gesture(gesture, including: mask) }
}

// MARK: - keyboard shortcuts

public struct KeyEquivalent: Hashable, ExpressibleByExtendedGraphemeClusterLiteral {
    public var character: Character
    public init(_ character: Character) { self.character = character }
    public init(extendedGraphemeClusterLiteral: Character) { character = extendedGraphemeClusterLiteral }
    public static let upArrow = KeyEquivalent("\u{F700}")
    public static let downArrow = KeyEquivalent("\u{F701}")
    public static let leftArrow = KeyEquivalent("\u{F702}")
    public static let rightArrow = KeyEquivalent("\u{F703}")
    public static let escape = KeyEquivalent("\u{1B}")
    public static let delete = KeyEquivalent("\u{8}")
    public static let deleteForward = KeyEquivalent("\u{F728}")
    public static let home = KeyEquivalent("\u{F729}")
    public static let end = KeyEquivalent("\u{F72B}")
    public static let pageUp = KeyEquivalent("\u{F72C}")
    public static let pageDown = KeyEquivalent("\u{F72D}")
    public static let clear = KeyEquivalent("\u{F739}")
    public static let tab = KeyEquivalent("\t")
    public static let space = KeyEquivalent(" ")
    public static let `return` = KeyEquivalent("\r")
}
@frozen public struct EventModifiers: OptionSet {
    public let rawValue: Int
    @inlinable public init(rawValue: Int) { self.rawValue = rawValue }
    public static let capsLock = EventModifiers(rawValue: 1)
    public static let shift = EventModifiers(rawValue: 2)
    public static let control = EventModifiers(rawValue: 4)
    public static let option = EventModifiers(rawValue: 8)
    public static let command = EventModifiers(rawValue: 16)
    public static let numericPad = EventModifiers(rawValue: 32)
    public static let function = EventModifiers(rawValue: 64)
    public static let all = EventModifiers(rawValue: 127)
}
public struct KeyboardShortcut: Hashable {
    public struct Localization: Hashable {
        let kind: Int
        public static let automatic = Localization(kind: 0)
        public static let withoutMirroring = Localization(kind: 1)
        public static let custom = Localization(kind: 2)
    }
    public var key: KeyEquivalent
    public var modifiers: EventModifiers
    public var localization: KeyboardShortcut.Localization
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) { self.key = key; self.modifiers = modifiers; localization = .automatic }
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command, localization: KeyboardShortcut.Localization) { self.key = key; self.modifiers = modifiers; self.localization = localization }
    public static let defaultAction = KeyboardShortcut(.return, modifiers: [])
    public static let cancelAction = KeyboardShortcut(.escape, modifiers: [])
    public static func == (a: KeyboardShortcut, b: KeyboardShortcut) -> Bool { a.key == b.key && a.modifiers == b.modifiers }
    public func hash(into h: inout Hasher) { h.combine(key); h.combine(modifiers.rawValue) }
}
extension View {
    public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        modifier(_MWWrap { n, _ in n.all { ($0 as? _MWButtonNode)?.shortcut = (key, modifiers) }; return n })
    }
    public func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View { keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers) }
    public func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        modifier(_MWWrap { n, _ in n.all { ($0 as? _MWButtonNode)?.shortcut = shortcut.map { ($0.key, $0.modifiers) } }; return n })
    }
}
/// a key event that matches a button's shortcut presses it
func _mwPerformShortcut(_ root: _MWNode?, _ e: NSEvent) -> Bool {
    guard let root = root, let chars = e.charactersIgnoringModifiers, let ch = chars.first else { return false }
    var mods: EventModifiers = []
    let f = e.modifierFlags
    if f.contains(.command) { mods.insert(.command) }
    if f.contains(.shift) { mods.insert(.shift) }
    if f.contains(.option) { mods.insert(.option) }
    if f.contains(.control) { mods.insert(.control) }
    var done = false
    root.all { n in
        guard !done, let b = n as? _MWButtonNode, let s = b.shortcut, b.enabled else { return }
        if String(s.0.character).lowercased() == String(ch).lowercased() && s.1 == mods { b.action(); done = true }
    }
    return done
}

// MARK: - accessibility (stored nowhere)

public struct AccessibilityChildBehavior: Hashable {
    let kind: Int
    public static let ignore = AccessibilityChildBehavior(kind: 0)
    public static let contain = AccessibilityChildBehavior(kind: 1)
    public static let combine = AccessibilityChildBehavior(kind: 2)
}
public struct AccessibilityAttachmentModifier: ViewModifier, _MWModifier {
    public typealias Body = Never
    func _mwModify(_ c: _MWContext, _ content: @escaping (_MWContext) -> [_MWNode]) -> [_MWNode] { content(c) }
}
public struct AccessibilityTraits: OptionSet {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let isButton = AccessibilityTraits(rawValue: 1), isHeader = AccessibilityTraits(rawValue: 2), isSelected = AccessibilityTraits(rawValue: 4)
}
extension View {
    public func accessibilityLabel<S>(_ label: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S: StringProtocol { modifier(AccessibilityAttachmentModifier()) }
    public func accessibilityLabel(_ label: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { modifier(AccessibilityAttachmentModifier()) }
    public func accessibilityLabel(_ labelKey: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { modifier(AccessibilityAttachmentModifier()) }
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View { self }
    public func accessibilityHidden(_ hidden: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { modifier(AccessibilityAttachmentModifier()) }
    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { modifier(AccessibilityAttachmentModifier()) }
    public func accessibilityIdentifier(_ identifier: String) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { modifier(AccessibilityAttachmentModifier()) }
    public func accessibilityHint(_ hint: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> { modifier(AccessibilityAttachmentModifier()) }
}
extension ModifiedContent where Modifier == AccessibilityAttachmentModifier {
    public func accessibilityValue<S>(_ valueDescription: S) -> ModifiedContent<Content, Modifier> where S: StringProtocol { self }
    public func accessibilityValue(_ valueDescription: Text) -> ModifiedContent<Content, Modifier> { self }
    public func accessibilityLabel<S>(_ label: S) -> ModifiedContent<Content, Modifier> where S: StringProtocol { self }
    public func accessibilityHint<S>(_ hint: S) -> ModifiedContent<Content, Modifier> where S: StringProtocol { self }
}
