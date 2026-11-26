/* more.m — Foundation classes for document-based apps and the libraries they bundle: NSMethodSignature and NSInvocation
 * (with -forwardInvocation: through libobjc's forwarding stub), NSProxy, NSUndoManager, NSSortDescriptor,
 * NSValueTransformer, NSByteCountFormatter, streams, URL requests and URLSession (on the host's HTTP stack), NSFileCoordinator,
 * NSArchiver, NSDistributedNotificationCenter and a few stand-ins (NSAppleScript, NSXMLDocument, Mach ports). */
#include "internal.h"
#include "../hostcalls.h"
#import <objc/runtime.h>
#import <objc/message.h>
typedef struct dqueue *dq_t; extern struct dqueue _dispatch_main_q; void dispatch_async(dq_t, void (^)(void));
void *_Block_copy(const void *); void _Block_release(const void *);

/* ======================================================================= calling convention */
/* A frame holds the argument registers as the forwarding stub saves them (and _scion_objc_invoke loads them):
 * x86_64: rdi..r9 at 0, xmm0-7 at 48, stack arguments at 208 past the stub's frame; arm64: x0-x7 at 0, x8 at 64,
 * q0-q7 at 80, stack arguments at 224. Each argument is a list of pieces copied between the frame and its buffer. */
#if defined(__x86_64__)
enum { NGPR = 6, FPR_OFF = 48, STACK_OFF = 208 };
#else
enum { NGPR = 8, FPR_OFF = 80, STACK_OFF = 224 };
#endif
enum { P_GPR, P_FPR, P_STACK, P_REF };
typedef struct { uint8_t kind, reg; uint16_t len, off, src; } piece;   /* off: stack offset; src: offset in the value */
typedef struct { const char *type; uint32_t size, align, n; piece p[4]; } argloc;
extern void _scion_objc_invoke(void *frame, IMP imp, const void *stack, size_t bytes);
extern int (*_scion_forward_invocation_hook)(id self, SEL sel, void *frame);

static const char *skip_qual(const char *t) { while (*t && strchr("rnNoORVA+", *t)) t++; return t; }
static const char *skip_num(const char *t) { if (*t == '-') t++; while (*t >= '0' && *t <= '9') t++; return t; }
/* the scalar fields of a type with their offsets: fp[] gets 'f'/'d' or 'i' per field */
typedef struct { int n; uint16_t off[16]; char kind[16]; uint8_t len[16]; } fields;
static const char *type_info(const char *t, uint32_t *size, uint32_t *align, fields *f, uint32_t base);
static const char *struct_info(const char *t, char close, uint32_t *size, uint32_t *align, fields *f, uint32_t base, int is_union) {
    while (*t && *t != '=' && *t != close) t++;  /* name */
    uint32_t sz = 0, al = 1;
    if (*t == '=') {
        t++;
        while (*t && *t != close) {
            if (*t == '"') { t++; while (*t && *t != '"') t++; if (*t) t++; } /* field name */
            uint32_t s, a;
            uint32_t at = is_union ? 0 : (sz + 0) ;
            /* align the field first: compute its alignment with a dry run */
            uint32_t ds, da; type_info(t, &ds, &da, 0, 0);
            if (!is_union) at = (sz + da - 1) / da * da;
            t = type_info(t, &s, &a, f, base + at);
            if (a > al) al = a;
            sz = is_union ? (s > sz ? s : sz) : at + s;
        }
    }
    if (*t == close) t++;
    *size = (sz + al - 1) / al * al; *align = al;
    return t;
}
static void add_field(fields *f, uint32_t off, char k, uint32_t len) { if (f && f->n < 16) { f->off[f->n] = (uint16_t)off; f->kind[f->n] = k; f->len[f->n] = (uint8_t)len; f->n++; } }
static const char *type_info(const char *t, uint32_t *size, uint32_t *align, fields *f, uint32_t base) {
    t = skip_qual(t);
    uint32_t s = 8; char k = 'i';
    switch (*t) {
    case 'c': case 'C': case 'B': s = 1; t++; break;
    case 's': case 'S': s = 2; t++; break;
    case 'i': case 'I': case 'l': case 'L': s = 4; t++; break;
    case 'f': s = 4; k = 'f'; t++; break;
    case 'd': s = 8; k = 'd'; t++; break;
#if defined(__x86_64__)
    case 'D': s = 16; k = 'D'; t++; break;
#else
    case 'D': s = 8; k = 'd'; t++; break;
#endif
    case 'q': case 'Q': case '*': case '#': case ':': case '?': s = 8; t++; break;
    case '@': t++; if (*t == '?') t++; else if (*t == '"') { t++; while (*t && *t != '"') t++; if (*t) t++; } break;
    case '^': t++; { uint32_t a, b; t = type_info(t, &a, &b, 0, 0); } break;
    case '{': { t = struct_info(t + 1, '}', size, align, f, base, 0); return skip_num(t); }
    case '(': { t = struct_info(t + 1, ')', size, align, 0, base, 1); add_field(f, base, 'u', *size); return skip_num(t); }
    case '[': {
        t++; uint32_t n = 0; while (*t >= '0' && *t <= '9') n = n * 10 + (uint32_t)(*t++ - '0');
        uint32_t es, ea; fields ef = {0};
        t = type_info(t, &es, &ea, &ef, 0);
        for (uint32_t i = 0; i < n && f; i++) for (int j = 0; j < ef.n; j++) add_field(f, base + i * es + ef.off[j], ef.kind[j], ef.len[j]);
        if (*t == ']') t++;
        *size = es * n; *align = ea; return skip_num(t);
    }
    case 'b': t++; t = skip_num(t); s = 4; break; /* bitfield: approximate */
    case 'v': s = 0; t++; break;
    default: if (*t) t++; break;
    }
    *size = s; *align = s ? (s > 8 ? 16 : s) : 1;
    if (s) add_field(f, base, k, s);
    return skip_num(t);
}
const char *NSGetSizeAndAlignment(const char *t, NSUInteger *size, NSUInteger *align) {
    uint32_t s = 0, a = 1;
    const char *e = type_info(t, &s, &a, 0, 0);
    if (size) *size = s;
    if (align) *align = a;
    return e;
}
#if defined(__arm64__)
/* homogeneous floating-point aggregate (arm64): 1-4 fields, all 'f' or all 'd' */
static int hfa(fields *f, uint32_t size) {
    if (f->n < 1 || f->n > 4) return 0;
    for (int i = 0; i < f->n; i++) if (f->kind[i] != f->kind[0] || (f->kind[i] != 'f' && f->kind[i] != 'd')) return 0;
    return f->n * f->len[0] == (int)size;
}
#endif
typedef struct { int ngpr, nfpr; uint32_t stack; } alloc_state;
static void place(argloc *a, alloc_state *st, int is_ret) {
    fields f = {0}; uint32_t size, align;
    type_info(a->type, &size, &align, &f, 0);
    a->size = size; a->align = align; a->n = 0;
    if (!size) return;
    int scalar = f.n == 1 && f.off[0] == 0 && f.len[0] == size && f.kind[0] != 'u' && a->type[strspn(a->type, "rnNoORVA+")] != '{';
#if defined(__x86_64__)
    if (scalar && f.kind[0] == 'D') goto memory;
    if (size <= 16 && !(f.n && f.kind[0] == 'u' && size > 8)) {
        /* each eightbyte is SSE if all its fields are floating point */
        int cls[2] = {0, 0}, ne = (int)((size + 7) / 8), need_g = 0, need_f = 0;
        for (int e = 0; e < ne; e++) {
            int sse = 1;
            for (int i = 0; i < f.n; i++) if (f.off[i] / 8 == e && f.kind[i] != 'f' && f.kind[i] != 'd') sse = 0;
            cls[e] = sse; if (sse) need_f++; else need_g++;
        }
        int gl = is_ret ? 2 : NGPR, fl = is_ret ? 2 : 8;
        if (st->ngpr + need_g <= gl && st->nfpr + need_f <= fl) {
            for (int e = 0; e < ne; e++) {
                uint16_t len = (uint16_t)((uint32_t)(e + 1) * 8 > size ? size - (uint32_t)e * 8 : 8);
                a->p[a->n++] = cls[e] ? (piece){P_FPR, (uint8_t)st->nfpr++, len, 0, (uint16_t)(e * 8)} : (piece){P_GPR, (uint8_t)st->ngpr++, len, 0, (uint16_t)(e * 8)};
            }
            return;
        }
    }
memory:
    if (is_ret) { a->p[a->n++] = (piece){P_REF, 0, (uint16_t)size, 0, 0}; return; } /* sret: the caller adds the hidden argument */
    { uint32_t al = align > 8 ? 16 : 8; st->stack = (st->stack + al - 1) / al * al;
      a->p[a->n++] = (piece){P_STACK, 0, (uint16_t)size, (uint16_t)st->stack, 0}; st->stack += (size + 7) / 8 * 8; }
#else
    if (hfa(&f, size)) {
        if (is_ret || st->nfpr + f.n <= 8) { for (int i = 0; i < f.n; i++) a->p[a->n++] = (piece){P_FPR, (uint8_t)st->nfpr++, f.len[i], 0, f.off[i]}; return; }
        st->nfpr = 8;
        st->stack = (st->stack + align - 1) / align * align;
        a->p[a->n++] = (piece){P_STACK, 0, (uint16_t)size, (uint16_t)st->stack, 0}; st->stack += size;
        return;
    }
    if (size > 16) {
        if (is_ret) { a->p[a->n++] = (piece){P_REF, 8, (uint16_t)size, 0, 0}; return; } /* x8 */
        if (st->ngpr < 8) { a->p[a->n++] = (piece){P_REF, (uint8_t)st->ngpr++, (uint16_t)size, 0, 0}; return; }
        st->stack = (st->stack + 7) / 8 * 8; a->p[a->n++] = (piece){P_REF, 0xff, (uint16_t)size, (uint16_t)st->stack, 0}; st->stack += 8;
        return;
    }
    int ng = (int)((size + 7) / 8);
    if (is_ret || st->ngpr + ng <= 8) {
        for (int i = 0; i < ng; i++) a->p[a->n++] = (piece){P_GPR, (uint8_t)st->ngpr++, (uint16_t)(size - (uint32_t)i * 8 < 8 ? size - (uint32_t)i * 8 : 8), 0, (uint16_t)(i * 8)};
        return;
    }
    st->ngpr = 8;
    { uint32_t al = scalar ? align : 8; st->stack = (st->stack + al - 1) / al * al; } /* Darwin packs scalars by their size */
    a->p[a->n++] = (piece){P_STACK, 0, (uint16_t)size, (uint16_t)st->stack, 0};
    st->stack += scalar ? size : (size + 7) / 8 * 8;
#endif
}

/* ======================================================================= NSMethodSignature */
@implementation NSMethodSignature {
@public
    char *_types; NSUInteger _nargs; argloc *_args; argloc _ret; uint32_t _stack; BOOL _sret;
}
+ (NSMethodSignature *)signatureWithObjCTypes:(const char *)types {
    if (!types || !*types) return nil;
    NSMethodSignature *m = [[[self alloc] init] autorelease];
    m->_types = strdup(types);
    /* split into return type + arguments (each type string kept with its offsets stripped) */
    const char *t = m->_types; NSUInteger cap = 8; const char *starts[64]; NSUInteger n = 0;
    while (*t && n < 64) { starts[n++] = t; uint32_t s, a; t = type_info(t, &s, &a, 0, 0); }
    if (!n) return nil;
    m->_nargs = n - 1; (void)cap;
    m->_args = calloc(n, sizeof(argloc));
    m->_ret.type = starts[0];
    alloc_state rs = {0, 0, 0};
    place(&m->_ret, &rs, 1);
    alloc_state st = {0, 0, 0};
#if defined(__x86_64__)
    if (m->_ret.n == 1 && m->_ret.p[0].kind == P_REF) { m->_sret = YES; st.ngpr = 1; }
#endif
    for (NSUInteger i = 0; i < m->_nargs; i++) { m->_args[i].type = starts[i + 1]; place(&m->_args[i], &st, 0); }
    m->_stack = (st.stack + 15) & ~15u;
    return m;
}
- (void)dealloc { free(_types); free(_args); [super dealloc]; }
- (NSUInteger)numberOfArguments { return _nargs; }
static NSString *one_type(const char *t) { uint32_t s, a; const char *e = type_info(t, &s, &a, 0, 0); while (e > t && e[-1] >= '0' && e[-1] <= '9') e--; return [[[NSString alloc] initWithBytes:t length:(NSUInteger)(e - t) encoding:NSUTF8StringEncoding] autorelease]; }
- (const char *)getArgumentTypeAtIndex:(NSUInteger)i { return i < _nargs ? [one_type(_args[i].type) UTF8String] : NULL; }
- (const char *)methodReturnType { return [one_type(_ret.type) UTF8String]; }
- (NSUInteger)methodReturnLength { return _ret.size; }
- (NSUInteger)frameLength { return 224 + _stack; }
- (BOOL)isOneway { return _types[0] == 'V'; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSMethodSignature class]] && !strcmp(_types, ((NSMethodSignature *)o)->_types); }
- (NSUInteger)hash { return [[NSString stringWithUTF8String:_types] hash]; }
- (NSString *)description { return [NSString stringWithFormat:@"<NSMethodSignature: %s>", _types]; }
- (const char *)_typeString { return _types; }
@end

/* ======================================================================= NSInvocation */
@implementation NSInvocation {
    NSMethodSignature *_sig; void **_vals; void *_ret; BOOL _retained;
}
+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)sig {
    if (!sig) [NSException raise:NSInvalidArgumentException format:@"+[NSInvocation invocationWithMethodSignature:]: method signature argument cannot be nil"];
    NSInvocation *i = [[[self alloc] init] autorelease];
    i->_sig = [sig retain];
    i->_vals = calloc(sig->_nargs ? sig->_nargs : 1, sizeof(void *));
    for (NSUInteger k = 0; k < sig->_nargs; k++) i->_vals[k] = calloc(1, sig->_args[k].size ? (sig->_args[k].size + 15) & ~15u : 16);
    i->_ret = calloc(1, sig->_ret.size > 16 ? (sig->_ret.size + 15) & ~15u : 16);
    return i;
}
- (void)dealloc {
    for (NSUInteger k = 0; k < _sig->_nargs; k++) {
        if (_retained) { const char *t = skip_qual(_sig->_args[k].type); id o = *(id *)_vals[k];
            if (*t == '@') { if (t[1] == '?') _Block_release(o); else [o release]; }
            else if (*t == '*') free(*(char **)_vals[k]); }
        free(_vals[k]);
    }
    free(_vals); free(_ret); [_sig release]; [super dealloc];
}
- (NSMethodSignature *)methodSignature { return _sig; }
- (void)retainArguments {
    if (_retained) return;
    _retained = YES;
    for (NSUInteger k = 0; k < _sig->_nargs; k++) {
        const char *t = skip_qual(_sig->_args[k].type);
        if (*t == '@') { id o = *(id *)_vals[k]; *(id *)_vals[k] = t[1] == '?' ? (id)_Block_copy(o) : [o retain]; }
        else if (*t == '*' && *(char **)_vals[k]) *(char **)_vals[k] = strdup(*(char **)_vals[k]);
    }
}
- (BOOL)argumentsRetained { return _retained; }
- (void)getArgument:(void *)buf atIndex:(NSInteger)i {
    if (i < 0 || (NSUInteger)i >= _sig->_nargs) [NSException raise:NSRangeException format:@"-[NSInvocation getArgument:atIndex:]: index (%ld) out of bounds", (long)i];
    memcpy(buf, _vals[i], _sig->_args[i].size);
}
- (void)setArgument:(void *)buf atIndex:(NSInteger)i {
    if (i < 0 || (NSUInteger)i >= _sig->_nargs) [NSException raise:NSRangeException format:@"-[NSInvocation setArgument:atIndex:]: index (%ld) out of bounds", (long)i];
    const char *t = skip_qual(_sig->_args[i].type);
    if (_retained && *t == '@') { id n = *(id *)buf, o = *(id *)_vals[i]; n = t[1] == '?' ? (id)_Block_copy(n) : [n retain]; if (t[1] == '?') _Block_release(o); else [o release]; *(id *)_vals[i] = n; return; }
    memcpy(_vals[i], buf, _sig->_args[i].size);
}
- (id)target { return _sig->_nargs ? *(id *)_vals[0] : nil; }
- (void)setTarget:(id)t { if (_sig->_nargs) [self setArgument:&t atIndex:0]; }
- (SEL)selector { return _sig->_nargs > 1 ? *(SEL *)_vals[1] : NULL; }
- (void)setSelector:(SEL)s { if (_sig->_nargs > 1) [self setArgument:&s atIndex:1]; }
- (void)getReturnValue:(void *)buf { if (_sig->_ret.size) memcpy(buf, _ret, _sig->_ret.size); }
- (void)setReturnValue:(void *)buf { if (_sig->_ret.size) memcpy(_ret, buf, _sig->_ret.size); }
static uint8_t *loc_of(uint8_t *frame, uint8_t *stack, piece *p) {
    switch (p->kind) {
    case P_GPR: return frame + p->reg * 8;
    case P_FPR: return frame + FPR_OFF + p->reg * 16;
    case P_STACK: return stack + p->off;
    default: return p->reg == 0xff ? stack + p->off : frame + p->reg * 8; /* P_REF: the pointer's register (x8 = 64) */
    }
}
/* frame -> argument buffers (a forwarded call) */
- (void)_mwLoadFrame:(uint8_t *)frame {
    for (NSUInteger k = 0; k < _sig->_nargs; k++) {
        argloc *a = &_sig->_args[k];
        for (uint32_t j = 0; j < a->n; j++) {
            piece *p = &a->p[j];
            uint8_t *src = loc_of(frame, frame + STACK_OFF, p);
            if (p->kind == P_REF) memcpy(_vals[k], *(void **)src, p->len); else memcpy((uint8_t *)_vals[k] + p->src, src, p->len);
        }
    }
}
/* return buffer -> frame (after -forwardInvocation:) */
- (void)_mwStoreReturn:(uint8_t *)frame {
    argloc *r = &_sig->_ret;
    for (uint32_t j = 0; j < r->n; j++) {
        piece *p = &r->p[j];
        if (p->kind == P_REF) { void *dst = *(void **)(frame + (NGPR == 8 ? 64 : 0)); if (dst) memcpy(dst, _ret, p->len); }
        else memcpy(loc_of(frame, 0, p), (uint8_t *)_ret + p->src, p->len);
    }
}
- (void)invokeWithTarget:(id)target {
    [self setTarget:target];
    if (!target) { memset(_ret, 0, _sig->_ret.size > 16 ? _sig->_ret.size : 16); return; }
    SEL sel = [self selector];
    IMP imp = class_getMethodImplementation(object_getClass(target), sel);
    uint64_t frame[28] __attribute__((aligned(16))) = {0};
    uint8_t *stack = _sig->_stack ? __builtin_alloca(_sig->_stack) : NULL;
    if (stack) memset(stack, 0, _sig->_stack);
    uint8_t *fr = (uint8_t *)frame;
    for (NSUInteger k = 0; k < _sig->_nargs; k++) {
        argloc *a = &_sig->_args[k];
        for (uint32_t j = 0; j < a->n; j++) {
            piece *p = &a->p[j];
            uint8_t *dst = loc_of(fr, stack, p);
            if (p->kind == P_REF) *(void **)dst = _vals[k]; else memcpy(dst, (uint8_t *)_vals[k] + p->src, p->len);
        }
    }
    argloc *r = &_sig->_ret;
    if (r->n == 1 && r->p[0].kind == P_REF) {
#if defined(__x86_64__)
        frame[0] = (uint64_t)(uintptr_t)_ret;   /* hidden first argument; self moved to rsi by the signature */
#else
        frame[8] = (uint64_t)(uintptr_t)_ret;   /* x8 */
#endif
    }
    _scion_objc_invoke(fr, imp, stack, _sig->_stack);
    for (uint32_t j = 0; j < r->n; j++) { piece *p = &r->p[j]; if (p->kind != P_REF) memcpy((uint8_t *)_ret + p->src, loc_of(fr, 0, p), p->len); }
}
- (void)invoke { [self invokeWithTarget:[self target]]; }
- (void)invokeUsingIMP:(IMP)imp { [self invoke]; }
@end

static int forward_hook(id self, SEL sel, void *frame) {
    if (sel == @selector(methodSignatureForSelector:) || sel == @selector(forwardInvocation:)) return 0;
    if (!class_respondsToSelector(object_getClass(self), @selector(methodSignatureForSelector:))) return 0; /* not an NSObject (a class whose superclass is missing) */
    NSMethodSignature *sig = [self methodSignatureForSelector:sel];
    if (!sig) return 0;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
#if defined(__x86_64__)
    if (sig->_sret) return 0; /* ponytail: forwarded struct returns (objc_msgSend_stret) are not captured */
#endif
    [inv _mwLoadFrame:frame];
    [self forwardInvocation:inv];
    [inv _mwStoreReturn:frame];
    return 1;
}
__attribute__((constructor)) static void install_forward_hook(void) { _scion_forward_invocation_hook = forward_hook; }

@implementation NSObject (MWForwarding)
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { Method m = class_getInstanceMethod(object_getClass(self), s); return m ? [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)] : nil; }
+ (NSMethodSignature *)methodSignatureForSelector:(SEL)s { Method m = class_getClassMethod(self, s); return m ? [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)] : nil; }
+ (NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)s { Method m = class_getInstanceMethod(self, s); return m ? [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)] : nil; }
- (void)forwardInvocation:(NSInvocation *)i { [self doesNotRecognizeSelector:[i selector]]; }
/* NSComparisonMethods (scripting) */
- (BOOL)isEqualTo:(id)o { return [self isEqual:o]; }
- (BOOL)isNotEqualTo:(id)o { return ![self isEqual:o]; }
- (BOOL)isLessThan:(id)o { return [self respondsToSelector:@selector(compare:)] && (NSComparisonResult)(intptr_t)[self performSelector:@selector(compare:) withObject:o] == NSOrderedAscending; }
- (BOOL)isLessThanOrEqualTo:(id)o { return [self isLessThan:o] || [self isEqual:o]; }
- (BOOL)isGreaterThan:(id)o { return [self respondsToSelector:@selector(compare:)] && (NSComparisonResult)(intptr_t)[self performSelector:@selector(compare:) withObject:o] == NSOrderedDescending; }
- (BOOL)isGreaterThanOrEqualTo:(id)o { return [self isGreaterThan:o] || [self isEqual:o]; }
- (BOOL)doesContain:(id)o { return [self respondsToSelector:@selector(containsObject:)] && [(id)self containsObject:o]; }
- (id)performSelector:(SEL)s withObject:(id)a withObject:(id)b { return ((id (*)(id, SEL, id, id))objc_msgSend)(self, s, a, b); }
@end

/* ======================================================================= NSProxy */
id _scion_objc_rootRetain(id); BOOL _scion_objc_rootRelease(id); uintptr_t _scion_objc_rootRetainCount(id); id _scion_objc_rootAutorelease(id);
id _objc_rootAllocWithZone(Class, void *);
@implementation NSProxy
+ (id)alloc { return [self allocWithZone:NULL]; }
+ (id)allocWithZone:(NSZone *)z { return _objc_rootAllocWithZone(self, 0); }
+ (Class)class { return self; }
+ (BOOL)respondsToSelector:(SEL)s { return class_respondsToSelector(object_getClass(self), s); }
+ (void)initialize {}
+ (void)load {}
- (void)dealloc { object_dispose(self); }
- (void)finalize {}
- (id)retain { return _scion_objc_rootRetain(self); }
- (oneway void)release { if (_scion_objc_rootRelease(self)) [self dealloc]; }
- (id)autorelease { return _scion_objc_rootAutorelease(self); }
- (NSUInteger)retainCount { return _scion_objc_rootRetainCount(self); }
- (id)self { return self; }
- (Class)class { return object_getClass(self); }
- (Class)superclass { return class_getSuperclass(object_getClass(self)); }
- (BOOL)isProxy { return YES; }
- (NSZone *)zone { return 0; }
- (NSUInteger)hash { return (NSUInteger)self; }
- (BOOL)isEqual:(id)o { return self == o; }
- (BOOL)isKindOfClass:(Class)c { for (Class k = object_getClass(self); k; k = class_getSuperclass(k)) if (k == c) return YES; return NO; }
- (BOOL)respondsToSelector:(SEL)s { return class_respondsToSelector(object_getClass(self), s); }
- (BOOL)conformsToProtocol:(Protocol *)p { return class_conformsToProtocol(object_getClass(self), p); }
- (BOOL)allowsWeakReference { return YES; }
- (BOOL)retainWeakReference { return YES; }
- (NSString *)description { return [NSString stringWithFormat:@"<%s: %p>", class_getName(object_getClass(self)), self]; }
- (NSString *)debugDescription { return [self description]; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { [NSException raise:NSInvalidArgumentException format:@"-[NSProxy methodSignatureForSelector:] called!"]; return nil; }
- (void)forwardInvocation:(NSInvocation *)i { [NSException raise:NSInvalidArgumentException format:@"-[NSProxy forwardInvocation:] called!"]; }
- (void)doesNotRecognizeSelector:(SEL)s { [NSException raise:NSInvalidArgumentException format:@"-[%s %s]: unrecognized selector sent to instance %p", class_getName(object_getClass(self)), sel_getName(s), self]; }
- (id)performSelector:(SEL)s { return ((id (*)(id, SEL))objc_msgSend)(self, s); }
- (id)performSelector:(SEL)s withObject:(id)a { return ((id (*)(id, SEL, id))objc_msgSend)(self, s, a); }
@end

/* ======================================================================= NSUndoManager */
NSString *const NSUndoManagerCheckpointNotification = @"NSUndoManagerCheckpointNotification",
    *const NSUndoManagerWillUndoChangeNotification = @"NSUndoManagerWillUndoChangeNotification",
    *const NSUndoManagerWillRedoChangeNotification = @"NSUndoManagerWillRedoChangeNotification",
    *const NSUndoManagerDidUndoChangeNotification = @"NSUndoManagerDidUndoChangeNotification",
    *const NSUndoManagerDidRedoChangeNotification = @"NSUndoManagerDidRedoChangeNotification",
    *const NSUndoManagerDidOpenUndoGroupNotification = @"NSUndoManagerDidOpenUndoGroupNotification",
    *const NSUndoManagerWillCloseUndoGroupNotification = @"NSUndoManagerWillCloseUndoGroupNotification",
    *const NSUndoManagerDidCloseUndoGroupNotification = @"NSUndoManagerDidCloseUndoGroupNotification",
    *const NSUndoManagerGroupIsDiscardableKey = @"NSUndoManagerGroupIsDiscardableKey";
@interface _MWUndoGroup : NSObject { @public NSMutableArray *actions; NSString *name; _MWUndoGroup *parent; } @end
@implementation _MWUndoGroup
- (instancetype)init { actions = [[NSMutableArray alloc] init]; return self; }
- (void)dealloc { [actions release]; [name release]; [super dealloc]; }
@end
/* one undo action: an invocation, a block, or target + selector + object */
@interface _MWUndoAction : NSObject { @public id target; SEL sel; id obj; NSInvocation *inv; void (^block)(id); } @end
@implementation _MWUndoAction
- (void)dealloc { [obj release]; [inv release]; if (block) _Block_release(block); [super dealloc]; }
- (void)perform {
    if (inv) [inv invoke];
    else if (block) block(target);
    else ((void (*)(id, SEL, id))objc_msgSend)(target, sel, obj);
}
@end
@interface _MWUndoProxy : NSProxy { @public NSUndoManager *mgr; id target; } @end
@interface NSUndoManager () - (void)_mwAdd:(_MWUndoAction *)a; @end
@implementation _MWUndoProxy
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { return [target methodSignatureForSelector:s]; }
- (void)forwardInvocation:(NSInvocation *)i {
    _MWUndoAction *a = [[[_MWUndoAction alloc] init] autorelease];
    [i setTarget:target]; [i retainArguments];
    a->target = target; a->inv = [i retain];
    [mgr _mwAdd:a];
}
@end
@implementation NSUndoManager {
    NSMutableArray *_undo, *_redo; _MWUndoGroup *_open; NSInteger _disabled; BOOL _undoing, _redoing, _groupsByEvent, _autoGroup;
    NSUInteger _levels; NSString *_pendingName; _MWUndoProxy *_proxy; NSArray *_modes;
}
- (instancetype)init {
    _undo = [[NSMutableArray alloc] init]; _redo = [[NSMutableArray alloc] init]; _groupsByEvent = YES;
    _proxy = [_MWUndoProxy alloc]; _proxy->mgr = self;
    return self;
}
- (void)dealloc { [_undo release]; [_redo release]; [_open release]; [_pendingName release]; [_proxy release]; [_modes release]; [super dealloc]; }
- (void)_post:(NSString *)n { [[NSNotificationCenter defaultCenter] postNotificationName:n object:self]; }
- (void)beginUndoGrouping {
    _MWUndoGroup *g = [[_MWUndoGroup alloc] init];
    g->parent = _open; _open = g;
    [self _post:NSUndoManagerDidOpenUndoGroupNotification];
}
- (void)endUndoGrouping {
    if (!_open) [NSException raise:NSInternalInconsistencyException format:@"endUndoGrouping called with no matching begin"];
    [self _post:NSUndoManagerWillCloseUndoGroupNotification];
    _MWUndoGroup *g = _open; _open = g->parent; g->parent = nil;
    if (_open) { if ([g->actions count]) [_open->actions addObject:g]; }
    else if ([g->actions count]) {
        NSMutableArray *stack = _undoing ? _redo : _undo;
        [stack addObject:g];
        if (_levels && [stack count] > _levels) [stack removeObjectAtIndex:0];
    }
    [g release];
    [self _post:NSUndoManagerDidCloseUndoGroupNotification];
}
- (NSInteger)groupingLevel { NSInteger n = 0; for (_MWUndoGroup *g = _open; g; g = g->parent) n++; return n; }
- (void)_mwCloseAutoGroup { if (_autoGroup) { _autoGroup = NO; while (_open) [self endUndoGrouping]; } }
- (void)_mwAdd:(_MWUndoAction *)a {
    if (_disabled > 0) return;
    if (!_open) {
        if (!_groupsByEvent) [NSException raise:NSInternalInconsistencyException format:@"undo registration with no open group"];
        [self beginUndoGrouping]; _autoGroup = YES;
        /* the group of an event closes when the run loop comes back */
        [self performSelector:@selector(_mwCloseAutoGroup) withObject:nil afterDelay:0];
    }
    if (_pendingName && !_open->name) { _open->name = [_pendingName copy]; }
    [_open->actions addObject:a];
    if (!_undoing && !_redoing) [_redo removeAllObjects];
}
- (void)registerUndoWithTarget:(id)t selector:(SEL)s object:(id)o {
    _MWUndoAction *a = [[[_MWUndoAction alloc] init] autorelease];
    a->target = t; a->sel = s; a->obj = [o retain];
    [self _mwAdd:a];
}
- (void)registerUndoWithTarget:(id)t handler:(void (^)(id))h {
    _MWUndoAction *a = [[[_MWUndoAction alloc] init] autorelease];
    a->target = t; a->block = _Block_copy(h);
    [self _mwAdd:a];
}
- (id)prepareWithInvocationTarget:(id)t { _proxy->target = t; return _proxy; }
static void run_group(_MWUndoGroup *g) {
    for (id a in [g->actions reverseObjectEnumerator]) { if ([a isKindOfClass:[_MWUndoGroup class]]) run_group(a); else [a perform]; }
}
- (void)undo {
    [self _mwCloseAutoGroup];
    if (_open) [NSException raise:NSInternalInconsistencyException format:@"undo was called with too many nested undo groups"];
    [self undoNestedGroup];
}
- (void)undoNestedGroup {
    _MWUndoGroup *g = [[_undo lastObject] retain]; if (!g) return;
    [self _post:NSUndoManagerCheckpointNotification];
    [self _post:NSUndoManagerWillUndoChangeNotification];
    [_undo removeLastObject];
    _undoing = YES;
    [self beginUndoGrouping]; [self setActionName:g->name ?: @""];
    _open->name = [g->name copy];
    run_group(g);
    [self endUndoGrouping];
    _undoing = NO;
    [g release];
    [self _post:NSUndoManagerDidUndoChangeNotification];
}
- (void)redo {
    [self _mwCloseAutoGroup];
    _MWUndoGroup *g = [[_redo lastObject] retain]; if (!g) return;
    [self _post:NSUndoManagerCheckpointNotification];
    [self _post:NSUndoManagerWillRedoChangeNotification];
    [_redo removeLastObject];
    _redoing = YES;
    [self beginUndoGrouping];
    _open->name = [g->name copy];
    run_group(g);
    [self endUndoGrouping];
    _redoing = NO;
    [g release];
    [self _post:NSUndoManagerDidRedoChangeNotification];
}
- (BOOL)canUndo { return [_undo count] > 0 || (_open && [_open->actions count] && _autoGroup); }
- (BOOL)canRedo { return [_redo count] > 0; }
- (BOOL)isUndoing { return _undoing; }
- (BOOL)isRedoing { return _redoing; }
- (void)disableUndoRegistration { _disabled++; }
- (void)enableUndoRegistration { _disabled--; }
- (BOOL)isUndoRegistrationEnabled { return _disabled <= 0; }
- (BOOL)groupsByEvent { return _groupsByEvent; }
- (void)setGroupsByEvent:(BOOL)b { _groupsByEvent = b; }
- (NSUInteger)levelsOfUndo { return _levels; }
- (void)setLevelsOfUndo:(NSUInteger)n { _levels = n; }
- (NSArray *)runLoopModes { return _modes ?: @[NSDefaultRunLoopMode]; }
- (void)setRunLoopModes:(NSArray *)m { [_modes release]; _modes = [m copy]; }
- (void)removeAllActions { [_undo removeAllObjects]; [_redo removeAllObjects]; [_open release]; _open = nil; _autoGroup = NO; }
static void strip_target(NSMutableArray *stack, id t) {
    for (_MWUndoGroup *g in stack)
        for (NSInteger i = (NSInteger)[g->actions count] - 1; i >= 0; i--) { _MWUndoAction *a = g->actions[(NSUInteger)i]; if ([a isKindOfClass:[_MWUndoAction class]] && a->target == t) [g->actions removeObjectAtIndex:(NSUInteger)i]; }
}
- (void)removeAllActionsWithTarget:(id)t { strip_target(_undo, t); strip_target(_redo, t); }
- (void)setActionName:(NSString *)n { [_pendingName release]; _pendingName = [n copy]; if (_open) { [_open->name release]; _open->name = [n copy]; } }
- (NSString *)undoActionName { _MWUndoGroup *g = _open && _autoGroup ? _open : [_undo lastObject]; return g->name ?: @""; }
- (NSString *)redoActionName { return ((_MWUndoGroup *)[_redo lastObject])->name ?: @""; }
- (NSString *)undoMenuTitleForUndoActionName:(NSString *)n { return [n length] ? [@"Undo " stringByAppendingString:n] : @"Undo"; }
- (NSString *)redoMenuTitleForUndoActionName:(NSString *)n { return [n length] ? [@"Redo " stringByAppendingString:n] : @"Redo"; }
- (NSString *)undoMenuItemTitle { return [self undoMenuTitleForUndoActionName:[self undoActionName]]; }
- (NSString *)redoMenuItemTitle { return [self redoMenuTitleForUndoActionName:[self redoActionName]]; }
- (void)setActionIsDiscardable:(BOOL)d {}
- (BOOL)undoActionIsDiscardable { return NO; }
- (BOOL)redoActionIsDiscardable { return NO; }
@end

/* ======================================================================= NSSortDescriptor */
@implementation NSSortDescriptor { NSString *_key; BOOL _asc; SEL _sel; NSComparator _cmp; }
+ (instancetype)sortDescriptorWithKey:(NSString *)k ascending:(BOOL)a { return [[[self alloc] initWithKey:k ascending:a] autorelease]; }
+ (instancetype)sortDescriptorWithKey:(NSString *)k ascending:(BOOL)a selector:(SEL)s { return [[[self alloc] initWithKey:k ascending:a selector:s] autorelease]; }
+ (instancetype)sortDescriptorWithKey:(NSString *)k ascending:(BOOL)a comparator:(NSComparator)c { return [[[self alloc] initWithKey:k ascending:a comparator:c] autorelease]; }
- (instancetype)initWithKey:(NSString *)k ascending:(BOOL)a { return [self initWithKey:k ascending:a selector:@selector(compare:)]; }
- (instancetype)initWithKey:(NSString *)k ascending:(BOOL)a selector:(SEL)s { _key = [k copy]; _asc = a; _sel = s ? s : @selector(compare:); return self; }
- (instancetype)initWithKey:(NSString *)k ascending:(BOOL)a comparator:(NSComparator)c { _key = [k copy]; _asc = a; _cmp = [c copy]; return self; }
- (void)dealloc { [_key release]; [_cmp release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)key { return _key; }
- (BOOL)ascending { return _asc; }
- (SEL)selector { return _sel; }
- (NSComparator)comparator { return _cmp; }
- (id)reversedSortDescriptor { return _cmp ? [[[NSSortDescriptor alloc] initWithKey:_key ascending:!_asc comparator:_cmp] autorelease] : [[[NSSortDescriptor alloc] initWithKey:_key ascending:!_asc selector:_sel] autorelease]; }
- (NSComparisonResult)compareObject:(id)a toObject:(id)b {
    id x = _key ? [a valueForKeyPath:_key] : a, y = _key ? [b valueForKeyPath:_key] : b;
    NSComparisonResult r;
    if (x == y) r = NSOrderedSame; else if (!x) r = NSOrderedAscending; else if (!y) r = NSOrderedDescending;
    else r = _cmp ? _cmp(x, y) : (NSComparisonResult)(intptr_t)((id (*)(id, SEL, id))objc_msgSend)(x, _sel, y);
    return _asc ? r : (NSComparisonResult)-r;
}
@end
static NSComparisonResult by_descriptors(id a, id b, NSArray *ds) {
    for (NSSortDescriptor *d in ds) { NSComparisonResult r = [d compareObject:a toObject:b]; if (r != NSOrderedSame) return r; }
    return NSOrderedSame;
}
@implementation NSArray (MWSortDescriptors)
- (NSArray *)sortedArrayUsingDescriptors:(NSArray *)ds { return [self sortedArrayUsingComparator:^NSComparisonResult(id a, id b) { return by_descriptors(a, b, ds); }]; }
@end
@implementation NSMutableArray (MWSortDescriptors)
- (void)sortUsingDescriptors:(NSArray *)ds { [self sortUsingComparator:^NSComparisonResult(id a, id b) { return by_descriptors(a, b, ds); }]; }
@end

/* ======================================================================= NSValueTransformer */
NSString *const NSNegateBooleanTransformerName = @"NSNegateBoolean", *const NSIsNilTransformerName = @"NSIsNil",
    *const NSIsNotNilTransformerName = @"NSIsNotNil", *const NSUnarchiveFromDataTransformerName = @"NSUnarchiveFromData",
    *const NSKeyedUnarchiveFromDataTransformerName = @"NSKeyedUnarchiveFromData", *const NSSecureUnarchiveFromDataTransformerName = @"NSSecureUnarchiveFromData";
@interface _MWBuiltinTransformer : NSValueTransformer { @public int kind; } @end
@implementation NSValueTransformer
static NSMutableDictionary *transformers;
+ (void)setValueTransformer:(NSValueTransformer *)t forName:(NSString *)n {
    @synchronized ([NSValueTransformer class]) { if (!transformers) transformers = [[NSMutableDictionary alloc] init]; if (t) transformers[n] = t; else [transformers removeObjectForKey:n]; }
}
+ (NSValueTransformer *)valueTransformerForName:(NSString *)n {
    NSValueTransformer *t; @synchronized ([NSValueTransformer class]) { t = transformers[n]; }
    if (t) return t;
    int k = [n isEqualToString:NSNegateBooleanTransformerName] ? 1 : [n isEqualToString:NSIsNilTransformerName] ? 2 : [n isEqualToString:NSIsNotNilTransformerName] ? 3 : 0;
    if (k) { _MWBuiltinTransformer *b = [[[_MWBuiltinTransformer alloc] init] autorelease]; b->kind = k; [self setValueTransformer:b forName:n]; return b; }
    Class c = NSClassFromString(n);   /* a transformer class named directly */
    if (c && [c isSubclassOfClass:[NSValueTransformer class]]) { t = [[[c alloc] init] autorelease]; [self setValueTransformer:t forName:n]; return t; }
    return nil;
}
+ (NSArray *)valueTransformerNames { @synchronized ([NSValueTransformer class]) { return [transformers allKeys] ?: @[]; } }
+ (Class)transformedValueClass { return [NSObject class]; }
+ (BOOL)allowsReverseTransformation { return NO; }
- (id)transformedValue:(id)v { return v; }
- (id)reverseTransformedValue:(id)v { return [self transformedValue:v]; }
@end
@implementation _MWBuiltinTransformer
+ (BOOL)allowsReverseTransformation { return YES; }
- (id)transformedValue:(id)v {
    switch (kind) {
    case 1: return @(![v boolValue]);
    case 2: return @(v == nil);
    default: return @(v != nil);
    }
}
@end

/* ======================================================================= NSByteCountFormatter */
@implementation NSByteCountFormatter
+ (NSString *)stringFromByteCount:(long long)n countStyle:(NSByteCountFormatterCountStyle)s {
    NSByteCountFormatter *f = [[[self alloc] init] autorelease]; f.countStyle = s; return [f stringFromByteCount:n];
}
- (instancetype)init { _includesUnit = _includesCount = _allowsNonnumericFormatting = YES; return self; }
- (NSString *)stringFromByteCount:(long long)n {
    double base = _countStyle == NSByteCountFormatterCountStyleMemory || _countStyle == NSByteCountFormatterCountStyleBinary ? 1024 : 1000;
    static NSString *const units[] = {@"bytes", @"KB", @"MB", @"GB", @"TB", @"PB", @"EB"};
    if (n == 0 && _allowsNonnumericFormatting) return _includesUnit ? @"Zero KB" : @"0";
    double v = (double)(n < 0 ? -n : n); int u = 0;
    NSByteCountFormatterUnits allowed = _allowedUnits;
    if (!allowed || allowed == NSByteCountFormatterUseDefault) allowed = NSByteCountFormatterUseAll;
    if (!(allowed & NSByteCountFormatterUseBytes) || v >= base) { while (v >= base && u < 6) { v /= base; u++; } }
    if (u == 0 && !(allowed & NSByteCountFormatterUseBytes)) u = 1, v /= base;
    NSString *num = u == 0 ? [NSString stringWithFormat:@"%lld", n < 0 ? -n : n] : [NSString stringWithFormat:v < 10 ? @"%.1f" : @"%.0f", v];
    if (n < 0) num = [@"-" stringByAppendingString:num];
    NSString *unit = u == 0 ? ((n == 1 || n == -1) ? @"byte" : @"bytes") : units[u];
    if (!_includesUnit) return num;
    if (!_includesCount) return unit;
    NSString *r = [NSString stringWithFormat:@"%@ %@", num, unit];
    if (_includesActualByteCount && u) r = [r stringByAppendingFormat:@" (%lld bytes)", n];
    return r;
}
- (NSString *)stringForObjectValue:(id)o { return [o respondsToSelector:@selector(longLongValue)] ? [self stringFromByteCount:[o longLongValue]] : nil; }
@end

/* ======================================================================= streams (whole contents in memory) */
NSString *const NSStreamFileCurrentOffsetKey = @"NSStreamFileCurrentOffsetKey", *const NSStreamDataWrittenToMemoryStreamKey = @"NSStreamDataWrittenToMemoryStreamKey";
@implementation NSStream
- (void)open {} - (void)close {}
- (id)delegate { return nil; } - (void)setDelegate:(id)d {}
- (id)propertyForKey:(NSString *)k { return nil; } - (BOOL)setProperty:(id)p forKey:(NSString *)k { return NO; }
- (void)scheduleInRunLoop:(NSRunLoop *)r forMode:(NSString *)m {} - (void)removeFromRunLoop:(NSRunLoop *)r forMode:(NSString *)m {}
- (NSStreamStatus)streamStatus { return NSStreamStatusNotOpen; } - (NSError *)streamError { return nil; }
@end
@implementation NSInputStream { NSData *_data; NSString *_path; NSUInteger _pos; NSStreamStatus _status; NSError *_err; }
+ (instancetype)inputStreamWithData:(NSData *)d { return [[[self alloc] initWithData:d] autorelease]; }
+ (instancetype)inputStreamWithFileAtPath:(NSString *)p { return [[[self alloc] initWithFileAtPath:p] autorelease]; }
+ (instancetype)inputStreamWithURL:(NSURL *)u { return [[[self alloc] initWithURL:u] autorelease]; }
- (instancetype)initWithData:(NSData *)d { _data = [d copy]; return self; }
- (instancetype)initWithFileAtPath:(NSString *)p { _path = [p copy]; return self; }
- (instancetype)initWithURL:(NSURL *)u { return [u isFileURL] ? [self initWithFileAtPath:[u path]] : [self initWithData:nil]; }
- (void)dealloc { [_data release]; [_path release]; [_err release]; [super dealloc]; }
- (void)open {   /* ponytail: a file is read whole at open */
    if (_path && !_data) { _data = [[NSData alloc] initWithContentsOfFile:_path]; if (!_data) { _err = [[NSError errorWithDomain:NSPOSIXErrorDomain code:2 userInfo:nil] retain]; _status = NSStreamStatusError; return; } }
    _status = NSStreamStatusOpen;
}
- (void)close { _status = NSStreamStatusClosed; }
- (NSInteger)read:(uint8_t *)buf maxLength:(NSUInteger)n {
    if (_status != NSStreamStatusOpen && _status != NSStreamStatusAtEnd) return -1;
    NSUInteger left = [_data length] - _pos, k = n < left ? n : left;
    memcpy(buf, (const uint8_t *)[_data bytes] + _pos, k); _pos += k;
    if (_pos >= [_data length]) _status = NSStreamStatusAtEnd;
    return (NSInteger)k;
}
- (BOOL)getBuffer:(uint8_t **)b length:(NSUInteger *)n { return NO; }
- (BOOL)hasBytesAvailable { return _status == NSStreamStatusOpen && _pos < [_data length]; }
- (NSStreamStatus)streamStatus { return _status; }
- (NSError *)streamError { return _err; }
- (id)propertyForKey:(NSString *)k { return [k isEqualToString:NSStreamFileCurrentOffsetKey] ? @(_pos) : nil; }
- (BOOL)setProperty:(id)p forKey:(NSString *)k { if ([k isEqualToString:NSStreamFileCurrentOffsetKey]) { _pos = [p unsignedIntegerValue]; return YES; } return NO; }
@end
@implementation NSOutputStream { NSMutableData *_mem; NSString *_path; BOOL _append; NSStreamStatus _status; uint8_t *_buf; NSUInteger _cap, _len; }
+ (instancetype)outputStreamToMemory { return [[[self alloc] initToMemory] autorelease]; }
+ (instancetype)outputStreamToFileAtPath:(NSString *)p append:(BOOL)a { return [[[self alloc] initToFileAtPath:p append:a] autorelease]; }
+ (instancetype)outputStreamWithURL:(NSURL *)u append:(BOOL)a { return [[[self alloc] initWithURL:u append:a] autorelease]; }
- (instancetype)initToMemory { _mem = [[NSMutableData alloc] init]; return self; }
- (instancetype)initToFileAtPath:(NSString *)p append:(BOOL)a { _path = [p copy]; _append = a; _mem = [[NSMutableData alloc] init]; return self; }
- (instancetype)initWithURL:(NSURL *)u append:(BOOL)a { return [self initToFileAtPath:[u path] append:a]; }
- (instancetype)initToBuffer:(uint8_t *)b capacity:(NSUInteger)c { _buf = b; _cap = c; return self; }
- (void)dealloc { [_mem release]; [_path release]; [super dealloc]; }
- (void)open {
    if (_path && _append) { NSData *old = [NSData dataWithContentsOfFile:_path]; if (old) [_mem setData:old]; }
    _status = NSStreamStatusOpen;
}
- (void)close { if (_path && _status == NSStreamStatusOpen) [_mem writeToFile:_path atomically:NO]; _status = NSStreamStatusClosed; } /* ponytail: written at close */
- (NSInteger)write:(const uint8_t *)b maxLength:(NSUInteger)n {
    if (_status != NSStreamStatusOpen) return -1;
    if (_buf) { NSUInteger k = _cap - _len < n ? _cap - _len : n; memcpy(_buf + _len, b, k); _len += k; return (NSInteger)k; }
    [_mem appendBytes:b length:n]; return (NSInteger)n;
}
- (BOOL)hasSpaceAvailable { return _status == NSStreamStatusOpen; }
- (NSStreamStatus)streamStatus { return _status; }
- (id)propertyForKey:(NSString *)k { return [k isEqualToString:NSStreamDataWrittenToMemoryStreamKey] && !_path ? [[_mem copy] autorelease] : nil; }
@end

/* ======================================================================= URL loading: requests, responses, URLSession */
@implementation NSURLRequest { @protected NSURL *_url; NSString *_method; NSMutableDictionary *_headers; NSData *_body; NSTimeInterval _timeout; NSURLRequestCachePolicy _policy; }
+ (instancetype)requestWithURL:(NSURL *)u { return [[[self alloc] initWithURL:u] autorelease]; }
+ (instancetype)requestWithURL:(NSURL *)u cachePolicy:(NSURLRequestCachePolicy)p timeoutInterval:(NSTimeInterval)t { return [[[self alloc] initWithURL:u cachePolicy:p timeoutInterval:t] autorelease]; }
- (instancetype)initWithURL:(NSURL *)u { return [self initWithURL:u cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:60]; }
- (instancetype)initWithURL:(NSURL *)u cachePolicy:(NSURLRequestCachePolicy)p timeoutInterval:(NSTimeInterval)t {
    _url = [u copy]; _method = @"GET"; _headers = [[NSMutableDictionary alloc] init]; _timeout = t; _policy = p; return self;
}
- (void)dealloc { [_url release]; [_method release]; [_headers release]; [_body release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSURLRequest *r = [[NSURLRequest alloc] initWithURL:_url cachePolicy:_policy timeoutInterval:_timeout]; r->_method = [_method copy]; [r->_headers addEntriesFromDictionary:_headers]; r->_body = [_body copy]; return r; }
- (id)mutableCopyWithZone:(NSZone *)z { NSMutableURLRequest *r = [[NSMutableURLRequest alloc] initWithURL:_url cachePolicy:_policy timeoutInterval:_timeout]; [r setHTTPMethod:_method]; [r setAllHTTPHeaderFields:_headers]; [r setHTTPBody:_body]; return r; }
- (NSURL *)URL { return _url; }
- (NSString *)HTTPMethod { return _method; }
- (NSDictionary *)allHTTPHeaderFields { return [[_headers copy] autorelease]; }
- (NSString *)valueForHTTPHeaderField:(NSString *)f { for (NSString *k in _headers) if ([k caseInsensitiveCompare:f] == NSOrderedSame) return _headers[k]; return nil; }
- (NSData *)HTTPBody { return _body; }
- (NSTimeInterval)timeoutInterval { return _timeout; }
- (NSURLRequestCachePolicy)cachePolicy { return _policy; }
@end
@implementation NSMutableURLRequest
- (void)setURL:(NSURL *)u { [_url release]; _url = [u copy]; }
- (void)setHTTPMethod:(NSString *)m { [_method release]; _method = [m copy]; }
- (void)setValue:(NSString *)v forHTTPHeaderField:(NSString *)f { if (v) _headers[f] = v; else [_headers removeObjectForKey:f]; }
- (void)addValue:(NSString *)v forHTTPHeaderField:(NSString *)f { NSString *o = _headers[f]; _headers[f] = o ? [NSString stringWithFormat:@"%@,%@", o, v] : v; }
- (void)setAllHTTPHeaderFields:(NSDictionary *)d { [_headers removeAllObjects]; if (d) [_headers addEntriesFromDictionary:d]; }
- (void)setHTTPBody:(NSData *)b { [_body release]; _body = [b copy]; }
- (void)setTimeoutInterval:(NSTimeInterval)t { _timeout = t; }
- (void)setCachePolicy:(NSURLRequestCachePolicy)p { _policy = p; }
@end
@implementation NSURLSessionConfiguration { NSDictionary *_headers; NSTimeInterval _req, _res; NSURLRequestCachePolicy _policy; NSInteger _conns; BOOL _cell, _wait, _cookies; }
+ (NSURLSessionConfiguration *)defaultSessionConfiguration { return [[[self alloc] init] autorelease]; }
+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration { return [[[self alloc] init] autorelease]; }
- (instancetype)init { _req = 60; _res = 7 * 86400; _conns = 6; _cell = _cookies = YES; return self; }
- (void)dealloc { [_headers release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z {
    NSURLSessionConfiguration *c = [[NSURLSessionConfiguration alloc] init];
    c->_headers = [_headers copy]; c->_req = _req; c->_res = _res; c->_policy = _policy; c->_conns = _conns;
    c->_cell = _cell; c->_wait = _wait; c->_cookies = _cookies;
    return c;
}
- (NSDictionary *)HTTPAdditionalHeaders { return _headers; } - (void)setHTTPAdditionalHeaders:(NSDictionary *)h { [_headers release]; _headers = [h copy]; }
- (NSTimeInterval)timeoutIntervalForRequest { return _req; } - (void)setTimeoutIntervalForRequest:(NSTimeInterval)t { _req = t; }
- (NSTimeInterval)timeoutIntervalForResource { return _res; } - (void)setTimeoutIntervalForResource:(NSTimeInterval)t { _res = t; }
- (NSURLRequestCachePolicy)requestCachePolicy { return _policy; } - (void)setRequestCachePolicy:(NSURLRequestCachePolicy)p { _policy = p; }
- (NSInteger)HTTPMaximumConnectionsPerHost { return _conns; } - (void)setHTTPMaximumConnectionsPerHost:(NSInteger)n { _conns = n; }
- (BOOL)allowsCellularAccess { return _cell; } - (void)setAllowsCellularAccess:(BOOL)b { _cell = b; }
- (BOOL)waitsForConnectivity { return _wait; } - (void)setWaitsForConnectivity:(BOOL)b { _wait = b; }
- (BOOL)HTTPShouldSetCookies { return _cookies; } - (void)setHTTPShouldSetCookies:(BOOL)b { _cookies = b; }
/* the rest of the configuration (cookie storage, caches, proxies, TLS versions) is accepted and has no effect */
- (void)setValue:(id)v forUndefinedKey:(NSString *)k {} - (id)valueForUndefinedKey:(NSString *)k { return nil; }
@end

@implementation NSURLResponse { NSURL *_url; NSString *_mime, *_encoding; long long _length; }
- (instancetype)initWithURL:(NSURL *)u MIMEType:(NSString *)m expectedContentLength:(NSInteger)l textEncodingName:(NSString *)e {
    if ((self = [super init])) { _url = [u copy]; _mime = [m copy]; _length = l; _encoding = [e copy]; }
    return self;
}
- (void)dealloc { [_url release]; [_mime release]; [_encoding release]; [super dealloc]; }
- (NSURL *)URL { return _url; } - (NSString *)MIMEType { return _mime; } - (NSString *)textEncodingName { return _encoding; }
- (long long)expectedContentLength { return _length; }
- (NSString *)suggestedFilename { NSString *n = [_url lastPathComponent]; return [n length] && ![n isEqualToString:@"/"] ? n : @"Unknown"; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
@end
@implementation NSHTTPURLResponse { NSInteger _status; NSDictionary *_headers; }
static NSString *header_in(NSDictionary *h, NSString *f) { for (NSString *k in h) if ([k caseInsensitiveCompare:f] == NSOrderedSame) return h[k]; return nil; }
- (instancetype)initWithURL:(NSURL *)u statusCode:(NSInteger)s HTTPVersion:(NSString *)v headerFields:(NSDictionary *)h {
    /* the MIME type and text encoding come from Content-Type ("text/html; charset=utf-8"), the length from Content-Length */
    NSString *type = header_in(h, @"Content-Type"), *mime = nil, *enc = nil, *len = header_in(h, @"Content-Length");
    if (type) {
        NSArray *parts = [type componentsSeparatedByString:@";"];
        mime = [[parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
        for (NSString *p in parts) {
            NSString *t = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([[t lowercaseString] hasPrefix:@"charset="]) enc = [[t substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
        }
    }
    if ((self = [super initWithURL:u MIMEType:mime expectedContentLength:len ? (NSInteger)[len longLongValue] : -1 textEncodingName:enc])) {
        _status = s; _headers = [h copy] ?: [@{} retain];
    }
    return self;
}
- (void)dealloc { [_headers release]; [super dealloc]; }
- (NSInteger)statusCode { return _status; }
- (NSDictionary *)allHeaderFields { return _headers; }
- (NSString *)valueForHTTPHeaderField:(NSString *)f { return header_in(_headers, f); }
+ (NSString *)localizedStringForStatusCode:(NSInteger)s {
    switch (s) {
    case 200: return @"no error"; case 201: return @"created"; case 204: return @"no content"; case 301: return @"moved permanently";
    case 302: return @"found"; case 304: return @"not modified"; case 400: return @"bad request"; case 401: return @"unauthorized";
    case 403: return @"forbidden"; case 404: return @"not found"; case 500: return @"internal server error"; case 503: return @"service unavailable";
    }
    return s < 200 ? @"informational" : s < 300 ? @"success" : s < 400 ? @"redirected" : s < 500 ? @"client error" : @"server error";
}
@end

/* URLSession: each task runs on a global queue, in one blocking request on the host's HTTP stack (HC_net's NET_HTTP_*,
 * http.cpp), and its results go to the session's delegate queue (a serial queue if the app gives none): the
 * completion handler if the task has one, the delegate's methods if not. Redirects, TLS, proxies and decompression
 * are the host's. ponytail: no cookie storage, URL cache, authentication challenges or background sessions; a
 * download goes to a file in NSTemporaryDirectory(), removed once the handler or delegate returns. */
int64_t _scion_net(int op, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e);
typedef struct dsema *dsem_t; dsem_t dispatch_semaphore_create(long); long dispatch_semaphore_wait(dsem_t, uint64_t);
long dispatch_semaphore_signal(dsem_t); void dispatch_release(void *); dq_t dispatch_get_global_queue(long, unsigned long);
int open(const char *, int, ...); long write(int, const void *, unsigned long); int close(int); int unlink(const char *);

static NSError *url_error(NSInteger code, NSURL *u) {
    NSString *msg;
    switch (code) {
    case NSURLErrorCancelled: msg = @"cancelled"; break;
    case NSURLErrorBadURL: msg = @"bad URL"; break;
    case NSURLErrorTimedOut: msg = @"The request timed out."; break;
    case NSURLErrorUnsupportedURL: msg = @"unsupported URL"; break;
    case NSURLErrorCannotFindHost: msg = @"A server with the specified hostname could not be found."; break;
    case NSURLErrorCannotConnectToHost: msg = @"Could not connect to the server."; break;
    case NSURLErrorNetworkConnectionLost: msg = @"The network connection was lost."; break;
    case NSURLErrorHTTPTooManyRedirects: msg = @"too many HTTP redirects"; break;
    case NSURLErrorSecureConnectionFailed: msg = @"An SSL error has occurred and a secure connection to the server cannot be made."; break;
    case NSURLErrorServerCertificateUntrusted: msg = @"The certificate for this server is invalid."; break;
    case NSURLErrorCannotCreateFile: msg = @"cannot create file"; break;
    default: msg = @"An unknown error occurred.";
    }
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:msg forKey:NSLocalizedDescriptionKey];
    if (u) { info[NSURLErrorFailingURLErrorKey] = u; info[NSURLErrorFailingURLStringErrorKey] = [u absoluteString] ?: @""; }
    return [NSError errorWithDomain:NSURLErrorDomain code:code userInfo:info];
}
static BOOL is_http(NSURL *u) { NSString *s = [[u scheme] lowercaseString]; return [s isEqualToString:@"http"] || [s isEqualToString:@"https"]; }

/* What one request needs from its task and session, and what it gives back */
typedef struct {
    NSURLRequest *request; NSDictionary *extra;  /* the session's HTTPAdditionalHeaders */
    NSData *body; NSTimeInterval timeout;
    volatile int64_t *handle; volatile BOOL *cancelled;   /* (shared with -cancel) */
} HTTPJob;

/* Runs a request in this thread: the response once its headers are in (got_response may cancel it), then the body in
 * pieces to got_data. Returns nil or the error. */
static NSError *http_run(HTTPJob *j, NSHTTPURLResponse **out, BOOL (^got_response)(NSHTTPURLResponse *), BOOL (^got_data)(const void *, size_t)) {
    NSURLRequest *r = j->request;
    NSURL *u = [r URL];
    if (!u) return url_error(NSURLErrorBadURL, nil);
    if (!is_http(u)) return url_error(NSURLErrorUnsupportedURL, u);
    NSMutableString *headers = [NSMutableString string];
    NSDictionary *own = [r allHTTPHeaderFields];
    for (NSString *k in j->extra) if (!header_in(own, k)) [headers appendFormat:@"%@: %@\r\n", k, j->extra[k]];
    for (NSString *k in own) [headers appendFormat:@"%@: %@\r\n", k, own[k]];
    if (!header_in(own, @"Accept") && !header_in(j->extra, @"Accept")) [headers appendString:@"Accept: */*\r\n"];
    if (!header_in(own, @"User-Agent") && !header_in(j->extra, @"User-Agent")) {
        NSString *name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"] ?: [[NSProcessInfo processInfo] processName];
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0";
        [headers appendFormat:@"User-Agent: %@/%@ CFNetwork/1410.0.3 Darwin/22.6.0\r\n", name, version];
    }
    NSData *body = j->body ?: [r HTTPBody];
    char rh[32768], fu[4096];
    struct dhttpreq q = {0};
    q.method = (uint64_t)[[r HTTPMethod] ?: @"GET" UTF8String];
    q.url = (uint64_t)[[u absoluteString] UTF8String];
    q.headers = (uint64_t)[headers UTF8String];
    q.body = (uint64_t)[body bytes]; q.body_len = [body length];
    q.timeout_ms = (int64_t)((j->timeout > 0 ? j->timeout : 60) * 1000);
    q.resp_headers = (uint64_t)rh; q.resp_headers_cap = sizeof rh; q.final_url = (uint64_t)fu; q.final_url_cap = sizeof fu;
    int64_t h = _scion_net(NET_HTTP_NEW, (uint64_t)&q, 0, 0, 0, 0);
    if (h < 0) return url_error(h, u);
    *j->handle = h;
    if (*j->cancelled) _scion_net(NET_HTTP_CANCEL, h, 0, 0, 0, 0);
    NSError *err = nil;
    int64_t rc = _scion_net(NET_HTTP_SEND, h, (uint64_t)&q, 0, 0, 0);
    if (rc < 0) err = url_error(rc, u);
    else {
        NSMutableDictionary *fields = [NSMutableDictionary dictionary];
        for (NSString *line in [@(rh) componentsSeparatedByString:@"\r\n"]) {
            NSRange c = [line rangeOfString:@":"];
            if (!c.length) continue;
            NSString *k = [line substringToIndex:c.location];
            NSString *v = [[line substringFromIndex:c.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *have = header_in(fields, k);
            if (have) {   /* a repeated field: one value, comma-separated, under the first spelling */
                for (NSString *key in [fields allKeys]) if ([key caseInsensitiveCompare:k] == NSOrderedSame) fields[key] = [NSString stringWithFormat:@"%@, %@", have, v];
            } else fields[k] = v;
        }
        NSURL *final = [NSURL URLWithString:@(fu)] ?: u;
        NSHTTPURLResponse *resp = [[[NSHTTPURLResponse alloc] initWithURL:final statusCode:q.status HTTPVersion:@"HTTP/1.1" headerFields:fields] autorelease];
        if (out) *out = resp;
        if (got_response && !got_response(resp)) err = url_error(NSURLErrorCancelled, u);
        else {
            enum { N = 65536 };
            char *buf = malloc(N);
            int64_t n;
            while ((n = _scion_net(NET_HTTP_READ, h, (uint64_t)buf, N, 0, 0)) > 0)
                if (got_data && !got_data(buf, (size_t)n)) { n = NSURLErrorCannotCreateFile; break; }
            free(buf);
            if (n < 0) err = url_error(n, u);
        }
    }
    *j->handle = 0;
    _scion_net(NET_HTTP_CLOSE, h, 0, 0, 0, 0);
    if (*j->cancelled) err = url_error(NSURLErrorCancelled, u);
    return err;
}

/* the whole body of an http(s) URL, in this thread (NSData's and NSString's URL initializers) */
__attribute__((visibility("hidden"))) NSData *_scion_url_data(NSURL *u, NSError **e) {
    NSMutableData *d = [NSMutableData data];
    volatile int64_t handle = 0; volatile BOOL cancelled = NO;
    HTTPJob j = {[NSURLRequest requestWithURL:u], nil, nil, 60, &handle, &cancelled};
    NSHTTPURLResponse *resp = nil;
    NSError *err = http_run(&j, &resp, nil, ^BOOL(const void *p, size_t n) { [d appendBytes:p length:n]; return YES; });
    if (!err && [resp statusCode] >= 400) err = [NSError errorWithDomain:NSCocoaErrorDomain code:256 userInfo:@{NSURLErrorKey: u}];   /* NSFileReadUnknownError */
    if (e) *e = err;
    return err ? nil : d;
}

/* the body as text in encoding e (UTF-8 when 0) */
__attribute__((visibility("hidden"))) NSString *_scion_url_string(NSURL *u, NSStringEncoding e, NSError **err) {
    NSData *d = _scion_url_data(u, err);
    if (!d) return nil;
    NSString *s = [[[NSString alloc] initWithData:d encoding:e ?: NSUTF8StringEncoding] autorelease];
    if (!s && err) *err = [NSError errorWithDomain:NSCocoaErrorDomain code:261 userInfo:@{NSURLErrorKey: u}];   /* NSFileReadInapplicableStringEncodingError */
    return s;
}

enum { TASK_DATA, TASK_DOWNLOAD, TASK_UPLOAD };
@interface NSURLSession () - (void)_taskDone:(NSURLSessionTask *)t; - (NSURLSessionConfiguration *)_config; - (id)_delegate; - (NSOperationQueue *)_queue; @end
@implementation NSURLSessionTask {
@public
    NSURLSession *_session; NSURLRequest *_original, *_current; NSURLResponse *_response; NSError *_error; NSString *_desc;
    id _handler; NSData *_upload; NSInteger _kind, _state; NSUInteger _ident; float _priority;
    int64_t _received, _expected, _sent; volatile int64_t _host; volatile BOOL _cancelled; BOOL _started;
}
- (void)dealloc {
    [_session release]; [_original release]; [_current release]; [_response release]; [_error release]; [_desc release];
    if (_handler) _Block_release(_handler);
    [_upload release]; [super dealloc];
}
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSUInteger)taskIdentifier { return _ident; }
- (NSURLRequest *)originalRequest { return _original; } - (NSURLRequest *)currentRequest { return _current; }
- (NSURLResponse *)response { return _response; } - (NSError *)error { return _error; }
- (NSURLSessionTaskState)state { return _state; }
- (NSString *)taskDescription { return _desc; } - (void)setTaskDescription:(NSString *)d { [_desc release]; _desc = [d copy]; }
- (float)priority { return _priority; } - (void)setPriority:(float)p { _priority = p; }
- (int64_t)countOfBytesReceived { return _received; } - (int64_t)countOfBytesExpectedToReceive { return _expected; }
- (int64_t)countOfBytesSent { return _sent; } - (int64_t)countOfBytesExpectedToSend { return (int64_t)[_upload ?: [_original HTTPBody] length]; }
- (void)suspend { if (!_started) _state = NSURLSessionTaskStateSuspended; }   /* ponytail: a running task keeps running */
- (void)cancel {
    if (_state == NSURLSessionTaskStateCompleted) return;
    _cancelled = YES;
    if (_host) _scion_net(NET_HTTP_CANCEL, (uint64_t)_host, 0, 0, 0, 0);
    if (!_started) { _started = YES; [self retain]; dispatch_async(dispatch_get_global_queue(0, 0), ^{ [self _run]; [self release]; }); }
    else if (_state != NSURLSessionTaskStateCompleted) _state = NSURLSessionTaskStateCanceling;
}
- (void)resume {
    if (_started) return;
    _started = YES; _state = NSURLSessionTaskStateRunning;
    [self retain];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{ [self _run]; [self release]; });
}
- (void)_deliver:(void (^)(void))b { [[_session _queue] addOperationWithBlock:b]; }
- (void)_run {
    NSURLSession *s = _session;
    id d = _handler ? nil : [s _delegate];
    NSURLSessionConfiguration *c = [s _config];
    HTTPJob j = {_current, [c HTTPAdditionalHeaders], _upload, [_current timeoutInterval] ?: [c timeoutIntervalForRequest], &_host, &_cancelled};
    if (j.timeout <= 0) j.timeout = [c timeoutIntervalForRequest];
    _sent = (int64_t)[_upload ?: [_current HTTPBody] length];
    NSMutableData *data = _kind != TASK_DOWNLOAD && _handler ? [NSMutableData data] : nil;
    __block int fd = -1;
    NSString *path = nil;
    if (_kind == TASK_DOWNLOAD) {
        path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"CFNetworkDownload_%@.tmp", [[NSUUID UUID] UUIDString]]];
        fd = open([path fileSystemRepresentation], 0x601, 0644);   /* O_WRONLY | O_CREAT | O_TRUNC */
    }
    BOOL wants_response = [d respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)] && _kind != TASK_DOWNLOAD;
    BOOL wants_data = [d respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)] && _kind != TASK_DOWNLOAD;
    BOOL wants_progress = [d respondsToSelector:@selector(URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)] && _kind == TASK_DOWNLOAD;
    NSHTTPURLResponse *resp = nil;
    NSError *err = _cancelled ? url_error(NSURLErrorCancelled, [_current URL]) : nil;
    if (!err && _kind == TASK_DOWNLOAD && fd < 0) err = url_error(NSURLErrorCannotCreateFile, [_current URL]);
    if (!err) err = http_run(&j, &resp, ^BOOL(NSHTTPURLResponse *r) {
        _response = [r retain];
        _expected = [r expectedContentLength] < 0 ? -1 : [r expectedContentLength];
        if (!wants_response) return YES;
        /* the delegate decides, on its queue, whether the body comes */
        __block NSInteger disposition = NSURLSessionResponseAllow;
        dsem_t sem = dispatch_semaphore_create(0);
        [self _deliver:^{
            [d URLSession:s dataTask:(NSURLSessionDataTask *)self didReceiveResponse:r completionHandler:^(NSURLSessionResponseDisposition x) {
                disposition = x; dispatch_semaphore_signal(sem);
            }];
        }];
        dispatch_semaphore_wait(sem, ~0ull);
        dispatch_release(sem);
        return disposition != NSURLSessionResponseCancel;
    }, ^BOOL(const void *p, size_t n) {
        _received += n;
        if (fd >= 0) {
            if (write(fd, p, n) != (long)n) return NO;
            if (wants_progress) {
                int64_t total = _received, expected = _expected;
                [self _deliver:^{ [d URLSession:s downloadTask:(NSURLSessionDownloadTask *)self didWriteData:(int64_t)n totalBytesWritten:total totalBytesExpectedToWrite:expected]; }];
            }
        } else if (data) [data appendBytes:p length:n];
        else if (wants_data) {
            NSData *piece = [NSData dataWithBytes:p length:n];
            [self _deliver:^{ [d URLSession:s dataTask:(NSURLSessionDataTask *)self didReceiveData:piece]; }];
        }
        return YES;
    });
    if (fd >= 0) close(fd);
    _error = [err retain];
    NSURLResponse *r = _response;
    id h = _handler;
    NSURL *location = path && !err ? [NSURL fileURLWithPath:path] : nil;
    [self _deliver:^{
        if (_kind == TASK_DOWNLOAD) {
            @autoreleasepool {   /* (what the handler read from the file goes first: Windows keeps a mapped file) */
                if (h) ((void (^)(NSURL *, NSURLResponse *, NSError *))h)(location, r, err);
                else if (location && [d respondsToSelector:@selector(URLSession:downloadTask:didFinishDownloadingToURL:)])
                    [d URLSession:s downloadTask:(NSURLSessionDownloadTask *)self didFinishDownloadingToURL:location];
            }
            if (path) unlink([path fileSystemRepresentation]);
        } else if (h) ((void (^)(NSData *, NSURLResponse *, NSError *))h)(err ? nil : data, r, err);
        _state = NSURLSessionTaskStateCompleted;
        if (!h && [d respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) [d URLSession:s task:self didCompleteWithError:err];
        [s _taskDone:self];
    }];
}
@end
@implementation NSURLSessionDataTask @end
@implementation NSURLSessionUploadTask @end
@implementation NSURLSessionDownloadTask
- (void)cancelByProducingResumeData:(void (^)(NSData *))h { [self cancel]; if (h) [self _deliver:^{ h(nil); }]; }   /* no resume data */
@end

@implementation NSURLSession { NSURLSessionConfiguration *_config; id _delegate; NSOperationQueue *_queue; NSString *_desc; NSMutableArray *_tasks; BOOL _invalid; }
static NSUInteger g_task_ids;
+ (NSURLSession *)sharedSession { static NSURLSession *s; @synchronized(self) { if (!s) s = [[self alloc] initWithConfiguration:nil delegate:nil queue:nil]; } return s; }
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)c { return [[[self alloc] initWithConfiguration:c delegate:nil queue:nil] autorelease]; }
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)c delegate:(id)d delegateQueue:(NSOperationQueue *)q {
    return [[[self alloc] initWithConfiguration:c delegate:d queue:q] autorelease];
}
- (instancetype)initWithConfiguration:(NSURLSessionConfiguration *)c delegate:(id)d queue:(NSOperationQueue *)q {
    if (!(self = [super init])) return nil;
    _config = [c ?: [NSURLSessionConfiguration defaultSessionConfiguration] copy];
    _delegate = [d retain];   /* (a session keeps its delegate until it is invalidated) */
    if (q) _queue = [q retain];
    else { _queue = [[NSOperationQueue alloc] init]; [_queue setMaxConcurrentOperationCount:1]; }
    _tasks = [[NSMutableArray alloc] init];
    return self;
}
- (void)dealloc { [_config release]; [_delegate release]; [_queue release]; [_desc release]; [_tasks release]; [super dealloc]; }
- (NSURLSessionConfiguration *)configuration { return [[_config copy] autorelease]; }
- (NSURLSessionConfiguration *)_config { return _config; }
- (id)delegate { return _delegate; } - (id)_delegate { return _delegate; }
- (NSOperationQueue *)delegateQueue { return _queue; } - (NSOperationQueue *)_queue { return _queue; }
- (NSString *)sessionDescription { return _desc; } - (void)setSessionDescription:(NSString *)d { [_desc release]; _desc = [d copy]; }
- (id)_task:(Class)cls kind:(NSInteger)k request:(NSURLRequest *)r body:(NSData *)body handler:(id)h {
    NSURLSessionTask *t = [[[cls alloc] init] autorelease];
    t->_session = [self retain]; t->_original = [r copy]; t->_current = [r copy]; t->_kind = k; t->_upload = [body copy];
    t->_handler = h ? _Block_copy(h) : nil; t->_state = NSURLSessionTaskStateSuspended; t->_priority = 0.5f;
    @synchronized(self) {
        t->_ident = ++g_task_ids;
        if (_invalid) { t->_cancelled = YES; return t; }
        [_tasks addObject:t];
    }
    return t;
}
- (void)_taskDone:(NSURLSessionTask *)t {
    BOOL last;
    @synchronized(self) { [_tasks removeObjectIdenticalTo:t]; last = _invalid && ![_tasks count]; }
    if (last) [self _invalidated];
}
- (void)_invalidated {
    if ([_delegate respondsToSelector:@selector(URLSession:didBecomeInvalidWithError:)]) [_delegate URLSession:self didBecomeInvalidWithError:nil];
    id d = _delegate; _delegate = nil; [d release];
}
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)r { return [self _task:[NSURLSessionDataTask class] kind:TASK_DATA request:r body:nil handler:nil]; }
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)u { return [self dataTaskWithRequest:[NSURLRequest requestWithURL:u]]; }
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)r completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))h {
    return [self _task:[NSURLSessionDataTask class] kind:TASK_DATA request:r body:nil handler:h];
}
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)u completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))h { return [self dataTaskWithRequest:[NSURLRequest requestWithURL:u] completionHandler:h]; }
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)r fromData:(NSData *)d { return [self uploadTaskWithRequest:r fromData:d completionHandler:nil]; }
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)r fromData:(NSData *)d completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))h {
    return [self _task:[NSURLSessionUploadTask class] kind:TASK_UPLOAD request:r body:d ?: [NSData data] handler:h];
}
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)r fromFile:(NSURL *)f { return [self uploadTaskWithRequest:r fromFile:f completionHandler:nil]; }
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)r fromFile:(NSURL *)f completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))h {
    return [self uploadTaskWithRequest:r fromData:[NSData dataWithContentsOfURL:f] completionHandler:h];
}
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)r { return [self _task:[NSURLSessionDownloadTask class] kind:TASK_DOWNLOAD request:r body:nil handler:nil]; }
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)u { return [self downloadTaskWithRequest:[NSURLRequest requestWithURL:u]]; }
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)r completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))h {
    return [self _task:[NSURLSessionDownloadTask class] kind:TASK_DOWNLOAD request:r body:nil handler:h];
}
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)u completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))h { return [self downloadTaskWithRequest:[NSURLRequest requestWithURL:u] completionHandler:h]; }
- (void)getAllTasksWithCompletionHandler:(void (^)(NSArray *))h { NSArray *a; @synchronized(self) { a = [[_tasks copy] autorelease]; } [_queue addOperationWithBlock:^{ h(a); }]; }
- (void)getTasksWithCompletionHandler:(void (^)(NSArray *, NSArray *, NSArray *))h {
    NSMutableArray *data = [NSMutableArray array], *up = [NSMutableArray array], *down = [NSMutableArray array];
    @synchronized(self) { for (NSURLSessionTask *t in _tasks) [t->_kind == TASK_DOWNLOAD ? down : t->_kind == TASK_UPLOAD ? up : data addObject:t]; }
    [_queue addOperationWithBlock:^{ h(data, up, down); }];
}
- (void)finishTasksAndInvalidate {
    if (self == [NSURLSession sharedSession]) return;
    BOOL now;
    @synchronized(self) { _invalid = YES; now = ![_tasks count]; }
    if (now) [_queue addOperationWithBlock:^{ [self _invalidated]; }];
}
- (void)invalidateAndCancel {
    if (self == [NSURLSession sharedSession]) return;
    NSArray *a;
    @synchronized(self) { a = [[_tasks copy] autorelease]; }
    for (NSURLSessionTask *t in a) [t cancel];
    [self finishTasksAndInvalidate];
}
- (void)resetWithCompletionHandler:(void (^)(void))h { [_queue addOperationWithBlock:h]; }
- (void)flushWithCompletionHandler:(void (^)(void))h { [_queue addOperationWithBlock:h]; }
@end

/* the old API, on the same requests */
@implementation NSURLConnection
+ (NSData *)sendSynchronousRequest:(NSURLRequest *)r returningResponse:(NSURLResponse **)resp error:(NSError **)e {
    NSMutableData *d = [NSMutableData data];
    volatile int64_t handle = 0; volatile BOOL cancelled = NO;
    HTTPJob j = {r, nil, nil, [r timeoutInterval], &handle, &cancelled};
    NSHTTPURLResponse *got = nil;
    NSError *err = http_run(&j, &got, nil, ^BOOL(const void *p, size_t n) { [d appendBytes:p length:n]; return YES; });
    if (resp) *resp = got;
    if (e) *e = err;
    return err ? nil : d;
}
+ (void)sendAsynchronousRequest:(NSURLRequest *)r queue:(NSOperationQueue *)q completionHandler:(void (^)(NSURLResponse *, NSData *, NSError *))h {
    [[[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        [q addOperationWithBlock:^{ h(resp, d, e); }];
    }] resume];
}
@end

/* ======================================================================= files, archives, notifications, scripting */
@implementation NSFileCoordinator
+ (void)addFilePresenter:(id)p {} + (void)removeFilePresenter:(id)p {}
+ (NSArray *)filePresenters { return @[]; }
- (instancetype)initWithFilePresenter:(id)p { return [self init]; }
- (void)coordinateReadingItemAtURL:(NSURL *)u options:(NSUInteger)o error:(NSError **)e byAccessor:(void (NS_NOESCAPE ^)(NSURL *))a { if (e) *e = nil; a(u); }
- (void)coordinateWritingItemAtURL:(NSURL *)u options:(NSUInteger)o error:(NSError **)e byAccessor:(void (NS_NOESCAPE ^)(NSURL *))a { if (e) *e = nil; a(u); }
- (void)coordinateReadingItemAtURL:(NSURL *)r options:(NSUInteger)ro writingItemAtURL:(NSURL *)w options:(NSUInteger)wo error:(NSError **)e byAccessor:(void (NS_NOESCAPE ^)(NSURL *, NSURL *))a { if (e) *e = nil; a(r, w); }
- (void)coordinateWritingItemAtURL:(NSURL *)u1 options:(NSUInteger)o1 writingItemAtURL:(NSURL *)u2 options:(NSUInteger)o2 error:(NSError **)e byAccessor:(void (NS_NOESCAPE ^)(NSURL *, NSURL *))a { if (e) *e = nil; a(u1, u2); }
- (void)itemAtURL:(NSURL *)o didMoveToURL:(NSURL *)n {} - (void)itemAtURL:(NSURL *)o willMoveToURL:(NSURL *)n {}
- (void)cancel {}
@end
/* the old typed archives: keyed archives here (they only need to read back what this process wrote) */
@implementation NSArchiver
+ (NSData *)archivedDataWithRootObject:(id)o { return [NSKeyedArchiver archivedDataWithRootObject:o]; }
+ (BOOL)archiveRootObject:(id)o toFile:(NSString *)p { return [[self archivedDataWithRootObject:o] writeToFile:p atomically:YES]; }
@end
@implementation NSUnarchiver
+ (id)unarchiveObjectWithData:(NSData *)d { return [NSKeyedUnarchiver unarchiveObjectWithData:d]; }
+ (id)unarchiveObjectWithFile:(NSString *)p { return [self unarchiveObjectWithData:[NSData dataWithContentsOfFile:p]]; }
@end
@implementation NSDistributedNotificationCenter
+ (instancetype)defaultCenter { static NSDistributedNotificationCenter *c; if (!c) c = [[self alloc] init]; return c; }
+ (instancetype)notificationCenterForType:(NSString *)t { return [self defaultCenter]; }
- (void)postNotificationName:(NSString *)n object:(NSString *)o userInfo:(NSDictionary *)u deliverImmediately:(BOOL)d { [self postNotificationName:n object:o userInfo:u]; }
- (void)postNotificationName:(NSString *)n object:(NSString *)o userInfo:(NSDictionary *)u options:(NSUInteger)opts { [self postNotificationName:n object:o userInfo:u]; }
- (void)addObserver:(id)o selector:(SEL)s name:(NSString *)n object:(NSString *)obj suspensionBehavior:(NSUInteger)b { [self addObserver:o selector:s name:n object:obj]; }
@end
NSString *const NSAppleScriptErrorMessage = @"NSAppleScriptErrorMessage", *const NSAppleScriptErrorNumber = @"NSAppleScriptErrorNumber",
    *const NSAppleScriptErrorBriefMessage = @"NSAppleScriptErrorBriefMessage", *const NSAppleScriptErrorAppName = @"NSAppleScriptErrorAppName",
    *const NSAppleScriptErrorRange = @"NSAppleScriptErrorRange";
@implementation NSAppleScript { NSString *_src; }
- (instancetype)initWithSource:(NSString *)s { _src = [s copy]; return self; }
- (instancetype)initWithContentsOfURL:(NSURL *)u error:(NSDictionary **)e { return [self initWithSource:[NSString stringWithContentsOfURL:u encoding:NSUTF8StringEncoding error:NULL] ?: @""]; }
- (void)dealloc { [_src release]; [super dealloc]; }
- (NSString *)source { return _src; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (BOOL)isCompiled { return NO; }
- (BOOL)compileAndReturnError:(NSDictionary **)e { return [self executeAndReturnError:e] != nil; }
- (id)executeAndReturnError:(NSDictionary **)e {
    if (e) *e = @{NSAppleScriptErrorMessage: @"AppleScript is not available in scion.", NSAppleScriptErrorNumber: @(-1750)};
    return nil;
}
@end
@implementation NSXMLNode
- (NSString *)stringValue { return nil; } - (NSString *)name { return nil; } - (NSArray *)children { return nil; }
- (NSArray *)nodesForXPath:(NSString *)x error:(NSError **)e { if (e) *e = nil; return @[]; }
- (NSString *)XMLString { return @""; }
@end
@implementation NSXMLElement
- (instancetype)initWithName:(NSString *)n { return [self init]; }
- (NSArray *)elementsForName:(NSString *)n { return @[]; }
- (NSXMLNode *)attributeForName:(NSString *)n { return nil; }
@end
@implementation NSXMLDocument   /* ponytail: no XML parser yet; documents fail to load */
- (instancetype)initWithData:(NSData *)d options:(NSUInteger)o error:(NSError **)e {
    if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:259 userInfo:@{NSLocalizedDescriptionKey: @"XML documents are not supported in scion yet."}];
    [self release]; return nil;
}
- (instancetype)initWithContentsOfURL:(NSURL *)u options:(NSUInteger)o error:(NSError **)e { return [self initWithData:[NSData data] options:o error:e]; }
- (instancetype)initWithXMLString:(NSString *)s options:(NSUInteger)o error:(NSError **)e { return [self initWithData:[NSData data] options:o error:e]; }
- (NSXMLElement *)rootElement { return nil; }
@end
@implementation NSPort
+ (NSPort *)port { return [[[NSMachPort alloc] init] autorelease]; }
- (void)invalidate {} - (BOOL)isValid { return NO; }
- (void)setDelegate:(id)d {} - (id)delegate { return nil; }
- (void)scheduleInRunLoop:(NSRunLoop *)r forMode:(NSString *)m {} - (void)removeFromRunLoop:(NSRunLoop *)r forMode:(NSString *)m {}
@end
@implementation NSMachPort
+ (NSPort *)portWithMachPort:(uint32_t)p { return [[[self alloc] init] autorelease]; }
- (uint32_t)machPort { return 0; }
@end
@implementation NSPortNameServer + (NSPortNameServer *)systemDefaultPortNameServer { return [NSMachBootstrapServer sharedInstance]; } @end
@implementation NSMachBootstrapServer
+ (id)sharedInstance { static NSMachBootstrapServer *s; if (!s) s = [[self alloc] init]; return s; }
- (NSPort *)portForName:(NSString *)n { return nil; }
- (NSPort *)portForName:(NSString *)n host:(NSString *)h { return nil; }
- (BOOL)registerPort:(NSPort *)p name:(NSString *)n { return NO; }
@end
@implementation NSInvocationOperation { NSInvocation *_inv; id _result; }
- (instancetype)initWithInvocation:(NSInvocation *)i { if ((self = [super init])) { _inv = [i retain]; [_inv retainArguments]; } return self; }
- (instancetype)initWithTarget:(id)t selector:(SEL)s object:(id)o {
    NSMethodSignature *sig = [t methodSignatureForSelector:s];
    if (!sig) { [self release]; return nil; }
    NSInvocation *i = [NSInvocation invocationWithMethodSignature:sig];
    [i setTarget:t]; [i setSelector:s];
    if ([sig numberOfArguments] > 2) [i setArgument:&o atIndex:2];
    return [self initWithInvocation:i];
}
- (void)dealloc { [_inv release]; [_result release]; [super dealloc]; }
- (NSInvocation *)invocation { return _inv; }
- (void)main {
    [_inv invoke];
    if (*skip_qual([[_inv methodSignature] methodReturnType]) == '@') { id r = nil; [_inv getReturnValue:&r]; _result = [r retain]; }
}
- (id)result { return _result; }
@end

/* ======================================================================= odds and ends */
NSString *const NSFileOwnerAccountID = @"NSFileOwnerAccountID", *const NSFileGroupOwnerAccountID = @"NSFileGroupOwnerAccountID";
NSRange NSIntersectionRange(NSRange a, NSRange b) {
    NSUInteger s = a.location > b.location ? a.location : b.location, e = NSMaxRange(a) < NSMaxRange(b) ? NSMaxRange(a) : NSMaxRange(b);
    return e > s ? NSMakeRange(s, e - s) : NSMakeRange(0, 0);
}
NSRange NSUnionRange(NSRange a, NSRange b) {
    NSUInteger s = a.location < b.location ? a.location : b.location, e = NSMaxRange(a) > NSMaxRange(b) ? NSMaxRange(a) : NSMaxRange(b);
    return NSMakeRange(s, e - s);
}

/* ======================================================================= NSFileWrapper (regular files and folders) */
@implementation NSFileWrapper { NSData *_data; NSMutableDictionary *_children; NSString *_filename, *_preferred; NSDictionary *_attrs; }
- (instancetype)initWithURL:(NSURL *)u options:(NSFileWrapperReadingOptions)o error:(NSError **)e {
    BOOL dir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:[u path] isDirectory:&dir]) {
        if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:@{NSFilePathErrorKey: [u path] ?: @""}];
        [self release]; return nil;
    }
    _filename = [[u lastPathComponent] copy]; _preferred = [_filename copy];
    if (dir) {
        _children = [[NSMutableDictionary alloc] init];
        for (NSString *n in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[u path] error:NULL]) {
            NSFileWrapper *c = [[NSFileWrapper alloc] initWithURL:[u URLByAppendingPathComponent:n] options:o error:NULL];
            if (c) _children[n] = c;
            [c release];
        }
    } else {
        _data = [[NSData alloc] initWithContentsOfFile:[u path] options:NSDataReadingMappedIfSafe error:e];
        if (!_data) { [self release]; return nil; }
    }
    return self;
}
- (instancetype)initRegularFileWithContents:(NSData *)d { _data = [d copy]; return self; }
- (instancetype)initDirectoryWithFileWrappers:(NSDictionary *)c { _children = [c mutableCopy] ?: [[NSMutableDictionary alloc] init]; return self; }
- (void)dealloc { [_data release]; [_children release]; [_filename release]; [_preferred release]; [_attrs release]; [super dealloc]; }
- (BOOL)isRegularFile { return _data != nil; }
- (BOOL)isDirectory { return _children != nil; }
- (BOOL)isSymbolicLink { return NO; }
- (NSData *)regularFileContents { return _data; }
- (NSDictionary *)fileWrappers { return _children ? [[_children copy] autorelease] : nil; }
- (NSString *)filename { return _filename; } - (void)setFilename:(NSString *)f { [_filename release]; _filename = [f copy]; }
- (NSString *)preferredFilename { return _preferred; } - (void)setPreferredFilename:(NSString *)f { [_preferred release]; _preferred = [f copy]; }
- (NSDictionary *)fileAttributes { return _attrs ?: @{}; } - (void)setFileAttributes:(NSDictionary *)a { [_attrs release]; _attrs = [a copy]; }
- (NSString *)addFileWrapper:(NSFileWrapper *)w { NSString *n = w.preferredFilename ?: w.filename ?: @"file"; if (_children) _children[n] = w; return n; }
- (NSString *)addRegularFileWithContents:(NSData *)d preferredFilename:(NSString *)n {
    NSFileWrapper *w = [[[NSFileWrapper alloc] initRegularFileWithContents:d] autorelease]; w.preferredFilename = n; return [self addFileWrapper:w];
}
- (void)removeFileWrapper:(NSFileWrapper *)w { for (NSString *k in [_children allKeysForObject:w]) [_children removeObjectForKey:k]; }
- (BOOL)matchesContentsOfURL:(NSURL *)u { return _data && [_data isEqualToData:[NSData dataWithContentsOfURL:u]]; }
- (BOOL)readFromURL:(NSURL *)u options:(NSFileWrapperReadingOptions)o error:(NSError **)e {
    NSFileWrapper *n = [[NSFileWrapper alloc] initWithURL:u options:o error:e];
    if (!n) return NO;
    [_data release]; _data = [n->_data retain]; [_children release]; _children = [n->_children retain];
    [n release]; return YES;
}
- (BOOL)writeToURL:(NSURL *)u options:(NSFileWrapperWritingOptions)o originalContentsURL:(NSURL *)orig error:(NSError **)e {
    if (_data) return [_data writeToURL:u options:(o & NSFileWrapperWritingAtomic) ? NSDataWritingAtomic : 0 error:e];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:[u path] withIntermediateDirectories:YES attributes:nil error:e]) return NO;
    for (NSString *k in _children) if (![_children[k] writeToURL:[u URLByAppendingPathComponent:k] options:o originalContentsURL:nil error:e]) return NO;
    return YES;
}
- (NSData *)serializedRepresentation { return _data; }
@end
@implementation NSFileManager (MWDisplayName)
- (NSString *)displayNameAtPath:(NSString *)p { return [p lastPathComponent]; }
@end

/* ======================================================================= NSPredicate: a small format language
 * comparisons (== = != <> < <= > >= CONTAINS BEGINSWITH ENDSWITH LIKE MATCHES IN, with [c] [d] [cd]) between key paths,
 * SELF, %@ %K %d %f %s arguments, 'strings', numbers, TRUE/FALSE/YES/NO/NIL/NULL; joined by AND/OR/NOT/&&/||/! and parentheses. */
@interface _MWPredNode : NSObject { @public int kind; NSString *op; id lhs, rhs; NSArray *kids; BOOL ci, di, (^block)(id, NSDictionary *); } @end
@implementation _MWPredNode - (void)dealloc { [op release]; [lhs release]; [rhs release]; [kids release]; if (block) _Block_release(block); [super dealloc]; } @end
@interface _MWPredExpr : NSObject { @public int kind; id value; } @end   /* 0 constant, 1 key path, 2 SELF */
@implementation _MWPredExpr - (void)dealloc { [value release]; [super dealloc]; } @end
typedef struct { const unichar *s; NSUInteger i, n; NSArray *args; NSUInteger ai; va_list *ap; } pparse;
static void p_ws(pparse *p) { while (p->i < p->n && (p->s[p->i] == ' ' || p->s[p->i] == '\t' || p->s[p->i] == '\n')) p->i++; }
static NSString *p_word(pparse *p) {
    p_ws(p); NSUInteger b = p->i;
    while (p->i < p->n && (isalnum(p->s[p->i]) || p->s[p->i] == '_' || p->s[p->i] == '.' || p->s[p->i] == '@' || p->s[p->i] == '$')) p->i++;
    return [NSString stringWithCharacters:p->s + b length:p->i - b];
}
static BOOL p_kw(pparse *p, NSString *kw) {
    p_ws(p); NSUInteger save = p->i; NSString *w = p_word(p);
    if ([w caseInsensitiveCompare:kw] == NSOrderedSame) return YES;
    p->i = save; return NO;
}
static BOOL p_sym(pparse *p, const char *sym) {
    p_ws(p); NSUInteger l = strlen(sym);
    if (p->i + l > p->n) return NO;
    for (NSUInteger k = 0; k < l; k++) if (p->s[p->i + k] != (unichar)sym[k]) return NO;
    p->i += l; return YES;
}
static id p_arg(pparse *p, char f) {
    if (p->args) return p->ai < [p->args count] ? p->args[p->ai++] : nil;
    if (!p->ap) return nil;
    switch (f) {
    case '@': case 'K': return va_arg(*p->ap, id);
    case 'd': case 'i': return @(va_arg(*p->ap, int));
    case 'l': return @(va_arg(*p->ap, long));
    case 'f': return @(va_arg(*p->ap, double));
    case 's': { const char *c = va_arg(*p->ap, const char *); return c ? [NSString stringWithUTF8String:c] : nil; }
    }
    return nil;
}
static _MWPredExpr *p_expr(pparse *p) {
    _MWPredExpr *e = [[[_MWPredExpr alloc] init] autorelease];
    p_ws(p);
    if (p->i >= p->n) return e;
    unichar c = p->s[p->i];
    if (c == '%' && p->i + 1 < p->n) {
        unichar f = p->s[p->i + 1]; p->i += 2;
        if (f == 'l' && p->i < p->n && (p->s[p->i] == 'd' || p->s[p->i] == 'u')) p->i++;
        id v = p_arg(p, (char)f);
        if (f == 'K') { e->kind = 1; e->value = [v copy]; } else e->value = [v retain];
        return e;
    }
    if (c == '\'' || c == '"') {
        NSUInteger b = ++p->i; while (p->i < p->n && p->s[p->i] != c) p->i++;
        e->value = [[NSString alloc] initWithCharacters:p->s + b length:p->i - b];
        if (p->i < p->n) p->i++;
        return e;
    }
    if (isdigit(c) || c == '-') {
        NSUInteger b = p->i++; while (p->i < p->n && (isdigit(p->s[p->i]) || p->s[p->i] == '.')) p->i++;
        e->value = [@([[NSString stringWithCharacters:p->s + b length:p->i - b] doubleValue]) retain];
        return e;
    }
    if (c == '{') {   /* aggregate */
        p->i++; NSMutableArray *a = [NSMutableArray array];
        while (!p_sym(p, "}") && p->i < p->n) { [a addObject:p_expr(p)->value ?: [NSNull null]]; p_sym(p, ","); }
        e->value = [a retain]; return e;
    }
    NSString *w = p_word(p);
    NSString *u = [w uppercaseString];
    if ([u isEqualToString:@"SELF"]) e->kind = 2;
    else if ([u isEqualToString:@"TRUE"] || [u isEqualToString:@"YES"]) e->value = [@YES retain];
    else if ([u isEqualToString:@"FALSE"] || [u isEqualToString:@"NO"]) e->value = [@NO retain];
    else if ([u isEqualToString:@"NIL"] || [u isEqualToString:@"NULL"]) e->value = nil;
    else { e->kind = 1; e->value = [w copy]; }
    return e;
}
static _MWPredNode *p_or(pparse *p);
static _MWPredNode *p_unary(pparse *p) {
    if (p_sym(p, "!") || p_kw(p, @"NOT")) { _MWPredNode *n = [[[_MWPredNode alloc] init] autorelease]; n->kind = 3; n->kids = [@[p_unary(p)] retain]; return n; }
    if (p_sym(p, "(")) { _MWPredNode *n = p_or(p); p_sym(p, ")"); return n; }
    if (p_kw(p, @"TRUEPREDICATE")) { _MWPredNode *n = [[[_MWPredNode alloc] init] autorelease]; n->kind = 4; return n; }
    if (p_kw(p, @"FALSEPREDICATE")) { _MWPredNode *n = [[[_MWPredNode alloc] init] autorelease]; n->kind = 5; return n; }
    _MWPredNode *n = [[[_MWPredNode alloc] init] autorelease];
    n->lhs = [p_expr(p) retain];
    static const char *ops[] = {"==", "!=", "<>", "<=", "=<", ">=", "=>", "=", "<", ">", 0};
    for (int k = 0; ops[k]; k++) if (p_sym(p, ops[k])) { n->op = [@(ops[k]) retain]; break; }
    if (!n->op) for (NSString *w in @[@"CONTAINS", @"BEGINSWITH", @"ENDSWITH", @"LIKE", @"MATCHES", @"IN"]) if (p_kw(p, w)) { n->op = [w retain]; break; }
    if (!n->op) { n->kind = 6; return n; }   /* a bare value: its truth */
    if (p_sym(p, "[")) { while (p->i < p->n && p->s[p->i] != ']') { if (p->s[p->i] == 'c') n->ci = YES; if (p->s[p->i] == 'd') n->di = YES; p->i++; } p_sym(p, "]"); }
    n->rhs = [p_expr(p) retain];
    return n;
}
static _MWPredNode *p_and(pparse *p) {
    _MWPredNode *a = p_unary(p);
    while (p_kw(p, @"AND") || p_sym(p, "&&")) { _MWPredNode *n = [[[_MWPredNode alloc] init] autorelease]; n->kind = 1; n->kids = [@[a, p_unary(p)] retain]; a = n; }
    return a;
}
static _MWPredNode *p_or(pparse *p) {
    _MWPredNode *a = p_and(p);
    while (p_kw(p, @"OR") || p_sym(p, "||")) { _MWPredNode *n = [[[_MWPredNode alloc] init] autorelease]; n->kind = 2; n->kids = [@[a, p_and(p)] retain]; a = n; }
    return a;
}
static id p_value(_MWPredExpr *e, id obj, NSDictionary *vars) {
    if (e->kind == 2) return obj;
    if (e->kind == 1) {
        if ([e->value hasPrefix:@"$"]) return vars[[e->value substringFromIndex:1]];
        @try { return [obj valueForKeyPath:e->value]; } @catch (NSException *x) { return nil; }
    }
    return e->value;
}
static NSString *p_fold(id v, BOOL ci, BOOL di) {
    NSString *s = [v isKindOfClass:[NSString class]] ? v : [v description];
    if (ci) s = [s lowercaseString];
    if (di) s = [s stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:nil];
    return s;
}
static BOOL p_like(NSString *s, NSUInteger i, NSString *pat, NSUInteger j) {
    for (; j < [pat length]; j++) {
        unichar c = [pat characterAtIndex:j];
        if (c == '*') { for (NSUInteger k = i; k <= [s length]; k++) if (p_like(s, k, pat, j + 1)) return YES; return NO; }
        if (i >= [s length] || (c != '?' && c != [s characterAtIndex:i])) return NO;
        i++;
    }
    return i == [s length];
}
static BOOL p_eval(_MWPredNode *n, id obj, NSDictionary *vars) {
    switch (n->kind) {
    case 1: return p_eval(n->kids[0], obj, vars) && p_eval(n->kids[1], obj, vars);
    case 2: return p_eval(n->kids[0], obj, vars) || p_eval(n->kids[1], obj, vars);
    case 3: return !p_eval(n->kids[0], obj, vars);
    case 4: return YES;
    case 5: return NO;
    case 6: return [p_value(n->lhs, obj, vars) boolValue];
    case 7: return n->block(obj, vars);
    }
    id a = p_value(n->lhs, obj, vars), b = p_value(n->rhs, obj, vars);
    NSString *op = n->op;
    if ([op isEqualToString:@"IN"]) {
        if ([b isKindOfClass:[NSString class]]) return a && [p_fold(b, n->ci, n->di) rangeOfString:p_fold(a, n->ci, n->di)].location != NSNotFound;
        for (id x in b) if ((n->ci || n->di) ? [p_fold(x, n->ci, n->di) isEqualToString:p_fold(a, n->ci, n->di)] : [x isEqual:a]) return YES;
        return NO;
    }
    if ([op isEqualToString:@"CONTAINS"]) {
        if ([a isKindOfClass:[NSString class]]) return b && [p_fold(a, n->ci, n->di) rangeOfString:p_fold(b, n->ci, n->di)].location != NSNotFound;
        for (id x in a) if ([x isEqual:b]) return YES;
        return NO;
    }
    if ([op isEqualToString:@"BEGINSWITH"]) return a && b && [p_fold(a, n->ci, n->di) hasPrefix:p_fold(b, n->ci, n->di)];
    if ([op isEqualToString:@"ENDSWITH"]) return a && b && [p_fold(a, n->ci, n->di) hasSuffix:p_fold(b, n->ci, n->di)];
    if ([op isEqualToString:@"LIKE"]) return a && b && p_like(p_fold(a, n->ci, n->di), 0, p_fold(b, n->ci, n->di), 0);
    if ([op isEqualToString:@"MATCHES"]) {
        if (!a || !b) return NO;
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^(?:%@)$", b] options:n->ci ? NSRegularExpressionCaseInsensitive : 0 error:NULL];
        return [re numberOfMatchesInString:a options:0 range:NSMakeRange(0, [a length])] > 0;
    }
    NSComparisonResult r;
    if (a == b) r = NSOrderedSame;
    else if (!a || !b || a == [NSNull null] || b == [NSNull null]) return [op isEqualToString:@"!="] || [op isEqualToString:@"<>"];
    else if ((n->ci || n->di) && [a isKindOfClass:[NSString class]]) r = [p_fold(a, n->ci, n->di) compare:p_fold(b, n->ci, n->di)];
    else if ([a respondsToSelector:@selector(compare:)] && [a isKindOfClass:[b class]] ? YES : [a isKindOfClass:[NSNumber class]] && [b isKindOfClass:[NSNumber class]]) r = (NSComparisonResult)(intptr_t)[a performSelector:@selector(compare:) withObject:b];
    else r = [a isEqual:b] ? NSOrderedSame : NSOrderedAscending;
    if ([op isEqualToString:@"=="] || [op isEqualToString:@"="]) return r == NSOrderedSame || [a isEqual:b];
    if ([op isEqualToString:@"!="] || [op isEqualToString:@"<>"]) return r != NSOrderedSame && ![a isEqual:b];
    if ([op isEqualToString:@"<"]) return r == NSOrderedAscending;
    if ([op isEqualToString:@">"]) return r == NSOrderedDescending;
    if ([op isEqualToString:@"<="] || [op isEqualToString:@"=<"]) return r != NSOrderedDescending;
    return r != NSOrderedAscending;
}
@implementation NSPredicate { _MWPredNode *_root; NSString *_format; }
+ (NSPredicate *)_mwParse:(NSString *)f args:(NSArray *)a list:(va_list *)ap {
    NSPredicate *p = [[[self alloc] init] autorelease];
    NSUInteger n = [f length]; unichar *buf = malloc((n + 1) * sizeof(unichar)); [f getCharacters:buf range:NSMakeRange(0, n)];
    pparse ps = {buf, 0, n, a, 0, ap};
    p->_root = [p_or(&ps) retain]; p->_format = [f copy];
    free(buf);
    return p;
}
+ (NSPredicate *)predicateWithFormat:(NSString *)f, ... { va_list ap; va_start(ap, f); NSPredicate *p = [self _mwParse:f args:nil list:&ap]; va_end(ap); return p; }
+ (NSPredicate *)predicateWithFormat:(NSString *)f arguments:(va_list)ap { va_list c; va_copy(c, ap); NSPredicate *p = [self _mwParse:f args:nil list:&c]; va_end(c); return p; }
+ (NSPredicate *)predicateWithFormat:(NSString *)f argumentArray:(NSArray *)a { return [self _mwParse:f args:a ?: @[] list:NULL]; }
+ (NSPredicate *)predicateWithValue:(BOOL)v { return [self _mwParse:v ? @"TRUEPREDICATE" : @"FALSEPREDICATE" args:@[] list:NULL]; }
+ (NSPredicate *)predicateWithBlock:(BOOL (^)(id _Nullable, NSDictionary<NSString *, id> * _Nullable))b {
    NSPredicate *p = [[[self alloc] init] autorelease];
    p->_root = [[_MWPredNode alloc] init]; p->_root->kind = 7; p->_root->block = _Block_copy(b);
    p->_format = @"BLOCKPREDICATE";
    return p;
}
- (void)dealloc { [_root release]; [_format release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (BOOL)evaluateWithObject:(id)o { return p_eval(_root, o, nil); }
- (BOOL)evaluateWithObject:(id)o substitutionVariables:(NSDictionary *)v { return p_eval(_root, o, v); }
- (NSString *)predicateFormat { return _format; }
- (NSString *)description { return _format; }
- (void)allowEvaluation {}
@end
@implementation NSArray (MWPredicate)
- (NSArray *)filteredArrayUsingPredicate:(NSPredicate *)p { NSMutableArray *r = [NSMutableArray array]; for (id o in self) if ([p evaluateWithObject:o]) [r addObject:o]; return r; }
@end
@implementation NSMutableArray (MWPredicate)
- (void)filterUsingPredicate:(NSPredicate *)p { for (NSInteger i = (NSInteger)[self count] - 1; i >= 0; i--) if (![p evaluateWithObject:self[(NSUInteger)i]]) [self removeObjectAtIndex:(NSUInteger)i]; }
@end
@implementation NSSet (MWPredicate)
- (NSSet *)filteredSetUsingPredicate:(NSPredicate *)p { NSMutableSet *r = [NSMutableSet set]; for (id o in self) if ([p evaluateWithObject:o]) [r addObject:o]; return r; }
@end

/* ======================================================================= odds and ends apps call */
@implementation NSDirectoryEnumerator { NSString *_root; NSMutableArray *_stack; NSString *_current; NSUInteger _level; NSArray *_keys; BOOL _urls, _skipHidden, _noDescend; }
- (instancetype)_mwInitWithPath:(NSString *)p urls:(BOOL)u keys:(NSArray *)k options:(NSUInteger)o {
    _root = [p copy]; _urls = u; _keys = [k copy];
    _skipHidden = (o & 4) != 0; _noDescend = (o & 1) != 0;   /* NSDirectoryEnumerationSkipsSubdirectoryDescendants / SkipsHiddenFiles */
    NSArray *c = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:p error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    _stack = [[NSMutableArray alloc] init];
    if (c) [_stack addObject:[NSMutableArray arrayWithArray:c]];
    return self;
}
- (void)dealloc { [_root release]; [_stack release]; [_current release]; [_keys release]; [super dealloc]; }
- (id)nextObject {
    /* descend into the directory returned last time, unless skipped */
    if (_current && !_noDescend) {
        NSString *full = [_root stringByAppendingPathComponent:_current]; BOOL dir = NO;
        NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:full error:NULL];
        if ([[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&dir] && dir && ![a[NSFileType] isEqual:NSFileTypeSymbolicLink]) {
            NSArray *c = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:full error:NULL] sortedArrayUsingSelector:@selector(compare:)];
            NSMutableArray *pref = [NSMutableArray array];
            for (NSString *n in c) [pref addObject:[_current stringByAppendingPathComponent:n]];
            if ([pref count]) [_stack addObject:pref];
        }
    }
    [_current release]; _current = nil;
    while ([_stack count]) {
        NSMutableArray *top = [_stack lastObject];
        if (![top count]) { [_stack removeLastObject]; continue; }
        NSString *n = [[top[0] retain] autorelease]; [top removeObjectAtIndex:0];
        if (_skipHidden && [[n lastPathComponent] hasPrefix:@"."]) continue;
        _current = [n copy]; _level = [_stack count];
        return _urls ? (id)[NSURL fileURLWithPath:[_root stringByAppendingPathComponent:n]] : n;
    }
    return nil;
}
- (void)skipDescendants { [_current release]; _current = nil; }
- (void)skipDescendents { [self skipDescendants]; }
- (NSUInteger)level { return _level; }
- (NSDictionary *)fileAttributes { return _current ? [[NSFileManager defaultManager] attributesOfItemAtPath:[_root stringByAppendingPathComponent:_current] error:NULL] : nil; }
- (NSDictionary *)directoryAttributes { return [[NSFileManager defaultManager] attributesOfItemAtPath:_root error:NULL]; }
- (BOOL)isEnumeratingDirectoryPostOrder { return NO; }
@end
@implementation NSFileManager (MWEnumerators)
- (NSDirectoryEnumerator *)enumeratorAtPath:(NSString *)p { BOOL d; if (![self fileExistsAtPath:p isDirectory:&d] || !d) return nil; return [[[NSDirectoryEnumerator alloc] _mwInitWithPath:p urls:NO keys:nil options:0] autorelease]; }
- (NSDirectoryEnumerator *)enumeratorAtURL:(NSURL *)u includingPropertiesForKeys:(NSArray *)k options:(NSDirectoryEnumerationOptions)o errorHandler:(BOOL (^)(NSURL *, NSError *))h {
    return [[[NSDirectoryEnumerator alloc] _mwInitWithPath:[u path] urls:YES keys:k options:o] autorelease];
}
- (NSArray *)subpathsAtPath:(NSString *)p { NSMutableArray *a = [NSMutableArray array]; for (NSString *s in [self enumeratorAtPath:p]) [a addObject:s]; return a; }
@end
@implementation NSJSONSerialization (MWStreams)
+ (id)JSONObjectWithStream:(NSInputStream *)s options:(NSJSONReadingOptions)o error:(NSError **)e {
    NSMutableData *d = [NSMutableData data]; uint8_t buf[4096]; NSInteger n;
    if ([s streamStatus] == NSStreamStatusNotOpen) [s open];
    while ((n = [s read:buf maxLength:sizeof buf]) > 0) [d appendBytes:buf length:(NSUInteger)n];
    return [self JSONObjectWithData:d options:o error:e];
}
+ (NSInteger)writeJSONObject:(id)obj toStream:(NSOutputStream *)s options:(NSJSONWritingOptions)o error:(NSError **)e {
    NSData *d = [self dataWithJSONObject:obj options:o error:e]; return d ? [s write:[d bytes] maxLength:[d length]] : 0;
}
@end
@implementation NSCoder (MWBytes)
- (void)encodeBytes:(const void *)b length:(NSUInteger)n { [self encodeBytes:(const uint8_t *)b length:n forKey:@"NS.bytes"]; }
- (void *)decodeBytesWithReturnedLength:(NSUInteger *)n { return (void *)[self decodeBytesForKey:@"NS.bytes" returnedLength:n]; }
@end
@implementation NSData (MWBase64Old)
- (instancetype)initWithBase64Encoding:(NSString *)s { return [self initWithBase64EncodedString:s options:NSDataBase64DecodingIgnoreUnknownCharacters]; }
- (NSString *)base64Encoding { return [self base64EncodedStringWithOptions:0]; }
@end
@implementation NSDictionary (MWObjectsAndKeys)
- (instancetype)initWithObjectsAndKeys:(id)first, ... {
    NSMutableArray *o = [NSMutableArray array], *k = [NSMutableArray array]; va_list ap; va_start(ap, first);
    for (id v = first; v; v = va_arg(ap, id)) { id key = va_arg(ap, id); if (!key) break; [o addObject:v]; [k addObject:key]; }
    va_end(ap);
    return [self initWithDictionary:[NSDictionary dictionaryWithObjects:o forKeys:k]];
}
@end
@implementation NSMutableArray (MWMore)
- (void)removeObjectsAtIndexes:(NSIndexSet *)i { for (NSUInteger x = [i lastIndex]; x != NSNotFound; x = [i indexLessThanIndex:x]) [self removeObjectAtIndex:x]; }
- (void)sortUsingFunction:(NSInteger (*)(id, id, void *))f context:(void *)ctx { [self sortUsingComparator:^NSComparisonResult(id a, id b) { return (NSComparisonResult)f(a, b, ctx); }]; }
@end
@implementation NSArray (MWMore)
- (NSArray *)sortedArrayUsingFunction:(NSInteger (*)(id, id, void *))f context:(void *)ctx { return [self sortedArrayUsingComparator:^NSComparisonResult(id a, id b) { return (NSComparisonResult)f(a, b, ctx); }]; }
@end
@implementation NSObject (MWKeyPathSet)
- (void)setValue:(id)v forKeyPath:(NSString *)p {
    NSRange r = [p rangeOfString:@"."];
    if (r.location == NSNotFound) { [self setValue:v forKey:p]; return; }
    [[self valueForKey:[p substringToIndex:r.location]] setValue:v forKeyPath:[p substringFromIndex:NSMaxRange(r)]];
}
@end
@implementation NSString (MWTilde)
- (NSString *)stringByAbbreviatingWithTildeInPath {
    NSString *h = NSHomeDirectory();
    if ([self isEqualToString:h]) return @"~";
    if ([h length] && [self hasPrefix:[h stringByAppendingString:@"/"]]) return [@"~" stringByAppendingString:[self substringFromIndex:[h length]]];
    return self;
}
@end
@implementation NSProcessInfo (MWTermination)
- (void)disableSuddenTermination {} - (void)enableSuddenTermination {}
- (void)disableAutomaticTermination:(NSString *)r {} - (void)enableAutomaticTermination:(NSString *)r {}
- (BOOL)automaticTerminationSupportEnabled { return NO; } - (void)setAutomaticTerminationSupportEnabled:(BOOL)e {}
@end
@implementation NSTask (MWLaunched)
+ (NSTask *)launchedTaskWithLaunchPath:(NSString *)p arguments:(NSArray *)a { NSTask *t = [[[NSTask alloc] init] autorelease]; t.launchPath = p; t.arguments = a; [t launch]; return t; }
+ (NSTask *)launchedTaskWithExecutableURL:(NSURL *)u arguments:(NSArray *)a error:(NSError **)e terminationHandler:(void (^)(NSTask *))h {
    NSTask *t = [[[NSTask alloc] init] autorelease]; t.executableURL = u; t.arguments = a; t.terminationHandler = h;
    return [t launchAndReturnError:e] ? t : nil;
}
@end
@implementation NSSet (MWPerform)
- (void)makeObjectsPerformSelector:(SEL)s { for (id o in [[self copy] autorelease]) ((id (*)(id, SEL))objc_msgSend)(o, s); }
- (void)makeObjectsPerformSelector:(SEL)s withObject:(id)a { for (id o in [[self copy] autorelease]) ((id (*)(id, SEL, id))objc_msgSend)(o, s, a); }
@end
@implementation NSMutableURLRequest (MWService) - (void)setNetworkServiceType:(NSUInteger)t {} - (NSUInteger)networkServiceType { return 0; } @end
@implementation NSXMLNode (MWTree)
- (NSString *)URI { return nil; } - (NSString *)localName { return nil; } - (NSXMLNode *)nextSibling { return nil; }
- (NSXMLNode *)childAtIndex:(NSUInteger)i { return nil; } - (NSUInteger)childCount { return 0; } - (NSXMLNode *)parent { return nil; }
@end

/* ScriptingBridge (aliased to Foundation): no Apple Events here, so there is no application to script */
@interface SBObject : NSObject @end
@implementation SBObject - (id)get { return nil; } @end
@interface SBApplication : SBObject @end
@implementation SBApplication
+ (instancetype)applicationWithBundleIdentifier:(NSString *)i { return nil; }
+ (instancetype)applicationWithURL:(NSURL *)u { return nil; }
+ (instancetype)applicationWithProcessIdentifier:(int)p { return nil; }
- (BOOL)isRunning { return NO; }
@end
@interface SBElementArray : NSMutableArray @end
@implementation SBElementArray { NSMutableArray *_a; }
- (NSUInteger)count { return [_a count]; } - (id)objectAtIndex:(NSUInteger)i { return [_a objectAtIndex:i]; }
@end

NSString *const NSCalendarDayChangedNotification = @"NSCalendarDayChangedNotification";   /* ponytail: never posted */
NSString *const NSSystemClockDidChangeNotification = @"NSSystemClockDidChangeNotification";


/* ---------------- NSAffineTransform (its drawing methods are in AppKit, misc.m) ---------------- */
typedef struct { CGFloat m11, m12, m21, m22, tX, tY; } NSAffineTransformStruct;
@interface NSAffineTransform : NSObject <NSCopying> { @public NSAffineTransformStruct _t; } @end
@implementation NSAffineTransform
+ (instancetype)transform { return [[[self alloc] init] autorelease]; }
- (instancetype)init { if ((self = [super init])) { _t.m11 = _t.m22 = 1; } return self; }
- (instancetype)initWithTransform:(NSAffineTransform *)o { if ((self = [super init])) _t = o->_t; return self; }
- (id)copyWithZone:(NSZone *)z { return [[NSAffineTransform alloc] initWithTransform:self]; }
- (NSAffineTransformStruct)transformStruct { return _t; }
- (void)setTransformStruct:(NSAffineTransformStruct)t { _t = t; }
static NSAffineTransformStruct mul(NSAffineTransformStruct a, NSAffineTransformStruct b) {   /* a then b */
    NSAffineTransformStruct r = { a.m11 * b.m11 + a.m12 * b.m21, a.m11 * b.m12 + a.m12 * b.m22, a.m21 * b.m11 + a.m22 * b.m21,
                                  a.m21 * b.m12 + a.m22 * b.m22, a.tX * b.m11 + a.tY * b.m21 + b.tX, a.tX * b.m12 + a.tY * b.m22 + b.tY };
    return r;
}
- (void)appendTransform:(NSAffineTransform *)o { _t = mul(_t, o->_t); }
- (void)prependTransform:(NSAffineTransform *)o { _t = mul(o->_t, _t); }
- (void)translateXBy:(CGFloat)x yBy:(CGFloat)y { NSAffineTransformStruct m = {1, 0, 0, 1, x, y}; _t = mul(m, _t); }
- (void)scaleXBy:(CGFloat)x yBy:(CGFloat)y { NSAffineTransformStruct m = {x, 0, 0, y, 0, 0}; _t = mul(m, _t); }
- (void)scaleBy:(CGFloat)s { [self scaleXBy:s yBy:s]; }
- (void)rotateByRadians:(CGFloat)a { CGFloat c = __builtin_cos(a), s = __builtin_sin(a); NSAffineTransformStruct m = {c, s, -s, c, 0, 0}; _t = mul(m, _t); }
- (void)rotateByDegrees:(CGFloat)d { [self rotateByRadians:d * 3.14159265358979323846 / 180]; }
- (void)invert {
    CGFloat det = _t.m11 * _t.m22 - _t.m12 * _t.m21;
    if (det == 0) return;
    NSAffineTransformStruct r = { _t.m22 / det, -_t.m12 / det, -_t.m21 / det, _t.m11 / det, 0, 0 };
    r.tX = -(_t.tX * r.m11 + _t.tY * r.m21); r.tY = -(_t.tX * r.m12 + _t.tY * r.m22);
    _t = r;
}
- (NSPoint)transformPoint:(NSPoint)p { return NSMakePoint(p.x * _t.m11 + p.y * _t.m21 + _t.tX, p.x * _t.m12 + p.y * _t.m22 + _t.tY); }
- (NSSize)transformSize:(NSSize)s { return NSMakeSize(s.width * _t.m11 + s.height * _t.m21, s.width * _t.m12 + s.height * _t.m22); }
@end

/* ---------------- NSDataDetector: finds nothing (ponytail: links and dates when an app depends on them) ---------------- */
@interface NSDataDetector : NSRegularExpression @end
@implementation NSDataDetector { uint64_t _types; }
+ (instancetype)dataDetectorWithTypes:(uint64_t)t error:(NSError **)e { return [[[self alloc] initWithTypes:t error:e] autorelease]; }
- (instancetype)initWithTypes:(uint64_t)t error:(NSError **)e { if ((self = [super initWithPattern:@"x" options:0 error:e])) _types = t; return self; }
- (uint64_t)checkingTypes { return _types; }
- (NSArray *)matchesInString:(NSString *)s options:(NSMatchingOptions)o range:(NSRange)r { return @[]; }
- (NSTextCheckingResult *)firstMatchInString:(NSString *)s options:(NSMatchingOptions)o range:(NSRange)r { return nil; }
- (NSUInteger)numberOfMatchesInString:(NSString *)s options:(NSMatchingOptions)o range:(NSRange)r { return 0; }
- (NSRange)rangeOfFirstMatchInString:(NSString *)s options:(NSMatchingOptions)o range:(NSRange)r { return NSMakeRange(NSNotFound, 0); }
- (void)enumerateMatchesInString:(NSString *)s options:(NSMatchingOptions)o range:(NSRange)r usingBlock:(void (^)(NSTextCheckingResult *, NSMatchingFlags, BOOL *))b {}
@end

/* ---------------- NSDateIntervalFormatter: "start – end" with two date formatters ---------------- */
@interface NSDateIntervalFormatter : NSFormatter
@property NSDateFormatterStyle dateStyle, timeStyle;
@property(copy) NSLocale *locale; @property(copy) NSCalendar *calendar; @property(copy) NSTimeZone *timeZone; @property(copy) NSString *dateTemplate;
@end
@implementation NSDateIntervalFormatter
- (void)dealloc { [_locale release]; [_calendar release]; [_timeZone release]; [_dateTemplate release]; [super dealloc]; }
- (NSDateFormatter *)_mwFormatter:(NSDateFormatterStyle)ds {
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    if (_locale) f.locale = _locale;
    if (_timeZone) f.timeZone = _timeZone;
    if (_dateTemplate) [f setLocalizedDateFormatFromTemplate:_dateTemplate];
    else { f.dateStyle = ds; f.timeStyle = _timeStyle; }
    return f;
}
- (NSString *)stringFromDate:(NSDate *)a toDate:(NSDate *)b {
    if (!a || !b) return @"";
    NSCalendar *cal = _calendar ?: [NSCalendar currentCalendar];
    BOOL sameDay = [cal isDate:a inSameDayAsDate:b];
    NSString *s = [[self _mwFormatter:_dateStyle] stringFromDate:a];
    if ([a isEqualToDate:b]) return s;
    NSString *e = [[self _mwFormatter:sameDay && _timeStyle != NSDateFormatterNoStyle ? NSDateFormatterNoStyle : _dateStyle] stringFromDate:b];
    return [NSString stringWithFormat:@"%@ – %@", s, e];
}
- (NSString *)stringFromDateInterval:(id)i { return [self stringFromDate:[i valueForKey:@"startDate"] toDate:[i valueForKey:@"endDate"]]; }
- (NSString *)stringForObjectValue:(id)o { return nil; }
@end
