// concurrency.swift: Swift Concurrency (async/await, Task, TaskGroup, actors, AsyncStream, Task.sleep, cancellation,
// continuations and MainActor). Prints "CONCURRENCY OK" when every check passes.
var failures = 0
func ok(_ c: Bool, _ what: String) { if !c { print("FAIL: \(what)"); failures += 1 } }

actor Counter {
    var n = 0
    func add(_ k: Int) { n += k }
}

func twice(_ x: Int) async -> Int { await Task.yield(); return x * 2 }

func slow() async throws -> Int {
    try await Task.sleep(nanoseconds: 50_000_000)
    return 7
}

@MainActor func onMain() -> Bool { true }

@main struct Main {
    static func main() async {
        ok(await twice(21) == 42, "await")
        let t = Task { await twice(5) }
        ok(await t.value == 10, "Task.value")

        let total = await withTaskGroup(of: Int.self) { g -> Int in
            for i in 1...100 { g.addTask { await twice(i) } }
            var s = 0
            for await v in g { s += v }
            return s
        }
        ok(total == 10100, "TaskGroup")

        let c = Counter()
        await withTaskGroup(of: Void.self) { g in for _ in 0..<1000 { g.addTask { await c.add(1) } } }
        ok(await c.n == 1000, "actor")

        let stream = AsyncStream<Int> { cont in
            Task { for i in 0..<5 { cont.yield(i) }; cont.finish() }
        }
        var seen: [Int] = []
        for await v in stream { seen.append(v) }
        ok(seen == [0, 1, 2, 3, 4], "AsyncStream")

        let before = ContinuousClock.now
        ok((try? await slow()) == 7, "Task.sleep")
        ok(ContinuousClock.now - before >= .milliseconds(40), "the sleep lasts")

        let cancelled = Task { () -> Bool in
            do { try await Task.sleep(nanoseconds: 5_000_000_000); return false } catch { return error is CancellationError }
        }
        cancelled.cancel()
        ok(await cancelled.value, "cancellation")

        let v = await withCheckedContinuation { (k: CheckedContinuation<Int, Never>) in
            Task.detached { k.resume(returning: 99) }
        }
        ok(v == 99, "continuation")
        ok(await onMain(), "MainActor")

        async let a = twice(1), b = twice(2)
        ok(await a + b == 6, "async let")

        print(failures == 0 ? "CONCURRENCY OK" : "CONCURRENCY: \(failures) FAILURES")
    }
}
