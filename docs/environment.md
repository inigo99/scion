# Environment variables

Scion reads these from the environment of `scion.exe`. On Windows: `set SCION_TRACE=1` (cmd) or
`$env:SCION_TRACE = '1'` (PowerShell) before running it. The program being run sees the rest of the environment as its
own (`HOME` points to your user profile).

## Running

| Variable | Effect |
|---|---|
| `SCION_ARCH=arm64` | Run the arm64 (Apple Silicon) slice of a universal binary instead of x86_64. `x86_64` forces the other one. |
| `SCION_AUDIO_NULL=1` | No sound device: audio output goes to a silent sink paced like a real one. |
| `SCION_JIT_MB=<n>` | Size of each arm64 thread's translated-code cache in MB (dynarmic's default is 128; when it fills, code is translated again). |

## Diagnosing apps

| Variable | Effect |
|---|---|
| `SCION_TRACE=1` | Log image loading, binding and every host call to stderr. Verbose. |
| `SCION_TRACE_MSG=1` | Log the first time each Objective-C selector is sent to each class, and whether it was found. |
| `SCION_TOLERANT=1` | An unrecognized Objective-C message logs `[tolerant]` and returns 0 instead of raising, to see how far an app gets without the missing methods. |
| `SCION_SWIFTUI_TRACE=1` | Log every SwiftUI view the engine resolves (path and type). |
| `SCION_SWIFTUI_DUMP=1` | Print each SwiftUI host's node tree after its first layout; `=2` after every update. |

## Metal

| Variable | Effect |
|---|---|
| `SCION_METAL_INFO=1` | Show the Vulkan device, its memory types, presentation details and MSL compiler errors. |
| `SCION_METAL_VALIDATION=1` | Enable the Vulkan validation layer (it must be installed, e.g. with the Vulkan SDK). |
| `SCION_METAL_TRACE=1` | Log every Metal call that crosses into the host. |
| `SCION_METAL_NOCOPY=0` | Always copy `newBufferWithBytesNoCopy` buffers instead of importing the app's memory (for comparisons). |
| `SCION_MSL_NOCACHE=1` | Do not use the on-disk cache of compiled MSL. |
| `SCION_MSL_DUMP=1` | Print the MSL source and the LLVM IR it compiles to. |
| `AIR2SPV_DUMP=1` | Print each shader function's LLVM IR as the AIR → SPIR-V translator sees it. |
| `AIR2SPV_SPV=<dir>` | Write every translated SPIR-V module to `<dir>` (for `spirv-val` and `spirv-dis`). |

## Performance

| Variable | Effect |
|---|---|
| `SCION_PROF=1` | Host profiler: every millisecond, samples where busy guest threads are (translated code, Scion's libraries, the host, Windows DLLs) and prints a breakdown every 60 s and at exit. |
| `SCION_SAMPLE=<ms>[,<s>]` | arm64 guests: a histogram of guest program counters, sampled every `<ms>` ms (and printed every `<s>` s). |
| `SCION_THREAD_DUMP=<s>` | Every `<s>` seconds, where each guest thread is (pc, return address, frame chain by image and offset), with slow memory accesses and newly translated instructions per second. |
| `SCION_NOFASTMEM=1` | arm64: route every memory access through callbacks instead of direct access (slow; for debugging the JIT). |
| `SCION_OPT=<hex>` | arm64: dynarmic's optimization flags, as a hexadecimal mask (for debugging the JIT). |

## Tests

These are used by the test suite and by anyone checking a GUI app without clicking it.

| Variable | Effect |
|---|---|
| `SCION_TEST_GUI=<s>` | After `<s>` seconds, print `APP OK:` with the visible windows (titles), open documents and status icons, and quit. |
| `SCION_TEST_CLICK=<s>` | After `<s>` seconds, left-click the app's first status item (its popover then counts as a window). |
| `SCION_TEST_FRAMES=1` | With `SCION_TEST_GUI`, also print each window's frame and content frame. |
