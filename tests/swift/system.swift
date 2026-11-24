// system.swift — the Darwin, ObjectiveC and Dispatch overlays on scion: C library calls through Darwin, NSObject
// equality and hashing, and libdispatch from Swift (queues, sync/async, groups, semaphores, work items, timers,
// queue-specific values, DispatchTime). Prints "SYSTEM OK" when every check passes.
import Darwin
import Dispatch
import ObjectiveC

var fails = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "  ok: \(what)" : "  FAIL: \(what)"); if !ok { fails += 1 } }

// Darwin: libc through the overlay
check(getpid() > 0 && strlen("test") == 4, "getpid, strlen")
var buf = [CChar](repeating: 0, count: 64)
_ = withVaList([7, 42]) { vsnprintf(&buf, 64, "%d-%d", $0) }
check(String(cString: buf) == "7-42", "vsnprintf through withVaList")
check(sqrt(16.0) == 4 && Darwin.floor(2.7) == 2 && fabs(-1.5) == 1.5, "math")
check(POSIXErrorCode.ENOENT.rawValue == ENOENT && POSIXErrorCode(rawValue: EACCES) == .EACCES, "POSIXErrorCode")
var tv = timeval(); gettimeofday(&tv, nil)
check(tv.tv_sec > 1_600_000_000, "gettimeofday")

// ObjectiveC: NSObject from Swift
let o1 = NSObject(), o2 = NSObject()
check(o1 == o1 && o1 != o2 && Set([o1, o2, o1]).count == 2, "NSObject ==, hash (ObjectiveC overlay)")

// Dispatch
let q = DispatchQueue(label: "scion.test")
var n = 0
q.sync { n += 1 }
check(n == 1 && q.label == "scion.test", "serial queue sync, label")
let group = DispatchGroup()
let lock = DispatchSemaphore(value: 1)
var total = 0
for i in 1...100 {
    DispatchQueue.global(qos: .userInitiated).async(group: group) { lock.wait(); total += i; lock.signal() }
}
check(group.wait(timeout: .now() + 10) == .success && total == 5050, "global queue + group + semaphore (\(total))")
var order: [Int] = []
for i in 0..<10 { q.async { order.append(i) } }
q.sync {}
check(order == Array(0..<10), "serial queue keeps order")
let item = DispatchWorkItem { n += 10 }
q.async(execute: item)
item.wait()
check(n == 11, "DispatchWorkItem wait")
let cancelled = DispatchWorkItem { n += 100 }
cancelled.cancel()
q.async(execute: cancelled)
q.sync {}
check(n == 11 && cancelled.isCancelled, "cancelled work item does not run")
let notified = DispatchSemaphore(value: 0)
let first = DispatchWorkItem { n += 1 }
first.notify(queue: .global()) { notified.signal() }
q.async(execute: first)
check(notified.wait(timeout: .now() + 5) == .success && n == 12, "work item notify")
let key = DispatchSpecificKey<String>()
q.setSpecific(key: key, value: "valor")
var seen: String?
q.sync { seen = DispatchQueue.getSpecific(key: key) }
check(seen == "valor" && q.getSpecific(key: key) == "valor", "queue-specific values")
let t0 = DispatchTime.now()
let fired = DispatchSemaphore(value: 0)
var ticks = 0
let timer = DispatchSource.makeTimerSource(queue: q)
timer.schedule(deadline: .now() + .milliseconds(10), repeating: .milliseconds(10))
timer.setEventHandler { ticks += 1; if ticks == 3 { fired.signal() } }
timer.resume()
check(fired.wait(timeout: .now() + 5) == .success, "DispatchSource timer (\(ticks) ticks)")
timer.cancel()
let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
check(ms >= 20 && ms < 5000, "DispatchTime (\(Int(ms)) ms)")
let done = DispatchSemaphore(value: 0)
DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(20)) { done.signal() }
check(done.wait(timeout: .now() + 5) == .success, "asyncAfter")
var sum = 0
DispatchQueue.concurrentPerform(iterations: 10) { i in lock.wait(); sum += i; lock.signal() }
check(sum == 45, "concurrentPerform")

print(fails == 0 ? "SYSTEM OK" : "SYSTEM FAIL (\(fails))")
