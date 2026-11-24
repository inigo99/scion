/* internal.h — private declarations shared by scion's Foundation sources. */
#define MW_FOUNDATION_INTERNAL 1
#import <Foundation/Foundation.h>
void *malloc(size_t); void *calloc(size_t, size_t); void *realloc(void *, size_t); void free(void *);
void *memcpy(void *, const void *, size_t); void *memmove(void *, const void *, size_t); void *memset(void *, int, size_t);
int memcmp(const void *, const void *, size_t); size_t strlen(const char *); int strcmp(const char *, const char *);
int strncmp(const char *, const char *, size_t); int strcasecmp(const char *, const char *);
char *strdup(const char *); char *strchr(const char *, int); char *strrchr(const char *, int);
long strtol(const char *, char **, int); long long strtoll(const char *, char **, int); double strtod(const char *, char **);
unsigned long long strtoull(const char *, char **, int); size_t strspn(const char *, const char *);
int tolower(int); int toupper(int); int isdigit(int); int isspace(int); int isalpha(int); int isalnum(int); int ispunct(int);
int vasprintf(char **, const char *, va_list); int snprintf(char *, size_t, const char *, ...); int asprintf(char **, const char *, ...);
int *__error(void);
#define errno (*__error())
long write(int, const void *, size_t); long read(int, void *, size_t); int open(const char *, int, ...); int close(int);
void abort(void) __attribute__((noreturn)); char *getenv(const char *); int getpid(void);
typedef uint64_t pthread_mutex_t[8]; typedef uint64_t pthread_cond_t[6];
int pthread_mutex_lock(void *); int pthread_mutex_unlock(void *); int pthread_mutex_trylock(void *);
int pthread_cond_wait(void *, void *); int pthread_cond_signal(void *); int pthread_cond_broadcast(void *);
struct timespec { int64_t tv_sec, tv_nsec; };
int pthread_cond_timedwait_relative_np(void *, void *, const struct timespec *);
void *pthread_self(void); int pthread_create(void **, const void *, void *(*)(void *), void *);
id objc_msgSend(id, SEL, ...); id class_createInstance(Class, size_t); id object_dispose(id); BOOL class_isMetaClass(Class);
void *objc_autoreleasePoolPush(void); void objc_autoreleasePoolPop(void *);

@interface NSString (MWPrivate) - (instancetype)_initTakingUTF16:(unichar *)u length:(NSUInteger)n; @end
@interface __NSStringImpl : NSString { @public unichar *_u; NSUInteger _n; char *_utf8; } @end
@interface __NSCFConstantString : NSString { @public uint32_t _info, _pad; const void *_str; long _len; } @end

unichar *mw_utf8_to_utf16(const char *s, size_t n, NSUInteger *outn);
char *mw_utf16_to_utf8(const unichar *u, NSUInteger n, size_t *outn);
unichar *mw_chars(NSString *s, NSUInteger *n);
NSString *mw_str_take(unichar *u, NSUInteger n);
void mw_raise(const char *name, const char *reason) __attribute__((noreturn));
NSError *mw_posix_error(int code, NSString *path);
BOOL mw_number_is_bool(NSNumber *n); BOOL mw_number_is_real(NSNumber *n);
void mw_foundation_load(void);
NSString *mw_darwin_errstr(int e);

extern void (*mw_defaults_change_hook)(NSString *key, BOOL did);   /* plist.m: NSUserDefaultsController follows the defaults */
