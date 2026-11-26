/* URLSession, NSURLConnection and NSData/NSString URL loading against an HTTP server on the loopback interface (in a
 * thread of this program): completion handlers, redirects, uploads, downloads, a delegate, cancel, timeouts,
 * connection errors, cookies, HTTP authentication and the redirect delegate. Prints URLSESSION OK. */
#import <Foundation/Foundation.h>
#include <arpa/inet.h>
#include <dispatch/dispatch.h>
#include <netinet/in.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define CHECK(c, ...) do { if (!(c)) { printf("FAIL line %d: %s ", __LINE__, #c); printf("" __VA_ARGS__); printf("\n"); exit(1); } } while (0)
enum { BIG = 200000 };

static void reply(int c, const char *status, const char *extra, const void *body, size_t n) {
    char h[512];
    int k = snprintf(h, sizeof h, "HTTP/1.1 %s\r\nContent-Length: %zu\r\nConnection: close\r\n%s\r\n", status, n, extra);
    send(c, h, k, 0);
    for (size_t off = 0; off < n;) { ssize_t w = send(c, (const char *)body + off, n - off, 0); if (w <= 0) break; off += w; }
}

static void *serve(void *arg) {
    int c = (int)(intptr_t)arg;
    char req[8192]; size_t got = 0; char *end = NULL;
    while (!end && got < sizeof req - 1) {
        ssize_t r = recv(c, req + got, sizeof req - 1 - got, 0);
        if (r <= 0) { close(c); return NULL; }
        got += r; req[got] = 0; end = strstr(req, "\r\n\r\n");
    }
    char method[16] = "", path[256] = "";
    sscanf(req, "%15s %255s", method, path);
    const char *cl = strcasestr(req, "\r\nContent-Length:");
    size_t want = cl ? strtoul(cl + 17, NULL, 10) : 0, have = got - (end + 4 - req);
    char *body = malloc(want + 1); memcpy(body, end + 4, have);
    while (have < want) { ssize_t r = recv(c, body + have, want - have, 0); if (r <= 0) break; have += r; }
    if (!strcmp(path, "/hello")) reply(c, "200 OK", "Content-Type: text/plain; charset=utf-8\r\nX-Test: one\r\nX-Test: two\r\n", "hello", 5);
    else if (!strcmp(path, "/redirect")) reply(c, "302 Found", "Location: /hello\r\n", "", 0);
    else if (!strcmp(path, "/missing")) reply(c, "404 Not Found", "Content-Type: text/html\r\n", "<p>no</p>", 9);
    else if (!strcmp(path, "/echo")) {
        /* the body back, with the method and the headers the client sent */
        const char *ua = strcasestr(req, "\r\nUser-Agent:"), *x = strcasestr(req, "\r\nX-Custom:"), *ck = strcasestr(req, "\r\nCookie:");
        char extra[900];
        snprintf(extra, sizeof extra, "X-Method: %s\r\nX-Has-UA: %d\r\nX-Custom-Seen: %.*s\r\nX-Cookie-Seen: %.*s\r\n", method, ua != NULL,
                 x ? (int)strcspn(x + 11, "\r") : 0, x ? x + 11 : "", ck ? (int)strcspn(ck + 9, "\r") : 0, ck ? ck + 9 : "");
        reply(c, "200 OK", extra, body, have);
    } else if (!strcmp(path, "/big")) {
        char *b = malloc(BIG);
        for (int i = 0; i < BIG; i++) b[i] = 'a' + i % 26;
        reply(c, "200 OK", "Content-Type: application/octet-stream\r\n", b, BIG);
        free(b);
    } else if (!strcmp(path, "/slow")) { sleep(4); reply(c, "200 OK", "", "late", 4); }
    else if (!strcmp(path, "/setcookie"))
        reply(c, "200 OK", "Set-Cookie: session=abc123; Path=/\r\nSet-Cookie: theme=dark; Path=/; Expires=Wed, 21 Oct 2099 07:28:00 GMT\r\n", "ok", 2);
    else if (!strcmp(path, "/login")) reply(c, "302 Found", "Set-Cookie: auth=yes; Path=/; HttpOnly\r\nLocation: /echo\r\n", "", 0);
    else if (!strcmp(path, "/auth")) {
        if (strstr(req, "\r\nAuthorization: Basic dXNlcjpzZWNyZXQ=\r\n")) reply(c, "200 OK", "", "welcome", 7);   /* user:secret */
        else reply(c, "401 Unauthorized", "WWW-Authenticate: Basic realm=\"scion\"\r\n", "no", 2);
    }
    else reply(c, "400 Bad Request", "", "", 0);
    free(body);
    close(c);
    return NULL;
}

static void *server(void *arg) {
    int s = (int)(intptr_t)arg;
    for (;;) {
        int c = accept(s, NULL, NULL);
        if (c < 0) continue;
        pthread_t t; pthread_create(&t, NULL, serve, (void *)(intptr_t)c); pthread_detach(t);
    }
    return NULL;
}

static int listener(int *port) {
    int s = socket(AF_INET, SOCK_STREAM, 0), one = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = {0}; a.sin_family = AF_INET; a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t l = sizeof a;
    CHECK(bind(s, (struct sockaddr *)&a, sizeof a) == 0 && getsockname(s, (struct sockaddr *)&a, &l) == 0);
    *port = ntohs(a.sin_port);
    return s;
}

static NSString *text(NSData *d) { return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]; }
/* answers authentication challenges with user:secret (once), and stops redirects when asked */
@interface Gate : NSObject <NSURLSessionTaskDelegate>
@property int challenges; @property BOOL stopRedirects; @property NSString *realm;
@end
@implementation Gate
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didReceiveChallenge:(NSURLAuthenticationChallenge *)c
    completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))h {
    self.challenges++; self.realm = c.protectionSpace.realm;
    if (c.previousFailureCount) { h(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil); return; }
    h(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialWithUser:@"user" password:@"secret" persistence:NSURLCredentialPersistenceNone]);
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t willPerformHTTPRedirection:(NSHTTPURLResponse *)r newRequest:(NSURLRequest *)req
    completionHandler:(void (^)(NSURLRequest *))h { h(self.stopRedirects ? nil : req); }
@end
/* a data task on a session, waited for */
static NSData *fetch_on(NSURLSession *ses, NSURLRequest *r, NSHTTPURLResponse **resp, NSError **err) {
    __block NSData *d; __block NSURLResponse *rs; __block NSError *e;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[ses dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        d = data; rs = response; e = error; dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (resp) *resp = (NSHTTPURLResponse *)rs;
    if (err) *err = e;
    return d;
}

@interface Collector : NSObject <NSURLSessionDataDelegate>
@property NSMutableData *data; @property NSURLResponse *response; @property NSError *error; @property BOOL done;
@property dispatch_semaphore_t sem;
@end
@implementation Collector
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveResponse:(NSURLResponse *)r completionHandler:(void (^)(NSURLSessionResponseDisposition))h {
    self.response = r; self.data = [NSMutableData data]; h(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d { [self.data appendData:d]; }
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)e { self.error = e; self.done = YES; dispatch_semaphore_signal(self.sem); }
@end

static NSString *base;
static NSURL *U(NSString *p) { return [NSURL URLWithString:[base stringByAppendingString:p]]; }

/* runs a data task on the shared session and waits for its completion handler */
static NSData *fetch(NSURLRequest *r, NSHTTPURLResponse **resp, NSError **err) {
    __block NSData *d; __block NSURLResponse *rs; __block NSError *e;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        d = data; rs = response; e = error; dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (resp) *resp = (NSHTTPURLResponse *)rs;
    if (err) *err = e;
    return d;
}

int main(void) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        int port, s = listener(&port);
        CHECK(listen(s, 16) == 0);
        pthread_t t; pthread_create(&t, NULL, server, (void *)(intptr_t)s);
        base = [NSString stringWithFormat:@"http://127.0.0.1:%d", port];

        /* a GET, its response and headers */
        NSHTTPURLResponse *r; NSError *e;
        NSData *d = fetch([NSURLRequest requestWithURL:U(@"/hello")], &r, &e);
        CHECK(!e && [r isKindOfClass:[NSHTTPURLResponse class]] && r.statusCode == 200);
        CHECK([[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] isEqualToString:@"hello"]);
        CHECK([r.MIMEType isEqualToString:@"text/plain"] && [r.textEncodingName isEqualToString:@"utf-8"] && r.expectedContentLength == 5);
        CHECK([[r valueForHTTPHeaderField:@"x-test"] isEqualToString:@"one, two"]);
        CHECK([r.suggestedFilename isEqualToString:@"hello"]);

        /* a redirect is followed; a 404 is a response, not an error */
        fetch([NSURLRequest requestWithURL:U(@"/redirect")], &r, &e);
        CHECK(!e && r.statusCode == 200 && [r.URL.path isEqualToString:@"/hello"]);
        d = fetch([NSURLRequest requestWithURL:U(@"/missing")], &r, &e);
        CHECK(!e && r.statusCode == 404 && d.length == 9);

        /* POST with a body and a header; an upload task */
        NSMutableURLRequest *m = [NSMutableURLRequest requestWithURL:U(@"/echo")];
        m.HTTPMethod = @"POST"; m.HTTPBody = [@"ping" dataUsingEncoding:NSUTF8StringEncoding];
        [m setValue:@"yes" forHTTPHeaderField:@"X-Custom"];
        d = fetch(m, &r, &e);
        CHECK(!e && [d isEqualToData:m.HTTPBody] && [[r valueForHTTPHeaderField:@"X-Method"] isEqualToString:@"POST"]);
        CHECK([[r valueForHTTPHeaderField:@"X-Has-UA"] isEqualToString:@"1"] && [[r valueForHTTPHeaderField:@"X-Custom-Seen"] isEqualToString:@"yes"]);
        __block NSData *up; dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        NSMutableURLRequest *put = [NSMutableURLRequest requestWithURL:U(@"/echo")]; put.HTTPMethod = @"PUT";
        [[[NSURLSession sharedSession] uploadTaskWithRequest:put fromData:[NSData dataWithBytes:"0123456789" length:10] completionHandler:^(NSData *data, NSURLResponse *rs, NSError *er) {
            up = er ? nil : data; dispatch_semaphore_signal(sem);
        }] resume];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        CHECK(up.length == 10 && !memcmp(up.bytes, "0123456789", 10));

        /* a download goes to a file, removed after the handler */
        __block NSString *where; __block unsigned long long size = 0; __block BOOL ok = NO;
        [[[NSURLSession sharedSession] downloadTaskWithURL:U(@"/big") completionHandler:^(NSURL *loc, NSURLResponse *rs, NSError *er) {
            where = loc.path;
            NSData *f = [NSData dataWithContentsOfURL:loc];
            size = f.length;
            ok = f.length == BIG && ((const char *)f.bytes)[BIG - 1] == 'a' + (BIG - 1) % 26;
            dispatch_semaphore_signal(sem);
        }] resume];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        CHECK(ok && size == BIG && where);

        /* a session with a delegate */
        Collector *c = [Collector new]; c.sem = dispatch_semaphore_create(0);
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.HTTPAdditionalHeaders = @{@"X-Custom": @"from-config"};
        NSURLSession *ses = [NSURLSession sessionWithConfiguration:cfg delegate:c delegateQueue:nil];
        NSURLSessionDataTask *task = [ses dataTaskWithURL:U(@"/big")];
        CHECK(task.state == NSURLSessionTaskStateSuspended && task.taskIdentifier > 0);
        [task resume];
        dispatch_semaphore_wait(c.sem, DISPATCH_TIME_FOREVER);
        CHECK(c.done && !c.error && c.data.length == BIG && task.state == NSURLSessionTaskStateCompleted && task.countOfBytesReceived == BIG);
        [[ses dataTaskWithURL:U(@"/echo")] resume];
        dispatch_semaphore_wait(c.sem, DISPATCH_TIME_FOREVER);
        CHECK([[(NSHTTPURLResponse *)c.response valueForHTTPHeaderField:@"X-Custom-Seen"] isEqualToString:@"from-config"]);
        [ses finishTasksAndInvalidate];

        /* cancel, a timeout, a refused connection, a URL scheme it does not handle */
        __block NSError *ce;
        NSURLSessionDataTask *slow = [[NSURLSession sharedSession] dataTaskWithURL:U(@"/slow") completionHandler:^(NSData *data, NSURLResponse *rs, NSError *er) {
            ce = er; dispatch_semaphore_signal(sem);
        }];
        [slow resume];
        usleep(200000);
        [slow cancel];
        CHECK(dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0);
        CHECK([ce.domain isEqualToString:NSURLErrorDomain] && ce.code == NSURLErrorCancelled);
        /* (the shared session's handlers run one at a time: the download's file was removed before this one ran) */
        CHECK(![[NSFileManager defaultManager] fileExistsAtPath:where]);
        NSMutableURLRequest *tr = [NSMutableURLRequest requestWithURL:U(@"/slow")]; tr.timeoutInterval = 0.5;
        fetch(tr, &r, &e);
        CHECK(e.code == NSURLErrorTimedOut && [e.userInfo[NSURLErrorFailingURLErrorKey] isEqual:tr.URL]);
        int dead, ds = listener(&dead); close(ds);
        fetch([NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%d/", dead]]], &r, &e);
        CHECK(e.code == NSURLErrorCannotConnectToHost && !r);
        fetch([NSURLRequest requestWithURL:[NSURL URLWithString:@"gopher://127.0.0.1/"]], &r, &e);
        CHECK(e.code == NSURLErrorUnsupportedURL);

        /* cookies: kept from responses (also from a redirect), sent back, not shared with an ephemeral session */
        NSHTTPCookieStorage *jar = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *k in [jar cookies]) [jar deleteCookie:k];
        fetch([NSURLRequest requestWithURL:U(@"/setcookie")], &r, &e);
        NSArray *kept = [jar cookiesForURL:U(@"/")];
        CHECK(!e && kept.count == 2, "cookies kept: %lu", (unsigned long)kept.count);
        NSHTTPCookie *theme = nil;
        for (NSHTTPCookie *k in kept) if ([k.name isEqualToString:@"theme"]) theme = k;
        CHECK(theme && [theme.value isEqualToString:@"dark"] && !theme.sessionOnly && [theme.expiresDate timeIntervalSince1970] > 4000000000.0, "lasting cookie");
        fetch([NSURLRequest requestWithURL:U(@"/echo")], &r, &e);
        NSString *seen = [r valueForHTTPHeaderField:@"X-Cookie-Seen"];
        CHECK([seen containsString:@"session=abc123"] && [seen containsString:@"theme=dark"], "cookies sent: %s", seen.UTF8String);
        NSMutableURLRequest *login = [NSMutableURLRequest requestWithURL:U(@"/login")];
        login.HTTPMethod = @"POST"; login.HTTPBody = [@"user=x" dataUsingEncoding:NSUTF8StringEncoding];
        fetch(login, &r, &e);
        seen = [r valueForHTTPHeaderField:@"X-Cookie-Seen"];
        CHECK(!e && [r.URL.path isEqualToString:@"/echo"] && [[r valueForHTTPHeaderField:@"X-Method"] isEqualToString:@"GET"] && [seen containsString:@"auth=yes"],
              "POST, 302 with a cookie, GET: %s %s", [[r valueForHTTPHeaderField:@"X-Method"] UTF8String], seen.UTF8String);
        NSURLSession *eph = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
        fetch_on(eph, [NSURLRequest requestWithURL:U(@"/echo")], &r, &e);
        CHECK([[r valueForHTTPHeaderField:@"X-Cookie-Seen"] length] == 0, "an ephemeral session has its own cookies");
        NSMutableURLRequest *nocookies = [NSMutableURLRequest requestWithURL:U(@"/echo")]; [nocookies setHTTPShouldHandleCookies:NO];
        fetch(nocookies, &r, &e);
        CHECK([[r valueForHTTPHeaderField:@"X-Cookie-Seen"] length] == 0, "HTTPShouldHandleCookies NO");

        /* authentication: the delegate answers a 401; without one the 401 is the response */
        Gate *gate = [Gate new];
        NSURLSession *gs = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration] delegate:gate delegateQueue:nil];
        d = fetch_on(gs, [NSURLRequest requestWithURL:U(@"/auth")], &r, &e);
        CHECK(!e && r.statusCode == 200 && [text(d) isEqualToString:@"welcome"] && gate.challenges == 1 && [gate.realm isEqualToString:@"scion"],
              "challenge answered: %ld, %d challenges", (long)r.statusCode, gate.challenges);
        d = fetch([NSURLRequest requestWithURL:U(@"/auth")], &r, &e);
        CHECK(!e && r.statusCode == 401, "no credential: 401");
        NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:@"127.0.0.1" port:port protocol:@"http" realm:@"scion" authenticationMethod:NSURLAuthenticationMethodHTTPBasic];
        [[NSURLCredentialStorage sharedCredentialStorage] setDefaultCredential:[NSURLCredential credentialWithUser:@"user" password:@"secret" persistence:NSURLCredentialPersistenceForSession] forProtectionSpace:space];
        d = fetch([NSURLRequest requestWithURL:U(@"/auth")], &r, &e);
        CHECK(!e && r.statusCode == 200, "the stored default credential: %ld", (long)r.statusCode);
        /* the redirect delegate can stop a redirect: the 302 is the response */
        gate.stopRedirects = YES;
        fetch_on(gs, [NSURLRequest requestWithURL:U(@"/redirect")], &r, &e);
        CHECK(!e && r.statusCode == 302 && [[r valueForHTTPHeaderField:@"Location"] isEqualToString:@"/hello"], "redirect stopped: %ld", (long)r.statusCode);

        /* the synchronous ways */
        CHECK([[NSString stringWithContentsOfURL:U(@"/hello") encoding:NSUTF8StringEncoding error:NULL] isEqualToString:@"hello"]);
        CHECK([NSData dataWithContentsOfURL:U(@"/big")].length == BIG);
        CHECK(![NSData dataWithContentsOfURL:U(@"/missing") options:0 error:&e] && e);
        NSURLResponse *sr;
        d = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:U(@"/hello")] returningResponse:&sr error:&e];
        CHECK(d.length == 5 && [(NSHTTPURLResponse *)sr statusCode] == 200);
        printf("URLSESSION OK\n");
    }
    return 0;
}
