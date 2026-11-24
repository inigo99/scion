/* scion: the static linker's symbols for the image headers (the executable's one: _mh_execute_header) */
#ifndef _MACHO_LDSYMS_H_
#define _MACHO_LDSYMS_H_
#include <mach-o/loader.h>
#define _MH_EXECUTE_SYM "__mh_execute_header"
#define MH_EXECUTE_SYM "_mh_execute_header"
#define _MH_DYLIB_SYM "__mh_dylib_header"
#define MH_DYLIB_SYM "_mh_dylib_header"
#ifdef __cplusplus
extern "C" {
#endif
extern const struct mach_header_64 _mh_execute_header;
extern const struct mach_header_64 _mh_dylib_header;
#ifdef __cplusplus
}
#endif
#endif
