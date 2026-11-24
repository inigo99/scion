/* The C part of the Swift Dispatch overlay (Dispatch.mm in Swift's sources): called when dispatch_source_create fails.
 * ponytail: the overlay's constructor that adds the OS_dispatch_source_* protocols to the source class is left out
 * (scion's dispatch objects share one class). */
#include <stdio.h>
#include <stdlib.h>
void _swift_dispatch_source_create_abort(void) {
    fputs("Fatal error: dispatch_source_create returned NULL, invalid parameters passed to dispatch_source_create\n", stderr);
    abort();
}
