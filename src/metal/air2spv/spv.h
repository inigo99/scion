/* spv.h — minimal SPIR-V module builder for air2spv (Iridium-NG).
 * Words go into the sections a SPIR-V module requires, in order; types and constants are deduplicated by key. */
#pragma once
#include <cstdint>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>
#include "spirv.hpp11"
#include "GLSL.std.450.h"

namespace a2s {
using Id = uint32_t;
using Words = std::vector<uint32_t>;

inline void emit(Words &s, spv::Op op, const Words &operands) {
    s.push_back(uint32_t(operands.size() + 1) << 16 | uint32_t(op));
    s.insert(s.end(), operands.begin(), operands.end());
}
inline void addString(Words &w, const std::string &str) {
    size_t n = str.size() / 4 + 1;
    size_t at = w.size();
    w.resize(at + n, 0);
    memcpy(&w[at], str.data(), str.size());
}

struct Module {
    Id bound = 1;
    std::set<spv::Capability> caps;
    std::set<std::string> exts;
    Words entries, modes, names, decos, globals, funcs;
    std::map<std::string, Id> cache; /* types and constants */
    std::map<std::string, Id> globals_by_name; /* module-wide variables shared by its functions (bindless arrays) */
    Id glsl = 0;

    Id id() { return bound++; }
    void cap(spv::Capability c) { caps.insert(c); }
    void ext(const char *e) { exts.insert(e); }
    Id glslSet() {
        if (!glsl) glsl = id();
        return glsl;
    }
    void name(Id i, const std::string &n) { Words w{i}; addString(w, n); emit(names, spv::Op::OpName, w); }
    void deco(Id i, spv::Decoration d, Words lits = {}) {
        Words w{i, uint32_t(d)};
        w.insert(w.end(), lits.begin(), lits.end());
        emit(decos, spv::Op::OpDecorate, w);
    }
    void memberDeco(Id i, uint32_t m, spv::Decoration d, Words lits = {}) {
        Words w{i, m, uint32_t(d)};
        w.insert(w.end(), lits.begin(), lits.end());
        emit(decos, spv::Op::OpMemberDecorate, w);
    }

    /* types, deduplicated: key = opcode + operands (result id excluded) */
    Id type(spv::Op op, const Words &ops) {
        std::string key = std::to_string(uint32_t(op));
        for (auto w : ops) key += "," + std::to_string(w);
        auto it = cache.find(key);
        if (it != cache.end()) return it->second;
        Id r = id();
        Words w{r};
        w.insert(w.end(), ops.begin(), ops.end());
        emit(globals, op, w);
        cache[key] = r;
        return r;
    }
    Id tVoid() { return type(spv::Op::OpTypeVoid, {}); }
    Id tBool() { return type(spv::Op::OpTypeBool, {}); }
    Id tInt(uint32_t bits) {
        if (bits == 8) cap(spv::Capability::Int8);
        if (bits == 16) cap(spv::Capability::Int16);
        if (bits == 64) cap(spv::Capability::Int64);
        return type(spv::Op::OpTypeInt, {bits, 0});
    }
    Id tFloat(uint32_t bits) {
        if (bits == 16) cap(spv::Capability::Float16);
        if (bits == 64) cap(spv::Capability::Float64);
        return type(spv::Op::OpTypeFloat, {bits});
    }
    Id tVec(Id elem, uint32_t n) { return n == 1 ? elem : type(spv::Op::OpTypeVector, {elem, n}); }
    Id tPtr(spv::StorageClass sc, Id pointee) { return type(spv::Op::OpTypePointer, {uint32_t(sc), pointee}); }
    Id tFunc(Id ret, const Words &params = {}) {
        Words w{ret};
        w.insert(w.end(), params.begin(), params.end());
        return type(spv::Op::OpTypeFunction, w);
    }
    Id tArray(Id elem, uint32_t n) { return type(spv::Op::OpTypeArray, {elem, cU32(n)}); }
    Id tStruct(const Words &members) { return type(spv::Op::OpTypeStruct, members); }
    /* structs that get decorations (Block, offsets) must not be shared with plain structs */
    Id tStructUnique(const Words &members) {
        Id r = id();
        Words w{r};
        w.insert(w.end(), members.begin(), members.end());
        emit(globals, spv::Op::OpTypeStruct, w);
        return r;
    }

    /* constants */
    Id constant(Id ty, const Words &bits) {
        Words w{ty};
        w.insert(w.end(), bits.begin(), bits.end());
        std::string key = "c" + std::to_string(ty);
        for (auto b : bits) key += "," + std::to_string(b);
        auto it = cache.find(key);
        if (it != cache.end()) return it->second;
        Id r = id();
        Words o{ty, r};
        o.insert(o.end(), bits.begin(), bits.end());
        emit(globals, spv::Op::OpConstant, o);
        cache[key] = r;
        return r;
    }
    Id cU32(uint32_t v) { return constant(tInt(32), {v}); }
    Id cU64(uint64_t v) { return constant(tInt(64), {uint32_t(v), uint32_t(v >> 32)}); }
    /* OpConstantTrue/False/Null and OpUndef: result type first, then result id */
    Id typedValue(spv::Op op, Id ty) {
        std::string key = "v" + std::to_string(uint32_t(op)) + "," + std::to_string(ty);
        auto it = cache.find(key);
        if (it != cache.end()) return it->second;
        Id r = id();
        emit(globals, op, {ty, r});
        cache[key] = r;
        return r;
    }
    Id cBool(bool v) { return typedValue(v ? spv::Op::OpConstantTrue : spv::Op::OpConstantFalse, tBool()); }
    Id cComposite(Id ty, const Words &parts) {
        Words w{ty};
        w.insert(w.end(), parts.begin(), parts.end());
        std::string key = "cc";
        for (auto p : w) key += "," + std::to_string(p);
        auto it = cache.find(key);
        if (it != cache.end()) return it->second;
        Id r = id();
        Words o{ty, r};
        o.insert(o.end(), parts.begin(), parts.end());
        emit(globals, spv::Op::OpConstantComposite, o);
        cache[key] = r;
        return r;
    }
    Id cNull(Id ty) { return typedValue(spv::Op::OpConstantNull, ty); }
    Id undef(Id ty) { return typedValue(spv::Op::OpUndef, ty); }
    Id var(Id ptrTy, spv::StorageClass sc, Id init = 0) {
        Id r = id();
        Words w{ptrTy, r, uint32_t(sc)};
        if (init) w.push_back(init);
        emit(globals, spv::Op::OpVariable, w);
        return r;
    }

    Words finish() {
        Words out{0x07230203, 0x00010500, 0x00170000 /* generator */, 0, 0};
        for (auto c : caps) emit(out, spv::Op::OpCapability, {uint32_t(c)});
        for (auto &e : exts) { Words w; addString(w, e); emit(out, spv::Op::OpExtension, w); }
        if (glsl) { Words w{glsl}; addString(w, "GLSL.std.450"); emit(out, spv::Op::OpExtInstImport, w); }
        emit(out, spv::Op::OpMemoryModel, {uint32_t(spv::AddressingModel::PhysicalStorageBuffer64), uint32_t(spv::MemoryModel::GLSL450)});
        for (auto *s : {&entries, &modes, &names, &decos, &globals, &funcs}) out.insert(out.end(), s->begin(), s->end());
        out[3] = bound;
        return out;
    }
};
} // namespace a2s
