/* scion SDK: minimal <mach-o/getsect.h> */
#ifndef _MACH_O_GETSECT_H_
#define _MACH_O_GETSECT_H_
#include <stdint.h>
#include <mach-o/loader.h>
#ifdef __cplusplus
extern "C" {
#endif
extern uint8_t *getsectiondata(const struct mach_header_64 *mhp, const char *segname, const char *sectname, unsigned long *size);
extern uint8_t *getsegmentdata(const struct mach_header_64 *mhp, const char *segname, unsigned long *size);
extern const struct section_64 *getsectbynamefromheader_64(const struct mach_header_64 *mhp, const char *segname, const char *sectname);
extern const struct segment_command_64 *getsegbyname(const char *segname);
extern unsigned long get_end(void), get_etext(void), get_edata(void);
#ifdef __cplusplus
}
#endif
#endif
