/* scion SDK: minimal <copyfile.h> */
#ifndef _COPYFILE_H_
#define _COPYFILE_H_
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
struct _copyfile_state;
typedef struct _copyfile_state *copyfile_state_t;
typedef uint32_t copyfile_flags_t;
#define COPYFILE_ACL (1 << 0)
#define COPYFILE_STAT (1 << 1)
#define COPYFILE_XATTR (1 << 2)
#define COPYFILE_DATA (1 << 3)
#define COPYFILE_SECURITY (COPYFILE_STAT | COPYFILE_ACL)
#define COPYFILE_METADATA (COPYFILE_SECURITY | COPYFILE_XATTR)
#define COPYFILE_ALL (COPYFILE_METADATA | COPYFILE_DATA)
#define COPYFILE_RECURSIVE (1 << 15)
#define COPYFILE_EXCL (1 << 17)
#define COPYFILE_NOFOLLOW_SRC (1 << 18)
#define COPYFILE_NOFOLLOW_DST (1 << 19)
#define COPYFILE_UNLINK (1 << 21)
#define COPYFILE_CLONE (1 << 24)
int copyfile(const char *from, const char *to, copyfile_state_t state, copyfile_flags_t flags);
int fcopyfile(int from_fd, int to_fd, copyfile_state_t, copyfile_flags_t flags);
copyfile_state_t copyfile_state_alloc(void);
int copyfile_state_free(copyfile_state_t);
int copyfile_state_get(copyfile_state_t s, uint32_t flag, void *dst);
int copyfile_state_set(copyfile_state_t s, uint32_t flag, const void *src);
#ifdef __cplusplus
}
#endif
#endif
