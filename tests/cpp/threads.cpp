// Thread stress test: repeats the threading part of cxx.cpp and writes to stderr which step starts, to see where it
// dies if it does. Usage: threads [rounds]
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <thread>
#include <vector>
int main(int argc, char **argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : 200, fails = 0;
    for (int it = 0; it < rounds; it++) {
        fprintf(stderr, "%d:a ", it);
        std::atomic<int> cnt{0}; std::mutex mu; long total = 0;
        std::vector<std::thread> ts;
        for (int i = 0; i < 4; i++) ts.emplace_back([&, i] { for (int j = 0; j < 10000; j++) { cnt++; std::lock_guard<std::mutex> g(mu); total += i; } });
        for (auto &t : ts) t.join();
        if (!(cnt == 40000 && total == 60000)) { printf("FAIL mutex round %d\n", it); fails++; }
        fprintf(stderr, "b ");
        std::atomic<int> flag{0};
        std::thread w([&] { flag.wait(0); flag = 2; });
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        flag = 1; flag.notify_one(); w.join();
        if (flag != 2) { printf("FAIL wait/notify round %d\n", it); fails++; }
        fprintf(stderr, "c ");
        std::thread([] { try { throw 1; } catch (int) {} }).join();
        fprintf(stderr, "d\n");
    }
    printf(fails ? "THREADS FAIL\n" : "THREADS OK\n");
    return fails;
}
