/* calendar.m — time zones (fixed offsets, no daylight saving rules), locales (their identifier and the en_US
 * conventions), the Gregorian calendar, date components and date formatters (Unicode date patterns), for Foundation and
 * Swift's Foundation overlay. Written from Apple's public documentation. */
#include "internal.h"
double floor(double);

/* ======================================================================= time zones (fixed offsets) */
struct tm_ { int tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst; long tm_gmtoff; char *tm_zone; };
struct tm_ *localtime_r(const long *, struct tm_ *); long time(long *);
static const struct { const char *name, *abbr; int offset; } known_zones[] = {
    {"GMT", "GMT", 0}, {"UTC", "UTC", 0}, {"Europe/London", "GMT", 0}, {"Europe/Lisbon", "WET", 0}, {"Europe/Madrid", "CET", 3600},
    {"Europe/Paris", "CET", 3600}, {"Europe/Berlin", "CET", 3600}, {"Europe/Rome", "CET", 3600}, {"Europe/Amsterdam", "CET", 3600},
    {"Europe/Brussels", "CET", 3600}, {"Europe/Vienna", "CET", 3600}, {"Europe/Zurich", "CET", 3600}, {"Europe/Stockholm", "CET", 3600},
    {"Europe/Warsaw", "CET", 3600}, {"Europe/Athens", "EET", 7200}, {"Europe/Helsinki", "EET", 7200}, {"Europe/Kiev", "EET", 7200},
    {"Europe/Istanbul", "TRT", 10800}, {"Europe/Moscow", "MSK", 10800}, {"Atlantic/Canary", "WET", 0}, {"Africa/Cairo", "EET", 7200},
    {"Africa/Johannesburg", "SAST", 7200}, {"Africa/Lagos", "WAT", 3600}, {"Asia/Dubai", "GST", 14400}, {"Asia/Karachi", "PKT", 18000},
    {"Asia/Kolkata", "IST", 19800}, {"Asia/Dhaka", "BST", 21600}, {"Asia/Bangkok", "ICT", 25200}, {"Asia/Shanghai", "CST", 28800},
    {"Asia/Hong_Kong", "HKT", 28800}, {"Asia/Singapore", "SGT", 28800}, {"Asia/Tokyo", "JST", 32400}, {"Asia/Seoul", "KST", 32400},
    {"Australia/Sydney", "AEST", 36000}, {"Pacific/Auckland", "NZST", 43200}, {"America/Sao_Paulo", "BRT", -10800},
    {"America/Argentina/Buenos_Aires", "ART", -10800}, {"America/Halifax", "AST", -14400}, {"America/New_York", "EST", -18000},
    {"America/Toronto", "EST", -18000}, {"America/Chicago", "CST", -21600}, {"America/Mexico_City", "CST", -21600},
    {"America/Denver", "MST", -25200}, {"America/Phoenix", "MST", -25200}, {"America/Los_Angeles", "PST", -28800},
    {"America/Anchorage", "AKST", -32400}, {"Pacific/Honolulu", "HST", -36000},
};
#define NZONES (sizeof known_zones / sizeof *known_zones)
@implementation NSTimeZone { NSString *_name, *_abbr; NSInteger _off; }
- (instancetype)initWithName:(NSString *)n offset:(NSInteger)off abbreviation:(NSString *)a {
    _name = [n copy]; _off = off; _abbr = [a copy]; return self;
}
- (void)dealloc { [_name release]; [_abbr release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
static NSString *gmt_name(NSInteger off) {
    if (!off) return @"GMT";
    NSInteger a = off < 0 ? -off : off;
    return [NSString stringWithFormat:@"GMT%c%02ld%02ld", off < 0 ? '-' : '+', (long)(a / 3600), (long)(a / 60 % 60)];
}
+ (instancetype)timeZoneForSecondsFromGMT:(NSInteger)s {
    if (s < -18 * 3600 || s > 18 * 3600) return nil;
    return [[[self alloc] initWithName:gmt_name(s) offset:s abbreviation:gmt_name(s)] autorelease];
}
static NSInteger parse_gmt(const char *s, BOOL *ok) { /* GMT+2, GMT-0530, UTC+01:00 */
    *ok = NO; int sign = 1;
    if (!strncmp(s, "GMT", 3) || !strncmp(s, "UTC", 3)) s += 3; else return 0;
    if (!*s) { *ok = YES; return 0; }
    if (*s == '+') s++; else if (*s == '-') { sign = -1; s++; } else return 0;
    int h = 0, m = 0, digits = 0;
    while (isdigit(*s) && digits < 2) { h = h * 10 + (*s++ - '0'); digits++; }
    if (*s == ':') s++;
    if (isdigit(*s)) { m = (s[0] - '0') * 10 + (isdigit(s[1]) ? s[1] - '0' : 0); s += isdigit(s[1]) ? 2 : 1; }
    if (*s || h > 18) return 0;
    *ok = YES; return sign * (h * 3600 + m * 60);
}
- (instancetype)initWithName:(NSString *)n {
    const char *c = [n UTF8String];
    for (unsigned i = 0; i < NZONES; i++) if (!strcmp(c, known_zones[i].name))
        return [self initWithName:n offset:known_zones[i].offset abbreviation:[NSString stringWithUTF8String:known_zones[i].abbr]];
    BOOL ok; NSInteger off = parse_gmt(c, &ok);
    if (ok) return [self initWithName:gmt_name(off) offset:off abbreviation:gmt_name(off)];
    [self release]; return nil;
}
- (instancetype)initWithName:(NSString *)n data:(NSData *)d { return [self initWithName:n]; }
+ (instancetype)timeZoneWithName:(NSString *)n { return [[[self alloc] initWithName:n] autorelease]; }
+ (instancetype)timeZoneWithName:(NSString *)n data:(NSData *)d { return [self timeZoneWithName:n]; }
+ (instancetype)timeZoneWithAbbreviation:(NSString *)a {
    NSString *name = [[self abbreviationDictionary] objectForKey:a];
    if (name) return [self timeZoneWithName:name];
    BOOL ok; NSInteger off = parse_gmt([a UTF8String], &ok);
    return ok ? [self timeZoneForSecondsFromGMT:off] : nil;
}
static NSTimeZone *system_tz, *default_tz;
+ (NSTimeZone *)systemTimeZone {
    @synchronized(self) {
        if (!system_tz) {
            const char *tz = getenv("TZ");
            if (tz && *tz) system_tz = [[NSTimeZone alloc] initWithName:[NSString stringWithUTF8String:tz]];
            if (!system_tz) {
                long now = time(0); struct tm_ t; memset(&t, 0, sizeof t); localtime_r(&now, &t);
                for (unsigned i = 0; i < NZONES && !system_tz; i++) if (known_zones[i].offset == t.tm_gmtoff - (t.tm_isdst > 0 ? 3600 : 0) && i > 1)
                    system_tz = [[NSTimeZone alloc] initWithName:[NSString stringWithUTF8String:known_zones[i].name] offset:t.tm_gmtoff
                                                     abbreviation:t.tm_zone ? [NSString stringWithUTF8String:t.tm_zone] : gmt_name(t.tm_gmtoff)];
                if (!system_tz) system_tz = [[NSTimeZone alloc] initWithName:gmt_name(t.tm_gmtoff) offset:t.tm_gmtoff abbreviation:gmt_name(t.tm_gmtoff)];
            }
        }
        return system_tz;
    }
}
+ (NSTimeZone *)localTimeZone { return [self defaultTimeZone]; }
+ (NSTimeZone *)defaultTimeZone { return default_tz ? default_tz : [self systemTimeZone]; }
+ (void)setDefaultTimeZone:(NSTimeZone *)tz { [default_tz release]; default_tz = [tz retain]; }
+ (void)resetSystemTimeZone { @synchronized(self) { [system_tz release]; system_tz = nil; } }
+ (NSArray<NSString *> *)knownTimeZoneNames {
    NSMutableArray *a = [NSMutableArray array];
    for (unsigned i = 2; i < NZONES; i++) [a addObject:[NSString stringWithUTF8String:known_zones[i].name]];
    return a;
}
static NSDictionary *abbr_dict;
+ (NSDictionary<NSString *, NSString *> *)abbreviationDictionary {
    @synchronized(self) {
        if (!abbr_dict) abbr_dict = [@{@"GMT": @"GMT", @"UTC": @"UTC", @"BST": @"Europe/London", @"WET": @"Europe/Lisbon", @"CET": @"Europe/Paris",
            @"CEST": @"Europe/Paris", @"EET": @"Europe/Athens", @"MSK": @"Europe/Moscow", @"IST": @"Asia/Kolkata", @"PKT": @"Asia/Karachi",
            @"ICT": @"Asia/Bangkok", @"HKT": @"Asia/Hong_Kong", @"SGT": @"Asia/Singapore", @"JST": @"Asia/Tokyo", @"KST": @"Asia/Seoul",
            @"NZST": @"Pacific/Auckland", @"BRT": @"America/Sao_Paulo", @"ART": @"America/Argentina/Buenos_Aires", @"AST": @"America/Halifax",
            @"EST": @"America/New_York", @"EDT": @"America/New_York", @"CST": @"America/Chicago", @"CDT": @"America/Chicago",
            @"MST": @"America/Denver", @"MDT": @"America/Denver", @"PST": @"America/Los_Angeles", @"PDT": @"America/Los_Angeles",
            @"AKST": @"America/Anchorage", @"HST": @"Pacific/Honolulu", @"WAT": @"Africa/Lagos", @"SAST": @"Africa/Johannesburg"} retain];
        return abbr_dict;
    }
}
+ (void)setAbbreviationDictionary:(NSDictionary *)d { @synchronized(self) { [abbr_dict release]; abbr_dict = [d copy]; } }
+ (NSString *)timeZoneDataVersion { return @"2024a"; }
- (NSString *)name { return _name; }
- (NSData *)data { return [NSData data]; }
- (NSInteger)secondsFromGMTForDate:(NSDate *)d { return _off; }
- (NSInteger)secondsFromGMT { return _off; }
- (NSString *)abbreviationForDate:(NSDate *)d { return _abbr; }
- (NSString *)abbreviation { return _abbr; }
- (BOOL)isDaylightSavingTimeForDate:(NSDate *)d { return NO; }
- (BOOL)isDaylightSavingTime { return NO; }
- (NSTimeInterval)daylightSavingTimeOffsetForDate:(NSDate *)d { return 0; }
- (NSTimeInterval)daylightSavingTimeOffset { return 0; }
- (NSDate *)nextDaylightSavingTimeTransitionAfterDate:(NSDate *)d { return nil; }
- (NSDate *)nextDaylightSavingTimeTransition { return nil; }
- (BOOL)isEqualToTimeZone:(NSTimeZone *)o { return [_name isEqualToString:[o name]] && _off == [o secondsFromGMT]; }
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSTimeZone class]] && [self isEqualToTimeZone:o]); }
- (NSUInteger)hash { return [_name hash]; }
- (NSString *)localizedName:(NSTimeZoneNameStyle)style locale:(NSLocale *)l { return style == NSTimeZoneNameStyleShortStandard ? _abbr : _name; }
- (NSString *)description { return [NSString stringWithFormat:@"%@ (%@) offset %ld", _name, _abbr, (long)_off]; }
@end

/* ======================================================================= locales */
@implementation NSLocale { NSString *_id; }
- (instancetype)initWithLocaleIdentifier:(NSString *)s { _id = [s copy]; return self; }
- (void)dealloc { [_id release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
+ (instancetype)localeWithLocaleIdentifier:(NSString *)s { return [[[self alloc] initWithLocaleIdentifier:s] autorelease]; }
static NSLocale *current_locale;
+ (NSLocale *)currentLocale {
    @synchronized(self) {
        if (!current_locale) {
            const char *l = getenv("LC_ALL"); if (!l || !*l) l = getenv("LANG");
            char buf[32] = "en_US";
            if (l && *l && strcmp(l, "C") && strcmp(l, "POSIX")) { size_t i = 0; while (l[i] && l[i] != '.' && l[i] != '@' && i < 31) { buf[i] = l[i]; i++; } buf[i] = 0; }
            current_locale = [[NSLocale alloc] initWithLocaleIdentifier:[NSString stringWithUTF8String:buf]];
        }
        return current_locale;
    }
}
+ (NSLocale *)autoupdatingCurrentLocale { return [self currentLocale]; }
+ (NSLocale *)systemLocale { return [self localeWithLocaleIdentifier:@""]; }
+ (NSArray<NSString *> *)availableLocaleIdentifiers {
    return @[@"en", @"en_US", @"en_GB", @"en_AU", @"en_CA", @"es", @"es_ES", @"es_MX", @"fr", @"fr_FR", @"de", @"de_DE", @"it", @"it_IT",
             @"pt", @"pt_BR", @"pt_PT", @"nl", @"nl_NL", @"sv", @"sv_SE", @"da", @"nb", @"fi", @"pl", @"ru", @"tr", @"ja", @"ja_JP",
             @"ko", @"ko_KR", @"zh", @"zh_CN", @"zh_TW", @"ar", @"he", @"hi", @"th", @"el", @"cs", @"ca", @"eu", @"gl", @"en_US_POSIX"];
}
+ (NSArray<NSString *> *)ISOLanguageCodes { return @[@"ar", @"ca", @"cs", @"da", @"de", @"el", @"en", @"es", @"eu", @"fi", @"fr", @"gl", @"he", @"hi", @"it", @"ja", @"ko", @"nb", @"nl", @"pl", @"pt", @"ru", @"sv", @"th", @"tr", @"zh"]; }
+ (NSArray<NSString *> *)ISOCountryCodes { return @[@"AR", @"AU", @"BR", @"CA", @"CN", @"DE", @"ES", @"FR", @"GB", @"IN", @"IT", @"JP", @"KR", @"MX", @"NL", @"PT", @"RU", @"SE", @"TW", @"US"]; }
+ (NSArray<NSString *> *)ISOCurrencyCodes { return @[@"EUR", @"USD", @"GBP", @"JPY", @"CNY", @"BRL", @"MXN", @"CAD", @"AUD", @"CHF", @"SEK", @"INR", @"KRW", @"RUB"]; }
+ (NSArray<NSString *> *)commonISOCurrencyCodes { return [self ISOCurrencyCodes]; }
+ (NSArray<NSString *> *)preferredLanguages { NSString *l = [[self currentLocale] languageCode]; return @[l ? l : @"en"]; }
+ (NSDictionary *)componentsFromLocaleIdentifier:(NSString *)s {
    NSLocale *l = [self localeWithLocaleIdentifier:s]; NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if ([l languageCode]) d[NSLocaleLanguageCode] = [l languageCode];
    if ([l countryCode]) d[NSLocaleCountryCode] = [l countryCode];
    if ([l scriptCode]) d[NSLocaleScriptCode] = [l scriptCode];
    return d;
}
+ (NSString *)localeIdentifierFromComponents:(NSDictionary *)d {
    NSMutableString *s = [NSMutableString stringWithString:d[NSLocaleLanguageCode] ? d[NSLocaleLanguageCode] : @""];
    if (d[NSLocaleScriptCode]) [s appendFormat:@"_%@", d[NSLocaleScriptCode]];
    if (d[NSLocaleCountryCode]) [s appendFormat:@"_%@", d[NSLocaleCountryCode]];
    return s;
}
+ (NSString *)canonicalLocaleIdentifierFromString:(NSString *)s { return [s stringByReplacingOccurrencesOfString:@"-" withString:@"_"]; }
+ (NSString *)canonicalLanguageIdentifierFromString:(NSString *)s { return [s stringByReplacingOccurrencesOfString:@"_" withString:@"-"]; }
+ (NSString *)localeIdentifierFromWindowsLocaleCode:(uint32_t)l { return l == 0x0c0a ? @"es_ES" : @"en_US"; }
+ (uint32_t)windowsLocaleCodeFromLocaleIdentifier:(NSString *)s { return [s hasPrefix:@"es"] ? 0x0c0a : 0x0409; }
+ (NSLocaleLanguageDirection)characterDirectionForLanguage:(NSString *)l { return [l hasPrefix:@"ar"] || [l hasPrefix:@"he"] ? NSLocaleLanguageDirectionRightToLeft : NSLocaleLanguageDirectionLeftToRight; }
+ (NSLocaleLanguageDirection)lineDirectionForLanguage:(NSString *)l { return NSLocaleLanguageDirectionTopToBottom; }
- (NSString *)localeIdentifier { return _id; }
static NSArray *id_parts(NSString *s) { return [[s stringByReplacingOccurrencesOfString:@"-" withString:@"_"] componentsSeparatedByString:@"_"]; }
- (NSString *)languageCode { NSString *l = [id_parts(_id) firstObject]; return [l length] ? l : @"en"; }
- (NSString *)countryCode { for (NSString *p in [id_parts(_id) subarrayWithRange:NSMakeRange(1, [id_parts(_id) count] - 1)]) if ([p length] == 2 || [p length] == 3) { if ([p isEqualToString:[p uppercaseString]]) return p; } return nil; }
- (NSString *)scriptCode { for (NSString *p in id_parts(_id)) if ([p length] == 4 && ([p characterAtIndex:0] >= 'A' && [p characterAtIndex:0] <= 'Z')) return p; return nil; }
- (NSString *)variantCode { return [_id isEqualToString:@"en_US_POSIX"] ? @"POSIX" : nil; }
- (NSString *)calendarIdentifier { return NSCalendarIdentifierGregorian; }
- (NSString *)collationIdentifier { return nil; }
- (NSString *)collatorIdentifier { return _id; }
static BOOL comma_locale(NSString *lang) { return [@[@"es", @"fr", @"de", @"it", @"pt", @"nl", @"sv", @"da", @"nb", @"fi", @"pl", @"ru", @"tr", @"cs", @"ca", @"eu", @"gl", @"el"] containsObject:lang]; }
- (NSString *)decimalSeparator { return comma_locale([self languageCode]) ? @"," : @"."; }
- (NSString *)groupingSeparator { return comma_locale([self languageCode]) ? @"." : @","; }
- (NSString *)currencyCode { NSString *c = [self countryCode]; if (!c) return nil; return [c isEqualToString:@"US"] ? @"USD" : [c isEqualToString:@"GB"] ? @"GBP" : [c isEqualToString:@"JP"] ? @"JPY" : comma_locale([self languageCode]) ? @"EUR" : @"USD"; }
- (NSString *)currencySymbol { NSString *c = [self currencyCode]; return [c isEqualToString:@"EUR"] ? @"€" : [c isEqualToString:@"GBP"] ? @"£" : [c isEqualToString:@"JPY"] ? @"¥" : @"$"; }
- (BOOL)usesMetricSystem { return ![[self countryCode] isEqualToString:@"US"]; }
- (NSString *)quotationBeginDelimiter { return @"“"; } - (NSString *)quotationEndDelimiter { return @"”"; }
- (NSString *)alternateQuotationBeginDelimiter { return @"‘"; } - (NSString *)alternateQuotationEndDelimiter { return @"’"; }
- (NSCharacterSet *)exemplarCharacterSet { return [NSCharacterSet letterCharacterSet]; }
- (id)objectForKey:(NSLocaleKey)k {
    if ([k isEqualToString:NSLocaleIdentifier]) return _id;
    if ([k isEqualToString:NSLocaleLanguageCode]) return [self languageCode];
    if ([k isEqualToString:NSLocaleCountryCode]) return [self countryCode];
    if ([k isEqualToString:NSLocaleScriptCode]) return [self scriptCode];
    if ([k isEqualToString:NSLocaleVariantCode]) return [self variantCode];
    if ([k isEqualToString:NSLocaleCalendar]) return [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    if ([k isEqualToString:NSLocaleUsesMetricSystem]) return [NSNumber numberWithBool:[self usesMetricSystem]];
    if ([k isEqualToString:NSLocaleMeasurementSystem]) return [self usesMetricSystem] ? @"Metric" : @"U.S.";
    if ([k isEqualToString:NSLocaleDecimalSeparator]) return [self decimalSeparator];
    if ([k isEqualToString:NSLocaleGroupingSeparator]) return [self groupingSeparator];
    if ([k isEqualToString:NSLocaleCurrencySymbol]) return [self currencySymbol];
    if ([k isEqualToString:NSLocaleCurrencyCode]) return [self currencyCode];
    if ([k isEqualToString:NSLocaleExemplarCharacterSet]) return [self exemplarCharacterSet];
    return nil;
}
- (NSString *)displayNameForKey:(NSLocaleKey)k value:(id)v { return [v isKindOfClass:[NSString class]] ? v : nil; } /* ponytail: no localized names */
- (NSString *)localizedStringForLocaleIdentifier:(NSString *)s { return s; }
- (NSString *)localizedStringForLanguageCode:(NSString *)s { return s; }
- (NSString *)localizedStringForCountryCode:(NSString *)s { return s; }
- (NSString *)localizedStringForScriptCode:(NSString *)s { return s; }
- (NSString *)localizedStringForVariantCode:(NSString *)s { return s; }
- (NSString *)localizedStringForCalendarIdentifier:(NSString *)s { return s; }
- (NSString *)localizedStringForCollationIdentifier:(NSString *)s { return s; }
- (NSString *)localizedStringForCurrencyCode:(NSString *)s { return s; }
- (NSString *)localizedStringForCollatorIdentifier:(NSString *)s { return s; }
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSLocale class]] && [_id isEqualToString:[o localeIdentifier]]); }
- (NSUInteger)hash { return [_id hash]; }
- (NSString *)description { return [NSString stringWithFormat:@"%@ (fixed)", _id]; }
@end

/* ======================================================================= the Gregorian calendar */
/* days since 1970-01-01 <-> civil date (Howard Hinnant's algorithms) */
static long days_from_civil(long y, long m, long d) {
    y -= m <= 2; long era = (y >= 0 ? y : y - 399) / 400; long yoe = y - era * 400;
    long doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1; long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}
static void civil_from_days(long z, long *y, long *m, long *d) {
    z += 719468; long era = (z >= 0 ? z : z - 146096) / 146097; long doe = z - era * 146097;
    long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; long yy = yoe + era * 400;
    long doy = doe - (365 * yoe + yoe / 4 - yoe / 100); long mp = (5 * doy + 2) / 153;
    *d = doy - (153 * mp + 2) / 5 + 1; *m = mp + (mp < 10 ? 3 : -9); *y = yy + (*m <= 2);
}
static BOOL is_leap(long y) { return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0; }
static long days_in_month(long y, long m) { static const int dm[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}; return m == 2 && is_leap(y) ? 29 : dm[(m - 1) % 12]; }
static long floordiv(long a, long b) { return a / b - ((a % b != 0) && ((a < 0) != (b < 0))); }
#define REF1970 978307200.0
typedef struct { long era, year, month, day, hour, minute, second, nanosecond, weekday, weekdayOrdinal, quarter, weekOfMonth, weekOfYear, yearForWeekOfYear; } mw_fields;
@implementation NSCalendar { NSString *_ident; NSTimeZone *_tz; NSLocale *_locale; NSUInteger _firstWeekday, _minDays; }
- (id)initWithCalendarIdentifier:(NSCalendarIdentifier)ident {
    if (![ident isEqualToString:NSCalendarIdentifierGregorian] && ![ident isEqualToString:NSCalendarIdentifierISO8601]) { [self release]; return nil; }
    _ident = [ident copy]; _tz = [[NSTimeZone defaultTimeZone] retain]; _locale = [[NSLocale currentLocale] retain];
    BOOL iso = [ident isEqualToString:NSCalendarIdentifierISO8601];
    _firstWeekday = iso ? 2 : 1; _minDays = iso ? 4 : 1;
    return self;
}
- (void)dealloc { [_ident release]; [_tz release]; [_locale release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSCalendar *c = [[NSCalendar alloc] initWithCalendarIdentifier:_ident]; [c setTimeZone:_tz]; [c setLocale:_locale]; c->_firstWeekday = _firstWeekday; c->_minDays = _minDays; return c; }
+ (NSCalendar *)currentCalendar { return [[[self alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian] autorelease]; }
+ (NSCalendar *)autoupdatingCurrentCalendar { return [self currentCalendar]; }
+ (NSCalendar *)calendarWithIdentifier:(NSCalendarIdentifier)i { return [[[self alloc] initWithCalendarIdentifier:i] autorelease]; }
- (NSCalendarIdentifier)calendarIdentifier { return _ident; }
- (NSTimeZone *)timeZone { return _tz; }
- (void)setTimeZone:(NSTimeZone *)tz { if (!tz) tz = [NSTimeZone defaultTimeZone]; [_tz release]; _tz = [tz retain]; }
- (NSLocale *)locale { return _locale; }
- (void)setLocale:(NSLocale *)l { [_locale release]; _locale = [l retain]; }
- (NSUInteger)firstWeekday { return _firstWeekday; } - (void)setFirstWeekday:(NSUInteger)w { _firstWeekday = w; }
- (NSUInteger)minimumDaysInFirstWeek { return _minDays; } - (void)setMinimumDaysInFirstWeek:(NSUInteger)m { _minDays = m; }
- (NSArray *)monthSymbols { return @[@"January", @"February", @"March", @"April", @"May", @"June", @"July", @"August", @"September", @"October", @"November", @"December"]; }
- (NSArray *)shortMonthSymbols { return @[@"Jan", @"Feb", @"Mar", @"Apr", @"May", @"Jun", @"Jul", @"Aug", @"Sep", @"Oct", @"Nov", @"Dec"]; }
- (NSArray *)veryShortMonthSymbols { return @[@"J", @"F", @"M", @"A", @"M", @"J", @"J", @"A", @"S", @"O", @"N", @"D"]; }
- (NSArray *)standaloneMonthSymbols { return [self monthSymbols]; } - (NSArray *)shortStandaloneMonthSymbols { return [self shortMonthSymbols]; }
- (NSArray *)veryShortStandaloneMonthSymbols { return [self veryShortMonthSymbols]; }
- (NSArray *)weekdaySymbols { return @[@"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday", @"Saturday"]; }
- (NSArray *)shortWeekdaySymbols { return @[@"Sun", @"Mon", @"Tue", @"Wed", @"Thu", @"Fri", @"Sat"]; }
- (NSArray *)veryShortWeekdaySymbols { return @[@"S", @"M", @"T", @"W", @"T", @"F", @"S"]; }
- (NSArray *)standaloneWeekdaySymbols { return [self weekdaySymbols]; } - (NSArray *)shortStandaloneWeekdaySymbols { return [self shortWeekdaySymbols]; }
- (NSArray *)veryShortStandaloneWeekdaySymbols { return [self veryShortWeekdaySymbols]; }
- (NSArray *)eraSymbols { return @[@"BC", @"AD"]; } - (NSArray *)longEraSymbols { return @[@"Before Christ", @"Anno Domini"]; }
- (NSArray *)quarterSymbols { return @[@"1st quarter", @"2nd quarter", @"3rd quarter", @"4th quarter"]; }
- (NSArray *)shortQuarterSymbols { return @[@"Q1", @"Q2", @"Q3", @"Q4"]; }
- (NSArray *)standaloneQuarterSymbols { return [self quarterSymbols]; } - (NSArray *)shortStandaloneQuarterSymbols { return [self shortQuarterSymbols]; }
- (NSString *)AMSymbol { return @"AM"; } - (NSString *)PMSymbol { return @"PM"; }
- (NSInteger)formattingContext { return 0; } - (void)setFormattingContext:(NSInteger)c { }
static mw_fields fields_of(NSCalendar *c, NSDate *date, NSTimeZone *tz) {
    mw_fields f; memset(&f, 0, sizeof f);
    double t = [date timeIntervalSinceReferenceDate] + REF1970 + (double)[tz secondsFromGMTForDate:date];
    double ts = floor(t); long secs = (long)ts; long days = floordiv(secs, 86400), rem = secs - days * 86400;
    civil_from_days(days, &f.year, &f.month, &f.day);
    f.hour = rem / 3600; f.minute = rem / 60 % 60; f.second = rem % 60; f.nanosecond = (long)((t - ts) * 1e9 + 0.5);
    if (f.nanosecond >= 1000000000) f.nanosecond = 999999999;
    f.weekday = floordiv(days + 4, 7) * -7 + days + 4 + 1; /* 1970-01-01 was a Thursday: 1 = Sunday */
    f.era = f.year > 0; if (f.year <= 0) f.year = 1 - f.year;
    f.quarter = (f.month - 1) / 3 + 1; f.weekdayOrdinal = (f.day - 1) / 7 + 1;
    long fw = (long)c->_firstWeekday, md = (long)c->_minDays;
    long jan1 = days_from_civil(f.era ? f.year : 1 - f.year, 1, 1), doy = days - jan1;
    long jan1wd = ((jan1 + 4) % 7 + 7) % 7 + 1, off = ((jan1wd - fw) + 7) % 7; /* days of week 1 before Jan 1 */
    long week = (doy + off) / 7 + ((7 - off) >= md ? 1 : 0);
    f.yearForWeekOfYear = f.era ? f.year : 1 - f.year;
    if (week == 0) { /* belongs to the last week of the previous year */
        long py = f.yearForWeekOfYear - 1, pj = days_from_civil(py, 1, 1), pwd = ((pj + 4) % 7 + 7) % 7 + 1, poff = ((pwd - fw) + 7) % 7;
        week = (days - pj + poff) / 7 + ((7 - poff) >= md ? 1 : 0); f.yearForWeekOfYear = py;
    } else {
        long ny = f.yearForWeekOfYear + 1, nj = days_from_civil(ny, 1, 1), nwd = ((nj + 4) % 7 + 7) % 7 + 1, noff = ((nwd - fw) + 7) % 7;
        if ((7 - noff) >= md && days >= nj - noff) { week = 1; f.yearForWeekOfYear = ny; }
    }
    f.weekOfYear = week;
    long first = days - (f.day - 1), fwd = ((first + 4) % 7 + 7) % 7 + 1, moff = ((fwd - fw) + 7) % 7;
    f.weekOfMonth = (f.day - 1 + moff) / 7 + ((7 - moff) >= md ? 1 : 0);
    return f;
}
static NSDate *date_of(long era, long y, long mo, long d, long h, long mi, long s, long ns, NSTimeZone *tz) {
    if (!era) y = 1 - y;
    y += floordiv(mo - 1, 12); mo = mo - 1 - floordiv(mo - 1, 12) * 12 + 1;
    double days = (double)days_from_civil(y, mo, 1) + (double)(d - 1);
    double t = days * 86400 + (double)h * 3600 + (double)mi * 60 + (double)s + (double)ns / 1e9 - REF1970;
    NSDate *guess = [NSDate dateWithTimeIntervalSinceReferenceDate:t];
    return [NSDate dateWithTimeIntervalSinceReferenceDate:t - (double)[tz secondsFromGMTForDate:guess]];
}
#define U(x) NSCalendarUnit##x
- (NSDateComponents *)components:(NSCalendarUnit)units fromDate:(NSDate *)date { return [self _components:units fromDate:date timeZone:_tz]; }
- (NSDateComponents *)componentsInTimeZone:(NSTimeZone *)tz fromDate:(NSDate *)date {
    NSDateComponents *c = [self _components:(NSCalendarUnit)~0ul fromDate:date timeZone:tz]; [c setCalendar:self]; [c setTimeZone:tz]; return c;
}
- (NSDateComponents *)_components:(NSCalendarUnit)u fromDate:(NSDate *)date timeZone:(NSTimeZone *)tz {
    mw_fields f = fields_of(self, date, tz); NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    if (u & U(Era)) [c setEra:f.era]; if (u & U(Year)) [c setYear:f.year]; if (u & U(Month)) [c setMonth:f.month];
    if (u & U(Day)) [c setDay:f.day]; if (u & U(Hour)) [c setHour:f.hour]; if (u & U(Minute)) [c setMinute:f.minute];
    if (u & U(Second)) [c setSecond:f.second]; if (u & U(Nanosecond)) [c setNanosecond:f.nanosecond]; if (u & U(Weekday)) [c setWeekday:f.weekday];
    if (u & U(WeekdayOrdinal)) [c setWeekdayOrdinal:f.weekdayOrdinal]; if (u & U(Quarter)) [c setQuarter:f.quarter];
    if (u & U(WeekOfMonth)) [c setWeekOfMonth:f.weekOfMonth]; if (u & U(WeekOfYear)) [c setWeekOfYear:f.weekOfYear];
    if (u & U(YearForWeekOfYear)) [c setYearForWeekOfYear:f.yearForWeekOfYear];
    if (u & U(Calendar)) [c setCalendar:self]; if (u & U(TimeZone)) [c setTimeZone:tz];
    return c;
}
static long cv(NSInteger v, long dflt) { return v == NSDateComponentUndefined ? dflt : (long)v; }
- (NSDate *)dateFromComponents:(NSDateComponents *)c {
    NSTimeZone *tz = [c timeZone] ? [c timeZone] : _tz;
    long year = cv([c year], 1), month = cv([c month], 1), day = cv([c day], 1);
    if ([c year] == NSDateComponentUndefined && [c yearForWeekOfYear] != NSDateComponentUndefined) {
        /* week-based date: Monday-or-firstWeekday of the week, then the weekday */
        long y = [c yearForWeekOfYear], wk = cv([c weekOfYear], 1), wd = cv([c weekday], (long)_firstWeekday);
        long jan1 = days_from_civil(y, 1, 1), jwd = ((jan1 + 4) % 7 + 7) % 7 + 1, off = ((jwd - (long)_firstWeekday) + 7) % 7;
        long start = jan1 - off + ((7 - off) >= (long)_minDays ? 0 : 7) + (wk - 1) * 7 + ((wd - (long)_firstWeekday) + 7) % 7;
        civil_from_days(start, &year, &month, &day);
    }
    return date_of(cv([c era], 1), year, month, day, cv([c hour], 0), cv([c minute], 0), cv([c second], 0), cv([c nanosecond], 0), tz);
}
- (NSInteger)component:(NSCalendarUnit)unit fromDate:(NSDate *)date { return [[self components:unit fromDate:date] valueForComponent:unit]; }
- (void)getEra:(NSInteger *)e year:(NSInteger *)y month:(NSInteger *)m day:(NSInteger *)d fromDate:(NSDate *)date {
    mw_fields f = fields_of(self, date, _tz); if (e) *e = f.era; if (y) *y = f.year; if (m) *m = f.month; if (d) *d = f.day;
}
- (void)getEra:(NSInteger *)e yearForWeekOfYear:(NSInteger *)y weekOfYear:(NSInteger *)w weekday:(NSInteger *)wd fromDate:(NSDate *)date {
    mw_fields f = fields_of(self, date, _tz); if (e) *e = f.era; if (y) *y = f.yearForWeekOfYear; if (w) *w = f.weekOfYear; if (wd) *wd = f.weekday;
}
- (void)getHour:(NSInteger *)h minute:(NSInteger *)m second:(NSInteger *)s nanosecond:(NSInteger *)ns fromDate:(NSDate *)date {
    mw_fields f = fields_of(self, date, _tz); if (h) *h = f.hour; if (m) *m = f.minute; if (s) *s = f.second; if (ns) *ns = f.nanosecond;
}
- (NSDate *)dateWithEra:(NSInteger)e year:(NSInteger)y month:(NSInteger)m day:(NSInteger)d hour:(NSInteger)h minute:(NSInteger)mi second:(NSInteger)s nanosecond:(NSInteger)ns {
    return date_of(e, y, m, d, h, mi, s, ns, _tz);
}
- (NSDate *)dateWithEra:(NSInteger)e yearForWeekOfYear:(NSInteger)y weekOfYear:(NSInteger)w weekday:(NSInteger)wd hour:(NSInteger)h minute:(NSInteger)mi second:(NSInteger)s nanosecond:(NSInteger)ns {
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    [c setEra:e]; [c setYearForWeekOfYear:y]; [c setWeekOfYear:w]; [c setWeekday:wd]; [c setHour:h]; [c setMinute:mi]; [c setSecond:s]; [c setNanosecond:ns];
    return [self dateFromComponents:c];
}
- (NSDate *)dateByAddingComponents:(NSDateComponents *)c toDate:(NSDate *)date options:(NSCalendarOptions)opts {
    mw_fields f = fields_of(self, date, _tz);
    long y = f.era ? f.year : 1 - f.year, mo = f.month + cv([c month], 0) + 12 * cv([c year], 0) + 3 * cv([c quarter], 0);
    y += floordiv(mo - 1, 12); mo = mo - 1 - floordiv(mo - 1, 12) * 12 + 1;
    long d = f.day; if (d > days_in_month(y, mo)) d = days_in_month(y, mo); /* Jan 31 + 1 month = Feb 28/29 */
    d += cv([c day], 0) + 7 * (cv([c weekOfYear], 0) + cv([c weekOfMonth], 0)) + cv([c weekday], 0);
    NSDate *r = date_of(1, y, mo, d, f.hour, f.minute, f.second, f.nanosecond, _tz);
    double extra = (double)cv([c hour], 0) * 3600 + (double)cv([c minute], 0) * 60 + (double)cv([c second], 0) + (double)cv([c nanosecond], 0) / 1e9;
    return [r dateByAddingTimeInterval:extra];
}
- (NSDate *)dateByAddingUnit:(NSCalendarUnit)unit value:(NSInteger)v toDate:(NSDate *)date options:(NSCalendarOptions)o {
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease]; [c setValue:v forComponent:unit];
    return [self dateByAddingComponents:c toDate:date options:o];
}
- (NSDateComponents *)components:(NSCalendarUnit)u fromDate:(NSDate *)a toDate:(NSDate *)b options:(NSCalendarOptions)o {
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    NSDate *cur = a; BOOL neg = [b compare:a] == NSOrderedAscending;
    static const NSCalendarUnit order[] = {NSCalendarUnitEra, NSCalendarUnitYear, NSCalendarUnitMonth, NSCalendarUnitWeekOfYear, NSCalendarUnitDay, NSCalendarUnitHour,
                                           NSCalendarUnitMinute, NSCalendarUnitSecond, NSCalendarUnitNanosecond};
    for (unsigned i = 0; i < sizeof order / sizeof *order; i++) {
        NSCalendarUnit k = order[i]; if (!(u & k) || k == NSCalendarUnitEra) continue;
        NSInteger n = 0;
        if (k == NSCalendarUnitNanosecond) n = (NSInteger)(([b timeIntervalSinceReferenceDate] - [cur timeIntervalSinceReferenceDate]) * 1e9);
        else if (k >= NSCalendarUnitDay && k <= NSCalendarUnitSecond) {
            double per = k == NSCalendarUnitDay ? 86400 : k == NSCalendarUnitHour ? 3600 : k == NSCalendarUnitMinute ? 60 : 1;
            n = (NSInteger)(([b timeIntervalSinceReferenceDate] - [cur timeIntervalSinceReferenceDate]) / per);
        } else {
            NSCalendarUnit step = k == NSCalendarUnitWeekOfYear ? NSCalendarUnitDay : k; NSInteger mult = k == NSCalendarUnitWeekOfYear ? 7 : 1;
            for (;;) { NSDate *nx = [self dateByAddingUnit:step value:(n + (neg ? -1 : 1)) * mult toDate:cur options:0];
                       if (neg ? [nx compare:b] == NSOrderedAscending : [nx compare:b] == NSOrderedDescending) break; n += neg ? -1 : 1; if (n > 100000 || n < -100000) break; }
        }
        [c setValue:n forComponent:k];
        if (k != NSCalendarUnitNanosecond) cur = [self dateByAddingUnit:(k == NSCalendarUnitWeekOfYear ? NSCalendarUnitDay : k) value:(k == NSCalendarUnitWeekOfYear ? n * 7 : n) toDate:cur options:0];
    }
    return c;
}
- (NSDateComponents *)components:(NSCalendarUnit)u fromDateComponents:(NSDateComponents *)a toDateComponents:(NSDateComponents *)b options:(NSCalendarOptions)o {
    return [self components:u fromDate:[self dateFromComponents:a] toDate:[self dateFromComponents:b] options:o];
}
- (NSRange)minimumRangeOfUnit:(NSCalendarUnit)u {
    switch (u) { case U(Era): return NSMakeRange(0, 2); case U(Year): return NSMakeRange(1, 140742); case U(Month): return NSMakeRange(1, 12);
                 case U(Day): return NSMakeRange(1, 28); case U(Hour): return NSMakeRange(0, 24); case U(Minute): case U(Second): return NSMakeRange(0, 60);
                 case U(Weekday): return NSMakeRange(1, 7); case U(WeekdayOrdinal): return NSMakeRange(1, 4); case U(Quarter): return NSMakeRange(1, 4);
                 case U(WeekOfMonth): return NSMakeRange(1, 4); case U(WeekOfYear): return NSMakeRange(1, 52); case U(Nanosecond): return NSMakeRange(0, 1000000000);
                 default: return NSMakeRange(NSNotFound, NSNotFound); }
}
- (NSRange)maximumRangeOfUnit:(NSCalendarUnit)u {
    switch (u) { case U(Day): return NSMakeRange(1, 31); case U(WeekdayOrdinal): return NSMakeRange(1, 5); case U(WeekOfMonth): return NSMakeRange(1, 6);
                 case U(WeekOfYear): return NSMakeRange(1, 53); case U(Year): return NSMakeRange(1, 144683); default: return [self minimumRangeOfUnit:u]; }
}
- (NSRange)rangeOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date {
    mw_fields f = fields_of(self, date, _tz); long y = f.era ? f.year : 1 - f.year;
    if (smaller == U(Day) && larger == U(Month)) return NSMakeRange(1, (NSUInteger)days_in_month(y, f.month));
    if (smaller == U(Day) && larger == U(Year)) return NSMakeRange(1, is_leap(y) ? 366 : 365);
    if (smaller == U(Month) && larger == U(Year)) return NSMakeRange(1, 12);
    if (smaller == U(Hour) && larger == U(Day)) return NSMakeRange(0, 24);
    if (smaller == U(Minute) && larger == U(Hour)) return NSMakeRange(0, 60);
    if (smaller == U(Second) && larger == U(Minute)) return NSMakeRange(0, 60);
    if (smaller == U(Weekday)) return NSMakeRange(1, 7);
    return [self maximumRangeOfUnit:smaller];
}
- (NSUInteger)ordinalityOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date {
    mw_fields f = fields_of(self, date, _tz); long y = f.era ? f.year : 1 - f.year;
    if (smaller == U(Day) && larger == U(Month)) return (NSUInteger)f.day;
    if (smaller == U(Day) && larger == U(Year)) return (NSUInteger)(days_from_civil(y, f.month, f.day) - days_from_civil(y, 1, 1) + 1);
    if (smaller == U(Month) && larger == U(Year)) return (NSUInteger)f.month;
    if (smaller == U(Hour) && larger == U(Day)) return (NSUInteger)f.hour + 1;
    if (smaller == U(Weekday) && larger == U(WeekOfYear)) return (NSUInteger)(((f.weekday - (long)_firstWeekday) + 7) % 7 + 1);
    if (smaller == U(WeekOfYear) && larger == U(Year)) return (NSUInteger)f.weekOfYear;
    return NSNotFound;
}
- (BOOL)rangeOfUnit:(NSCalendarUnit)u startDate:(NSDate **)start interval:(NSTimeInterval *)iv forDate:(NSDate *)date {
    mw_fields f = fields_of(self, date, _tz); long y = f.era ? f.year : 1 - f.year; NSDate *s; double len;
    switch (u) {
    case U(Year): s = date_of(1, y, 1, 1, 0, 0, 0, 0, _tz); len = (is_leap(y) ? 366 : 365) * 86400.0; break;
    case U(Month): s = date_of(1, y, f.month, 1, 0, 0, 0, 0, _tz); len = (double)days_in_month(y, f.month) * 86400; break;
    case U(Day): s = date_of(1, y, f.month, f.day, 0, 0, 0, 0, _tz); len = 86400; break;
    case U(Hour): s = date_of(1, y, f.month, f.day, f.hour, 0, 0, 0, _tz); len = 3600; break;
    case U(Minute): s = date_of(1, y, f.month, f.day, f.hour, f.minute, 0, 0, _tz); len = 60; break;
    case U(Second): s = date_of(1, y, f.month, f.day, f.hour, f.minute, f.second, 0, _tz); len = 1; break;
    case U(WeekOfYear): case U(WeekOfMonth): {
        long back = ((f.weekday - (long)_firstWeekday) + 7) % 7;
        s = [date_of(1, y, f.month, f.day, 0, 0, 0, 0, _tz) dateByAddingTimeInterval:-86400.0 * (double)back]; len = 7 * 86400; break;
    }
    default: return NO;
    }
    if (start) *start = s; if (iv) *iv = len; return YES;
}
- (NSDate *)startOfDayForDate:(NSDate *)d { NSDate *s = nil; [self rangeOfUnit:NSCalendarUnitDay startDate:&s interval:0 forDate:d]; return s; }
- (NSComparisonResult)compareDate:(NSDate *)a toDate:(NSDate *)b toUnitGranularity:(NSCalendarUnit)u {
    NSDate *sa = nil, *sb = nil; [self rangeOfUnit:u startDate:&sa interval:0 forDate:a]; [self rangeOfUnit:u startDate:&sb interval:0 forDate:b];
    return [sa ? sa : a compare:sb ? sb : b];
}
- (BOOL)isDate:(NSDate *)a equalToDate:(NSDate *)b toUnitGranularity:(NSCalendarUnit)u { return [self compareDate:a toDate:b toUnitGranularity:u] == NSOrderedSame; }
- (BOOL)isDate:(NSDate *)a inSameDayAsDate:(NSDate *)b { return [self isDate:a equalToDate:b toUnitGranularity:NSCalendarUnitDay]; }
- (BOOL)isDateInToday:(NSDate *)d { return [self isDate:d inSameDayAsDate:[NSDate date]]; }
- (BOOL)isDateInYesterday:(NSDate *)d { return [self isDate:d inSameDayAsDate:[NSDate dateWithTimeIntervalSinceNow:-86400]]; }
- (BOOL)isDateInTomorrow:(NSDate *)d { return [self isDate:d inSameDayAsDate:[NSDate dateWithTimeIntervalSinceNow:86400]]; }
- (BOOL)isDateInWeekend:(NSDate *)d { NSInteger w = [self component:NSCalendarUnitWeekday fromDate:d]; return w == 1 || w == 7; }
- (BOOL)rangeOfWeekendStartDate:(NSDate **)s interval:(NSTimeInterval *)iv containingDate:(NSDate *)d {
    if (![self isDateInWeekend:d]) return NO;
    NSDate *day = [self startOfDayForDate:d]; if ([self component:NSCalendarUnitWeekday fromDate:d] == 1) day = [day dateByAddingTimeInterval:-86400];
    if (s) *s = day; if (iv) *iv = 2 * 86400; return YES;
}
- (BOOL)nextWeekendStartDate:(NSDate **)s interval:(NSTimeInterval *)iv options:(NSCalendarOptions)o afterDate:(NSDate *)d {
    NSDate *day = [self startOfDayForDate:d];
    for (int i = 1; i <= 7; i++) { NSDate *n = [day dateByAddingTimeInterval:(o & NSCalendarSearchBackwards ? -86400.0 : 86400.0) * i];
        if ([self component:NSCalendarUnitWeekday fromDate:n] == 7) { if (s) *s = n; if (iv) *iv = 2 * 86400; return YES; } }
    return NO;
}
- (BOOL)date:(NSDate *)date matchesComponents:(NSDateComponents *)c {
    NSDateComponents *have = [self componentsInTimeZone:_tz fromDate:date];
    static const NSCalendarUnit all[] = {U(Era), U(Year), U(Month), U(Day), U(Hour), U(Minute), U(Second), U(Weekday), U(WeekdayOrdinal), U(Quarter),
                                         U(WeekOfMonth), U(WeekOfYear), U(YearForWeekOfYear), U(Nanosecond)};
    for (unsigned i = 0; i < sizeof all / sizeof *all; i++) { NSInteger v = [c valueForComponent:all[i]]; if (v != NSDateComponentUndefined && v != [have valueForComponent:all[i]]) return NO; }
    return YES;
}
- (NSDate *)nextDateAfterDate:(NSDate *)date matchingComponents:(NSDateComponents *)c options:(NSCalendarOptions)o {
    /* ponytail: steps by the smallest unit the components name, up to 4 years */
    NSCalendarUnit step = [c second] != NSDateComponentUndefined ? U(Second) : [c minute] != NSDateComponentUndefined ? U(Minute)
                        : [c hour] != NSDateComponentUndefined ? U(Hour) : U(Day);
    NSDate *d = date;
    if (step != U(Second)) { NSDate *s = nil; [self rangeOfUnit:step startDate:&s interval:0 forDate:d]; d = s ? s : d; }
    BOOL back = (o & NSCalendarSearchBackwards) != 0;
    for (int i = 0; i < 1500 * (step == U(Day) ? 1 : step == U(Hour) ? 24 : 60); i++) {
        d = [self dateByAddingUnit:step value:back ? -1 : 1 toDate:d options:0];
        if ([self date:d matchesComponents:c]) return d;
    }
    return nil;
}
- (void)enumerateDatesStartingAfterDate:(NSDate *)start matchingComponents:(NSDateComponents *)c options:(NSCalendarOptions)o usingBlock:(void (^)(NSDate *, BOOL, BOOL *))block {
    NSDate *d = start; BOOL stop = NO;
    while (!stop && (d = [self nextDateAfterDate:d matchingComponents:c options:o])) block(d, YES, &stop);
}
- (NSDate *)nextDateAfterDate:(NSDate *)date matchingUnit:(NSCalendarUnit)u value:(NSInteger)v options:(NSCalendarOptions)o {
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease]; [c setValue:v forComponent:u]; return [self nextDateAfterDate:date matchingComponents:c options:o];
}
- (NSDate *)nextDateAfterDate:(NSDate *)date matchingHour:(NSInteger)h minute:(NSInteger)m second:(NSInteger)s options:(NSCalendarOptions)o {
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease]; [c setHour:h]; [c setMinute:m]; [c setSecond:s]; return [self nextDateAfterDate:date matchingComponents:c options:o];
}
- (NSDate *)dateBySettingUnit:(NSCalendarUnit)u value:(NSInteger)v ofDate:(NSDate *)date options:(NSCalendarOptions)o {
    NSDateComponents *c = [self componentsInTimeZone:_tz fromDate:date]; [c setValue:v forComponent:u];
    if (u != U(Weekday)) [c setWeekday:NSDateComponentUndefined]; [c setWeekOfYear:NSDateComponentUndefined]; [c setYearForWeekOfYear:NSDateComponentUndefined];
    return [self dateFromComponents:c];
}
- (NSDate *)dateBySettingHour:(NSInteger)h minute:(NSInteger)m second:(NSInteger)s ofDate:(NSDate *)date options:(NSCalendarOptions)o {
    mw_fields f = fields_of(self, date, _tz); return date_of(f.era, f.year, f.month, f.day, h, m, s, 0, _tz);
}
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSCalendar class]] && [_ident isEqualToString:[o calendarIdentifier]] && [_tz isEqual:[o timeZone]]); }
- (NSUInteger)hash { return [_ident hash]; }
@end

@implementation NSDateComponents { NSInteger _v[14]; BOOL _leap; NSCalendar *_cal; NSTimeZone *_tz; }
- (instancetype)init { for (int i = 0; i < 14; i++) _v[i] = NSDateComponentUndefined; return self; }
- (void)dealloc { [_cal release]; [_tz release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSDateComponents *c = [[NSDateComponents alloc] init]; memcpy(c->_v, _v, sizeof _v); c->_leap = _leap; c->_cal = [_cal retain]; c->_tz = [_tz retain]; return c; }
static int slot(NSCalendarUnit u) {
    switch (u) { case U(Era): return 0; case U(Year): return 1; case U(Month): return 2; case U(Day): return 3; case U(Hour): return 4;
                 case U(Minute): return 5; case U(Second): return 6; case U(Nanosecond): return 7; case U(Weekday): return 8;
                 case U(WeekdayOrdinal): return 9; case U(Quarter): return 10; case U(WeekOfMonth): return 11; case U(WeekOfYear): return 12;
                 case U(YearForWeekOfYear): return 13; default: return -1; }
}
- (void)setValue:(NSInteger)v forComponent:(NSCalendarUnit)u { int s = slot(u); if (s >= 0) _v[s] = v; }
- (NSInteger)valueForComponent:(NSCalendarUnit)u { int s = slot(u); return s >= 0 ? _v[s] : NSDateComponentUndefined; }
#define ACC(get, set, i) - (NSInteger)get { return _v[i]; } - (void)set:(NSInteger)v { _v[i] = v; }
ACC(era, setEra, 0) ACC(year, setYear, 1) ACC(month, setMonth, 2) ACC(day, setDay, 3) ACC(hour, setHour, 4) ACC(minute, setMinute, 5)
ACC(second, setSecond, 6) ACC(nanosecond, setNanosecond, 7) ACC(weekday, setWeekday, 8) ACC(weekdayOrdinal, setWeekdayOrdinal, 9)
ACC(quarter, setQuarter, 10) ACC(weekOfMonth, setWeekOfMonth, 11) ACC(weekOfYear, setWeekOfYear, 12) ACC(yearForWeekOfYear, setYearForWeekOfYear, 13)
- (BOOL)isLeapMonth { return _leap; } - (void)setLeapMonth:(BOOL)l { _leap = l; }
- (NSCalendar *)calendar { return _cal; } - (void)setCalendar:(NSCalendar *)c { [_cal release]; _cal = [c copy]; }
- (NSTimeZone *)timeZone { return _tz; } - (void)setTimeZone:(NSTimeZone *)t { [_tz release]; _tz = [t retain]; }
- (NSDate *)date { return _cal ? [_cal dateFromComponents:self] : nil; }
- (BOOL)isValidDate { return _cal ? [self isValidDateInCalendar:_cal] : NO; }
- (BOOL)isValidDateInCalendar:(NSCalendar *)cal {
    if (_v[2] != NSDateComponentUndefined && (_v[2] < 1 || _v[2] > 12)) return NO;
    if (_v[3] != NSDateComponentUndefined && (_v[3] < 1 || _v[3] > days_in_month(_v[1] == NSDateComponentUndefined ? 2001 : _v[1], _v[2] == NSDateComponentUndefined ? 1 : _v[2]))) return NO;
    if (_v[4] != NSDateComponentUndefined && (_v[4] < 0 || _v[4] > 23)) return NO;
    if (_v[5] != NSDateComponentUndefined && (_v[5] < 0 || _v[5] > 59)) return NO;
    if (_v[6] != NSDateComponentUndefined && (_v[6] < 0 || _v[6] > 59)) return NO;
    return YES;
}
- (BOOL)isEqual:(id)o {
    if (o == self) return YES; if (![o isKindOfClass:[NSDateComponents class]]) return NO;
    NSDateComponents *c = o; return !memcmp(_v, c->_v, sizeof _v) && _leap == c->_leap;
}
- (NSUInteger)hash { NSUInteger h = 0; for (int i = 0; i < 14; i++) h = h * 31 + (NSUInteger)_v[i]; return h; }
@end

@implementation NSDateInterval { NSDate *_start; NSTimeInterval _dur; }
- (instancetype)init { return [self initWithStartDate:[NSDate date] duration:0]; }
- (instancetype)initWithStartDate:(NSDate *)s duration:(NSTimeInterval)d { _start = [s copy]; _dur = d; return self; }
- (instancetype)initWithStartDate:(NSDate *)s endDate:(NSDate *)e { return [self initWithStartDate:s duration:[e timeIntervalSinceDate:s]]; }
- (void)dealloc { [_start release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSDate *)startDate { return _start; } - (NSDate *)endDate { return [_start dateByAddingTimeInterval:_dur]; } - (NSTimeInterval)duration { return _dur; }
- (NSComparisonResult)compare:(NSDateInterval *)o { NSComparisonResult r = [_start compare:[o startDate]]; return r != NSOrderedSame ? r : _dur < [o duration] ? NSOrderedAscending : _dur > [o duration] ? NSOrderedDescending : NSOrderedSame; }
- (BOOL)isEqualToDateInterval:(NSDateInterval *)o { return [self compare:o] == NSOrderedSame; }
- (BOOL)intersectsDateInterval:(NSDateInterval *)o { return [[self startDate] compare:[o endDate]] != NSOrderedDescending && [[o startDate] compare:[self endDate]] != NSOrderedDescending; }
- (NSDateInterval *)intersectionWithDateInterval:(NSDateInterval *)o {
    if (![self intersectsDateInterval:o]) return nil;
    NSDate *s = [[self startDate] laterDate:[o startDate]], *e = [[self endDate] earlierDate:[o endDate]];
    return [[[NSDateInterval alloc] initWithStartDate:s endDate:e] autorelease];
}
- (BOOL)containsDate:(NSDate *)d { return [d compare:_start] != NSOrderedAscending && [d compare:[self endDate]] != NSOrderedDescending; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSDateInterval class]] && [self isEqualToDateInterval:o]; }
- (NSUInteger)hash { return [_start hash] ^ (NSUInteger)_dur; }
@end

@implementation NSDate (NSExtendedDate)
- (instancetype)initWithTimeIntervalSinceNow:(NSTimeInterval)s { return [self initWithTimeIntervalSinceReferenceDate:[NSDate timeIntervalSinceReferenceDate] + s]; }
- (instancetype)initWithTimeIntervalSince1970:(NSTimeInterval)s { return [self initWithTimeIntervalSinceReferenceDate:s - REF1970]; }
- (instancetype)initWithTimeInterval:(NSTimeInterval)s sinceDate:(NSDate *)d { return [self initWithTimeIntervalSinceReferenceDate:[d timeIntervalSinceReferenceDate] + s]; }
- (BOOL)isEqualToDate:(NSDate *)o { return [o timeIntervalSinceReferenceDate] == [self timeIntervalSinceReferenceDate]; }
- (NSDate *)earlierDate:(NSDate *)o { return [self compare:o] == NSOrderedDescending ? o : self; }
- (NSDate *)laterDate:(NSDate *)o { return [self compare:o] == NSOrderedAscending ? o : self; }
- (NSString *)descriptionWithLocale:(id)l { return [self description]; }
@end

/* ======================================================================= date formatters (Unicode date patterns) */
@implementation NSFormatter
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)stringForObjectValue:(id)o { return [o description]; }
- (BOOL)getObjectValue:(id *)obj forString:(NSString *)s errorDescription:(NSString **)e { if (obj) *obj = s; return YES; }
@end
static NSString *format_date(NSString *fmt, NSDate *date, NSTimeZone *tz, NSCalendar *cal) {
    mw_fields f = fields_of(cal, date, tz); NSMutableString *out = [NSMutableString string];
    NSUInteger n; unichar *u = mw_chars(fmt, &n);
    for (NSUInteger i = 0; i < n;) {
        unichar c = u[i];
        if (c == '\'') { /* quoted literal; '' is a quote */
            i++; if (i < n && u[i] == '\'') { [out appendString:@"'"]; i++; continue; }
            while (i < n && u[i] != '\'') { [out appendString:[NSString stringWithCharacters:&u[i] length:1]]; i++; }
            i++; continue;
        }
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))) { [out appendString:[NSString stringWithCharacters:&c length:1]]; i++; continue; }
        NSUInteger k = 1; while (i + k < n && u[i + k] == c) k++;
        long off = (long)[tz secondsFromGMTForDate:date], ao = off < 0 ? -off : off;
        switch (c) {
        case 'y': case 'u': if (k == 2) [out appendFormat:@"%02ld", f.year % 100]; else [out appendFormat:@"%0*ld", (int)k, f.year]; break;
        case 'Y': [out appendFormat:@"%0*ld", (int)(k == 2 ? 2 : k), k == 2 ? f.yearForWeekOfYear % 100 : f.yearForWeekOfYear]; break;
        case 'M': case 'L':
            if (k >= 4) [out appendString:[cal monthSymbols][(NSUInteger)f.month - 1]];
            else if (k == 3) [out appendString:[cal shortMonthSymbols][(NSUInteger)f.month - 1]];
            else [out appendFormat:@"%0*ld", (int)k, f.month]; break;
        case 'd': [out appendFormat:@"%0*ld", (int)k, f.day]; break;
        case 'D': [out appendFormat:@"%0*ld", (int)k, days_from_civil(f.year, f.month, f.day) - days_from_civil(f.year, 1, 1) + 1]; break;
        case 'E': case 'e': case 'c':
            if (k >= 4) [out appendString:[cal weekdaySymbols][(NSUInteger)f.weekday - 1]];
            else if (k == 3 || c == 'E') [out appendString:[cal shortWeekdaySymbols][(NSUInteger)f.weekday - 1]];
            else [out appendFormat:@"%ld", f.weekday]; break;
        case 'a': [out appendString:f.hour < 12 ? @"AM" : @"PM"]; break;
        case 'H': [out appendFormat:@"%0*ld", (int)k, f.hour]; break;
        case 'k': [out appendFormat:@"%0*ld", (int)k, f.hour ? f.hour : 24]; break;
        case 'h': [out appendFormat:@"%0*ld", (int)k, f.hour % 12 ? f.hour % 12 : 12]; break;
        case 'K': [out appendFormat:@"%0*ld", (int)k, f.hour % 12]; break;
        case 'm': [out appendFormat:@"%0*ld", (int)k, f.minute]; break;
        case 's': [out appendFormat:@"%0*ld", (int)k, f.second]; break;
        case 'S': { long v = f.nanosecond; int digits = 9; while (digits > (int)k) { v /= 10; digits--; } [out appendFormat:@"%0*ld", (int)k, v]; break; }
        case 'G': [out appendString:f.era ? @"AD" : @"BC"]; break;
        case 'Q': case 'q': [out appendFormat:k >= 3 ? @"Q%ld" : @"%ld", f.quarter]; break;
        case 'w': [out appendFormat:@"%0*ld", (int)k, f.weekOfYear]; break;
        case 'W': [out appendFormat:@"%ld", f.weekOfMonth]; break;
        case 'Z': if (k == 4) { if (!off) [out appendString:@"GMT"]; else [out appendFormat:@"GMT%c%02ld:%02ld", off < 0 ? '-' : '+', ao / 3600, ao / 60 % 60]; }
                  else if (k == 5) { if (!off) [out appendString:@"Z"]; else [out appendFormat:@"%c%02ld:%02ld", off < 0 ? '-' : '+', ao / 3600, ao / 60 % 60]; }
                  else [out appendFormat:@"%c%02ld%02ld", off < 0 ? '-' : '+', ao / 3600, ao / 60 % 60]; break;
        case 'X': case 'x':
            if (!off && c == 'X') [out appendString:@"Z"];
            else if (k == 1) [out appendFormat:@"%c%02ld", off < 0 ? '-' : '+', ao / 3600];
            else if (k == 2 || k == 4) [out appendFormat:@"%c%02ld%02ld", off < 0 ? '-' : '+', ao / 3600, ao / 60 % 60];
            else [out appendFormat:@"%c%02ld:%02ld", off < 0 ? '-' : '+', ao / 3600, ao / 60 % 60]; break;
        case 'z': case 'v': case 'V': case 'O': [out appendString:k >= 4 ? [tz name] : [tz abbreviation] ? [tz abbreviation] : [tz name]]; break;
        default: break;
        }
        i += k;
    }
    free(u);
    return out;
}
static NSDate *parse_date(NSString *fmt, NSString *str, NSTimeZone *tz, NSCalendar *cal) {
    NSUInteger n, m; unichar *u = mw_chars(fmt, &n), *s = mw_chars(str, &m); NSUInteger p = 0;
    long y = 2000, mo = 1, d = 1, h = 0, mi = 0, sec = 0, ns = 0; BOOL pm = NO, ampm = NO, haveOff = NO; long off = 0; BOOL ok = YES;
    for (NSUInteger i = 0; i < n && ok;) {
        unichar c = u[i];
        if (c == '\'') { i++; while (i < n && u[i] != '\'') { if (p >= m || s[p] != u[i]) ok = NO; p++; i++; } i++; continue; }
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))) { if (p >= m || s[p] != c) ok = NO; p++; i++; continue; }
        NSUInteger k = 1; while (i + k < n && u[i + k] == c) k++;
        long v = 0; NSUInteger digits = 0;
        #define NUM(maxd) do { v = 0; digits = 0; BOOL neg = NO; if (c == 'y' && p < m && s[p] == '-') { neg = YES; p++; } \
            while (p < m && s[p] >= '0' && s[p] <= '9' && digits < (maxd)) { v = v * 10 + (s[p++] - '0'); digits++; } if (!digits) ok = NO; if (neg) v = -v; } while (0)
        switch (c) {
        case 'y': case 'u': case 'Y': NUM(k == 2 ? 2 : 9); y = k == 2 && digits == 2 ? 2000 + v : v; break;
        case 'M': case 'L':
            if (k >= 3) { NSArray *names = k >= 4 ? [cal monthSymbols] : [cal shortMonthSymbols]; BOOL found = NO;
                for (NSUInteger j = 0; j < 12 && !found; j++) { NSString *nm = names[j]; NSUInteger l = [nm length];
                    if (p + l <= m && [[NSString stringWithCharacters:s + p length:l] caseInsensitiveCompare:nm] == NSOrderedSame) { mo = (long)j + 1; p += l; found = YES; } }
                if (!found) ok = NO; }
            else { NUM(2); mo = v; } break;
        case 'd': NUM(2); d = v; break;
        case 'H': case 'k': NUM(2); h = v; break;
        case 'h': case 'K': NUM(2); h = v; ampm = YES; break;
        case 'm': NUM(2); mi = v; break;
        case 's': NUM(2); sec = v; break;
        case 'S': NUM(9); ns = v; while (digits < 9) { ns *= 10; digits++; } break;
        case 'a': if (p + 2 <= m) { pm = s[p] == 'P' || s[p] == 'p'; p += 2; ampm = YES; } else ok = NO; break;
        case 'E': case 'e': case 'c': while (p < m && ((s[p] >= 'a' && s[p] <= 'z') || (s[p] >= 'A' && s[p] <= 'Z'))) p++; break;
        case 'Z': case 'X': case 'x': case 'z': case 'O': {
            if (p < m && s[p] == 'Z') { p++; haveOff = YES; off = 0; break; }
            if (p + 3 <= m && (s[p] == 'G' || s[p] == 'U')) p += 3; /* GMT / UTC */
            if (p < m && (s[p] == '+' || s[p] == '-')) {
                int sign = s[p++] == '-' ? -1 : 1; long hh = 0, mm = 0; int dg = 0;
                while (p < m && isdigit(s[p]) && dg < 2) { hh = hh * 10 + (s[p++] - '0'); dg++; }
                if (p < m && s[p] == ':') p++;
                dg = 0; while (p < m && isdigit(s[p]) && dg < 2) { mm = mm * 10 + (s[p++] - '0'); dg++; }
                haveOff = YES; off = sign * (hh * 3600 + mm * 60);
            } else haveOff = YES;
            break;
        }
        default: break;
        }
        i += k;
    }
    BOOL full = ok && p == m;
    free(u); free(s);
    if (!full) return nil;
    if (ampm) { h %= 12; if (pm) h += 12; }
    if (haveOff) return date_of(1, y, mo, d, h, mi, sec, ns, [NSTimeZone timeZoneForSecondsFromGMT:off]);
    return date_of(1, y, mo, d, h, mi, sec, ns, tz);
}
@implementation NSDateFormatter { NSString *_fmt; NSDateFormatterStyle _ds, _ts; NSLocale *_loc; NSTimeZone *_tz; NSCalendar *_cal; NSDate *_two, *_def; BOOL _lenient, _rel, _gen; }
/* the calendar's names (ponytail: English for every locale, like the styles below) */
#define SYM(n) - (NSArray *)n { return [(_cal ?: [NSCalendar currentCalendar]) n]; } - (void)set##n:(NSArray *)a { }
SYM(monthSymbols) SYM(shortMonthSymbols) SYM(veryShortMonthSymbols) SYM(standaloneMonthSymbols) SYM(shortStandaloneMonthSymbols)
SYM(veryShortStandaloneMonthSymbols) SYM(weekdaySymbols) SYM(shortWeekdaySymbols) SYM(veryShortWeekdaySymbols) SYM(standaloneWeekdaySymbols)
SYM(shortStandaloneWeekdaySymbols) SYM(veryShortStandaloneWeekdaySymbols) SYM(eraSymbols) SYM(longEraSymbols) SYM(quarterSymbols) SYM(shortQuarterSymbols)
#undef SYM
- (NSString *)AMSymbol { return @"AM"; } - (NSString *)PMSymbol { return @"PM"; }
- (NSInteger)formattingContext { return 0; } - (void)setFormattingContext:(NSInteger)c { }
- (void)dealloc { [_fmt release]; [_loc release]; [_tz release]; [_cal release]; [_two release]; [_def release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSDateFormatter *f = [[NSDateFormatter alloc] init]; [f setDateFormat:_fmt]; [f setLocale:_loc]; [f setTimeZone:_tz]; f->_ds = _ds; f->_ts = _ts; return f; }
static NSString *style_format(NSDateFormatterStyle ds, NSDateFormatterStyle ts) {
    static NSString *const d[] = {@"", @"M/d/yy", @"MMM d, y", @"MMMM d, y", @"EEEE, MMMM d, y"};
    static NSString *const t[] = {@"", @"h:mm a", @"h:mm:ss a", @"h:mm:ss a z", @"h:mm:ss a zzzz"};
    if (ds && ts) return [NSString stringWithFormat:@"%@, %@", d[ds], t[ts]];
    return ds ? d[ds] : t[ts];
}
- (NSString *)dateFormat { return _fmt ? _fmt : style_format(_ds, _ts); }
- (void)setDateFormat:(NSString *)f { [_fmt release]; _fmt = [f copy]; }
- (NSDateFormatterStyle)dateStyle { return _ds; } - (void)setDateStyle:(NSDateFormatterStyle)s { _ds = s; [_fmt release]; _fmt = nil; }
- (NSDateFormatterStyle)timeStyle { return _ts; } - (void)setTimeStyle:(NSDateFormatterStyle)s { _ts = s; [_fmt release]; _fmt = nil; }
- (NSLocale *)locale { return _loc ? _loc : [NSLocale currentLocale]; } - (void)setLocale:(NSLocale *)l { [_loc release]; _loc = [l retain]; }
- (NSTimeZone *)timeZone { return _tz ? _tz : [NSTimeZone defaultTimeZone]; } - (void)setTimeZone:(NSTimeZone *)t { [_tz release]; _tz = [t retain]; }
- (NSCalendar *)calendar { if (!_cal) _cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]; return _cal; }
- (void)setCalendar:(NSCalendar *)c { [_cal release]; _cal = [c copy]; }
- (BOOL)generatesCalendarDates { return _gen; } - (void)setGeneratesCalendarDates:(BOOL)b { _gen = b; }
- (BOOL)lenient { return _lenient; } - (void)setLenient:(BOOL)b { _lenient = b; }
- (BOOL)doesRelativeDateFormatting { return _rel; } - (void)setDoesRelativeDateFormatting:(BOOL)b { _rel = b; }
- (NSDate *)twoDigitStartDate { return _two; } - (void)setTwoDigitStartDate:(NSDate *)d { [_two release]; _two = [d copy]; }
- (NSDate *)defaultDate { return _def; } - (void)setDefaultDate:(NSDate *)d { [_def release]; _def = [d copy]; }
- (NSString *)stringFromDate:(NSDate *)d { return d ? format_date([self dateFormat], d, [self timeZone], [self calendar]) : nil; }
- (NSDate *)dateFromString:(NSString *)s { return s ? parse_date([self dateFormat], s, [self timeZone], [self calendar]) : nil; }
- (NSString *)stringForObjectValue:(id)o { return [o isKindOfClass:[NSDate class]] ? [self stringFromDate:o] : nil; }
+ (NSString *)localizedStringFromDate:(NSDate *)d dateStyle:(NSDateFormatterStyle)ds timeStyle:(NSDateFormatterStyle)ts {
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease]; [f setDateStyle:ds]; [f setTimeStyle:ts]; return [f stringFromDate:d];
}
/* a skeleton ("dMMM", "EEEEdMMMMy", "jmm") to a pattern for the locale. ponytail: two orders (US "MMM d, y" and the
   day-first one most locales use) and 12/24 h by locale; the full CLDR tables when an app needs them */
+ (NSString *)dateFormatFromTemplate:(NSString *)t options:(NSUInteger)o locale:(NSLocale *)l {
    NSString *loc = [(l ?: [NSLocale currentLocale]) localeIdentifier] ?: @"";
    BOOL us = [loc hasPrefix:@"en_US"] || [loc isEqualToString:@"en"], h12 = us || [loc hasPrefix:@"en_AU"] || [loc hasPrefix:@"en_CA"];
    NSMutableDictionary *tok = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < t.length;) {
        unichar c = [t characterAtIndex:i]; NSUInteger j = i;
        while (j < t.length && [t characterAtIndex:j] == c) j++;
        tok[[NSString stringWithCharacters:&c length:1]] = [t substringWithRange:NSMakeRange(i, j - i)];
        i = j;
    }
    NSMutableArray *date = [NSMutableArray array];
    NSString *E = tok[@"E"] ?: tok[@"c"], *d = tok[@"d"], *M = tok[@"M"] ?: tok[@"L"], *y = tok[@"y"];
    if (us) { if (M) [date addObject:M]; if (d) [date addObject:d]; }
    else { if (d) [date addObject:d]; if (M) [date addObject:M]; }
    NSString *ds = [date componentsJoinedByString:(M && M.length <= 2 ? (us ? @"/" : @"/") : @" ")];
    if (y) ds = ds.length ? [NSString stringWithFormat:(us && M.length > 2 ? @"%@, %@" : M.length <= 2 ? @"%@/%@" : @"%@ %@"), ds, y] : y;
    if (E) ds = ds.length ? [NSString stringWithFormat:@"%@, %@", E, ds] : E;
    NSString *hour = tok[@"j"] ?: tok[@"h"] ?: tok[@"H"] ?: tok[@"k"] ?: tok[@"K"], *time = nil;
    if (hour) {
        BOOL twelve = tok[@"h"] || tok[@"K"] || (tok[@"j"] && h12);
        NSString *hp = twelve ? (hour.length > 1 ? @"hh" : @"h") : (hour.length > 1 ? @"HH" : @"H");
        time = tok[@"m"] ? [NSString stringWithFormat:@"%@:%@", hp, tok[@"m"]] : hp;
        if (tok[@"s"]) time = [time stringByAppendingFormat:@":%@", tok[@"s"]];
        if (twelve) time = [time stringByAppendingString:@" a"];
    } else if (tok[@"m"]) time = tok[@"s"] ? [NSString stringWithFormat:@"%@:%@", tok[@"m"], tok[@"s"]] : tok[@"m"];
    if (ds.length && time) return [NSString stringWithFormat:@"%@ %@", ds, time];
    return ds.length ? ds : time ?: t;
}
- (void)setLocalizedDateFormatFromTemplate:(NSString *)t { [self setDateFormat:[NSDateFormatter dateFormatFromTemplate:t options:0 locale:_loc]]; }
@end
@implementation NSISO8601DateFormatter { NSTimeZone *_tz; NSISO8601DateFormatOptions _opt; }
- (instancetype)init { _opt = NSISO8601DateFormatWithInternetDateTime; _tz = [[NSTimeZone timeZoneForSecondsFromGMT:0] retain]; return self; }
- (void)dealloc { [_tz release]; [super dealloc]; }
- (NSTimeZone *)timeZone { return _tz; } - (void)setTimeZone:(NSTimeZone *)t { [_tz release]; _tz = [(t ? t : [NSTimeZone timeZoneForSecondsFromGMT:0]) retain]; }
- (NSISO8601DateFormatOptions)formatOptions { return _opt; } - (void)setFormatOptions:(NSISO8601DateFormatOptions)o { _opt = o; }
static NSString *iso_pattern(NSISO8601DateFormatOptions o) {
    NSMutableString *p = [NSMutableString string]; BOOL dash = (o & NSISO8601DateFormatWithDashSeparatorInDate) != 0, colon = (o & NSISO8601DateFormatWithColonSeparatorInTime) != 0;
    if (o & NSISO8601DateFormatWithYear) [p appendString:(o & NSISO8601DateFormatWithWeekOfYear) ? @"YYYY" : @"yyyy"];
    if (o & NSISO8601DateFormatWithMonth) [p appendString:dash ? @"-MM" : @"MM"];
    if (o & NSISO8601DateFormatWithWeekOfYear) [p appendString:dash ? @"-'W'ww" : @"'W'ww"];
    if (o & NSISO8601DateFormatWithDay) [p appendString:(o & NSISO8601DateFormatWithWeekOfYear) ? (dash ? @"-ee" : @"ee") : (o & NSISO8601DateFormatWithMonth) ? (dash ? @"-dd" : @"dd") : (dash ? @"-DDD" : @"DDD")];
    if ((o & NSISO8601DateFormatWithTime) && [p length]) [p appendString:(o & NSISO8601DateFormatWithSpaceBetweenDateAndTime) ? @" " : @"'T'"];
    if (o & NSISO8601DateFormatWithTime) [p appendString:colon ? @"HH:mm:ss" : @"HHmmss"];
    if ((o & NSISO8601DateFormatWithTime) && (o & NSISO8601DateFormatWithFractionalSeconds)) [p appendString:@".SSS"];
    if (o & NSISO8601DateFormatWithTimeZone) [p appendString:(o & NSISO8601DateFormatWithColonSeparatorInTimeZone) ? @"XXXXX" : @"XXXX"];
    return p;
}
- (NSString *)stringFromDate:(NSDate *)d { return [NSISO8601DateFormatter stringFromDate:d timeZone:_tz formatOptions:_opt]; }
- (NSDate *)dateFromString:(NSString *)s {
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierISO8601];
    return parse_date(iso_pattern(_opt), s, _tz, cal);
}
- (NSString *)stringForObjectValue:(id)o { return [o isKindOfClass:[NSDate class]] ? [self stringFromDate:o] : nil; }
+ (NSString *)stringFromDate:(NSDate *)d timeZone:(NSTimeZone *)tz formatOptions:(NSISO8601DateFormatOptions)o {
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierISO8601];
    return format_date(iso_pattern(o), d, tz, cal);
}
@end
