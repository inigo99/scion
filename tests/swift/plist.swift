// plist.swift: property lists (XML, binary, OpenStep, .strings), PropertyListEncoder/Decoder, Bundle with its Info.plist
// and localized strings, and UserDefaults saved to disk. Runs as Sample.app/Contents/MacOS/Sample. Prints "PLIST OK".
import Foundation

var fails = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) { if !ok { fails += 1; print("FAIL (\(line)): \(what)") } }

// Bundle
let b = Bundle.main
check(b.bundleIdentifier == "dev.scion.sample", "bundleIdentifier \(String(describing: b.bundleIdentifier))")
check(b.infoDictionary?["CFBundleShortVersionString"] as? String == "1.2", "infoDictionary")
check(b.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String == "© 2026 <scion> & co", "XML entities")
check(NSLocalizedString("greeting", comment: "") == "Hello", "NSLocalizedString (UTF-16)")
check(NSLocalizedString("quoted", comment: "") == "say \"hi\"\n", ".strings escapes")
check(NSLocalizedString("missing_key", comment: "") == "missing_key", "untranslated key")
check(b.url(forResource: "data", withExtension: "json") != nil, "url(forResource:)")
check(b.executablePath?.hasSuffix("MacOS/Sample") == true, "executablePath")

// XML and binary round trips
let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
let dict: [String: Any] = ["text": "ñandú ✓", "integer": 42, "negative": -7, "big": 5_000_000_000, "real": 2.5,
                           "yes": true, "no": false, "date": date, "data": Data([0, 1, 2, 255]),
                           "list": ["a", 1, ["nested": true]], "empty": [String: Any](), "empty_list": [Any]()]
for fmt in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
    let data = try! PropertyListSerialization.data(fromPropertyList: dict, format: fmt, options: 0)
    var got = PropertyListSerialization.PropertyListFormat.openStep
    let back = try! PropertyListSerialization.propertyList(from: data, options: [], format: &got) as! [String: Any]
    let name = fmt == .xml ? "XML" : "binary"
    check(got == fmt, "detected format \(name)")
    check(back["text"] as? String == "ñandú ✓", "\(name) text")
    check(back["integer"] as? Int == 42 && back["negative"] as? Int == -7 && back["big"] as? Int == 5_000_000_000, "\(name) integers")
    check(back["real"] as? Double == 2.5, "\(name) real")
    check(back["yes"] as? Bool == true && back["no"] as? Bool == false, "\(name) booleans")
    check(back["date"] as? Date == date, "\(name) date")
    check(back["data"] as? Data == Data([0, 1, 2, 255]), "\(name) data")
    let list = back["list"] as? [Any]
    check(list?.count == 3 && list?[0] as? String == "a" && (list?[2] as? [String: Any])?["nested"] as? Bool == true, "\(name) list")
    check((back["empty"] as? [String: Any])?.isEmpty == true && (back["empty_list"] as? [Any])?.isEmpty == true, "\(name) empty containers")
}
let xml = String(data: try! PropertyListSerialization.data(fromPropertyList: ["k": 1], format: .xml, options: 0), encoding: .utf8)!
check(xml.contains("<key>k</key>") && xml.contains("<integer>1</integer>"), "XML written")

// OpenStep
let os = try! PropertyListSerialization.propertyList(from: Data("{ a = 1; b = (\"x\", y); c = <0102 ff>; \"d e\" = { f = g; }; }".utf8), options: [], format: nil) as! [String: Any]
check(os["a"] as? String == "1" && (os["b"] as? [String]) == ["x", "y"] && os["c"] as? Data == Data([1, 2, 255]), "OpenStep")
check((os["d e"] as? [String: String])?["f"] == "g", "nested OpenStep")

// corrupt data
check((try? PropertyListSerialization.propertyList(from: Data("bplist00garbage".utf8), options: [], format: nil)) == nil, "corrupt binary")
check((try? PropertyListSerialization.propertyList(from: Data("<plist><dict><key>a</key></dict></plist>".utf8), options: [], format: nil)) == nil, "corrupt XML")

// Codable
struct Settings: Codable, Equatable { var name: String; var level: Int; var enabled: Bool; var tamaño: Double; var tags: [String]; var when: Date }
let st = Settings(name: "scion", level: 3, enabled: true, tamaño: 1.5, tags: ["a", "b"], when: date)
for fmt in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
    let enc = PropertyListEncoder(); enc.outputFormat = fmt
    let back = try! PropertyListDecoder().decode(Settings.self, from: try! enc.encode(st))
    check(back == st, "PropertyListEncoder \(fmt.rawValue)")
}

// NSDictionary to and from files
let tmp = NSTemporaryDirectory() + "/scion_plist_test.plist"
check((["x": 1, "y": "z"] as NSDictionary).write(toFile: tmp, atomically: true), "writeToFile")
check(NSDictionary(contentsOfFile: tmp)?["y"] as? String == "z", "contentsOfFile")
try? FileManager.default.removeItem(atPath: tmp)

// UserDefaults saved on disk
let suite = "dev.scion.sample.settings"
do {
    let d = UserDefaults(suiteName: suite)!
    d.removePersistentDomain(forName: suite)
    d.set(7, forKey: "counter"); d.set("hello", forKey: "text"); d.set(true, forKey: "flag"); d.set([1, 2], forKey: "list")
    d.register(defaults: ["default_value": 9])
    check(d.integer(forKey: "default_value") == 9 && d.bool(forKey: "flag"), "UserDefaults in memory")
    check(d.synchronize(), "synchronize")
}
let saved = UserDefaults(suiteName: suite)!
check(saved.integer(forKey: "counter") == 7 && saved.string(forKey: "text") == "hello" && saved.array(forKey: "list") as? [Int] == [1, 2], "UserDefaults saved")
check(saved.object(forKey: "default_value") == nil, "registered defaults are not saved")
saved.removePersistentDomain(forName: suite)

print(fails == 0 ? "PLIST OK" : "PLIST: \(fails) FAILURES")
