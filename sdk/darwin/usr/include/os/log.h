/* Scion SDK: <os/log.h>, the unified logging API. Scion keeps no log (os_log_type_enabled is always false), so the
 * macros below compile to a check that never formats anything. Declarations follow Apple's public documentation. */
#ifndef _OS_LOG_H_
#define _OS_LOG_H_

#include <stdbool.h>
#include <stdint.h>
#include <os/base.h>
#include <os/object.h>
#include <os/trace_base.h>
#include <os/trace.h>

__BEGIN_DECLS

#if OS_OBJECT_SWIFT3
OS_OBJECT_DECL_SWIFT(os_log);
#elif OS_OBJECT_USE_OBJC
OS_OBJECT_DECL(os_log);
#else
typedef struct os_log_s *os_log_t;
#endif

OS_ENUM(os_log_type, uint8_t,
    OS_LOG_TYPE_DEFAULT = 0x00,
    OS_LOG_TYPE_INFO = 0x01,
    OS_LOG_TYPE_DEBUG = 0x02,
    OS_LOG_TYPE_ERROR = 0x10,
    OS_LOG_TYPE_FAULT = 0x11,
);

OS_EXPORT struct os_log_s _os_log_default;
OS_EXPORT struct os_log_s _os_log_disabled;
#define OS_LOG_DEFAULT OS_OBJECT_GLOBAL_OBJECT(os_log_t, _os_log_default)
#define OS_LOG_DISABLED OS_OBJECT_GLOBAL_OBJECT(os_log_t, _os_log_disabled)

OS_EXPORT os_log_t os_log_create(const char *subsystem, const char *category);
OS_EXPORT bool os_log_type_enabled(os_log_t log, os_log_type_t type);
OS_EXPORT bool os_log_is_debug_enabled(os_log_t log);
OS_EXPORT OS_NOT_TAIL_CALLED void _os_log_impl(void *dso, os_log_t log, os_log_type_t type, const char *format, uint8_t *buf, uint32_t size);

#define os_log_info_enabled(log) os_log_type_enabled(log, OS_LOG_TYPE_INFO)
#define os_log_debug_enabled(log) os_log_type_enabled(log, OS_LOG_TYPE_DEBUG)
#define os_log_with_type(log, type, format, ...) ({ \
    os_log_t _scion_log = (log); os_log_type_t _scion_type = (type); \
    if (os_log_type_enabled(_scion_log, _scion_type)) { \
        OS_LOG_CALL_WITH_FORMAT(_os_log_impl, (&__dso_handle, _scion_log, _scion_type), format, ##__VA_ARGS__); \
    } \
})
#define os_log(log, format, ...) os_log_with_type(log, OS_LOG_TYPE_DEFAULT, format, ##__VA_ARGS__)
#define os_log_info(log, format, ...) os_log_with_type(log, OS_LOG_TYPE_INFO, format, ##__VA_ARGS__)
#define os_log_debug(log, format, ...) os_log_with_type(log, OS_LOG_TYPE_DEBUG, format, ##__VA_ARGS__)
#define os_log_error(log, format, ...) os_log_with_type(log, OS_LOG_TYPE_ERROR, format, ##__VA_ARGS__)
#define os_log_fault(log, format, ...) os_log_with_type(log, OS_LOG_TYPE_FAULT, format, ##__VA_ARGS__)

__END_DECLS

#endif
