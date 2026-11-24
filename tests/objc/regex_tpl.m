/* NSRegularExpression. The table of cases is generated with Python's re as the reference: tests/objc/regex_gen.py
 * writes regex.m from this template. Prints "REGEX OK". */
#import <Foundation/Foundation.h>
int printf(const char *, ...);
static int fails;
#define CHECK(...) do { if (__VA_ARGS__) printf("ok   %s\n", #__VA_ARGS__); else { printf("FAIL %s (line %d)\n", #__VA_ARGS__, __LINE__); fails++; } } while (0)

struct test_case { NSString *p, *s; int nm, ng; long *r; };
static struct test_case cases[] = {
/*CASES*/
};

int main(void) {
    @autoreleasepool {
        int table_ok = 0, n = (int)(sizeof cases / sizeof cases[0]);
        for (int i = 0; i < n; i++) {
            struct test_case *c = &cases[i];
            NSError *e = nil;
            NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:c->p options:0 error:&e];
            if (!re) { printf("FAIL pattern %d does not compile: %s\n", i, [[e localizedDescription] UTF8String]); fails++; continue; }
            NSArray *ms = [re matchesInString:c->s options:0 range:NSMakeRange(0, [c->s length])];
            BOOL ok = (int)[ms count] == c->nm;
            for (int k = 0; ok && k < c->nm; k++) {
                NSTextCheckingResult *t = ms[k];
                ok = (int)[t numberOfRanges] == c->ng;
                for (int g = 0; ok && g < c->ng; g++) {
                    NSRange r = [t rangeAtIndex:g]; long a = c->r[(k * c->ng + g) * 2], b = c->r[(k * c->ng + g) * 2 + 1];
                    ok = a < 0 ? r.location == NSNotFound : (r.location == (NSUInteger)a && NSMaxRange(r) == (NSUInteger)b);
                }
            }
            if (ok) table_ok++;
            else {
                printf("FAIL case %d /%s/ on \"%s\": expected %d matches, got %lu:", i, [c->p UTF8String], [c->s UTF8String], c->nm, (unsigned long)[ms count]);
                for (NSTextCheckingResult *t in ms) printf(" {%lu,%lu}", (unsigned long)[t range].location, (unsigned long)[t range].length);
                printf("\n"); fails++;
            }
        }
        printf("table: %d/%d cases match the reference\n", table_ok, n);

        /* API */
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(?<k>\\w+)=(?<v>\\d+)" options:0 error:nil];
        NSString *s = @"a=1, bb=22, c=x";
        CHECK([re numberOfCaptureGroups] == 2 && [re numberOfMatchesInString:s options:0 range:NSMakeRange(0, s.length)] == 2);
        NSTextCheckingResult *f = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        CHECK([[s substringWithRange:[f rangeWithName:@"v"]] isEqualToString:@"1"]);
        CHECK([[re stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"$2:$1 \\$"] isEqualToString:@"1:a $, 22:bb $, c=x"]);
        CHECK([[re stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"${v}"] isEqualToString:@"1, 22, c=x"]);
        CHECK([re rangeOfFirstMatchInString:s options:NSMatchingAnchored range:NSMakeRange(1, s.length - 1)].location == NSNotFound);
        CHECK([re rangeOfFirstMatchInString:s options:0 range:NSMakeRange(5, 6)].location == 5);
        NSError *err = nil;
        CHECK([NSRegularExpression regularExpressionWithPattern:@"(abc" options:0 error:&err] == nil && err.code == 2048);
        CHECK([[NSRegularExpression regularExpressionWithPattern:@"HELLO" options:NSRegularExpressionCaseInsensitive error:nil] numberOfMatchesInString:@"hello Hello" options:0 range:NSMakeRange(0, 11)] == 2);
        CHECK([[NSRegularExpression regularExpressionWithPattern:@"a.c" options:NSRegularExpressionIgnoreMetacharacters error:nil] numberOfMatchesInString:@"abc a.c" options:0 range:NSMakeRange(0, 7)] == 1);
        CHECK([[NSRegularExpression escapedPatternForString:@"1+1=2?"] isEqualToString:@"1\\+1=2\\?"]);
        CHECK([@"price: 42 euros" rangeOfString:@"\\d+" options:NSRegularExpressionSearch].location == 7);
        CHECK([[@"a1b22c333" stringByReplacingOccurrencesOfString:@"[0-9]+" withString:@"#" options:NSRegularExpressionSearch range:NSMakeRange(0, 9)] isEqualToString:@"a#b#c#"]);
        NSString *emoji = @"x😀y😀";
        CHECK([[NSRegularExpression regularExpressionWithPattern:@"." options:0 error:nil] numberOfMatchesInString:emoji options:0 range:NSMakeRange(0, emoji.length)] == 4);
        __block int seen = 0;
        [re enumerateMatchesInString:s options:0 range:NSMakeRange(0, s.length) usingBlock:^(NSTextCheckingResult *r, NSMatchingFlags fl, BOOL *stop) { seen++; *stop = YES; }];
        CHECK(seen == 1);
        /* catastrophic pattern: must finish */
        NSString *as = [@"" stringByPaddingToLength:28 withString:@"a" startingAtIndex:0];
        CHECK([[NSRegularExpression regularExpressionWithPattern:@"(a+)+b" options:0 error:nil] numberOfMatchesInString:as options:0 range:NSMakeRange(0, as.length)] == 0);
    }
    printf(fails ? "REGEX: %d FAILURES\n" : "REGEX OK\n", fails);
    return fails;
}
