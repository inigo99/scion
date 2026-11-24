/* eventkit.m — EventKit (aliased to Foundation by the loader): scion's own reminders store, a plist in
 * ~/Library/Calendars shared by every app. Access is granted. Events are not kept: their calendar is empty.
 * ponytail: events and a link to the system's own calendars (Outlook/ICS) when an app needs them. */
#import <Foundation/Foundation.h>
#import <EventKit/EventKit.h>
void dispatch_async(void *q, void (^b)(void));   /* libdispatch (libSystem) */
void *dispatch_get_global_queue(long p, unsigned long f);
extern struct dqueue _dispatch_main_q;
#define dispatch_get_main_queue() ((void *)&_dispatch_main_q)
typedef long dispatch_once_t; void dispatch_once(dispatch_once_t *o, void (^b)(void));

NSString *const EKEventStoreChangedNotification = @"EKEventStoreChangedNotification";
NSString *const EKErrorDomain = @"EKErrorDomain";

/* ---------------------------------------------------------------- the store: lists and reminders in a plist
 * (~/Library/Calendars/scion.plist). Events are not kept (an empty calendar). One lock guards it. */
@interface EKCalendar () { @public NSString *_mwId; double _rgb[3]; } @end
@interface EKCalendarItem () { @public NSString *_mwId; } @end
@interface EKAlarm : EKObject { @public NSDate *_abs; NSTimeInterval _rel; } @end
@interface EKRecurrenceEnd : NSObject { @public NSDate *_date; NSUInteger _count; } @end
@interface EKRecurrenceDayOfWeek : NSObject { @public NSInteger _day, _week; } @end
@interface EKRecurrenceRule : EKObject {
    @public NSInteger _freq, _interval; EKRecurrenceEnd *_end; NSArray *_dow, *_dom, *_moy, *_woy, *_doy, *_pos;
} @end
static NSMutableArray *g_cals, *g_rems;
static EKSource *g_source;
static NSLock *g_lock;
static NSString *store_path(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Calendars/scion.plist"]; }
static NSString *new_id(void) { return [[NSUUID UUID] UUIDString]; }
static NSDictionary *comps_plist(NSDateComponents *c) {
    if (!c) return nil;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (c.year != NSDateComponentUndefined) d[@"y"] = @(c.year);
    if (c.month != NSDateComponentUndefined) d[@"m"] = @(c.month);
    if (c.day != NSDateComponentUndefined) d[@"d"] = @(c.day);
    if (c.hour != NSDateComponentUndefined) d[@"h"] = @(c.hour);
    if (c.minute != NSDateComponentUndefined) d[@"mi"] = @(c.minute);
    return d;
}
static NSDateComponents *plist_comps(NSDictionary *d) {
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease];
    if (d[@"y"]) c.year = [d[@"y"] integerValue];
    if (d[@"m"]) c.month = [d[@"m"] integerValue];
    if (d[@"d"]) c.day = [d[@"d"] integerValue];
    if (d[@"h"]) c.hour = [d[@"h"] integerValue];
    if (d[@"mi"]) c.minute = [d[@"mi"] integerValue];
    c.calendar = [NSCalendar currentCalendar];
    return c;
}
static EKCalendar *cal_with_id(NSString *i) { for (EKCalendar *c in g_cals) if ([c->_mwId isEqualToString:i]) return c; return nil; }
static void store_save(void) {   /* with g_lock held */
    NSMutableArray *cals = [NSMutableArray array], *rems = [NSMutableArray array];
    for (EKCalendar *c in g_cals) [cals addObject:@{@"id": c->_mwId, @"title": c.title ?: @"", @"rgb": @[@(c->_rgb[0]), @(c->_rgb[1]), @(c->_rgb[2])]}];
    for (EKReminder *r in g_rems) {
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:@{@"id": r->_mwId, @"title": r.title ?: @"", @"priority": @(r.priority), @"done": @(r.completed)}];
        if (r.calendar) d[@"cal"] = r.calendar->_mwId;
        if (r.notes) d[@"notes"] = r.notes;
        if (r.URL) d[@"url"] = r.URL.absoluteString;
        if (r.completionDate) d[@"doneAt"] = r.completionDate;
        if (r.creationDate) d[@"created"] = r.creationDate;
        if (r.lastModifiedDate) d[@"modified"] = r.lastModifiedDate;
        if (r.dueDateComponents) d[@"due"] = comps_plist(r.dueDateComponents);
        if (r.startDateComponents) d[@"start"] = comps_plist(r.startDateComponents);
        NSMutableArray *al = [NSMutableArray array];
        for (EKAlarm *a in r.alarms) [al addObject:a->_abs ? @{@"at": a->_abs} : @{@"rel": @(a->_rel)}];
        if (al.count) d[@"alarms"] = al;
        EKRecurrenceRule *rr = r.recurrenceRules.firstObject;   /* ponytail: the frequency, interval and end of the first rule */
        if (rr) { NSMutableDictionary *x = [NSMutableDictionary dictionaryWithDictionary:@{@"freq": @(rr->_freq), @"interval": @(rr->_interval)}];
            if (rr->_end && rr->_end->_date) x[@"until"] = rr->_end->_date; if (rr->_end && rr->_end->_count) x[@"count"] = @(rr->_end->_count);
            d[@"repeat"] = x; }
        [rems addObject:d];
    }
    NSString *p = store_path();
    [[NSFileManager defaultManager] createDirectoryAtPath:[p stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
    [@{@"calendars": cals, @"reminders": rems} writeToFile:p atomically:YES];
}
static void store_load(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_lock = [[NSLock alloc] init]; g_cals = [[NSMutableArray alloc] init]; g_rems = [[NSMutableArray alloc] init];
        g_source = [[EKSource alloc] init];
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:store_path()];
        for (NSDictionary *c in d[@"calendars"]) {
            EKCalendar *k = [[EKCalendar alloc] init];
            k->_mwId = [c[@"id"] copy]; k.title = c[@"title"];
            NSArray *rgb = c[@"rgb"]; for (int i = 0; i < 3 && i < (int)rgb.count; i++) k->_rgb[i] = [rgb[i] doubleValue];
            [g_cals addObject:k]; [k release];
        }
        if (!g_cals.count) {   /* first run: one list */
            EKCalendar *k = [[EKCalendar alloc] init];
            k->_mwId = [new_id() copy]; k.title = @"Recordatorios"; k->_rgb[0] = 1; k->_rgb[1] = 0.58; k->_rgb[2] = 0;
            [g_cals addObject:k]; [k release];
        }
        for (NSDictionary *x in d[@"reminders"]) {
            EKReminder *r = [[EKReminder alloc] init];
            r->_mwId = [x[@"id"] copy]; r.title = x[@"title"]; r.notes = x[@"notes"];
            r.priority = [x[@"priority"] unsignedIntegerValue]; r.completed = [x[@"done"] boolValue]; r.completionDate = x[@"doneAt"];
            if (x[@"url"]) r.URL = [NSURL URLWithString:x[@"url"]];
            r.creationDate = x[@"created"]; r.lastModifiedDate = x[@"modified"];
            r.dueDateComponents = plist_comps(x[@"due"]); r.startDateComponents = plist_comps(x[@"start"]);
            r.calendar = cal_with_id(x[@"cal"]) ?: g_cals[0];
            for (NSDictionary *a in x[@"alarms"]) [r addAlarm:a[@"at"] ? [EKAlarm alarmWithAbsoluteDate:a[@"at"]] : [EKAlarm alarmWithRelativeOffset:[a[@"rel"] doubleValue]]];
            NSDictionary *rp = x[@"repeat"];
            if (rp) {
                EKRecurrenceEnd *e = rp[@"until"] ? [EKRecurrenceEnd recurrenceEndWithEndDate:rp[@"until"]] : rp[@"count"] ? [EKRecurrenceEnd recurrenceEndWithOccurrenceCount:[rp[@"count"] unsignedIntegerValue]] : nil;
                [r addRecurrenceRule:[[[EKRecurrenceRule alloc] initRecurrenceWithFrequency:[rp[@"freq"] integerValue] interval:[rp[@"interval"] integerValue] end:e] autorelease]];
            }
            [g_rems addObject:r]; [r release];
        }
    });
}
static void store_changed(void) {
    store_save();
    dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:EKEventStoreChangedNotification object:nil]; });
}
static void answer(EKEventStoreRequestAccessCompletionHandler c) {
    if (!c) return;
    c = [[c copy] autorelease];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{ c(YES, nil); });   /* like EventKit: on another queue */
}
static NSDate *comps_date(NSDateComponents *c) {
    if (!c) return nil;
    NSDateComponents *x = [[c copy] autorelease];
    if (x.hour == NSDateComponentUndefined) x.hour = 0;
    return [[NSCalendar currentCalendar] dateFromComponents:x];
}

@implementation EKObject
- (BOOL)hasChanges { return NO; } - (BOOL)isNew { return YES; }
- (void)reset {} - (void)rollback {} - (BOOL)refresh { return YES; }
@end
@implementation EKSource
- (NSString *)sourceIdentifier { return @"scion"; } - (NSString *)title { return @"scion"; } - (NSInteger)sourceType { return 0; /* local */ }
- (NSSet *)calendarsForEntityType:(EKEntityType)t { store_load(); return t == EKEntityTypeReminder ? [NSSet setWithArray:g_cals] : [NSSet set]; }
@end
@implementation EKCalendar
+ (EKCalendar *)calendarForEntityType:(EKEntityType)t eventStore:(id)s { EKCalendar *c = [[[self alloc] init] autorelease]; c->_rgb[2] = 1; return c; }
- (NSString *)calendarIdentifier { if (!_mwId) _mwId = [new_id() copy]; return _mwId; }
- (EKSource *)source { store_load(); return g_source; }
- (id)color { return [NSClassFromString(@"NSColor") colorWithSRGBRed:_rgb[0] green:_rgb[1] blue:_rgb[2] alpha:1]; }
- (void)setColor:(id)c {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    id s = [c respondsToSelector:@selector(colorUsingColorSpace:)] ? [c colorUsingColorSpace:[NSClassFromString(@"NSColorSpace") sRGBColorSpace]] : c;
    if ([s respondsToSelector:@selector(getRed:green:blue:alpha:)]) [s getRed:&r green:&g blue:&b alpha:&a];
    _rgb[0] = r; _rgb[1] = g; _rgb[2] = b;
}
- (CGColorRef)CGColor { return (CGColorRef)[[self color] CGColor]; }
- (BOOL)allowsContentModifications { return YES; } - (BOOL)isSubscribed { return NO; } - (BOOL)isImmutable { return NO; }
- (NSInteger)type { return 0; } - (EKEntityMask)allowedEntityTypes { return EKEntityMaskReminder; }
@end
@implementation EKCalendarItem
- (NSString *)calendarItemIdentifier { if (!_mwId) _mwId = [new_id() copy]; return _mwId; }
- (NSString *)calendarItemExternalIdentifier { return self.calendarItemIdentifier; }
- (BOOL)hasAlarms { return self.alarms.count > 0; } - (BOOL)hasRecurrenceRules { return self.recurrenceRules.count > 0; } - (BOOL)hasAttendees { return NO; } - (BOOL)hasNotes { return self.notes.length > 0; }
- (NSArray *)attendees { return nil; }
@end
@implementation EKEvent
+ (EKEvent *)eventWithEventStore:(id)s { return [[[self alloc] init] autorelease]; }
- (NSString *)eventIdentifier { return self.calendarItemIdentifier; }
- (NSInteger)status { return 0; } - (NSInteger)availability { return 0; } - (BOOL)isDetached { return NO; }
- (NSComparisonResult)compareStartDateWithEvent:(EKEvent *)o { return [self.startDate compare:o.startDate]; }
@end
@implementation EKReminder
+ (EKReminder *)reminderWithEventStore:(id)s { EKReminder *r = [[[self alloc] init] autorelease]; r.creationDate = [NSDate date]; return r; }
- (void)setCompleted:(BOOL)c { _completed = c; if (c && !self.completionDate) self.completionDate = [NSDate date]; if (!c) self.completionDate = nil; }
@end
@implementation EKEventStore
+ (EKAuthorizationStatus)authorizationStatusForEntityType:(EKEntityType)t { return EKAuthorizationStatusFullAccess; }
- (void)requestAccessToEntityType:(EKEntityType)t completion:(EKEventStoreRequestAccessCompletionHandler)c { answer(c); }
- (void)requestFullAccessToEventsWithCompletion:(EKEventStoreRequestAccessCompletionHandler)c { answer(c); }
- (void)requestFullAccessToRemindersWithCompletion:(EKEventStoreRequestAccessCompletionHandler)c { answer(c); }
- (void)requestWriteOnlyAccessToEventsWithCompletion:(EKEventStoreRequestAccessCompletionHandler)c { answer(c); }
- (instancetype)init { if ((self = [super init])) store_load(); return self; }
- (instancetype)initWithAccessToEntityTypes:(EKEntityMask)m { return [self init]; }
- (instancetype)initWithSources:(NSArray *)s { return [self init]; }
- (NSArray *)sources { return @[g_source]; }
- (NSArray *)delegateSources { return @[]; }
- (NSString *)eventStoreIdentifier { return @"scion"; }
- (EKCalendar *)defaultCalendarForNewEvents { return nil; }
- (EKCalendar *)defaultCalendarForNewReminders { [g_lock lock]; EKCalendar *c = g_cals.count ? [[g_cals[0] retain] autorelease] : nil; [g_lock unlock]; return c; }
- (NSArray *)calendarsForEntityType:(EKEntityType)t { if (t != EKEntityTypeReminder) return @[]; [g_lock lock]; NSArray *a = [[g_cals copy] autorelease]; [g_lock unlock]; return a; }
- (NSArray *)calendars { return [self calendarsForEntityType:EKEntityTypeReminder]; }
- (EKCalendar *)calendarWithIdentifier:(NSString *)i { [g_lock lock]; EKCalendar *c = [[cal_with_id(i) retain] autorelease]; [g_lock unlock]; return c; }
- (id)calendarItemWithIdentifier:(NSString *)i {
    [g_lock lock]; EKReminder *f = nil;
    for (EKReminder *r in g_rems) if ([r->_mwId isEqualToString:i]) { f = [[r retain] autorelease]; break; }
    [g_lock unlock]; return f;
}
- (NSArray *)calendarItemsWithExternalIdentifier:(NSString *)i { id r = [self calendarItemWithIdentifier:i]; return r ? @[r] : @[]; }
- (EKEvent *)eventWithIdentifier:(NSString *)i { return nil; }
static BOOL in_cals(EKReminder *r, NSArray *c) { return !c || [c indexOfObjectPassingTest:^BOOL(id k, NSUInteger i, BOOL *s) { return [[k calendarIdentifier] isEqualToString:r.calendar.calendarIdentifier]; }] != NSNotFound; }
static BOOL in_range(NSDate *d, NSDate *s, NSDate *e) { if (!s && !e) return YES; if (!d) return NO; return (!s || [d compare:s] != NSOrderedAscending) && (!e || [d compare:e] == NSOrderedAscending); }
- (NSPredicate *)predicateForEventsWithStartDate:(NSDate *)s endDate:(NSDate *)e calendars:(NSArray *)c { return [NSPredicate predicateWithValue:NO]; }
- (NSPredicate *)predicateForRemindersInCalendars:(NSArray *)c {
    c = [[c copy] autorelease];
    return [NSPredicate predicateWithBlock:^BOOL(EKReminder *r, NSDictionary *b) { return in_cals(r, c); }];
}
- (NSPredicate *)predicateForIncompleteRemindersWithDueDateStarting:(NSDate *)s ending:(NSDate *)e calendars:(NSArray *)c {
    c = [[c copy] autorelease]; s = [[s copy] autorelease]; e = [[e copy] autorelease];
    return [NSPredicate predicateWithBlock:^BOOL(EKReminder *r, NSDictionary *b) { return !r.completed && in_cals(r, c) && in_range(comps_date(r.dueDateComponents), s, e); }];
}
- (NSPredicate *)predicateForCompletedRemindersWithCompletionDateStarting:(NSDate *)s ending:(NSDate *)e calendars:(NSArray *)c {
    c = [[c copy] autorelease]; s = [[s copy] autorelease]; e = [[e copy] autorelease];
    return [NSPredicate predicateWithBlock:^BOOL(EKReminder *r, NSDictionary *b) { return r.completed && in_cals(r, c) && in_range(r.completionDate, s, e); }];
}
- (NSArray *)eventsMatchingPredicate:(NSPredicate *)p { return @[]; }
- (void)enumerateEventsMatchingPredicate:(NSPredicate *)p usingBlock:(void (^)(EKEvent *, BOOL *))b {}
- (id)fetchRemindersMatchingPredicate:(NSPredicate *)p completion:(void (^)(NSArray *))c {
    if (c) {
        c = [[c copy] autorelease]; p = [[p retain] autorelease];
        [p retain];
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            [g_lock lock]; NSArray *all = [[g_rems copy] autorelease]; [g_lock unlock];
            NSMutableArray *out = [NSMutableArray array];
            for (EKReminder *r in all) if (!p || [p evaluateWithObject:r]) [out addObject:r];
            [p release];
            c(out);
        });
    }
    return [[[NSObject alloc] init] autorelease];
}
- (void)cancelFetchRequest:(id)r {}
- (BOOL)saveEvent:(EKEvent *)e span:(EKSpan)s commit:(BOOL)c error:(NSError **)err {
    if (err) *err = [NSError errorWithDomain:EKErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"scion does not store events"}];
    return NO;
}
- (BOOL)saveEvent:(EKEvent *)e span:(EKSpan)s error:(NSError **)err { return [self saveEvent:e span:s commit:YES error:err]; }
- (BOOL)removeEvent:(EKEvent *)e span:(EKSpan)s commit:(BOOL)c error:(NSError **)err { return [self saveEvent:e span:s commit:c error:err]; }
- (BOOL)removeEvent:(EKEvent *)e span:(EKSpan)s error:(NSError **)err { return [self removeEvent:e span:s commit:YES error:err]; }
- (BOOL)saveReminder:(EKReminder *)r commit:(BOOL)c error:(NSError **)err {
    [g_lock lock];
    if (!r.calendar) r.calendar = g_cals.count ? g_cals[0] : nil;
    if (!r.creationDate) r.creationDate = [NSDate date];
    r.lastModifiedDate = [NSDate date];
    [r calendarItemIdentifier];
    if ([g_rems indexOfObjectIdenticalTo:r] == NSNotFound) [g_rems addObject:r];
    store_changed();
    [g_lock unlock];
    return YES;
}
- (BOOL)removeReminder:(EKReminder *)r commit:(BOOL)c error:(NSError **)err {
    [g_lock lock]; [g_rems removeObjectIdenticalTo:r]; store_changed(); [g_lock unlock];
    return YES;
}
- (BOOL)saveCalendar:(EKCalendar *)cal commit:(BOOL)c error:(NSError **)err {
    [g_lock lock]; [cal calendarIdentifier]; if ([g_cals indexOfObjectIdenticalTo:cal] == NSNotFound) [g_cals addObject:cal]; store_changed(); [g_lock unlock];
    return YES;
}
- (BOOL)removeCalendar:(EKCalendar *)cal commit:(BOOL)c error:(NSError **)err {
    [g_lock lock];
    if (g_cals.count > 1) {
        [g_cals removeObjectIdenticalTo:cal];
        for (NSInteger i = (NSInteger)g_rems.count - 1; i >= 0; i--) if (((EKReminder *)g_rems[i]).calendar == cal) [g_rems removeObjectAtIndex:i];
        store_changed();
    }
    [g_lock unlock];
    return YES;
}
- (BOOL)commit:(NSError **)err { return YES; }
- (void)reset {}
- (void)refreshSourcesIfNecessary {}
@end
/* the other classes apps reference: alarms and recurrence rules keep what they are given */
@implementation EKAlarm
+ (id)alarmWithRelativeOffset:(NSTimeInterval)o { EKAlarm *a = [[[self alloc] init] autorelease]; a->_rel = o; return a; }
+ (id)alarmWithAbsoluteDate:(NSDate *)d { EKAlarm *a = [[[self alloc] init] autorelease]; a->_abs = [d copy]; return a; }
- (void)dealloc { [_abs release]; [super dealloc]; }
- (NSDate *)absoluteDate { return _abs; } - (void)setAbsoluteDate:(NSDate *)d { [_abs release]; _abs = [d copy]; }
- (NSTimeInterval)relativeOffset { return _rel; } - (void)setRelativeOffset:(NSTimeInterval)o { _rel = o; }
- (id)copyWithZone:(NSZone *)z { return [(_abs ? [EKAlarm alarmWithAbsoluteDate:_abs] : [EKAlarm alarmWithRelativeOffset:_rel]) retain]; }
@end
@implementation EKRecurrenceEnd
+ (id)recurrenceEndWithEndDate:(NSDate *)d { EKRecurrenceEnd *e = [[[self alloc] init] autorelease]; e->_date = [d copy]; return e; }
+ (id)recurrenceEndWithOccurrenceCount:(NSUInteger)n { EKRecurrenceEnd *e = [[[self alloc] init] autorelease]; e->_count = n; return e; }
- (void)dealloc { [_date release]; [super dealloc]; }
- (NSDate *)endDate { return _date; } - (NSUInteger)occurrenceCount { return _count; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
@end
@implementation EKRecurrenceDayOfWeek
+ (id)dayOfWeek:(NSInteger)d { return [self dayOfWeek:d weekNumber:0]; }
+ (id)dayOfWeek:(NSInteger)d weekNumber:(NSInteger)w { EKRecurrenceDayOfWeek *x = [[[self alloc] init] autorelease]; x->_day = d; x->_week = w; return x; }
- (NSInteger)dayOfTheWeek { return _day; } - (NSInteger)weekNumber { return _week; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
@end
@implementation EKRecurrenceRule
- (id)initRecurrenceWithFrequency:(NSInteger)f interval:(NSInteger)i end:(EKRecurrenceEnd *)e {
    return [self initRecurrenceWithFrequency:f interval:i daysOfTheWeek:nil daysOfTheMonth:nil monthsOfTheYear:nil weeksOfTheYear:nil daysOfTheYear:nil setPositions:nil end:e];
}
- (id)initRecurrenceWithFrequency:(NSInteger)f interval:(NSInteger)i daysOfTheWeek:(NSArray *)dw daysOfTheMonth:(NSArray *)dm monthsOfTheYear:(NSArray *)my
                  weeksOfTheYear:(NSArray *)wy daysOfTheYear:(NSArray *)dy setPositions:(NSArray *)p end:(EKRecurrenceEnd *)e {
    if ((self = [super init])) {
        _freq = f; _interval = i > 0 ? i : 1; _end = [e retain];
        _dow = [dw copy]; _dom = [dm copy]; _moy = [my copy]; _woy = [wy copy]; _doy = [dy copy]; _pos = [p copy];
    }
    return self;
}
- (void)dealloc { [_end release]; [_dow release]; [_dom release]; [_moy release]; [_woy release]; [_doy release]; [_pos release]; [super dealloc]; }
- (NSInteger)frequency { return _freq; } - (NSInteger)interval { return _interval; }
- (EKRecurrenceEnd *)recurrenceEnd { return _end; } - (void)setRecurrenceEnd:(EKRecurrenceEnd *)e { [e retain]; [_end release]; _end = e; }
- (NSArray *)daysOfTheWeek { return _dow; } - (NSArray *)daysOfTheMonth { return _dom; } - (NSArray *)monthsOfTheYear { return _moy; }
- (NSArray *)weeksOfTheYear { return _woy; } - (NSArray *)daysOfTheYear { return _doy; } - (NSArray *)setPositions { return _pos; }
- (NSString *)calendarIdentifier { return @"gregorian"; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
@end
@implementation EKCalendarItem (MWAlarmsAndRules)
- (void)addAlarm:(EKAlarm *)a { if (a) self.alarms = [(self.alarms ?: @[]) arrayByAddingObject:a]; }
- (void)removeAlarm:(EKAlarm *)a { NSMutableArray *m = [[self.alarms mutableCopy] autorelease]; [m removeObjectIdenticalTo:a]; self.alarms = m; }
- (void)addRecurrenceRule:(EKRecurrenceRule *)r { if (r) self.recurrenceRules = [(self.recurrenceRules ?: @[]) arrayByAddingObject:r]; }
- (void)removeRecurrenceRule:(EKRecurrenceRule *)r { NSMutableArray *m = [[self.recurrenceRules mutableCopy] autorelease]; [m removeObjectIdenticalTo:r]; self.recurrenceRules = m; }
@end
@interface EKParticipant : EKObject @end @implementation EKParticipant @end
@interface EKStructuredLocation : EKObject @end @implementation EKStructuredLocation + (id)locationWithTitle:(NSString *)t { return [[[self alloc] init] autorelease]; } @end
@interface EKVirtualConferenceDescriptor : NSObject @end @implementation EKVirtualConferenceDescriptor @end
