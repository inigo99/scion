#include <array>
/* msl.cpp — Metal Shading Language source -> metallib, for newLibraryWithSource:.
 *
 * MSL is C++14 with address spaces, vector types and [[attributes]]. clang's "C++ for OpenCL" mode already has the
 * address-space semantics MSL needs (a generic `this`, copies out of device memory), so:
 *   1. rewrite(): [[buffer(0)]] -> [[clang::annotate("air:buffer", (0))]], float4(a, b) -> ::__mw_make<metal::float4>(a, b),
 *      `constant T x [[function_constant(n)]];` -> extern, #include <metal_stdlib> dropped;
 *   2. clang (spir64, clc++2021) with metal_stdlib.h prepended -> LLVM IR. A consumer reads the air: annotations from the
 *      AST (entry points, argument and field attributes) and drops them before codegen sees them;
 *   3. airify(): each entry point gets a wrapper with Apple's AIR signature (flattened stage_in, struct return,
 *      textures/samplers as handles) plus the !air.vertex/fragment/kernel metadata air2spv reads; everything else is
 *      inlined (O2), generic pointers resolved (InferAddressSpaces), constexpr samplers become !air.sampler_states;
 *   4. pack(): one bitcode shared by all entries in an MTLB container, so the metallib path (air2spv) does the rest. */
#include "msl.h"

#include "clang/AST/ASTConsumer.h"
#include "clang/AST/ASTContext.h"
#include "clang/AST/Attr.h"
#include "clang/AST/DeclCXX.h"
#include "clang/AST/DeclTemplate.h"
#include "clang/AST/Mangle.h"
#include "clang/AST/RecordLayout.h"
#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Basic/DiagnosticOptions.h"
#include "clang/CodeGen/CodeGenAction.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Frontend/CompilerInvocation.h"
#include "clang/Frontend/MultiplexConsumer.h"
#include "clang/Frontend/TextDiagnosticPrinter.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Intrinsics.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/VirtualFileSystem.h"
#include "llvm/Transforms/InstCombine/InstCombine.h"
#include "llvm/Transforms/Scalar/InferAddressSpaces.h"

#include <cstring>
#include <map>
#include <mutex>
#include <regex>
#include <stdexcept>

using namespace clang;
extern const char kMslVersion[] = __DATE__ " " __TIME__;

namespace {
const char kStdlib[] =
#include "metal_stdlib.inc"
    ;

[[noreturn]] void fail(const std::string &m) { throw std::runtime_error(m); }

/* ====================================================================== 1. source rewrite */
bool idStart(char c) { return isalpha((unsigned char)c) || c == '_'; }
bool idChar(char c) { return isalnum((unsigned char)c) || c == '_'; }
std::string trim(const std::string &s) {
    size_t a = s.find_first_not_of(" \t\r\n"), b = s.find_last_not_of(" \t\r\n");
    return a == std::string::npos ? "" : s.substr(a, b - a + 1);
}
/* split at top-level commas */
std::vector<std::string> splitTop(const std::string &s) {
    std::vector<std::string> out;
    int depth = 0;
    std::string cur;
    for (char c : s) {
        if (c == '(' || c == '[' || c == '{') depth++;
        if (c == ')' || c == ']' || c == '}') depth--;
        if (c == ',' && depth == 0) { out.push_back(trim(cur)); cur.clear(); continue; }
        cur += c;
    }
    if (!trim(cur).empty()) out.push_back(trim(cur));
    return out;
}
bool isIdent(const std::string &s) {
    if (s.empty() || !idStart(s[0])) return false;
    for (char c : s) if (!idChar(c)) return false;
    return true;
}
std::string rewriteAttrs(const std::string &in, bool &isFunctionConstant) {
    static const char *keep[] = {"fallthrough", "maybe_unused", "nodiscard", "noreturn", "likely", "unlikely", "deprecated", "carries_dependency"};
    std::string out;
    for (auto &a : splitTop(in)) {
        std::string name = a, args;
        size_t p = a.find('(');
        if (p != std::string::npos) { name = trim(a.substr(0, p)); args = a.substr(p + 1, a.rfind(')') - p - 1); }
        bool std_ = name.find("::") != std::string::npos;
        for (auto *k : keep) std_ |= name == k;
        if (!out.empty()) out += ", ";
        if (std_) { out += a; continue; }
        if (name == "function_constant") isFunctionConstant = true;
        out += "clang::annotate(\"air:" + name + "\"";
        for (auto &arg : splitTop(args)) {
            bool asString = isIdent(arg) && (name == "user" || name == "depth" || name == "function_constant" || name == "patch");
            out += asString ? ", \"" + arg + "\"" : ", (" + arg + ")";
        }
        out += ")";
    }
    return out;
}
const std::regex &vecRe() {
    static const std::regex r("(packed_)?(float|half|int|uint|short|ushort|char|uchar|bool|long|ulong)[234]");
    return r;
}
std::string rewrite(const std::string &s) {
    std::string out;
    out.reserve(s.size() + s.size() / 4);
    size_t i = 0, n = s.size(), stmtStart = 0;
    bool lineStart = true;
    auto copyUntil = [&](const char *end) {
        size_t e = s.find(end, i);
        e = e == std::string::npos ? n : e + strlen(end);
        out.append(s, i, e - i);
        i = e;
    };
    while (i < n) {
        char c = s[i];
        if (c == '/' && i + 1 < n && s[i + 1] == '/') { copyUntil("\n"); lineStart = true; continue; }
        if (c == '/' && i + 1 < n && s[i + 1] == '*') { copyUntil("*/"); continue; }
        if (c == '"' || c == '\'') {
            size_t j = i + 1;
            while (j < n && s[j] != c) j += s[j] == '\\' ? 2 : 1;
            out.append(s, i, std::min(n, j + 1) - i);
            i = j + 1;
            continue;
        }
        if (lineStart && c == '#') { /* preprocessor line: drop the Metal headers, keep the rest */
            size_t e = i;
            while (e < n && s[e] != '\n') e += (s[e] == '\\' && e + 1 < n) ? 2 : 1;
            std::string line = s.substr(i, e - i);
            static const std::regex inc("#\\s*include\\s*<(metal_[a-z_]+|simd/[a-z_/]+\\.h|TargetConditionals\\.h)>.*");
            bool drop = std::regex_match(line, inc);
            if (!drop && line.find("#include") != std::string::npos) drop = false;
            if (!drop) {
                /* attributes inside #define bodies still need the rewrite: process the line's tail normally */
                size_t d = line.find("define");
                if (d == std::string::npos || line.find("[[") == std::string::npos) { out += line; i = e; stmtStart = out.size(); continue; }
            } else {
                i = e;
                stmtStart = out.size();
                continue;
            }
        }
        if (c == '\n') lineStart = true;
        else if (!isspace((unsigned char)c)) lineStart = false;
        if (c == '[' && i + 1 < n && s[i + 1] == '[') {
            int depth = 0;
            size_t j = i + 2;
            for (; j + 1 < n; j++) {
                if (s[j] == '(' || s[j] == '[') depth++;
                else if (s[j] == ')') depth--;
                else if (s[j] == ']') { if (depth == 0 && s[j + 1] == ']') break; depth--; }
            }
            if (j + 1 >= n) { out += c; i++; continue; }
            bool fc = false;
            out += "[[" + rewriteAttrs(s.substr(i + 2, j - i - 2), fc) + "]]";
            i = j + 2;
            if (fc) { /* `constant T name [[function_constant(n)]];`: a declaration without a value */
                size_t k = i;
                while (k < n && isspace((unsigned char)s[k])) k++;
                if (k < n && s[k] == ';') {
                    size_t st = stmtStart;
                    while (st < out.size() && isspace((unsigned char)out[st])) st++;
                    out.insert(st, "extern ");
                }
            }
            continue;
        }
        if (c == ';' || c == '{' || c == '}') { out += c; i++; stmtStart = out.size(); continue; }
        if (idStart(c) && (i == 0 || !idChar(s[i - 1]))) {
            size_t j = i;
            while (j < n && idChar(s[j])) j++;
            std::string w = s.substr(i, j - i);
            size_t k = j;
            while (k < n && (s[k] == ' ' || s[k] == '\t')) k++;
            size_t pb = out.size();
            while (pb > 0 && isspace((unsigned char)out[pb - 1])) pb--;
            bool member = pb > 0 && (out[pb - 1] == '.' || (out[pb - 1] == '>' && pb > 1 && out[pb - 2] == '-'));
            if (k < n && s[k] == '(' && !member && std::regex_match(w, vecRe())) {
                if (out.size() >= 7 && out.compare(out.size() - 7, 7, "metal::") == 0) out.resize(out.size() - 7);
                out += "::__mw_make<metal::" + w + ">";
            } else if (w == "vec" && k < n && s[k] == '<' && !member) { /* vec<T, N>(a, b) */
                int depth = 0;
                size_t e = k;
                for (; e < n; e++) {
                    if (s[e] == '<') depth++;
                    else if (s[e] == '>' && --depth == 0) break;
                    else if (s[e] == ';' || s[e] == '{') break;
                }
                size_t p = e + 1;
                while (p < n && isspace((unsigned char)s[p])) p++;
                if (e < n && s[e] == '>' && p < n && s[p] == '(') {
                    if (out.size() >= 7 && out.compare(out.size() - 7, 7, "metal::") == 0) out.resize(out.size() - 7);
                    out += "::__mw_make<metal::vec" + s.substr(k, e + 1 - k) + ">";
                    i = e + 1;
                    continue;
                }
                out += w;
            } else
                out += w;
            i = j;
            continue;
        }
        out += c;
        i++;
    }
    /* argument buffer samplers are 8-byte resource IDs: retype [[id(n)]] sampler fields (single, C arrays, array<sampler, N>) */
    static const std::regex abs1("\\bsampler(\\s+\\w+\\s*(\\[[^\\]]*\\]\\s*)?\\[\\[clang::annotate\\(\"air:id\")"),
                            abs2("\\barray\\s*<\\s*sampler\\s*,([^>]*)>(\\s+\\w+\\s*\\[\\[clang::annotate\\(\"air:id\")");
    out = std::regex_replace(out, abs1, "__mw_ab_sampler$1");
    out = std::regex_replace(out, abs2, "array<__mw_ab_sampler,$1>$2");
    return out;
}

/* ====================================================================== 2. AST: entry points and attributes */
struct AttrArg { bool isStr = false; std::string s; int64_t v = 0; };
struct MAttr { std::string name; std::vector<AttrArg> args; };
using Attrs = std::vector<MAttr>;
const MAttr *findAttr(const Attrs &a, const std::string &n) {
    for (auto &x : a) if (x.name == n) return &x;
    return nullptr;
}
int64_t argInt(const MAttr *a, size_t i = 0, int64_t def = 0) { return a && i < a->args.size() && !a->args[i].isStr ? a->args[i].v : def; }
std::string argStr(const MAttr *a, size_t i = 0) {
    if (!a || i >= a->args.size()) return "";
    return a->args[i].isStr ? a->args[i].s : std::to_string(a->args[i].v);
}

struct Field { std::string name, typeName; Attrs attrs; uint64_t offset = 0; };
struct Arg {
    enum Kind { Buffer, Builtin, StageIn, Texture, Sampler } kind = Builtin;
    std::string name, typeName;
    Attrs attrs;
    std::vector<Field> fields; /* stage_in */
    int access = 0;            /* textures: 0 sample, 1 read, 2 write, 3 read_write */
    unsigned count = 1;        /* arrays of textures / samplers: one AIR argument per element */
    uint64_t stride = 0;
    /* buffers: an argument buffer's [[id(n)]] fields {id, byte offset, kind (0 data, 1 buffer, 2 texture, 3 sampler), count}, and its size */
    std::vector<std::array<int64_t, 4>> ids;
    uint64_t size = 0;
};
struct Entry {
    std::string name, mangled;
    int stage = 2; /* 0 vertex, 1 fragment, 2 kernel */
    std::vector<Arg> args;
    bool retVoid = true, retRecord = false;
    std::string retTypeName;
    std::vector<Field> ret;
};
struct FConst { std::string mangled, name, typeName; int64_t index; };

struct Collector : ASTConsumer, RecursiveASTVisitor<Collector> {
    std::map<const Decl *, Attrs> attrs;
    std::vector<const FunctionDecl *> entryDecls;
    std::vector<const VarDecl *> fcDecls;
    std::vector<Entry> &entries;
    std::vector<FConst> &fconsts;
    ASTContext *ctx = nullptr;
    std::string error;
    Collector(std::vector<Entry> &e, std::vector<FConst> &f) : entries(e), fconsts(f) {}

    void Initialize(ASTContext &c) override { ctx = &c; }
    bool HandleTopLevelDecl(DeclGroupRef g) override {
        for (Decl *d : g) TraverseDecl(d);
        return true;
    }
    bool shouldVisitTemplateInstantiations() const { return false; }
    bool VisitDecl(Decl *D) {
        if (!D->hasAttrs()) return true;
        Attrs mine;
        AttrVec &v = D->getAttrs();
        for (auto it = v.begin(); it != v.end();) {
            auto *aa = dyn_cast<AnnotateAttr>(*it);
            if (!aa || !aa->getAnnotation().starts_with("air:")) { ++it; continue; }
            MAttr ma;
            ma.name = aa->getAnnotation().drop_front(4).str();
            for (Expr *e : aa->args()) {
                AttrArg arg;
                e = e->IgnoreParenImpCasts();
                if (auto *sl = dyn_cast<StringLiteral>(e)) { arg.isStr = true; arg.s = sl->getString().str(); }
                else if (auto r = e->getIntegerConstantExpr(*ctx)) arg.v = r->getExtValue();
                else if (auto *ce = dyn_cast<ConstantExpr>(e); ce && ce->hasAPValueResult() && ce->getAPValueResult().isInt()) arg.v = ce->getAPValueResult().getInt().getExtValue();
                ma.args.push_back(arg);
            }
            mine.push_back(ma);
            it = v.erase(it);
        }
        if (v.empty()) D->dropAttrs();
        if (mine.empty()) return true;
        auto &dst = attrs[D];
        dst.insert(dst.end(), mine.begin(), mine.end());
        if (auto *fd = dyn_cast<FunctionDecl>(D); fd && (findAttr(dst, "kernel") || findAttr(dst, "vertex") || findAttr(dst, "fragment")) && fd->hasBody())
            entryDecls.push_back(fd);
        if (auto *vd = dyn_cast<VarDecl>(D); vd && vd->hasGlobalStorage() && findAttr(dst, "function_constant")) fcDecls.push_back(vd);
        return true;
    }

    std::string mangle(const NamedDecl *d) {
        std::unique_ptr<MangleContext> mc(ctx->createMangleContext());
        if (!mc->shouldMangleDeclName(d)) return d->getName().str();
        std::string s;
        llvm::raw_string_ostream os(s);
        if (auto *fd = dyn_cast<FunctionDecl>(d)) mc->mangleName(GlobalDecl(fd), os);
        else mc->mangleName(GlobalDecl(cast<VarDecl>(d)), os);
        return os.str();
    }
    QualType bare(QualType t) { return ctx->removeAddrSpaceQualType(t.getCanonicalType().getUnqualifiedType()).getUnqualifiedType(); }
    std::string tname(QualType t) {
        PrintingPolicy pp(ctx->getLangOpts());
        pp.SuppressScope = true;
        pp.SuppressTagKeyword = true;
        return bare(t).getAsString(pp);
    }
    std::vector<Field> fieldsOf(QualType t, const char *what) {
        std::vector<Field> out;
        auto *rd = bare(t)->getAsRecordDecl();
        if (!rd) return out;
        if (auto *cxx = dyn_cast<CXXRecordDecl>(rd); cxx && cxx->getNumBases()) fail(std::string(what) + ": structures with base classes are not supported");
        const ASTRecordLayout &L = ctx->getASTRecordLayout(rd);
        for (const FieldDecl *f : rd->fields()) {
            Field fl;
            fl.name = f->getName().str();
            fl.typeName = tname(f->getType());
            fl.offset = L.getFieldOffset(f->getFieldIndex()) / 8;
            auto it = attrs.find(f);
            if (it != attrs.end()) fl.attrs = it->second;
            /* a field annotated in a template pattern: the instantiation's field has the pattern's attributes */
            if (it == attrs.end())
                if (auto *ts = dyn_cast<ClassTemplateSpecializationDecl>(rd))
                    if (auto *pat = ts->getSpecializedTemplate()->getTemplatedDecl())
                        for (const FieldDecl *pf : pat->fields())
                            if (pf->getName() == f->getName()) { auto pit = attrs.find(pf); if (pit != attrs.end()) fl.attrs = pit->second; }
            if (bare(f->getType())->isRecordType() && !bare(f->getType())->isVectorType()) {
                auto *frd = bare(f->getType())->getAsRecordDecl();
                bool isMatrixOrArray = frd && (frd->getName() == "matrix" || frd->getName() == "packed3" || frd->getName() == "array");
                if (!isMatrixOrArray) fail(std::string(what) + ": field " + fl.name + " is a nested structure (not supported)");
            }
            out.push_back(fl);
        }
        return out;
    }

    /* an argument buffer (Tier 2: a plain struct whose resources are 8-byte addresses or resource IDs) */
    void argumentIds(QualType t, Arg &a) {
        auto *rd = bare(t)->getAsRecordDecl();
        if (!rd || !rd->getDefinition()) return;
        const ASTRecordLayout &L = ctx->getASTRecordLayout(rd);
        a.size = uint64_t(L.getSize().getQuantity());
        for (const FieldDecl *f : rd->fields()) {
            auto it = attrs.find(f);
            const MAttr *id = it != attrs.end() ? findAttr(it->second, "id") : nullptr;
            if (!id) continue;
            QualType ft = bare(f->getType());
            int64_t count = 1;
            if (auto *at = ctx->getAsConstantArrayType(ft)) { count = int64_t(at->getSize().getZExtValue()); ft = bare(at->getElementType()); }
            else if (auto *ar = dyn_cast_or_null<ClassTemplateSpecializationDecl>(ft->getAsRecordDecl()); ar && ar->getName() == "array") {
                ft = bare(ar->getTemplateArgs()[0].getAsType()); count = int64_t(ar->getTemplateArgs()[1].getAsIntegral().getZExtValue());
            }
            std::string cls = ft->getAsRecordDecl() ? ft->getAsRecordDecl()->getName().str() : "";
            int64_t kind = ft->isPointerType() ? 1 : (cls.rfind("texture", 0) == 0 || cls.rfind("depth", 0) == 0) ? 2 : (cls == "sampler" || cls == "__mw_ab_sampler") ? 3 : 0;
            a.ids.push_back({argInt(id), int64_t(L.getFieldOffset(f->getFieldIndex()) / 8), kind, count});
        }
    }

    void HandleTranslationUnit(ASTContext &) override {
        try {
            for (auto *vd : fcDecls) {
                FConst fc;
                fc.mangled = mangle(vd);
                fc.name = vd->getName().str();
                fc.typeName = tname(vd->getType());
                fc.index = argInt(findAttr(attrs[vd], "function_constant"));
                fconsts.push_back(fc);
            }
            for (auto *fd : entryDecls) {
                Entry e;
                const Attrs &fa = attrs[fd];
                e.name = fd->getName().str();
                e.mangled = mangle(fd);
                e.stage = findAttr(fa, "vertex") ? 0 : findAttr(fa, "fragment") ? 1 : 2;
                for (const ParmVarDecl *p : fd->parameters()) {
                    Arg a;
                    a.name = p->getName().str();
                    a.typeName = tname(p->getType());
                    auto it = attrs.find(p);
                    if (it != attrs.end()) a.attrs = it->second;
                    QualType t = p->getType();
                    if (findAttr(a.attrs, "buffer")) {
                        a.kind = Arg::Buffer;
                        if (t->isPointerType() || t->isReferenceType()) { a.typeName = tname(t->getPointeeType()); argumentIds(t->getPointeeType(), a); }
                    } else if (findAttr(a.attrs, "texture") || findAttr(a.attrs, "sampler")) {
                        a.kind = findAttr(a.attrs, "texture") ? Arg::Texture : Arg::Sampler;
                        QualType et = bare(t);
                        if (et->isPointerType()) et = bare(et->getPointeeType()); /* T x[N] as a parameter */
                        if (auto *at = ctx->getAsConstantArrayType(bare(p->getOriginalType()))) { a.count = unsigned(at->getSize().getZExtValue()); et = bare(at->getElementType()); }
                        else if (auto *ar = dyn_cast_or_null<ClassTemplateSpecializationDecl>(et->getAsRecordDecl()); ar && ar->getName() == "array") {
                            auto &ta = ar->getTemplateArgs();
                            et = bare(ta[0].getAsType());
                            a.count = unsigned(ta[1].getAsIntegral().getZExtValue());
                        }
                        a.stride = ctx->getTypeSize(et) / 8;
                        if (a.kind == Arg::Sampler) { e.args.push_back(a); continue; }
                        auto *rd = et->getAsRecordDecl();
                        std::string cls = rd ? rd->getName().str() : "texture2d", elem = "float";
                        if (auto *ts = dyn_cast_or_null<ClassTemplateSpecializationDecl>(rd)) {
                            auto &ta = ts->getTemplateArgs();
                            if (ta.size() > 0 && ta[0].getKind() == TemplateArgument::Type) elem = tname(ta[0].getAsType());
                            if (ta.size() > 1 && ta[1].getKind() == TemplateArgument::Integral) a.access = int(ta[1].getAsIntegral().getExtValue());
                            else if (cls.find("_ms") != std::string::npos) a.access = 1;
                        }
                        static const char *accName[] = {"sample", "read", "write", "read_write"};
                        a.typeName = cls + "<" + elem + ", " + accName[a.access & 3] + ">";
                    } else if (findAttr(a.attrs, "stage_in")) {
                        a.kind = Arg::StageIn;
                        a.fields = fieldsOf(t, a.name.c_str());
                    } else if (a.attrs.empty()) {
                        fail("argument '" + a.name + "' of " + e.name + " has no attribute (buffer, texture, stage_in...)");
                    } else
                        a.kind = Arg::Builtin;
                    e.args.push_back(a);
                }
                QualType rt = fd->getReturnType();
                e.retVoid = rt->isVoidType();
                e.retTypeName = tname(rt);
                if (!e.retVoid && bare(rt)->isRecordType()) {
                    e.retRecord = true;
                    e.ret = fieldsOf(rt, e.name.c_str());
                }
                entries.push_back(e);
            }
        } catch (const std::exception &ex) {
            error = ex.what();
        }
    }
};

struct Action : EmitLLVMOnlyAction {
    Collector *col;
    Action(llvm::LLVMContext *c, Collector *cl) : EmitLLVMOnlyAction(c), col(cl) {}
    std::unique_ptr<ASTConsumer> CreateASTConsumer(CompilerInstance &CI, StringRef f) override {
        std::vector<std::unique_ptr<ASTConsumer>> v;
        struct Fwd : ASTConsumer { /* the collector outlives the action */
            Collector *c;
            Fwd(Collector *x) : c(x) {}
            void Initialize(ASTContext &x) override { c->Initialize(x); }
            bool HandleTopLevelDecl(DeclGroupRef g) override { return c->HandleTopLevelDecl(g); }
            void HandleTranslationUnit(ASTContext &x) override { c->HandleTranslationUnit(x); }
        };
        v.push_back(std::make_unique<Fwd>(col)); /* first: annotations are gone before codegen sees a declaration */
        v.push_back(EmitLLVMOnlyAction::CreateASTConsumer(CI, f));
        return std::make_unique<MultiplexConsumer>(std::move(v));
    }
};

/* ====================================================================== 3. AIR entry points */
using namespace llvm;
using llvm::Module;
using llvm::Type;
using llvm::PointerType;
using llvm::FunctionType;
using llvm::ArrayType;
using llvm::StructType;
using llvm::Function;
using llvm::Argument;
using llvm::Value;
using llvm::Constant;
MDString *S(LLVMContext &c, const std::string &s) { return MDString::get(c, s); }
Metadata *I32(LLVMContext &c, int64_t v) { return ConstantAsMetadata::get(ConstantInt::get(Type::getInt32Ty(c), v)); }

/* element of an LLVM struct at a byte offset */
Type *typeAt(const DataLayout &DL, StructType *st, uint64_t off, unsigned *idx = nullptr) {
    const StructLayout *sl = DL.getStructLayout(st);
    if (off >= sl->getSizeInBytes()) fail("field outside the structure");
    unsigned i = sl->getElementContainingOffset(off);
    if (sl->getElementOffset(i) != off) fail("field not aligned with the LLVM structure");
    if (idx) *idx = i;
    return st->getElementType(i);
}

std::string userName(const Field &f) {
    if (auto *u = findAttr(f.attrs, "user")) return "user(" + argStr(u) + ")";
    return "user(" + f.name + ")";
}

void airify(Module &M, std::vector<Entry> &entries, std::vector<FConst> &fconsts) {
    LLVMContext &C = M.getContext();
    const DataLayout &DL = M.getDataLayout();
    Type *i8 = Type::getInt8Ty(C), *i64 = Type::getInt64Ty(C);
    PointerType *pDev = PointerType::get(C, 1), *pConst = PointerType::get(C, 2);
    std::map<int, std::vector<Metadata *>> stageMD;
    std::vector<Function *> wrappers;

    for (auto &e : entries) {
        Function *orig = M.getFunction(e.mangled);
        if (!orig || orig->isDeclaration()) fail("function " + e.name + " was not generated");
        if (orig->getName() == e.name) orig->setName(e.name + ".msl");
        unsigned k = 0;
        StructType *sretTy = nullptr;
        if (orig->hasStructRetAttr()) { sretTy = dyn_cast<StructType>(orig->getParamStructRetType(0)); k = 1; }
        if (orig->arg_size() != k + e.args.size()) fail(e.name + ": unexpected arguments in the IR");

        /* wrapper signature */
        std::vector<Type *> wtys;
        std::vector<Metadata *> pmd;
        auto common = [&](std::vector<Metadata *> &v, const std::string &tn, const std::string &an) {
            v.push_back(S(C, "air.arg_type_name")); v.push_back(S(C, tn));
            v.push_back(S(C, "air.arg_name")); v.push_back(S(C, an));
        };
        for (size_t ai = 0; ai < e.args.size(); ai++) {
            Arg &a = e.args[ai];
            Argument *P = orig->getArg(k + ai);
            std::vector<Metadata *> v;
            auto idx = [&] { return I32(C, wtys.size()); };
            const MAttr *fcA = findAttr(a.attrs, "function_constant");
            auto fcPrefix = [&] { if (fcA) { v.push_back(S(C, "air.function_constant")); v.push_back(S(C, argStr(fcA))); } };
            switch (a.kind) {
            case Arg::Buffer: {
                v = {idx()};
                fcPrefix();
                v.push_back(S(C, "air.buffer"));
                v.push_back(S(C, "air.location_index")); v.push_back(I32(C, argInt(findAttr(a.attrs, "buffer")))); v.push_back(I32(C, 1));
                v.push_back(S(C, "air.read_write"));
                if (a.size) { v.push_back(S(C, "air.arg_type_size")); v.push_back(I32(C, int64_t(a.size))); }
                if (!a.ids.empty()) { /* scion: the argument buffer layout, for MTLArgumentEncoder */
                    std::vector<Metadata *> ids;
                    for (auto &x : a.ids) for (int64_t w : x) ids.push_back(I32(C, w));
                    v.push_back(S(C, "mw.argument_ids")); v.push_back(MDNode::get(C, ids));
                }
                common(v, a.typeName, a.name);
                wtys.push_back(P->getType());
                pmd.push_back(MDNode::get(C, v));
                break;
            }
            case Arg::Texture:
                for (unsigned el = 0; el < a.count; el++) {
                    v = {idx()};
                    fcPrefix();
                    v.push_back(S(C, "air.texture"));
                    v.push_back(S(C, "air.location_index")); v.push_back(I32(C, argInt(findAttr(a.attrs, "texture")) + el)); v.push_back(I32(C, 1));
                    static const char *acc[] = {"air.sample", "air.read", "air.write", "air.read_write"};
                    v.push_back(S(C, acc[a.access & 3]));
                    common(v, a.typeName, a.name);
                    wtys.push_back(pDev);
                    pmd.push_back(MDNode::get(C, v));
                }
                break;
            case Arg::Sampler:
                for (unsigned el = 0; el < a.count; el++) {
                    v = {idx(), S(C, "air.sampler"), S(C, "air.location_index"), I32(C, argInt(findAttr(a.attrs, "sampler")) + el), I32(C, 1)};
                    common(v, "sampler", a.name);
                    wtys.push_back(pConst);
                    pmd.push_back(MDNode::get(C, v));
                }
                break;
            case Arg::Builtin: {
                v = {idx(), S(C, "air." + a.attrs[0].name)};
                common(v, a.typeName, a.name);
                wtys.push_back(P->getType());
                pmd.push_back(MDNode::get(C, v));
                break;
            }
            case Arg::StageIn: {
                auto *st = dyn_cast<StructType>(P->hasByValAttr() ? P->getParamByValType() : P->getType());
                if (!st) fail(e.name + ": stage_in is not a structure");
                for (auto &f : a.fields) {
                    std::vector<Metadata *> fv{idx()};
                    if (e.stage == 0) {
                        const MAttr *at = findAttr(f.attrs, "attribute");
                        if (!at) fail(e.name + ": stage_in field " + f.name + " has no [[attribute(n)]]");
                        fv.push_back(S(C, "air.vertex_input"));
                        fv.push_back(S(C, "air.location_index")); fv.push_back(I32(C, argInt(at))); fv.push_back(I32(C, 1));
                    } else {
                        static const char *builtins[] = {"position", "front_facing", "sample_id", "point_coord", "primitive_id", "render_target_array_index", "viewport_array_index"};
                        std::string b;
                        for (auto *bn : builtins) if (findAttr(f.attrs, bn)) b = bn;
                        if (!b.empty()) fv.push_back(S(C, "air." + b));
                        else {
                            fv.push_back(S(C, "air.fragment_input"));
                            fv.push_back(S(C, userName(f)));
                        }
                        bool flat = findAttr(f.attrs, "flat"), np = findAttr(f.attrs, "center_no_perspective") || findAttr(f.attrs, "centroid_no_perspective") || findAttr(f.attrs, "sample_no_perspective");
                        bool cen = findAttr(f.attrs, "centroid_perspective") || findAttr(f.attrs, "centroid_no_perspective"), smp = findAttr(f.attrs, "sample_perspective") || findAttr(f.attrs, "sample_no_perspective");
                        if (flat) fv.push_back(S(C, "air.flat"));
                        else {
                            fv.push_back(S(C, cen ? "air.centroid" : smp ? "air.sample" : "air.center"));
                            fv.push_back(S(C, np || !b.empty() ? "air.no_perspective" : "air.perspective"));
                        }
                    }
                    common(fv, f.typeName, f.name);
                    wtys.push_back(typeAt(DL, st, f.offset));
                    pmd.push_back(MDNode::get(C, fv));
                }
                break;
            }
            }
        }
        /* return */
        Type *rty = Type::getVoidTy(C);
        std::vector<Metadata *> rmd;
        std::vector<std::pair<uint64_t, Type *>> outFields;
        if (!e.retVoid) {
            auto outMD = [&](const Field &f, bool implicitOnly) {
                std::vector<Metadata *> v;
                if (e.stage == 0) {
                    if (findAttr(f.attrs, "position") || implicitOnly) v = {S(C, "air.position")};
                    else if (findAttr(f.attrs, "point_size")) v = {S(C, "air.point_size")};
                    else if (findAttr(f.attrs, "clip_distance")) v = {S(C, "air.clip_distance")};
                    else if (findAttr(f.attrs, "render_target_array_index")) v = {S(C, "air.render_target_array_index")};
                    else if (findAttr(f.attrs, "viewport_array_index")) v = {S(C, "air.viewport_array_index")};
                    else v = {S(C, "air.vertex_output"), S(C, userName(f))};
                } else if (e.stage == 1) {
                    if (auto *col = findAttr(f.attrs, "color")) v = {S(C, "air.render_target"), I32(C, argInt(col)), I32(C, argInt(findAttr(f.attrs, "index")))};
                    else if (auto *d = findAttr(f.attrs, "depth")) v = {S(C, "air.depth"), S(C, "air.depth_qualifier"), S(C, "air." + argStr(d))};
                    else if (implicitOnly) v = {S(C, "air.render_target"), I32(C, 0), I32(C, 0)};
                    else fail(e.name + ": output " + f.name + " has no [[color(n)]] / [[depth]]");
                } else
                    fail(e.name + ": a kernel function does not return values");
                v.push_back(S(C, "air.arg_type_name")); v.push_back(S(C, f.typeName));
                v.push_back(S(C, "air.arg_name")); v.push_back(S(C, f.name));
                rmd.push_back(MDNode::get(C, v));
            };
            if (e.retRecord) {
                StructType *st = sretTy ? sretTy : dyn_cast<StructType>(orig->getReturnType());
                if (!st) fail(e.name + ": unexpected return type");
                std::vector<Type *> ft;
                for (auto &f : e.ret) {
                    Type *t = typeAt(DL, st, f.offset);
                    if (e.stage == 0 && findAttr(f.attrs, "invariant")) {}
                    outFields.push_back({f.offset, t});
                    ft.push_back(t);
                    outMD(f, false);
                }
                rty = StructType::get(C, ft);
            } else {
                rty = orig->getReturnType();
                Field f;
                f.name = "out";
                f.typeName = e.retTypeName;
                outMD(f, true);
            }
        }

        Function *W = Function::Create(FunctionType::get(rty, wtys, false), GlobalValue::ExternalLinkage, e.name, &M);
        BasicBlock *bb = BasicBlock::Create(C, "entry", W);
        IRBuilder<> B(bb);
        std::vector<Value *> callArgs;
        AllocaInst *sret = nullptr;
        if (sretTy) { sret = B.CreateAlloca(sretTy); callArgs.push_back(sret); }
        unsigned wi = 0;
        for (size_t ai = 0; ai < e.args.size(); ai++) {
            Arg &a = e.args[ai];
            Argument *P = orig->getArg(k + ai);
            if (a.kind == Arg::Buffer || a.kind == Arg::Builtin) { callArgs.push_back(W->getArg(wi++)); continue; }
            if (a.kind == Arg::StageIn) {
                Type *st = P->hasByValAttr() ? P->getParamByValType() : P->getType();
                AllocaInst *tmp = B.CreateAlloca(st);
                for (auto &f : a.fields) B.CreateStore(W->getArg(wi++), B.CreateConstInBoundsGEP1_64(i8, tmp, f.offset));
                callArgs.push_back(P->hasByValAttr() ? (Value *)tmp : B.CreateLoad(st, tmp));
                continue;
            }
            /* texture / sampler objects: { handle, [state] } */
            if (a.count > 1) { /* arrays: every element's handle at its offset */
                bool byval = P->hasByValAttr();
                Type *at = byval ? P->getParamByValType() : (Type *)ArrayType::get(i8, a.count * a.stride);
                AllocaInst *tmp = B.CreateAlloca(at);
                B.CreateStore(Constant::getNullValue(at), tmp);
                for (unsigned el = 0; el < a.count; el++) B.CreateStore(W->getArg(wi++), B.CreateConstInBoundsGEP1_64(i8, tmp, el * a.stride));
                callArgs.push_back(byval ? (Value *)tmp : P->getType()->isPointerTy() ? B.CreatePointerBitCastOrAddrSpaceCast(tmp, P->getType()) : (Value *)B.CreateLoad(at, tmp));
                continue;
            }
            Value *h = W->getArg(wi++);
            if (!P->hasByValAttr()) { callArgs.push_back(P->getType()->isPointerTy() ? h : (Value *)B.CreateInsertValue(PoisonValue::get(P->getType()), h, {0})); continue; }
            Type *st = P->getParamByValType();
            AllocaInst *tmp = B.CreateAlloca(st);
            B.CreateStore(Constant::getNullValue(st), tmp);
            B.CreateStore(h, tmp);
            callArgs.push_back(tmp);
        }
        CallInst *call = B.CreateCall(orig, callArgs);
        call->setCallingConv(orig->getCallingConv());
        for (unsigned i = 0; i < orig->arg_size(); i++)
            if (orig->getArg(i)->hasByValAttr()) call->addParamAttr(i, Attribute::getWithByValType(C, orig->getArg(i)->getParamByValType()));
            else if (orig->getArg(i)->hasStructRetAttr()) call->addParamAttr(i, Attribute::getWithStructRetType(C, sretTy));
        if (e.retVoid) B.CreateRetVoid();
        else if (e.retRecord) {
            Value *rv = PoisonValue::get(rty);
            for (unsigned i = 0; i < outFields.size(); i++) {
                Value *fv;
                if (sret) fv = B.CreateLoad(outFields[i].second, B.CreateConstInBoundsGEP1_64(i8, sret, outFields[i].first));
                else {
                    unsigned ei;
                    typeAt(DL, cast<StructType>(orig->getReturnType()), outFields[i].first, &ei);
                    fv = B.CreateExtractValue(call, {ei});
                }
                rv = B.CreateInsertValue(rv, fv, {i});
            }
            B.CreateRet(rv);
        } else
            B.CreateRet(call);
        wrappers.push_back(W);
        stageMD[e.stage].push_back(MDNode::get(C, {ValueAsMetadata::get(W), MDNode::get(C, rmd), MDNode::get(C, pmd)}));
    }

    /* everything but the entry points is inlined */
    for (Function &F : M) {
        if (F.isDeclaration() || std::find(wrappers.begin(), wrappers.end(), &F) != wrappers.end()) continue;
        F.setLinkage(GlobalValue::InternalLinkage);
        F.removeFnAttr(Attribute::NoInline);
        F.removeFnAttr(Attribute::OptimizeNone);
        F.addFnAttr(Attribute::AlwaysInline);
    }
    for (auto &[stage, nodes] : stageMD) {
        static const char *names[] = {"air.vertex", "air.fragment", "air.kernel"};
        NamedMDNode *nm = M.getOrInsertNamedMetadata(names[stage]);
        for (auto *n : nodes) nm->addOperand(cast<MDNode>(n));
    }

    /* O2 without vectorization, then generic (AS 4) pointers back to their real address space */
    {
        PipelineTuningOptions PTO;
        PTO.LoopVectorization = false;
        PTO.SLPVectorization = false;
        PassBuilder PB(nullptr, PTO);
        LoopAnalysisManager LAM;
        FunctionAnalysisManager FAM;
        CGSCCAnalysisManager CGAM;
        ModuleAnalysisManager MAM;
        PB.registerModuleAnalyses(MAM);
        PB.registerCGSCCAnalyses(CGAM);
        PB.registerFunctionAnalyses(FAM);
        PB.registerLoopAnalyses(LAM);
        PB.crossRegisterProxies(LAM, FAM, CGAM, MAM);
        ModulePassManager MPM = PB.buildPerModuleDefaultPipeline(OptimizationLevel::O2);
        FunctionPassManager FPM;
        FPM.addPass(InferAddressSpacesPass(4));
        FPM.addPass(InstCombinePass());
        MPM.addPass(createModuleToFunctionPassAdaptor(std::move(FPM)));
        MPM.run(M, MAM);
    }

    /* markers the translator has no use for */
    for (Function &F : M)
        if (F.getIntrinsicID() == Intrinsic::invariant_start || F.getIntrinsicID() == Intrinsic::invariant_end)
            for (User *u : make_early_inc_range(F.users()))
                if (auto *ci = dyn_cast<CallInst>(u)) { ci->replaceAllUsesWith(PoisonValue::get(ci->getType())); ci->eraseFromParent(); }
    /* samplers: __mw_sampler(handle, state) -> the argument, or a constexpr sampler global */
    if (Function *ms = M.getFunction("__mw_sampler")) {
        std::map<uint64_t, GlobalVariable *> states;
        NamedMDNode *ss = nullptr;
        for (User *u : make_early_inc_range(ms->users())) {
            auto *ci = dyn_cast<CallInst>(u);
            if (!ci) continue;
            Value *h = ci->getArgOperand(0), *st = ci->getArgOperand(1);
            Value *r = h;
            if (isa<ConstantPointerNull>(h)) {
                auto *c = dyn_cast<ConstantInt>(st);
                if (!c) fail("constexpr sampler with non-constant state");
                GlobalVariable *&g = states[c->getZExtValue()];
                if (!g) {
                    auto *at = ArrayType::get(i64, 2);
                    g = new GlobalVariable(M, at, true, GlobalValue::InternalLinkage, ConstantArray::get(at, {c, ConstantInt::get(i64, 0)}),
                                           "__air_sampler_state", nullptr, GlobalValue::NotThreadLocal, 2);
                    if (!ss) ss = M.getOrInsertNamedMetadata("air.sampler_states");
                    ss->addOperand(MDNode::get(C, {S(C, "air.sampler_state"), ValueAsMetadata::get(g)}));
                }
                r = g;
            }
            ci->replaceAllUsesWith(r);
            ci->eraseFromParent();
        }
    }
    /* function constants */
    NamedMDNode *fcm = nullptr;
    for (auto &fc : fconsts) {
        GlobalVariable *g = M.getGlobalVariable(fc.mangled, true);
        if (!g) continue; /* unused */
        if (!fcm) fcm = M.getOrInsertNamedMetadata("air.function_constants");
        fcm->addOperand(MDNode::get(C, {ValueAsMetadata::get(g), S(C, fc.typeName), S(C, fc.name), I32(C, fc.index), ConstantAsMetadata::get(ConstantInt::getTrue(C))}));
    }
    NamedMDNode *ver = M.getOrInsertNamedMetadata("air.version");
    ver->addOperand(MDNode::get(C, {I32(C, 2), I32(C, 6), I32(C, 0)}));
}

/* ====================================================================== 4. MTLB container */
std::vector<uint8_t> pack(const std::vector<Entry> &entries, const SmallVectorImpl<char> &bc) {
    auto put = [](std::vector<uint8_t> &v, const void *p, size_t n) { v.insert(v.end(), (const uint8_t *)p, (const uint8_t *)p + n); };
    std::vector<uint8_t> list;
    uint32_t count = uint32_t(entries.size());
    put(list, &count, 4);
    for (auto &e : entries) {
        std::vector<uint8_t> t;
        uint16_t nl = uint16_t(e.name.size() + 1), one = 1, eight = 8, tf = 24;
        uint8_t type = uint8_t(e.stage == 0 ? 0 : e.stage == 1 ? 1 : 2);
        uint64_t sz = bc.size(), zero = 0;
        put(t, "NAME", 4); put(t, &nl, 2); put(t, e.name.c_str(), nl);
        put(t, "TYPE", 4); put(t, &one, 2); put(t, &type, 1);
        put(t, "MDSZ", 4); put(t, &eight, 2); put(t, &sz, 8);
        put(t, "OFFT", 4); put(t, &tf, 2); put(t, &zero, 8); put(t, &zero, 8); put(t, &zero, 8);
        put(t, "ENDT", 4);
        uint32_t gs = uint32_t(t.size() + 4);
        put(list, &gs, 4);
        put(list, t.data(), t.size());
    }
    const uint64_t hdr = 88, flOff = hdr, bcOff = hdr + list.size(), total = bcOff + bc.size(), flSize = list.size(), bcSize = bc.size(), z = 0;
    std::vector<uint8_t> out;
    put(out, "MTLB", 4);
    uint16_t h16[] = {0x8001, 1, 2};
    put(out, h16, 6);
    uint8_t h8[] = {0, 1};
    put(out, h8, 2);
    uint16_t h16b[] = {14, 0};
    put(out, h16b, 4);
    uint64_t h64[] = {total, flOff, flSize, bcOff, z, bcOff, z, bcOff, bcSize};
    put(out, h64, sizeof h64);
    put(out, list.data(), list.size());
    put(out, bc.data(), bc.size());
    return out;
}
} // namespace

std::vector<uint8_t> mslCompile(const std::string &userSrc, const std::string &macros, std::string &log) {
    static std::mutex mu; /* LLVM's command-line state is global */
    std::lock_guard<std::mutex> lock(mu);
    try {
        std::string src = macros + "#line 1 \"metal_stdlib\"\n" + kStdlib + "\n#line 1 \"shader.metal\"\n" + rewrite(userSrc);
        if (getenv("SCION_MSL_DUMP")) fprintf(stderr, "%s\n", src.c_str() + macros.size() + strlen(kStdlib));
        std::string diag;
        llvm::raw_string_ostream dos(diag);
        IntrusiveRefCntPtr<DiagnosticOptions> dopts = new DiagnosticOptions();
        dopts->ShowColors = false;
        dopts->ShowPresumedLoc = true; /* #line: errors point into the app's source */
        auto *printer = new TextDiagnosticPrinter(dos, dopts.get());
        std::vector<const char *> args = {"-triple", "spir64", "-cl-std=clc++2021", "-emit-llvm", "-O2", "-disable-llvm-passes", "-Wno-everything",
                                          "-ferror-limit", "20", "-ffp-contract=fast", "-fno-signed-zeros", "-cl-single-precision-constant"};
#ifdef MSL_NO_BOOLVEC
        args.push_back("-D__MW_NO_BOOLVEC");
#endif
        auto inv = std::make_shared<CompilerInvocation>();
        IntrusiveRefCntPtr<DiagnosticIDs> ids(new DiagnosticIDs());
        DiagnosticsEngine argDiags(ids, dopts.get(), printer, false);
        if (!CompilerInvocation::CreateFromArgs(*inv, args, argDiags)) fail("compiler arguments: " + dos.str());
        auto buf = llvm::MemoryBuffer::getMemBuffer(src, "shader.metal");
        inv->getFrontendOpts().Inputs.clear();
        inv->getFrontendOpts().Inputs.push_back(FrontendInputFile(buf->getMemBufferRef(), InputKind(Language::OpenCLCXX)));
        inv->getFrontendOpts().ProgramAction = frontend::EmitLLVMOnly;
        CompilerInstance ci;
        ci.setInvocation(inv);
        ci.createDiagnostics(*llvm::vfs::getRealFileSystem(), printer, true);
        llvm::LLVMContext ctx;
        std::vector<Entry> entries;
        std::vector<FConst> fconsts;
        Collector col(entries, fconsts);
        Action act(&ctx, &col);
        bool ok = ci.ExecuteAction(act);
        log = dos.str();
        if (!col.error.empty()) { log += col.error; return {}; }
        if (!ok) return {};
        std::unique_ptr<llvm::Module> M = act.takeModule();
        if (!M) { log += "no module"; return {}; }
        if (entries.empty()) { log += "the source has no kernel/vertex/fragment functions"; return {}; }
        airify(*M, entries, fconsts);
        if (getenv("SCION_MSL_DUMP")) M->print(llvm::errs(), nullptr);
        llvm::SmallVector<char, 0> bc;
        llvm::raw_svector_ostream bos(bc);
        llvm::WriteBitcodeToFile(*M, bos);
        return pack(entries, bc);
    } catch (const std::exception &e) {
        log += e.what();
        return {};
    }
}

/* scion-msl.dll: C entry points for scion-metal.dll, which loads this library the first time a program compiles MSL */
#ifdef _WIN32
#define MSL_EXPORT extern "C" __declspec(dllexport)
#else
#define MSL_EXPORT extern "C" __attribute__((visibility("default")))
#endif
MSL_EXPORT const char *mw_msl_version() { return kMslVersion; }
MSL_EXPORT void *mw_msl_compile(const char *src, const char *macros, size_t *len, char *log, size_t logsz) {
    std::string l;
    std::vector<uint8_t> lib = mslCompile(src, macros ? macros : "", l);
    if (log && logsz) { strncpy(log, l.c_str(), logsz - 1); log[logsz - 1] = 0; }
    if (lib.empty()) return nullptr;
    void *p = malloc(lib.size());
    memcpy(p, lib.data(), lib.size());
    *len = lib.size();
    return p;
}
MSL_EXPORT void mw_msl_free(void *p) { free(p); }
