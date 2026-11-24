/* Scion SDK: <os/signpost.h>. Signposts are accepted and dropped (Scion keeps no log). */
#ifndef _OS_SIGNPOST_H_
#define _OS_SIGNPOST_H_

#include <stdint.h>
#include <os/log.h>

__BEGIN_DECLS

typedef uint64_t os_signpost_id_t;
#define OS_SIGNPOST_ID_NULL ((os_signpost_id_t)0)
#define OS_SIGNPOST_ID_INVALID ((os_signpost_id_t)~0ULL)
#define OS_SIGNPOST_ID_EXCLUSIVE ((os_signpost_id_t)0xEEEEB0B5B2B2EEEEULL)

OS_ENUM(os_signpost_type, uint8_t,
    OS_SIGNPOST_EVENT = 0x00,
    OS_SIGNPOST_INTERVAL_BEGIN = 0x01,
    OS_SIGNPOST_INTERVAL_END = 0x02,
);

OS_EXPORT os_signpost_id_t os_signpost_id_generate(os_log_t log);
OS_EXPORT os_signpost_id_t os_signpost_id_make_with_pointer(os_log_t log, const void *ptr);

#define os_signpost_emit_with_type(log, type, spid, name, ...) ((void)(log), (void)(spid))
#define os_signpost_event_emit(log, spid, name, ...) ((void)(log), (void)(spid))
#define os_signpost_interval_begin(log, spid, name, ...) ((void)(log), (void)(spid))
#define os_signpost_interval_end(log, spid, name, ...) ((void)(log), (void)(spid))

__END_DECLS

#endif
