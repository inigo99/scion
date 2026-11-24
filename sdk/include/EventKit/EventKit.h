/* EventKit: calendars and reminders. scion keeps reminders in its own store; events are not kept (src/foundation/eventkit.m). */
#pragma once
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSUInteger, EKEntityType) { EKEntityTypeEvent, EKEntityTypeReminder };
typedef NS_OPTIONS(NSUInteger, EKEntityMask) { EKEntityMaskEvent = 1, EKEntityMaskReminder = 2 };
typedef NS_ENUM(NSInteger, EKAuthorizationStatus) { EKAuthorizationStatusNotDetermined = 0, EKAuthorizationStatusRestricted, EKAuthorizationStatusDenied,
    EKAuthorizationStatusFullAccess, EKAuthorizationStatusWriteOnly, EKAuthorizationStatusAuthorized = EKAuthorizationStatusFullAccess };
typedef NS_ENUM(NSInteger, EKSpan) { EKSpanThisEvent, EKSpanFutureEvents };
typedef void (^EKEventStoreRequestAccessCompletionHandler)(BOOL granted, NSError *_Nullable error);
FOUNDATION_EXPORT NSString *const EKEventStoreChangedNotification;
FOUNDATION_EXPORT NSString *const EKErrorDomain;
@class EKCalendar, EKEvent, EKReminder, EKSource;
@interface EKObject : NSObject
@property(readonly) BOOL hasChanges, isNew;
- (void)reset; - (void)rollback; - (BOOL)refresh;
@end
@interface EKSource : EKObject
@property(readonly) NSString *sourceIdentifier, *title;
@property(readonly) NSInteger sourceType;
- (NSSet<EKCalendar *> *)calendarsForEntityType:(EKEntityType)t;
@end
@interface EKCalendar : EKObject
+ (EKCalendar *)calendarForEntityType:(EKEntityType)t eventStore:(id)s;
@property(copy) NSString *title; @property(readonly) NSString *calendarIdentifier;
@property(retain, nullable) EKSource *source; @property(retain, nullable) id color; @property(nullable) CGColorRef CGColor;
@property(readonly) BOOL allowsContentModifications, isSubscribed, isImmutable;
@property(readonly) NSInteger type; @property(readonly) EKEntityMask allowedEntityTypes;
@end
@interface EKCalendarItem : EKObject
@property(retain, nullable) EKCalendar *calendar; @property(copy, nullable) NSString *title, *location, *notes;
@property(copy, nullable) NSURL *URL; @property(readonly) NSString *calendarItemIdentifier;
@property(readonly) BOOL hasAlarms, hasRecurrenceRules, hasAttendees, hasNotes;
@property(copy, nullable) NSArray *alarms, *recurrenceRules; @property(readonly, nullable) NSArray *attendees;
@property(copy, nullable) NSTimeZone *timeZone;
@property(copy, nullable) NSDate *creationDate, *lastModifiedDate;
@end
@interface EKEvent : EKCalendarItem
+ (EKEvent *)eventWithEventStore:(id)s;
@property(copy) NSDate *startDate, *endDate; @property(getter=isAllDay) BOOL allDay;
@property(readonly) NSString *eventIdentifier; @property(readonly) NSInteger status, availability;
@property(readonly) BOOL isDetached;
@end
@interface EKReminder : EKCalendarItem
+ (EKReminder *)reminderWithEventStore:(id)s;
@property(copy, nullable) NSDateComponents *startDateComponents, *dueDateComponents;
@property(getter=isCompleted) BOOL completed; @property(copy, nullable) NSDate *completionDate; @property NSUInteger priority;
@end
@interface EKEventStore : NSObject
+ (EKAuthorizationStatus)authorizationStatusForEntityType:(EKEntityType)t;
- (void)requestAccessToEntityType:(EKEntityType)t completion:(EKEventStoreRequestAccessCompletionHandler)c;
- (void)requestFullAccessToEventsWithCompletion:(EKEventStoreRequestAccessCompletionHandler)c;
- (void)requestFullAccessToRemindersWithCompletion:(EKEventStoreRequestAccessCompletionHandler)c;
- (void)requestWriteOnlyAccessToEventsWithCompletion:(EKEventStoreRequestAccessCompletionHandler)c;
@property(readonly) NSArray<EKSource *> *sources; @property(readonly) NSString *eventStoreIdentifier;
@property(readonly, nullable) EKCalendar *defaultCalendarForNewEvents, *defaultCalendarForNewReminders;
- (NSArray<EKCalendar *> *)calendarsForEntityType:(EKEntityType)t;
- (nullable EKCalendar *)calendarWithIdentifier:(NSString *)i;
- (nullable id)calendarItemWithIdentifier:(NSString *)i; - (nullable EKEvent *)eventWithIdentifier:(NSString *)i;
- (NSPredicate *)predicateForEventsWithStartDate:(NSDate *)s endDate:(NSDate *)e calendars:(nullable NSArray<EKCalendar *> *)c;
- (NSPredicate *)predicateForRemindersInCalendars:(nullable NSArray<EKCalendar *> *)c;
- (NSPredicate *)predicateForIncompleteRemindersWithDueDateStarting:(nullable NSDate *)s ending:(nullable NSDate *)e calendars:(nullable NSArray<EKCalendar *> *)c;
- (NSPredicate *)predicateForCompletedRemindersWithCompletionDateStarting:(nullable NSDate *)s ending:(nullable NSDate *)e calendars:(nullable NSArray<EKCalendar *> *)c;
- (NSArray<EKEvent *> *)eventsMatchingPredicate:(NSPredicate *)p;
- (void)enumerateEventsMatchingPredicate:(NSPredicate *)p usingBlock:(void (^)(EKEvent *e, BOOL *stop))b;
- (id)fetchRemindersMatchingPredicate:(NSPredicate *)p completion:(void (^)(NSArray<EKReminder *> *_Nullable r))c;
- (void)cancelFetchRequest:(id)r;
- (BOOL)saveEvent:(EKEvent *)e span:(EKSpan)s commit:(BOOL)c error:(NSError **)err;
- (BOOL)removeEvent:(EKEvent *)e span:(EKSpan)s commit:(BOOL)c error:(NSError **)err;
- (BOOL)saveReminder:(EKReminder *)r commit:(BOOL)c error:(NSError **)err;
- (BOOL)saveCalendar:(EKCalendar *)cal commit:(BOOL)c error:(NSError **)err;
- (BOOL)removeCalendar:(EKCalendar *)cal commit:(BOOL)c error:(NSError **)err;
- (BOOL)removeReminder:(EKReminder *)r commit:(BOOL)c error:(NSError **)err;
- (BOOL)commit:(NSError **)err; - (void)reset; - (void)refreshSourcesIfNecessary;
@end
NS_ASSUME_NONNULL_END
