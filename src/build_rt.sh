#!/bin/sh
# Builds the LLVM runtimes for the guest (darwin x86_64 + arm64) into ../out/rt/<arch>/:
#   unwind/  -> linked into libSystem.B.dylib (as on macOS, where libunwind lives inside libSystem)
#   cxxabi/ cxx/ -> libc++.1.dylib
# Objects are cached: a source is recompiled only when it is newer than its object.
set -e
cd "$(dirname "$0")"
SDK=$(cd ../sdk/darwin && pwd); CFG=$(cd ../sdk/libcxx-config && pwd); OUT=$(mkdir -p ../out/rt && cd ../out/rt && pwd)
TP=$(cd "${DEPS:-../deps}/llvm-runtimes" && pwd)   # libunwind, libc++abi, libc++ (scripts/fetch-deps.sh)
CXXINC="-nostdinc++ -isystem $CFG -isystem $TP/libcxx/include"
cc1() { # arch src obj flags...
  a=$1; s=$2; o=$3; shift 3
  [ -f "$o" ] && [ "$o" -nt "$s" ] && return 0
  case $s in *.cpp) C=clang++;; *) C=clang;; esac
  $C -target $a-apple-macos11 -isysroot $SDK -O2 -fno-stack-protector -funwind-tables -DNDEBUG "$@" -c $s -o $o
}
for a in x86_64 arm64; do
  mkdir -p $OUT/$a/unwind $OUT/$a/cxxabi $OUT/$a/cxx
  U=$TP/libunwind/src
  for f in libunwind.cpp UnwindLevel1.c UnwindLevel1-gcc-ext.c UnwindRegistersRestore.S UnwindRegistersSave.S; do
    case $f in *.cpp) X="-std=c++17 -fno-exceptions -fno-rtti -nostdinc++";; *.c) X="-std=c11";; *) X="";; esac
    cc1 $a $U/$f $OUT/$a/unwind/${f%.*}.o -I$TP/libunwind/include $X &
  done; wait
  B=$TP/libcxxabi/src
  for f in abort_message cxa_aux_runtime cxa_default_handlers cxa_demangle cxa_exception cxa_exception_storage cxa_guard \
           cxa_handlers cxa_personality cxa_thread_atexit cxa_vector cxa_virtual fallback_malloc private_typeinfo \
           stdlib_exception stdlib_new_delete stdlib_stdexcept stdlib_typeinfo; do
    cc1 $a $B/$f.cpp $OUT/$a/cxxabi/$f.o $CXXINC -I$TP/libcxxabi/include -I$TP/libcxx/src -I$TP/libunwind/include \
      -std=c++20 -D_LIBCXXABI_BUILDING_LIBRARY -D_LIBCPP_BUILDING_LIBRARY -DLIBCXXABI_USE_LLVM_UNWINDER &
  done; wait
  X=$TP/libcxx/src
  for f in algorithm any atomic barrier bind call_once charconv chrono condition_variable condition_variable_destructor \
           error_category exception filesystem/directory_entry filesystem/directory_iterator filesystem/filesystem_clock \
           filesystem/filesystem_error filesystem/operations filesystem/path fstream functional future hash ios \
           ios.instantiations iostream legacy_pointer_safety locale memory memory_resource mutex mutex_destructor \
           new_handler new_helpers optional ostream print random random_shuffle regex ryu/d2fixed ryu/d2s ryu/f2s \
           shared_mutex stdexcept string strstream system_error thread typeinfo valarray variant vector verbose_abort; do
    cc1 $a $X/$f.cpp $OUT/$a/cxx/$(echo $f | tr / _).o $CXXINC -I$X -I$TP/libcxxabi/include -std=c++23 \
      -D_LIBCPP_BUILDING_LIBRARY -DLIBCXX_BUILDING_LIBCXXABI -D_LIBCPP_REMOVE_TRANSITIVE_INCLUDES -fvisibility-inlines-hidden &
  done; wait
done
echo "runtimes OK -> $OUT"
