// animation.swift: withAnimation with linear, eased, spring and delayed curves (frames), transitions of views that
// appear and go away (move, with the views around them sliding), opacity, rotationEffect and scaleEffect, and
// animation(_:value:). The animations' clock is stopped (scion's test hook) and set to points of each animation;
// the laid-out tree must be in between. Then one animation on the real clock, with its completion. Prints
// "ANIMATION OK" when everything matches.
import SwiftUI
@_spi(ScionTest) import SwiftUI
import AppKit

final class Model: ObservableObject {
    static let shared = Model()
    @Published var wide = false
    @Published var show = true
    @Published var faded = false
    @Published var turned = false
    @Published var count = 0
}

struct Content: View {
    @ObservedObject var model = Model.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bar").frame(width: model.wide ? 200 : 100, alignment: .trailing)
            HStack {
                if model.show { Text("Here").transition(.move(edge: .leading)) }
                Text("Fixed")
            }
            Text("Faded").opacity(model.faded ? 0.2 : 1)
            Text("Turned").rotationEffect(.degrees(model.turned ? 90 : 0)).scaleEffect(model.turned ? 2 : 1)
            Text("Counter").offset(x: CGFloat(model.count) * 10).animation(.linear(duration: 1), value: model.count)
        }
        .padding()
        .frame(width: 400, height: 300, alignment: .topLeading)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Test.run() } }
    }
}

enum Test {
    static var failures: [String] = []
    static var view: NSView?
    static var now = 1000.0
    static func ok(_ c: Bool, _ what: String) {
        guard !c else { return }
        print("FAIL: \(what)")
        failures.append(what)
    }
    static func pause(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
    /// the frame of the text node showing `text`: x, y, width, height
    static func frame(_ tree: String, _ text: String) -> [Int]? {
        guard let l = line(tree, text) else { return nil }
        let parts = l.split(separator: " ").filter { !$0.isEmpty }
        guard parts.count >= 3 else { return nil }
        let xy = parts[1].split(separator: ",").compactMap { Int($0) }, wh = parts[2].split(separator: "x").compactMap { Int($0) }
        return xy.count == 2 && wh.count == 2 ? xy + wh : nil
    }
    static func line(_ tree: String, _ text: String) -> String? {
        tree.split(separator: "\n").first(where: { $0.hasSuffix("\"\(text)\"") }).map(String.init)
    }
    /// the lines of the tree with `key`, and the ones after them, on one line
    static func show(_ tree: String, _ key: String) -> String {
        let ls = tree.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let i = ls.firstIndex(where: { $0.contains(key) }) else { return "no \(key) in \(ls.count) lines: " + ls.suffix(8).joined(separator: " | ") }
        return ls[i..<min(ls.count, i + 3)].joined(separator: " | ")
    }
    static func x(_ tree: String, _ text: String) -> Int { frame(tree, text)?[0] ?? -9999 }
    /// a change made in `animation` (nil: none), at a new point of the stopped clock
    static func animate(_ a: Animation?, _ change: () -> Void) {
        now += 10
        _mwTestAnimationTime(now)
        if let a = a { withAnimation(a, change) } else { change() }
        pause()
    }
    /// the tree `s` seconds into the last animation
    static func at(_ s: Double) -> String { _mwTestAnimationTime(now + s); return _mwTestDump(view!) }
    static func near(_ a: Int, _ b: Int, _ d: Int = 2) -> Bool { abs(a - b) <= d }

    static func run() {
        guard let w = NSApplication.shared.windows.first, let v = w.contentView else { print("FAIL: no window"); exit(1) }
        view = v
        let m = Model.shared
        _mwTestAnimationTime(now)
        var t = _mwTestDump(v)
        if ProcessInfo.processInfo.environment["SCION_SWIFTUI_DUMP"] != nil { print(t) }
        let bar = x(t, "Bar"), fixed0 = x(t, "Fixed"), counter = x(t, "Counter")
        ok(bar > -9999 && fixed0 > -9999 && counter > -9999, "the views")

        // frames on curves
        animate(.linear(duration: 1)) { m.wide = true }
        ok(near(x(at(0.5), "Bar"), bar + 50), "linear: halfway at half time (\(x(at(0.5), "Bar")), from \(bar))")
        ok(x(at(1.01), "Bar") == bar + 100, "linear: in place at the end (\(x(at(1.01), "Bar")))")
        animate(.easeIn(duration: 1)) { m.wide = false }
        let e = x(at(0.5), "Bar") - bar
        ok(e >= 60 && e <= 75, "easeIn: a third of the way at half time (\(e) of 100 left)")
        ok(x(at(1.01), "Bar") == bar, "easeIn: in place at the end")
        animate(.spring(response: 0.5, dampingFraction: 0.5)) { m.wide = true }
        ok(x(at(0.29), "Bar") > bar + 105, "spring: overshoots (\(x(at(0.29), "Bar") - bar))")
        ok(x(at(5), "Bar") == bar + 100, "spring: settles")
        animate(.linear(duration: 1).delay(1)) { m.wide = false }
        ok(x(at(0.5), "Bar") == bar + 100, "delay: nothing moves before it")
        ok(near(x(at(1.5), "Bar"), bar + 50), "delay: halfway after it (\(x(at(1.5), "Bar") - bar))")
        ok(x(at(2.1), "Bar") == bar, "delay: in place at the end")

        // a view goes away, then comes back: it moves out to the leading edge (and in), the view after it slides
        animate(.linear(duration: 1)) { m.show = false }
        let half = at(0.5)   // (before the end: an animation that is over is gone)
        t = at(1.01)
        let fixed1 = x(t, "Fixed")
        ok(fixed1 < fixed0 && !t.contains("\"Here\""), "removed: gone at the end (Fixed \(fixed0) -> \(fixed1))")
        ok(half.contains("ghost") && (line(half, "Here")?.contains("fx=1.00,-") ?? false), "removed: moving out at half time (\(line(half, "Here") ?? "none"))")
        ok(near(x(half, "Fixed"), (fixed0 + fixed1) / 2), "removed: the next view halfway (\(x(half, "Fixed")))")
        animate(.linear(duration: 1)) { m.show = true }
        t = at(0.5)
        ok(!t.contains("ghost") && (line(t, "Here")?.contains("fx=1.00,-") ?? false), "inserted: moving in at half time (\(line(t, "Here") ?? "none"))")
        t = at(1.01)
        ok(!(line(t, "Here")?.contains("fx=") ?? true) && x(t, "Fixed") == fixed0, "inserted: in place at the end")

        // opacity, rotation and scale
        animate(.linear(duration: 1)) { m.faded = true }
        t = at(0.5)
        ok(t.contains("alpha=0.60"), "opacity halfway (\(show(t, "alpha")))")
        t = at(1.01)
        ok(t.contains("alpha=0.20"), "opacity at the end (\(show(t, "alpha")))")
        animate(.linear(duration: 1)) { m.turned = true }
        t = at(0.5)
        ok(t.contains("rot=45.00") && t.contains("scale=1.50"), "rotation and scale halfway (\(show(t, "rot=")))")
        t = at(1.01)
        ok(t.contains("rot=90.00") && t.contains("scale=2.00"), "rotation and scale at the end (\(show(t, "rot=")))")

        // animation(_:value:): a change made without withAnimation
        animate(nil) { m.count = 1 }
        ok(near(x(at(0.5), "Counter"), counter + 5), "animation(_:value:) halfway (\(x(at(0.5), "Counter") - counter))")
        ok(x(at(1.01), "Counter") == counter + 10, "animation(_:value:) at the end")
        animate(nil) { m.wide = true }
        ok(x(at(0), "Bar") == bar + 100, "a change without an animation is in place at once")

        // the real clock, and a completion
        _mwTestAnimationTime(nil)
        var done = false
        withAnimation(.linear(duration: 0.2), { m.wide = false }, completion: { done = true })
        pause(0.8)
        ok(done, "withAnimation's completion")
        ok(x(_mwTestDump(v), "Bar") == bar, "on the real clock: in place at the end")

        if let e = getenv("SWIFTUI_WAIT"), let s = Double(String(cString: e)) { pause(s) }   // for screenshots
        print(failures.isEmpty ? "ANIMATION OK" : "ANIMATION: \(failures.count) FAILURES: \(failures.joined(separator: "; "))")
        fflush(stdout)
        exit(failures.isEmpty ? 0 : 1)
    }
}

@main
struct TestApp: App {
    var body: some Scene {
        WindowGroup("Animation test") { Content() }
    }
}
