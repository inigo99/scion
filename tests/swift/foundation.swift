// foundation.swift: Swift's Foundation overlay on scion's Foundation — String/NSString bridging, Data, URL, JSON
// coding, collections bridging, Date/Calendar/DateFormatter, CharacterSet, IndexSet, UUID, Decimal, errors.
import Foundation

var fails = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) { if !ok { fails += 1; print("FAIL (\(line)): \(what)") } }

// String <-> NSString
let ns: NSString = "hello moon"
let s = ns as String
check(s == "hello moon", "NSString as String")
check((s as NSString).length == 10, "String as NSString")
check(s.components(separatedBy: " ") == ["hello", "moon"], "components(separatedBy:)")
check(s.trimmingCharacters(in: .whitespaces) == s, "trimmingCharacters")
check("  x \n".trimmingCharacters(in: .whitespacesAndNewlines) == "x", "trimming newlines")
check(s.range(of: "moon") != nil, "range(of:)")
check(s.replacingOccurrences(of: "moon", with: "scion") == "hello scion", "replacingOccurrences")
check(String(format: "%d-%@-%.2f", 42, "x", 3.14159) == "42-x-3.14", "String(format:)")
check("ñandú".uppercased() == "ÑANDÚ", "uppercased")
check(s.hasPrefix("hello") && s.hasSuffix("moon"), "prefix/suffix")

// Data
let d = "abc".data(using: .utf8)!
check(d.count == 3 && d[0] == 0x61, "data(using:)")
check(String(data: d, encoding: .utf8) == "abc", "String(data:encoding:)")
check(d.base64EncodedString() == "YWJj", "base64")
check(Data(base64Encoded: "YWJj") == d, "Data(base64Encoded:)")
var m = Data(); m.append(contentsOf: [1, 2, 3]); m.append(d)
check(m.count == 6 && Array(m.prefix(3)) == [1, 2, 3], "Data append")
let nsd = m as NSData
check(nsd.length == 6, "Data as NSData")

// collections
let arr: NSArray = [1, 2, 3]
check((arr as! [Int]) == [1, 2, 3], "NSArray as [Int]")
let dict = ["a": 1, "b": 2] as NSDictionary
check((dict as! [String: Int])["b"] == 2, "NSDictionary bridging")
check((Set(["x", "y"]) as NSSet).count == 2, "Set as NSSet")

// URL
let u = URL(string: "https://user@example.com:8080/a/b.txt?q=1#frag")!
check(u.scheme == "https" && u.host == "example.com" && u.port == 8080, "URL parts")
check(u.path == "/a/b.txt" && u.lastPathComponent == "b.txt" && u.pathExtension == "txt", "URL path")
let f = URL(fileURLWithPath: "/tmp/x/y.json")
check(f.isFileURL && f.deletingLastPathComponent().path == "/tmp/x", "file URL")
check(f.appendingPathComponent("z").path == "/tmp/x/y.json/z", "appendingPathComponent")
var comps = URLComponents(string: "http://h/p?a=1&b=two")!
check(comps.queryItems?.count == 2 && comps.queryItems?[1].value == "two", "URLComponents.queryItems")
comps.queryItems = [URLQueryItem(name: "k", value: "v")]
check(comps.url?.absoluteString == "http://h/p?k=v", "URLComponents.url")

// JSON
struct Person: Codable, Equatable { var name: String; var age: Int; var tags: [String]; var extra: Double? }
let p = Person(name: "Ana", age: 30, tags: ["a", "b"], extra: 1.5)
let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
let json = try! enc.encode(p)
check(String(data: json, encoding: .utf8) == #"{"age":30,"extra":1.5,"name":"Ana","tags":["a","b"]}"#, "JSONEncoder: \(String(data: json, encoding: .utf8) ?? "nil")")
let back = try! JSONDecoder().decode(Person.self, from: json)
check(back == p, "JSONDecoder")
do { _ = try JSONDecoder().decode(Person.self, from: Data("{}".utf8)); check(false, "decode should throw") }
catch DecodingError.keyNotFound(let k, _) { check(k.stringValue == "name", "keyNotFound key") }
catch { check(false, "wrong error \(error)") }
let obj = try! JSONSerialization.jsonObject(with: Data(#"{"x":[1,2]}"#.utf8)) as! [String: Any]
check((obj["x"] as! [Int]) == [1, 2], "JSONSerialization")

// dates
let ref = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: ref)
check(c.year == 2023 && c.month == 11 && c.day == 14 && c.hour == 22 && c.minute == 13 && c.weekday == 3, "dateComponents \(c)")
let next = cal.date(byAdding: .month, value: 3, to: ref)!
check(cal.component(.month, from: next) == 2 && cal.component(.year, from: next) == 2024, "date(byAdding:)")
check(cal.date(from: DateComponents(year: 2024, month: 2, day: 29))!.timeIntervalSince1970 == 1_709_164_800, "date(from:)")
check(cal.range(of: .day, in: .month, for: next) == 1..<30, "range(of:in:for:) leap February")
let df = DateFormatter(); df.timeZone = TimeZone(secondsFromGMT: 0); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
check(df.string(from: ref) == "2023-11-14 22:13:20", "DateFormatter.string")
check(df.date(from: "2023-11-14 22:13:20") == ref, "DateFormatter.date")
let iso = ISO8601DateFormatter()
check(iso.string(from: ref) == "2023-11-14T22:13:20Z", "ISO8601DateFormatter \(iso.string(from: ref))")
check(iso.date(from: "2023-11-14T23:13:20+01:00") == ref, "ISO8601 parse with offset")
let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
struct E: Codable { var t: Date }
check(try! dec.decode(E.self, from: Data(#"{"t":"2023-11-14T22:13:20Z"}"#.utf8)).t == ref, ".iso8601 strategy")
check(TimeZone(identifier: "Europe/Madrid")!.secondsFromGMT(for: ref) == 3600, "TimeZone")
check(Locale(identifier: "es_ES").languageCode == "es", "Locale")

// CharacterSet, IndexSet, UUID, Decimal
var cs = CharacterSet.letters; cs.insert(charactersIn: "_")
check(cs.contains("_") && cs.contains("a") && !cs.contains("1"), "CharacterSet")
check("a-b_c".components(separatedBy: CharacterSet(charactersIn: "-_")) == ["a", "b", "c"], "components(separatedBy: CharacterSet)")
check("a b".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) == "a%20b", "addingPercentEncoding")
var ix = IndexSet(integersIn: 2..<5); ix.insert(9); ix.remove(3)
check(Array(ix) == [2, 4, 9] && ix.count == 3, "IndexSet \(Array(ix))")
let uu = UUID()
check(UUID(uuidString: uu.uuidString) == uu && uu.uuidString.count == 36, "UUID")
let dd = Decimal(string: "1.25")! + Decimal(2)
check(dd == Decimal(string: "3.25")!, "Decimal")

// errors
do { _ = try String(contentsOfFile: "/does/not/exist/scion", encoding: .utf8); check(false, "should throw") }
catch let e as NSError { check(e.domain == NSCocoaErrorDomain || e.domain == NSPOSIXErrorDomain, "NSError domain \(e.domain)") }
enum MyError: Error { case bad }
check((MyError.bad as NSError).domain.contains("MyError"), "Swift Error as NSError")

print(fails == 0 ? "FOUNDATION OK" : "FOUNDATION: \(fails) FAILURES")
