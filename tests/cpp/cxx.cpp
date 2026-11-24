// Real C++ (scion's libc++ + libc++abi + libunwind): exceptions, STL, iostream, threads, regex, filesystem. Prints "CXX OK".
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
#include <map>
#include <unordered_map>
#include <memory>
#include <stdexcept>
#include <thread>
#include <mutex>
#include <atomic>
#include <functional>
#include <algorithm>
#include <regex>
#include <filesystem>
#include <fstream>
#include <chrono>
#include <cstdio>

static int fails;
#define CHECK(...) do { if (__VA_ARGS__) std::cout << "ok   " #__VA_ARGS__ "\n"; else { std::cout << "FAIL " #__VA_ARGS__ " (line " << __LINE__ << ")\n"; fails++; } } while (0)

static int destructores;
struct Raii { ~Raii() { destructores++; } };
struct MyError : std::runtime_error { int code; MyError(int c) : std::runtime_error("my error"), code(c) {} };
[[gnu::noinline]] static void throw_it(int n) { Raii r; if (n == 0) throw MyError(42); throw_it(n - 1); }

int main() {
    // exceptions
    try { throw_it(5); } catch (const MyError &e) { CHECK(e.code == 42 && std::string(e.what()) == "my error"); }
    CHECK(destructores == 6);
    try { throw 7; } catch (int x) { CHECK(x == 7); }
    try { std::vector<int>().at(3); } catch (const std::out_of_range &) { CHECK(true); }
    try { try { throw std::logic_error("a"); } catch (...) { throw; } } catch (const std::exception &e) { CHECK(std::string(e.what()) == "a"); }
    std::exception_ptr ep;
    try { throw std::runtime_error("saved"); } catch (...) { ep = std::current_exception(); }
    try { std::rethrow_exception(ep); } catch (const std::runtime_error &e) { CHECK(std::string(e.what()) == "saved"); }
    try { std::stoi("abc"); } catch (const std::invalid_argument &) { CHECK(true); }

    // STL
    std::vector<std::string> v = {"pear", "apple", "grape"};
    std::sort(v.begin(), v.end());
    CHECK(v[0] == "apple" && v[2] == "pear");
    std::map<std::string, int> m; for (auto &s : v) m[s] = (int)s.size();
    CHECK(m["pear"] == 4);
    std::unordered_map<int, std::string> um; for (int i = 0; i < 1000; i++) um[i] = std::to_string(i);
    CHECK(um.size() == 1000 && um[999] == "999");
    auto up = std::make_unique<std::string>("hello"); std::shared_ptr<int> sp = std::make_shared<int>(5);
    CHECK(*up == "hello" && *sp == 5);
    std::function<int(int)> f = [k = 3](int x) { return x * k; };
    CHECK(f(4) == 12);
    std::ostringstream os; os << 3.5 << " " << 42 << " " << std::hex << 255; CHECK(os.str() == "3.5 42 ff");
    CHECK(std::stod("2.25") == 2.25 && std::to_string(1.5) == "1.500000");

    // regex
    std::regex re(R"((\w+)@(\w+)\.com)");
    std::smatch sm; std::string mail = "write to ana@example.com today";
    CHECK(std::regex_search(mail, sm, re) && sm[1] == "ana" && sm[2] == "example");
    CHECK(std::regex_replace(std::string("a1b22c333"), std::regex("[0-9]+"), "#") == "a#b#c#");

    // threads
    std::atomic<int> cnt{0}; std::mutex mu; long total = 0;
    std::vector<std::thread> ts;
    for (int i = 0; i < 4; i++) ts.emplace_back([&, i] { for (int j = 0; j < 10000; j++) { cnt++; std::lock_guard<std::mutex> g(mu); total += i; } });
    for (auto &t : ts) t.join();
    CHECK(cnt == 40000 && total == 60000);
    std::atomic<int> flag{0};
    std::thread w([&] { flag.wait(0); flag = 2; });
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    flag = 1; flag.notify_one(); w.join();
    CHECK(flag == 2);
    try { std::thread([] { try { throw 1; } catch (int) {} }).join(); CHECK(true); } catch (...) { CHECK(false); }

    // filesystem + fstream
    namespace fs = std::filesystem;
    fs::path d = fs::temp_directory_path() / "scion_cxx";
    fs::remove_all(d); fs::create_directories(d / "sub");
    { std::ofstream o(d / "sub" / "a.txt"); o << "line1\nline2\n"; }
    std::ifstream in(d / "sub" / "a.txt"); std::string l1, l2; std::getline(in, l1); std::getline(in, l2);
    CHECK(l1 == "line1" && l2 == "line2");
    CHECK(fs::file_size(d / "sub" / "a.txt") == 12 && fs::is_directory(d / "sub"));
    int n = 0; for (auto &e : fs::recursive_directory_iterator(d)) { (void)e; n++; }
    CHECK(n == 2);
    try { fs::file_size(d / "no"); } catch (const fs::filesystem_error &e) { CHECK(e.code() == std::errc::no_such_file_or_directory); }
    fs::remove_all(d); CHECK(!fs::exists(d));

    std::cout << (fails ? "CXX: FAILURES " + std::to_string(fails) : std::string("CXX OK")) << std::endl;
    return fails;
}
