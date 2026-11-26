// navigation.swift: NavigationStack (values with navigationDestination(for:), destination links, a bound path,
// navigationDestination(isPresented:), back), NavigationSplitView with list links, navigationTitle as the window's
// title, Grid/GridRow, LazyVStack and LazyHGrid. Once it appears it presses its own links through scion's test hooks
// and checks the laid-out tree. Prints "NAVIGATION OK" when everything matches.
import SwiftUI
@_spi(ScionTest) import SwiftUI
import AppKit

final class Model: ObservableObject {
    static let shared = Model()
    @Published var path: [Int] = []
    @Published var showPresented = false
}

struct NumberView: View {
    let n: Int
    var body: some View {
        VStack {
            Text("Number \(n)")
            NavigationLink { Text("Deep view") } label: { Text("Deeper") }
        }
        .navigationTitle("Number \(n)")
    }
}

struct StackSide: View {
    @ObservedObject var model = Model.shared
    var body: some View {
        NavigationStack(path: $model.path) {
            VStack {
                Text("Home")
                NavigationLink("Go to 1", value: 1)
                Button("Present") { model.showPresented = true }
            }
            .navigationTitle("Home")
            .navigationDestination(for: Int.self) { NumberView(n: $0) }
            .navigationDestination(isPresented: $model.showPresented) { Text("Presented view") }
        }
        .frame(width: 260, height: 220)
    }
}

struct SplitSide: View {
    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink("Sidebar A") { Text("Detail A") }
                NavigationLink("Sidebar B", value: "b")
            }
            .navigationDestination(for: String.self) { Text("Detail \($0)") }
            .navigationSplitViewColumnWidth(120)
        } detail: {
            Text("Pick one")
        }
        .frame(width: 360, height: 220)
    }
}

struct Grids: View {
    var body: some View {
        HStack(alignment: .top) {
            Grid(alignment: .leading) {
                GridRow { Text("r1c1"); Text("wide cell r1c2") }
                GridRow { Text("r2c1 longer"); Text("x") }
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow { Text("span").gridCellColumns(2) }
            }
            LazyVStack(alignment: .leading) { Text("lv1"); Text("lv2") }
            LazyHGrid(rows: [GridItem(.fixed(20)), GridItem(.fixed(20))]) {
                ForEach(0..<4) { Text("h\($0)") }
            }
        }
    }
}

struct Content: View {
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) { StackSide(); SplitSide() }
            Grids()
        }
        .padding()
        .frame(width: 700)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Test.run() } }
    }
}

enum Test {
    static var failures: [String] = []
    static var view: NSView?
    /// a failure, with the texts the window shows (the test runner keeps only the end of the output)
    static func ok(_ c: Bool, _ what: String) {
        guard !c else { return }
        let texts = view.map { _mwTestDump($0).split(separator: "\n").compactMap { l in l.firstIndex(of: "\"").map { String(l[$0...]) } } } ?? []
        print("FAIL: \(what) [shows \(texts.prefix(12).joined(separator: " "))]")
        failures.append(what)
    }
    static func pause(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
    /// the frame of the text node showing `text` in the dump: x, y, width, height
    static func frame(_ tree: String, _ text: String) -> [Int]? {
        guard let line = tree.split(separator: "\n").first(where: { $0.hasSuffix("\"\(text)\"") }) else { return nil }
        let parts = line.split(separator: " ").filter { !$0.isEmpty }
        guard parts.count >= 3 else { return nil }
        let xy = parts[1].split(separator: ",").compactMap { Int($0) }, wh = parts[2].split(separator: "x").compactMap { Int($0) }
        return xy.count == 2 && wh.count == 2 ? xy + wh : nil
    }
    static func run() {
        guard let w = NSApplication.shared.windows.first, let v = w.contentView else { print("FAIL: no window"); exit(1) }
        let model = Model.shared
        view = v
        var tree = _mwTestDump(v)
        if ProcessInfo.processInfo.environment["SCION_SWIFTUI_DUMP"] != nil { print(tree) }
        ok(tree.contains("\"Home\""), "stack root")
        ok(tree.contains("\"Pick one\"") && tree.contains("\"Sidebar A\""), "split view columns")
        ok(w.title == "Home", "navigationTitle as the window's title (\(w.title))")

        // a value link, then a destination link, then back
        ok(_mwTestTap(v, "Go to 1"), "press Go to 1")
        pause()
        tree = _mwTestDump(v)
        ok(tree.contains("\"Number 1\"") && !tree.contains("\"Go to 1\""), "navigationDestination(for:) shows the value")
        ok(model.path == [1], "the bound path has the value (\(model.path))")
        ok(tree.contains("\"‹ Home\""), "a back button named after the previous title")
        ok(w.title == "Number 1", "the title follows the stack (\(w.title))")
        ok(_mwTestTap(v, "Deeper"), "press Deeper")
        pause()
        ok(_mwTestDump(v).contains("\"Deep view\""), "a destination link")
        ok(_mwTestTap(v, "‹ Number 1"), "press back")
        pause()
        tree = _mwTestDump(v)
        ok(!tree.contains("\"Deep view\"") && tree.contains("\"Deeper\""), "back pops one view")
        model.path = []
        pause()
        ok(_mwTestDump(v).contains("\"Go to 1\""), "emptying the path shows the root")

        // a destination presented by a binding
        ok(_mwTestTap(v, "Present"), "press Present")
        pause()
        ok(_mwTestDump(v).contains("\"Presented view\""), "navigationDestination(isPresented:)")
        ok(_mwTestTap(v, "‹ Home"), "press back from the presented view")
        pause()
        ok(!model.showPresented && _mwTestDump(v).contains("\"Go to 1\""), "back clears the binding")

        // the split view: list links show in the detail column
        ok(_mwTestTap(v, "Sidebar A"), "press Sidebar A")
        pause()
        tree = _mwTestDump(v)
        ok(tree.contains("\"Detail A\"") && !tree.contains("\"Pick one\""), "a sidebar link shows its destination")
        ok(_mwTestTap(v, "Sidebar B"), "press Sidebar B")
        pause()
        tree = _mwTestDump(v)
        ok(tree.contains("\"Detail b\"") && !tree.contains("\"Detail A\""), "a sidebar value link")
        if let a = frame(tree, "Sidebar A"), let d = frame(tree, "Detail b") { ok(d[0] > a[0] + 100, "the detail column is right of the 120-wide sidebar") }
        else { ok(false, "sidebar and detail frames") }

        // grids and lazy stacks
        if let a = frame(tree, "r1c1"), let b = frame(tree, "r2c1 longer"), let c = frame(tree, "wide cell r1c2"), let d = frame(tree, "x"),
           let s = frame(tree, "span") {
            ok(a[0] == b[0] && c[0] == d[0], "grid columns line up")
            ok(c[0] >= b[0] + b[2], "a column is as wide as its widest cell")
            ok(s[1] > b[1] && s[0] == a[0], "a spanning cell in the last row")
        } else { ok(false, "grid cells") }
        if let a = frame(tree, "lv1"), let b = frame(tree, "lv2") { ok(b[1] > a[1] && a[0] == b[0], "LazyVStack") } else { ok(false, "LazyVStack cells") }
        if let h0 = frame(tree, "h0"), let h1 = frame(tree, "h1"), let h2 = frame(tree, "h2") {
            ok(h1[1] > h0[1] && h2[0] > h0[0], "LazyHGrid fills columns of two rows")
        } else { ok(false, "LazyHGrid cells") }

        if let e = getenv("SWIFTUI_WAIT"), let s = Double(String(cString: e)) { pause(s) }   // for screenshots
        print(failures.isEmpty ? "NAVIGATION OK" : "NAVIGATION: \(failures.count) FAILURES: \(failures.joined(separator: "; "))")
        fflush(stdout)
        exit(failures.isEmpty ? 0 : 1)
    }
}

@main
struct TestApp: App {
    var body: some Scene {
        WindowGroup("Navigation test") { Content() }
    }
}
