/* arm64.cpp — arm64 guests on dynarmic: memory, LSE/LRCPC2 emulation, hostcalls via SVC. */
#include "scion.h"
#include <atomic>
#include <mutex>
#include <vector>
#include <type_traits>
#include <optional>
#include <algorithm>
#include <condition_variable>
#include <dynarmic/interface/A64/a64.h>
#include <dynarmic/interface/A64/config.h>
#include <dynarmic/interface/exclusive_monitor.h>

/* ======================================================================= arm64 guest (dynarmic) */
uint32_t *g_arm_thunks;
static Dynarmic::ExclusiveMonitor *g_monitor;
/* translated code shared by the threads' JITs: a block one thread has compiled is copied by the others.
 * SCION_JIT_CACHE=0: off; =stats: counters at exit; =verify: compile anyway and report differences from the copy;
 * =selftest: every thread runs relocated copies of its own blocks (tests the relocation) */
static std::shared_ptr<Dynarmic::A64::CodeCache> g_code_cache;
static const char *g_code_cache_mode;
static std::atomic<size_t> g_cpu_ids{0};
static const size_t MAX_CPUS = 256;

/* Guest code that changes (munmap/mprotect of executable memory, sys_icache_invalidate) is logged here; every
 * JIT applies new entries before running and after each hostcall. ponytail: the log only grows. */
static std::mutex g_inv_mu;
static std::vector<std::pair<uint64_t, uint64_t>> g_inv_log;
static std::atomic<size_t> g_inv_n{0};
void arm64_invalidate(uint64_t a, uint64_t n) {
    std::lock_guard<std::mutex> l(g_inv_mu);
    g_inv_log.push_back({a, n});
    g_inv_n = g_inv_log.size();
}

/* vm_remap(copy=FALSE): dst is kept inaccessible to the host, so fastmem accesses fault and dynarmic retries them
 * through the callbacks below, which redirect to the source pages. Any page alignment works (Windows views need 64 KB).
 * ponytail: linear scan; a sorted map if programs create many aliases. */
struct Alias { uint64_t dst, len, src; };
static std::mutex g_alias_mu;
static std::vector<Alias> g_alias;                         /* writers, under g_alias_mu */
/* Readers (every memory access an instruction makes once it has touched an alias) take no lock: they look up an
 * immutable copy sorted by dst. A reader/writer lock here made such code 20x slower: a guest's memcpy that once
 * touched an alias runs every later copy through this lookup. */
static std::atomic<const std::vector<Alias> *> g_alias_snap{nullptr};
static std::vector<std::pair<const std::vector<Alias> *, uint64_t>> g_alias_old;   /* retired copies and when */
static std::atomic<size_t> g_alias_n{0};
static std::atomic<uint64_t> g_mem_gen{0};
uint64_t arm64_translate(uint64_t a) {
    const std::vector<Alias> *v = g_alias_snap.load(std::memory_order_acquire);
    if (!v) return a;
    auto it = std::upper_bound(v->begin(), v->end(), a, [](uint64_t x, const Alias &y) { return x < y.dst; });
    if (it == v->begin()) return a;
    --it;
    return a - it->dst < it->len ? it->src + (a - it->dst) : a;
}
size_t arm64_alias_count() { return g_alias_n.load(); }
/* protections changed: every thread drops the regions it last validated (they may be read-only now) */
void arm64_mem_changed() { g_mem_gen++; }
void arm64_alias_set(uint64_t dst, uint64_t len, uint64_t src) {
    if (!src && !g_alias_n.load()) return;
    std::lock_guard<std::mutex> l(g_alias_mu);
    std::vector<Alias> keep;
    for (auto &x : g_alias)
        if (x.dst + x.len <= dst || x.dst >= dst + len) keep.push_back(x);
        else { /* keep the parts outside [dst, dst+len) */
            if (x.dst < dst) keep.push_back({x.dst, dst - x.dst, x.src});
            if (x.dst + x.len > dst + len) keep.push_back({dst + len, x.dst + x.len - dst - len, x.src + (dst + len - x.dst)});
        }
    if (src) keep.push_back({dst, len, src});
    std::sort(keep.begin(), keep.end(), [](const Alias &x, const Alias &y) { return x.dst < y.dst; });
    g_alias = std::move(keep);
    g_alias_n = g_alias.size();
    /* a reader holds a copy for a single lookup (nanoseconds): copies retired more than 10 s ago can go */
    uint64_t now = (uint64_t)hc_clock(1, 0, 0, 0, 0, 0) / 1000000;
    const std::vector<Alias> *old = g_alias_snap.exchange(g_alias.empty() ? nullptr : new std::vector<Alias>(g_alias));
    if (old) g_alias_old.push_back({old, now});
    while (!g_alias_old.empty() && now - g_alias_old.front().second > 10000) { delete g_alias_old.front().first; g_alias_old.erase(g_alias_old.begin()); }
    g_mem_gen++;
}

struct ArmEnv final : Dynarmic::A64::UserCallbacks {
    Dynarmic::A64::Jit *jit = nullptr;
    Dynarmic::A64::UserConfig cfg;
    size_t inv_seen = 0;
    void apply_invalidations() {
        if (g_inv_n.load() == inv_seen) return;
        std::lock_guard<std::mutex> l(g_inv_mu);
        for (; inv_seen < g_inv_log.size(); inv_seen++) jit->InvalidateCacheRange(g_inv_log[inv_seen].first, g_inv_log[inv_seen].second);
    }
    uint64_t tpidrro = 0, tpidr = 0;
    std::atomic<uint64_t> pending{0};      /* async signals (bit n = signal n) */
    uint64_t fault_addr = 0; bool fault_write = false, faulted = false;
    uint64_t callbacks = 0, code_reads = 0;   /* slow memory accesses and instructions read to compile (SCION_THREAD_DUMP) */
    uint64_t ok_lo = 1, ok_hi = 0, okw_lo = 1, okw_hi = 0; /* last validated readable / writable region */
    /* Callback accesses are validated; a bad one halts the JIT precisely (check_halt_on_memory_access)
     * and becomes SIGSEGV/SIGBUS for the guest. Fastmem accesses fault in JIT code and land here too. */
    uint64_t gen_seen = 0;
    bool valid(uint64_t a, size_t n, bool w) {
        if (uint64_t g = g_mem_gen.load(std::memory_order_relaxed); g != gen_seen) { gen_seen = g; invalidate_ok(); }
        if (w ? (a >= okw_lo && a + n <= okw_hi) : (a >= ok_lo && a + n <= ok_hi)) return true;
        if (a < 0x10000) return false;
        uint64_t lo, hi; int prot;
        if (!host_mem_query(a, &lo, &hi, &prot) || !(prot & D_PROT_READ)) return false;
        bool wr_ok = prot & D_PROT_WRITE;
        if (a + n > hi) return valid(a, hi - a, w) && valid(hi, a + n - hi, w);
        if (w && !wr_ok) return false;
        if (w) okw_lo = lo, okw_hi = hi; else ok_lo = lo, ok_hi = hi;
        return true;
    }
    void fault(uint64_t a, bool w) {
        if (!faulted) { faulted = true; fault_addr = a; fault_write = w; jit->HaltExecution(Dynarmic::HaltReason::MemoryAbort); }
    }
    void invalidate_ok() { ok_lo = okw_lo = 1; ok_hi = okw_hi = 0; }
    template <class T> T rd(uint64_t a) { callbacks++; a = arm64_translate(a); if (!valid(a, sizeof(T), false)) { fault(a, false); return T{}; } T v; memcpy(&v, (void *)a, sizeof v); return v; }
    template <class T> void wr(uint64_t a, T v) { callbacks++; a = arm64_translate(a); if (!valid(a, sizeof(T), true)) { fault(a, true); return; } memcpy((void *)a, &v, sizeof v); }
    template <class T> bool cas(uint64_t a, T v, T exp) {
        a = arm64_translate(a);
        if (!valid(a, sizeof(T), true)) { fault(a, true); return false; }
        return __atomic_compare_exchange_n((T *)a, &exp, v, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    }
    /* the slow path: accesses that fastmem cannot take (faults, vm_remap aliases, exclusives) */
    uint8_t MemoryRead8(uint64_t a) override { return rd<uint8_t>(a); }
    uint16_t MemoryRead16(uint64_t a) override { return rd<uint16_t>(a); }
    uint32_t MemoryRead32(uint64_t a) override { return rd<uint32_t>(a); }
    std::optional<uint32_t> MemoryReadCode(uint64_t a) override { code_reads++; callbacks--; return rd<uint32_t>(a); }
    uint64_t MemoryRead64(uint64_t a) override { return rd<uint64_t>(a); }
    Dynarmic::A64::Vector MemoryRead128(uint64_t a) override { return rd<Dynarmic::A64::Vector>(a); }
    void MemoryWrite8(uint64_t a, uint8_t v) override { wr(a, v); }
    void MemoryWrite16(uint64_t a, uint16_t v) override { wr(a, v); }
    void MemoryWrite32(uint64_t a, uint32_t v) override { wr(a, v); }
    void MemoryWrite64(uint64_t a, uint64_t v) override { wr(a, v); }
    void MemoryWrite128(uint64_t a, Dynarmic::A64::Vector v) override { wr(a, v); }
    bool MemoryWriteExclusive8(uint64_t a, uint8_t v, uint8_t e) override { return cas(a, v, e); }
    bool MemoryWriteExclusive16(uint64_t a, uint16_t v, uint16_t e) override { return cas(a, v, e); }
    bool MemoryWriteExclusive32(uint64_t a, uint32_t v, uint32_t e) override { return cas(a, v, e); }
    bool MemoryWriteExclusive64(uint64_t a, uint64_t v, uint64_t e) override { return cas(a, v, e); }
    bool MemoryWriteExclusive128(uint64_t a, Dynarmic::A64::Vector v, Dynarmic::A64::Vector e) override {
        a = arm64_translate(a);
        if (!valid(a, 16, true)) { fault(a, true); return false; }
        uint64_t lo = e[0], hi = e[1]; bool ok;
        asm volatile("lock cmpxchg16b %1" : "=@ccz"(ok), "+m"(*(volatile unsigned __int128 *)a), "+a"(lo), "+d"(hi) : "b"(v[0]), "c"(v[1]) : "memory");
        return ok;
    }
    void InterpreterFallback(uint64_t pc, size_t) override {
        uint32_t insn = rd<uint32_t>(pc);
        if (lse(pc, insn)) { if (!faulted) jit->SetPC(pc + 4); else jit->SetPC(pc); return; }
        /* ARMv8.3 pointer authentication on registers (PACIA..AUTDZB, XPACI/XPACD): arm64 (not arm64e) code never
           signs, so adding, checking or stripping a signature leaves the value as it is (clang emits XPACI for
           __builtin_return_address on Apple targets) */
        if ((insn & 0xffff0000) == 0xdac10000 && ((insn >> 10) & 0x3f) <= 0x11) { jit->SetPC(pc + 4); return; }
        fprintf(stderr, "scion: unsupported arm64 instruction %08x at pc=%llx\n", rd<uint32_t>(pc), (unsigned long long)pc);
        hc_exit(126, 0, 0, 0, 0, 0);
    }
    /* ARMv8.1 LSE atomics (Apple Silicon code uses them everywhere; dynarmic only knows v8.0 LL/SC).
     * Executed here with host atomics: guest VA == host VA. */
    uint64_t reg(int r) { return r == 31 ? 0 : jit->GetRegister(r); }
    void setreg(int r, uint64_t v) { if (r != 31) jit->SetRegister(r, v); }
    template <class T> bool lse_op(uint32_t i, int opc, bool swp) {
        int rs = (i >> 16) & 31, rn = (i >> 5) & 31, rt = i & 31;
        T *m = (T *)arm64_translate(rn == 31 ? jit->GetSP() : jit->GetRegister(rn)), v = (T)reg(rs), old;
        if (!valid((uint64_t)m, sizeof(T), true)) { fault((uint64_t)m, true); return true; }
        typedef std::make_signed_t<T> S;
        if (swp) old = __atomic_exchange_n(m, v, __ATOMIC_SEQ_CST);
        else switch (opc) {
        case 0: old = __atomic_fetch_add(m, v, __ATOMIC_SEQ_CST); break;
        case 1: old = __atomic_fetch_and(m, (T)~v, __ATOMIC_SEQ_CST); break;
        case 2: old = __atomic_fetch_xor(m, v, __ATOMIC_SEQ_CST); break;
        case 3: old = __atomic_fetch_or(m, v, __ATOMIC_SEQ_CST); break;
        default: {
            old = __atomic_load_n(m, __ATOMIC_SEQ_CST);
            for (;;) {
                T nv = opc == 4 ? ((S)old > (S)v ? old : v) : opc == 5 ? ((S)old < (S)v ? old : v)
                     : opc == 6 ? (old > v ? old : v) : (old < v ? old : v);
                if (__atomic_compare_exchange_n(m, &old, nv, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) break;
            }
        }
        }
        setreg(rt, (uint64_t)old);
        return true;
    }
    template <class T> bool cas_op(uint32_t i) {
        int rs = (i >> 16) & 31, rn = (i >> 5) & 31, rt = i & 31;
        T *m = (T *)arm64_translate(rn == 31 ? jit->GetSP() : jit->GetRegister(rn)), exp = (T)reg(rs);
        if (!valid((uint64_t)m, sizeof(T), true)) { fault((uint64_t)m, true); return true; }
        __atomic_compare_exchange_n(m, &exp, (T)reg(rt), false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
        setreg(rs, (uint64_t)exp); /* Rs receives the old value either way */
        return true;
    }
    bool lse(uint64_t pc, uint32_t i) {
        int size = i >> 30;
        if ((i & 0x3F200C00) == 0x38200000) { /* LDADD/LDCLR/LDEOR/LDSET/LD{S,U}{MAX,MIN}/SWP/LDAPR */
            int opc = (i >> 12) & 7; bool o3 = (i >> 15) & 1;
            if (o3 && opc == 4) { /* LDAPR: plain acquire load */
                int rn = (i >> 5) & 31; uint64_t a = rn == 31 ? jit->GetSP() : jit->GetRegister(rn);
                setreg(i & 31, size == 3 ? rd<uint64_t>(a) : size == 2 ? rd<uint32_t>(a) : size == 1 ? rd<uint16_t>(a) : rd<uint8_t>(a));
                return true;
            }
            if (o3 && opc) return false;
            switch (size) { case 0: return lse_op<uint8_t>(i, opc, o3); case 1: return lse_op<uint16_t>(i, opc, o3);
                            case 2: return lse_op<uint32_t>(i, opc, o3); default: return lse_op<uint64_t>(i, opc, o3); }
        }
        if ((i & 0x3F200C00) == 0x19000000) { /* ARMv8.4 LRCPC2: STLUR / LDAPUR / LDAPURS (unscaled imm9) */
            int opc = (i >> 22) & 3, rn = (i >> 5) & 31, rt = i & 31;
            int64_t imm = (int64_t)((i >> 12) & 0x1FF) << 55 >> 55;
            uint64_t a = (rn == 31 ? jit->GetSP() : jit->GetRegister(rn)) + imm;
            if (opc == 0) {
                uint64_t v = reg(rt);
                switch (size) { case 0: wr<uint8_t>(a, (uint8_t)v); break; case 1: wr<uint16_t>(a, (uint16_t)v); break;
                                case 2: wr<uint32_t>(a, (uint32_t)v); break; default: wr<uint64_t>(a, v); }
                return true;
            }
            uint64_t v = size == 0 ? rd<uint8_t>(a) : size == 1 ? rd<uint16_t>(a) : size == 2 ? rd<uint32_t>(a) : rd<uint64_t>(a);
            if (opc >= 2 && size < 3) { int sh = 64 - (8 << size); v = (uint64_t)((int64_t)(v << sh) >> sh); if (opc == 3) v &= 0xFFFFFFFF; }
            setreg(rt, v);
            return true;
        }
        if ((i & 0x3FA07C00) == 0x08A07C00) { /* CAS{A,L,AL}{B,H,} */
            switch (size) { case 0: return cas_op<uint8_t>(i); case 1: return cas_op<uint16_t>(i);
                            case 2: return cas_op<uint32_t>(i); default: return cas_op<uint64_t>(i); }
        }
        if ((i & 0xBFA07C00) == 0x08207C00) { /* CASP: pair compare-and-swap */
            int rs = (i >> 16) & 31, rn = (i >> 5) & 31, rt = i & 31; bool x = (i >> 30) & 1;
            uint64_t a = arm64_translate(rn == 31 ? jit->GetSP() : jit->GetRegister(rn));
            if (!valid(a, x ? 16 : 8, true)) { fault(a, true); return true; }
            if (!x) {
                uint64_t exp = (reg(rs) & 0xFFFFFFFF) | reg(rs + 1) << 32, nv = (reg(rt) & 0xFFFFFFFF) | reg(rt + 1) << 32;
                __atomic_compare_exchange_n((uint64_t *)a, &exp, nv, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
                setreg(rs, exp & 0xFFFFFFFF); setreg(rs + 1, exp >> 32);
            } else {
                uint64_t lo = reg(rs), hi = reg(rs + 1);
                asm volatile("lock cmpxchg16b %0" : "+m"(*(volatile unsigned __int128 *)a), "+a"(lo), "+d"(hi) : "b"(reg(rt)), "c"(reg(rt + 1)) : "memory");
                setreg(rs, lo); setreg(rs + 1, hi);
            }
            return true;
        }
        (void)pc;
        return false;
    }
    void ExceptionRaised(uint64_t pc, Dynarmic::A64::Exception e) override {
        if (e == Dynarmic::A64::Exception::Yield || e == Dynarmic::A64::Exception::WaitForEvent ||
            e == Dynarmic::A64::Exception::SendEvent || e == Dynarmic::A64::Exception::SendEventLocal || e == Dynarmic::A64::Exception::WaitForInterrupt) return;
        fprintf(stderr, "scion: arm64 exception %d at pc=%llx\n", (int)e, (unsigned long long)pc); hc_exit(125, 0, 0, 0, 0, 0);
    }
    /* mach thread_suspend/resume/get_state: the thread parks at a block boundary (or is already
     * blocked inside a hostcall) and publishes its registers in `snap` */
    std::atomic<int> suspend_count{0};
    std::atomic<bool> parked{false}, in_hostcall{false};
    struct Event {   /* manual-reset event */
        std::mutex m; std::condition_variable c; bool on = false;
        void set() { std::lock_guard<std::mutex> l(m); on = true; c.notify_all(); }
        void reset() { std::lock_guard<std::mutex> l(m); on = false; }
        void wait(int ms = -1) { std::unique_lock<std::mutex> l(m); if (ms < 0) c.wait(l, [&] { return on; }); else c.wait_for(l, std::chrono::milliseconds(ms), [&] { return on; }); }
    } park_ev, resume_ev;
    struct darm_state snap{}; struct darm_neon neon{}; bool snap_dirty = false;
    void take_snapshot() {
        for (int i = 0; i < 29; i++) snap.x[i] = jit->GetRegister(i);
        snap.fp = jit->GetRegister(29); snap.lr = jit->GetRegister(30); snap.sp = jit->GetSP(); snap.pc = jit->GetPC(); snap.cpsr = jit->GetPstate();
        for (int i = 0; i < 32; i++) { auto v = jit->GetVector(i); neon.v[2 * i] = v[0]; neon.v[2 * i + 1] = v[1]; }
        neon.fpsr = jit->GetFpsr(); neon.fpcr = jit->GetFpcr();
    }
    void park() {
        take_snapshot(); snap_dirty = false;
        parked = true; park_ev.set();
        while (suspend_count > 0) resume_ev.wait();
        resume_ev.reset(); parked = false; park_ev.reset();
        if (snap_dirty) {
            for (int i = 0; i < 29; i++) jit->SetRegister(i, snap.x[i]);
            jit->SetRegister(29, snap.fp); jit->SetRegister(30, snap.lr); jit->SetSP(snap.sp); jit->SetPC(snap.pc); jit->SetPstate(snap.cpsr);
            for (int i = 0; i < 32; i++) jit->SetVector(i, {neon.v[2 * i], neon.v[2 * i + 1]});
            jit->SetFpsr(neon.fpsr); jit->SetFpcr(neon.fpcr);
        }
    }
    void deliver(int sig, int code, uint64_t addr);
    void sigreturn();
    void deliver_pending();
    void AddTicks(uint64_t) override {}
    uint64_t GetTicksRemaining() override { return 1ull << 40; }
    uint64_t GetCNTPCT() override { return (uint64_t)hc_clock(1, 0, 0, 0, 0, 0) / 41; /* ~24 MHz like Apple */ }
    void CallSVC(uint32_t n) override {
        if (n == HC_COUNT + 1) { sigreturn(); return; }
        if (n >= HC_COUNT) { jit->HaltExecution(); return; } /* return-from-entry trap */
        A a[6]; for (int i = 0; i < 6; i++) a[i] = (A)jit->GetRegister(i);
        in_hostcall = true;     /* a suspender reads our registers (snapshot on demand) while we block */
        A r = g_hc[n](a[0], a[1], a[2], a[3], a[4], a[5]);
        in_hostcall = false;
        jit->SetRegister(0, (uint64_t)r);
        apply_invalidations();
        if (suspend_count > 0) jit->HaltExecution(Dynarmic::HaltReason::UserDefined3);
    }
};

/* ---------- signals for arm64 guests ---------- */
struct SigFrameArm {
    struct dsiginfo si; uint64_t pad0;
    struct ducontext uc; uint64_t pad1;
    struct dmcontext_arm mc;
};
void ArmEnv::deliver(int sig, int code, uint64_t addr) {
    struct dsigaction a = g_sig[sig];
    if (a.flags & D_SA_RESETHAND) g_sig[sig].handler = 0;
    struct gthread *t = (struct gthread *)tpidrro;
    if (a.handler <= 1) {
        if (dsig_default_ignored(sig) || (a.handler == 1 && sig != D_SIGSEGV && sig != D_SIGBUS)) return;
        fprintf(stderr, "scion: signal %d (pc=%llx addr=%llx)\n", sig, (unsigned long long)jit->GetPC(), (unsigned long long)addr);
        hc_exit(128 + sig, 0, 0, 0, 0, 0);
    }
    uint64_t cur = jit->GetSP();
    bool alt_ok = t->alt_size && !(t->alt_flags & D_SS_DISABLE), on_alt = alt_ok && cur >= t->alt_sp && cur < t->alt_sp + t->alt_size;
    uint64_t sp = (a.flags & D_SA_ONSTACK) && alt_ok && !on_alt ? t->alt_sp + t->alt_size : cur - 128;
    SigFrameArm *f = (SigFrameArm *)((sp - sizeof(SigFrameArm)) & ~15ull);
    memset(f, 0, sizeof *f);
    f->si.signo = sig; f->si.code = code; f->si.addr = addr; f->si.pid = (int32_t)host_pid();
    f->uc.onstack = on_alt; f->uc.stack.sp = t->alt_sp; f->uc.stack.size = t->alt_size; f->uc.stack.flags = t->alt_flags;
    f->uc.mcsize = sizeof f->mc; f->uc.mcontext = (uint64_t)&f->mc;
    struct dmcontext_arm &m = f->mc;
    m.faddr = addr; m.esr = sig == D_SIGSEGV || sig == D_SIGBUS ? 0x92000000u | (fault_write ? 0x40 : 0) : 0;
    for (int i = 0; i < 29; i++) m.x[i] = jit->GetRegister(i);
    m.fp = jit->GetRegister(29); m.lr = jit->GetRegister(30); m.sp = cur; m.pc = jit->GetPC(); m.cpsr = jit->GetPstate();
    for (int i = 0; i < 32; i++) { auto v = jit->GetVector(i); m.v[2 * i] = v[0]; m.v[2 * i + 1] = v[1]; }
    m.fpsr = jit->GetFpsr(); m.fpcr = jit->GetFpcr();
    jit->SetRegister(0, sig); jit->SetRegister(1, (uint64_t)&f->si); jit->SetRegister(2, (uint64_t)&f->uc);
    jit->SetRegister(30, (uint64_t)(g_arm_thunks + 2 * (HC_COUNT + 1)));
    jit->SetSP((uint64_t)f); jit->SetPC(a.handler);
    t->in_handler++;
    invalidate_ok(); /* the handler may change protections */
}
/* async signals are blocked while a handler runs (POSIX mask): deliver one at a time, the rest on sigreturn */
void ArmEnv::deliver_pending() {
    struct gthread *t = (struct gthread *)tpidrro;
    if (t->in_handler > 0) return;
    uint64_t p = pending.load();
    while (p && !pending.compare_exchange_weak(p, p & (p - 1))) {}
    if (p) deliver(__builtin_ctzll(p), 0, 0);
}
void ArmEnv::sigreturn() {
    SigFrameArm *f = (SigFrameArm *)jit->GetSP();
    struct dmcontext_arm &m = *(struct dmcontext_arm *)f->uc.mcontext;
    for (int i = 0; i < 29; i++) jit->SetRegister(i, m.x[i]);
    jit->SetRegister(29, m.fp); jit->SetRegister(30, m.lr); jit->SetSP(m.sp); jit->SetPC(m.pc); jit->SetPstate(m.cpsr);
    for (int i = 0; i < 32; i++) jit->SetVector(i, {m.v[2 * i], m.v[2 * i + 1]});
    jit->SetFpsr(m.fpsr); jit->SetFpcr(m.fpcr);
    struct gthread *t = (struct gthread *)tpidrro;
    if (t->in_handler > 0) t->in_handler--;
    deliver_pending();
}
void arm64_signal(struct gthread *t, int sig) {
    ArmEnv *e = (ArmEnv *)t->host;
    if (!e || !e->jit) return;
    e->pending.fetch_or(1ull << sig);
    e->jit->HaltExecution(Dynarmic::HaltReason::UserDefined2);
}

/* One JIT per thread, reused by every guest entry on that thread (thread start, initializers, callbacks): compiled
 * code survives between calls. A nested entry (guest -> host -> guest) takes another JIT from the same pool. */
/* A plain pointer: MinGW frees emutls storage before running thread_local destructors, so an object with a destructor
 * here was destroyed from freed memory at every thread exit (heap corruption on Windows). JITs are never deleted
 * either (destroying a dynarmic JIT corrupted the Windows heap): a finished thread hands them to the next new thread,
 * compiled code included. */
static thread_local std::vector<ArmEnv *> *t_pool;
#define t_idle_envs (*(t_pool ? t_pool : (t_pool = new std::vector<ArmEnv *>)))
static std::mutex g_spare_mu;
static std::vector<ArmEnv *> g_spare;
void arm64_thread_end() {
    if (!t_pool) return;
    {
        std::lock_guard<std::mutex> l(g_spare_mu);
        g_spare.insert(g_spare.end(), t_pool->begin(), t_pool->end());
    }
    delete t_pool;
    t_pool = nullptr;
}
static ArmEnv *new_env(struct gthread *t) {
    {
        std::lock_guard<std::mutex> l(g_spare_mu);
        if (!g_spare.empty()) { /* a dead thread's JIT: reset its per-thread state */
            ArmEnv *e = g_spare.back();
            g_spare.pop_back();
            e->tpidr = 0; e->pending = 0; e->suspend_count = 0; e->parked = false; e->in_hostcall = false; e->snap_dirty = false;
            e->park_ev.reset(); e->resume_ev.reset();
            for (auto r : {Dynarmic::HaltReason::UserDefined2, Dynarmic::HaltReason::UserDefined3}) e->jit->ClearHalt(r);
            return e;
        }
    }
    ArmEnv *e = new ArmEnv;
    Dynarmic::A64::UserConfig &cfg = e->cfg;
    cfg.callbacks = e;
    cfg.tpidrro_el0 = &e->tpidrro;
    cfg.tpidr_el0 = &e->tpidr;
    cfg.global_monitor = g_monitor;
    cfg.processor_id = g_cpu_ids++ % MAX_CPUS;
    cfg.cntfrq_el0 = 24000000;
    /* precise faults; dynarmic is patched to keep get/set elimination between memory accesses (patches/) */
    cfg.check_halt_on_memory_access = true; /* measured: <5% with the patched dynarmic */
    cfg.enable_cycle_counting = false; /* block links then poll halt_reason, so other threads can interrupt loops */
    /* fastmem: guest VA == host VA, so the arena base is 0; faults fall back to the callbacks above */
    if (!getenv("SCION_NOFASTMEM")) { cfg.fastmem_pointer = 0; cfg.fastmem_address_space_bits = 47; cfg.silently_mirror_fastmem = false; }
    /* SCION_JIT_MB: code cache per thread (dynarmic's default is 128 MB; when it fills, everything is recompiled) */
    if (const char *m = getenv("SCION_JIT_MB")) cfg.code_cache_size = (size_t)strtoul(m, nullptr, 10) << 20;
    if (const char *o = getenv("SCION_OPT")) cfg.optimizations = (Dynarmic::OptimizationFlag)strtoul(o, nullptr, 16); /* tuning */
    cfg.code_cache = g_code_cache;
    cfg.code_cache_verify = g_code_cache_mode && !strcmp(g_code_cache_mode, "verify");
    cfg.code_cache_selftest = g_code_cache_mode && !strcmp(g_code_cache_mode, "selftest");
    e->jit = new Dynarmic::A64::Jit(cfg);
    { std::lock_guard<std::mutex> l(g_inv_mu); e->inv_seen = g_inv_log.size(); }   /* a new JIT has nothing stale */
    return e;
}
uint64_t run_arm64(uint64_t pc, const uint64_t *args, int nargs, uint64_t sp, struct gthread *t) {
    ArmEnv *ep;
    if (!t_idle_envs.empty()) { ep = t_idle_envs.back(); t_idle_envs.pop_back(); } else ep = new_env(t);
    ArmEnv &env = *ep;
    env.tpidrro = (uint64_t)t;
    env.faulted = false; env.invalidate_ok();
    env.apply_invalidations();
    Dynarmic::A64::Jit &jit = *env.jit;
    jit.ClearHalt(Dynarmic::HaltReason::UserDefined1); jit.ClearHalt(Dynarmic::HaltReason::MemoryAbort);
    jit.SetSP(sp & ~15ull);
    for (int i = 0; i < nargs; i++) jit.SetRegister(i, args[i]);
    jit.SetRegister(30, (uint64_t)(g_arm_thunks + 2 * HC_COUNT)); /* LR -> trap */
    jit.SetPC(pc);
    uint64_t prev = t->host; t->host = (uint64_t)&env;
    for (;;) {
        Dynarmic::HaltReason hr = jit.Run();
        if (Dynarmic::Has(hr, Dynarmic::HaltReason::MemoryAbort)) {
            jit.ClearHalt(Dynarmic::HaltReason::MemoryAbort);
            env.faulted = false;
            uint64_t lo, hi; int prot;
            int code = host_mem_query(env.fault_addr, &lo, &hi, &prot) ? 2 : 1;   /* SEGV_ACCERR : SEGV_MAPERR */
            TRACE("arm64 SIGSEGV pc=%llx addr=%llx\n", (unsigned long long)jit.GetPC(), (unsigned long long)env.fault_addr);
            env.deliver(D_SIGSEGV, code, env.fault_addr);
            continue;
        }
        if (Dynarmic::Has(hr, Dynarmic::HaltReason::UserDefined2)) {
            jit.ClearHalt(Dynarmic::HaltReason::UserDefined2);
            TRACE("async arm64 signals %llx at pc=%llx\n", (unsigned long long)env.pending.load(), (unsigned long long)jit.GetPC());
            env.deliver_pending();
            continue;
        }
        if (Dynarmic::Has(hr, Dynarmic::HaltReason::UserDefined3)) {
            jit.ClearHalt(Dynarmic::HaltReason::UserDefined3);
            if (env.suspend_count > 0) env.park();
            continue;
        }
        if (Dynarmic::Has(hr, Dynarmic::HaltReason::CacheInvalidation) && !Dynarmic::Has(hr, Dynarmic::HaltReason::UserDefined1)) continue;
        break; /* UserDefined1: return-from-entry trap */
    }
    t->host = prev;
    uint64_t r = jit.GetRegister(0);
    t_idle_envs.push_back(ep);
    return r;
}


void arm64_init() {
    g_monitor = new Dynarmic::ExclusiveMonitor(MAX_CPUS);
    g_code_cache_mode = getenv("SCION_JIT_CACHE");
    if (!g_code_cache_mode || strcmp(g_code_cache_mode, "0")) g_code_cache = Dynarmic::A64::MakeCodeCache();
    g_arm_thunks = (uint32_t *)image_alloc(0, 4096);
    for (uint32_t i = 0; i <= HC_COUNT + 1; i++) { g_arm_thunks[2 * i] = 0xD4000001u | (i << 5); g_arm_thunks[2 * i + 1] = 0xD65F03C0u; }
}

int arm64_thread_ctl(struct gthread *t, int op, int flavor, void *state);
/* SCION_THREAD_DUMP / SCION_SAMPLE: registers of a guest thread (stopped for the copy), whether it is blocked in a
 * host call, and its counters */
bool arm64_thread_peek(struct gthread *t, struct darm_state *st, bool *hostcall, uint64_t *callbacks, uint64_t *code_reads) {
    ArmEnv *e = (ArmEnv *)t->host;
    if (!e || !e->jit) return false;
    arm64_thread_ctl(t, D_THREAD_SUSPEND, 0, nullptr);
    if (!e->parked) e->take_snapshot();
    *st = e->snap; *hostcall = e->in_hostcall && !e->parked; *callbacks = e->callbacks; *code_reads = e->code_reads;
    arm64_thread_ctl(t, D_THREAD_RESUME, 0, nullptr);
    return true;
}
int arm64_thread_ctl(struct gthread *t, int op, int flavor, void *state) {
    ArmEnv *e = (ArmEnv *)t->host;
    if (!e || !e->jit) return -1;
    switch (op) {
    case D_THREAD_SUSPEND:
        if (e->suspend_count++ == 0) {
            e->jit->HaltExecution(Dynarmic::HaltReason::UserDefined3);
            while (!e->parked && !e->in_hostcall) e->park_ev.wait(1);
        }
        return 0;
    case D_THREAD_RESUME:
        if (e->suspend_count > 0 && --e->suspend_count == 0) e->resume_ev.set();
        return 0;
    }
    if (flavor != D_ARM_THREAD_STATE64 && flavor != D_ARM_NEON_STATE64) return -4;
    void *s = flavor == D_ARM_NEON_STATE64 ? (void *)&e->neon : (void *)&e->snap;
    size_t n = flavor == D_ARM_NEON_STATE64 ? sizeof e->neon : sizeof e->snap;
    if (op == D_THREAD_GET_STATE) { if (!e->parked) e->take_snapshot(); memcpy(state, s, n); return 0; }
    if (!e->parked) return -1; /* ponytail: set_state only while parked at a block boundary */
    memcpy(s, state, n); e->snap_dirty = true;
    return 0;
}

void arm64_exit() {
    if (g_code_cache && g_code_cache_mode && strcmp(g_code_cache_mode, "0"))
        fprintf(stderr, "[scion] JIT code cache: %s\n", Dynarmic::A64::CodeCacheStats(*g_code_cache).c_str());
}
