// language.swift — the Swift language on scion's libswiftCore: strings, collections, classes (inheritance, deinit,
// weak references), generics (generic classes are realized at run time), protocols and existentials, enums, errors,
// closures, key paths, mirrors and dynamic casts. Prints "SWIFT OK" when every check passes.

var fails = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "  ok: \(what)" : "  FAIL: \(what)"); if !ok { fails += 1 } }

// strings and characters
let s = "Hola, señor 👋🏽"
check(s.count == 13 && s.utf8.count == 21, "String: graphemes \(s.count), UTF-8 \(s.utf8.count)")
check(s.uppercased() == "HOLA, SEÑOR 👋🏽" && s.hasPrefix("Hola") && s.split(separator: ",").count == 2, "uppercased, hasPrefix, split")
check("\(42) \(3.5) \(true) \([1, 2])" == "42 3.5 true [1, 2]", "string interpolation")
check(Int("123") == 123 && Double("2.5") == 2.5 && Int("x") == nil, "parsing numbers")
var big = ""
for i in 0..<1000 { big += String(i % 10) }
check(big.count == 1000 && big.reversed().first == "9", "growing a long string")

// collections
var a = [5, 3, 9, 1]
a.sort()
check(a == [1, 3, 5, 9] && a.map { $0 * 2 }.reduce(0, +) == 36 && a.filter { $0 > 2 }.count == 3, "Array: sort, map, reduce, filter")
var d: [String: Int] = [:]
for w in "one two three two one one".split(separator: " ") { d[String(w), default: 0] += 1 }
check(d["one"] == 3 && d["two"] == 2 && d.count == 3, "Dictionary counting")
let set: Set = [1, 2, 3, 2, 1]
check(set.count == 3 && set.contains(2) && set.union([4]).count == 4, "Set")
check(Array(zip([1, 2, 3], ["a", "b", "c"])).last! == (3, "c"), "zip")

// classes: inheritance, dynamic dispatch, deinit, weak and unowned references
var deinits = 0
class Animal { let name: String; init(name: String) { self.name = name }; func sound() -> String { "..." }; deinit { deinits += 1 } }
final class Dog: Animal { override func sound() -> String { "woof" } }
class Cat: Animal { override func sound() -> String { "meow" } }
do {
    let zoo: [Animal] = [Dog(name: "Rex"), Cat(name: "Tom")]
    check(zoo.map { $0.sound() } == ["woof", "meow"], "dynamic dispatch")
    check(zoo[0] is Dog && (zoo[1] as? Dog) == nil && type(of: zoo[1]) == Cat.self, "is / as? / type(of:)")
}
check(deinits == 2, "deinit when the last reference goes (\(deinits))")
class Node { var next: Node?; weak var parent: Node?; deinit { deinits += 1 } }
do {
    let p = Node(); let c = Node(); p.next = c; c.parent = p
    check(c.parent === p, "weak reference while alive")
}
check(deinits == 4, "no retain cycle through weak (\(deinits))")
var weakOne: Node? = Node()
weak var w = weakOne
weakOne = nil
check(w == nil, "weak reference becomes nil")

// generics: functions, structs and classes (generic class metadata is made at run time)
func largest<T: Comparable>(_ xs: [T]) -> T? { xs.max() }
struct Stack<Element> { private var items: [Element] = []; mutating func push(_ e: Element) { items.append(e) }; mutating func pop() -> Element? { items.popLast() } }
class Box<T> { var value: T; init(_ v: T) { value = v } }
class LabeledBox<T>: Box<T> { var label = "box" }
var st = Stack<String>(); st.push("a"); st.push("b")
check(largest([3, 8, 2]) == 8 && largest(["b", "z", "a"]) == "z" && st.pop() == "b", "generic functions and structs")
let boxes: [AnyObject] = [Box(1), Box("dos"), LabeledBox(3.0)]
check((boxes[0] as? Box<Int>)?.value == 1 && (boxes[1] as? Box<String>)?.value == "dos" && boxes[2] is Box<Double>, "generic classes and casts")
check("\(type(of: boxes[2]))" == "LabeledBox<Double>", "generic class names (\(type(of: boxes[2])))")

// protocols, extensions, existentials, associated types
protocol Shape { var area: Double { get }; var name: String { get } }
extension Shape { var name: String { "shape" } }
struct Square: Shape { var side: Double; var area: Double { side * side }; var name: String { "square" } }
struct Circle: Shape { var r: Double; var area: Double { 3.0 * r * r } }
let shapes: [any Shape] = [Square(side: 2), Circle(r: 1)]
check(shapes.map(\.area) == [4, 3] && shapes.map(\.name) == ["square", "shape"], "protocols, default implementations, key paths")
check(shapes[0] is Square && !(shapes[1] is Square), "existential casts")
extension Int { var squared: Int { self * self } }
check(7.squared == 49, "extensions on standard types")

// enums, pattern matching, errors
enum Token: Equatable { case number(Int), word(String), end }
func tokens(_ str: String) -> [Token] { str.split(separator: " ").map { Int($0).map(Token.number) ?? .word(String($0)) } + [.end] }
check(tokens("add 2 and 3") == [.word("add"), .number(2), .word("and"), .number(3), .end], "enums with associated values")
enum ParseError: Error { case empty, bad(String) }
func parse(_ x: String) throws -> Int { if x.isEmpty { throw ParseError.empty }; guard let v = Int(x) else { throw ParseError.bad(x) }; return v }
var caught = ""
do { _ = try parse("12"); _ = try parse("twelve") } catch ParseError.bad(let v) { caught = v } catch { caught = "other" }
check(caught == "twelve" && (try? parse("")) == nil, "throw / catch / try?")
let r: Result<Int, ParseError> = Result { try parse("7") }.mapError { $0 as! ParseError }
check((try? r.get()) == 7, "Result")

// closures capturing state, escaping closures, sorting with closures
func counter() -> () -> Int { var n = 0; return { n += 1; return n } }
let next = counter(); _ = next(); _ = next()
check(next() == 3, "closures capture state")
let people = [("Ana", 31), ("Luis", 25), ("Eva", 40)]
check(people.sorted { $0.1 < $1.1 }.map(\.0) == ["Luis", "Ana", "Eva"], "sorting tuples with a closure")

// reflection and dynamic features
struct Point { var x = 1, y = 2 }
let labels = Mirror(reflecting: Point()).children.compactMap(\.label)
check(labels == ["x", "y"], "Mirror")
var dumped = ""
dump(Point(), to: &dumped)
check(dumped.indices.contains { dumped[$0...].hasPrefix("x: 1") }, "dump")
let any: Any = 3.5
check((any as? Double) == 3.5 && (any as? Int) == nil, "Any casts")
let anyHashables: Set<AnyHashable> = [1, "one", 1.5]
check(anyHashables.contains("one") && anyHashables.count == 3, "AnyHashable")

// numbers
check(Int.max &+ 1 == Int.min && (1 << 62).leadingZeroBitCount == 1 && Double.pi > 3.14159 && (2.0).squareRoot() > 1.414, "integer and floating point")
check(String(255, radix: 16) == "ff" && UInt8(truncatingIfNeeded: 300) == 44, "radix and truncation")

print(fails == 0 ? "SWIFT OK" : "SWIFT FAIL (\(fails))")
