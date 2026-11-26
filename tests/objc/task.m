/* NSTask (Swift's Process) running this same program: pipes, the termination handler and status, environment,
 * working directory, a readability handler, terminate, launch errors. Prints TASK OK. */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); exit(1); } } while (0)

static int child(int argc, char **argv) {
    const char *what = argv[2];
    if (!strcmp(what, "echo")) { for (int i = 3; i < argc; i++) printf("%s%s", i > 3 ? " " : "", argv[i]); printf("\n"); return 0; }
    if (!strcmp(what, "cat")) { char b[256]; ssize_t n; while ((n = read(0, b, sizeof b)) > 0) write(1, b, n); return 4; }
    if (!strcmp(what, "env")) { printf("%s\n", getenv("TASK_VAR") ?: "(none)"); return 0; }
    if (!strcmp(what, "pwd")) { char b[1024]; printf("%s\n", getcwd(b, sizeof b)); return 0; }
    if (!strcmp(what, "lines")) { for (int i = 0; i < 3; i++) { printf("line %d\n", i); fflush(stdout); usleep(50000); } return 0; }
    if (!strcmp(what, "err")) { fprintf(stderr, "to stderr\n"); return 1; }
    if (!strcmp(what, "sleep")) { sleep(30); return 0; }
    return 98;
}

static NSString *self_path;
static NSTask *task(NSArray *args) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:self_path];
    t.arguments = [@[@"child"] arrayByAddingObjectsFromArray:args];
    return t;
}
static NSString *text(NSData *d) { return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]; }

int main(int argc, char **argv) {
    if (argc > 2 && !strcmp(argv[1], "child")) return child(argc, argv);
    @autoreleasepool {
        char cwd[1024]; getcwd(cwd, sizeof cwd);
        self_path = argv[0][0] == '/' ? @(argv[0]) : [@(cwd) stringByAppendingPathComponent:@(argv[0])];

        /* stdout through a pipe; the status */
        NSTask *t = task(@[@"echo", @"hello", @"two words"]);
        NSPipe *out = [NSPipe pipe];
        t.standardOutput = out;
        NSError *e = nil;
        CHECK([t launchAndReturnError:&e] && t.processIdentifier > 0);
        NSData *d = [out.fileHandleForReading readDataToEndOfFile];
        [t waitUntilExit];
        CHECK(!t.isRunning && t.terminationStatus == 0 && t.terminationReason == NSTaskTerminationReasonExit);
        CHECK([text(d) isEqualToString:@"hello two words\n"]);

        /* stdin and stdout, the termination handler */
        t = task(@[@"cat"]);
        NSPipe *in = [NSPipe pipe]; out = [NSPipe pipe];
        t.standardInput = in; t.standardOutput = out;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block int handled = -1;
        t.terminationHandler = ^(NSTask *x) { handled = x.terminationStatus; dispatch_semaphore_signal(done); };
        [t launch];
        [in.fileHandleForWriting writeData:[@"through cat" dataUsingEncoding:NSUTF8StringEncoding]];
        [in.fileHandleForWriting closeFile];
        CHECK([text([out.fileHandleForReading readDataToEndOfFile]) isEqualToString:@"through cat"]);
        CHECK(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) == 0 && handled == 4);

        /* environment, working directory, stderr */
        t = task(@[@"env"]); out = [NSPipe pipe]; t.standardOutput = out;
        t.environment = @{@"TASK_VAR": @"from NSTask"};
        [t launch];
        CHECK([text([out.fileHandleForReading readDataToEndOfFile]) isEqualToString:@"from NSTask\n"]);
        [t waitUntilExit];
        NSString *tmp = [@"/tmp" stringByResolvingSymlinksInPath];
        t = task(@[@"pwd"]); out = [NSPipe pipe]; t.standardOutput = out;
        t.currentDirectoryURL = [NSURL fileURLWithPath:@"/tmp"];
        [t launch];
        NSString *pwd = [text([out.fileHandleForReading readDataToEndOfFile]) stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        [t waitUntilExit];
        CHECK([pwd isEqualToString:tmp] || [pwd isEqualToString:@"/tmp"] || [[pwd lowercaseString] hasSuffix:@"/temp"]);
        t = task(@[@"err"]); NSPipe *err = [NSPipe pipe]; t.standardError = err;
        [t launch];
        CHECK([text([err.fileHandleForReading readDataToEndOfFile]) isEqualToString:@"to stderr\n"]);
        [t waitUntilExit];
        CHECK(t.terminationStatus == 1);

        /* output as it comes, through a readability handler */
        t = task(@[@"lines"]); out = [NSPipe pipe]; t.standardOutput = out;
        NSMutableString *got = [NSMutableString string];
        dispatch_semaphore_t eof = dispatch_semaphore_create(0);
        out.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
            NSData *chunk = h.availableData;
            if (!chunk.length) { h.readabilityHandler = nil; dispatch_semaphore_signal(eof); return; }
            @synchronized(got) { [got appendString:text(chunk)]; }
        };
        [t launch];
        CHECK(dispatch_semaphore_wait(eof, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) == 0);
        [t waitUntilExit];
        CHECK([got isEqualToString:@"line 0\nline 1\nline 2\n"]);

        /* terminate; a program that is not there */
        t = task(@[@"sleep"]);
        [t launch];
        CHECK(t.isRunning);
        [t terminate];
        [t waitUntilExit];
        CHECK(t.terminationReason == NSTaskTerminationReasonUncaughtSignal && t.terminationStatus == 15);
        t = [NSTask new];
        t.executableURL = [NSURL fileURLWithPath:@"/nonexistent/tool"];
        e = nil;
        CHECK(![t launchAndReturnError:&e] && [e.domain isEqualToString:NSCocoaErrorDomain] && e.code == 4);
        printf("TASK OK\n");
    }
    return 0;
}
