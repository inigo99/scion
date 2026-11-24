// swiftui.swift: a SwiftUI app (App, WindowGroup, @State, @StateObject, @Published, Binding, stacks, Text, Button, Toggle,
// Picker, List/ForEach, TextField, Spacer, padding, frame, onAppear, onChange). Once it appears it presses its own
// controls through scion's test hooks and checks the laid-out tree. Prints "SWIFTUI OK" when everything matches.
import SwiftUI
@_spi(ScionTest) import SwiftUI
import AppKit

final class Model: ObservableObject {
    @Published var color = 0
    @Published var name = "Ana"
    @Published var items = ["one", "two", "three"]
}

struct Row: View {
    let text: String
    var body: some View {
        HStack {
            Image(systemName: "circle.fill").foregroundColor(.green)
            Text(text)
            Spacer()
        }
    }
}

struct Content: View {
    @State private var count = 0
    @State private var active = false
    @State private var changes = 0
    @StateObject private var model = Model()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Count: \(count)").font(.headline)
            HStack {
                Button("Add") { count += 1 }
                Spacer()
                Toggle("Active", isOn: $active)
            }
            Picker("Color", selection: $model.color) {
                Text("Red").tag(0)
                Text("Green").tag(1)
            }
            List {
                ForEach(model.items, id: \.self) { Row(text: $0) }
            }
            .frame(height: 80)
            TextField("Name", text: $model.name)
            Text(active ? "enabled" : "disabled")
            Text("changes \(changes)")
        }
        .padding()
        .frame(width: 320)
        .onChange(of: count) { _ in changes += 1 }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Test.run() } }
    }
}

enum Test {
    static var failures = 0
    static func ok(_ c: Bool, _ what: String) { if !c { print("FAIL: \(what)"); failures += 1 } }
    static func pause(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
    static func run() {
        guard let v = NSApplication.shared.windows.first?.contentView else { print("FAIL: no window"); exit(1) }
        var tree = _mwTestDump(v)
        if ProcessInfo.processInfo.environment["SCION_SWIFTUI_DUMP"] != nil { print(tree) }
        ok(tree.contains("\"Count: 0\""), "initial text")
        ok(tree.contains("\"three\""), "list rows")
        ok(tree.contains("_MWStackNode 16,16 288x"), "VStack with padding inside the 320-wide frame")
        ok(_mwTestTap(v, "Add"), "press Add")
        ok(_mwTestTap(v, "Active"), "press Active")
        ok(_mwTestPick(v, 1), "choose Green")
        pause()
        tree = _mwTestDump(v)
        ok(tree.contains("\"Count: 1\""), "@State after the button")
        ok(tree.contains("\"enabled\""), "Toggle with a Binding")
        ok(tree.contains("\"Green\""), "Picker with @Published")
        ok(tree.contains("\"changes 1\""), "onChange")
        ok(_mwTestTap(v, "Add"), "press Add again")
        pause()
        ok(_mwTestDump(v).contains("\"Count: 2\""), "state survives updates")
        if let e = getenv("SWIFTUI_WAIT"), let s = Double(String(cString: e)) { pause(s) }   // for screenshots
        print(failures == 0 ? "SWIFTUI OK" : "SWIFTUI: \(failures) FAILURES")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }
}

@main
struct TestApp: App {
    var body: some Scene {
        WindowGroup("SwiftUI test") { Content() }
    }
}
