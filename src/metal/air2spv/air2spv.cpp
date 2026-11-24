#include <atomic>
/* air2spv.cpp — Iridium-NG: Apple AIR (Metal bitcode, typed or opaque pointers) -> SPIR-V for Vulkan.
 * Drop-in replacement for Iridium::translate (same interface and binding conventions, so Indium is unchanged).
 *
 * Model:
 *  - LLVM (>= 17) reads the bitcode and normalizes the function: SROA, switch lowering, single exit, structured CFG.
 *  - device/constant pointers (buffers) are 64-bit integers: GEP is integer arithmetic (DataLayout offsets) and every
 *    access converts the address to a PhysicalStorageBuffer pointer of the accessed type. Metal's arbitrary pointer
 *    casts therefore need no pointee types at all.
 *  - thread-private (alloca), threadgroup and program-scope constant memory are uint arrays addressed by byte offset.
 *  - air.* intrinsics map to SPIR-V / GLSL.std.450 by name. */
#include "spv.h"
#include <cstdint>
#include <cmath>
#include <functional>
#include <iridium/iridium.hpp>
#include <llvm/Transforms/Utils/BasicBlockUtils.h>
#include <llvm/Transforms/Utils/Cloning.h>
#include <llvm/IR/IRBuilder.h>

#include <llvm/ADT/PostOrderIterator.h>
#include <llvm/Analysis/AssumptionCache.h>
#include <llvm/Analysis/CFG.h>
#include <llvm/Analysis/LoopInfo.h>
#include <llvm/Analysis/PostDominators.h>
#include <llvm/Analysis/TargetLibraryInfo.h>
#include <llvm/Analysis/TargetTransformInfo.h>
#include <llvm/Analysis/UniformityAnalysis.h>
#include <llvm/Bitcode/BitcodeReader.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/DataLayout.h>
#include <llvm/IR/Dominators.h>
#include <llvm/IR/GetElementPtrTypeIterator.h>
#include <llvm/IR/Instructions.h>
#include <llvm/IR/IntrinsicInst.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/Operator.h>
#include <llvm/IR/PassManager.h>
#include <llvm/IR/Verifier.h>
#include <llvm/Support/MemoryBuffer.h>
#include <llvm/IR/LegacyPassManager.h>
#include <llvm/InitializePasses.h>
#include <llvm/Transforms/Scalar.h>
#include <llvm/Transforms/Utils.h>
#include <llvm/Transforms/Utils/UnifyFunctionExitNodes.h>

#include <cstdlib>
#include <stdexcept>

using namespace llvm;
using a2s::Id;
using a2s::Words;
using SO = spv::Op;
using SC = spv::StorageClass;

namespace {

struct Unsupported : std::runtime_error {
    using std::runtime_error::runtime_error;
};
[[noreturn]] void fail(const std::string &m) { throw Unsupported(m); }

std::string mdStr(const Metadata *m) {
    if (auto s = dyn_cast_or_null<MDString>(m)) return s->getString().str();
    return {};
}
int64_t mdInt(const Metadata *m) {
    if (auto c = dyn_cast_or_null<ConstantAsMetadata>(m))
        if (auto ci = dyn_cast<ConstantInt>(c->getValue())) return ci->getSExtValue();
    return -1;
}
/* value right after a string key in an AIR metadata node, e.g. "air.location_index", i32 N */
int64_t mdAfter(const MDNode *n, StringRef key, unsigned skip = 1) {
    for (unsigned i = 0; i + skip < n->getNumOperands(); i++)
        if (mdStr(n->getOperand(i)) == key) return mdInt(n->getOperand(i + skip));
    return -1;
}
bool mdHas(const MDNode *n, StringRef key) {
    for (auto &o : n->operands())
        if (mdStr(o) == key) return true;
    return false;
}
std::string mdAfterStr(const MDNode *n, StringRef key) {
    for (unsigned i = 0; i + 1 < n->getNumOperands(); i++)
        if (mdStr(n->getOperand(i)) == key) return mdStr(n->getOperand(i + 1));
    return {};
}

struct BuiltinDef;

/* kind of memory a pointer value points into (decided by where the pointer comes from) */
enum class PK { None, Phys, Private, Group, Const, Image, Sampler };

/* ================================================================== LLVM normalization */
/* bfloat: SPIR-V has no bf16 arithmetic. Everything except moves/loads/stores/fpext/fptrunc goes through float here;
 * in SPIR-V a bfloat is a 16-bit integer and fpext/fptrunc are bit operations (Fn::translate). */
bool hasBF(Type *t) { return t->getScalarType()->isBFloatTy(); }
Type *bfToF(Type *t) {
    if (!hasBF(t)) return t;
    Type *f = Type::getFloatTy(t->getContext());
    if (auto v = dyn_cast<FixedVectorType>(t)) return FixedVectorType::get(f, v->getNumElements());
    return f;
}
void legalizeBFloat(Function &F) {
    SmallVector<Instruction *, 32> work;
    for (auto &BB : F)
        for (auto &I : BB) {
            bool bf = hasBF(I.getType());
            for (auto &o : I.operands()) bf |= hasBF(o->getType());
            if (!bf) continue;
            if (isa<BinaryOperator>(I) || isa<UnaryOperator>(I) || isa<FCmpInst>(I) || isa<SIToFPInst>(I) || isa<UIToFPInst>(I) ||
                isa<FPToSIInst>(I) || isa<FPToUIInst>(I) || isa<FPExtInst>(I) || isa<FPTruncInst>(I) || isa<CallInst>(I))
                work.push_back(&I);
        }
    for (Instruction *I : work) {
        IRBuilder<> B(I);
        Type *ft = Type::getFloatTy(I->getContext());
        auto up = [&](Value *v) { return hasBF(v->getType()) ? B.CreateFPExt(v, bfToF(v->getType())) : v; };
        auto down = [&](Value *v, Type *want) { return hasBF(want) ? B.CreateFPTrunc(v, want) : v; };
        Value *r = nullptr;
        if (auto *bo = dyn_cast<BinaryOperator>(I)) r = down(B.CreateBinOp(bo->getOpcode(), up(bo->getOperand(0)), up(bo->getOperand(1))), I->getType());
        else if (auto *uo = dyn_cast<UnaryOperator>(I)) r = down(B.CreateUnOp(uo->getOpcode(), up(uo->getOperand(0))), I->getType());
        else if (auto *fc = dyn_cast<FCmpInst>(I)) r = B.CreateFCmp(fc->getPredicate(), up(fc->getOperand(0)), up(fc->getOperand(1)));
        else if (isa<SIToFPInst>(I)) r = down(B.CreateSIToFP(I->getOperand(0), bfToF(I->getType())), I->getType());
        else if (isa<UIToFPInst>(I)) r = down(B.CreateUIToFP(I->getOperand(0), bfToF(I->getType())), I->getType());
        else if (isa<FPToSIInst>(I)) r = B.CreateFPToSI(up(I->getOperand(0)), I->getType());
        else if (isa<FPToUIInst>(I)) r = B.CreateFPToUI(up(I->getOperand(0)), I->getType());
        else if (isa<FPExtInst>(I) || isa<FPTruncInst>(I)) {
            Value *s = I->getOperand(0);
            Type *st = s->getType(), *dt = I->getType();
            if ((hasBF(st) && dt->getScalarType()->isFloatTy()) || (hasBF(dt) && st->getScalarType()->isFloatTy())) continue; /* native */
            Value *mid = hasBF(st) ? up(s) : B.CreateFPCast(s, bfToF(dt));
            r = hasBF(dt) ? B.CreateFPTrunc(mid, dt) : B.CreateFPCast(mid, dt);
        } else if (auto *ci = dyn_cast<CallInst>(I)) {
            Function *callee = ci->getCalledFunction();
            if (!callee || callee->getName().contains("simdgroup_matrix")) continue;
            SmallVector<Value *, 8> args;
            SmallVector<Type *, 8> tys;
            for (auto &a : ci->args()) { args.push_back(up(a)); tys.push_back(args.back()->getType()); }
            Type *rt = bfToF(ci->getType());
            Function *nf;
            if (callee->isIntrinsic()) {
                SmallVector<Type *, 4> overload;
                if (!Intrinsic::isOverloaded(callee->getIntrinsicID())) continue;
                overload.push_back(rt->isVoidTy() ? tys[0] : rt);
                nf = Intrinsic::getOrInsertDeclaration(F.getParent(), callee->getIntrinsicID(), overload);
            } else {
                std::string n = callee->getName().str();
                for (size_t p; (p = n.find("bf16")) != std::string::npos;) n.replace(p, 4, "f32");
                nf = cast<Function>(F.getParent()->getOrInsertFunction(n, FunctionType::get(rt, tys, false)).getCallee());
            }
            r = down(B.CreateCall(nf, args), ci->getType());
        }
        if (!r) continue;
        I->replaceAllUsesWith(r);
        I->eraseFromParent();
    }
}

/* a branch into a block that only reaches `unreachable` (an impossible switch default, say) is never taken: dropping it
 * gives every selection a merge point the structurizer and the post-dominator tree can see */
void dropUnreachablePaths(Function &F) {
    for (bool changed = true; changed;) {
        changed = false;
        for (BasicBlock &BB : F) {
            if (&BB == &F.getEntryBlock() || !isa<UnreachableInst>(BB.getTerminator())) continue;
            bool sideEffects = false;
            for (Instruction &I : BB) sideEffects |= !I.isTerminator() && I.mayHaveSideEffects();
            if (sideEffects) continue;
            for (BasicBlock *P : SmallVector<BasicBlock *, 4>(predecessors(&BB))) {
                Instruction *t = P->getTerminator();
                if (auto *br = dyn_cast<BranchInst>(t); br && br->isConditional()) {
                    BasicBlock *other = br->getSuccessor(0) == &BB ? br->getSuccessor(1) : br->getSuccessor(0);
                    if (other == &BB) continue;
                    BB.removePredecessor(P);
                    BranchInst::Create(other, t->getIterator());
                    t->eraseFromParent();
                    changed = true;
                } else if (auto *sw = dyn_cast<SwitchInst>(t)) {
                    BasicBlock *alt = nullptr;
                    for (auto &c : sw->cases()) if (c.getCaseSuccessor() != &BB) alt = c.getCaseSuccessor();
                    if (!alt && sw->getDefaultDest() != &BB) alt = sw->getDefaultDest();
                    if (!alt) continue;
                    BB.removePredecessor(P, true);
                    for (auto it = sw->case_begin(); it != sw->case_end();) it = it->getCaseSuccessor() == &BB ? sw->removeCase(it) : std::next(it);
                    if (sw->getDefaultDest() == &BB) sw->setDefaultDest(alt);
                    changed = true;
                }
            }
        }
        if (changed) EliminateUnreachableBlocks(F);
    }
}

void normalize(Function &F) {
    static bool registered = [] {
        PassRegistry &R = *PassRegistry::getPassRegistry();
        initializeCore(R);
        initializeAnalysis(R);
        initializeTransformUtils(R);
        initializeScalarOpts(R);
        return true;
    }();
    (void)registered;
    /* Metal code may keep helper functions out of line: inline everything defined in the module */
    for (int budget = 4096; budget > 0;) {
        CallBase *site = nullptr;
        for (auto &BB : F)
            for (auto &I : BB)
                if (auto *CB = dyn_cast<CallBase>(&I))
                    if (Function *c = CB->getCalledFunction(); c && !c->isDeclaration() && c != &F) { site = CB; break; }
        if (!site) break;
        InlineFunctionInfo IFI;
        if (!InlineFunction(*site, IFI).isSuccess()) fail("could not inline " + site->getCalledFunction()->getName().str());
        budget--;
    }
    legalizeBFloat(F);
    dropUnreachablePaths(F);
    FunctionAnalysisManager FAM;
    UnifyFunctionExitNodesPass().run(F, FAM); /* needs no analyses */
    legacy::FunctionPassManager PM(F.getParent());
    PM.add(createSROAPass(false));
    PM.add(createPromoteMemoryToRegisterPass());
    PM.add(createLowerSwitchPass());
    PM.add(createLoopSimplifyPass());
    PM.add(createFixIrreduciblePass());
    PM.add(createUnifyLoopExitsPass());
    PM.add(createLoopSimplifyPass());
    PM.add(createStructurizeCFGPass(/*SkipUniformRegions=*/false));
    PM.doInitialization();
    PM.run(F);
    PM.doFinalization();
}

/* ================================================================== per-function translation */
struct Fn {
    a2s::Module &m;
    Function &F;
    const DataLayout &DL;
    Iridium::FunctionInfo &info;
    Iridium::FunctionType stage;

    Words *cur = nullptr;
    Words body, prologue, fvars;
    std::vector<Id> iface;
    DenseMap<const Value *, Id> vals, fwd;
    DenseMap<const Value *, PK> kinds;
    DenseMap<const Value *, Id> handles; /* texture / sampler UniformConstant variables */
    DenseMap<const Value *, Iridium::TextureAccessType> texAccess;
    DenseMap<Id, Id> texType;        /* image variable -> OpTypeImage */
    DenseMap<Id, unsigned> texDims;  /* image variable -> components of its size query */
    DenseMap<Id, Id> texSampled;     /* image variable -> sampled type (float, int, uint) */
    DenseMap<const BasicBlock *, Id> labels;

    /* word-addressed memories */
    struct Mem { uint32_t size = 0; DenseMap<const Value *, uint32_t> at; Id var = 0; SC sc; };
    Mem priv{0, {}, 0, SC::Function}, group{0, {}, 0, SC::Workgroup}, cbank{0, {}, 0, SC::Private};

    /* outputs */
    struct Out { Id var = 0, type = 0; bool widen = false, wrap = false; Type *llty = nullptr; };
    std::vector<Out> outs; /* one per returned value / struct member (var 0 = dropped) */

    Id uboVar = 0, fnId = 0, wgSize = 0, gridSize = 0, inGrid = 0;
    DenseMap<int, Id> builtinVals;
    /* builtin input, loaded once in the prologue (so the body can use it anywhere) */
    Id builtinIn(spv::BuiltIn b, Id t) {
        auto it = builtinVals.find(int(b));
        if (it != builtinVals.end()) return it->second;
        Id v = m.var(m.tPtr(SC::Input, t), SC::Input);
        m.deco(v, spv::Decoration::BuiltIn, {uint32_t(b)});
        if (stage == Iridium::FunctionType::Fragment && t != m.tBool() && t != m.tVec(m.tFloat(32), 4) && t != m.tVec(m.tFloat(32), 2))
            m.deco(v, spv::Decoration::Flat);
        if (b == spv::BuiltIn::SubgroupLocalInvocationId || b == spv::BuiltIn::SubgroupId || b == spv::BuiltIn::SubgroupSize || b == spv::BuiltIn::NumSubgroups)
            m.cap(spv::Capability::GroupNonUniform);
        iface.push_back(v);
        Words *save = cur;
        cur = &prologue;
        Id r = op(SO::OpLoad, t, {v});
        cur = save;
        builtinVals[int(b)] = r;
        return r;
    }
    Id simd(CallInst *CI, StringRef op, bool quad);
    /* function constants: global holding the value (section air.fc_initializer) -> index */
    DenseMap<const GlobalVariable *, unsigned> fcIndex;
    Id fcValue(unsigned index, Type *t) { /* 32-bit specialization constant 1000 + index, converted to the loaded type */
        std::string key = "fc" + std::to_string(index);
        Id sc;
        auto it = m.cache.find(key);
        if (it != m.cache.end()) sc = it->second;
        else {
            sc = m.id();
            a2s::emit(m.globals, SO::OpSpecConstant, {u32(), sc, 0});
            m.deco(sc, spv::Decoration::SpecId, {1000 + index});
            m.cache[key] = sc;
        }
        if (t->isIntegerTy(32)) return sc;
        if (t->isFloatTy()) return op(SO::OpBitcast, ty(t), {sc});
        if (t->isIntegerTy(1)) return op(SO::OpINotEqual, m.tBool(), {sc, m.cU32(0)});
        if (t->isIntegerTy(8) || t->isIntegerTy(16)) return op(SO::OpUConvert, ty(t), {sc});
        if (t->isHalfTy()) return op(SO::OpBitcast, ty(t), {op(SO::OpUConvert, m.tInt(16), {sc})});
        fail("function constant of an unsupported type");
    }
    size_t internal = 0;
    uint32_t bufCount = 0;

    Fn(a2s::Module &mm, Function &f, Iridium::FunctionInfo &i) : m(mm), F(f), DL(f.getParent()->getDataLayout()), info(i) {}

    /* ---------------------------------------------------------- emission helpers */
    Id op(SO o, Id type, Words args) {
        Id r = m.id();
        Words w{type, r};
        w.insert(w.end(), args.begin(), args.end());
        a2s::emit(*cur, o, w);
        return r;
    }
    void opv(SO o, Words args) { a2s::emit(*cur, o, args); }
    Id ext(Id type, GLSLstd450 inst, Words args) {
        Words w{m.glslSet(), uint32_t(inst)};
        w.insert(w.end(), args.begin(), args.end());
        return op(SO::OpExtInst, type, w);
    }
    Id u32() { return m.tInt(32); }
    Id u64() { return m.tInt(64); }

    /* ---------------------------------------------------------- types */
    Id ptrNumTy(PK k) { return k == PK::Phys ? u64() : u32(); }
    PK defaultKind(Type *t) {
        unsigned as = t->getPointerAddressSpace();
        return as == 0 ? PK::Private : as == 3 ? PK::Group : PK::Phys;
    }
    Id ty(Type *t) {
        if (t->isVoidTy()) return m.tVoid();
        if (t->isIntegerTy(1)) return m.tBool();
        if (t->isIntegerTy()) {
            unsigned w = t->getIntegerBitWidth();
            if (w != 8 && w != 16 && w != 32 && w != 64) fail(std::to_string(w) + "-bit integer");
            return m.tInt(w);
        }
        if (t->isHalfTy()) return m.tFloat(16);
        if (t->isBFloatTy()) return m.tInt(16); /* bits; arithmetic was legalized to float */
        if (t->isFloatTy()) return m.tFloat(32);
        if (t->isDoubleTy()) return m.tFloat(64);
        if (t->isPointerTy()) return ptrNumTy(defaultKind(t));
        if (auto v = dyn_cast<FixedVectorType>(t)) {
            if (v->getElementType()->isPointerTy()) fail("vector of pointers");
            if (isMatrix(t)) return m.tVec(ty(v->getElementType()), 2); /* simdgroup_matrix: this thread's 2 elements */
            return m.tVec(ty(v->getElementType()), v->getNumElements());
        }
        if (auto a = dyn_cast<ArrayType>(t)) return m.tArray(ty(a->getElementType()), a->getNumElements());
        if (auto s = dyn_cast<StructType>(t)) {
            Words mem;
            for (auto *e : s->elements()) mem.push_back(ty(e));
            return m.tStruct(mem);
        }
        std::string str;
        raw_string_ostream os(str);
        t->print(os);
        fail("type " + str);
    }
    static bool isMatrix(Type *t) { return t->isVectorTy() && cast<FixedVectorType>(t)->getNumElements() == 64; }
    /* number of SPIR-V components of an LLVM vector (64 -> 2 for matrices) */
    static unsigned comps(Type *t) { return isMatrix(t) ? 2 : cast<FixedVectorType>(t)->getNumElements(); }
    Id simdMatrix(CallInst *CI, StringRef name);
    Id tyOf(const Value *v) {
        if (v->getType()->isPointerTy()) return ptrNumTy(kindOf(v));
        return ty(v->getType());
    }

    /* ---------------------------------------------------------- pointer provenance */
    PK kindOf(const Value *v) {
        if (!v->getType()->isPointerTy()) return PK::None;
        auto it = kinds.find(v);
        if (it != kinds.end()) return it->second;
        PK k = PK::None;
        kinds[v] = PK::None; /* breaks phi cycles */
        if (isa<AllocaInst>(v)) k = PK::Private;
        else if (auto g = dyn_cast<GlobalVariable>(v)) k = g->getAddressSpace() == 3 ? PK::Group : PK::Const;
        else if (isa<ConstantPointerNull>(v) || isa<UndefValue>(v)) k = PK::None;
        else if (auto ce = dyn_cast<ConstantExpr>(v)) k = ce->getOpcode() == Instruction::IntToPtr ? PK::Phys : kindOf(ce->getOperand(0));
        else if (auto g = dyn_cast<GEPOperator>(v)) k = kindOf(g->getPointerOperand());
        else if (auto c = dyn_cast<CastInst>(v)) k = isa<IntToPtrInst>(c) ? PK::Phys : kindOf(c->getOperand(0));
        else if (auto f = dyn_cast<FreezeInst>(v)) k = kindOf(f->getOperand(0));
        else if (auto s = dyn_cast<SelectInst>(v)) { k = kindOf(s->getTrueValue()); if (k == PK::None) k = kindOf(s->getFalseValue()); }
        else if (auto p = dyn_cast<PHINode>(v)) {
            for (auto &in : p->incoming_values())
                if ((k = kindOf(in)) != PK::None) break;
        } else k = PK::Phys; /* arguments (buffers), loaded pointers, call results */
        bool derived = isa<GEPOperator>(v) || isa<CastInst>(v) || isa<FreezeInst>(v) || isa<SelectInst>(v) || isa<ConstantExpr>(v);
        if (k == PK::None && derived && !isa<IntToPtrInst>(v)) { /* still resolving a phi cycle: decide later */
            kinds.erase(v);
            return PK::None;
        }
        if (k == PK::None) k = defaultKind(v->getType());
        kinds[v] = k;
        return k;
    }

    /* ---------------------------------------------------------- constants */
    Id cInt(Type *t, uint64_t v) {
        unsigned w = t->getIntegerBitWidth();
        if (w == 1) return m.cBool(v & 1);
        if (w == 64) return m.constant(m.tInt(64), {uint32_t(v), uint32_t(v >> 32)});
        if (w < 32) v &= (1ull << w) - 1;
        return m.constant(m.tInt(w), {uint32_t(v)});
    }
    Id cOf(Type *t, uint64_t v) { return t->isIntegerTy() ? cInt(t, v) : m.cU64(v); }
    uint64_t pow2Align(uint64_t align, uint64_t delta) {
        if (!align) align = 1;
        while (delta % align) align /= 2;
        return align;
    }
    Id cst(const Constant *C) {
        Type *t = C->getType();
        if (auto ci = dyn_cast<ConstantInt>(C)) return cInt(t, ci->getZExtValue());
        if (auto cf = dyn_cast<ConstantFP>(C)) {
            uint64_t bits = cf->getValueAPF().bitcastToAPInt().getZExtValue();
            if (t->isDoubleTy()) return m.constant(ty(t), {uint32_t(bits), uint32_t(bits >> 32)});
            return m.constant(ty(t), {uint32_t(bits)});
        }
        if (isa<ConstantPointerNull>(C)) return m.constant(ptrNumTy(defaultKind(t)), t->getPointerAddressSpace() == 0 || t->getPointerAddressSpace() == 3 ? Words{0} : Words{0, 0});
        if (isa<PoisonValue>(C) || isa<UndefValue>(C)) {
            if (t->isPointerTy()) return m.undef(ptrNumTy(defaultKind(t)));
            if (isa<UndefValue>(C) && !isa<PoisonValue>(C) && (t->isStructTy() || t->isArrayTy() || t->isVectorTy())) {
                /* partially-undef aggregates go through the generic path below */
            }
            return m.undef(ty(t));
        }
        if (isa<ConstantAggregateZero>(C)) return m.cNull(ty(t));
        if (auto cds = dyn_cast<ConstantDataSequential>(C)) {
            Words parts;
            unsigned n = isMatrix(t) ? 2 : cds->getNumElements();
            for (unsigned i = 0; i < n; i++) parts.push_back(cst(cds->getElementAsConstant(i)));
            return m.cComposite(ty(t), parts);
        }
        if (isa<ConstantVector>(C) || isa<ConstantStruct>(C) || isa<ConstantArray>(C)) {
            Words parts;
            for (auto &o : C->operands()) {
                if (isMatrix(t) && parts.size() == 2) break;
                parts.push_back(cst(cast<Constant>(o)));
            }
            return m.cComposite(ty(t), parts);
        }
        if (auto g = dyn_cast<GlobalVariable>(C)) return m.cU32(memOf(kindOf(g)).at.lookup(g));
        if (auto ce = dyn_cast<ConstantExpr>(C)) {
            if (ce->getOpcode() == Instruction::GetElementPtr || ce->getOpcode() == Instruction::BitCast || ce->getOpcode() == Instruction::AddrSpaceCast) {
                APInt off(64, 0);
                const Value *base = ce->stripAndAccumulateConstantOffsets(DL, off, true);
                if (auto g = dyn_cast<GlobalVariable>(base)) return m.cU32(memOf(kindOf(g)).at.lookup(g) + uint32_t(off.getZExtValue()));
            }
            /* anything else: materialize it as an instruction where it is used */
            Instruction *I = const_cast<ConstantExpr *>(ce)->getAsInstruction();
            Id r = translate(I);
            I->deleteValue();
            return r;
        }
        std::string str;
        raw_string_ostream os(str);
        C->print(os);
        fail("constant " + str);
    }
    Id get(const Value *v) {
        auto it = vals.find(v);
        if (it != vals.end()) return it->second;
        if (auto c = dyn_cast<Constant>(v)) return cst(c);
        fail("untranslated value: " + v->getName().str());
    }
    void set(const Value *v, Id r) {
        auto f = fwd.find(v);
        if (f != fwd.end()) { /* a phi referenced it before it existed */
            a2s::emit(*cur, SO::OpCopyObject, {tyOf(v), f->second, r});
            r = f->second;
        }
        vals[v] = r;
    }

    /* ---------------------------------------------------------- memory */
    Mem &memOf(PK k) { return k == PK::Private ? priv : k == PK::Group ? group : cbank; }
    Id word(PK k, Id byteAddr) { /* pointer to the uint holding byte address A */
        Mem &mm = memOf(k);
        Id idx = op(SO::OpShiftRightLogical, u32(), {byteAddr, m.cU32(2)});
        return op(SO::OpAccessChain, m.tPtr(mm.sc, u32()), {mm.var, idx});
    }
    Id addOff(Id p, PK k, uint64_t delta) {
        if (!delta) return p;
        return op(SO::OpIAdd, ptrNumTy(k), {p, k == PK::Phys ? m.cU64(delta) : m.cU32(uint32_t(delta))});
    }
    Id loadAny(PK k, Id p, uint64_t delta, Type *t, uint64_t align) {
        if (auto s = dyn_cast<StructType>(t)) {
            auto *sl = DL.getStructLayout(s);
            Words parts;
            for (unsigned i = 0; i < s->getNumElements(); i++)
                parts.push_back(loadAny(k, p, delta + sl->getElementOffset(i), s->getElementType(i), align));
            return op(SO::OpCompositeConstruct, ty(t), parts);
        }
        if (auto a = dyn_cast<ArrayType>(t)) {
            uint64_t stride = DL.getTypeAllocSize(a->getElementType());
            Words parts;
            for (unsigned i = 0; i < a->getNumElements(); i++) parts.push_back(loadAny(k, p, delta + i * stride, a->getElementType(), align));
            return op(SO::OpCompositeConstruct, ty(t), parts);
        }
        if (k == PK::Phys) {
            Type *mt = t->isIntegerTy(1) ? Type::getInt8Ty(t->getContext()) : t;
            Id addr = addOff(p, k, delta);
            Id ptr = op(SO::OpConvertUToPtr, m.tPtr(SC::PhysicalStorageBuffer, ty(mt)), {addr});
            Id v = op(SO::OpLoad, ty(mt), {ptr, uint32_t(spv::MemoryAccessMask::Aligned), uint32_t(pow2Align(align, delta))});
            if (mt != t) v = op(SO::OpINotEqual, m.tBool(), {v, cInt(mt, 0)});
            return v;
        }
        if (auto vt = dyn_cast<FixedVectorType>(t)) {
            uint64_t es = DL.getTypeStoreSize(vt->getElementType());
            Words parts;
            for (unsigned i = 0; i < comps(t); i++) parts.push_back(loadAny(k, p, delta + i * es, vt->getElementType(), align));
            return op(SO::OpCompositeConstruct, ty(t), parts);
        }
        Id a = addOff(p, k, delta);
        unsigned bytes = t->isIntegerTy(1) ? 1 : unsigned(DL.getTypeStoreSize(t));
        Id v;
        if (bytes == 4) {
            v = op(SO::OpLoad, u32(), {word(k, a)});
        } else if (bytes == 8) {
            Id lo = op(SO::OpLoad, u32(), {word(k, a)});
            Id hi = op(SO::OpLoad, u32(), {word(k, op(SO::OpIAdd, u32(), {a, m.cU32(4)}))});
            v = op(SO::OpCompositeConstruct, m.tVec(u32(), 2), {lo, hi});
        } else if (bytes == 2 || bytes == 1) {
            Id w = op(SO::OpLoad, u32(), {word(k, a)});
            Id sh = op(SO::OpShiftLeftLogical, u32(), {op(SO::OpBitwiseAnd, u32(), {a, m.cU32(bytes == 2 ? 2 : 3)}), m.cU32(3)});
            Id x = op(SO::OpShiftRightLogical, u32(), {w, sh});
            v = op(SO::OpUConvert, m.tInt(bytes * 8), {x});
        } else
            fail("load of " + std::to_string(bytes) + " bytes");
        if (t->isIntegerTy(1)) return op(SO::OpINotEqual, m.tBool(), {v, m.constant(m.tInt(8), {0})});
        if (ty(t) != (bytes == 8 ? m.tVec(u32(), 2) : m.tInt(bytes * 8))) v = op(SO::OpBitcast, ty(t), {v});
        return v;
    }
    void storeAny(PK k, Id p, uint64_t delta, Type *t, Id v, uint64_t align) {
        if (auto s = dyn_cast<StructType>(t)) {
            auto *sl = DL.getStructLayout(s);
            for (unsigned i = 0; i < s->getNumElements(); i++)
                storeAny(k, p, delta + sl->getElementOffset(i), s->getElementType(i), op(SO::OpCompositeExtract, ty(s->getElementType(i)), {v, i}), align);
            return;
        }
        if (auto a = dyn_cast<ArrayType>(t)) {
            uint64_t stride = DL.getTypeAllocSize(a->getElementType());
            for (unsigned i = 0; i < a->getNumElements(); i++)
                storeAny(k, p, delta + i * stride, a->getElementType(), op(SO::OpCompositeExtract, ty(a->getElementType()), {v, i}), align);
            return;
        }
        if (t->isIntegerTy(1)) { /* bools live in memory as bytes */
            Type *i8 = Type::getInt8Ty(t->getContext());
            v = op(SO::OpSelect, ty(i8), {v, cInt(i8, 1), cInt(i8, 0)});
            t = i8;
        }
        if (k == PK::Phys) {
            Id addr = addOff(p, k, delta);
            Id ptr = op(SO::OpConvertUToPtr, m.tPtr(SC::PhysicalStorageBuffer, ty(t)), {addr});
            opv(SO::OpStore, {ptr, v, uint32_t(spv::MemoryAccessMask::Aligned), uint32_t(pow2Align(align, delta))});
            return;
        }
        if (auto vt = dyn_cast<FixedVectorType>(t)) {
            uint64_t es = DL.getTypeStoreSize(vt->getElementType());
            for (unsigned i = 0; i < comps(t); i++)
                storeAny(k, p, delta + i * es, vt->getElementType(), op(SO::OpCompositeExtract, ty(vt->getElementType()), {v, i}), align);
            return;
        }
        Id a = addOff(p, k, delta);
        unsigned bytes = unsigned(DL.getTypeStoreSize(t));
        if (bytes == 4) {
            if (ty(t) != u32()) v = op(SO::OpBitcast, u32(), {v});
            opv(SO::OpStore, {word(k, a), v});
        } else if (bytes == 8) {
            Id pair = op(SO::OpBitcast, m.tVec(u32(), 2), {v});
            opv(SO::OpStore, {word(k, a), op(SO::OpCompositeExtract, u32(), {pair, 0})});
            opv(SO::OpStore, {word(k, op(SO::OpIAdd, u32(), {a, m.cU32(4)})), op(SO::OpCompositeExtract, u32(), {pair, 1})});
        } else if (bytes == 2 || bytes == 1) {
            Id it = m.tInt(bytes * 8);
            if (ty(t) != it) v = op(SO::OpBitcast, it, {v});
            Id x = op(SO::OpUConvert, u32(), {v});
            Id sh = op(SO::OpShiftLeftLogical, u32(), {op(SO::OpBitwiseAnd, u32(), {a, m.cU32(bytes == 2 ? 2 : 3)}), m.cU32(3)});
            Id mask = op(SO::OpShiftLeftLogical, u32(), {m.cU32(bytes == 2 ? 0xFFFF : 0xFF), sh});
            Id nmask = op(SO::OpNot, u32(), {mask});
            Id bits = op(SO::OpShiftLeftLogical, u32(), {x, sh});
            Id wp = word(k, a);
            if (k == PK::Group) { /* other threads may write the other bytes of this word: two atomics keep it race-free */
                Id scope = m.cU32(uint32_t(spv::Scope::Workgroup)), sem = m.cU32(0);
                op(SO::OpAtomicAnd, u32(), {wp, scope, sem, nmask});
                op(SO::OpAtomicOr, u32(), {wp, scope, sem, bits});
            } else {
                Id w = op(SO::OpLoad, u32(), {wp});
                opv(SO::OpStore, {wp, op(SO::OpBitwiseOr, u32(), {op(SO::OpBitwiseAnd, u32(), {w, nmask}), bits})});
            }
        } else
            fail("store of " + std::to_string(bytes) + " bytes");
    }

    /* ---------------------------------------------------------- conversions */
    Id toWidth(const Value *v, unsigned bits, bool sign) { /* integer value converted to an unsigned int of `bits` */
        Id x = get(v);
        Type *t = v->getType();
        if (t->isIntegerTy(1)) return op(SO::OpSelect, m.tInt(bits), {x, m.constant(m.tInt(bits), bits == 64 ? Words{1, 0} : Words{1}), bits == 64 ? m.cU64(0) : m.constant(m.tInt(bits), {0})});
        unsigned w = t->isPointerTy() ? (kindOf(v) == PK::Phys ? 64 : 32) : t->getIntegerBitWidth();
        if (w == bits) return x;
        return op(sign ? SO::OpSConvert : SO::OpUConvert, m.tInt(bits), {x});
    }

    /* ---------------------------------------------------------- instructions */
    Id gep(const GEPOperator *g) {
        PK k = kindOf(g);
        bool wide = k == PK::Phys;
        Id nt = ptrNumTy(k);
        Id r = get(g->getPointerOperand());
        int64_t constOff = 0;
        for (auto GTI = gep_type_begin(g), E = gep_type_end(g); GTI != E; ++GTI) {
            const Value *idx = GTI.getOperand();
            if (StructType *st = GTI.getStructTypeOrNull()) {
                constOff += DL.getStructLayout(st)->getElementOffset(cast<ConstantInt>(idx)->getZExtValue());
                continue;
            }
            int64_t stride = GTI.getSequentialElementStride(DL);
            if (auto ci = dyn_cast<ConstantInt>(idx)) {
                constOff += ci->getSExtValue() * stride;
                continue;
            }
            if (idx->getType()->isVectorTy()) fail("vector GEP");
            Id iv = toWidth(idx, wide ? 64 : 32, true);
            Id term = stride == 1 ? iv : op(SO::OpIMul, nt, {iv, wide ? m.cU64(stride) : m.cU32(uint32_t(stride))});
            r = op(SO::OpIAdd, nt, {r, term});
        }
        if (constOff) r = op(SO::OpIAdd, nt, {r, wide ? m.cU64(uint64_t(constOff)) : m.cU32(uint32_t(constOff))});
        return r;
    }

    Id translate(Instruction *I);
    Id call(CallInst *CI);
    Id airTexture(CallInst *CI, StringRef name);
    Id bindlessVar(const std::string &key, Id elemTy, uint32_t count, uint32_t binding);
    Id bindlessTexture(CallInst *CI, StringRef name);
    Id bindlessSampler(Value *sV);
    DenseSet<Id> bindlessPtrs;
    DenseMap<Id, uint32_t> texLoc;   /* argument texture variable -> its [[texture(n)]] */
    Id pcVar = 0;                    /* push constants: u32 per stage, bit n = texture n is sRGB written through a UNORM view */
    Id srgbEncode(Id tvar, Id v4);
    Id mwTexture(CallInst *CI, StringRef name, Id tvar, Id imgTy, Id img);

    /* ---------------------------------------------------------- driver */
    void run();
    void setupInterface(const MDNode *root);
    void writeOutputs(Instruction *ret);
};

/* ====================================================================== instruction translation */
Id Fn::translate(Instruction *I) {
    Type *t = I->getType();
    auto bin = [&](SO o) { return op(o, ty(t), {get(I->getOperand(0)), get(I->getOperand(1))}); };
    bool isBool = t->getScalarType()->isIntegerTy(1);
    switch (I->getOpcode()) {
    case Instruction::Add: return bin(SO::OpIAdd);
    case Instruction::Sub: return bin(SO::OpISub);
    case Instruction::Mul: return bin(SO::OpIMul);
    case Instruction::UDiv: return bin(SO::OpUDiv);
    case Instruction::SDiv: return bin(SO::OpSDiv);
    case Instruction::URem: return bin(SO::OpUMod);
    case Instruction::SRem: return bin(SO::OpSRem);
    case Instruction::Shl: return bin(SO::OpShiftLeftLogical);
    case Instruction::LShr: return bin(SO::OpShiftRightLogical);
    case Instruction::AShr: return bin(SO::OpShiftRightArithmetic);
    case Instruction::And: return bin(isBool ? SO::OpLogicalAnd : SO::OpBitwiseAnd);
    case Instruction::Or: return bin(isBool ? SO::OpLogicalOr : SO::OpBitwiseOr);
    case Instruction::Xor: return bin(isBool ? SO::OpLogicalNotEqual : SO::OpBitwiseXor);
    case Instruction::FAdd: return bin(SO::OpFAdd);
    case Instruction::FSub: return bin(SO::OpFSub);
    case Instruction::FMul: return bin(SO::OpFMul);
    case Instruction::FDiv: return bin(SO::OpFDiv);
    case Instruction::FRem: return bin(SO::OpFRem);
    case Instruction::FNeg: return op(SO::OpFNegate, ty(t), {get(I->getOperand(0))});
    case Instruction::Freeze: return get(I->getOperand(0));
    case Instruction::ICmp: {
        auto *c = cast<ICmpInst>(I);
        bool b = c->getOperand(0)->getType()->getScalarType()->isIntegerTy(1);
        SO o;
        switch (c->getPredicate()) {
        case CmpInst::ICMP_EQ: o = b ? SO::OpLogicalEqual : SO::OpIEqual; break;
        case CmpInst::ICMP_NE: o = b ? SO::OpLogicalNotEqual : SO::OpINotEqual; break;
        case CmpInst::ICMP_UGT: o = SO::OpUGreaterThan; break;
        case CmpInst::ICMP_UGE: o = SO::OpUGreaterThanEqual; break;
        case CmpInst::ICMP_ULT: o = SO::OpULessThan; break;
        case CmpInst::ICMP_ULE: o = SO::OpULessThanEqual; break;
        case CmpInst::ICMP_SGT: o = SO::OpSGreaterThan; break;
        case CmpInst::ICMP_SGE: o = SO::OpSGreaterThanEqual; break;
        case CmpInst::ICMP_SLT: o = SO::OpSLessThan; break;
        default: o = SO::OpSLessThanEqual; break;
        }
        if (b && o != SO::OpLogicalEqual && o != SO::OpLogicalNotEqual) fail("ordered comparison of i1");
        return op(o, ty(t), {get(c->getOperand(0)), get(c->getOperand(1))});
    }
    case Instruction::FCmp: {
        auto *c = cast<FCmpInst>(I);
        Id a = get(c->getOperand(0)), b = get(c->getOperand(1)), bt = ty(t);
        auto nan = [&]() { return op(SO::OpLogicalOr, bt, {op(SO::OpIsNan, bt, {a}), op(SO::OpIsNan, bt, {b})}); };
        switch (c->getPredicate()) {
        case CmpInst::FCMP_OEQ: return op(SO::OpFOrdEqual, bt, {a, b});
        case CmpInst::FCMP_OGT: return op(SO::OpFOrdGreaterThan, bt, {a, b});
        case CmpInst::FCMP_OGE: return op(SO::OpFOrdGreaterThanEqual, bt, {a, b});
        case CmpInst::FCMP_OLT: return op(SO::OpFOrdLessThan, bt, {a, b});
        case CmpInst::FCMP_OLE: return op(SO::OpFOrdLessThanEqual, bt, {a, b});
        case CmpInst::FCMP_ONE: return op(SO::OpFOrdNotEqual, bt, {a, b});
        case CmpInst::FCMP_UEQ: return op(SO::OpFUnordEqual, bt, {a, b});
        case CmpInst::FCMP_UGT: return op(SO::OpFUnordGreaterThan, bt, {a, b});
        case CmpInst::FCMP_UGE: return op(SO::OpFUnordGreaterThanEqual, bt, {a, b});
        case CmpInst::FCMP_ULT: return op(SO::OpFUnordLessThan, bt, {a, b});
        case CmpInst::FCMP_ULE: return op(SO::OpFUnordLessThanEqual, bt, {a, b});
        case CmpInst::FCMP_UNE: return op(SO::OpFUnordNotEqual, bt, {a, b});
        case CmpInst::FCMP_UNO: return nan();
        case CmpInst::FCMP_ORD: return op(SO::OpLogicalNot, bt, {nan()});
        case CmpInst::FCMP_TRUE: return t->isVectorTy() ? m.cComposite(bt, Words(cast<FixedVectorType>(t)->getNumElements(), m.cBool(true))) : m.cBool(true);
        default: return t->isVectorTy() ? m.cComposite(bt, Words(cast<FixedVectorType>(t)->getNumElements(), m.cBool(false))) : m.cBool(false);
        }
    }
    case Instruction::Select: {
        Id c = get(I->getOperand(0));
        return op(SO::OpSelect, tyOf(I), {c, get(I->getOperand(1)), get(I->getOperand(2))});
    }
    case Instruction::ZExt:
    case Instruction::SExt:
    case Instruction::Trunc: {
        Value *s = I->getOperand(0);
        Id x = get(s);
        Type *st = s->getType();
        if (st->getScalarType()->isIntegerTy(1)) { /* bool -> int */
            uint64_t one = I->getOpcode() == Instruction::SExt ? ~0ull : 1;
            Type *et = t->getScalarType();
            Id o = cInt(et, one), z = cInt(et, 0);
            if (auto vt = dyn_cast<FixedVectorType>(t)) {
                o = m.cComposite(ty(t), Words(vt->getNumElements(), o));
                z = m.cComposite(ty(t), Words(vt->getNumElements(), z));
            }
            return op(SO::OpSelect, ty(t), {x, o, z});
        }
        if (isBool) { /* int -> bool: low bit */
            Type *et = st->getScalarType();
            Id one = cInt(et, 1), zero = cInt(et, 0);
            if (auto vt = dyn_cast<FixedVectorType>(st)) {
                one = m.cComposite(ty(st), Words(vt->getNumElements(), one));
                zero = m.cComposite(ty(st), Words(vt->getNumElements(), zero));
            }
            return op(SO::OpINotEqual, ty(t), {op(SO::OpBitwiseAnd, ty(st), {x, one}), zero});
        }
        return op(I->getOpcode() == Instruction::SExt ? SO::OpSConvert : SO::OpUConvert, ty(t), {x});
    }
    case Instruction::FPExt:
    case Instruction::FPTrunc: {
        Value *s = I->getOperand(0);
        unsigned n = t->isVectorTy() ? cast<FixedVectorType>(t)->getNumElements() : 1;
        Id u32t = m.tVec(u32(), n), u16t = m.tVec(m.tInt(16), n);
        auto splat = [&](uint32_t c) { return n == 1 ? m.cU32(c) : m.cComposite(u32t, Words(n, m.cU32(c))); };
        if (hasBF(s->getType())) { /* bf16 -> f32: the bits are the top half of the float */
            Id w = op(SO::OpShiftLeftLogical, u32t, {op(SO::OpUConvert, u32t, {get(s)}), splat(16)});
            return op(SO::OpBitcast, ty(t), {w});
        }
        if (hasBF(t)) { /* f32 -> bf16, round to nearest even */
            Id b = op(SO::OpBitcast, u32t, {get(s)});
            Id lsb = op(SO::OpBitwiseAnd, u32t, {op(SO::OpShiftRightLogical, u32t, {b, splat(16)}), splat(1)});
            Id r = op(SO::OpIAdd, u32t, {op(SO::OpIAdd, u32t, {b, splat(0x7FFF)}), lsb});
            return op(SO::OpUConvert, u16t, {op(SO::OpShiftRightLogical, u32t, {r, splat(16)})});
        }
        return op(SO::OpFConvert, ty(t), {get(s)});
    }
    case Instruction::FPToUI:
    case Instruction::FPToSI: {
        Id x = get(I->getOperand(0));
        if (isBool) return op(SO::OpFUnordNotEqual, ty(t), {x, m.cNull(ty(I->getOperand(0)->getType()))});
        return op(I->getOpcode() == Instruction::FPToUI ? SO::OpConvertFToU : SO::OpConvertFToS, ty(t), {x});
    }
    case Instruction::UIToFP:
    case Instruction::SIToFP: {
        Value *s = I->getOperand(0);
        if (s->getType()->getScalarType()->isIntegerTy(1)) {
            Type *et = t->getScalarType();
            Id one = cst(ConstantFP::get(et, I->getOpcode() == Instruction::SIToFP ? -1.0 : 1.0)), zero = cst(ConstantFP::get(et, 0.0));
            if (auto vt = dyn_cast<FixedVectorType>(t)) {
                one = m.cComposite(ty(t), Words(vt->getNumElements(), one));
                zero = m.cComposite(ty(t), Words(vt->getNumElements(), zero));
            }
            return op(SO::OpSelect, ty(t), {get(s), one, zero});
        }
        return op(I->getOpcode() == Instruction::UIToFP ? SO::OpConvertUToF : SO::OpConvertSToF, ty(t), {get(s)});
    }
    case Instruction::BitCast: {
        Value *s = I->getOperand(0);
        if (t->isPointerTy()) return get(s);
        Id x = get(s);
        if (ty(s->getType()) == ty(t)) return x;
        return op(SO::OpBitcast, ty(t), {x});
    }
    case Instruction::AddrSpaceCast: {
        Value *s = I->getOperand(0);
        if (kindOf(s) != kindOf(I)) fail("addrspacecast between different memories");
        return get(s);
    }
    case Instruction::PtrToInt: return toWidth(I->getOperand(0), t->getIntegerBitWidth(), false);
    case Instruction::IntToPtr: return toWidth(I->getOperand(0), kindOf(I) == PK::Phys ? 64 : 32, false);
    case Instruction::GetElementPtr: return gep(cast<GEPOperator>(I));
    case Instruction::Load: {
        auto *L = cast<LoadInst>(I);
        if (auto *g = dyn_cast<GlobalVariable>(L->getPointerOperand()->stripPointerCasts()); g && fcIndex.count(g)) return fcValue(fcIndex[g], t);
        PK k = kindOf(L->getPointerOperand());
        if (k == PK::Image || k == PK::Sampler) fail("load from a texture/sampler");
        Type *lt = t->isPointerTy() ? Type::getInt64Ty(t->getContext()) : t;
        Id v = loadAny(k, get(L->getPointerOperand()), 0, lt, L->getAlign().value());
        if (t->isPointerTy() && kindOf(I) != PK::Phys) v = op(SO::OpUConvert, u32(), {v});
        return v;
    }
    case Instruction::Store: {
        auto *S = cast<StoreInst>(I);
        Value *v = S->getValueOperand();
        PK k = kindOf(S->getPointerOperand());
        Type *vt = v->getType()->isPointerTy() ? Type::getInt64Ty(v->getContext()) : v->getType();
        Id val = v->getType()->isPointerTy() ? toWidth(v, 64, false) : get(v);
        storeAny(k, get(S->getPointerOperand()), 0, vt, val, S->getAlign().value());
        return 0;
    }
    case Instruction::Alloca: return m.cU32(priv.at.lookup(I));
    case Instruction::ExtractElement: {
        Value *idx = I->getOperand(1);
        if (auto ci = dyn_cast<ConstantInt>(idx)) {
            if (isMatrix(I->getOperand(0)->getType()) && ci->getZExtValue() > 1) return m.undef(ty(t));
            return op(SO::OpCompositeExtract, ty(t), {get(I->getOperand(0)), uint32_t(ci->getZExtValue())});
        }
        return op(SO::OpVectorExtractDynamic, ty(t), {get(I->getOperand(0)), get(idx)});
    }
    case Instruction::InsertElement: {
        Value *idx = I->getOperand(2);
        if (auto ci = dyn_cast<ConstantInt>(idx)) {
            if (isMatrix(t) && ci->getZExtValue() > 1) return get(I->getOperand(0));
            return op(SO::OpCompositeInsert, ty(t), {get(I->getOperand(1)), get(I->getOperand(0)), uint32_t(ci->getZExtValue())});
        }
        return op(SO::OpVectorInsertDynamic, ty(t), {get(I->getOperand(0)), get(I->getOperand(1)), get(idx)});
    }
    case Instruction::ShuffleVector: {
        auto *sv = cast<ShuffleVectorInst>(I);
        Type *t0 = sv->getOperand(0)->getType();
        unsigned n1 = cast<FixedVectorType>(t0)->getNumElements(), c1 = comps(t0), c2 = comps(sv->getOperand(1)->getType());
        Words w{get(sv->getOperand(0)), get(sv->getOperand(1))};
        unsigned outN = comps(t), i = 0;
        for (int e : sv->getShuffleMask()) { /* renumber LLVM lanes into SPIR-V components (matrices keep lanes 0-1) */
            if (i++ == outN) break;
            uint32_t idx = 0xFFFFFFFFu;
            if (e >= 0 && unsigned(e) < n1) idx = unsigned(e) < c1 ? uint32_t(e) : 0xFFFFFFFFu;
            else if (e >= 0) idx = unsigned(e) - n1 < c2 ? c1 + (unsigned(e) - n1) : 0xFFFFFFFFu;
            w.push_back(idx);
        }
        if (n1 == 1) fail("shufflevector of 1-element vectors");
        return op(SO::OpVectorShuffle, ty(t), w);
    }
    case Instruction::ExtractValue: {
        Words w{get(I->getOperand(0))};
        for (unsigned i : cast<ExtractValueInst>(I)->indices()) w.push_back(i);
        return op(SO::OpCompositeExtract, tyOf(I), w);
    }
    case Instruction::InsertValue: {
        Words w{get(I->getOperand(1)), get(I->getOperand(0))};
        for (unsigned i : cast<InsertValueInst>(I)->indices()) w.push_back(i);
        return op(SO::OpCompositeInsert, ty(t), w);
    }
    case Instruction::PHI: {
        auto *P = cast<PHINode>(I);
        Words w;
        for (unsigned i = 0; i < P->getNumIncomingValues(); i++) {
            Value *v = P->getIncomingValue(i);
            Id x;
            auto it = vals.find(v);
            if (it != vals.end()) x = it->second;
            else if (isa<Instruction>(v)) { /* back edge: defined later */
                auto f = fwd.find(v);
                x = f != fwd.end() ? f->second : (fwd[v] = m.id());
            } else x = get(v);
            w.push_back(x);
            w.push_back(labels.lookup(P->getIncomingBlock(i)));
        }
        auto f = fwd.find(I);
        if (f == fwd.end()) return op(SO::OpPhi, tyOf(I), w);
        /* another phi already referenced this one: define the reserved id directly (no copy between phis) */
        Words full{tyOf(I), f->second};
        full.insert(full.end(), w.begin(), w.end());
        a2s::emit(*cur, SO::OpPhi, full);
        Id r = f->second;
        fwd.erase(f);
        return r;
    }
    case Instruction::Call: return call(cast<CallInst>(I));
    default: fail(std::string("instruction ") + I->getOpcodeName());
    }
}

/* ====================================================================== calls: llvm.* and air.* */
struct MathOp { const char *name; GLSLstd450 f, s, u; };
const MathOp kMath[] = {
    {"sin", GLSLstd450Sin}, {"cos", GLSLstd450Cos}, {"tan", GLSLstd450Tan}, {"asin", GLSLstd450Asin}, {"acos", GLSLstd450Acos},
    {"atan", GLSLstd450Atan}, {"atan2", GLSLstd450Atan2}, {"sinh", GLSLstd450Sinh}, {"cosh", GLSLstd450Cosh}, {"tanh", GLSLstd450Tanh},
    {"asinh", GLSLstd450Asinh}, {"acosh", GLSLstd450Acosh}, {"atanh", GLSLstd450Atanh}, {"exp", GLSLstd450Exp}, {"exp2", GLSLstd450Exp2},
    {"log", GLSLstd450Log}, {"log2", GLSLstd450Log2}, {"pow", GLSLstd450Pow}, {"powr", GLSLstd450Pow}, {"sqrt", GLSLstd450Sqrt},
    {"rsqrt", GLSLstd450InverseSqrt}, {"floor", GLSLstd450Floor}, {"ceil", GLSLstd450Ceil}, {"trunc", GLSLstd450Trunc},
    {"rint", GLSLstd450RoundEven}, {"round", GLSLstd450Round}, {"fract", GLSLstd450Fract}, {"fabs", GLSLstd450FAbs},
    {"fmin", GLSLstd450FMin}, {"fmax", GLSLstd450FMax}, {"fma", GLSLstd450Fma}, {"mix", GLSLstd450FMix}, {"step", GLSLstd450Step},
    {"smoothstep", GLSLstd450SmoothStep}, {"sign", GLSLstd450FSign}, {"cross", GLSLstd450Cross}, {"normalize", GLSLstd450Normalize},
    {"length", GLSLstd450Length}, {"distance", GLSLstd450Distance}, {"reflect", GLSLstd450Reflect}, {"refract", GLSLstd450Refract},
    {"min", GLSLstd450FMin, GLSLstd450SMin, GLSLstd450UMin}, {"max", GLSLstd450FMax, GLSLstd450SMax, GLSLstd450UMax},
    {"clamp", GLSLstd450FClamp, GLSLstd450SClamp, GLSLstd450UClamp}, {"abs", GLSLstd450FAbs, GLSLstd450SAbs, GLSLstd450SAbs},
    {"ldexp", GLSLstd450Ldexp}, {"exp10", GLSLstd450Bad},
};

Id Fn::call(CallInst *CI) {
    Function *callee = CI->getCalledFunction();
    if (!callee) fail("indirect call");
    StringRef name = callee->getName();
    Type *t = CI->getType();
    auto arg = [&](unsigned i) { return get(CI->getArgOperand(i)); };
    Id rt = t->isVoidTy() ? 0 : ty(t);

    /* ---- LLVM intrinsics */
    switch (callee->getIntrinsicID()) {
    case Intrinsic::lifetime_start:
    case Intrinsic::lifetime_end:
    case Intrinsic::assume:
    case Intrinsic::experimental_noalias_scope_decl:
    case Intrinsic::dbg_value:
    case Intrinsic::dbg_declare: return 0;
    case Intrinsic::fabs: return ext(rt, GLSLstd450FAbs, {arg(0)});
    case Intrinsic::fma:
    case Intrinsic::fmuladd: return ext(rt, GLSLstd450Fma, {arg(0), arg(1), arg(2)});
    case Intrinsic::sqrt: return ext(rt, GLSLstd450Sqrt, {arg(0)});
    case Intrinsic::floor: return ext(rt, GLSLstd450Floor, {arg(0)});
    case Intrinsic::ceil: return ext(rt, GLSLstd450Ceil, {arg(0)});
    case Intrinsic::trunc: return ext(rt, GLSLstd450Trunc, {arg(0)});
    case Intrinsic::rint:
    case Intrinsic::nearbyint:
    case Intrinsic::roundeven: return ext(rt, GLSLstd450RoundEven, {arg(0)});
    case Intrinsic::round: return ext(rt, GLSLstd450Round, {arg(0)});
    case Intrinsic::sin: return ext(rt, GLSLstd450Sin, {arg(0)});
    case Intrinsic::cos: return ext(rt, GLSLstd450Cos, {arg(0)});
    case Intrinsic::exp: return ext(rt, GLSLstd450Exp, {arg(0)});
    case Intrinsic::exp2: return ext(rt, GLSLstd450Exp2, {arg(0)});
    case Intrinsic::log: return ext(rt, GLSLstd450Log, {arg(0)});
    case Intrinsic::log2: return ext(rt, GLSLstd450Log2, {arg(0)});
    case Intrinsic::pow: return ext(rt, GLSLstd450Pow, {arg(0), arg(1)});
    case Intrinsic::minnum:
    case Intrinsic::minimum: return ext(rt, GLSLstd450NMin, {arg(0), arg(1)});
    case Intrinsic::maxnum:
    case Intrinsic::maximum: return ext(rt, GLSLstd450NMax, {arg(0), arg(1)});
    case Intrinsic::copysign: {
        /* |a| with the sign bit of b */
        Type *it = IntegerType::get(t->getContext(), t->getScalarSizeInBits());
        Type *ivt = t->isVectorTy() ? (Type *)FixedVectorType::get(it, cast<FixedVectorType>(t)->getNumElements()) : it;
        uint64_t sign = 1ull << (t->getScalarSizeInBits() - 1);
        Id sm = cInt(it, sign), am = cInt(it, sign - 1);
        if (t->isVectorTy()) {
            unsigned n = cast<FixedVectorType>(t)->getNumElements();
            sm = m.cComposite(ty(ivt), Words(n, sm));
            am = m.cComposite(ty(ivt), Words(n, am));
        }
        Id a = op(SO::OpBitcast, ty(ivt), {arg(0)}), b = op(SO::OpBitcast, ty(ivt), {arg(1)});
        Id r = op(SO::OpBitwiseOr, ty(ivt), {op(SO::OpBitwiseAnd, ty(ivt), {a, am}), op(SO::OpBitwiseAnd, ty(ivt), {b, sm})});
        return op(SO::OpBitcast, rt, {r});
    }
    case Intrinsic::is_fpclass: { /* isnan/isinf/isfinite...: OR of the classes in the mask (LLVM FPClassTest bits) */
        Value *x = CI->getArgOperand(0);
        uint64_t mask = cast<ConstantInt>(CI->getArgOperand(1))->getZExtValue();
        Type *xt = x->getType(), *st = xt->getScalarType();
        unsigned n = xt->isVectorTy() ? cast<FixedVectorType>(xt)->getNumElements() : 1;
        Type *it = IntegerType::get(CI->getContext(), st->getScalarSizeInBits());
        Type *ivt = n > 1 ? (Type *)FixedVectorType::get(it, n) : it;
        auto splat = [&](Id k, Type *vt) { return n > 1 ? m.cComposite(ty(vt), Words(n, k)) : k; };
        Id bt = rt, X = arg(0);
        Id bits = op(SO::OpBitcast, ty(ivt), {X});
        Id absb = op(SO::OpBitwiseAnd, ty(ivt), {bits, splat(cInt(it, (~0ull >> (65 - st->getScalarSizeInBits()))), ivt)});
        Id expMask = splat(cInt(it, st->isHalfTy() ? 0x7c00 : st->isDoubleTy() ? 0x7ff0000000000000ull : 0x7f800000), ivt);
        Id zeroI = splat(cInt(it, 0), ivt);
        Id isNan = op(SO::OpIsNan, bt, {X}), isInf = op(SO::OpIsInf, bt, {X});
        Id neg = op(SO::OpSLessThan, bt, {bits, zeroI});
        Id zero = op(SO::OpIEqual, bt, {absb, zeroI});
        Id expZero = op(SO::OpIEqual, bt, {op(SO::OpBitwiseAnd, ty(ivt), {bits, expMask}), zeroI});
        Id sub = op(SO::OpLogicalAnd, bt, {expZero, op(SO::OpLogicalNot, bt, {zero})});
        Id special = op(SO::OpLogicalOr, bt, {op(SO::OpLogicalOr, bt, {isNan, isInf}), expZero});
        Id normal = op(SO::OpLogicalNot, bt, {special});
        Id pos = op(SO::OpLogicalNot, bt, {neg});
        Id r = 0;
        auto add = [&](Id c) { r = r ? op(SO::OpLogicalOr, bt, {r, c}) : c; };
        if (mask & 3) add(isNan);
        auto cls = [&](unsigned negBit, unsigned posBit, Id c) {
            bool a = mask & (1u << negBit), b = mask & (1u << posBit);
            if (a && b) add(c); else if (a) add(op(SO::OpLogicalAnd, bt, {c, neg})); else if (b) add(op(SO::OpLogicalAnd, bt, {c, pos}));
        };
        cls(2, 9, isInf); cls(3, 8, normal); cls(4, 7, sub); cls(5, 6, zero);
        return r ? r : cst(Constant::getNullValue(t));
    }
    case Intrinsic::smin: return ext(rt, GLSLstd450SMin, {arg(0), arg(1)});
    case Intrinsic::smax: return ext(rt, GLSLstd450SMax, {arg(0), arg(1)});
    case Intrinsic::umin: return ext(rt, GLSLstd450UMin, {arg(0), arg(1)});
    case Intrinsic::umax: return ext(rt, GLSLstd450UMax, {arg(0), arg(1)});
    case Intrinsic::abs: return ext(rt, GLSLstd450SAbs, {arg(0)});
    case Intrinsic::ctpop: return op(SO::OpBitCount, rt, {arg(0)});
    case Intrinsic::fshl:
    case Intrinsic::fshr: { /* funnel shift: concat(a,b) shifted by c mod width */
        unsigned w = t->getScalarSizeInBits();
        Type *et = t->getScalarType();
        auto sp = [&](uint64_t c) { Id k = cInt(et, c); return t->isVectorTy() ? m.cComposite(rt, Words(cast<FixedVectorType>(t)->getNumElements(), k)) : k; };
        Id c = op(SO::OpBitwiseAnd, rt, {arg(2), sp(w - 1)});
        Id ic = op(SO::OpISub, rt, {sp(w), c});
        bool left = callee->getIntrinsicID() == Intrinsic::fshl;
        Id hi = op(SO::OpShiftLeftLogical, rt, {arg(0), left ? c : ic});
        Id lo = op(SO::OpShiftRightLogical, rt, {arg(1), left ? ic : c});
        Id r = op(SO::OpBitwiseOr, rt, {hi, lo});
        Id isZero = op(SO::OpIEqual, ty(CmpInst::makeCmpResultType(t)), {c, sp(0)});
        return op(SO::OpSelect, rt, {isZero, left ? arg(0) : arg(1), r});
    }
    case Intrinsic::bitreverse: return op(SO::OpBitReverse, rt, {arg(0)});
    case Intrinsic::ctlz: { /* 31 - findMSB, 32 for zero (32-bit only) */
        if (t->getScalarSizeInBits() != 32) fail("ctlz that is not 32-bit");
        Id msb = ext(rt, GLSLstd450FindUMsb, {arg(0)});
        return op(SO::OpISub, rt, {cInt(t, 31), msb}); /* FindUMsb(0) = -1 -> 32 */
    }
    case Intrinsic::cttz: {
        if (t->getScalarSizeInBits() != 32) fail("cttz that is not 32-bit");
        Id lsb = ext(rt, GLSLstd450FindILsb, {arg(0)});
        return ext(rt, GLSLstd450UMin, {lsb, cInt(t, 32)});
    }
    case Intrinsic::memcpy:
    case Intrinsic::memmove:
    case Intrinsic::memset: {
        auto *len = dyn_cast<ConstantInt>(CI->getArgOperand(2));
        if (!len) fail("memcpy/memset of variable length");
        uint64_t n = len->getZExtValue();
        Value *dst = CI->getArgOperand(0);
        PK dk = kindOf(dst);
        uint64_t align = cast<MemIntrinsic>(CI)->getDestAlign().valueOrOne().value();
        bool isSet = callee->getIntrinsicID() == Intrinsic::memset;
        uint64_t salign = isSet ? align : cast<MemTransferInst>(CI)->getSourceAlign().valueOrOne().value();
        uint64_t unit = std::min<uint64_t>(4, std::min(align, salign));
        while (n % unit) unit /= 2;
        Type *ut = IntegerType::get(CI->getContext(), unsigned(unit * 8));
        Id d = get(dst);
        Id fill = 0;
        if (isSet) {
            auto *bv = dyn_cast<ConstantInt>(CI->getArgOperand(1));
            if (!bv) fail("memset with a variable value");
            uint64_t b = bv->getZExtValue() & 0xFF, v = 0;
            for (uint64_t i = 0; i < unit; i++) v |= b << (8 * i);
            fill = cInt(ut, v);
        }
        for (uint64_t off = 0; off < n; off += unit) {
            Id v = isSet ? fill : loadAny(kindOf(CI->getArgOperand(1)), get(CI->getArgOperand(1)), off, ut, salign);
            storeAny(dk, d, off, ut, v, align);
        }
        return 0;
    }
    default: break;
    }
    if (name.starts_with("llvm.")) fail("intrinsic " + name.str());
    if (!name.starts_with("air.")) fail("call to function " + name.str() + " (not inlined)");

    /* ---- air.* */
    StringRef rest = name.drop_front(4);
    if (rest == "simd_is_helper_thread") {
        m.ext("SPV_EXT_demote_to_helper_invocation");
        m.cap(spv::Capability::DemoteToHelperInvocationEXT);
        return op(SO::OpIsHelperInvocationEXT, m.tBool(), {});
    }
    if (rest.starts_with("simdgroup_matrix_8x8_")) return simdMatrix(CI, rest.drop_front(21));
    if (rest.starts_with("simd_") || rest.starts_with("quad_")) return simd(CI, rest.drop_front(5), rest.starts_with("quad_"));
    if (rest.starts_with("is_uniform")) {
        m.cap(spv::Capability::GroupNonUniformVote);
        return op(SO::OpGroupNonUniformAllEqual, m.tBool(), {m.cU32(uint32_t(spv::Scope::Subgroup)), arg(0)});
    }
    if (rest.starts_with("get_simdgroup_size") || rest.starts_with("get_thread_execution_width")) {
        Id v = builtinIn(spv::BuiltIn::SubgroupSize, u32());
        return rt == u32() ? v : op(SO::OpUConvert, rt, {v});
    }
    if (rest.starts_with("fmod.")) return op(SO::OpFRem, rt, {arg(0), arg(1)});
    if (rest == "discard_fragment") { /* demote: derivatives in the rest of the quad stay valid */
        m.ext("SPV_EXT_demote_to_helper_invocation");
        m.cap(spv::Capability::DemoteToHelperInvocationEXT);
        opv(SO::OpDemoteToHelperInvocationEXT, {});
        return 0;
    }
    if (rest.starts_with("dfdx.") || rest.starts_with("dfdy.") || rest.starts_with("fwidth.")) {
        SO o = rest.starts_with("dfdx") ? SO::OpDPdx : rest.starts_with("dfdy") ? SO::OpDPdy : SO::OpFwidth;
        Type *e = t->getScalarType();
        if (!e->isHalfTy()) return op(o, rt, {arg(0)});
        Type *ft = t->isVectorTy() ? (Type *)FixedVectorType::get(Type::getFloatTy(CI->getContext()), cast<FixedVectorType>(t)->getNumElements()) : Type::getFloatTy(CI->getContext());
        return op(SO::OpFConvert, rt, {op(o, ty(ft), {op(SO::OpFConvert, ty(ft), {arg(0)})})});
    }
    if (rest.starts_with("normalize_function_constant_predicate")) /* any non-zero -> 1 */
        return op(SO::OpSelect, rt, {op(SO::OpINotEqual, m.tBool(), {arg(0), cInt(t, 0)}), cInt(t, 1), cInt(t, 0)});
    if (rest.starts_with("convert.")) { /* air.convert.<dk>.<dt>.<sk>.<st> */
        SmallVector<StringRef, 6> p;
        rest.split(p, '.');
        if (p.size() < 5) fail(name.str());
        char dk = p[1][0], sk = p[3][0];
        Id x = arg(0);
        Type *st = CI->getArgOperand(0)->getType();
        if (ty(st) == rt) return x;
        auto splatC = [&](Type *vt, Id c) { return vt->isVectorTy() ? m.cComposite(ty(vt), Words(cast<FixedVectorType>(vt)->getNumElements(), c)) : c; };
        if (st->getScalarType()->isIntegerTy(1)) { /* bool -> number */
            Type *et = t->getScalarType();
            Id one = et->isFloatingPointTy() ? cst(ConstantFP::get(et, 1.0)) : cInt(et, 1), zero = et->isFloatingPointTy() ? cst(ConstantFP::get(et, 0.0)) : cInt(et, 0);
            return op(SO::OpSelect, rt, {x, splatC(t, one), splatC(t, zero)});
        }
        if (t->getScalarType()->isIntegerTy(1)) { /* number -> bool */
            Type *et = st->getScalarType();
            Id zero = splatC(st, et->isFloatingPointTy() ? cst(ConstantFP::get(et, 0.0)) : cInt(et, 0));
            return op(et->isFloatingPointTy() ? SO::OpFUnordNotEqual : SO::OpINotEqual, rt, {x, zero});
        }
        if (dk == 'f' && sk == 'f') return op(SO::OpFConvert, rt, {x});
        if (dk == 'f') return op(sk == 's' ? SO::OpConvertSToF : SO::OpConvertUToF, rt, {x});
        if (sk == 'f') return op(dk == 's' ? SO::OpConvertFToS : SO::OpConvertFToU, rt, {x});
        if (ty(CI->getArgOperand(0)->getType()) == rt) return x;
        return op(sk == 's' ? SO::OpSConvert : SO::OpUConvert, rt, {x});
    }
    if (rest.contains("texture") || rest.contains("_depth_")) return airTexture(CI, rest);
    if (rest.starts_with("wg.barrier") || rest.starts_with("simdgroup.barrier")) {
        bool wg = rest.starts_with("wg");
        uint64_t flags = cast<ConstantInt>(CI->getArgOperand(0))->getZExtValue(); /* 1 device, 2 threadgroup, 4 texture */
        uint32_t sem = uint32_t(spv::MemorySemanticsMask::AcquireRelease);
        if (flags & 1) sem |= uint32_t(spv::MemorySemanticsMask::UniformMemory);
        if (flags & 2) sem |= uint32_t(spv::MemorySemanticsMask::WorkgroupMemory);
        if (flags & 4) sem |= uint32_t(spv::MemorySemanticsMask::ImageMemory);
        if (!(flags & 7)) sem = 0;
        Id scope = m.cU32(uint32_t(wg ? spv::Scope::Workgroup : spv::Scope::Subgroup));
        opv(SO::OpControlBarrier, {scope, scope, m.cU32(sem)});
        return 0;
    }
    if (rest.starts_with("atomic.")) { /* air.atomic.{global,local}.<op>.<s|u|f>.<ty> (ptr, value, order, scope, volatile) */
        SmallVector<StringRef, 6> p;
        rest.split(p, '.');
        StringRef aop = p.size() > 2 ? p[2] : "";
        Value *ptrV = CI->getArgOperand(0);
        PK k = kindOf(ptrV);
        Id ptr;
        Type *vt = aop == "load" ? CI->getType() : (aop == "cmpxchg" ? CI->getArgOperand(2) : CI->getArgOperand(1))->getType();
        if (k == PK::Phys) ptr = op(SO::OpConvertUToPtr, m.tPtr(SC::PhysicalStorageBuffer, ty(vt)), {get(ptrV)});
        else if (k == PK::Group && DL.getTypeStoreSize(vt) == 4) ptr = word(k, get(ptrV));
        else fail("atomic in this memory");
        Id scope = m.cU32(uint32_t(k == PK::Group ? spv::Scope::Workgroup : spv::Scope::Device)), sem = m.cU32(0);
        if (vt->isFloatTy() && (aop == "add" || aop == "sub")) { /* VK_EXT_shader_atomic_float */
            m.ext("SPV_EXT_shader_atomic_float_add");
            m.cap(spv::Capability::AtomicFloat32AddEXT);
            Id v = aop == "sub" ? op(SO::OpFNegate, rt, {arg(1)}) : arg(1);
            return op(SO::OpAtomicFAddEXT, rt, {ptr, scope, sem, v});
        }
        if (vt->isFloatTy() && aop != "xchg" && aop != "load" && aop != "store") fail("float atomic " + aop.str());
        bool sgn = p.size() > 3 && p[3] == "s";
        if (aop == "load") return op(SO::OpAtomicLoad, rt, {ptr, scope, sem});
        if (aop == "store") { opv(SO::OpAtomicStore, {ptr, scope, sem, arg(1)}); return 0; }
        if (aop == "cmpxchg") { /* (ptr, expected*, desired, ...) -> bool; Metal passes expected by pointer */
            Value *expP = CI->getArgOperand(1);
            Type *it = CI->getArgOperand(2)->getType();
            Id e = loadAny(kindOf(expP), get(expP), 0, it, 4);
            Id d = get(CI->getArgOperand(2));
            Id old = op(SO::OpAtomicCompareExchange, ty(it), {ptr, scope, sem, sem, d, e});
            storeAny(kindOf(expP), get(expP), 0, it, old, 4);
            return op(SO::OpIEqual, m.tBool(), {old, e});
        }
        SO o = aop == "add" ? SO::OpAtomicIAdd : aop == "sub" ? SO::OpAtomicISub : aop == "and" ? SO::OpAtomicAnd : aop == "or" ? SO::OpAtomicOr
             : aop == "xor" ? SO::OpAtomicXor : aop == "xchg" ? SO::OpAtomicExchange : aop == "min" ? (sgn ? SO::OpAtomicSMin : SO::OpAtomicUMin)
             : aop == "max" ? (sgn ? SO::OpAtomicSMax : SO::OpAtomicUMax) : SO::OpNop;
        if (o == SO::OpNop) fail("atomic " + aop.str());
        return op(o, rt, {ptr, scope, sem, arg(1)});
    }
    /* math: air.[fast_|precise_]<name>.<type> */
    StringRef fname = rest.split('.').first;
    StringRef tyName = rest.split('.').second;
    fname.consume_front("fast_");
    fname.consume_front("precise_");
    if (fname == "saturate") {
        Type *et = t->getScalarType();
        Id z = cst(ConstantFP::get(et, 0.0)), o = cst(ConstantFP::get(et, 1.0));
        if (auto vt = dyn_cast<FixedVectorType>(t)) { z = m.cComposite(rt, Words(vt->getNumElements(), z)); o = m.cComposite(rt, Words(vt->getNumElements(), o)); }
        return ext(rt, GLSLstd450FClamp, {arg(0), z, o});
    }
    if (fname == "dot") {
        if (!t->isFloatingPointTy()) fail("integer dot");
        return op(SO::OpDot, rt, {arg(0), arg(1)});
    }
    if (fname == "select") return op(SO::OpSelect, rt, {arg(2), arg(1), arg(0)});
    if (fname == "fmin3" || fname == "fmax3" || fname == "fmedian3") {
        GLSLstd450 mm = fname == "fmin3" ? GLSLstd450FMin : GLSLstd450FMax;
        if (fname == "fmedian3") return ext(rt, GLSLstd450FMax, {ext(rt, GLSLstd450FMin, {arg(0), arg(1)}), ext(rt, GLSLstd450FMin, {ext(rt, GLSLstd450FMax, {arg(0), arg(1)}), arg(2)})});
        return ext(rt, mm, {ext(rt, mm, {arg(0), arg(1)}), arg(2)});
    }
    if (fname == "divide") return op(SO::OpFDiv, rt, {arg(0), arg(1)});
    if (fname == "fdim") return ext(rt, GLSLstd450FMax, {op(SO::OpFSub, rt, {arg(0), arg(1)}), m.cNull(rt)});
    if (fname == "exp10") return ext(rt, GLSLstd450Exp2, {op(SO::OpFMul, rt, {arg(0), t->isVectorTy() ? m.cComposite(rt, Words(cast<FixedVectorType>(t)->getNumElements(), cst(ConstantFP::get(t->getScalarType(), 3.321928094887362)))) : cst(ConstantFP::get(t, 3.321928094887362))})});
    if (fname == "log10") return op(SO::OpFMul, rt, {ext(rt, GLSLstd450Log2, {arg(0)}), t->isVectorTy() ? m.cComposite(rt, Words(cast<FixedVectorType>(t)->getNumElements(), cst(ConstantFP::get(t->getScalarType(), 0.30102999566398120)))) : cst(ConstantFP::get(t, 0.30102999566398120))});
    if (fname == "clz" || fname == "ctz" || fname == "popcount") {
        if (fname == "popcount") return op(SO::OpBitCount, rt, {arg(0)});
        if (t->getScalarSizeInBits() != 32) fail(name.str());
        auto sp = [&](uint64_t c) { Id k = cInt(t->getScalarType(), c); return t->isVectorTy() ? m.cComposite(rt, Words(cast<FixedVectorType>(t)->getNumElements(), k)) : k; };
        if (fname == "clz") return op(SO::OpISub, rt, {sp(31), ext(rt, GLSLstd450FindUMsb, {arg(0)})});
        return ext(rt, GLSLstd450UMin, {ext(rt, GLSLstd450FindILsb, {arg(0)}), sp(32)});
    }
    for (auto &mo : kMath) {
        if (fname != mo.name || mo.f == GLSLstd450Bad) continue;
        /* type letter after the name: f (float), s (signed), u (unsigned); default by result type */
        char k = t->getScalarType()->isFloatingPointTy() ? 'f' : 's';
        if (tyName.size() > 1 && tyName[1] == '.') k = tyName[0];
        GLSLstd450 inst = k == 'f' ? mo.f : k == 'u' ? (mo.u ? mo.u : mo.f) : (mo.s ? mo.s : mo.f);
        if (k != 'f' && !mo.s) fail(name.str());
        Words args;
        for (unsigned i = 0; i < CI->arg_size(); i++) args.push_back(arg(i));
        if (fname == "length" || fname == "distance" || fname == "dot") rt = ty(t);
        return ext(rt, inst, args);
    }
    fail("function " + name.str());
}

/* simdgroup_matrix<T,8,8>: AIR gives each thread a <64 x T> whose lanes 0-1 are the two elements it owns. Lane L of the
 * 32-wide SIMD group owns (row, col) and (row, col+1) with row = 4*b4 + 2*b2 + b1 and col = 4*b3 + 2*b0 (bits of L;
 * the layout Apple GPUs use, documented by MLX). Multiply-accumulate gathers rows of A and columns of B with shuffles. */
Id Fn::simdMatrix(CallInst *CI, StringRef name) {
    Id f32 = m.tFloat(32);
    auto toF = [&](Id v, Type *et) {
        if (et->isFloatTy()) return v;
        if (et->isHalfTy()) return op(SO::OpFConvert, f32, {v});
        if (et->isBFloatTy()) return op(SO::OpBitcast, f32, {op(SO::OpShiftLeftLogical, u32(), {op(SO::OpUConvert, u32(), {v}), m.cU32(16)})});
        fail("simdgroup_matrix of an unsupported type");
    };
    auto fromF = [&](Id v, Type *et) {
        if (et->isFloatTy()) return v;
        if (et->isHalfTy()) return op(SO::OpFConvert, ty(et), {v});
        Id b = op(SO::OpBitcast, u32(), {v}); /* bfloat, round to nearest even */
        Id lsb = op(SO::OpBitwiseAnd, u32(), {op(SO::OpShiftRightLogical, u32(), {b, m.cU32(16)}), m.cU32(1)});
        Id r = op(SO::OpIAdd, u32(), {op(SO::OpIAdd, u32(), {b, m.cU32(0x7FFF)}), lsb});
        return op(SO::OpUConvert, m.tInt(16), {op(SO::OpShiftRightLogical, u32(), {r, m.cU32(16)})});
    };
    auto elemT = [](Type *v) { return cast<FixedVectorType>(v)->getElementType(); };
    auto ex = [&](Id v, Type *et, unsigned i) { return op(SO::OpCompositeExtract, ty(et), {v, i}); };
    Id lane = builtinIn(spv::BuiltIn::SubgroupLocalInvocationId, u32());
    Id l32 = op(SO::OpBitwiseAnd, u32(), {lane, m.cU32(31)}), base = op(SO::OpBitwiseAnd, u32(), {lane, m.cU32(~31u)});
    auto bit = [&](unsigned b) { return op(SO::OpBitwiseAnd, u32(), {op(SO::OpShiftRightLogical, u32(), {l32, m.cU32(b)}), m.cU32(1)}); };
    auto rowOf = [&]() { return op(SO::OpIAdd, u32(), {op(SO::OpIAdd, u32(), {op(SO::OpShiftLeftLogical, u32(), {bit(4), m.cU32(2)}), op(SO::OpShiftLeftLogical, u32(), {bit(2), m.cU32(1)})}), bit(1)}); };
    auto colOf = [&]() { return op(SO::OpIAdd, u32(), {op(SO::OpShiftLeftLogical, u32(), {bit(3), m.cU32(2)}), op(SO::OpShiftLeftLogical, u32(), {bit(0), m.cU32(1)})}); };
    Type *t = CI->getType();

    if (name.starts_with("multiply_accumulate")) {
        Type *ta = elemT(CI->getArgOperand(0)->getType()), *tb = elemT(CI->getArgOperand(1)->getType()), *tc = elemT(CI->getArgOperand(2)->getType());
        Id A = get(CI->getArgOperand(0)), B = get(CI->getArgOperand(1)), C = get(CI->getArgOperand(2));
        Id a[2] = {toF(ex(A, ta, 0), ta), toF(ex(A, ta, 1), ta)}, b[2] = {toF(ex(B, tb, 0), tb), toF(ex(B, tb, 1), tb)};
        Id d[2] = {toF(ex(C, tc, 0), tc), toF(ex(C, tc, 1), tc)};
        m.cap(spv::Capability::GroupNonUniformShuffle);
        Id scope = m.cU32(uint32_t(spv::Scope::Subgroup));
        Id rowBits = op(SO::OpBitwiseAnd, u32(), {l32, m.cU32(0x16)}), colBits = op(SO::OpBitwiseAnd, u32(), {l32, m.cU32(0x09)});
        for (unsigned k = 0; k < 8; k++) {
            uint32_t kA = ((k >> 2) & 1) << 3 | ((k >> 1) & 1);                      /* A(row, k) lives in lane rowBits | kA */
            uint32_t kB = ((k >> 2) & 1) << 4 | ((k >> 1) & 1) << 2 | (k & 1) << 1; /* B(k, col..col+1) in lane kB | colBits */
            Id lA = op(SO::OpBitwiseOr, u32(), {base, op(SO::OpBitwiseOr, u32(), {rowBits, m.cU32(kA)})});
            Id lB = op(SO::OpBitwiseOr, u32(), {base, op(SO::OpBitwiseOr, u32(), {colBits, m.cU32(kB)})});
            Id av = op(SO::OpGroupNonUniformShuffle, f32, {scope, a[k & 1], lA});
            for (unsigned e = 0; e < 2; e++) {
                Id bv = op(SO::OpGroupNonUniformShuffle, f32, {scope, b[e], lB});
                d[e] = ext(f32, GLSLstd450Fma, {av, bv, d[e]});
            }
        }
        Type *td = elemT(t);
        return op(SO::OpCompositeConstruct, ty(t), {fromF(d[0], td), fromF(d[1], td)});
    }
    if (name.starts_with("init_filled")) {
        Id x = get(CI->getArgOperand(0));
        return op(SO::OpCompositeConstruct, ty(t), {x, x});
    }
    if (name.starts_with("init_diagonal")) {
        Type *et = elemT(t);
        Id x = get(CI->getArgOperand(0)), z = m.cNull(ty(et)), r = rowOf(), c = colOf();
        Id e0 = op(SO::OpSelect, ty(et), {op(SO::OpIEqual, m.tBool(), {r, c}), x, z});
        Id e1 = op(SO::OpSelect, ty(et), {op(SO::OpIEqual, m.tBool(), {r, op(SO::OpIAdd, u32(), {c, m.cU32(1)})}), x, z});
        return op(SO::OpCompositeConstruct, ty(t), {e0, e1});
    }
    bool isLoad = name.starts_with("load"), isStore = name.starts_with("store");
    if (!isLoad && !isStore) fail("simdgroup_matrix_8x8_" + name.str());
    /* load(ptr, elements_per_row, origin {x = column, y = row}, transpose) / store(matrix, ptr, ...) */
    unsigned pa = isStore ? 1 : 0;
    Value *ptrV = CI->getArgOperand(pa);
    PK k = kindOf(ptrV);
    Type *et = elemT(isStore ? CI->getArgOperand(0)->getType() : t);
    uint64_t es = DL.getTypeStoreSize(et);
    Id stride = toWidth(CI->getArgOperand(pa + 1), 64, false), origin = get(CI->getArgOperand(pa + 2)), tr = get(CI->getArgOperand(pa + 3));
    Id ox = op(SO::OpCompositeExtract, u64(), {origin, 0}), oy = op(SO::OpCompositeExtract, u64(), {origin, 1});
    Id r = op(SO::OpUConvert, u64(), {rowOf()}), c = op(SO::OpUConvert, u64(), {colOf()});
    Id vals[2], mat = isStore ? get(CI->getArgOperand(0)) : 0;
    for (unsigned e = 0; e < 2; e++) {
        Id ce = op(SO::OpIAdd, u64(), {c, m.cU64(e)});
        Id mr = op(SO::OpSelect, u64(), {tr, ce, r}), mc = op(SO::OpSelect, u64(), {tr, r, ce});
        Id index = op(SO::OpIAdd, u64(), {op(SO::OpIMul, u64(), {op(SO::OpIAdd, u64(), {oy, mr}), stride}), op(SO::OpIAdd, u64(), {ox, mc})});
        Id off = op(SO::OpIMul, u64(), {index, m.cU64(es)});
        Id addr = k == PK::Phys ? op(SO::OpIAdd, u64(), {get(ptrV), off}) : op(SO::OpIAdd, u32(), {get(ptrV), op(SO::OpUConvert, u32(), {off})});
        if (isLoad) vals[e] = loadAny(k, addr, 0, et, es);
        else storeAny(k, addr, 0, et, ex(mat, et, e), es);
    }
    return isLoad ? op(SO::OpCompositeConstruct, ty(t), {vals[0], vals[1]}) : 0;
}

/* SIMD-group (subgroup) and quad-group operations -> GroupNonUniform. Metal SIMD groups are 32 lanes; that matches
 * Vulkan subgroups on NVIDIA, AMD RDNA (wave32) and Intel when the pipeline asks for 32. 8/16-bit values and half are
 * widened (no shaderSubgroupExtendedTypes needed). */
Id Fn::simd(CallInst *CI, StringRef name, bool quad) {
    Type *t = CI->getType();
    StringRef opn = name.split('.').first, tail = name.split('.').second;
    char k = (tail.size() > 1 && tail[1] == '.') ? tail[0] : 0;
    Id scope = m.cU32(uint32_t(spv::Scope::Subgroup));
    auto wideTy = [&](Type *x) -> Type * {
        Type *e = x->getScalarType(), *w = e;
        if (e->isHalfTy()) w = Type::getFloatTy(x->getContext());
        else if (e->isIntegerTy() && !e->isIntegerTy(1) && e->getIntegerBitWidth() < 32) w = Type::getInt32Ty(x->getContext());
        if (w == e) return x;
        if (auto v = dyn_cast<FixedVectorType>(x)) return FixedVectorType::get(w, v->getNumElements());
        return w;
    };
    auto widen = [&](Value *v) {
        Type *x = v->getType(), *w = wideTy(x);
        if (w == x) return get(v);
        return op(x->getScalarType()->isFloatingPointTy() ? SO::OpFConvert : k == 's' ? SO::OpSConvert : SO::OpUConvert, ty(w), {get(v)});
    };
    Type *wt = wideTy(t);
    auto narrow = [&](Id x) {
        if (wt == t) return x;
        return op(t->getScalarType()->isFloatingPointTy() ? SO::OpFConvert : SO::OpUConvert, ty(t), {x});
    };
    auto lane = [&]() { return builtinIn(spv::BuiltIn::SubgroupLocalInvocationId, u32()); };
    auto u = [&](unsigned i) { return toWidth(CI->getArgOperand(i), 32, false); };
    auto shuffle = [&](Id v, Id from) {
        m.cap(spv::Capability::GroupNonUniformShuffle);
        return op(SO::OpGroupNonUniformShuffle, ty(wt), {scope, v, from});
    };
    Type *e = wt->getScalarType();
    bool isF = e->isFloatingPointTy(), isB = e->isIntegerTy(1);

    if (opn == "any" || opn == "all") {
        if (quad) {
            m.cap(spv::Capability::GroupNonUniformClustered);
            return op(opn == "any" ? SO::OpGroupNonUniformLogicalOr : SO::OpGroupNonUniformLogicalAnd, m.tBool(),
                      {scope, uint32_t(spv::GroupOperation::ClusteredReduce), get(CI->getArgOperand(0)), m.cU32(4)});
        }
        m.cap(spv::Capability::GroupNonUniformVote);
        return op(opn == "any" ? SO::OpGroupNonUniformAny : SO::OpGroupNonUniformAll, m.tBool(), {scope, get(CI->getArgOperand(0))});
    }
    if (opn == "ballot" || opn == "active_threads_mask") {
        m.cap(spv::Capability::GroupNonUniformBallot);
        Id pred = opn == "ballot" ? get(CI->getArgOperand(0)) : m.cBool(true);
        Id b = op(SO::OpGroupNonUniformBallot, m.tVec(u32(), 4), {scope, pred});
        Id lo2 = op(SO::OpVectorShuffle, m.tVec(u32(), 2), {b, b, 0, 1});
        if (t->isIntegerTy(64)) return op(SO::OpBitcast, u64(), {lo2});
        if (t->isIntegerTy(32)) return op(SO::OpCompositeExtract, u32(), {b, 0});
        if (ty(t) == m.tVec(u32(), 2)) return lo2;
        fail("simd_ballot of an unexpected type");
    }
    if (opn == "is_first") {
        m.cap(spv::Capability::GroupNonUniform);
        return op(SO::OpGroupNonUniformElect, m.tBool(), {scope});
    }
    if (opn == "broadcast_first" && quad) {
        m.cap(spv::Capability::GroupNonUniformQuad);
        return narrow(op(SO::OpGroupNonUniformQuadBroadcast, ty(wt), {scope, widen(CI->getArgOperand(0)), m.cU32(0)}));
    }
    if (opn == "broadcast_first") {
        m.cap(spv::Capability::GroupNonUniformBallot);
        return narrow(op(SO::OpGroupNonUniformBroadcastFirst, ty(wt), {scope, widen(CI->getArgOperand(0))}));
    }
    if (opn == "broadcast" || opn == "shuffle") {
        Id from = u(1);
        if (quad) from = op(SO::OpBitwiseOr, u32(), {op(SO::OpBitwiseAnd, u32(), {lane(), m.cU32(~3u)}), op(SO::OpBitwiseAnd, u32(), {from, m.cU32(3)})});
        return narrow(shuffle(widen(CI->getArgOperand(0)), from));
    }
    if (opn == "shuffle_xor") {
        m.cap(spv::Capability::GroupNonUniformShuffle);
        Id mask = u(1);
        if (quad) mask = op(SO::OpBitwiseAnd, u32(), {mask, m.cU32(3)});
        return narrow(op(SO::OpGroupNonUniformShuffleXor, ty(wt), {scope, widen(CI->getArgOperand(0)), mask}));
    }
    if (opn == "shuffle_up" || opn == "shuffle_down") {
        Id v = widen(CI->getArgOperand(0)), d = u(1);
        if (quad) { /* stay inside the quad: lanes that would leave it keep their own value */
            Id q = op(SO::OpBitwiseAnd, u32(), {lane(), m.cU32(3)});
            Id inq = opn == "shuffle_up" ? op(SO::OpUGreaterThanEqual, m.tBool(), {q, d}) : op(SO::OpULessThan, m.tBool(), {op(SO::OpIAdd, u32(), {q, d}), m.cU32(4)});
            Id src = opn == "shuffle_up" ? op(SO::OpISub, u32(), {lane(), d}) : op(SO::OpIAdd, u32(), {lane(), d});
            return narrow(shuffle(v, op(SO::OpSelect, u32(), {inq, src, lane()})));
        }
        m.cap(spv::Capability::GroupNonUniformShuffleRelative);
        return narrow(op(opn == "shuffle_up" ? SO::OpGroupNonUniformShuffleUp : SO::OpGroupNonUniformShuffleDown, ty(wt), {scope, v, d}));
    }
    if (opn == "shuffle_rotate_up" || opn == "shuffle_rotate_down") {
        Id size = quad ? m.cU32(4) : builtinIn(spv::BuiltIn::SubgroupSize, u32());
        Id base = quad ? op(SO::OpBitwiseAnd, u32(), {lane(), m.cU32(~3u)}) : m.cU32(0);
        Id rel = op(SO::OpISub, u32(), {lane(), base});
        Id moved = opn == "shuffle_rotate_up" ? op(SO::OpISub, u32(), {op(SO::OpIAdd, u32(), {rel, size}), op(SO::OpUMod, u32(), {u(1), size})})
                                              : op(SO::OpIAdd, u32(), {rel, u(1)});
        return narrow(shuffle(widen(CI->getArgOperand(0)), op(SO::OpIAdd, u32(), {base, op(SO::OpUMod, u32(), {moved, size})})));
    }
    if (opn == "shuffle_and_fill_up" || opn == "shuffle_and_fill_down") {
        /* (data, filling, delta[, modulo]): within windows of `modulo` lanes, lanes whose source would leave the window
         * take `filling` from the matching lane on the other side */
        Id data = widen(CI->getArgOperand(0)), fill = widen(CI->getArgOperand(1)), d = u(2);
        Id mod = CI->arg_size() > 3 ? u(3) : (quad ? m.cU32(4) : builtinIn(spv::BuiltIn::SubgroupSize, u32()));
        Id l = lane(), w = op(SO::OpUMod, u32(), {l, mod});
        Id useData, idxD, idxF;
        if (opn == "shuffle_and_fill_up") {
            useData = op(SO::OpUGreaterThanEqual, m.tBool(), {w, d});
            idxD = op(SO::OpSelect, u32(), {useData, op(SO::OpISub, u32(), {l, d}), l});
            idxF = op(SO::OpSelect, u32(), {useData, l, op(SO::OpISub, u32(), {op(SO::OpIAdd, u32(), {l, mod}), d})});
        } else {
            useData = op(SO::OpULessThan, m.tBool(), {op(SO::OpIAdd, u32(), {w, d}), mod});
            idxD = op(SO::OpSelect, u32(), {useData, op(SO::OpIAdd, u32(), {l, d}), l});
            idxF = op(SO::OpSelect, u32(), {useData, l, op(SO::OpISub, u32(), {op(SO::OpIAdd, u32(), {l, d}), mod})});
        }
        Id a = shuffle(data, idxD), b = shuffle(fill, idxF);
        Id sel = useData;
        if (auto vt = dyn_cast<FixedVectorType>(wt)) sel = op(SO::OpCompositeConstruct, m.tVec(m.tBool(), vt->getNumElements()), Words(vt->getNumElements(), useData));
        return narrow(op(SO::OpSelect, ty(wt), {sel, a, b}));
    }
    /* reductions and scans */
    spv::GroupOperation g = spv::GroupOperation::Reduce;
    StringRef base = opn;
    if (base.consume_front("prefix_inclusive_")) g = spv::GroupOperation::InclusiveScan;
    else if (base.consume_front("prefix_exclusive_")) g = spv::GroupOperation::ExclusiveScan;
    bool sgn = k == 's';
    SO o = SO::OpNop;
    if (base == "sum") o = isF ? SO::OpGroupNonUniformFAdd : SO::OpGroupNonUniformIAdd;
    else if (base == "product") o = isF ? SO::OpGroupNonUniformFMul : SO::OpGroupNonUniformIMul;
    else if (base == "min") o = isF ? SO::OpGroupNonUniformFMin : sgn ? SO::OpGroupNonUniformSMin : SO::OpGroupNonUniformUMin;
    else if (base == "max") o = isF ? SO::OpGroupNonUniformFMax : sgn ? SO::OpGroupNonUniformSMax : SO::OpGroupNonUniformUMax;
    else if (base == "and") o = isB ? SO::OpGroupNonUniformLogicalAnd : SO::OpGroupNonUniformBitwiseAnd;
    else if (base == "or") o = isB ? SO::OpGroupNonUniformLogicalOr : SO::OpGroupNonUniformBitwiseOr;
    else if (base == "xor") o = isB ? SO::OpGroupNonUniformLogicalXor : SO::OpGroupNonUniformBitwiseXor;
    if (o == SO::OpNop) fail(std::string(quad ? "quad_" : "simd_") + opn.str());
    m.cap(spv::Capability::GroupNonUniformArithmetic);
    Words w{scope, uint32_t(g), widen(CI->getArgOperand(0))};
    if (quad && g == spv::GroupOperation::Reduce) {
        m.cap(spv::Capability::GroupNonUniformClustered);
        w[1] = uint32_t(spv::GroupOperation::ClusteredReduce);
        w.push_back(m.cU32(4));
    } else if (quad) fail("quad prefix");
    return narrow(op(o, ty(wt), w));
}

/* bindless resources (textures and samplers loaded from argument buffers, Metal resource IDs): descriptor set 2 of every
 * pipeline (Indium's bindless table): binding 0 sampled images, 1 storage images, 2 samplers; one array variable per
 * image type, all aliasing their binding. The 8-byte value in the argument buffer is the index. */
Id Fn::bindlessVar(const std::string &key, Id elemTy, uint32_t count, uint32_t binding) {
    Id &var = m.globals_by_name[key];
    if (!var) {
        var = m.var(m.tPtr(SC::UniformConstant, m.tArray(elemTy, count)), SC::UniformConstant);
        m.deco(var, spv::Decoration::DescriptorSet, {2});
        m.deco(var, spv::Decoration::Binding, {binding});
    }
    if (std::find(iface.begin(), iface.end(), var) == iface.end()) iface.push_back(var);
    return var;
}
static Id bindlessIndex(Fn &f, Value *v) { /* the low 32 bits of the 8-byte resource ID */
    Id raw = f.get(v);
    Id t = f.ty(v->getType());
    Id idx = t == f.u32() ? raw : t == f.u64() ? f.op(SO::OpUConvert, f.u32(), {raw}) : f.op(SO::OpUConvert, f.u32(), {f.op(SO::OpBitcast, f.u64(), {raw})});
    f.m.deco(idx, spv::Decoration::NonUniform);
    return idx;
}
Id Fn::bindlessTexture(CallInst *CI, StringRef name) {
    Value *texV = CI->getArgOperand(0);
    bool write = name.starts_with("write_") || name.contains("atomic");
    bool arrayed = name.contains("_array"), ms = name.contains("_ms"), depth = name.contains("depth");
    spv::Dim dim = name.contains("1d") ? spv::Dim::Dim1D : name.contains("3d") ? spv::Dim::Dim3D : name.contains("cube") ? spv::Dim::Cube : spv::Dim::Dim2D;
    unsigned dims = dim == spv::Dim::Dim1D ? 1 : dim == spv::Dim::Dim3D ? 3 : 2;
    if (arrayed) dims++;
    Id sampled = depth ? m.tFloat(32) : name.contains(".s.") ? m.type(SO::OpTypeInt, {32, 1}) : name.contains(".u.") ? u32() : m.tFloat(32);
    if (dim == spv::Dim::Dim1D) m.cap(write ? spv::Capability::Image1D : spv::Capability::Sampled1D);
    if (dim == spv::Dim::Cube && arrayed) m.cap(write ? spv::Capability::ImageCubeArray : spv::Capability::SampledCubeArray);
    if (write) { m.cap(spv::Capability::StorageImageReadWithoutFormat); m.cap(spv::Capability::StorageImageWriteWithoutFormat); }
    if (ms && write) m.cap(spv::Capability::StorageImageMultisample);
    Id imgTy = m.type(SO::OpTypeImage, {sampled, uint32_t(dim), depth ? 1u : 0u, arrayed ? 1u : 0u, ms ? 1u : 0u, write ? 2u : 1u, uint32_t(spv::ImageFormat::Unknown)});
    Id var = bindlessVar("bindless.image." + std::to_string(imgTy), imgTy, 8192, write ? 1 : 0);
    m.cap(spv::Capability::ShaderNonUniform);
    m.cap(write ? spv::Capability::StorageImageArrayNonUniformIndexing : spv::Capability::SampledImageArrayNonUniformIndexing);
    Id ptr = op(SO::OpAccessChain, m.tPtr(SC::UniformConstant, imgTy), {var, bindlessIndex(*this, texV)});
    m.deco(ptr, spv::Decoration::NonUniform);
    texType[ptr] = imgTy; texDims[ptr] = dims; texSampled[ptr] = sampled;
    texAccess[texV] = write ? Iridium::TextureAccessType::ReadWrite : Iridium::TextureAccessType::Sample;
    bindlessPtrs.insert(ptr);
    return ptr;
}
/* Metal encodes writes to sRGB textures; Vulkan has no sRGB storage images, so Indium binds a UNORM view and sets this
 * texture's bit in the push constants: the shader encodes linear -> sRGB itself. ponytail: argument-buffer textures are not encoded */
Id Fn::srgbEncode(Id tvar, Id v) {
    auto it = texLoc.find(tvar);
    if (it == texLoc.end() || it->second >= 32 || texSampled.lookup(tvar) != m.tFloat(32)) return v;
    Id f32 = m.tFloat(32), v3 = m.tVec(f32, 3), v4 = m.tVec(f32, 4), b = m.tBool(), b3 = m.tVec(b, 3);
    if (!pcVar) {
        Id st = m.tStructUnique({u32(), u32()});
        m.memberDeco(st, 0, spv::Decoration::Offset, {0});
        m.memberDeco(st, 1, spv::Decoration::Offset, {4});
        m.deco(st, spv::Decoration::Block);
        pcVar = m.var(m.tPtr(SC::PushConstant, st), SC::PushConstant);
        iface.push_back(pcVar);
    }
    auto fc = [&](float x) { uint32_t w; memcpy(&w, &x, 4); return m.constant(f32, {w}); };
    auto splat = [&](float x) { Id c = fc(x); return m.cComposite(v3, {c, c, c}); };
    Id mask = op(SO::OpLoad, u32(), {op(SO::OpAccessChain, m.tPtr(SC::PushConstant, u32()), {pcVar, m.cU32(stage == Iridium::FunctionType::Fragment ? 1 : 0)})});
    Id on = op(SO::OpINotEqual, b, {op(SO::OpBitwiseAnd, u32(), {op(SO::OpShiftRightLogical, u32(), {mask, m.cU32(it->second)}), m.cU32(1)}), m.cU32(0)});
    Id c = ext(v3, GLSLstd450FClamp, {op(SO::OpVectorShuffle, v3, {v, v, 0, 1, 2}), splat(0), splat(1)});
    Id lo = op(SO::OpVectorTimesScalar, v3, {c, fc(12.92f)});
    Id hi = op(SO::OpFSub, v3, {op(SO::OpVectorTimesScalar, v3, {ext(v3, GLSLstd450Pow, {c, splat(1 / 2.4f)}), fc(1.055f)}), splat(0.055f)});
    Id enc = op(SO::OpSelect, v3, {op(SO::OpFOrdLessThanEqual, b3, {c, splat(0.0031308f)}), lo, hi});
    return op(SO::OpSelect, v4, {on, op(SO::OpVectorShuffle, v4, {enc, v, 0, 1, 2, 6}), v});
}

Id Fn::bindlessSampler(Value *sV) {
    Id smpTy = m.type(SO::OpTypeSampler, {});
    Id var = bindlessVar("bindless.sampler", smpTy, 1024, 2);
    m.cap(spv::Capability::ShaderNonUniform);
    Id ptr = op(SO::OpAccessChain, m.tPtr(SC::UniformConstant, smpTy), {var, bindlessIndex(*this, sV)});
    m.deco(ptr, spv::Decoration::NonUniform);
    return ptr;
}

/* textures: air.sample_texture_2d.v4f32, air.read_texture_2d.v4f32, air.write_texture_2d.v4f32, air.get_width_texture_2d ... */
Id Fn::airTexture(CallInst *CI, StringRef name) {
    Value *texV = CI->getArgOperand(0);
    Id tvar = handles.lookup(texV);
    if (!tvar) tvar = bindlessTexture(CI, name); /* a texture from an argument buffer */
    Id imgTy = texType.lookup(tvar);
    Id img = op(SO::OpLoad, imgTy, {tvar});
    if (bindlessPtrs.count(tvar)) m.deco(img, spv::Decoration::NonUniform);
    Type *t = CI->getType();
    auto arg = [&](unsigned i) { return get(CI->getArgOperand(i)); };
    bool depthTex = name.contains("depth");
    if (name.contains(".mw.")) return mwTexture(CI, name, tvar, imgTy, img);
    if (name.starts_with("calculate_lod")) { /* scion: { clamped, unclamped } LOD (calculate_[un]clamped_lod); implicit
                                                derivatives exist only in fragment shaders: 0 elsewhere, as Metal */
        if (stage != Iridium::FunctionType::Fragment) return cst(Constant::getNullValue(t));
        Value *sV = CI->getArgOperand(1);
        Id svar = handles.lookup(sV);
        if (!svar) svar = bindlessSampler(sV);
        Id smp = op(SO::OpLoad, m.type(SO::OpTypeSampler, {}), {svar});
        Id si = op(SO::OpSampledImage, m.type(SO::OpTypeSampledImage, {imgTy}), {img, smp});
        m.cap(spv::Capability::ImageQuery);
        Id r = op(SO::OpImageQueryLod, m.tVec(m.tFloat(32), 2), {si, arg(2)});
        return ty(t) != m.tVec(m.tFloat(32), 2) ? op(SO::OpFConvert, ty(t), {r}) : r;
    }
    if (name.starts_with("sample_") || name.starts_with("sample_compare")) {
        Value *sV = CI->getArgOperand(1);
        Id svar = handles.lookup(sV);
        if (!svar) svar = bindlessSampler(sV);
        Id smp = op(SO::OpLoad, m.type(SO::OpTypeSampler, {}), {svar});
        Id si = op(SO::OpSampledImage, m.type(SO::OpTypeSampledImage, {imgTy}), {img, smp});
        Id coord = arg(2);
        /* array textures pass the slice separately: fold it into the coordinate */
        unsigned next = 3;
        if (name.contains("_array")) {
            Value *slice = CI->getArgOperand(3);
            Id sf = op(SO::OpConvertUToF, m.tFloat(32), {get(slice)});
            unsigned n = cast<FixedVectorType>(CI->getArgOperand(2)->getType())->getNumElements();
            Words parts;
            for (unsigned i = 0; i < n; i++) parts.push_back(op(SO::OpCompositeExtract, m.tFloat(32), {coord, i}));
            parts.push_back(sf);
            coord = op(SO::OpCompositeConstruct, m.tVec(m.tFloat(32), n + 1), parts);
            next = 4;
        }
        Id dref = 0;
        if (name.starts_with("sample_compare")) dref = get(CI->getArgOperand(next++));
        Id v4 = m.tVec(m.tFloat(32), 4);
        Id res;
        bool frag = stage == Iridium::FunctionType::Fragment;
        if (dref) {
            Id f = m.tFloat(32);
            res = frag ? op(SO::OpImageSampleDrefImplicitLod, f, {si, coord, dref})
                       : op(SO::OpImageSampleDrefExplicitLod, f, {si, coord, dref, uint32_t(spv::ImageOperandsMask::Lod), cst(ConstantFP::get(Type::getFloatTy(CI->getContext()), 0.0))});
        } else {
            res = frag ? op(SO::OpImageSampleImplicitLod, v4, {si, coord})
                       : op(SO::OpImageSampleExplicitLod, v4, {si, coord, uint32_t(spv::ImageOperandsMask::Lod), cst(ConstantFP::get(Type::getFloatTy(CI->getContext()), 0.0))});
        }
        /* result: { <4 x T>, i8 residency } or T */
        Type *rv = t->isStructTy() ? t->getStructElementType(0) : t;
        if (dref && !rv->isVectorTy()) { /* scalar depth compare */
            if (rv->isHalfTy()) res = op(SO::OpFConvert, ty(rv), {res});
        } else if (rv->getScalarType()->isHalfTy()) res = op(SO::OpFConvert, ty(rv), {res});
        if (t->isStructTy()) {
            Id s = op(SO::OpCompositeInsert, ty(t), {res, m.undef(ty(t)), 0});
            return op(SO::OpCompositeInsert, ty(t), {cInt(t->getStructElementType(1), 1), s, 1});
        }
        return res;
    }
    if (name.starts_with("read_")) {
        Id coord = arg(1);
        Type *rv = t->isStructTy() ? t->getStructElementType(0) : t;
        Type *et = rv->getScalarType();
        Id sampled = texSampled.lookup(tvar);
        Id v4 = m.tVec(sampled, 4);
        bool storage = texAccess.lookup(texV) != Iridium::TextureAccessType::Sample;
        Id res;
        if (storage) res = op(SO::OpImageRead, v4, {img, coord});
        else {
            unsigned lodArg = name.contains("_array") ? 3 : 2;
            Words w{img, coord};
            if (lodArg < CI->arg_size() && !name.contains("_ms")) { w.push_back(uint32_t(spv::ImageOperandsMask::Lod)); w.push_back(toWidth(CI->getArgOperand(lodArg), 32, false)); }
            res = op(SO::OpImageFetch, v4, w);
        }
        if (!et->isFloatingPointTy() && sampled != u32()) res = op(SO::OpBitcast, m.tVec(u32(), 4), {res});
        if (ty(rv) != m.tVec(et->isFloatingPointTy() ? m.tFloat(32) : u32(), 4)) res = et->isFloatingPointTy() ? op(SO::OpFConvert, ty(rv), {res}) : op(SO::OpUConvert, ty(rv), {res});
        if (t->isStructTy()) {
            Id s = op(SO::OpCompositeInsert, ty(t), {res, m.undef(ty(t)), 0});
            return op(SO::OpCompositeInsert, ty(t), {cInt(t->getStructElementType(1), 1), s, 1});
        }
        return res;
    }
    if (name.starts_with("write_")) {
        Value *val = CI->getArgOperand(2);
        Type *vt = val->getType();
        Id v = get(val);
        Type *et = vt->getScalarType();
        if (et->isHalfTy()) v = op(SO::OpFConvert, m.tVec(m.tFloat(32), 4), {v});
        else if (et->isIntegerTy() && et->getIntegerBitWidth() != 32) v = op(SO::OpUConvert, m.tVec(m.tInt(32), 4), {v});
        if (et->isIntegerTy() && texSampled.lookup(tvar) != u32()) v = op(SO::OpBitcast, m.tVec(texSampled.lookup(tvar), 4), {v});
        m.cap(spv::Capability::StorageImageWriteWithoutFormat);
        if (et->isFloatingPointTy()) v = srgbEncode(tvar, v);
        opv(SO::OpImageWrite, {img, arg(1), v});
        return 0;
    }
    if (name.starts_with("get_width") || name.starts_with("get_height") || name.starts_with("get_depth") || name.starts_with("get_array_size")) {
        m.cap(spv::Capability::ImageQuery);
        unsigned comps = texDims.lookup(tvar);
        Id st = m.tVec(u32(), comps);
        bool storage = texAccess.lookup(texV) != Iridium::TextureAccessType::Sample;
        Id size = storage ? op(SO::OpImageQuerySize, st, {img}) : op(SO::OpImageQuerySizeLod, st, {img, CI->arg_size() > 1 ? toWidth(CI->getArgOperand(1), 32, false) : m.cU32(0)});
        unsigned which = name.starts_with("get_width") ? 0 : name.starts_with("get_height") ? 1 : comps - 1;
        Id r = comps == 1 ? size : op(SO::OpCompositeExtract, u32(), {size, which});
        if (ty(t) != u32()) r = op(SO::OpUConvert, ty(t), {r});
        return r;
    }
    if (name.starts_with("get_num_mip_levels")) {
        m.cap(spv::Capability::ImageQuery);
        Id r = op(SO::OpImageQueryLevels, u32(), {img});
        return ty(t) != u32() ? op(SO::OpUConvert, ty(t), {r}) : r;
    }
    fail("texture: " + name.str());
}

/* the extended texture calls scion's own MSL compiler emits (msl/metal_stdlib.h), all with explicit operands:
 *   sample_*.mw         (tex, smp, coord, slice, mode, a, dx, dy, offset)        mode: 0 implicit, 1 lod a, 2 bias a, 3 grad dx/dy
 *   sample_compare_*.mw (tex, smp, coord, slice, dref, mode, a, dx, dy, offset)
 *   gather_*.mw         (tex, smp, coord, slice, offset, component)
 *   gather_compare_*.mw (tex, smp, coord, slice, dref, offset)
 *   read_*.mw           (tex, coord, slice, lod | sample)
 *   write_*.mw          (tex, coord, value, slice, lod) */
Id Fn::mwTexture(CallInst *CI, StringRef name, Id tvar, Id imgTy, Id img) {
    Type *t = CI->getType();
    Value *texV = CI->getArgOperand(0);
    bool arrayed = name.contains("_array"), cube = name.contains("cube"), ms = name.contains("_ms");
    bool frag = stage == Iridium::FunctionType::Fragment;
    Id f32 = m.tFloat(32);
    auto addSlice = [&](Value *coordV, Value *sliceV, bool asFloat) { /* append the array slice (or cube face) to the coordinate */
        Id c = get(coordV);
        Type *ct = coordV->getType();
        unsigned n = ct->isVectorTy() ? cast<FixedVectorType>(ct)->getNumElements() : 1;
        Id et = asFloat ? f32 : u32();
        Id s = toWidth(sliceV, 32, false);
        if (asFloat) s = op(SO::OpConvertUToF, f32, {s});
        Words parts;
        for (unsigned i = 0; i < n; i++) parts.push_back(n == 1 ? c : op(SO::OpCompositeExtract, et, {c, i}));
        parts.push_back(s);
        return op(SO::OpCompositeConstruct, m.tVec(et, n + 1), parts);
    };
    auto coordDims = [&](Value *coordV) { Type *ct = coordV->getType(); return ct->isVectorTy() ? cast<FixedVectorType>(ct)->getNumElements() : 1u; };
    /* constant offsets (ConstOffset); non-zero variable ones need ImageGatherExtended (Offset) */
    auto offsetOperand = [&](Value *offV, unsigned dims, Words &ops, uint32_t &mask) {
        if (cube) return;
        if (auto *c = dyn_cast<Constant>(offV); c && c->isNullValue()) return;
        Words comps;
        Id it = m.tInt(32);
        Id ov = get(offV);
        for (unsigned i = 0; i < dims; i++) comps.push_back(op(SO::OpCompositeExtract, it, {ov, i}));
        Id v = dims == 1 ? comps[0] : op(SO::OpCompositeConstruct, m.tVec(it, dims), comps);
        if (isa<Constant>(offV)) {
            Constant *c = cast<Constant>(offV);
            Words cw;
            for (unsigned i = 0; i < dims; i++) cw.push_back(cst(c->getAggregateElement(i)));
            mask |= uint32_t(spv::ImageOperandsMask::ConstOffset);
            ops.push_back(dims == 1 ? cw[0] : m.cComposite(m.tVec(it, dims), cw));
        } else {
            m.cap(spv::Capability::ImageGatherExtended);
            mask |= uint32_t(spv::ImageOperandsMask::Offset);
            ops.push_back(v);
        }
    };
    auto finish = [&](Id res, Id resTy) { /* to the call's vector type (half / 16-bit / signedness) */
        if (resTy == ty(t)) return res;
        Type *et = t->getScalarType();
        if (et->isFloatingPointTy()) return op(SO::OpFConvert, ty(t), {res});
        return op(SO::OpBitcast, ty(t), {res});
    };
    Id sampled = texSampled.lookup(tvar);
    Id v4 = m.tVec(sampled, 4);
    if (name.starts_with("sample_") || name.starts_with("gather_")) {
        Id svar = handles.lookup(CI->getArgOperand(1));
        if (!svar) svar = bindlessSampler(CI->getArgOperand(1)); /* a sampler from an argument buffer */
        Id smp = op(SO::OpLoad, m.type(SO::OpTypeSampler, {}), {svar});
        Id si = op(SO::OpSampledImage, m.type(SO::OpTypeSampledImage, {imgTy}), {img, smp});
        Value *coordV = CI->getArgOperand(2);
        unsigned dims = coordDims(coordV);
        Id coord = arrayed ? addSlice(coordV, CI->getArgOperand(3), true) : get(coordV);
        bool cmp = name.contains("_compare");
        unsigned next = 4;
        Id dref = cmp ? get(CI->getArgOperand(next++)) : 0;
        if (name.starts_with("gather_")) {
            Words ops{si, coord};
            if (cmp) ops.push_back(dref);
            else ops.push_back(toWidth(CI->getArgOperand(next + 1), 32, false));
            uint32_t mask = 0;
            Words extra;
            offsetOperand(CI->getArgOperand(next), dims, extra, mask);
            if (mask) { ops.push_back(mask); ops.insert(ops.end(), extra.begin(), extra.end()); }
            Id rt = cmp ? m.tVec(f32, 4) : v4;
            return finish(op(cmp ? SO::OpImageDrefGather : SO::OpImageGather, rt, ops), rt);
        }
        auto *modeC = dyn_cast<ConstantInt>(CI->getArgOperand(next));
        if (!modeC) fail("non-constant sampling mode");
        int mode = int(modeC->getZExtValue());
        Value *aV = CI->getArgOperand(next + 1), *dxV = CI->getArgOperand(next + 2), *dyV = CI->getArgOperand(next + 3), *offV = CI->getArgOperand(next + 4);
        if (!frag && (mode == 0 || mode == 2)) mode = -1; /* implicit lod only exists in fragment shaders: lod 0 */
        uint32_t mask = 0;
        Words ops;
        if (mode == 2) { mask |= uint32_t(spv::ImageOperandsMask::Bias); ops.push_back(get(aV)); }
        if (mode == 1) { mask |= uint32_t(spv::ImageOperandsMask::Lod); ops.push_back(get(aV)); }
        if (mode == -1) { mask |= uint32_t(spv::ImageOperandsMask::Lod); ops.push_back(cst(ConstantFP::get(Type::getFloatTy(CI->getContext()), 0.0))); }
        if (mode == 3) {
            mask |= uint32_t(spv::ImageOperandsMask::Grad);
            unsigned gd = cube ? 3 : dims;
            for (Value *g : {dxV, dyV}) {
                Id gv = get(g);
                Words w{gv, gv};
                for (unsigned i = 0; i < gd; i++) w.push_back(i);
                ops.push_back(gd == 1 ? op(SO::OpCompositeExtract, f32, {gv, 0}) : op(SO::OpVectorShuffle, m.tVec(f32, gd), w));
            }
        }
        offsetOperand(offV, dims, ops, mask);
        bool explicitLod = mask & (uint32_t(spv::ImageOperandsMask::Lod) | uint32_t(spv::ImageOperandsMask::Grad));
        Words w{si, coord};
        if (cmp) w.push_back(dref);
        if (mask) { w.push_back(mask); w.insert(w.end(), ops.begin(), ops.end()); }
        if (cmp) {
            Id r = op(explicitLod ? SO::OpImageSampleDrefExplicitLod : SO::OpImageSampleDrefImplicitLod, f32, w);
            return t->isHalfTy() ? op(SO::OpFConvert, ty(t), {r}) : r;
        }
        return finish(op(explicitLod ? SO::OpImageSampleExplicitLod : SO::OpImageSampleImplicitLod, v4, w), v4);
    }
    bool storage = texAccess.lookup(texV) != Iridium::TextureAccessType::Sample;
    if (name.starts_with("read_")) {
        Value *coordV = CI->getArgOperand(1);
        Id coord = (arrayed || cube) ? addSlice(coordV, CI->getArgOperand(2), false) : get(coordV);
        Words w{img, coord};
        Id lod = toWidth(CI->getArgOperand(3), 32, false);
        if (ms) { w.push_back(uint32_t(spv::ImageOperandsMask::Sample)); w.push_back(lod); }
        else if (!storage) { w.push_back(uint32_t(spv::ImageOperandsMask::Lod)); w.push_back(lod); }
        return finish(op(storage ? SO::OpImageRead : SO::OpImageFetch, v4, w), v4);
    }
    if (name.starts_with("write_")) {
        Value *coordV = CI->getArgOperand(1), *val = CI->getArgOperand(2);
        Id coord = (arrayed || cube) ? addSlice(coordV, CI->getArgOperand(3), false) : get(coordV);
        Id v = get(val);
        Type *et = val->getType()->getScalarType();
        if (et->isHalfTy()) v = op(SO::OpFConvert, m.tVec(f32, 4), {v});
        else if (et->isIntegerTy() && et->getIntegerBitWidth() != 32) v = op(SO::OpUConvert, m.tVec(u32(), 4), {v});
        if (et->isIntegerTy() && sampled != u32()) v = op(SO::OpBitcast, m.tVec(sampled, 4), {v});
        if (et->isFloatingPointTy() && sampled != f32) v = op(SO::OpBitcast, m.tVec(sampled, 4), {v});
        if (et->isFloatingPointTy()) v = srgbEncode(tvar, v);
        opv(SO::OpImageWrite, {img, coord, v});
        return 0;
    }
    fail("texture: " + name.str());
}

/* ====================================================================== interface (arguments, outputs) */
struct BuiltinDef { const char *air; spv::BuiltIn b; int comps; bool isFloat; };
const BuiltinDef kBuiltins[] = {
    {"air.thread_position_in_grid", spv::BuiltIn::GlobalInvocationId, 3, false},
    {"air.thread_position_in_threadgroup", spv::BuiltIn::LocalInvocationId, 3, false},
    {"air.threadgroup_position_in_grid", spv::BuiltIn::WorkgroupId, 3, false},
    {"air.threadgroups_per_grid", spv::BuiltIn::NumWorkgroups, 3, false},
    {"air.thread_index_in_threadgroup", spv::BuiltIn::LocalInvocationIndex, 1, false},
    {"air.vertex_id", spv::BuiltIn::VertexIndex, 1, false},
    {"air.instance_id", spv::BuiltIn::InstanceIndex, 1, false},
    {"air.base_vertex", spv::BuiltIn::BaseVertex, 1, false},
    {"air.base_instance", spv::BuiltIn::BaseInstance, 1, false},
    {"air.position", spv::BuiltIn::FragCoord, 4, true},
    {"air.front_facing", spv::BuiltIn::FrontFacing, 0 /* bool */, false},
    {"air.sample_id", spv::BuiltIn::SampleId, 1, false},
    {"air.point_coord", spv::BuiltIn::PointCoord, 2, true},
    {"air.thread_index_in_simdgroup", spv::BuiltIn::SubgroupLocalInvocationId, 1, false},
    {"air.simdgroup_index_in_threadgroup", spv::BuiltIn::SubgroupId, 1, false},
    {"air.threads_per_simdgroup", spv::BuiltIn::SubgroupSize, 1, false},
    {"air.thread_execution_width", spv::BuiltIn::SubgroupSize, 1, false},
    {"air.primitive_id", spv::BuiltIn::PrimitiveId, 1, false},
    {"air.render_target_array_index", spv::BuiltIn::Layer, 1, false},
    {"air.viewport_array_index", spv::BuiltIn::ViewportIndex, 1, false},
};

/* "user(locn3)" -> 3, otherwise -1 */
/* user(locnL_C): component C of location L */
uint32_t userComponent(const std::string &n) {
    auto p = n.find("locn");
    if (p == std::string::npos) return 0;
    auto u = n.find('_', p);
    return u == std::string::npos ? 0 : uint32_t(atoi(n.c_str() + u + 1));
}
int userLocation(const std::string &n) {
    auto p = n.find("locn");
    if (n.rfind("user(", 0) == 0 && p != std::string::npos) return atoi(n.c_str() + p + 4);
    return -1;
}

/* 16-bit and 8-bit values can't cross stage interfaces without optional features: widen them to 32 bits */
Type *widenIO(Type *t) {
    Type *e = t->getScalarType();
    Type *w = e;
    if (e->isHalfTy()) w = Type::getFloatTy(t->getContext());
    else if (e->isIntegerTy() && e->getIntegerBitWidth() < 32) w = Type::getInt32Ty(t->getContext());
    if (w == e) return t;
    if (auto v = dyn_cast<FixedVectorType>(t)) return FixedVectorType::get(w, v->getNumElements());
    return w;
}

void serialize(const Constant *C, const DataLayout &DL, uint8_t *dst) {
    Type *t = C->getType();
    if (isa<UndefValue>(C) || isa<ConstantAggregateZero>(C) || C->isNullValue()) return; /* already zero */
    if (auto ci = dyn_cast<ConstantInt>(C)) { uint64_t v = ci->getZExtValue(); memcpy(dst, &v, std::min<uint64_t>(8, DL.getTypeStoreSize(t))); return; }
    if (auto cf = dyn_cast<ConstantFP>(C)) { uint64_t v = cf->getValueAPF().bitcastToAPInt().getZExtValue(); memcpy(dst, &v, DL.getTypeStoreSize(t)); return; }
    if (auto cds = dyn_cast<ConstantDataSequential>(C)) { memcpy(dst, cds->getRawDataValues().data(), cds->getRawDataValues().size()); return; }
    if (auto s = dyn_cast<StructType>(t)) {
        auto *sl = DL.getStructLayout(s);
        for (unsigned i = 0; i < s->getNumElements(); i++) serialize(C->getAggregateElement(i), DL, dst + sl->getElementOffset(i));
        return;
    }
    if (t->isArrayTy() || t->isVectorTy()) {
        Type *e = t->isArrayTy() ? t->getArrayElementType() : cast<FixedVectorType>(t)->getElementType();
        uint64_t stride = t->isArrayTy() ? DL.getTypeAllocSize(e) : DL.getTypeStoreSize(e);
        unsigned n = t->isArrayTy() ? t->getArrayNumElements() : cast<FixedVectorType>(t)->getNumElements();
        for (unsigned i = 0; i < n; i++) serialize(C->getAggregateElement(i), DL, dst + i * stride);
        return;
    }
    fail("unsupported constant initializer");
}

void collectGlobals(const Value *v, SmallPtrSetImpl<const GlobalVariable *> &out) {
    if (auto g = dyn_cast<GlobalVariable>(v)) { out.insert(g); return; }
    if (auto ce = dyn_cast<ConstantExpr>(v))
        for (auto &o : ce->operands()) collectGlobals(o, out);
}

/* SPIR-V structured control flow: every construct needs its own merge block.
 *  - a loop header can't also be a selection header: split it when its conditional branch stays inside the loop;
 *  - when two constructs would merge at the same block (or a selection at a loop's continue/merge block), the inner
 *    one gets a new block in front of it (SplitBlockPredecessors keeps phis right). */
void separateMerges(Function &F) {
    for (int round = 0; round < 256; round++) {
        DominatorTree DT(F);
        PostDominatorTree PDT(F);
        LoopInfo LI(DT);
        bool changed = false;
        for (Loop *L : LI.getLoopsInPreorder()) {
            BasicBlock *H = L->getHeader();
            auto *br = dyn_cast<BranchInst>(H->getTerminator());
            if (br && br->isConditional() && L->contains(br->getSuccessor(0)) && L->contains(br->getSuccessor(1))) {
                SplitBlock(H, H->getTerminator(), &DT, &LI, nullptr, H->getName() + ".body");
                changed = true;
                break;
            }
        }
        if (changed) continue;
        DenseMap<BasicBlock *, BasicBlock *> claimed; /* merge/continue block -> header that owns it */
        for (Loop *L : LI.getLoopsInPreorder()) { /* outer loops first */
            SmallVector<BasicBlock *, 2> exits;
            L->getUniqueExitBlocks(exits);
            for (auto *e : exits) {
                auto it = claimed.find(e);
                if (it != claimed.end() && it->second != L->getHeader()) {
                    /* e.g. an inner loop leaving straight into the outer loop's continue block: give it its own merge */
                    SmallVector<BasicBlock *, 4> preds;
                    for (BasicBlock *p : predecessors(e))
                        if (L->contains(p)) preds.push_back(p);
                    SplitBlockPredecessors(e, preds, ".loopmerge", &DT, &LI);
                    changed = true;
                    break;
                }
                claimed[e] = L->getHeader();
            }
            if (changed) break;
            if (auto *latch = L->getLoopLatch(); latch && latch != L->getHeader()) claimed[latch] = L->getHeader();
        }
        if (changed) continue;
        for (BasicBlock *B : post_order(&F)) {
            auto *br = dyn_cast<BranchInst>(B->getTerminator());
            if (!br || !br->isConditional()) continue;
            Loop *L = LI.getLoopFor(B);
            if (L && (L->getHeader() == B || L->getLoopLatch() == B)) continue;
            auto *node = PDT.getNode(B);
            BasicBlock *M = node && node->getIDom() ? node->getIDom()->getBlock() : nullptr;
            if (!M || (L && !L->contains(M))) continue; /* break-style branch: handled at emission */
            auto it = claimed.find(M);
            if (it == claimed.end()) { claimed[M] = B; continue; }
            BasicBlock *C = it->second;
            bool loopOwned = LI.isLoopHeader(C) && LI.getLoopFor(C)->getHeader() == C;
            BasicBlock *inner = (!loopOwned && DT.dominates(B, C)) ? C : B;
            SmallVector<BasicBlock *, 4> preds;
            for (BasicBlock *p : predecessors(M))
                if (DT.dominates(inner, p)) preds.push_back(p);
            if (preds.empty()) continue;
            SplitBlockPredecessors(M, preds, ".merge", &DT, &LI);
            changed = true;
            break;
        }
        if (!changed) return;
    }
    fail("could not structure the control flow");
}

} // namespace

/* ====================================================================== interface and function body */
namespace {
void Fn::setupInterface(const MDNode *root) {
    bool frag = stage == Iridium::FunctionType::Fragment;
    uint32_t descSet = frag ? 1 : 0;
    auto inputVar = [&](Id t, std::function<void(Id)> deco) {
        Id v = m.var(m.tPtr(SC::Input, t), SC::Input);
        deco(v);
        iface.push_back(v);
        return op(SO::OpLoad, t, {v});
    };
    auto builtin = [&](spv::BuiltIn b, Id t) { return builtinIn(b, t); };
    if (stage == Iridium::FunctionType::Kernel) {
        Words ids;
        for (uint32_t i = 0; i < 3; i++) {
            Id c = m.id();
            a2s::emit(m.globals, SO::OpSpecConstant, {u32(), c, 1});
            m.deco(c, spv::Decoration::SpecId, {i});
            ids.push_back(c);
        }
        a2s::emit(m.modes, SO::OpExecutionModeId, {fnId, uint32_t(spv::ExecutionMode::LocalSizeId), ids[0], ids[1], ids[2]});
        wgSize = m.id();
        a2s::emit(m.globals, SO::OpSpecConstantComposite, {m.tVec(u32(), 3), wgSize, ids[0], ids[1], ids[2]});
        /* dispatchThreads with a grid that is not a multiple of the threadgroup: the dispatch rounds up and specialization
         * constants 3..5 carry the real grid (0: whole threadgroups); threads outside it return at once
         * (ponytail: they leave early, so a threadgroup barrier in a partial group relies on the driver tolerating that) */
        Id lim = m.id(); Words lids;
        for (uint32_t i = 0; i < 3; i++) {
            Id c = m.id();
            a2s::emit(m.globals, SO::OpSpecConstant, {u32(), c, 0});
            m.deco(c, spv::Decoration::SpecId, {3 + i});
            lids.push_back(c);
        }
        Id v3 = m.tVec(u32(), 3), b3 = m.tVec(m.tBool(), 3);
        a2s::emit(m.globals, SO::OpSpecConstantComposite, {v3, lim, lids[0], lids[1], lids[2]});
        Id none = op(SO::OpIEqual, b3, {lim, m.cNull(v3)});
        Id gid = builtin(spv::BuiltIn::GlobalInvocationId, v3);
        inGrid = op(SO::OpAll, m.tBool(), {op(SO::OpLogicalOr, b3, {none, op(SO::OpULessThan, b3, {gid, lim})})});
        gridSize = op(SO::OpSelect, v3, {none, op(SO::OpIMul, v3, {builtin(spv::BuiltIn::NumWorkgroups, v3), wgSize}), lim});
    }

    auto *params = cast<MDNode>(root->getOperand(2));
    /* buffers first: they share one UBO of 64-bit addresses at binding 0 */
    for (auto &po : params->operands()) {
        auto *pn = cast<MDNode>(po);
        std::string kind = mdStr(pn->getOperand(1));
        if (kind == "air.function_constant") kind = mdStr(pn->getOperand(3));
        if (kind == "air.buffer" || kind == "air.indirect_buffer") bufCount++;
    }
    if (bufCount) {
        Words mem(bufCount, u64());
        Id st = m.tStructUnique(mem);
        for (uint32_t i = 0; i < bufCount; i++) m.memberDeco(st, i, spv::Decoration::Offset, {i * 8});
        m.deco(st, spv::Decoration::Block);
        uboVar = m.var(m.tPtr(SC::Uniform, st), SC::Uniform);
        m.deco(uboVar, spv::Decoration::DescriptorSet, {descSet});
        m.deco(uboVar, spv::Decoration::Binding, {0});
        iface.push_back(uboVar);
        internal = 1;
    }
    uint32_t bufIndex = 0, fragLoc = 0;
    SmallVector<std::pair<Argument *, const MDNode *>, 4> textures, samplers;
    for (auto &po : params->operands()) {
        auto *pn = cast<MDNode>(po);
        unsigned idx = unsigned(mdInt(pn->getOperand(0)));
        std::string kind = mdStr(pn->getOperand(1));
        if (kind == "air.function_constant") kind = mdStr(pn->getOperand(3)); /* argument present only if a constant is true */
        Argument *A = F.getArg(idx);
        Type *at = A->getType();
        if (kind == "air.buffer" || kind == "air.indirect_buffer") {
            int64_t loc = mdAfter(pn, "air.location_index");
            info.bindings.push_back({Iridium::BindingType::Buffer, size_t(loc), 0, Iridium::TextureAccessType::Read, 0});
            /* argument buffer layout for MTLArgumentEncoder (scion's MSL compiler); size from air.arg_type_size */
            if (int64_t sz = mdAfter(pn, "air.arg_type_size"); sz > 0) info.argumentSizes[size_t(loc)] = size_t(sz);
            for (unsigned i = 0; i + 1 < pn->getNumOperands(); i++)
                if (mdStr(pn->getOperand(i)) == "mw.argument_ids")
                    if (auto *ids = dyn_cast<MDNode>(pn->getOperand(i + 1)); ids) {
                        auto &out = info.argumentIds[size_t(loc)];
                        for (unsigned j = 0; j + 3 < ids->getNumOperands(); j += 4)
                            out.push_back({mdInt(ids->getOperand(j)), mdInt(ids->getOperand(j + 1)), mdInt(ids->getOperand(j + 2)), mdInt(ids->getOperand(j + 3))});
                    }
            Id p = op(SO::OpAccessChain, m.tPtr(SC::Uniform, u64()), {uboVar, m.cU32(bufIndex++)});
            vals[A] = op(SO::OpLoad, u64(), {p});
            kinds[A] = PK::Phys;
        } else if (kind == "air.vertex_input" || kind == "air.fragment_input") {
            Type *wt = widenIO(at);
            uint32_t loc;
            if (kind == "air.vertex_input") {
                loc = uint32_t(mdAfter(pn, "air.location_index"));
                info.bindings.push_back({Iridium::BindingType::VertexInput, loc, 0, Iridium::TextureAccessType::Read, 0});
            } else {
                int u = userLocation(mdStr(pn->getOperand(2)));
                loc = u >= 0 ? uint32_t(u) : fragLoc;
                fragLoc = loc + 1;
            }
            uint32_t comp = kind == "air.fragment_input" ? userComponent(mdStr(pn->getOperand(2))) : 0;
            Id v = inputVar(ty(wt), [&](Id var) {
                m.deco(var, spv::Decoration::Location, {loc});
                if (comp) m.deco(var, spv::Decoration::Component, {comp});
                if (kind == "air.fragment_input") {
                    if (mdHas(pn, "air.flat") || !wt->getScalarType()->isFloatingPointTy()) m.deco(var, spv::Decoration::Flat);
                    if (mdHas(pn, "air.no_perspective")) m.deco(var, spv::Decoration::NoPerspective);
                    if (mdHas(pn, "air.centroid")) m.deco(var, spv::Decoration::Centroid);
                    if (mdHas(pn, "air.sample")) { m.deco(var, spv::Decoration::Sample); m.cap(spv::Capability::SampleRateShading); }
                }
            });
            if (wt != at) v = op(at->getScalarType()->isFloatingPointTy() ? SO::OpFConvert : SO::OpUConvert, ty(at), {v});
            vals[A] = v;
        } else if (kind == "air.texture") {
            textures.push_back({A, pn});
        } else if (kind == "air.sampler") {
            samplers.push_back({A, pn});
        } else {
            /* builtins: Vulkan gives uint3 / uint / float4; Metal lets the argument be uint, uint2, ushort... */
            const BuiltinDef *bd = nullptr;
            for (auto &bdef : kBuiltins)
                if (kind == bdef.air) bd = &bdef;
            Id v;
            unsigned have;
            bool isF = false;
            if (kind == "air.threads_per_threadgroup") { v = wgSize; have = 3; }
            else if (kind == "air.simdgroups_per_threadgroup" || kind == "air.dispatch_simdgroups_per_threadgroup") { v = builtin(spv::BuiltIn::NumSubgroups, u32()); have = 1; }
            else if (kind == "air.quadgroup_index_in_threadgroup") { v = op(SO::OpShiftRightLogical, u32(), {builtin(spv::BuiltIn::LocalInvocationIndex, u32()), m.cU32(2)}); have = 1; }
            else if (kind == "air.thread_index_in_quadgroup") { v = op(SO::OpBitwiseAnd, u32(), {builtin(spv::BuiltIn::LocalInvocationIndex, u32()), m.cU32(3)}); have = 1; }
            else if (kind == "air.quadgroups_per_threadgroup" || kind == "air.dispatch_quadgroups_per_threadgroup") {
                Id x = op(SO::OpCompositeExtract, u32(), {wgSize, 0}), y = op(SO::OpCompositeExtract, u32(), {wgSize, 1}), z = op(SO::OpCompositeExtract, u32(), {wgSize, 2});
                Id n = op(SO::OpIMul, u32(), {op(SO::OpIMul, u32(), {x, y}), z});
                v = op(SO::OpShiftRightLogical, u32(), {op(SO::OpIAdd, u32(), {n, m.cU32(3)}), m.cU32(2)});
                have = 1;
            }
            else if (kind == "air.grid_origin") { v = m.cNull(m.tVec(u32(), 3)); have = 3; }
            else if (kind == "air.threads_per_grid" || kind == "air.grid_size") { v = gridSize; have = 3; }
            else {
                if (!bd) fail("argument " + kind);
                if (bd->b == spv::BuiltIn::BaseVertex || bd->b == spv::BuiltIn::BaseInstance) m.cap(spv::Capability::DrawParameters);
                if (bd->b == spv::BuiltIn::SampleId) m.cap(spv::Capability::SampleRateShading);
                if (bd->b == spv::BuiltIn::PrimitiveId || bd->b == spv::BuiltIn::Layer || bd->b == spv::BuiltIn::ViewportIndex) m.cap(spv::Capability::Geometry);
                if (bd->b == spv::BuiltIn::SubgroupLocalInvocationId || bd->b == spv::BuiltIn::SubgroupId || bd->b == spv::BuiltIn::SubgroupSize) m.cap(spv::Capability::GroupNonUniform);
                have = bd->comps;
                isF = bd->isFloat;
                v = builtin(bd->b, have == 0 ? m.tBool() : m.tVec(isF ? m.tFloat(32) : u32(), have));
            }
            if (have > 1) {
                Id et = isF ? m.tFloat(32) : u32();
                unsigned want = at->isVectorTy() ? cast<FixedVectorType>(at)->getNumElements() : 1;
                if (want == 1) v = op(SO::OpCompositeExtract, et, {v, 0});
                else if (want < have) {
                    Words w{v, v};
                    for (unsigned i = 0; i < want; i++) w.push_back(i);
                    v = op(SO::OpVectorShuffle, m.tVec(et, want), w);
                }
                Id base = m.tVec(et, std::min(want, have));
                if (ty(at) != base) v = op(isF ? SO::OpFConvert : SO::OpUConvert, ty(at), {v});
            } else if (have == 1 && ty(at) != u32()) v = op(SO::OpUConvert, ty(at), {v});
            vals[A] = v;
        }
    }
    /* textures, then samplers (Indium binds them in this order after the buffer UBO) */
    for (auto &[A, pn] : textures) {
        int64_t loc = mdAfter(pn, "air.location_index");
        std::string tn = mdAfterStr(pn, "air.arg_type_name"); /* e.g. "texture2d<float, sample>" */
        Iridium::TextureAccessType acc = Iridium::TextureAccessType::Sample;
        if (mdHas(pn, "air.write")) acc = Iridium::TextureAccessType::Write;
        else if (mdHas(pn, "air.read_write")) acc = Iridium::TextureAccessType::ReadWrite;
        bool storage = acc != Iridium::TextureAccessType::Sample;
        std::string cls = tn.substr(0, tn.find('<'));
        std::string sty = tn.find('<') != std::string::npos ? tn.substr(tn.find('<') + 1) : "float";
        sty = sty.substr(0, sty.find_first_of(",>"));
        bool isDepth = cls.rfind("depth", 0) == 0;
        Id sampled = (sty == "float" || sty == "half" || isDepth) ? m.tFloat(32) : (sty == "int" || sty == "short" || sty == "char") ? m.type(SO::OpTypeInt, {32, 1}) : u32();
        spv::Dim dim = spv::Dim::Dim2D;
        bool arrayed = cls.find("_array") != std::string::npos, ms = cls.find("_ms") != std::string::npos;
        unsigned dims = 2;
        if (cls.find("1d") != std::string::npos) { dim = spv::Dim::Dim1D; dims = 1; m.cap(storage ? spv::Capability::Image1D : spv::Capability::Sampled1D); }
        else if (cls.find("3d") != std::string::npos) { dim = spv::Dim::Dim3D; dims = 3; }
        else if (cls.find("cube") != std::string::npos) { dim = spv::Dim::Cube; dims = 2; if (arrayed) m.cap(storage ? spv::Capability::ImageCubeArray : spv::Capability::SampledCubeArray); }
        if (arrayed) dims++;
        if (ms && storage) m.cap(spv::Capability::StorageImageMultisample);
        if (storage) { m.cap(spv::Capability::StorageImageReadWithoutFormat); m.cap(spv::Capability::StorageImageWriteWithoutFormat); }
        Id imgTy = m.type(SO::OpTypeImage, {sampled, uint32_t(dim), isDepth ? 1u : 0u, arrayed ? 1u : 0u, ms ? 1u : 0u, storage ? 2u : 1u, uint32_t(spv::ImageFormat::Unknown)});
        Id var = m.var(m.tPtr(SC::UniformConstant, imgTy), SC::UniformConstant);
        m.deco(var, spv::Decoration::DescriptorSet, {descSet});
        m.deco(var, spv::Decoration::Binding, {uint32_t(internal)});
        iface.push_back(var);
        info.bindings.push_back({Iridium::BindingType::Texture, size_t(loc), internal, acc, 0});
        internal++;
        handles[A] = var;
        kinds[A] = PK::Image;
        texAccess[A] = acc;
        texLoc[var] = uint32_t(loc);
        texType[var] = imgTy;
        texDims[var] = dims;
        texSampled[var] = sampled;
    }
    for (auto &[A, pn] : samplers) {
        int64_t loc = mdAfter(pn, "air.location_index");
        Id var = m.var(m.tPtr(SC::UniformConstant, m.type(SO::OpTypeSampler, {})), SC::UniformConstant);
        m.deco(var, spv::Decoration::DescriptorSet, {descSet});
        m.deco(var, spv::Decoration::Binding, {uint32_t(internal)});
        iface.push_back(var);
        info.bindings.push_back({Iridium::BindingType::Sampler, size_t(loc), internal, Iridium::TextureAccessType::Read, SIZE_MAX});
        internal++;
        handles[A] = var;
        kinds[A] = PK::Sampler;
    }
    /* constexpr samplers declared in the shader */
    if (auto *ss = F.getParent()->getNamedMetadata("air.sampler_states")) {
        for (auto *n : ss->operands()) {
            auto *g = dyn_cast<GlobalVariable>(cast<ValueAsMetadata>(n->getOperand(1))->getValue());
            if (!g || !g->hasInitializer()) continue;
            bool used = false;
            for (const User *u : g->users())
                if (auto *ui = dyn_cast<Instruction>(u); ui && ui->getFunction() == &F) used = true;
            if (!used) continue;
            /* AIR <= 2.6: i64; AIR 2.7 (Metal 3.2): [2 x i64] {state, 0} */
            const Constant *init = g->getInitializer();
            if (init->getType()->isArrayTy()) init = init->getAggregateElement(0u);
            auto *ci = dyn_cast_or_null<ConstantInt>(init);
            if (!ci) continue;
            uint64_t v = ci->getZExtValue();
            Iridium::EmbeddedSampler es{};
            es.widthAddressMode = Iridium::EmbeddedSampler::AddressMode(v & 7);
            es.heightAddressMode = Iridium::EmbeddedSampler::AddressMode((v >> 3) & 7);
            es.depthAddressMode = Iridium::EmbeddedSampler::AddressMode((v >> 6) & 7);
            es.magnificationFilter = Iridium::EmbeddedSampler::Filter((v >> 9) & 3);
            es.minificationFilter = Iridium::EmbeddedSampler::Filter((v >> 11) & 3);
            es.mipmapFilter = Iridium::EmbeddedSampler::MipFilter((v >> 13) & 3);
            es.usesNormalizedCoordinates = !(v & (1ull << 15));
            es.compareFunction = Iridium::EmbeddedSampler::CompareFunction((v >> 16) & 15);
            es.anisotropyLevel = uint8_t(((v >> 20) & 15) + 1);
            es.borderColor = Iridium::EmbeddedSampler::BorderColor((v >> 56) & 3);
            uint16_t lmin = (v >> 24) & 0xFFFF, lmax = (v >> 40) & 0xFFFF;
            auto h2f = [](uint16_t h) { /* IEEE half -> float */
                uint32_t s = (h >> 15) & 1, e = (h >> 10) & 31, f = h & 1023, r;
                if (e == 0) { float x = std::ldexp(float(f), -24); return s ? -x : x; }
                if (e == 31) r = (s << 31) | 0x7F800000 | (f << 13);
                else r = (s << 31) | ((e + 112) << 23) | (f << 13);
                float x; memcpy(&x, &r, 4); return x;
            };
            es.lodMin = h2f(lmin);
            es.lodMax = h2f(lmax);
            size_t esi = info.embeddedSamplers.size();
            info.embeddedSamplers.push_back(es);
            Id var = m.var(m.tPtr(SC::UniformConstant, m.type(SO::OpTypeSampler, {})), SC::UniformConstant);
            m.deco(var, spv::Decoration::DescriptorSet, {descSet});
            m.deco(var, spv::Decoration::Binding, {uint32_t(internal)});
            iface.push_back(var);
            info.bindings.push_back({Iridium::BindingType::Sampler, SIZE_MAX, internal, Iridium::TextureAccessType::Read, esi});
            internal++;
            handles[g] = var;
            kinds[g] = PK::Sampler;
        }
    }

    /* outputs */
    Type *rt = F.getReturnType();
    if (rt->isVoidTy()) return;
    auto *retMD = cast<MDNode>(root->getOperand(1));
    unsigned n = rt->isStructTy() ? rt->getStructNumElements() : 1;
    uint32_t outLoc = 0;
    for (unsigned i = 0; i < n; i++) {
        Type *mt = rt->isStructTy() ? rt->getStructElementType(i) : rt;
        auto *on = i < retMD->getNumOperands() ? dyn_cast<MDNode>(retMD->getOperand(i)) : nullptr;
        std::string kind = on ? mdStr(on->getOperand(0)) : "";
        Out o;
        o.llty = mt;
        Type *wt = widenIO(mt);
        o.widen = wt != mt;
        o.type = ty(wt);
        auto outVar = [&](std::function<void(Id)> deco) {
            Id v = m.var(m.tPtr(SC::Output, o.type), SC::Output);
            deco(v);
            iface.push_back(v);
            return v;
        };
        if (kind == "air.position") o.var = outVar([&](Id v) { m.deco(v, spv::Decoration::BuiltIn, {uint32_t(spv::BuiltIn::Position)}); });
        else if (kind == "air.point_size") o.var = outVar([&](Id v) { m.deco(v, spv::Decoration::BuiltIn, {uint32_t(spv::BuiltIn::PointSize)}); });
        else if (kind == "air.render_target_array_index" || kind == "air.viewport_array_index") { /* layered rendering from the vertex stage (Vulkan 1.2 shaderOutputLayer) */
            bool layer = kind == "air.render_target_array_index";
            m.cap(layer ? spv::Capability::ShaderLayer : spv::Capability::ShaderViewportIndex);
            o.var = outVar([&](Id v) { m.deco(v, spv::Decoration::BuiltIn, {uint32_t(layer ? spv::BuiltIn::Layer : spv::BuiltIn::ViewportIndex)}); });
        }
        else if (kind == "air.clip_distance") {
            m.cap(spv::Capability::ClipDistance);
            if (!mt->isArrayTy()) { o.type = ty(ArrayType::get(mt, 1)); o.wrap = true; }
            o.var = outVar([&](Id v) { m.deco(v, spv::Decoration::BuiltIn, {uint32_t(spv::BuiltIn::ClipDistance)}); });
        }
        else if (kind == "air.vertex_output") {
            int u = userLocation(on->getNumOperands() > 1 ? mdStr(on->getOperand(1)) : "");
            uint32_t loc = u >= 0 ? uint32_t(u) : outLoc;
            outLoc = loc + 1;
            uint32_t comp = userComponent(on->getNumOperands() > 1 ? mdStr(on->getOperand(1)) : "");
            o.var = outVar([&](Id v) { m.deco(v, spv::Decoration::Location, {loc}); if (comp) m.deco(v, spv::Decoration::Component, {comp}); });
        } else if (kind == "air.render_target") {
            uint32_t loc = uint32_t(mdInt(on->getOperand(1))), index = on->getNumOperands() > 2 ? uint32_t(std::max<int64_t>(0, mdInt(on->getOperand(2)))) : 0;
            o.var = outVar([&](Id v) {
                m.deco(v, spv::Decoration::Location, {loc});
                if (index) m.deco(v, spv::Decoration::Index, {index});
            });
        } else if (kind == "air.depth") {
            o.var = outVar([&](Id v) { m.deco(v, spv::Decoration::BuiltIn, {uint32_t(spv::BuiltIn::FragDepth)}); });
            info.writesDepth = true;
            a2s::emit(m.modes, SO::OpExecutionMode, {fnId, uint32_t(spv::ExecutionMode::DepthReplacing)});
        } else
            fail("output " + kind);
        outs.push_back(o);
    }
}

void Fn::writeOutputs(Instruction *ret) {
    if (outs.empty() || ret->getNumOperands() == 0) return;
    Value *rv = ret->getOperand(0);
    Id v = get(rv);
    for (unsigned i = 0; i < outs.size(); i++) {
        Out &o = outs[i];
        if (!o.var) continue;
        Id e = rv->getType()->isStructTy() ? op(SO::OpCompositeExtract, ty(o.llty), {v, i}) : v;
        if (o.widen) e = op(o.llty->getScalarType()->isFloatingPointTy() ? SO::OpFConvert : SO::OpUConvert, o.type, {e});
        if (o.wrap) e = op(SO::OpCompositeConstruct, o.type, {e});
        opv(SO::OpStore, {o.var, e});
    }
}

void Fn::run() {
    /* which stage and its metadata */
    const MDNode *root = nullptr;
    for (auto [mdName, st] : {std::pair{"air.vertex", Iridium::FunctionType::Vertex}, {"air.fragment", Iridium::FunctionType::Fragment}, {"air.kernel", Iridium::FunctionType::Kernel}}) {
        if (auto *nm = F.getParent()->getNamedMetadata(mdName))
            for (auto *n : nm->operands())
                if (auto *vm = dyn_cast_or_null<ValueAsMetadata>(n->getOperand(0)); vm && vm->getValue() == &F) { root = n; stage = st; }
    }
    if (!root) fail("function without air.vertex/air.fragment/air.kernel metadata");
    info.type = stage;

    /* function constants: {value global, type, name, index, required} */
    if (auto *fcs = F.getParent()->getNamedMetadata("air.function_constants"))
        for (auto *n : fcs->operands()) {
            auto *vm = dyn_cast_or_null<ValueAsMetadata>(n->getOperand(0));
            auto *g = vm ? dyn_cast<GlobalVariable>(vm->getValue()->stripPointerCasts()) : nullptr;
            if (!g || n->getNumOperands() < 4) continue;
            unsigned index = unsigned(mdInt(n->getOperand(3)));
            fcIndex[g] = index;
            info.functionConstants.push_back({mdStr(n->getOperand(2)), index});
        }
    /* program-scope static initializers (they copy function constants into the variables the code reads):
     * run them at the start of the function; normalize() inlines them */
    if (auto *ctors = F.getParent()->getNamedGlobal("llvm.global_ctors"); ctors && ctors->hasInitializer())
        if (auto *arr = dyn_cast<ConstantArray>(ctors->getInitializer())) {
            IRBuilder<> B(&*F.getEntryBlock().getFirstInsertionPt());
            for (auto &o : arr->operands())
                if (auto *cs = dyn_cast<ConstantStruct>(o))
                    if (auto *fn = dyn_cast<Function>(cs->getOperand(1)->stripPointerCasts()); fn && !fn->isDeclaration()) B.CreateCall(fn);
        }

    normalize(F);
    separateMerges(F);
    if (getenv("AIR2SPV_DUMP")) F.print(errs());

    /* memory layout: allocas (private), threadgroup globals, program-scope constants */
    SmallPtrSet<const GlobalVariable *, 8> globals;
    for (auto &BB : F)
        for (auto &I : BB) {
            if (auto *a = dyn_cast<AllocaInst>(&I)) {
                auto sz = a->getAllocationSize(DL);
                if (!sz) fail("alloca of variable size");
                uint32_t al = std::max<uint32_t>(4, a->getAlign().value());
                priv.size = (priv.size + al - 1) & ~(al - 1);
                priv.at[a] = priv.size;
                priv.size += uint32_t((sz->getFixedValue() + 3) & ~3ull);
            }
            for (auto &o : I.operands()) collectGlobals(o, globals);
        }
    std::vector<uint8_t> cdata;
    for (auto *g : globals) {
        if (handles.count(g) || fcIndex.count(g)) continue;
        Mem &mm = g->getAddressSpace() == 3 ? group : cbank;
        uint64_t sz = DL.getTypeAllocSize(g->getValueType());
        uint32_t al = std::max<uint32_t>(4, g->getAlign().valueOrOne().value());
        mm.size = (mm.size + al - 1) & ~(al - 1);
        mm.at[g] = mm.size;
        mm.size += uint32_t((sz + 3) & ~3ull);
        if (&mm == &cbank) {
            cdata.resize(cbank.size, 0);
            if (!g->hasInitializer()) fail("global constant without a value: " + g->getName().str());
            serialize(g->getInitializer(), DL, cdata.data() + cbank.at[g]);
        }
    }

    fnId = m.id();
    m.name(fnId, F.getName().str());
    cur = &prologue;
    setupInterface(root);

    if (priv.size) {
        Id at = m.tArray(u32(), priv.size / 4);
        priv.var = m.id();
        a2s::emit(fvars, SO::OpVariable, {m.tPtr(SC::Function, at), priv.var, uint32_t(SC::Function)});
    }
    if (group.size) group.var = m.var(m.tPtr(SC::Workgroup, m.tArray(u32(), group.size / 4)), SC::Workgroup), iface.push_back(group.var);
    if (cbank.size) {
        cdata.resize(cbank.size, 0);
        Words parts;
        for (size_t i = 0; i < cdata.size(); i += 4) { uint32_t w; memcpy(&w, &cdata[i], 4); parts.push_back(m.cU32(w)); }
        Id at = m.tArray(u32(), cbank.size / 4);
        cbank.var = m.var(m.tPtr(SC::Private, at), SC::Private, m.cComposite(at, parts));
        iface.push_back(cbank.var);
    }

    {
        unsigned n = 0;
        for (auto &BB : F) {
            labels[&BB] = m.id();
            if (getenv("AIR2SPV_DUMP")) m.name(labels[&BB], BB.hasName() ? BB.getName().str() : "b" + std::to_string(n));
            n++;
        }
    }

    DominatorTree DT(F);
    PostDominatorTree PDT(F);
    LoopInfo LI(DT);
    cur = &body;
    ReversePostOrderTraversal<Function *> rpo(&F);
    for (BasicBlock *BB : rpo) {
        opv(SO::OpLabel, {labels[BB]});
        for (Instruction &I : *BB) {
            if (I.isTerminator()) break;
            Id r = translate(&I);
            if (r && !I.getType()->isVoidTy()) set(&I, r);
        }
        Instruction *term = BB->getTerminator();
        Loop *L = LI.getLoopFor(BB);
        if (L && L->getHeader() == BB) {
            SmallVector<BasicBlock *, 2> exits;
            L->getUniqueExitBlocks(exits);
            BasicBlock *latch = L->getLoopLatch();
            if (exits.size() != 1 || !latch) fail("unstructured loop");
            opv(SO::OpLoopMerge, {labels[exits[0]], labels[latch], 0});
        } else if (auto *br = dyn_cast<BranchInst>(term); br && br->isConditional() && !(L && L->getLoopLatch() == BB)) {
            auto *node = PDT.getNode(BB);
            BasicBlock *M = node && node->getIDom() ? node->getIDom()->getBlock() : nullptr;
            if (L && M && !L->contains(M)) { /* break: merge where the non-exiting side continues */
                SmallVector<BasicBlock *, 2> exits;
                L->getUniqueExitBlocks(exits);
                BasicBlock *s0 = br->getSuccessor(0), *s1 = br->getSuccessor(1);
                M = (exits.size() == 1 && s0 == exits[0]) ? s1 : s0;
            }
            if (!M) fail("branch without a merge point");
            opv(SO::OpSelectionMerge, {labels[M], 0});
        }
        if (auto *br = dyn_cast<BranchInst>(term)) {
            if (br->isConditional()) opv(SO::OpBranchConditional, {get(br->getCondition()), labels[br->getSuccessor(0)], labels[br->getSuccessor(1)]});
            else opv(SO::OpBranch, {labels[br->getSuccessor(0)]});
        } else if (isa<ReturnInst>(term)) {
            writeOutputs(term);
            opv(SO::OpReturn, {});
        } else if (isa<UnreachableInst>(term)) {
            opv(SO::OpUnreachable, {});
        } else
            fail(std::string("terminator ") + term->getOpcodeName());
    }
    for (auto &[v, id] : fwd)
        if (!vals.count(v)) fail("value used in a phi and never defined");

    /* function = prologue block (variables, interface loads) + body */
    Words &out = m.funcs;
    a2s::emit(out, SO::OpFunction, {m.tVoid(), fnId, 0, m.tFunc(m.tVoid())});
    a2s::emit(out, SO::OpLabel, {m.id()});
    out.insert(out.end(), fvars.begin(), fvars.end());
    out.insert(out.end(), prologue.begin(), prologue.end());
    Id outside = inGrid ? m.id() : 0;
    if (inGrid) {
        a2s::emit(out, SO::OpSelectionMerge, {outside, 0});
        a2s::emit(out, SO::OpBranchConditional, {inGrid, labels[&F.getEntryBlock()], outside});
    } else a2s::emit(out, SO::OpBranch, {labels[&F.getEntryBlock()]});
    out.insert(out.end(), body.begin(), body.end());
    if (inGrid) { a2s::emit(out, SO::OpLabel, {outside}); a2s::emit(out, SO::OpReturn, {}); }
    a2s::emit(out, SO::OpFunctionEnd, {});

    spv::ExecutionModel em = stage == Iridium::FunctionType::Vertex ? spv::ExecutionModel::Vertex
                           : stage == Iridium::FunctionType::Fragment ? spv::ExecutionModel::Fragment : spv::ExecutionModel::GLCompute;
    Words ep{uint32_t(em), fnId};
    a2s::addString(ep, F.getName().str());
    ep.insert(ep.end(), iface.begin(), iface.end());
    a2s::emit(m.entries, SO::OpEntryPoint, ep);
    if (stage == Iridium::FunctionType::Fragment) a2s::emit(m.modes, SO::OpExecutionMode, {fnId, uint32_t(spv::ExecutionMode::OriginUpperLeft)});
}
} // namespace

/* ====================================================================== metallib container + public API */
namespace {
struct MtlFunc { std::string name; const char *bc; size_t size; };
std::vector<MtlFunc> readMetallib(const uint8_t *d, size_t n) {
    auto rd = [&](size_t off, size_t len) -> uint64_t {
        if (off + len > n) fail("truncated metallib");
        uint64_t v = 0;
        memcpy(&v, d + off, len);
        return v;
    };
    if (n < 88 || memcmp(d, "MTLB", 4)) fail("not a metallib");
    uint64_t flOff = rd(24, 8), bcOff = rd(72, 8);
    uint32_t count = uint32_t(rd(flOff, 4));
    std::vector<MtlFunc> out;
    size_t p = flOff + 4;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t gsz = uint32_t(rd(p, 4));
        size_t q = p + 4, end = p + gsz;
        MtlFunc f{};
        while (q + 4 <= end) {
            std::string tag((const char *)d + q, 4);
            q += 4;
            if (tag == "ENDT") break;
            uint16_t sz = uint16_t(rd(q, 2));
            q += 2;
            if (tag == "NAME") f.name = std::string((const char *)d + q, strnlen((const char *)d + q, sz));
            else if (tag == "MDSZ") f.size = rd(q, 8);
            else if (tag == "OFFT") f.bc = (const char *)d + bcOff + rd(q + 16, 8);
            q += sz;
        }
        if (f.bc && f.bc + f.size <= (const char *)d + n) out.push_back(f);
        p = end;
    }
    return out;
}
} // namespace

bool Iridium::init() { return true; }
void Iridium::finit() {}

void *Iridium::translate(const void *inputData, size_t inputSize, size_t &outputSize, OutputInfo &outputInfo) {
    try {
        a2s::Module m;
        m.cap(spv::Capability::Shader);
        m.cap(spv::Capability::PhysicalStorageBufferAddresses);
        m.cap(spv::Capability::Int64); /* buffer addresses */
        for (auto &f : readMetallib((const uint8_t *)inputData, inputSize)) {
            LLVMContext ctx;
            auto mod = parseBitcodeFile(MemoryBufferRef(StringRef(f.bc, f.size), f.name), ctx);
            if (!mod) { fprintf(stderr, "air2spv: %s: %s\n", f.name.c_str(), toString(mod.takeError()).c_str()); continue; }
            Function *F = (*mod)->getFunction(f.name);
            if (!F || F->isDeclaration()) { fprintf(stderr, "air2spv: %s: function not found\n", f.name.c_str()); continue; }
            /* a failed function must not leave half a body in the shared module: translate into a copy first */
            a2s::Module saved = m;
            Iridium::FunctionInfo fi;
            try {
                Fn fn(m, *F, fi);
                fn.run();
                outputInfo.functionInfos[f.name] = fi;
            } catch (const std::exception &e) {
                fprintf(stderr, "air2spv: %s: %s\n", f.name.c_str(), e.what());
                m = std::move(saved);
            }
        }
        Words w = m.finish();
        if (const char *dir = getenv("AIR2SPV_SPV")) { /* debugging: every module as <dir>/mN.spv (spirv-val, spirv-dis) */
            static std::atomic<int> n{0};
            std::string path = std::string(dir) + "/m" + std::to_string(n++) + ".spv";
            if (FILE *f = fopen(path.c_str(), "wb")) { fwrite(w.data(), 4, w.size(), f); fclose(f); }
        }
        outputSize = w.size() * 4;
        void *out = malloc(outputSize);
        memcpy(out, w.data(), outputSize);
        return out;
    } catch (const std::exception &e) {
        fprintf(stderr, "air2spv: %s\n", e.what());
        return nullptr;
    }
}
