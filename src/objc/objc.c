/* objc.c — scion's Objective-C runtime (libobjc.A.dylib), Apple "objc2" ABI.
 * Written from the public ABI that clang emits (class_ro_t, method/ivar/protocol lists, objc_* entry points)
 * and Apple's runtime documentation. Design: plain-pointer isa, retain counts and weak refs in side tables,
 * one global (isa, sel) -> imp cache probed by objc_msgSend in assembly. */
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>

typedef struct objc_class *Class;
typedef struct objc_object { Class isa; } *id;
typedef const char *SEL;
typedef id (*IMP)(id, SEL, ...);
typedef signed char BOOL;

void *malloc(size_t); void *calloc(size_t, size_t); void *realloc(void *, size_t); void free(void *);
void *memset(void *, int, size_t); void *memcpy(void *, const void *, size_t); size_t strlen(const char *);
int strcmp(const char *, const char *); int strncmp(const char *, const char *, size_t);
long write(int, const void *, size_t); void abort(void);
typedef uint64_t pthread_mutex_t[8];
int pthread_mutex_lock(void *); int pthread_mutex_unlock(void *);
void *pthread_self(void);
int pthread_key_create(unsigned long *, void (*)(void *)); int pthread_setspecific(unsigned long, const void *); void *pthread_getspecific(unsigned long);
void *_Block_copy(const void *); void _Block_release(const void *);
struct Block_callbacks_RR { size_t size; void (*retain)(const void *); void (*release)(const void *); void (*destructInstance)(const void *); };
void _Block_use_RR2(const struct Block_callbacks_RR *);
extern void *_NSConcreteStackBlock[32], *_NSConcreteMallocBlock[32], *_NSConcreteGlobalBlock[32];

char *getenv(const char *); int snprintf(char *, size_t, const char *, ...);
static void say(const char *s) { write(2, s, strlen(s)); }
static void die2(const char *a, const char *b) { say("objc[scion]: "); say(a); if (b) say(b); say("\n"); abort(); }

/* ===================================================================== ABI structures */
struct method_t { SEL name; const char *types; IMP imp; };
struct method_list_t { uint32_t entsize_flags, count; /* entries follow */ };
struct ivar_t { int32_t *offset; const char *name, *type; uint32_t alignment_raw, size; };
struct ivar_list_t { uint32_t entsize_flags, count; struct ivar_t first; };
struct protocol_t;
struct protocol_list_t { uintptr_t count; struct protocol_t *list[]; };
struct property_t { const char *name, *attributes; };
struct property_list_t { uint32_t entsize_flags, count; struct property_t first; };
struct protocol_t {
    Class isa; const char *name; struct protocol_list_t *protocols;
    struct method_list_t *instanceMethods, *classMethods, *optionalInstanceMethods, *optionalClassMethods;
    struct property_list_t *instanceProperties; uint32_t size, flags;
};
struct class_ro_t {
    uint32_t flags, instanceStart, instanceSize, reserved;
    const uint8_t *ivarLayout; const char *name;
    struct method_list_t *baseMethods; struct protocol_list_t *baseProtocols; struct ivar_list_t *ivars;
    const uint8_t *weakIvarLayout; struct property_list_t *baseProperties;
};
enum { RO_META = 1, RO_ROOT = 2, RO_HAS_CXX_STRUCTORS = 4 };
struct category_t {
    const char *name; Class cls; struct method_list_t *instanceMethods, *classMethods;
    struct protocol_list_t *protocols; struct property_list_t *instanceProperties;
};

/* runtime-private class state lives in the second cache word (compiled code never reads it) */
struct class_rw {
    const struct class_ro_t *ro;
    struct method_list_t **mlists; int nmlists, cap;   /* categories first (newest first), base last */
    struct protocol_list_t **plists; int nplists;
    uint32_t instanceSize;
    int realized, initialized, initializing, has_cxx_destruct, loaded;
    void *init_thread;
    Class nonmeta;                                      /* for metaclasses */
};
struct objc_class { Class isa, superclass; void *cache; struct class_rw *rw; uintptr_t bits; };
static inline const struct class_ro_t *RO(Class c) { return (const struct class_ro_t *)(c->bits & ~(uintptr_t)7); }
static inline int IS_META(Class c) { return RO(c)->flags & RO_META; }

void *_objc_empty_cache[2];
void *_objc_empty_vtable[2];

/* ===================================================================== locks */
static pthread_mutex_t rtlock;                /* runtime lock, recursive (realize/initialize may nest) */
static void *rt_owner; static int rt_depth;
static void lock_rt(void) { void *me = pthread_self(); if (rt_owner == me) { rt_depth++; return; } pthread_mutex_lock(&rtlock); rt_owner = me; rt_depth = 1; }
static void unlock_rt(void) { if (--rt_depth == 0) { rt_owner = 0; pthread_mutex_unlock(&rtlock); } }

/* ===================================================================== hash maps */
static uint64_t hstr(const char *s) { uint64_t h = 1469598103934665603ull; while (*s) h = (h ^ (unsigned char)*s++) * 1099511628211ull; return h; }
struct strmap { const char **k; void **v; size_t cap, n; };
static void *sm_get(struct strmap *m, const char *k) {
    if (!m->cap) return 0;
    for (size_t i = hstr(k) & (m->cap - 1);; i = (i + 1) & (m->cap - 1)) { if (!m->k[i]) return 0; if (!strcmp(m->k[i], k)) return m->v[i]; }
}
static void sm_put(struct strmap *m, const char *k, void *v) {
    if ((m->n + 1) * 2 > m->cap) {
        struct strmap n = {0, 0, m->cap ? m->cap * 2 : 1024, 0};
        n.k = calloc(n.cap, sizeof *n.k); n.v = calloc(n.cap, sizeof *n.v);
        for (size_t i = 0; i < m->cap; i++) if (m->k[i]) sm_put(&n, m->k[i], m->v[i]);
        free(m->k); free(m->v); *m = n;
    }
    size_t i = hstr(k) & (m->cap - 1);
    while (m->k[i] && strcmp(m->k[i], k)) i = (i + 1) & (m->cap - 1);
    if (!m->k[i]) m->n++;
    m->k[i] = k; m->v[i] = v;
}
struct ptrmap { uintptr_t *k; uintptr_t *v; size_t cap, n; };
static uint64_t hptr(uintptr_t p) { p ^= p >> 33; p *= 0xff51afd7ed558ccdull; p ^= p >> 33; return p; }
static uintptr_t *pm_slot(struct ptrmap *m, uintptr_t k, int create) {
    if (create && (m->n + 1) * 2 > m->cap) {
        struct ptrmap n = {0, 0, m->cap ? m->cap * 2 : 1024, 0};
        n.k = calloc(n.cap, sizeof *n.k); n.v = calloc(n.cap, sizeof *n.v);
        for (size_t i = 0; i < m->cap; i++) if (m->k[i] && m->k[i] != 1) *pm_slot(&n, m->k[i], 1) = m->v[i];
        free(m->k); free(m->v); *m = n;
    }
    if (!m->cap) return 0;
    size_t i = hptr(k) & (m->cap - 1), tomb = (size_t)-1;
    for (;; i = (i + 1) & (m->cap - 1)) {
        if (m->k[i] == k) return &m->v[i];
        if (m->k[i] == 1 && tomb == (size_t)-1) tomb = i; /* deleted */
        if (!m->k[i]) break;
    }
    if (!create) return 0;
    if (tomb != (size_t)-1) i = tomb;
    m->k[i] = k; m->v[i] = 0; m->n++;
    return &m->v[i];
}
static void pm_del(struct ptrmap *m, uintptr_t k) {
    uintptr_t *v = pm_slot(m, k, 0);
    if (v) { m->k[v - m->v] = 1; *v = 0; }
}

/* ===================================================================== selectors */
static struct strmap sels;
static pthread_mutex_t sellock;
SEL sel_registerName(const char *name) {
    if (!name) return 0;
    pthread_mutex_lock(&sellock);
    SEL s = sm_get(&sels, name);
    if (!s) { s = name; sm_put(&sels, name, (void *)name); }
    pthread_mutex_unlock(&sellock);
    return s;
}
SEL sel_getUid(const char *n) { return sel_registerName(n); }
const char *sel_getName(SEL s) { return s ? s : "<null selector>"; }
BOOL sel_isEqual(SEL a, SEL b) { return a == b; }
static SEL S(const char *n) { return sel_registerName(n); }

/* ===================================================================== method cache probed by objc_msgSend */
struct centry { Class isa; SEL sel; IMP imp; void *pad; };            /* 32 bytes: asm scales the index by 32 */
struct ctable { size_t mask, maskshift, used, pad; struct centry e[]; }; /* entries at +32 */
struct ctable *_scion_objc_cache;
static struct ctable *new_ctable(size_t n) { struct ctable *t = calloc(1, sizeof *t + n * sizeof(struct centry)); t->mask = n - 1; t->maskshift = (n - 1) << 5; return t; }
static size_t cidx(Class c, SEL s, size_t mask) { return (((uintptr_t)c >> 4) ^ ((uintptr_t)s >> 3)) & mask; }
static void cache_fill(Class c, SEL s, IMP imp) {
    struct ctable *t = _scion_objc_cache;
    if ((t->used + 1) * 4 > (t->mask + 1) * 3) { /* grow: build a fresh table, publish, leak the old one */
        struct ctable *n = new_ctable((t->mask + 1) * 2);
        for (size_t i = 0; i <= t->mask; i++) if (t->e[i].isa) {
            size_t j = cidx(t->e[i].isa, t->e[i].sel, n->mask);
            while (n->e[j].isa) j = (j + 1) & n->mask;
            n->e[j] = t->e[i]; n->used++;
        }
        __atomic_store_n(&_scion_objc_cache, n, __ATOMIC_RELEASE);
        t = n;
    }
    size_t j = cidx(c, s, t->mask);
    for (; t->e[j].isa; j = (j + 1) & t->mask) if (t->e[j].isa == c && t->e[j].sel == s) return;
    t->e[j].imp = imp; t->e[j].sel = s;
    __atomic_store_n(&t->e[j].isa, c, __ATOMIC_RELEASE); /* entries are published once and never change */
    t->used++;
}
static void cache_flush(void) { __atomic_store_n(&_scion_objc_cache, new_ctable((_scion_objc_cache->mask + 1)), __ATOMIC_RELEASE); }

/* ===================================================================== classes */
static struct strmap classes;
static struct strmap protocols;
static struct ptrmap pending_cats;  /* class -> linked list of category_t* waiting for realization */
struct catnode { struct category_t *cat; struct catnode *next; };
static Class Protocol_class;

static void add_mlist(struct class_rw *rw, struct method_list_t *ml, int front) {
    if (!ml || !ml->count) return;
    if (rw->nmlists == rw->cap) { rw->cap = rw->cap ? rw->cap * 2 : 4; rw->mlists = realloc(rw->mlists, rw->cap * sizeof *rw->mlists); }
    if (front) { for (int i = rw->nmlists; i > 0; i--) rw->mlists[i] = rw->mlists[i - 1]; rw->mlists[0] = ml; }
    else rw->mlists[rw->nmlists] = ml;
    rw->nmlists++;
}
static void add_plist(struct class_rw *rw, struct protocol_list_t *pl) {
    if (!pl || !pl->count) return;
    rw->plists = realloc(rw->plists, (rw->nplists + 1) * sizeof *rw->plists);
    rw->plists[rw->nplists++] = pl;
}
/* method list access: classic 24-byte entries or Apple's relative "small" lists (12 bytes, int32 offsets) */
static int ml_small(struct method_list_t *ml) { return (ml->entsize_flags & 0x80000000) != 0; }
static uint32_t ml_entsize(struct method_list_t *ml) { return ml->entsize_flags & 0xFFFC & ~3u; }
static void ml_get(struct method_list_t *ml, uint32_t i, SEL *name, const char **types, IMP *imp, int32_t **imp_slot) {
    uint8_t *e = (uint8_t *)(ml + 1) + (size_t)i * ml_entsize(ml);
    if (ml_small(ml)) {
        int32_t *o = (int32_t *)e;
        *name = *(SEL *)((uint8_t *)&o[0] + o[0]);
        *types = (const char *)((uint8_t *)&o[1] + o[1]);
        *imp = (IMP)((uint8_t *)&o[2] + o[2]);
        if (imp_slot) *imp_slot = &o[2];
    } else {
        struct method_t *m = (struct method_t *)e;
        *name = m->name; *types = m->types; *imp = m->imp;
        if (imp_slot) *imp_slot = 0;
    }
}
static void fixup_mlist(struct method_list_t *ml) {
    if (!ml || ml_small(ml) || (ml->entsize_flags & 3) == 3) return; /* small lists use selrefs, already uniqued */
    for (uint32_t i = 0; i < ml->count; i++) { struct method_t *m = (struct method_t *)((uint8_t *)(ml + 1) + (size_t)i * ml_entsize(ml)); m->name = S(m->name); }
    ml->entsize_flags |= 3;
}
static void realize(Class c);
static void attach_category(Class c, struct category_t *cat) {
    fixup_mlist(cat->instanceMethods); fixup_mlist(cat->classMethods);
    add_mlist(c->rw, cat->instanceMethods, 1);
    add_mlist(c->isa->rw, cat->classMethods, 1);
    add_plist(c->rw, cat->protocols);
}
static void realize(Class c) {
    if (!c || (c->rw && c->rw->realized)) return;
    lock_rt();
    if (c->rw) { unlock_rt(); return; } /* realized, or being realized higher up this (recursive-locked) stack */
    const struct class_ro_t *ro = RO(c);
    struct class_rw *rw = calloc(1, sizeof *rw);
    rw->ro = ro;
    c->rw = rw; /* visible early so recursive realization of the metaclass chain terminates */
    realize(c->superclass);
    if (c->isa != c) realize(c->isa);
    fixup_mlist(ro->baseMethods);
    add_mlist(rw, ro->baseMethods, 0);
    add_plist(rw, ro->baseProtocols);
    rw->instanceSize = ro->instanceSize;
    /* non-fragile ivars: slide our ivars if the superclass grew */
    if (c->superclass && !(ro->flags & RO_META)) {
        uint32_t super_size = c->superclass->rw->instanceSize;
        if (super_size > ro->instanceStart) {
            uint32_t align = 8;   /* the delta keeps every ivar aligned (long double, SIMD ivars need 16) */
            if (ro->ivars) for (uint32_t i = 0; i < ro->ivars->count; i++) {
                struct ivar_t *iv = (struct ivar_t *)((uint8_t *)&ro->ivars->first + (size_t)i * (ro->ivars->entsize_flags & ~3u));
                uint32_t a = iv->alignment_raw == ~0u ? 8 : iv->alignment_raw < 16 ? 1u << iv->alignment_raw : 8;
                if (a > align) align = a;
            }
            uint32_t delta = (super_size - ro->instanceStart + align - 1) & ~(align - 1);
            if (ro->ivars) for (uint32_t i = 0; i < ro->ivars->count; i++) {
                struct ivar_t *iv = (struct ivar_t *)((uint8_t *)&ro->ivars->first + (size_t)i * (ro->ivars->entsize_flags & ~3u));
                if (iv->offset) *iv->offset += (int32_t)delta;
            }
            rw->instanceSize += delta;
        }
    }
    rw->has_cxx_destruct = (ro->flags & RO_HAS_CXX_STRUCTORS) != 0;
    if (!(ro->flags & RO_META)) {
        c->isa->rw->nonmeta = c;
        uintptr_t *p = pm_slot(&pending_cats, (uintptr_t)c, 0);
        if (p) { for (struct catnode *n = (struct catnode *)*p; n; n = n->next) attach_category(c, n->cat); pm_del(&pending_cats, (uintptr_t)c); cache_flush(); }
    }
    rw->realized = 1;
    unlock_rt();
}

/* own (not inherited) method lookup */
static IMP find_in_class(Class c, SEL sel, const char **types) {
    for (int k = 0; k < c->rw->nmlists; k++) {
        struct method_list_t *ml = c->rw->mlists[k];
        for (uint32_t i = 0; i < ml->count; i++) {
            SEL n; const char *t; IMP imp; ml_get(ml, i, &n, &t, &imp, 0);
            if (n == sel) { if (types) *types = t; return imp; }
        }
    }
    return 0;
}
static IMP find_method(Class c, SEL sel) {
    for (; c; c = c->superclass) { realize(c); IMP i = find_in_class(c, sel, 0); if (i) return i; }
    return 0;
}

id objc_msgSend(id, SEL, ...);
static void initialize_class(Class c) {
    Class cls = IS_META(c) ? c->rw->nonmeta : c;
    if (!cls || cls->rw->initialized) return;
    if (cls->superclass) { realize(cls->superclass); initialize_class(cls->superclass); }
    lock_rt();
    if (cls->rw->initialized || (cls->rw->initializing && cls->rw->init_thread == pthread_self())) { unlock_rt(); return; }
    cls->rw->initializing = 1; cls->rw->init_thread = pthread_self();
    unlock_rt();
    IMP init = find_method(cls->isa, S("initialize"));
    if (init) ((void (*)(Class, SEL))init)(cls, S("initialize"));
    cls->rw->initialized = 1;
}

extern void _objc_msgForward(void);
IMP _scion_objc_lookup(id self, SEL sel, Class cls) {
    if (!cls) return (IMP)_objc_msgForward;
    /* first message to a class goes to its metaclass: realize the class itself too (categories, +initialize) */
    if (IS_META(cls) && self && self->isa == cls) realize((Class)self);
    realize(cls);
    initialize_class(cls);
    IMP imp = find_method(cls, sel);
    static int trace = -1;   /* SCION_TRACE_MSG=1: the first send of each selector to each class (a cache miss) */
    if (trace < 0) trace = getenv("SCION_TRACE_MSG") != 0;
    if (trace) { char b[512]; int n = snprintf(b, sizeof b, "[msg] %c[%s %s]%s\n", IS_META(cls) ? '+' : '-', RO(cls)->name, (const char *)sel, imp ? "" : " (not implemented)"); write(2, b, (size_t)n); }
    if (!imp) { /* dynamic resolution */
        int meta = IS_META(cls);
        SEL r = S(meta ? "resolveClassMethod:" : "resolveInstanceMethod:");
        IMP ri = find_method(meta ? cls : cls->isa, r);
        if (ri && sel != r && ((BOOL(*)(id, SEL, SEL))ri)(meta ? (id)cls->rw->nonmeta : (id)cls, r, sel)) imp = find_method(cls, sel);
    }
    if (!imp) return (IMP)_objc_msgForward;
    cache_fill(cls, sel, imp);
    return imp;
}
/* message forwarding: -forwardingTargetForSelector:, else -forwardInvocation: through Foundation's hook (which makes an
 * NSInvocation from the registers the forwarding stub saved in frame; it returns 0 when the class gives no method
 * signature), else -doesNotRecognizeSelector:. A NULL result tells the stub the call is done. */
int (*_scion_forward_invocation_hook)(id self, SEL sel, void *frame);
id _scion_objc_forward_target(id self, SEL sel, void *frame) {
    SEL f = S("forwardingTargetForSelector:");
    IMP fi = find_method(self->isa, f);
    if (fi && sel != f) { id t = ((id (*)(id, SEL, SEL))fi)(self, f, sel); if (t && t != self) return t; }
    if (_scion_forward_invocation_hook && _scion_forward_invocation_hook(self, sel, frame)) return 0;
    /* SCION_TOLERANT=1: an unknown message logs and returns 0 instead of raising, to list what an app is missing in
       one run (diagnosis only: the app may misbehave) */
    static int tolerant = -1;
    if (tolerant < 0) tolerant = getenv("SCION_TOLERANT") != 0;
    if (tolerant) {
        say("[tolerant] -"); say(sel); say(" to "); say(RO(self->isa)->name); say("\n");
        uint64_t *r = (uint64_t *)frame;
        r[0] = r[1] = 0;   /* the returned registers: rax/rdx (x86_64) or x0/x1 (arm64) */
        memset((char *)frame + 48, 0, 64);   /* xmm0-3 (x86_64, from 48) or q0/q1 (arm64, from 80) */
        return 0;
    }
    IMP d = find_method(self->isa, S("doesNotRecognizeSelector:"));
    if (d) ((void (*)(id, SEL, SEL))d)(self, S("doesNotRecognizeSelector:"), sel);
    say("objc[scion]: unrecognized selector -"); say(sel); say(" sent to instance of "); say(RO(self->isa)->name); say("\n");
    abort();
    return 0;
}

/* ===================================================================== image registration */
struct mh { uint32_t magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, reserved; };
struct seg { uint32_t cmd, cmdsize; char segname[16]; uint64_t vmaddr, vmsize, fileoff, filesize; uint32_t maxprot, initprot, nsects, flags; };
struct sect { char sectname[16], segname[16]; uint64_t addr, size; uint32_t offset, align, reloff, nreloc, flags, r1, r2, r3; };
static void *section(struct mh *h, intptr_t slide, const char *name, size_t *count, size_t elem) {
    uint8_t *lc = (uint8_t *)(h + 1);
    for (uint32_t i = 0; i < h->ncmds; i++, lc += ((uint32_t *)lc)[1]) {
        if (*(uint32_t *)lc != 0x19) continue;
        struct seg *s = (struct seg *)lc; struct sect *sc = (struct sect *)(s + 1);
        for (uint32_t k = 0; k < s->nsects; k++)
            if (!strncmp(sc[k].sectname, name, 16)) { *count = sc[k].size / elem; return (void *)(sc[k].addr + slide); }
    }
    *count = 0; return 0;
}
static void call_load(Class c) {
    realize(c);
    if (c->superclass) call_load(c->superclass);
    if (c->rw->loaded) return;
    c->rw->loaded = 1;
    IMP l = 0;
    struct method_list_t *ml = RO(c->isa)->baseMethods;
    if (ml) for (uint32_t i = 0; i < ml->count; i++) { SEL n; const char *t; IMP imp; ml_get(ml, i, &n, &t, &imp, 0); if (n == S("load")) l = imp; }
    if (l) ((void (*)(Class, SEL))l)(c, S("load"));
}
static void canon_protocol(struct protocol_t **ref) {
    struct protocol_t *p = sm_get(&protocols, (*ref)->name);
    if (!p) { p = *ref; sm_put(&protocols, p->name, p); if (Protocol_class) p->isa = Protocol_class; }
    *ref = p;
}
static void runtime_init(void);
void _scion_objc_image(struct mh *h, intptr_t slide) {
    runtime_init();
    lock_rt();
    size_t n;
    SEL *selrefs = section(h, slide, "__objc_selrefs", &n, 8);
    for (size_t i = 0; i < n; i++) selrefs[i] = S(selrefs[i]);
    struct protocol_t **pl = section(h, slide, "__objc_protolist", &n, 8);
    for (size_t i = 0; i < n; i++) canon_protocol(&pl[i]);
    struct protocol_t **pr = section(h, slide, "__objc_protorefs", &n, 8);
    for (size_t i = 0; i < n; i++) canon_protocol(&pr[i]);
    Class *cl = section(h, slide, "__objc_classlist", &n, 8);
    for (size_t i = 0; i < n; i++) if (RO(cl[i])->name && !sm_get(&classes, RO(cl[i])->name)) sm_put(&classes, RO(cl[i])->name, cl[i]);
    /* Swift classes carry an "is Swift" bit in their data pointer: bit 0 (legacy, what Apple's compilers emit) or bit 1 (stable ABI).
     * Apple's objc upgrades the legacy bit; scion's Swift runtime (built for Apple targets) only checks bit 1. */
    for (size_t i = 0; i < n; i++) if ((cl[i]->bits & 3) == 1) cl[i]->bits = (cl[i]->bits & ~(uintptr_t)3) | 2;
    if (!Protocol_class && (Protocol_class = sm_get(&classes, "Protocol"))) {
        for (size_t i = 0; i < protocols.cap; i++) if (protocols.k[i]) ((struct protocol_t *)protocols.v[i])->isa = Protocol_class;
    }
    const char *catsects[] = {"__objc_catlist", "__objc_catlist2"};
    for (int s = 0; s < 2; s++) {
        struct category_t **cats = section(h, slide, catsects[s], &n, 8);
        for (size_t i = 0; i < n; i++) {
            Class c = cats[i]->cls;
            if (!c) continue; /* weak-linked class missing */
            if (c->rw && c->rw->realized) { attach_category(c, cats[i]); cache_flush(); }
            else { uintptr_t *p = pm_slot(&pending_cats, (uintptr_t)c, 1); struct catnode *nn = malloc(sizeof *nn); nn->cat = cats[i]; nn->next = (struct catnode *)*p; *p = (uintptr_t)nn; }
        }
    }
    Class *nl = section(h, slide, "__objc_nlclslist", &n, 8);
    unlock_rt();
    for (size_t i = 0; i < n; i++) call_load(nl[i]);
    struct category_t **nlc = section(h, slide, "__objc_nlcatlist", &n, 8);
    for (size_t i = 0; i < n; i++) if (nlc[i]->cls) {
        realize(nlc[i]->cls);
        struct method_list_t *ml = nlc[i]->classMethods;
        if (ml) for (uint32_t k = 0; k < ml->count; k++) { SEL nm; const char *t; IMP imp; ml_get(ml, k, &nm, &t, &imp, 0); if (nm == S("load")) ((void (*)(Class, SEL))imp)(nlc[i]->cls, S("load")); }
    }
}

/* ===================================================================== reference counting (side table) */
#define NSHARD 64
static struct shard { pthread_mutex_t m; struct ptrmap rc; } shards[NSHARD]; /* extra retains beyond 1; flag bit 63 = deallocating */
static struct shard *shard_of(id o) { return &shards[hptr((uintptr_t)o) & (NSHARD - 1)]; }
#define DEALLOCATING (1ull << 63)
id _scion_objc_rootRetain(id o) {
    struct shard *s = shard_of(o);
    pthread_mutex_lock(&s->m); (*pm_slot(&s->rc, (uintptr_t)o, 1))++; pthread_mutex_unlock(&s->m);
    return o;
}
BOOL _scion_objc_rootTryRetain(id o) {
    struct shard *s = shard_of(o); BOOL ok;
    pthread_mutex_lock(&s->m);
    uintptr_t *v = pm_slot(&s->rc, (uintptr_t)o, 1);
    ok = !(*v & DEALLOCATING); if (ok) (*v)++;
    pthread_mutex_unlock(&s->m);
    return ok;
}
/* returns 1 when the object must be deallocated */
BOOL _scion_objc_rootRelease(id o) {
    struct shard *s = shard_of(o); int dealloc = 0;
    pthread_mutex_lock(&s->m);
    uintptr_t *v = pm_slot(&s->rc, (uintptr_t)o, 1);
    if (*v & DEALLOCATING) ;
    else if ((*v & ~DEALLOCATING) == 0) { *v = DEALLOCATING; dealloc = 1; }
    else (*v)--;
    pthread_mutex_unlock(&s->m);
    return dealloc;
}
uintptr_t _scion_objc_rootRetainCount(id o) {
    struct shard *s = shard_of(o);
    pthread_mutex_lock(&s->m); uintptr_t *v = pm_slot(&s->rc, (uintptr_t)o, 0); uintptr_t r = v ? (*v & ~DEALLOCATING) + 1 : 1; pthread_mutex_unlock(&s->m);
    return r;
}
static SEL s_retain, s_release, s_autorelease, s_dealloc, s_alloc, s_init, s_new, s_copy, s_class, s_isKindOfClass, s_respondsToSelector, s_self;
id objc_retain(id o) { if (!o) return o; return objc_msgSend(o, s_retain); }
void objc_release(id o) { if (o) objc_msgSend(o, s_release); }
id objc_autorelease(id o) { if (!o) return o; return objc_msgSend(o, s_autorelease); }
id objc_retainAutorelease(id o) { return objc_autorelease(objc_retain(o)); }
id objc_autoreleaseReturnValue(id o) { return objc_autorelease(o); }
id objc_retainAutoreleaseReturnValue(id o) { return objc_autorelease(objc_retain(o)); }
id objc_retainAutoreleasedReturnValue(id o) { return objc_retain(o); }
id objc_claimAutoreleasedReturnValue(id o) { return objc_retain(o); }
id objc_unsafeClaimAutoreleasedReturnValue(id o) { return o; }
id objc_retainBlock(id b) { return (id)_Block_copy(b); }
void objc_storeStrong(id *loc, id obj) { id old = *loc; if (old == obj) return; objc_retain(obj); *loc = obj; objc_release(old); }

/* ===================================================================== weak references */
static pthread_mutex_t weaklock;
static struct ptrmap weak_tab; /* object -> struct wlist* */
struct wlist { size_t n, cap; id *locs[]; };
static void weak_add(id o, id *loc) {
    uintptr_t *v = pm_slot(&weak_tab, (uintptr_t)o, 1);
    struct wlist *l = (struct wlist *)*v;
    if (!l || l->n == l->cap) { size_t cap = l ? l->cap * 2 : 4; struct wlist *n = realloc(l, sizeof *n + cap * sizeof(id *)); if (!l) n->n = 0; n->cap = cap; l = n; *v = (uintptr_t)l; }
    l->locs[l->n++] = loc;
}
static void weak_remove(id o, id *loc) {
    uintptr_t *v = pm_slot(&weak_tab, (uintptr_t)o, 0);
    if (!v) return;
    struct wlist *l = (struct wlist *)*v;
    for (size_t i = 0; i < l->n; i++) if (l->locs[i] == loc) { l->locs[i] = l->locs[--l->n]; break; }
}
static int deallocating(id o) {
    struct shard *s = shard_of(o); pthread_mutex_lock(&s->m);
    uintptr_t *v = pm_slot(&s->rc, (uintptr_t)o, 0); int d = v && (*v & DEALLOCATING);
    pthread_mutex_unlock(&s->m); return d;
}
id objc_storeWeak(id *loc, id obj) {
    pthread_mutex_lock(&weaklock);
    if (*loc) weak_remove(*loc, loc);
    if (obj && deallocating(obj)) obj = 0;
    if (obj) weak_add(obj, loc);
    *loc = obj;
    pthread_mutex_unlock(&weaklock);
    return obj;
}
id objc_initWeak(id *loc, id obj) { *loc = 0; return objc_storeWeak(loc, obj); }
id objc_initWeakOrNil(id *loc, id obj) { return objc_initWeak(loc, obj); }
id objc_storeWeakOrNil(id *loc, id obj) { return objc_storeWeak(loc, obj); }
void objc_destroyWeak(id *loc) { objc_storeWeak(loc, 0); }
id objc_loadWeakRetained(id *loc) {
    pthread_mutex_lock(&weaklock);
    id o = *loc;
    if (o && !_scion_objc_rootTryRetain(o)) o = 0;
    pthread_mutex_unlock(&weaklock);
    return o;
}
id objc_loadWeak(id *loc) { return objc_autorelease(objc_loadWeakRetained(loc)); }
/* copying and moving weak references never retain: a retain/release pair could deallocate (again) an object
 * whose deinit is what is moving its weak references around (Swift dictionaries of weak boxes) */
void objc_copyWeak(id *dst, id *src) {
    pthread_mutex_lock(&weaklock); id o = *src; pthread_mutex_unlock(&weaklock);
    *dst = 0; objc_storeWeak(dst, o);
}
void objc_moveWeak(id *dst, id *src) { objc_copyWeak(dst, src); objc_destroyWeak(src); }
static void weak_clear(id o) {
    pthread_mutex_lock(&weaklock);
    uintptr_t *v = pm_slot(&weak_tab, (uintptr_t)o, 0);
    if (v) { struct wlist *l = (struct wlist *)*v; for (size_t i = 0; i < l->n; i++) *l->locs[i] = 0; free(l); pm_del(&weak_tab, (uintptr_t)o); }
    pthread_mutex_unlock(&weaklock);
}

/* ===================================================================== associated objects */
static pthread_mutex_t assoclock;
static struct ptrmap assoc; /* object -> struct alist* */
struct aent { const void *key; id value; uintptr_t policy; };
struct alist { size_t n, cap; struct aent e[]; };
void objc_setAssociatedObject(id o, const void *key, id value, uintptr_t policy) {
    if (policy & 3) value = (policy & 3) == 3 ? objc_msgSend(value, s_copy) : objc_retain(value);
    id old = 0; uintptr_t oldp = 0;
    pthread_mutex_lock(&assoclock);
    uintptr_t *v = pm_slot(&assoc, (uintptr_t)o, 1);
    struct alist *l = (struct alist *)*v; size_t i = 0;
    if (l) for (; i < l->n; i++) if (l->e[i].key == key) break;
    if (l && i < l->n) { old = l->e[i].value; oldp = l->e[i].policy; l->e[i].value = value; l->e[i].policy = policy; }
    else {
        if (!l || l->n == l->cap) { size_t cap = l ? l->cap * 2 : 4; struct alist *n = realloc(l, sizeof *n + cap * sizeof(struct aent)); if (!l) n->n = 0; n->cap = cap; l = n; *v = (uintptr_t)l; }
        l->e[l->n++] = (struct aent){key, value, policy};
    }
    pthread_mutex_unlock(&assoclock);
    if (old && (oldp & 3)) objc_release(old);
}
id objc_getAssociatedObject(id o, const void *key) {
    id r = 0;
    pthread_mutex_lock(&assoclock);
    uintptr_t *v = pm_slot(&assoc, (uintptr_t)o, 0);
    if (v) { struct alist *l = (struct alist *)*v; for (size_t i = 0; i < l->n; i++) if (l->e[i].key == key) r = l->e[i].value; }
    pthread_mutex_unlock(&assoclock);
    return r;
}
void objc_removeAssociatedObjects(id o) {
    pthread_mutex_lock(&assoclock);
    uintptr_t *v = pm_slot(&assoc, (uintptr_t)o, 0);
    struct alist *l = v ? (struct alist *)*v : 0;
    if (v) pm_del(&assoc, (uintptr_t)o);
    pthread_mutex_unlock(&assoclock);
    if (l) { for (size_t i = 0; i < l->n; i++) if (l->e[i].policy & 3) objc_release(l->e[i].value); free(l); }
}

/* ===================================================================== object lifecycle */
id class_createInstance(Class c, size_t extra) {
    if (!c) return 0;
    realize(c);
    id o = calloc(1, c->rw->instanceSize + extra);
    if (!o) return 0;
    o->isa = c;
    return o;
}
id _objc_rootAllocWithZone(Class c, void *zone) { return class_createInstance(c, 0); }
void *objc_destructInstance(id o) {
    if (!o) return o;
    for (Class c = o->isa; c; c = c->superclass) { /* ARC: .cxx_destruct releases strong ivars */
        realize(c);
        if (c->rw->has_cxx_destruct) { IMP d = find_in_class(c, S(".cxx_destruct"), 0); if (d) ((void (*)(id, SEL))d)(o, S(".cxx_destruct")); }
    }
    weak_clear(o);
    objc_removeAssociatedObjects(o);
    struct shard *s = shard_of(o); pthread_mutex_lock(&s->m); pm_del(&s->rc, (uintptr_t)o); pthread_mutex_unlock(&s->m);
    return o;
}
id object_dispose(id o) { if (o) { objc_destructInstance(o); free(o); } return 0; }
id objc_alloc(Class c) { return c ? objc_msgSend((id)c, s_alloc) : 0; }
id objc_allocWithZone(Class c) { return c ? ((id (*)(id, SEL, void *))objc_msgSend)((id)c, S("allocWithZone:"), (void *)0) : 0; } /* not objc_alloc: +alloc overrides often call [self allocWithZone:] */
id objc_alloc_init(Class c) { id o = objc_alloc(c); return o ? objc_msgSend(o, s_init) : 0; }
id objc_opt_new(Class c) { return c ? objc_msgSend((id)c, s_new) : 0; }
Class objc_opt_class(id o) { return o ? (Class)objc_msgSend(o, s_class) : 0; }
id objc_opt_self(id o) { return o; }
BOOL objc_opt_isKindOfClass(id o, Class c) { return o ? ((BOOL (*)(id, SEL, Class))objc_msgSend)(o, s_isKindOfClass, c) : 0; }
BOOL objc_opt_respondsToSelector(id o, SEL s) { return o ? ((BOOL (*)(id, SEL, SEL))objc_msgSend)(o, s_respondsToSelector, s) : 0; }

/* ===================================================================== autorelease pools (per thread) */
struct pool { size_t n, cap; id *objs; };
static unsigned long pool_key;
#define POOL_BOUNDARY ((id)0)
static struct pool *thread_pool(void) {
    struct pool *p = pthread_getspecific(pool_key);
    if (!p) { p = calloc(1, sizeof *p); pthread_setspecific(pool_key, p); }
    return p;
}
static void pool_add(struct pool *p, id o) {
    if (p->n == p->cap) { p->cap = p->cap ? p->cap * 2 : 256; p->objs = realloc(p->objs, p->cap * sizeof(id)); }
    p->objs[p->n++] = o;
}
void *objc_autoreleasePoolPush(void) { struct pool *p = thread_pool(); pool_add(p, POOL_BOUNDARY); return (void *)(uintptr_t)p->n; }
void objc_autoreleasePoolPop(void *token) {
    struct pool *p = thread_pool();
    size_t to = (size_t)(uintptr_t)token;
    if (!to) to = 1;
    while (p->n >= to) { id o = p->objs[--p->n]; if (o) objc_release(o); }
}
id _scion_objc_rootAutorelease(id o) {
    struct pool *p = thread_pool();
    pool_add(p, o);
    return o;
}

/* ===================================================================== properties / misc */
static pthread_mutex_t proplock;
id objc_getProperty(id self, SEL _cmd, ptrdiff_t off, BOOL atomic) {
    id *slot = (id *)((char *)self + off);
    if (!atomic) return *slot;
    pthread_mutex_lock(&proplock); id v = objc_retain(*slot); pthread_mutex_unlock(&proplock);
    return objc_autorelease(v);
}
static void setprop(id self, ptrdiff_t off, id v, BOOL atomic, int copy) {
    id *slot = (id *)((char *)self + off);
    if (copy) v = objc_msgSend(v, copy == 2 ? S("mutableCopy") : s_copy); else v = objc_retain(v);
    if (atomic) pthread_mutex_lock(&proplock);
    id old = *slot; *slot = v;
    if (atomic) pthread_mutex_unlock(&proplock);
    objc_release(old);
}
void objc_setProperty(id self, SEL _cmd, ptrdiff_t off, id v, BOOL atomic, signed char copy) { setprop(self, off, v, atomic, copy); }
void objc_setProperty_atomic(id self, SEL _cmd, id v, ptrdiff_t off) { setprop(self, off, v, 1, 0); }
void objc_setProperty_nonatomic(id self, SEL _cmd, id v, ptrdiff_t off) { setprop(self, off, v, 0, 0); }
void objc_setProperty_atomic_copy(id self, SEL _cmd, id v, ptrdiff_t off) { setprop(self, off, v, 1, 1); }
void objc_setProperty_nonatomic_copy(id self, SEL _cmd, id v, ptrdiff_t off) { setprop(self, off, v, 0, 1); }
void objc_copyStruct(void *dst, const void *src, ptrdiff_t size, BOOL atomic, BOOL strong) {
    if (atomic) pthread_mutex_lock(&proplock);
    memcpy(dst, src, size);
    if (atomic) pthread_mutex_unlock(&proplock);
}
void objc_copyCppObjectAtomic(void *dst, const void *src, void (*cp)(void *, const void *)) { pthread_mutex_lock(&proplock); cp(dst, src); pthread_mutex_unlock(&proplock); }
void objc_enumerationMutation(id o) { die2("collection mutated while being enumerated", 0); }
void objc_setEnumerationMutationHandler(void (*h)(id)) {}

/* @synchronized: recursive locks keyed by object */
struct synclock { id obj; void *owner; int depth; pthread_mutex_t m; struct synclock *next; };
static pthread_mutex_t synclist_lock; static struct synclock *synclocks;
static struct synclock *sync_for(id o) {
    pthread_mutex_lock(&synclist_lock);
    struct synclock *s = synclocks;
    while (s && s->obj != o) s = s->next;
    if (!s) { s = calloc(1, sizeof *s); s->obj = o; s->next = synclocks; synclocks = s; }
    pthread_mutex_unlock(&synclist_lock);
    return s;
}
int objc_sync_enter(id o) {
    if (!o) return 0;
    struct synclock *s = sync_for(o); void *me = pthread_self();
    if (s->owner == me) { s->depth++; return 0; }
    pthread_mutex_lock(&s->m); s->owner = me; s->depth = 1; return 0;
}
int objc_sync_exit(id o) {
    if (!o) return 0;
    struct synclock *s = sync_for(o);
    if (s->owner != pthread_self()) return -1;
    if (--s->depth == 0) { s->owner = 0; pthread_mutex_unlock(&s->m); }
    return 0;
}

/* ===================================================================== exceptions (Apple's modern ABI)
 * An ObjC exception is a C++ exception (libc++abi) whose type_info is an objc_typeinfo: its vtable is
 * objc_ehtype_vtable+2, and the can_catch slot matches by class. @catch(Foo *) refers to OBJC_EHTYPE_$_Foo
 * (emitted by the compiler or by the framework that owns the class), @catch(id) to OBJC_EHTYPE_id. */
struct objc_typeinfo { const void *const *vtable; const char *name; Class cls; };
struct objc_exception { id obj; struct objc_typeinfo tinfo; };
void *__cxa_allocate_exception(size_t); void __cxa_throw(void *, void *, void (*)(void *)) __attribute__((noreturn));
void __cxa_rethrow(void) __attribute__((noreturn)); void *__cxa_begin_catch(void *); void __cxa_end_catch(void);
void *__cxa_current_exception_type(void); void *__cxa_current_primary_exception(void); void __cxa_decrement_exception_refcount(void *);
int __gxx_personality_v0(int, int, uint64_t, void *, void *); void _ZSt9terminatev(void) __attribute__((noreturn));
void (*_ZSt13set_terminatePFvvE(void (*)(void)))(void); /* std::set_terminate */
static void noop(void *a) {}
static int no(void *a) { return 0; }
static int do_catch(struct objc_typeinfo *catch_ti, struct objc_typeinfo *throw_ti, void **obj_p);
const void *objc_ehtype_vtable[] = { 0, 0, (void *)noop, (void *)noop, (void *)no, (void *)no, (void *)do_catch, (void *)no, (void *)no, (void *)no };
struct objc_typeinfo OBJC_EHTYPE_id = { objc_ehtype_vtable + 2, "id", 0 };
static int do_catch(struct objc_typeinfo *catch_ti, struct objc_typeinfo *throw_ti, void **obj_p) {
    if (throw_ti->vtable != objc_ehtype_vtable + 2) return 0;   /* a C++ exception: not ours */
    /* libc++abi passes a pointer to the thrown object (&objc_exception.obj); the catch gets the id itself.
     * *obj_p is recomputed by libc++abi for every catch clause, so dereferencing here is safe. */
    id e = *(id *)*obj_p;
    *obj_p = e;
    if (catch_ti == &OBJC_EHTYPE_id) return 1;
    Class want = catch_ti->cls;                                    /* 0: weak-linked class missing, no match */
    for (Class c = e ? e->isa : 0; want && c; c = c->superclass) if (c == want) return 1;
    return 0;
}
static void exc_destructor(void *p) { struct objc_exception *x = p; objc_release(x->obj); }
typedef id (*objc_exception_preprocessor)(id);
typedef void (*objc_uncaught_exception_handler)(id);
static objc_exception_preprocessor preprocessor;
static objc_uncaught_exception_handler uncaught_handler;
static void (*old_terminate)(void);
objc_exception_preprocessor objc_setExceptionPreprocessor(objc_exception_preprocessor f) { objc_exception_preprocessor o = preprocessor; preprocessor = f; return o; }
objc_uncaught_exception_handler objc_setUncaughtExceptionHandler(objc_uncaught_exception_handler f) { objc_uncaught_exception_handler o = uncaught_handler; uncaught_handler = f; return o; }
static void objc_terminate_handler(void) {
    struct objc_typeinfo *t = __cxa_current_exception_type();
    if (t && t->vtable == objc_ehtype_vtable + 2) {
        void *p = __cxa_current_primary_exception();
        id e = p ? *(id *)p : 0;
        if (uncaught_handler) uncaught_handler(e);
        else { say("*** Terminating app due to uncaught exception of class '"); say(e ? RO(e->isa)->name : "nil"); say("'\n"); }
        abort();
    }
    if (old_terminate) old_terminate();
    abort();
}
void objc_exception_throw(id obj) {
    static int once; if (!once) { once = 1; old_terminate = _ZSt13set_terminatePFvvE(objc_terminate_handler); }
    if (preprocessor) obj = preprocessor(obj);
    struct objc_exception *x = __cxa_allocate_exception(sizeof *x);
    x->obj = objc_retain(obj);
    x->tinfo.vtable = objc_ehtype_vtable + 2;
    x->tinfo.name = obj ? RO(obj->isa)->name : "nil";
    x->tinfo.cls = obj ? obj->isa : 0;
    __cxa_throw(x, &x->tinfo, exc_destructor);
}
void objc_exception_rethrow(void) { __cxa_rethrow(); }
id objc_begin_catch(void *e) { return (id)__cxa_begin_catch(e); }
void objc_end_catch(void) { __cxa_end_catch(); }
int __objc_personality_v0(int v, int a, uint64_t c, void *u, void *ctx) { return __gxx_personality_v0(v, a, c, u, ctx); }
void objc_terminate(void) { _ZSt9terminatev(); }

/* ===================================================================== public runtime API */
typedef BOOL (*mw_hook_getClass)(const char *name, Class *out);
static BOOL no_getClass(const char *name, Class *out) { return 0; }
static mw_hook_getClass hook_getClass = no_getClass;
/* a class not in the table may be one another runtime knows by name (Swift: mangled names): the getClass hook */
Class objc_getClass(const char *n) {
    if (!n) return 0;
    lock_rt(); Class c = sm_get(&classes, n); unlock_rt();
    if (!c && hook_getClass != no_getClass) { Class h = 0; if (hook_getClass(n, &h)) c = h; }
    return c;
}
void objc_setHook_getClass(mw_hook_getClass nv, mw_hook_getClass *old) { lock_rt(); *old = hook_getClass; hook_getClass = nv; unlock_rt(); }
Class objc_lookUpClass(const char *n) { return objc_getClass(n); }
Class objc_getRequiredClass(const char *n) { Class c = objc_getClass(n); if (!c) die2("class not found: ", n); return c; }
Class objc_getMetaClass(const char *n) { Class c = objc_getClass(n); return c ? c->isa : 0; }
typedef const char *(*mw_hook_lazyClassNamer)(Class c);
static mw_hook_lazyClassNamer hook_lazyClassNamer;
/* Swift generic classes have no name in their ro data until asked: the lazy class namer hook names them */
const char *class_getName(Class c) {
    if (!c) return "nil";
    const char *n = RO(c)->name;
    if (!n && hook_lazyClassNamer) n = hook_lazyClassNamer(IS_META(c) && c->rw && c->rw->nonmeta ? c->rw->nonmeta : c);
    return n ? n : "";
}
void objc_setHook_lazyClassNamer(mw_hook_lazyClassNamer nv, mw_hook_lazyClassNamer *old) { lock_rt(); *old = hook_lazyClassNamer; hook_lazyClassNamer = nv; unlock_rt(); }
Class class_getSuperclass(Class c) { return c ? c->superclass : 0; }
BOOL class_isMetaClass(Class c) { return c && IS_META(c); }
size_t class_getInstanceSize(Class c) { if (!c) return 0; realize(c); return c->rw->instanceSize; }
Class object_getClass(id o) { return o ? o->isa : 0; }
Class object_setClass(id o, Class c) { Class old = o ? o->isa : 0; if (o) o->isa = c; return old; }
const char *object_getClassName(id o) { return class_getName(object_getClass(o)); }
void *object_getIndexedIvars(id o) { return o ? (char *)o + class_getInstanceSize(o->isa) : 0; }
BOOL object_isClass(id o) { return o && IS_META(o->isa); }
IMP class_getMethodImplementation(Class c, SEL s) { IMP i = _scion_objc_lookup(0, s, c); return i; }
BOOL class_respondsToSelector(Class c, SEL s) { return c && find_method(c, s) != 0; }

/* Method handles: we hand out pointers to method entries; small-list entries are wrapped */
struct mhandle { SEL name; const char *types; IMP imp; struct method_list_t *ml; uint32_t idx; };
static struct ptrmap mhandles;
static struct mhandle *method_handle(Class c, SEL sel) {
    for (; c; c = c->superclass) {
        realize(c);
        for (int k = 0; k < c->rw->nmlists; k++) {
            struct method_list_t *ml = c->rw->mlists[k];
            for (uint32_t i = 0; i < ml->count; i++) {
                SEL n; const char *t; IMP imp; ml_get(ml, i, &n, &t, &imp, 0);
                if (n != sel) continue;
                uintptr_t key = (uintptr_t)ml + i;
                lock_rt();
                uintptr_t *v = pm_slot(&mhandles, key, 1);
                if (!*v) { struct mhandle *h = malloc(sizeof *h); *h = (struct mhandle){n, t, imp, ml, i}; *v = (uintptr_t)h; }
                unlock_rt();
                return (struct mhandle *)*v;
            }
        }
    }
    return 0;
}
void *class_getInstanceMethod(Class c, SEL s) { return c ? method_handle(c, s) : 0; }
void *class_getClassMethod(Class c, SEL s) { return c ? method_handle(c->isa, s) : 0; }
SEL method_getName(struct mhandle *m) { return m ? m->name : 0; }
IMP method_getImplementation(struct mhandle *m) { return m ? m->imp : 0; }
const char *method_getTypeEncoding(struct mhandle *m) { return m ? m->types : 0; }
/* type encodings: one type, then its stack offset digits */
static int qualifier(char c) { return c == 'r' || c == 'n' || c == 'N' || c == 'o' || c == 'O' || c == 'R' || c == 'V'; }
static char *dup_str(const char *b) { size_t n = 0; while (b[n]) n++; char *d = malloc(n + 1); memcpy(d, b, n + 1); return d; }
static const char *skip_type(const char *t) {
    while (*t && qualifier(*t)) t++;
    switch (*t) {
    case 0: return t;
    case '^': return skip_type(t + 1);
    case '@': t++; if (*t == '"') { t++; while (*t && *t != '"') t++; if (*t) t++; } else if (*t == '?') t++; return t;
    case 'b': t++; while (*t >= '0' && *t <= '9') t++; return t;
    case '{': case '[': case '(': {
        char open = *t, close = open == '{' ? '}' : open == '[' ? ']' : ')'; int depth = 0;
        do { if (*t == open) depth++; else if (*t == close) depth--; t++; } while (*t && depth);
        return t;
    }
    default: return t + 1;
    }
}
static const char *type_at(const char *types, unsigned idx) { /* 0: return type, 1: self, 2: _cmd, 3...: arguments */
    const char *t = types;
    for (unsigned i = 0; t && *t && i < idx; i++) { t = skip_type(t); while (*t >= '0' && *t <= '9') t++; if (*t == '+' || *t == '-') { t++; while (*t >= '0' && *t <= '9') t++; } }
    return t && *t ? t : 0;
}
static void copy_type(const char *t, char *dst, size_t n) {
    if (!dst || !n) return;
    size_t len = t ? (size_t)(skip_type(t) - t) : 0;
    if (len >= n) len = n - 1;
    if (len) memcpy(dst, t, len);
    dst[len] = 0;
}
void method_getReturnType(struct mhandle *m, char *dst, size_t n) { copy_type(m ? type_at(m->types, 0) : 0, dst, n); }
void method_getArgumentType(struct mhandle *m, unsigned idx, char *dst, size_t n) { copy_type(m ? type_at(m->types, idx + 1) : 0, dst, n); }
unsigned method_getNumberOfArguments(struct mhandle *m) { unsigned n = 0; while (m && type_at(m->types, n + 1)) n++; return n; }
char *method_copyReturnType(struct mhandle *m) { char b[256]; method_getReturnType(m, b, sizeof b); return dup_str(b); }
char *method_copyArgumentType(struct mhandle *m, unsigned idx) { char b[256]; method_getArgumentType(m, idx, b, sizeof b); return b[0] ? dup_str(b) : 0; }
static void set_imp(struct mhandle *m, IMP imp) {
    m->imp = imp;
    uint8_t *e = (uint8_t *)(m->ml + 1) + (size_t)m->idx * ml_entsize(m->ml);
    if (ml_small(m->ml)) { int32_t *o = (int32_t *)e; o[2] = (int32_t)((intptr_t)imp - (intptr_t)&o[2]); }
    else ((struct method_t *)e)->imp = imp;
    cache_flush();
}
IMP method_setImplementation(struct mhandle *m, IMP imp) { IMP old = m ? m->imp : 0; if (m) { lock_rt(); set_imp(m, imp); unlock_rt(); } return old; }
void method_exchangeImplementations(struct mhandle *a, struct mhandle *b) {
    if (!a || !b) return;
    lock_rt(); IMP ia = a->imp; set_imp(a, b->imp); set_imp(b, ia); unlock_rt();
}
BOOL class_addMethod(Class c, SEL s, IMP imp, const char *types) {
    realize(c);
    if (find_in_class(c, s, 0)) return 0;
    struct method_list_t *ml = calloc(1, sizeof *ml + sizeof(struct method_t));
    ml->entsize_flags = sizeof(struct method_t) | 3; ml->count = 1;
    struct method_t *m = (struct method_t *)(ml + 1); m->name = S(s); m->types = types; m->imp = imp;
    lock_rt(); add_mlist(c->rw, ml, 1); cache_flush(); unlock_rt();
    return 1;
}
IMP class_replaceMethod(Class c, SEL s, IMP imp, const char *types) {
    realize(c);
    const char *t; IMP old = find_in_class(c, s, &t);
    if (old) { struct mhandle *m = method_handle(c, s); method_setImplementation(m, imp); return old; }
    class_addMethod(c, s, imp, types);
    return 0;
}
void *objc_getProtocol(const char *n) { lock_rt(); void *p = sm_get(&protocols, n); unlock_rt(); return p; }
const char *protocol_getName(struct protocol_t *p) { return p ? p->name : 0; }
static BOOL proto_conforms(struct protocol_t *a, struct protocol_t *b) {
    if (!a || !b) return 0;
    if (a == b || !strcmp(a->name, b->name)) return 1;
    if (a->protocols) for (uintptr_t i = 0; i < a->protocols->count; i++) if (proto_conforms(a->protocols->list[i], b)) return 1;
    return 0;
}
BOOL protocol_conformsToProtocol(struct protocol_t *a, struct protocol_t *b) { return proto_conforms(a, b); }
BOOL class_conformsToProtocol(Class c, struct protocol_t *p) {
    if (!c || !p) return 0;
    realize(c);
    for (int k = 0; k < c->rw->nplists; k++)
        for (uintptr_t i = 0; i < c->rw->plists[k]->count; i++) if (proto_conforms(c->rw->plists[k]->list[i], p)) return 1;
    return 0;
}
void *class_getInstanceVariable(Class c, const char *name) {
    for (; c; c = c->superclass) {
        const struct class_ro_t *ro = RO(c);
        if (ro->ivars) for (uint32_t i = 0; i < ro->ivars->count; i++) {
            struct ivar_t *iv = (struct ivar_t *)((uint8_t *)&ro->ivars->first + (size_t)i * (ro->ivars->entsize_flags & ~3u));
            if (!strcmp(iv->name, name)) return iv;
        }
    }
    return 0;
}
ptrdiff_t ivar_getOffset(struct ivar_t *iv) { return iv && iv->offset ? *iv->offset : 0; }
const char *ivar_getName(struct ivar_t *iv) { return iv ? iv->name : 0; }
const char *ivar_getTypeEncoding(struct ivar_t *iv) { return iv ? iv->type : 0; }
int objc_getClassList(Class *buf, int n) {
    lock_rt(); int k = 0;
    for (size_t i = 0; i < classes.cap; i++) if (classes.k[i]) { if (buf && k < n) buf[k] = classes.v[i]; k++; }
    unlock_rt(); return k;
}

/* dynamic classes (objc_allocateClassPair) */
Class objc_allocateClassPair(Class super, const char *name, size_t extra) {
    if (objc_getClass(name)) return 0;
    if (super) realize(super);
    struct objc_class *cls = calloc(1, sizeof *cls + extra), *meta = calloc(1, sizeof *meta + extra);
    struct class_ro_t *ro = calloc(1, sizeof *ro), *mro = calloc(1, sizeof *mro);
    size_t nl = strlen(name) + 1; char *nm = malloc(nl); memcpy(nm, name, nl);
    ro->name = mro->name = nm;
    ro->instanceStart = ro->instanceSize = super ? (uint32_t)super->rw->instanceSize : 8;
    mro->flags = RO_META; mro->instanceStart = mro->instanceSize = sizeof(struct objc_class);
    cls->bits = (uintptr_t)ro; meta->bits = (uintptr_t)mro;
    cls->isa = meta; cls->superclass = super;
    meta->isa = super ? super->isa->isa : meta; meta->superclass = super ? super->isa : cls;
    cls->cache = meta->cache = _objc_empty_cache;
    return cls;
}
/* a class pair whose memory the caller provides (Swift): the same set-up as objc_allocateClassPair */
Class objc_initializeClassPair(Class super, const char *name, Class cls, Class meta) {
    if (super) realize(super);
    struct class_ro_t *ro = calloc(1, sizeof *ro), *mro = calloc(1, sizeof *mro);
    size_t nl = strlen(name) + 1; char *nm = malloc(nl); memcpy(nm, name, nl);
    ro->name = mro->name = nm;
    ro->instanceStart = ro->instanceSize = super ? (uint32_t)super->rw->instanceSize : 8;
    mro->flags = RO_META; mro->instanceStart = mro->instanceSize = sizeof(struct objc_class);
    cls->bits = (uintptr_t)ro; meta->bits = (uintptr_t)mro;
    cls->isa = meta; cls->superclass = super;
    meta->isa = super ? super->isa->isa : meta; meta->superclass = super ? super->isa : cls;
    cls->cache = meta->cache = _objc_empty_cache; cls->rw = meta->rw = 0;
    return cls;
}
BOOL class_addProtocol(Class c, struct protocol_t *p) {
    if (!c || !p || class_conformsToProtocol(c, p)) return 0;
    struct protocol_list_t *pl = malloc(sizeof *pl + sizeof pl->list[0]);
    pl->count = 1; pl->list[0] = p;
    lock_rt(); add_plist(c->rw, pl); unlock_rt();
    return 1;
}
const uint8_t *class_getIvarLayout(Class c) { return c ? RO(c)->ivarLayout : 0; }
const uint8_t *class_getWeakIvarLayout(Class c) { return c ? RO(c)->weakIvarLayout : 0; }
id object_getIvar(id o, struct ivar_t *iv) { return o && iv ? *(id *)((uint8_t *)o + ivar_getOffset(iv)) : 0; }
void object_setIvar(id o, struct ivar_t *iv, id v) { if (o && iv) *(id *)((uint8_t *)o + ivar_getOffset(iv)) = v; }
void object_setIvarWithStrongDefault(id o, struct ivar_t *iv, id v) { object_setIvar(o, iv, v); }
const char *class_getImageName(Class c);
/* the names of the classes defined in one image */
const char **objc_copyClassNamesForImage(const char *image, unsigned *out) {
    int n = objc_getClassList(0, 0); Class *all = malloc((size_t)(n ? n : 1) * sizeof(Class)); n = objc_getClassList(all, n);
    const char **names = malloc((size_t)(n + 1) * sizeof(char *)); unsigned k = 0;
    for (int i = 0; i < n; i++) { const char *im = class_getImageName(all[i]); if (im && image && !strcmp(im, image)) names[k++] = RO(all[i])->name; }
    names[k] = 0; free(all);
    if (out) *out = k;
    if (!k) { free(names); return 0; }
    return names;
}
struct objc_method_description { SEL name; const char *types; };
static int md_find(struct method_list_t *ml, SEL s, struct objc_method_description *d) {
    if (!ml) return 0;
    for (uint32_t i = 0; i < ml->count; i++) { SEL n; const char *t; IMP imp; int32_t *slot; ml_get(ml, i, &n, &t, &imp, &slot); if (n == s || (n && !strcmp(n, s))) { d->name = s; d->types = t; return 1; } }
    return 0;
}
struct objc_method_description protocol_getMethodDescription(struct protocol_t *p, SEL s, BOOL required, BOOL instance) {
    struct objc_method_description d = {0, 0};
    if (!p) return d;
    struct method_list_t *ml = required ? (instance ? p->instanceMethods : p->classMethods) : (instance ? p->optionalInstanceMethods : p->optionalClassMethods);
    if (md_find(ml, s, &d)) return d;
    if (p->protocols) for (uintptr_t i = 0; i < p->protocols->count; i++) { d = protocol_getMethodDescription(p->protocols->list[i], s, required, instance); if (d.name) return d; }
    return d;
}
void objc_registerClassPair(Class c) { realize(c); lock_rt(); sm_put(&classes, RO(c)->name, c); unlock_rt(); }
BOOL class_addIvar(Class c, const char *n, size_t size, uint8_t align, const char *types) {
    realize(c);
    uint32_t a = 1u << align, off = (c->rw->instanceSize + a - 1) & ~(a - 1);
    c->rw->instanceSize = off + (uint32_t)size;
    return 1;
}

/* ===================================================================== blocks as objects */
static void block_retain_obj(const void *o) { objc_retain((id)o); }
static void block_release_obj(const void *o) { objc_release((id)o); }

static int rt_inited;
extern struct objc_class OBJC_CLASS_$___NSStackBlock, OBJC_CLASS_$___NSMallocBlock, OBJC_CLASS_$___NSGlobalBlock;
static void runtime_init(void) {
    if (rt_inited) return;
    rt_inited = 1;
    _scion_objc_cache = new_ctable(4096);
    pthread_key_create(&pool_key, 0);
    s_retain = S("retain"); s_release = S("release"); s_autorelease = S("autorelease"); s_dealloc = S("dealloc");
    s_alloc = S("alloc"); s_init = S("init"); s_new = S("new"); s_copy = S("copy"); s_class = S("class");
    s_isKindOfClass = S("isKindOfClass:"); s_respondsToSelector = S("respondsToSelector:"); s_self = S("self");
    static const struct Block_callbacks_RR rr = {sizeof rr, block_retain_obj, block_release_obj, 0};
    _Block_use_RR2(&rr);
}
extern void *_dispatch_object_class[32];
void _scion_objc_setup_dispatch(Class c) { memcpy(_dispatch_object_class, c, sizeof(struct objc_class)); cache_flush(); }
/* Block isa arrays become real classes once NSObject.m's __NSStackBlock & co. are registered */
void _scion_objc_setup_blocks(Class stack, Class mallocb, Class global) {
    memcpy(_NSConcreteStackBlock, stack, sizeof(struct objc_class));
    memcpy(_NSConcreteMallocBlock, mallocb, sizeof(struct objc_class));
    memcpy(_NSConcreteGlobalBlock, global, sizeof(struct objc_class));
    cache_flush();
}

/* ===================================================================== Swift runtime support */
/* the image a class lives in (getImageName hook: Swift answers for classes it allocated) */
typedef BOOL (*mw_hook_getImageName)(Class c, const char **out);
const char *dyld_image_path_containing_address(const void *a);
static BOOL default_getImageName(Class c, const char **out) { *out = dyld_image_path_containing_address(c); return *out != 0; }
static mw_hook_getImageName hook_getImageName = default_getImageName;
void objc_setHook_getImageName(mw_hook_getImageName nv, mw_hook_getImageName *old) { lock_rt(); *old = hook_getImageName; hook_getImageName = nv; unlock_rt(); }
const char *class_getImageName(Class c) { const char *n = 0; return c && hook_getImageName(c, &n) ? n : 0; }

/* a class pair laid out by someone else (Swift metadata initialized at run time): realize it and make it known by name */
Class objc_readClassPair(Class c, const void *imageInfo) {
    if (!c) return 0;
    realize(c);
    const char *n = RO(c)->name;
    if (n) { lock_rt(); if (!sm_get(&classes, n)) sm_put(&classes, n, c); unlock_rt(); }
    return c;
}
Class _objc_realizeClassFromSwift(Class c, void *previously) { if (c) realize(c); return c; }

/* an instance in memory the caller allocated: isa, then C++ ivar constructors */
id objc_constructInstance(Class c, void *bytes) {
    if (!c || !bytes) return 0;
    realize(c);
    id o = (id)bytes; o->isa = c;
    for (Class k = c; k; k = k->superclass) {
        const struct class_ro_t *ro = RO(k);
        if (ro->flags & RO_HAS_CXX_STRUCTORS) { IMP ctor = find_in_class(k, S(".cxx_construct"), 0); if (ctor) { ((id (*)(id, SEL))ctor)(o, S(".cxx_construct")); break; } }
    }
    return o;
}
Class class_setSuperclass(Class c, Class sup) {
    lock_rt();
    Class old = c->superclass;
    c->superclass = sup;
    if (sup) c->isa->superclass = sup->isa;
    cache_flush();
    unlock_rt();
    return old;
}
struct ivar_t **class_copyIvarList(Class c, unsigned int *count) {
    const struct class_ro_t *ro = c ? RO(c) : 0;
    unsigned n = ro && ro->ivars ? ro->ivars->count : 0;
    if (count) *count = n;
    if (!n) return 0;
    struct ivar_t **v = malloc((n + 1) * sizeof *v);
    for (unsigned i = 0; i < n; i++) v[i] = (struct ivar_t *)((uint8_t *)&ro->ivars->first + (size_t)i * (ro->ivars->entsize_flags & ~3u));
    v[n] = 0;
    return v;
}
id _objc_rootAutorelease(id o) { return _scion_objc_rootAutorelease(o); }
