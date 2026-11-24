/* document.m — the document architecture: NSDocumentController (types from Info.plist's CFBundleDocumentTypes, untitled
 * and opened documents, recent documents) and NSDocument (reading and writing through data or URLs, window controllers
 * made from the document's nib, change count, undo manager, save and close with the unsaved-changes alert), plus how
 * NSWindowController, NSApplication's launch and the responder chain reach them. */
#import "internal.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSString *const NSDocumentErrorDomainKey = @"NSDocumentErrorDomain";
@interface NSWindowController (MWDocument) - (void)_mwSetDocumentQuietly:(NSDocument *)d; @end

/* ======================================================================= document types from Info.plist */
static NSArray *doc_types(void) { return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDocumentTypes"] ?: @[]; }
static NSString *type_name(NSDictionary *t) {
    NSArray *ct = t[@"LSItemContentTypes"];
    return [ct count] ? ct[0] : t[@"CFBundleTypeName"];
}
static NSDictionary *type_dict(NSString *name) {
    for (NSDictionary *t in doc_types()) {
        if ([type_name(t) isEqualToString:name] || [t[@"CFBundleTypeName"] isEqualToString:name] || [t[@"LSItemContentTypes"] containsObject:name]) return t;
    }
    return nil;
}

/* ======================================================================= NSDocumentController */
static NSDocumentController *g_shared_dc;
id mw_document_controller_if_any(void) { return g_shared_dc; }
@implementation NSDocumentController { NSMutableArray *_documents; NSMutableArray *_recent; NSUInteger _untitled; }
+ (__kindof NSDocumentController *)sharedDocumentController { if (!g_shared_dc) [[self alloc] init]; return g_shared_dc; }
- (instancetype)init {
    if (g_shared_dc) { [self release]; return [g_shared_dc retain]; }   /* the first one made (a subclass in the main nib) is shared */
    if ((self = [super init])) {
        g_shared_dc = self;
        _documents = [[NSMutableArray alloc] init];
        _recent = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"NSRecentDocuments"] mutableCopy] ?: [[NSMutableArray alloc] init];
    }
    return self;
}
- (NSArray *)documents { return [[_documents copy] autorelease]; }
- (void)addDocument:(NSDocument *)d { if (d && ![_documents containsObject:d]) [_documents addObject:d]; }
- (void)removeDocument:(NSDocument *)d { [_documents removeObjectIdenticalTo:d]; }
- (id)currentDocument {
    NSWindow *w = [NSApp keyWindow] ?: [NSApp mainWindow];
    id d = w.windowController.document;
    return [_documents containsObject:d] ? d : nil;
}
- (id)documentForWindow:(NSWindow *)w { return w.windowController.document; }
- (id)documentForURL:(NSURL *)u {
    NSString *p = [[u URLByStandardizingPath] path];
    for (NSDocument *d in _documents) if ([[[d.fileURL URLByStandardizingPath] path] isEqualToString:p]) return d;
    return nil;
}
- (BOOL)hasEditedDocuments { for (NSDocument *d in _documents) if (d.isDocumentEdited) return YES; return NO; }
- (NSArray *)documentClassNames {
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *t in doc_types()) if (t[@"NSDocumentClass"] && ![a containsObject:t[@"NSDocumentClass"]]) [a addObject:t[@"NSDocumentClass"]];
    return a;
}
- (NSString *)defaultType {
    for (NSDictionary *t in doc_types()) if (t[@"NSDocumentClass"] && ![t[@"CFBundleTypeRole"] isEqualToString:@"Viewer"] && ![t[@"CFBundleTypeRole"] isEqualToString:@"None"]) return type_name(t);
    for (NSDictionary *t in doc_types()) if (t[@"NSDocumentClass"]) return type_name(t);
    return nil;
}
- (Class)documentClassForType:(NSString *)type {
    NSString *c = type_dict(type)[@"NSDocumentClass"];
    if (!c) c = [self documentClassNames].firstObject;
    return c ? NSClassFromString(c) : Nil;
}
- (NSString *)displayNameForType:(NSString *)type { return type_dict(type)[@"CFBundleTypeName"] ?: type; }
- (NSArray *)fileExtensionsFromType:(NSString *)type { return type_dict(type)[@"CFBundleTypeExtensions"] ?: @[]; }
- (NSString *)typeForContentsOfURL:(NSURL *)u error:(NSError **)e {
    NSString *ext = [[u pathExtension] lowercaseString];
    NSDictionary *any = nil;
    for (NSDictionary *t in doc_types()) {
        if (!t[@"NSDocumentClass"]) continue;
        for (NSString *x in t[@"CFBundleTypeExtensions"]) {
            if ([[x lowercaseString] isEqualToString:ext]) return type_name(t);
            if ([x isEqualToString:@"*"] && !any) any = t;
        }
        NSArray *ct = t[@"LSItemContentTypes"];
        if (!any && ([ct containsObject:@"public.data"] || [ct containsObject:@"public.item"] || [ct containsObject:@"public.content"])) any = t;
    }
    if (any) return type_name(any);
    NSString *d = [self defaultType];
    if (!d && e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{NSLocalizedDescriptionKey: @"The document could not be opened because its type is unknown."}];
    return d;
}
- (NSString *)_untitledName { _untitled++; return _untitled == 1 ? @"Untitled" : [NSString stringWithFormat:@"Untitled %lu", (unsigned long)_untitled]; }
- (id)makeUntitledDocumentOfType:(NSString *)type error:(NSError **)e {
    Class c = [self documentClassForType:type];
    if (!c) { if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFeatureUnsupportedError userInfo:nil]; return nil; }
    return [[[c alloc] initWithType:type error:e] autorelease];
}
- (id)makeDocumentWithContentsOfURL:(NSURL *)u ofType:(NSString *)type error:(NSError **)e {
    Class c = [self documentClassForType:type];
    if (!c) { if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFeatureUnsupportedError userInfo:nil]; return nil; }
    return [[[c alloc] initWithContentsOfURL:u ofType:type error:e] autorelease];
}
- (id)makeDocumentForURL:(NSURL *)u withContentsOfURL:(NSURL *)c ofType:(NSString *)type error:(NSError **)e {
    Class k = [self documentClassForType:type];
    return k ? [[[k alloc] initForURL:u withContentsOfURL:c ofType:type error:e] autorelease] : nil;
}
- (id)openUntitledDocumentAndDisplay:(BOOL)show error:(NSError **)e {
    NSString *type = [self defaultType];
    NSDocument *d = type ? [self makeUntitledDocumentOfType:type error:e] : nil;
    if (!d) return nil;
    [self addDocument:d];
    if (show) { [d makeWindowControllers]; [d showWindows]; }
    return d;
}
- (void)newDocument:(id)s {
    NSError *e = nil;
    if (![self openUntitledDocumentAndDisplay:YES error:&e] && e) [self presentError:e];
}
- (id)openDocumentWithContentsOfURL:(NSURL *)u display:(BOOL)show error:(NSError **)e {
    NSDocument *d = [self documentForURL:u];
    if (d) { if (show) [d showWindows]; return d; }
    NSString *type = [self typeForContentsOfURL:u error:e];
    if (!type) return nil;
    d = [self makeDocumentWithContentsOfURL:u ofType:type error:e];
    if (!d) return nil;
    [self addDocument:d];
    [self noteNewRecentDocumentURL:u];
    if (show) { [d makeWindowControllers]; [d showWindows]; }
    return d;
}
- (void)openDocumentWithContentsOfURL:(NSURL *)u display:(BOOL)show completionHandler:(void (^)(NSDocument *, BOOL, NSError *))h {
    BOOL already = [self documentForURL:u] != nil;
    NSError *e = nil;
    NSDocument *d = [self openDocumentWithContentsOfURL:u display:show error:&e];
    if (h) h(d, already, e);
    else if (!d && e) [self presentError:e];
}
- (id)openDocumentWithContentsOfFile:(NSString *)p display:(BOOL)show { return [self openDocumentWithContentsOfURL:[NSURL fileURLWithPath:p] display:show error:NULL]; }
- (NSArray *)URLsFromRunningOpenPanel {
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.allowsMultipleSelection = YES;
    return [self runModalOpenPanel:p forTypes:nil] == NSModalResponseOK ? p.URLs : nil;
}
- (NSInteger)runModalOpenPanel:(NSOpenPanel *)p forTypes:(NSArray *)types { return [p runModal]; }
- (void)beginOpenPanel:(NSOpenPanel *)p forTypes:(NSArray *)types completionHandler:(void (^)(NSInteger))h { h([self runModalOpenPanel:p forTypes:types]); }
- (void)openDocument:(id)s {
    for (NSURL *u in [self URLsFromRunningOpenPanel])
        [self openDocumentWithContentsOfURL:u display:YES completionHandler:^(NSDocument *d, BOOL already, NSError *e) { if (!d && e) [self presentError:e]; }];
}
- (void)saveAllDocuments:(id)s { for (NSDocument *d in [self documents]) if (d.isDocumentEdited) [d saveDocument:s]; }
- (void)closeAllDocumentsWithDelegate:(id)dl didCloseAllSelector:(SEL)sel contextInfo:(void *)ctx {
    BOOL all = YES;
    for (NSDocument *d in [self documents]) { if ([d _mwCanClose]) [d close]; else { all = NO; break; } }
    if (dl && sel) ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(dl, sel, self, all, ctx);
}
- (void)reviewUnsavedDocumentsWithAlertTitle:(NSString *)t cancellable:(BOOL)c delegate:(id)dl didReviewAllSelector:(SEL)sel contextInfo:(void *)ctx {
    [self closeAllDocumentsWithDelegate:dl didCloseAllSelector:sel contextInfo:ctx];
}
/* recent documents (kept in the app's defaults) */
- (NSUInteger)maximumRecentDocumentCount { return 10; }
- (NSArray *)recentDocumentURLs {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *p in _recent) [a addObject:[NSURL fileURLWithPath:p]];
    return a;
}
- (void)noteNewRecentDocumentURL:(NSURL *)u {
    if (![u isFileURL]) return;
    [_recent removeObject:[u path]]; [_recent insertObject:[u path] atIndex:0];
    while ([_recent count] > [self maximumRecentDocumentCount]) [_recent removeLastObject];
    [[NSUserDefaults standardUserDefaults] setObject:_recent forKey:@"NSRecentDocuments"];
}
- (void)noteNewRecentDocument:(NSDocument *)d { if (d.fileURL) [self noteNewRecentDocumentURL:d.fileURL]; }
- (void)clearRecentDocuments:(id)s { [_recent removeAllObjects]; [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NSRecentDocuments"]; }
- (BOOL)presentError:(NSError *)e { [[NSAlert alertWithError:e] runModal]; return NO; }
- (void)presentError:(NSError *)e modalForWindow:(NSWindow *)w delegate:(id)d didPresentSelector:(SEL)s contextInfo:(void *)c { [self presentError:e]; }
- (NSError *)willPresentError:(NSError *)e { return e; }
- (BOOL)validateMenuItem:(NSMenuItem *)i { return [self validateUserInterfaceItem:i]; }
- (BOOL)validateUserInterfaceItem:(id)i {
    SEL a = [i action];
    if (a == @selector(saveAllDocuments:)) return [self hasEditedDocuments];
    if (a == @selector(clearRecentDocuments:)) return [_recent count] > 0;
    return YES;
}
- (NSTimeInterval)autosavingDelay { return 0; } - (void)setAutosavingDelay:(NSTimeInterval)t {}
- (BOOL)allowsAutomaticShareMenu { return NO; }
@end

/* ======================================================================= NSDocument */
@implementation NSDocument {
    NSURL *_fileURL; NSString *_fileType, *_displayName; NSDate *_modDate; NSMutableArray *_wcs; NSUndoManager *_undo;
    NSInteger _changes; BOOL _hasUndo, _undoObserved; NSWindow *_pendingWindow;
}
+ (BOOL)autosavesInPlace { return NO; }
+ (BOOL)autosavesDrafts { return NO; }
+ (BOOL)preservesVersions { return NO; }
+ (BOOL)usesUbiquitousStorage { return NO; }
+ (BOOL)canConcurrentlyReadDocumentsOfType:(NSString *)t { return NO; }
+ (NSArray *)readableTypes { NSMutableArray *a = [NSMutableArray array]; for (NSDictionary *t in doc_types()) if (NSClassFromString(t[@"NSDocumentClass"]) == self) [a addObject:type_name(t)]; return a; }
+ (NSArray *)writableTypes { return [self readableTypes]; }
+ (BOOL)isNativeType:(NSString *)t { return [[self readableTypes] containsObject:t]; }
- (instancetype)init {
    if ((self = [super init])) { _wcs = [[NSMutableArray alloc] init]; _hasUndo = YES; }
    return self;
}
- (instancetype)initWithType:(NSString *)type error:(NSError **)e {
    if ((self = [self init])) self.fileType = type;
    return self;
}
- (instancetype)initWithContentsOfURL:(NSURL *)u ofType:(NSString *)type error:(NSError **)e {
    if (!(self = [self init])) return nil;
    self.fileURL = u; self.fileType = type;
    if (![self readFromURL:u ofType:type error:e]) { [self release]; return nil; }
    [self _mwNoteFileDate];
    return self;
}
- (instancetype)initForURL:(NSURL *)u withContentsOfURL:(NSURL *)c ofType:(NSString *)type error:(NSError **)e {
    if (!(self = [self init])) return nil;
    self.fileURL = u; self.fileType = type;
    if (c && ![self readFromURL:c ofType:type error:e]) { [self release]; return nil; }
    return self;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_fileURL release]; [_fileType release]; [_displayName release]; [_modDate release]; [_wcs release]; [_undo release];
    [super dealloc];
}
- (void)_mwNoteFileDate {
    NSDictionary *a = _fileURL ? [[NSFileManager defaultManager] attributesOfItemAtPath:[_fileURL path] error:NULL] : nil;
    self.fileModificationDate = a[NSFileModificationDate];
}
- (NSURL *)fileURL { return _fileURL; }
- (void)setFileURL:(NSURL *)u { [_fileURL release]; _fileURL = [u copy]; [self _mwSyncTitles]; }
- (NSString *)fileName { return [_fileURL path]; }
- (void)setFileName:(NSString *)p { self.fileURL = p ? [NSURL fileURLWithPath:p] : nil; }
- (NSString *)fileType { return _fileType; }
- (void)setFileType:(NSString *)t { [_fileType release]; _fileType = [t copy]; }
- (NSDate *)fileModificationDate { return _modDate; }
- (void)setFileModificationDate:(NSDate *)d { [_modDate release]; _modDate = [d copy]; }
- (NSString *)displayName {
    if (_displayName) return _displayName;
    if (_fileURL) return [[NSFileManager defaultManager] displayNameAtPath:[_fileURL path]] ?: [_fileURL lastPathComponent];
    _displayName = [[(NSDocumentController *)[NSDocumentController sharedDocumentController] _untitledName] copy];
    return _displayName;
}
- (void)setDisplayName:(NSString *)n { [_displayName release]; _displayName = [n copy]; [self _mwSyncTitles]; }
- (void)_mwSyncTitles { for (NSWindowController *wc in _wcs) [wc synchronizeWindowTitleWithDocumentName]; }
- (NSString *)lastComponentOfFileName { return [self displayName]; }
- (BOOL)isDraft { return NO; } - (void)setDraft:(BOOL)d {}
- (BOOL)isEntireFileLoaded { return YES; }
- (BOOL)isInViewingMode { return NO; }
- (BOOL)isLocked { return NO; }
- (BOOL)isBrowsingVersions { return NO; }
- (BOOL)hasUnautosavedChanges { return self.isDocumentEdited; }
- (BOOL)keepBackupFile { return NO; }

/* windows */
- (NSString *)windowNibName { return nil; }
- (NSArray *)windowControllers { return [[_wcs copy] autorelease]; }
- (void)makeWindowControllers {
    NSString *n = [self windowNibName];
    if (!n) return;
    NSWindowController *wc = [[NSWindowController alloc] initWithWindowNibName:n owner:self];
    [self addWindowController:wc];
    [wc release];
}
- (void)addWindowController:(NSWindowController *)wc {
    if (!wc || [_wcs containsObject:wc]) return;
    [_wcs addObject:wc];
    if (wc.document != self) [wc _mwSetDocumentQuietly:self];
}
- (void)removeWindowController:(NSWindowController *)wc {
    if (![_wcs containsObject:wc]) return;
    [wc retain];
    [_wcs removeObjectIdenticalTo:wc];
    if (wc.document == self) [wc _mwSetDocumentQuietly:nil];
    [wc release];
}
- (void)showWindows { for (NSWindowController *wc in [self windowControllers]) [wc showWindow:self]; }
- (void)windowControllerWillLoadNib:(NSWindowController *)wc {}
- (void)windowControllerDidLoadNib:(NSWindowController *)wc {}
/* the nib's "window" outlet on the File's Owner: the window of the first window controller */
- (void)setWindow:(NSWindow *)w { NSWindowController *wc = [_wcs firstObject]; if (wc) wc.window = w; else _pendingWindow = w; }
- (NSWindow *)windowForSheet { NSWindow *w = [[_wcs firstObject] window]; return w ?: [NSApp mainWindow]; }
- (void)shouldCloseWindowController:(NSWindowController *)wc delegate:(id)dl shouldCloseSelector:(SEL)sel contextInfo:(void *)ctx {
    BOOL ok = !(wc.shouldCloseDocument || [_wcs count] == 1) || [self _mwCanClose];
    if (dl && sel) ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(dl, sel, self, ok, ctx);
}
- (void)canCloseDocumentWithDelegate:(id)dl shouldCloseSelector:(SEL)sel contextInfo:(void *)ctx {
    BOOL ok = [self _mwCanClose];
    if (dl && sel) ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(dl, sel, self, ok, ctx);
}
/* unsaved changes: Save / Don't Save / Cancel */
- (BOOL)_mwCanClose {
    if (!self.isDocumentEdited) return YES;
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    a.messageText = [NSString stringWithFormat:@"Do you want to save the changes made to the document “%@”?", [self displayName]];
    a.informativeText = @"Your changes will be lost if you don’t save them.";
    [a addButtonWithTitle:@"Save"]; [a addButtonWithTitle:@"Cancel"]; [a addButtonWithTitle:@"Don’t Save"];
    NSModalResponse r = [a runModal];
    if (r == NSAlertFirstButtonReturn) { [self saveDocument:nil]; return !self.isDocumentEdited; }
    return r == NSAlertThirdButtonReturn;
}
- (void)close {
    [self retain];
    for (NSWindowController *wc in [self windowControllers]) { [wc _mwSetDocumentQuietly:nil]; [wc close]; }
    [_wcs removeAllObjects];
    [(NSDocumentController *)[NSDocumentController sharedDocumentController] removeDocument:self];
    [self release];
}
- (void)performClose:(id)s { [[self windowForSheet] performClose:s]; }

/* changes and undo */
- (BOOL)isDocumentEdited { return _changes != 0; }
- (void)updateChangeCount:(NSDocumentChangeType)t {
    BOOL was = self.isDocumentEdited;
    switch (t & 0xff) {
    case NSChangeDone: case NSChangeRedone: _changes++; break;
    case NSChangeUndone: _changes--; break;
    case NSChangeCleared: _changes = 0; break;
    default: break;
    }
    if (was != self.isDocumentEdited) for (NSWindowController *wc in _wcs) [wc setDocumentEdited:self.isDocumentEdited];
}
- (id)changeCountTokenForSaveOperation:(NSSaveOperationType)op { return @(_changes); }
- (void)updateChangeCountWithToken:(id)tok forSaveOperation:(NSSaveOperationType)op { if ([tok integerValue] == _changes) [self updateChangeCount:NSChangeCleared]; }
- (BOOL)hasUndoManager { return _hasUndo; }
- (void)setHasUndoManager:(BOOL)f { _hasUndo = f; if (!f) self.undoManager = nil; }
- (NSUndoManager *)undoManager {
    if (!_undo && _hasUndo) self.undoManager = [[[NSUndoManager alloc] init] autorelease];
    return _undo;
}
- (void)setUndoManager:(NSUndoManager *)u {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (_undo) { [nc removeObserver:self name:nil object:_undo]; }
    [u retain]; [_undo release]; _undo = u;
    if (u) {
        [nc addObserver:self selector:@selector(_mwUndoChange:) name:NSUndoManagerDidCloseUndoGroupNotification object:u];
        [nc addObserver:self selector:@selector(_mwUndoChange:) name:NSUndoManagerDidUndoChangeNotification object:u];
        [nc addObserver:self selector:@selector(_mwUndoChange:) name:NSUndoManagerDidRedoChangeNotification object:u];
    }
}
- (void)_mwUndoChange:(NSNotification *)n {
    NSString *k = n.name;
    if ([k isEqualToString:NSUndoManagerDidUndoChangeNotification]) [self updateChangeCount:NSChangeUndone];
    else if ([k isEqualToString:NSUndoManagerDidRedoChangeNotification]) [self updateChangeCount:NSChangeRedone];
    else if (_undo.groupingLevel == 0 && !_undo.isUndoing && !_undo.isRedoing) [self updateChangeCount:NSChangeDone];
}
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)w { return self.undoManager; }
- (void)undo:(id)s { [self.undoManager undo]; }
- (void)redo:(id)s { [self.undoManager redo]; }

/* reading */
- (BOOL)readFromURL:(NSURL *)u ofType:(NSString *)type error:(NSError **)e {
    if (class_getMethodImplementation(object_getClass(self), @selector(readFromFileWrapper:ofType:error:)) != class_getMethodImplementation([NSDocument class], @selector(readFromFileWrapper:ofType:error:))) {
        id fw = [[[NSFileWrapper alloc] initWithURL:u options:0 error:e] autorelease];
        return fw && [self readFromFileWrapper:fw ofType:type error:e];
    }
    NSData *d = [NSData dataWithContentsOfURL:u options:0 error:e];
    return d && [self readFromData:d ofType:type error:e];
}
- (BOOL)readFromFileWrapper:(NSFileWrapper *)fw ofType:(NSString *)type error:(NSError **)e { return [self readFromData:[fw regularFileContents] ofType:type error:e]; }
- (BOOL)readFromData:(NSData *)d ofType:(NSString *)type error:(NSError **)e {
    if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFeatureUnsupportedError userInfo:@{NSLocalizedDescriptionKey: @"This document type cannot be read."}];
    return NO;
}
- (BOOL)revertToContentsOfURL:(NSURL *)u ofType:(NSString *)type error:(NSError **)e {
    if (![self readFromURL:u ofType:type error:e]) return NO;
    [self updateChangeCount:NSChangeCleared]; [_undo removeAllActions]; [self _mwNoteFileDate];
    return YES;
}
- (void)revertDocumentToSaved:(id)s { if (_fileURL) { NSError *e = nil; if (![self revertToContentsOfURL:_fileURL ofType:_fileType error:&e] && e) [self presentError:e]; } }

/* writing */
- (NSData *)dataOfType:(NSString *)type error:(NSError **)e {
    if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFeatureUnsupportedError userInfo:@{NSLocalizedDescriptionKey: @"This document type cannot be saved."}];
    return nil;
}
- (NSFileWrapper *)fileWrapperOfType:(NSString *)type error:(NSError **)e { NSData *d = [self dataOfType:type error:e]; return d ? [[[NSFileWrapper alloc] initRegularFileWithContents:d] autorelease] : nil; }
- (BOOL)writeToURL:(NSURL *)u ofType:(NSString *)type error:(NSError **)e {
    if (class_getMethodImplementation(object_getClass(self), @selector(fileWrapperOfType:error:)) != class_getMethodImplementation([NSDocument class], @selector(fileWrapperOfType:error:))) {
        NSFileWrapper *fw = [self fileWrapperOfType:type error:e];
        return fw && [fw writeToURL:u options:NSFileWrapperWritingAtomic originalContentsURL:nil error:e];
    }
    NSData *d = [self dataOfType:type error:e];
    return d && [d writeToURL:u options:NSDataWritingAtomic error:e];
}
- (BOOL)writeToURL:(NSURL *)u ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)op originalContentsURL:(NSURL *)orig error:(NSError **)e { return [self writeToURL:u ofType:type error:e]; }
- (BOOL)writeSafelyToURL:(NSURL *)u ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)op error:(NSError **)e {
    return [self writeToURL:u ofType:type forSaveOperation:op originalContentsURL:_fileURL error:e];
}
- (NSDictionary *)fileAttributesToWriteToURL:(NSURL *)u ofType:(NSString *)t forSaveOperation:(NSSaveOperationType)op originalContentsURL:(NSURL *)o error:(NSError **)e { return @{}; }
- (BOOL)saveToURL:(NSURL *)u ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)op error:(NSError **)e {
    if (![self writeSafelyToURL:u ofType:type forSaveOperation:op error:e]) return NO;
    if (op == NSSaveOperation || op == NSSaveAsOperation) {
        self.fileURL = u; self.fileType = type; [self _mwNoteFileDate];
        [self updateChangeCount:NSChangeCleared];
        [(NSDocumentController *)[NSDocumentController sharedDocumentController] noteNewRecentDocument:self];
    }
    return YES;
}
- (void)saveToURL:(NSURL *)u ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)op completionHandler:(void (^)(NSError *))h {
    NSError *e = nil;
    BOOL ok = [self saveToURL:u ofType:type forSaveOperation:op error:&e];
    if (h) h(ok ? nil : e ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil]);
    else if (!ok && e) [self presentError:e];
}
- (void)saveToURL:(NSURL *)u ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)op delegate:(id)dl didSaveSelector:(SEL)sel contextInfo:(void *)ctx {
    NSError *e = nil;
    BOOL ok = [self saveToURL:u ofType:type forSaveOperation:op error:&e];
    if (!ok && e) [self presentError:e];
    if (dl && sel) ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(dl, sel, self, ok, ctx);
}
- (NSArray *)writableTypesForSaveOperation:(NSSaveOperationType)op { return [[self class] writableTypes]; }
- (NSString *)fileNameExtensionForType:(NSString *)type saveOperation:(NSSaveOperationType)op {
    NSArray *x = [(NSDocumentController *)[NSDocumentController sharedDocumentController] fileExtensionsFromType:type];
    return [x count] && ![x[0] isEqualToString:@"*"] ? x[0] : nil;
}
- (BOOL)prepareSavePanel:(NSSavePanel *)p { return YES; }
- (BOOL)shouldRunSavePanelWithAccessoryView { return YES; }
- (NSString *)fileTypeFromLastRunSavePanel { return _fileType ?: [(NSDocumentController *)[NSDocumentController sharedDocumentController] defaultType]; }
- (BOOL)fileNameExtensionWasHiddenInLastRunSavePanel { return NO; }
- (void)_mwRunSavePanel:(NSSaveOperationType)op {
    NSSavePanel *p = [NSSavePanel savePanel];
    NSString *name = _fileURL ? [_fileURL lastPathComponent] : [self displayName];
    NSString *ext = [self fileNameExtensionForType:[self fileTypeFromLastRunSavePanel] saveOperation:op];
    if (ext && ![[name pathExtension] length]) name = [name stringByAppendingPathExtension:ext];
    p.nameFieldStringValue = name;
    if (_fileURL) p.directoryURL = [_fileURL URLByDeletingLastPathComponent];
    if (![self prepareSavePanel:p] || [p runModal] != NSModalResponseOK || !p.URL) return;
    [self saveToURL:p.URL ofType:[self fileTypeFromLastRunSavePanel] forSaveOperation:op completionHandler:nil];
}
- (void)saveDocument:(id)s {
    if (_fileURL) [self saveToURL:_fileURL ofType:_fileType forSaveOperation:NSSaveOperation completionHandler:nil];
    else [self _mwRunSavePanel:NSSaveAsOperation];
}
- (void)saveDocumentAs:(id)s { [self _mwRunSavePanel:NSSaveAsOperation]; }
- (void)saveDocumentTo:(id)s { [self _mwRunSavePanel:NSSaveToOperation]; }
- (void)saveDocumentWithDelegate:(id)dl didSaveSelector:(SEL)sel contextInfo:(void *)ctx {
    [self saveDocument:nil];
    if (dl && sel) ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(dl, sel, self, !self.isDocumentEdited, ctx);
}
- (void)autosaveDocumentWithDelegate:(id)d didAutosaveSelector:(SEL)s contextInfo:(void *)c {}
- (void)autosaveWithImplicitCancellability:(BOOL)c completionHandler:(void (^)(NSError *))h { if (h) h(nil); }
- (BOOL)checkAutosavingSafetyAndReturnError:(NSError **)e { return YES; }
- (void)printDocument:(id)s {} - (void)runPageLayout:(id)s {}
- (NSPrintInfo *)printInfo { return nil; } - (void)setPrintInfo:(NSPrintInfo *)p {}
- (void)duplicateDocument:(id)s {} - (void)renameDocument:(id)s {} - (void)moveDocument:(id)s {} - (void)lockDocument:(id)s {} - (void)unlockDocument:(id)s {}
- (void)browseDocumentVersions:(id)s {}
- (BOOL)presentError:(NSError *)e { [[NSAlert alertWithError:[self willPresentError:e]] runModal]; return NO; }
- (void)presentError:(NSError *)e modalForWindow:(NSWindow *)w delegate:(id)d didPresentSelector:(SEL)s contextInfo:(void *)c { [self presentError:e]; }
- (NSError *)willPresentError:(NSError *)e { return e; }
- (void)performActivityWithSynchronousWaiting:(BOOL)w usingBlock:(void (^)(void (^)(void)))b { b(^{}); }
- (void)continueActivityUsingBlock:(void (^)(void))b { b(); }
- (void)continueAsynchronousWorkOnMainThreadUsingBlock:(void (^)(void))b { b(); }
- (void)performSynchronousFileAccessUsingBlock:(void (^)(void))b { b(); }
- (void)performAsynchronousFileAccessUsingBlock:(void (^)(void (^)(void)))b { b(^{}); }
- (BOOL)validateMenuItem:(NSMenuItem *)i { return [self validateUserInterfaceItem:i]; }
- (BOOL)validateUserInterfaceItem:(id)i {
    SEL a = [i action];
    if (a == @selector(revertDocumentToSaved:)) return _fileURL && self.isDocumentEdited;
    if (a == @selector(undo:)) { if ([i respondsToSelector:@selector(setTitle:)]) [i setTitle:[self.undoManager undoMenuItemTitle]]; return [self.undoManager canUndo]; }
    if (a == @selector(redo:)) { if ([i respondsToSelector:@selector(setTitle:)]) [i setTitle:[self.undoManager redoMenuItemTitle]]; return [self.undoManager canRedo]; }
    return YES;
}
- (void)setWindowControllersNeedTitleUpdate {}
@end

/* ======================================================================= NSWindowController and the document */
@implementation NSWindowController (MWDocument)
- (void)_mwSetDocumentQuietly:(NSDocument *)d { /* the property's storage, without -setDocument:'s side effects in subclasses */
    Ivar iv = class_getInstanceVariable([NSWindowController class], "_document");
    if (iv) *(id *)((char *)self + ivar_getOffset(iv)) = d;
    if (d && self.isWindowLoaded) [self synchronizeWindowTitleWithDocumentName];
}
- (NSString *)windowTitleForDocumentDisplayName:(NSString *)n { return n; }
- (void)synchronizeWindowTitleWithDocumentName {
    NSDocument *d = self.document;
    if (!d || !self.isWindowLoaded) return;
    self.window.title = [self windowTitleForDocumentDisplayName:[d displayName]];
    if (d.fileURL) self.window.representedURL = d.fileURL;
}
- (void)setDocumentEdited:(BOOL)f { if (self.isWindowLoaded) self.window.documentEdited = f; }
/* NSWindow -performClose: asks this before closing */
- (BOOL)_mwWindowShouldClose {
    NSDocument *d = self.document;
    if (!d) return YES;
    BOOL last = self.shouldCloseDocument || [d.windowControllers count] <= 1;
    return !last || [d _mwCanClose];
}
- (void)_mwWindowWillClose:(NSNotification *)n {
    NSDocument *d = [[self.document retain] autorelease];
    if (!d) return;
    if (self.shouldCloseDocument || [d.windowControllers count] <= 1) [d close];
    else [d removeWindowController:self];
}
@end

@interface NSObject (MWAppDelegateDocuments)
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)a; - (BOOL)applicationOpenUntitledFile:(NSApplication *)a;
- (void)application:(NSApplication *)a openFiles:(NSArray *)f;
@end
/* ======================================================================= launch: files from the command line, or an untitled document */
void mw_open_launch_documents(void) {
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    NSMutableArray *files = [NSMutableArray array];
    for (NSUInteger i = 1; i < [args count]; i++) {
        NSString *a = args[i];
        if ([a hasPrefix:@"-"]) { i++; continue; } /* -Key value (defaults) */
        BOOL dir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:a isDirectory:&dir] && ![[a pathExtension] isEqualToString:@"app"]) [files addObject:a];
    }
    id dl = [NSApp delegate];
    if ([files count]) {
        if ([dl respondsToSelector:@selector(application:openURLs:)]) {
            NSMutableArray *u = [NSMutableArray array]; for (NSString *f in files) [u addObject:[NSURL fileURLWithPath:f]];
            [dl application:NSApp openURLs:u]; return;
        }
        if ([dl respondsToSelector:@selector(application:openFiles:)]) { [dl application:NSApp openFiles:files]; return; }
        if ([dl respondsToSelector:@selector(application:openFile:)]) { for (NSString *f in files) [dl application:NSApp openFile:f]; return; }
        NSDocumentController *dc = [NSDocumentController sharedDocumentController];
        if ([dc defaultType]) { for (NSString *f in files) [dc openDocumentWithContentsOfURL:[NSURL fileURLWithPath:f] display:YES completionHandler:^(NSDocument *d, BOOL already, NSError *e) { if (!d && e) [dc presentError:e]; }]; return; }
    }
    if ([dl respondsToSelector:@selector(applicationShouldOpenUntitledFile:)] && ![dl applicationShouldOpenUntitledFile:NSApp]) return;
    if (!g_shared_dc && ![[NSDocumentController sharedDocumentController] defaultType]) return;
    if (![[NSDocumentController sharedDocumentController] defaultType]) return;
    if ([dl respondsToSelector:@selector(applicationOpenUntitledFile:)]) { [dl applicationOpenUntitledFile:NSApp]; return; }
    [[NSDocumentController sharedDocumentController] newDocument:nil];
}
