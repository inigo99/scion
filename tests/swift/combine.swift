// combine.swift: scion's Combine (publishers, operators, subjects, @Published/ObservableObject, Dispatch and RunLoop
// schedulers, NotificationCenter and Timer). Prints "COMBINE OK" when every check passes.
import Combine
import Foundation

var failures = 0
func ok(_ c: Bool, _ what: String) { if !c { print("FAIL: \(what)"); failures += 1 } }

final class Model: ObservableObject {
    @Published var name = "a"
    @Published var count = 0
}

var bag = Set<AnyCancellable>()
var seen: [Int] = []
[1, 2, 3, 4, 5, 6].publisher.filter { $0 % 2 == 0 }.map { $0 * 10 }.sink { seen.append($0) }.store(in: &bag)
ok(seen == [20, 40, 60], "sequence + filter + map")

var merged: [Int] = []
let s1 = PassthroughSubject<Int, Never>(), s2 = PassthroughSubject<Int, Never>()
s1.merge(with: s2).sink { merged.append($0) }.store(in: &bag)
s1.send(1); s2.send(2); s1.send(3)
ok(merged == [1, 2, 3], "merge")

var pairs: [String] = []
let cv = CurrentValueSubject<Int, Never>(1)
cv.combineLatest(Just("x")).map { "\($0)\($1)" }.sink { pairs.append($0) }.store(in: &bag)
cv.send(2)
ok(pairs == ["1x", "2x"], "combineLatest + CurrentValueSubject")

var deduped: [Int] = []
[1, 1, 2, 2, 3].publisher.removeDuplicates().dropFirst().sink { deduped.append($0) }.store(in: &bag)
ok(deduped == [2, 3], "removeDuplicates + dropFirst")

let m = Model()
var changes = 0, names: [String] = []
m.objectWillChange.sink { changes += 1 }.store(in: &bag)
m.$name.sink { names.append($0) }.store(in: &bag)
m.name = "b"; m.count = 3
ok(changes == 2, "objectWillChange")
ok(names == ["a", "b"], "@Published")

var finished = false
Just(5).first().sink(receiveCompletion: { if case .finished = $0 { finished = true } }, receiveValue: { _ in }).store(in: &bag)
ok(finished, "Just + first + completion")

// schedulers: debounce on the main queue, Timer and NotificationCenter on the run loop
var debounced: [Int] = []
let bounce = PassthroughSubject<Int, Never>()
bounce.debounce(for: .milliseconds(50), scheduler: DispatchQueue.main).sink { debounced.append($0) }.store(in: &bag)
bounce.send(1); bounce.send(2); bounce.send(3)
var ticks = 0
Timer.publish(every: 0.02, on: .main, in: .common).autoconnect().sink { _ in ticks += 1 }.store(in: &bag)
var notes = 0
NotificationCenter.default.publisher(for: Notification.Name("test")).sink { _ in notes += 1 }.store(in: &bag)
NotificationCenter.default.post(name: Notification.Name("test"), object: nil)
var delayed = false
Just(1).delay(for: .milliseconds(20), scheduler: RunLoop.main).sink { _ in delayed = true }.store(in: &bag)
RunLoop.main.run(until: Date().addingTimeInterval(0.4))
ok(debounced == [3], "debounce on DispatchQueue.main")
ok(ticks >= 3, "Timer.publish")
ok(notes == 1, "NotificationCenter.publisher")
ok(delayed, "delay on RunLoop.main")

print(failures == 0 ? "COMBINE OK" : "COMBINE: \(failures) FAILURES")
