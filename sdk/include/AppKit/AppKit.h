/* scion SDK — AppKit subset (implemented in AppKit.dylib; Cocoa.framework maps to it).
 * Windows, views, events, menus, screens, cursors and the common controls. Controls keep their state but are not drawn
 * yet: windows show what Metal (CAMetalLayer / MTKView) draws. Values of every enum and constant are Apple's. */
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/CAMetalLayer.h>
NS_ASSUME_NONNULL_BEGIN

#define APPKIT_EXTERN extern
#ifndef NS_SWIFT_UI_ACTOR
#define NS_SWIFT_UI_ACTOR
#endif

@class NSApplication, NSWindow, NSView, NSEvent, NSScreen, NSMenu, NSMenuItem, NSCursor, NSColor, NSFont, NSImage,
    NSResponder, NSTrackingArea, NSLayoutConstraint, NSAppearance, NSGraphicsContext, NSWindowController, NSViewController,
    NSLayoutXAxisAnchor, NSLayoutYAxisAnchor, NSLayoutDimension, NSPasteboard, NSTextField, NSButton, NSControl, NSGridColumn,
    NSGridRow, NSGridCell, NSBitmapImageRep, NSImageRep, NSRunningApplication, NSColorSpace;

/* ============================================================================================ enums */
typedef NS_OPTIONS(NSUInteger, NSWindowStyleMask) {
    NSWindowStyleMaskBorderless = 0, NSWindowStyleMaskTitled = 1, NSWindowStyleMaskClosable = 2, NSWindowStyleMaskMiniaturizable = 4,
    NSWindowStyleMaskResizable = 8, NSWindowStyleMaskUtilityWindow = 1 << 4, NSWindowStyleMaskDocModalWindow = 1 << 6,
    NSWindowStyleMaskNonactivatingPanel = 1 << 7, NSWindowStyleMaskUnifiedTitleAndToolbar = 1 << 12, NSWindowStyleMaskHUDWindow = 1 << 13,
    NSWindowStyleMaskFullScreen = 1 << 14, NSWindowStyleMaskFullSizeContentView = 1 << 15,
};
enum { NSBorderlessWindowMask = 0, NSTitledWindowMask = 1, NSClosableWindowMask = 2, NSMiniaturizableWindowMask = 4, NSResizableWindowMask = 8,
       NSFullScreenWindowMask = 1 << 14, NSFullSizeContentViewWindowMask = 1 << 15 };
typedef NS_ENUM(NSUInteger, NSBackingStoreType) { NSBackingStoreRetained = 0, NSBackingStoreNonretained = 1, NSBackingStoreBuffered = 2 };
typedef NS_ENUM(NSUInteger, NSEventType) {
    NSEventTypeLeftMouseDown = 1, NSEventTypeLeftMouseUp = 2, NSEventTypeRightMouseDown = 3, NSEventTypeRightMouseUp = 4,
    NSEventTypeMouseMoved = 5, NSEventTypeLeftMouseDragged = 6, NSEventTypeRightMouseDragged = 7, NSEventTypeMouseEntered = 8,
    NSEventTypeMouseExited = 9, NSEventTypeKeyDown = 10, NSEventTypeKeyUp = 11, NSEventTypeFlagsChanged = 12,
    NSEventTypeAppKitDefined = 13, NSEventTypeSystemDefined = 14, NSEventTypeApplicationDefined = 15, NSEventTypePeriodic = 16,
    NSEventTypeCursorUpdate = 17, NSEventTypeRotate = 18, NSEventTypeBeginGesture = 19, NSEventTypeEndGesture = 20,
    NSEventTypeScrollWheel = 22, NSEventTypeTabletPoint = 23, NSEventTypeTabletProximity = 24, NSEventTypeOtherMouseDown = 25,
    NSEventTypeOtherMouseUp = 26, NSEventTypeOtherMouseDragged = 27, NSEventTypeGesture = 29, NSEventTypeMagnify = 30,
    NSEventTypeSwipe = 31, NSEventTypeSmartMagnify = 32, NSEventTypeQuickLook = 33, NSEventTypePressure = 34,
};
enum { NSLeftMouseDown = 1, NSLeftMouseUp = 2, NSRightMouseDown = 3, NSRightMouseUp = 4, NSMouseMoved = 5, NSKeyDown = 10, NSKeyUp = 11,
       NSFlagsChanged = 12, NSApplicationDefined = 15, NSScrollWheel = 22 };
typedef NS_OPTIONS(unsigned long long, NSEventMask) {
    NSEventMaskLeftMouseDown = 1ULL << 1, NSEventMaskLeftMouseUp = 1ULL << 2, NSEventMaskRightMouseDown = 1ULL << 3,
    NSEventMaskRightMouseUp = 1ULL << 4, NSEventMaskMouseMoved = 1ULL << 5, NSEventMaskLeftMouseDragged = 1ULL << 6,
    NSEventMaskRightMouseDragged = 1ULL << 7, NSEventMaskMouseEntered = 1ULL << 8, NSEventMaskMouseExited = 1ULL << 9,
    NSEventMaskKeyDown = 1ULL << 10, NSEventMaskKeyUp = 1ULL << 11, NSEventMaskFlagsChanged = 1ULL << 12,
    NSEventMaskAppKitDefined = 1ULL << 13, NSEventMaskSystemDefined = 1ULL << 14, NSEventMaskApplicationDefined = 1ULL << 15,
    NSEventMaskPeriodic = 1ULL << 16, NSEventMaskCursorUpdate = 1ULL << 17, NSEventMaskScrollWheel = 1ULL << 22,
    NSEventMaskOtherMouseDown = 1ULL << 25, NSEventMaskOtherMouseUp = 1ULL << 26, NSEventMaskOtherMouseDragged = 1ULL << 27,
    NSEventMaskMagnify = 1ULL << 30, NSEventMaskAny = ~0ULL,
};
#define NSAnyEventMask NSEventMaskAny
static inline NSEventMask NSEventMaskFromType(NSEventType t) { return 1ULL << t; }
typedef NS_OPTIONS(NSUInteger, NSEventModifierFlags) {
    NSEventModifierFlagCapsLock = 1 << 16, NSEventModifierFlagShift = 1 << 17, NSEventModifierFlagControl = 1 << 18,
    NSEventModifierFlagOption = 1 << 19, NSEventModifierFlagCommand = 1 << 20, NSEventModifierFlagNumericPad = 1 << 21,
    NSEventModifierFlagHelp = 1 << 22, NSEventModifierFlagFunction = 1 << 23, NSEventModifierFlagDeviceIndependentFlagsMask = 0xffff0000UL,
};
enum { NSAlphaShiftKeyMask = 1 << 16, NSShiftKeyMask = 1 << 17, NSControlKeyMask = 1 << 18, NSAlternateKeyMask = 1 << 19,
       NSCommandKeyMask = 1 << 20, NSNumericPadKeyMask = 1 << 21, NSFunctionKeyMask = 1 << 23, NSDeviceIndependentModifierFlagsMask = 0xffff0000UL };
typedef NS_OPTIONS(NSUInteger, NSEventPhase) {
    NSEventPhaseNone = 0, NSEventPhaseBegan = 1, NSEventPhaseStationary = 2, NSEventPhaseChanged = 4, NSEventPhaseEnded = 8,
    NSEventPhaseCancelled = 16, NSEventPhaseMayBegin = 32,
};
typedef NS_ENUM(short, NSEventSubtype) { NSEventSubtypeWindowExposed = 0, NSEventSubtypeApplicationActivated = 1, NSEventSubtypeMouseEvent = 0 };
enum { NSUpArrowFunctionKey = 0xF700, NSDownArrowFunctionKey = 0xF701, NSLeftArrowFunctionKey = 0xF702, NSRightArrowFunctionKey = 0xF703,
       NSF1FunctionKey = 0xF704, NSF2FunctionKey, NSF3FunctionKey, NSF4FunctionKey, NSF5FunctionKey, NSF6FunctionKey, NSF7FunctionKey,
       NSF8FunctionKey, NSF9FunctionKey, NSF10FunctionKey, NSF11FunctionKey, NSF12FunctionKey, NSInsertFunctionKey = 0xF727,
       NSDeleteFunctionKey = 0xF728, NSHomeFunctionKey = 0xF729, NSEndFunctionKey = 0xF72B, NSPageUpFunctionKey = 0xF72C,
       NSPageDownFunctionKey = 0xF72D };
enum { NSEnterCharacter = 0x3, NSBackspaceCharacter = 0x8, NSTabCharacter = 0x9, NSNewlineCharacter = 0xa, NSCarriageReturnCharacter = 0xd,
       NSBackTabCharacter = 0x19, NSDeleteCharacter = 0x7f };
typedef NS_ENUM(NSInteger, NSApplicationActivationPolicy) {
    NSApplicationActivationPolicyRegular = 0, NSApplicationActivationPolicyAccessory = 1, NSApplicationActivationPolicyProhibited = 2 };
typedef NS_ENUM(NSUInteger, NSApplicationTerminateReply) { NSTerminateCancel = 0, NSTerminateNow = 1, NSTerminateLater = 2 };
typedef NS_OPTIONS(NSUInteger, NSApplicationPresentationOptions) {
    NSApplicationPresentationDefault = 0, NSApplicationPresentationAutoHideDock = 1, NSApplicationPresentationHideDock = 2,
    NSApplicationPresentationAutoHideMenuBar = 4, NSApplicationPresentationHideMenuBar = 8, NSApplicationPresentationDisableAppleMenu = 16,
    NSApplicationPresentationDisableProcessSwitching = 32, NSApplicationPresentationDisableForceQuit = 64,
    NSApplicationPresentationDisableSessionTermination = 128, NSApplicationPresentationDisableHideApplication = 256,
    NSApplicationPresentationDisableMenuBarTransparency = 512, NSApplicationPresentationFullScreen = 1024,
    NSApplicationPresentationAutoHideToolbar = 2048,
};
typedef NS_OPTIONS(NSUInteger, NSApplicationActivationOptions) { NSApplicationActivateAllWindows = 1, NSApplicationActivateIgnoringOtherApps = 2 };
typedef NS_ENUM(NSUInteger, NSRequestUserAttentionType) { NSCriticalRequest = 0, NSInformationalRequest = 10 };
typedef NS_OPTIONS(NSUInteger, NSWindowCollectionBehavior) {
    NSWindowCollectionBehaviorDefault = 0, NSWindowCollectionBehaviorCanJoinAllSpaces = 1, NSWindowCollectionBehaviorMoveToActiveSpace = 2,
    NSWindowCollectionBehaviorManaged = 4, NSWindowCollectionBehaviorTransient = 8, NSWindowCollectionBehaviorStationary = 16,
    NSWindowCollectionBehaviorParticipatesInCycle = 32, NSWindowCollectionBehaviorIgnoresCycle = 64,
    NSWindowCollectionBehaviorFullScreenPrimary = 128, NSWindowCollectionBehaviorFullScreenAuxiliary = 256,
    NSWindowCollectionBehaviorFullScreenNone = 512, NSWindowCollectionBehaviorFullScreenAllowsTiling = 2048,
    NSWindowCollectionBehaviorFullScreenDisallowsTiling = 4096,
};
typedef NS_OPTIONS(NSUInteger, NSWindowOcclusionState) { NSWindowOcclusionStateVisible = 1 << 1 };
typedef NSInteger NSWindowLevel;
enum { NSNormalWindowLevel = 0, NSFloatingWindowLevel = 3, NSSubmenuWindowLevel = 3, NSTornOffMenuWindowLevel = 3, NSModalPanelWindowLevel = 8,
       NSMainMenuWindowLevel = 24, NSStatusWindowLevel = 25, NSPopUpMenuWindowLevel = 101, NSScreenSaverWindowLevel = 1000 };
typedef NS_ENUM(NSInteger, NSWindowOrderingMode) { NSWindowAbove = 1, NSWindowBelow = -1, NSWindowOut = 0 };
typedef NS_ENUM(NSInteger, NSWindowTitleVisibility) { NSWindowTitleVisible = 0, NSWindowTitleHidden = 1 };
typedef NS_ENUM(NSUInteger, NSWindowButton) { NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton, NSWindowToolbarButton, NSWindowDocumentIconButton };
typedef NS_ENUM(NSInteger, NSWindowTabbingMode) { NSWindowTabbingModeAutomatic, NSWindowTabbingModePreferred, NSWindowTabbingModeDisallowed };
typedef NS_ENUM(NSInteger, NSWindowAnimationBehavior) { NSWindowAnimationBehaviorDefault = 0, NSWindowAnimationBehaviorNone = 2,
    NSWindowAnimationBehaviorDocumentWindow = 3, NSWindowAnimationBehaviorUtilityWindow = 4, NSWindowAnimationBehaviorAlertPanel = 5 };
typedef NS_ENUM(NSInteger, NSWindowToolbarStyle) { NSWindowToolbarStyleAutomatic, NSWindowToolbarStyleExpanded, NSWindowToolbarStylePreference,
    NSWindowToolbarStyleUnified, NSWindowToolbarStyleUnifiedCompact };
typedef NS_OPTIONS(NSUInteger, NSAutoresizingMaskOptions) {
    NSViewNotSizable = 0, NSViewMinXMargin = 1, NSViewWidthSizable = 2, NSViewMaxXMargin = 4, NSViewMinYMargin = 8,
    NSViewHeightSizable = 16, NSViewMaxYMargin = 32,
};
typedef NS_ENUM(NSInteger, NSViewLayerContentsRedrawPolicy) {
    NSViewLayerContentsRedrawNever = 0, NSViewLayerContentsRedrawOnSetNeedsDisplay = 1, NSViewLayerContentsRedrawDuringViewResize = 2,
    NSViewLayerContentsRedrawBeforeViewResize = 3, NSViewLayerContentsRedrawCrossfade = 4 };
typedef NS_ENUM(NSInteger, NSViewLayerContentsPlacement) { NSViewLayerContentsPlacementScaleAxesIndependently = 0 };
typedef NS_OPTIONS(NSUInteger, NSTrackingAreaOptions) {
    NSTrackingMouseEnteredAndExited = 1, NSTrackingMouseMoved = 2, NSTrackingCursorUpdate = 4, NSTrackingActiveWhenFirstResponder = 0x10,
    NSTrackingActiveInKeyWindow = 0x20, NSTrackingActiveInActiveApp = 0x40, NSTrackingActiveAlways = 0x80, NSTrackingAssumeInside = 0x100,
    NSTrackingInVisibleRect = 0x200, NSTrackingEnabledDuringMouseDrag = 0x400,
};
typedef NSInteger NSControlStateValue;
static const NSControlStateValue NSControlStateValueMixed = -1, NSControlStateValueOff = 0, NSControlStateValueOn = 1;
enum { NSMixedState = -1, NSOffState = 0, NSOnState = 1 };
typedef NS_ENUM(NSUInteger, NSControlSize) { NSControlSizeRegular = 0, NSControlSizeSmall = 1, NSControlSizeMini = 2, NSControlSizeLarge = 3 };
typedef NS_ENUM(NSInteger, NSTextAlignment) { NSTextAlignmentLeft = 0, NSTextAlignmentRight = 1, NSTextAlignmentCenter = 2,
    NSTextAlignmentJustified = 3, NSTextAlignmentNatural = 4 };
typedef NS_ENUM(NSInteger, NSLineBreakMode) { NSLineBreakByWordWrapping = 0, NSLineBreakByCharWrapping, NSLineBreakByClipping,
    NSLineBreakByTruncatingHead, NSLineBreakByTruncatingTail, NSLineBreakByTruncatingMiddle };
typedef NS_ENUM(NSInteger, NSUserInterfaceLayoutOrientation) { NSUserInterfaceLayoutOrientationHorizontal = 0, NSUserInterfaceLayoutOrientationVertical = 1 };
typedef NS_ENUM(NSInteger, NSUserInterfaceLayoutDirection) { NSUserInterfaceLayoutDirectionLeftToRight = 0, NSUserInterfaceLayoutDirectionRightToLeft = 1 };
typedef NS_ENUM(NSInteger, NSStackViewDistribution) { NSStackViewDistributionGravityAreas = -1, NSStackViewDistributionFill = 0,
    NSStackViewDistributionFillEqually, NSStackViewDistributionFillProportionally, NSStackViewDistributionEqualSpacing,
    NSStackViewDistributionEqualCentering };
typedef NS_ENUM(NSInteger, NSStackViewGravity) { NSStackViewGravityTop = 1, NSStackViewGravityLeading = 1, NSStackViewGravityCenter = 2,
    NSStackViewGravityBottom = 3, NSStackViewGravityTrailing = 3 };
typedef NS_ENUM(NSInteger, NSLayoutAttribute) {
    NSLayoutAttributeLeft = 1, NSLayoutAttributeRight, NSLayoutAttributeTop, NSLayoutAttributeBottom, NSLayoutAttributeLeading,
    NSLayoutAttributeTrailing, NSLayoutAttributeWidth, NSLayoutAttributeHeight, NSLayoutAttributeCenterX, NSLayoutAttributeCenterY,
    NSLayoutAttributeLastBaseline, NSLayoutAttributeBaseline = NSLayoutAttributeLastBaseline, NSLayoutAttributeFirstBaseline,
    NSLayoutAttributeNotAnAttribute = 0,
};
typedef NS_ENUM(NSInteger, NSLayoutRelation) { NSLayoutRelationLessThanOrEqual = -1, NSLayoutRelationEqual = 0, NSLayoutRelationGreaterThanOrEqual = 1 };
typedef NS_ENUM(NSInteger, NSLayoutConstraintOrientation) { NSLayoutConstraintOrientationHorizontal = 0, NSLayoutConstraintOrientationVertical = 1 };
typedef NS_OPTIONS(NSUInteger, NSLayoutFormatOptions) { NSLayoutFormatAlignAllLeft = 1 << 1, NSLayoutFormatAlignAllCenterX = 1 << 9,
    NSLayoutFormatAlignAllCenterY = 1 << 10, NSLayoutFormatDirectionLeadingToTrailing = 0 };
typedef float NSLayoutPriority;
static const NSLayoutPriority NSLayoutPriorityRequired = 1000, NSLayoutPriorityDefaultHigh = 750, NSLayoutPriorityDragThatCanResizeWindow = 510,
    NSLayoutPriorityWindowSizeStayPut = 500, NSLayoutPriorityDragThatCannotResizeWindow = 490, NSLayoutPriorityDefaultLow = 250,
    NSLayoutPriorityFittingSizeCompression = 50;
typedef NS_ENUM(NSInteger, NSGridCellPlacement) { NSGridCellPlacementInherited = 0, NSGridCellPlacementNone, NSGridCellPlacementLeading,
    NSGridCellPlacementTop = NSGridCellPlacementLeading, NSGridCellPlacementTrailing, NSGridCellPlacementBottom = NSGridCellPlacementTrailing,
    NSGridCellPlacementCenter, NSGridCellPlacementFill };
typedef NS_ENUM(NSInteger, NSGridRowAlignment) { NSGridRowAlignmentInherited = 0, NSGridRowAlignmentNone, NSGridRowAlignmentFirstBaseline,
    NSGridRowAlignmentLastBaseline };
APPKIT_EXTERN const CGFloat NSGridViewSizeForContent;
typedef NS_ENUM(NSUInteger, NSSegmentSwitchTracking) { NSSegmentSwitchTrackingSelectOne = 0, NSSegmentSwitchTrackingSelectAny = 1,
    NSSegmentSwitchTrackingMomentary = 2, NSSegmentSwitchTrackingMomentaryAccelerator = 3 };
typedef NS_ENUM(NSInteger, NSSegmentDistribution) { NSSegmentDistributionFit = 0, NSSegmentDistributionFill, NSSegmentDistributionFillEqually,
    NSSegmentDistributionFillProportionally };
typedef NS_ENUM(NSInteger, NSSegmentStyle) { NSSegmentStyleAutomatic = 0, NSSegmentStyleRounded = 1, NSSegmentStyleTexturedRounded = 2,
    NSSegmentStyleRoundRect = 3, NSSegmentStyleTexturedSquare = 4, NSSegmentStyleCapsule = 5, NSSegmentStyleSmallSquare = 6, NSSegmentStyleSeparated = 8 };
typedef NS_ENUM(NSUInteger, NSButtonType) { NSButtonTypeMomentaryLight = 0, NSButtonTypePushOnPushOff = 1, NSButtonTypeToggle = 2,
    NSButtonTypeSwitch = 3, NSButtonTypeRadio = 4, NSButtonTypeMomentaryChange = 5, NSButtonTypeOnOff = 6, NSButtonTypeMomentaryPushIn = 7,
    NSButtonTypeAccelerator = 8, NSButtonTypeMultiLevelAccelerator = 9 };
enum { NSSwitchButton = 3, NSRadioButton = 4, NSMomentaryPushInButton = 7 };
typedef NS_ENUM(NSUInteger, NSBezelStyle) { NSBezelStyleRounded = 1, NSBezelStylePush = 1, NSBezelStyleRegularSquare = 2,
    NSBezelStyleDisclosure = 5, NSBezelStyleShadowlessSquare = 6, NSBezelStyleCircular = 7, NSBezelStyleTexturedSquare = 8,
    NSBezelStyleHelpButton = 9, NSBezelStyleSmallSquare = 10, NSBezelStyleTexturedRounded = 11, NSBezelStyleRoundRect = 12,
    NSBezelStyleRecessed = 13, NSBezelStyleRoundedDisclosure = 14, NSBezelStyleInline = 15 };
typedef NS_ENUM(NSUInteger, NSProgressIndicatorStyle) { NSProgressIndicatorStyleBar = 0, NSProgressIndicatorStyleSpinning = 1 };
typedef NS_ENUM(NSUInteger, NSAlertStyle) { NSAlertStyleWarning = 0, NSAlertStyleInformational = 1, NSAlertStyleCritical = 2 };
typedef NSInteger NSModalResponse;
static const NSModalResponse NSModalResponseOK = 1, NSModalResponseCancel = 0, NSModalResponseStop = -1000, NSModalResponseAbort = -1001,
    NSModalResponseContinue = -1002, NSAlertFirstButtonReturn = 1000, NSAlertSecondButtonReturn = 1001, NSAlertThirdButtonReturn = 1002;
enum { NSOKButton = 1, NSCancelButton = 0, NSFileHandlingPanelOKButton = 1, NSFileHandlingPanelCancelButton = 0 };
typedef NS_ENUM(NSInteger, NSVisualEffectMaterial) { NSVisualEffectMaterialTitlebar = 3, NSVisualEffectMaterialSelection = 4,
    NSVisualEffectMaterialMenu = 5, NSVisualEffectMaterialPopover = 6, NSVisualEffectMaterialSidebar = 7, NSVisualEffectMaterialHeaderView = 10,
    NSVisualEffectMaterialSheet = 11, NSVisualEffectMaterialWindowBackground = 12, NSVisualEffectMaterialHUDWindow = 13,
    NSVisualEffectMaterialFullScreenUI = 15, NSVisualEffectMaterialToolTip = 17, NSVisualEffectMaterialContentBackground = 18,
    NSVisualEffectMaterialUnderWindowBackground = 21, NSVisualEffectMaterialUnderPageBackground = 22, NSVisualEffectMaterialDark = 2,
    NSVisualEffectMaterialLight = 8, NSVisualEffectMaterialAppearanceBased = 0 };
typedef NS_ENUM(NSInteger, NSVisualEffectBlendingMode) { NSVisualEffectBlendingModeBehindWindow = 0, NSVisualEffectBlendingModeWithinWindow = 1 };
typedef NS_ENUM(NSInteger, NSVisualEffectState) { NSVisualEffectStateFollowsWindowActiveState = 0, NSVisualEffectStateActive, NSVisualEffectStateInactive };
typedef NS_ENUM(NSUInteger, NSBorderType) { NSNoBorder = 0, NSLineBorder = 1, NSBezelBorder = 2, NSGrooveBorder = 3 };
typedef NS_ENUM(NSUInteger, NSBoxType) { NSBoxPrimary = 0, NSBoxSeparator = 2, NSBoxCustom = 4 };
typedef NS_ENUM(NSUInteger, NSTitlePosition) { NSNoTitle = 0, NSAboveTop, NSAtTop, NSBelowTop, NSAboveBottom, NSAtBottom, NSBelowBottom };
typedef NS_ENUM(NSUInteger, NSBitmapImageFileType) { NSBitmapImageFileTypeTIFF = 0, NSBitmapImageFileTypeBMP, NSBitmapImageFileTypeGIF,
    NSBitmapImageFileTypeJPEG, NSBitmapImageFileTypePNG, NSBitmapImageFileTypeJPEG2000 };
typedef NS_ENUM(NSUInteger, NSCompositingOperation) { NSCompositingOperationClear = 0, NSCompositingOperationCopy = 1, NSCompositingOperationSourceOver = 2,
    NSCompositingOperationSourceIn, NSCompositingOperationSourceOut, NSCompositingOperationSourceAtop, NSCompositingOperationDestinationOver,
    NSCompositingOperationDestinationIn, NSCompositingOperationDestinationOut, NSCompositingOperationDestinationAtop, NSCompositingOperationXOR,
    NSCompositingOperationPlusDarker, NSCompositingOperationHighlight, NSCompositingOperationPlusLighter, NSCompositingOperationMultiply,
    NSCompositingOperationScreen, NSCompositingOperationOverlay, NSCompositingOperationDarken, NSCompositingOperationLighten,
    NSCompositingOperationColorDodge, NSCompositingOperationColorBurn, NSCompositingOperationSoftLight, NSCompositingOperationHardLight,
    NSCompositingOperationDifference, NSCompositingOperationExclusion, NSCompositingOperationHue, NSCompositingOperationSaturation,
    NSCompositingOperationColor, NSCompositingOperationLuminosity };
enum { NSCompositeClear = 0, NSCompositeCopy = 1, NSCompositeSourceOver = 2, NSCompositeSourceIn, NSCompositeSourceOut, NSCompositeSourceAtop, NSCompositeDestinationOver,
       NSCompositeDestinationIn, NSCompositeDestinationOut, NSCompositeDestinationAtop, NSCompositeXOR, NSCompositePlusDarker, NSCompositeHighlight, NSCompositePlusLighter };
typedef NS_ENUM(NSUInteger, NSLineJoinStyle) { NSLineJoinStyleMiter = 0, NSLineJoinStyleRound = 1, NSLineJoinStyleBevel = 2 };
typedef NS_ENUM(NSUInteger, NSLineCapStyle) { NSLineCapStyleButt = 0, NSLineCapStyleRound = 1, NSLineCapStyleSquare = 2 };
typedef NS_ENUM(NSUInteger, NSWindingRule) { NSWindingRuleNonZero = 0, NSWindingRuleEvenOdd = 1 };
typedef NS_ENUM(NSUInteger, NSImageInterpolation) { NSImageInterpolationDefault = 0, NSImageInterpolationNone = 1, NSImageInterpolationLow = 2,
    NSImageInterpolationMedium = 4, NSImageInterpolationHigh = 3 };
typedef NS_OPTIONS(NSInteger, NSStringDrawingOptions) { NSStringDrawingUsesLineFragmentOrigin = 1, NSStringDrawingUsesFontLeading = 2,
    NSStringDrawingUsesDeviceMetrics = 8, NSStringDrawingTruncatesLastVisibleLine = 32 };
typedef NS_OPTIONS(NSUInteger, NSBitmapFormat) { NSBitmapFormatAlphaFirst = 1, NSBitmapFormatAlphaNonpremultiplied = 2, NSBitmapFormatFloatingPointSamples = 4 };
typedef NS_ENUM(NSUInteger, NSCellImagePosition) { NSNoImage = 0, NSImageOnly, NSImageLeft, NSImageRight, NSImageBelow, NSImageAbove, NSImageOverlaps,
    NSImageLeading, NSImageTrailing };
typedef NSPoint *NSPointArray;
typedef NS_ENUM(NSUInteger, NSImageScaling) { NSImageScaleProportionallyDown = 0, NSImageScaleAxesIndependently, NSImageScaleNone,
    NSImageScaleProportionallyUpOrDown };
typedef NS_ENUM(NSUInteger, NSFocusRingType) { NSFocusRingTypeDefault = 0, NSFocusRingTypeNone = 1, NSFocusRingTypeExterior = 2 };
typedef NS_ENUM(NSUInteger, NSWindowNumberListOptions) { NSWindowNumberListAllApplications = 1 << 0 };
typedef NSUInteger NSDragOperation;
typedef CGFloat NSFontWeight;
APPKIT_EXTERN const NSFontWeight NSFontWeightUltraLight, NSFontWeightThin, NSFontWeightLight, NSFontWeightRegular, NSFontWeightMedium,
    NSFontWeightSemibold, NSFontWeightBold, NSFontWeightHeavy, NSFontWeightBlack;
typedef NSString *NSAppearanceName;
APPKIT_EXTERN NSAppearanceName const NSAppearanceNameAqua, NSAppearanceNameDarkAqua, NSAppearanceNameVibrantLight, NSAppearanceNameVibrantDark;
typedef NSString *NSPasteboardType;
APPKIT_EXTERN NSPasteboardType const NSPasteboardTypeString, NSPasteboardTypeURL, NSPasteboardTypeFileURL, NSPasteboardTypePNG, NSStringPboardType;
APPKIT_EXTERN NSAttributedStringKey const NSFontAttributeName NS_SWIFT_NAME(font);
APPKIT_EXTERN NSAttributedStringKey const NSForegroundColorAttributeName NS_SWIFT_NAME(foregroundColor);
APPKIT_EXTERN NSAttributedStringKey const NSBackgroundColorAttributeName NS_SWIFT_NAME(backgroundColor);
APPKIT_EXTERN NSAttributedStringKey const NSParagraphStyleAttributeName NS_SWIFT_NAME(paragraphStyle);
APPKIT_EXTERN NSAttributedStringKey const NSLinkAttributeName NS_SWIFT_NAME(link);
APPKIT_EXTERN NSAttributedStringKey const NSBaselineOffsetAttributeName NS_SWIFT_NAME(baselineOffset);
typedef NSString *NSRunLoopModeAppKit;
APPKIT_EXTERN NSString *const NSModalPanelRunLoopMode, *const NSEventTrackingRunLoopMode;
typedef NSString *NSDeviceDescriptionKey;
APPKIT_EXTERN NSDeviceDescriptionKey const NSDeviceResolution, NSDeviceSize, NSDeviceIsScreen, NSDeviceColorSpaceName;
typedef NSString *NSUserInterfaceItemIdentifier;
typedef NSString *NSImageName;
APPKIT_EXTERN NSImageName const NSImageNameApplicationIcon, NSImageNameCaution, NSImageNameInfo;

/* ============================================================================================ notifications */
APPKIT_EXTERN NSNotificationName const NSApplicationWillFinishLaunchingNotification, NSApplicationDidFinishLaunchingNotification,
    NSApplicationWillTerminateNotification, NSApplicationDidBecomeActiveNotification, NSApplicationDidResignActiveNotification,
    NSApplicationWillBecomeActiveNotification, NSApplicationWillResignActiveNotification, NSApplicationDidHideNotification,
    NSApplicationDidUnhideNotification, NSApplicationDidChangeScreenParametersNotification, NSApplicationDidUpdateNotification,
    NSApplicationWillUpdateNotification, NSApplicationDidChangeOcclusionStateNotification;
APPKIT_EXTERN NSNotificationName const NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification, NSWindowDidBecomeMainNotification,
    NSWindowDidResignMainNotification, NSWindowWillCloseNotification, NSWindowDidResizeNotification, NSWindowWillStartLiveResizeNotification,
    NSWindowDidEndLiveResizeNotification, NSWindowDidMoveNotification, NSWindowWillMoveNotification, NSWindowDidMiniaturizeNotification,
    NSWindowWillMiniaturizeNotification, NSWindowDidDeminiaturizeNotification, NSWindowWillEnterFullScreenNotification,
    NSWindowDidEnterFullScreenNotification, NSWindowWillExitFullScreenNotification, NSWindowDidExitFullScreenNotification,
    NSWindowDidChangeBackingPropertiesNotification, NSWindowDidChangeScreenNotification, NSWindowDidChangeOcclusionStateNotification,
    NSWindowDidExposeNotification, NSWindowDidUpdateNotification;
APPKIT_EXTERN NSNotificationName const NSViewFrameDidChangeNotification, NSViewBoundsDidChangeNotification,
    NSViewGlobalFrameDidChangeNotification, NSControlTextDidChangeNotification, NSControlTextDidBeginEditingNotification,
    NSControlTextDidEndEditingNotification, NSMenuDidSendActionNotification, NSMenuWillSendActionNotification,
    NSWorkspaceDidActivateApplicationNotification, NSWorkspaceWillSleepNotification, NSWorkspaceDidWakeNotification,
    NSWorkspaceScreensDidSleepNotification, NSWorkspaceScreensDidWakeNotification, NSSystemColorsDidChangeNotification;

/* ============================================================================================ protocols */
@protocol NSUserInterfaceValidations - (BOOL)validateUserInterfaceItem:(nullable id)item; @end
@protocol NSMenuItemValidation <NSObject> - (BOOL)validateMenuItem:(NSMenuItem *)item; @end
@protocol NSAnimatablePropertyContainer - (instancetype)animator; @end
@protocol NSAppearanceCustomization <NSObject>
@property(nullable, retain) NSAppearance *appearance;
@property(readonly) NSAppearance *effectiveAppearance;
@end
@protocol NSApplicationDelegate <NSObject>
@optional
- (void)applicationWillFinishLaunching:(NSNotification *)n;
- (void)applicationDidFinishLaunching:(NSNotification *)n;
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app;
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app;
- (void)applicationWillTerminate:(NSNotification *)n;
- (void)applicationDidBecomeActive:(NSNotification *)n;
- (void)applicationDidResignActive:(NSNotification *)n;
- (void)applicationWillBecomeActive:(NSNotification *)n;
- (void)applicationWillResignActive:(NSNotification *)n;
- (void)applicationDidHide:(NSNotification *)n;
- (void)applicationDidUnhide:(NSNotification *)n;
- (void)applicationDidChangeScreenParameters:(NSNotification *)n;
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)flag;
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app;
- (BOOL)application:(NSApplication *)app openFile:(NSString *)file;
- (void)application:(NSApplication *)app openURLs:(NSArray *)urls;
- (NSMenu *)applicationDockMenu:(NSApplication *)app;
@end
@protocol NSWindowDelegate <NSObject>
@optional
- (BOOL)windowShouldClose:(NSWindow *)w;
- (void)windowWillClose:(NSNotification *)n;
- (void)windowDidBecomeKey:(NSNotification *)n;
- (void)windowDidResignKey:(NSNotification *)n;
- (void)windowDidBecomeMain:(NSNotification *)n;
- (void)windowDidResignMain:(NSNotification *)n;
- (NSSize)windowWillResize:(NSWindow *)w toSize:(NSSize)s;
- (void)windowDidResize:(NSNotification *)n;
- (void)windowWillStartLiveResize:(NSNotification *)n;
- (void)windowDidEndLiveResize:(NSNotification *)n;
- (void)windowDidMove:(NSNotification *)n;
- (void)windowWillMiniaturize:(NSNotification *)n;
- (void)windowDidMiniaturize:(NSNotification *)n;
- (void)windowDidDeminiaturize:(NSNotification *)n;
- (void)windowWillEnterFullScreen:(NSNotification *)n;
- (void)windowDidEnterFullScreen:(NSNotification *)n;
- (void)windowWillExitFullScreen:(NSNotification *)n;
- (void)windowDidExitFullScreen:(NSNotification *)n;
- (NSSize)window:(NSWindow *)w willUseFullScreenContentSize:(NSSize)s;
- (NSApplicationPresentationOptions)window:(NSWindow *)w willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)o;
- (void)windowDidChangeBackingProperties:(NSNotification *)n;
- (void)windowDidChangeScreen:(NSNotification *)n;
- (void)windowDidChangeOcclusionState:(NSNotification *)n;
- (void)windowDidExpose:(NSNotification *)n;
- (void)windowDidUpdate:(NSNotification *)n;
@end
@protocol NSMenuDelegate <NSObject>
@optional
- (void)menuNeedsUpdate:(NSMenu *)m;
- (void)menuWillOpen:(NSMenu *)m;
- (void)menuDidClose:(NSMenu *)m;
@end
@protocol NSTextInputClient
@optional
- (void)insertText:(nullable id)s replacementRange:(NSRange)r;
- (void)doCommandBySelector:(nullable SEL)s;
- (void)setMarkedText:(nullable id)s selectedRange:(NSRange)sel replacementRange:(NSRange)r;
- (void)unmarkText;
- (NSRange)selectedRange; - (NSRange)markedRange; - (BOOL)hasMarkedText;
- (NSArray *)validAttributesForMarkedText;
- (NSRect)firstRectForCharacterRange:(NSRange)r actualRange:(NSRangePointer)a;
- (NSUInteger)characterIndexForPoint:(NSPoint)p;
@end
@protocol NSControlTextEditingDelegate <NSObject> @optional - (void)controlTextDidChange:(NSNotification *)n; - (void)controlTextDidEndEditing:(NSNotification *)n; @end
@protocol NSTextFieldDelegate <NSControlTextEditingDelegate> @end
@protocol NSStackViewDelegate <NSObject> @end
@protocol NSDraggingInfo <NSObject> @end
@protocol NSDraggingDestination <NSObject> @end

/* ============================================================================================ NSResponder */
@interface NSResponder : NSObject
@property(nullable, assign) NSResponder *nextResponder;
@property(readonly) BOOL acceptsFirstResponder;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;
- (void)mouseDown:(NSEvent *)event NS_SWIFT_NAME(mouseDown(with:)); - (void)mouseUp:(NSEvent *)event NS_SWIFT_NAME(mouseUp(with:)); - (void)mouseDragged:(NSEvent *)event NS_SWIFT_NAME(mouseDragged(with:)); - (void)mouseMoved:(NSEvent *)event NS_SWIFT_NAME(mouseMoved(with:));
- (void)rightMouseDown:(NSEvent *)event NS_SWIFT_NAME(rightMouseDown(with:)); - (void)rightMouseUp:(NSEvent *)event NS_SWIFT_NAME(rightMouseUp(with:)); - (void)rightMouseDragged:(NSEvent *)event NS_SWIFT_NAME(rightMouseDragged(with:));
- (void)otherMouseDown:(NSEvent *)event NS_SWIFT_NAME(otherMouseDown(with:)); - (void)otherMouseUp:(NSEvent *)event NS_SWIFT_NAME(otherMouseUp(with:)); - (void)otherMouseDragged:(NSEvent *)event NS_SWIFT_NAME(otherMouseDragged(with:));
- (void)mouseEntered:(NSEvent *)event NS_SWIFT_NAME(mouseEntered(with:)); - (void)mouseExited:(NSEvent *)event NS_SWIFT_NAME(mouseExited(with:)); - (void)scrollWheel:(NSEvent *)event NS_SWIFT_NAME(scrollWheel(with:));
- (void)keyDown:(NSEvent *)event NS_SWIFT_NAME(keyDown(with:)); - (void)keyUp:(NSEvent *)event NS_SWIFT_NAME(keyUp(with:)); - (void)flagsChanged:(NSEvent *)event NS_SWIFT_NAME(flagsChanged(with:)); - (void)cursorUpdate:(NSEvent *)event NS_SWIFT_NAME(cursorUpdate(with:));
- (void)magnifyWithEvent:(NSEvent *)event; - (void)rotateWithEvent:(NSEvent *)event; - (void)swipeWithEvent:(NSEvent *)event;
- (void)pressureChangeWithEvent:(NSEvent *)event;
- (BOOL)performKeyEquivalent:(NSEvent *)event NS_SWIFT_NAME(performKeyEquivalent(with:));
- (void)interpretKeyEvents:(NSArray *)events;
- (void)insertText:(nullable id)s;
- (void)doCommandBySelector:(nullable SEL)s;
- (void)noResponderFor:(nullable SEL)s;
- (BOOL)tryToPerform:(nullable SEL)s with:(nullable id)o;
- (id)validRequestorForSendType:(NSPasteboardType)s returnType:(NSPasteboardType)r;
- (BOOL)presentError:(NSError *)e;
- (void)flushBufferedKeyEvents;
- (NSMenu *)menu; - (void)setMenu:(NSMenu *)m;
@end

/* ============================================================================================ NSEvent */
@interface NSEvent : NSObject <NSCopying>
@property(readonly) NSEventType type;
@property(readonly) NSEventModifierFlags modifierFlags;
@property(readonly) NSTimeInterval timestamp;
@property(nullable, readonly, assign) NSWindow *window;
@property(readonly) NSInteger windowNumber;
@property(readonly) NSPoint locationInWindow;
@property(readonly) NSInteger buttonNumber, clickCount;
@property(readonly) float pressure;
@property(readonly) CGFloat deltaX, deltaY, deltaZ, scrollingDeltaX, scrollingDeltaY, magnification, rotation;
@property(readonly) BOOL hasPreciseScrollingDeltas;
@property(readonly, getter=isDirectionInvertedFromDevice) BOOL directionInvertedFromDevice;
@property(readonly) NSEventPhase phase, momentumPhase;
@property(readonly) unsigned short keyCode;
@property(nullable, readonly, copy) NSString *characters, *charactersIgnoringModifiers;
@property(readonly, getter=isARepeat) BOOL ARepeat;
@property(readonly) NSEventSubtype subtype;
@property(readonly) NSInteger data1, data2;
@property(readonly) NSInteger eventNumber, trackingNumber;
@property(readonly) NSTrackingArea *trackingArea;
@property(readonly) void *userData;
@property(readonly) void *CGEvent;
@property(class, readonly) NSPoint mouseLocation;
@property(class, readonly) NSEventModifierFlags modifierFlags;
@property(class, readonly) NSUInteger pressedMouseButtons;
@property(class, readonly) NSTimeInterval doubleClickInterval, keyRepeatDelay, keyRepeatInterval;
@property(class, getter=isMouseCoalescingEnabled) BOOL mouseCoalescingEnabled;
+ (id)addLocalMonitorForEventsMatchingMask:(NSEventMask)mask handler:(NSEvent * (^)(NSEvent *e))handler;
+ (id)addGlobalMonitorForEventsMatchingMask:(NSEventMask)mask handler:(void (^ _Nullable)(NSEvent *e))handler;
+ (void)removeMonitor:(nullable id)monitor;
+ (NSEvent *)keyEventWithType:(NSEventType)t location:(NSPoint)p modifierFlags:(NSEventModifierFlags)f timestamp:(NSTimeInterval)ts
    windowNumber:(NSInteger)w context:(id)c characters:(NSString *)ch charactersIgnoringModifiers:(NSString *)chn isARepeat:(BOOL)r keyCode:(unsigned short)k;
+ (NSEvent *)mouseEventWithType:(NSEventType)t location:(NSPoint)p modifierFlags:(NSEventModifierFlags)f timestamp:(NSTimeInterval)ts
    windowNumber:(NSInteger)w context:(id)c eventNumber:(NSInteger)n clickCount:(NSInteger)cc pressure:(float)pr;
+ (NSEvent *)otherEventWithType:(NSEventType)t location:(NSPoint)p modifierFlags:(NSEventModifierFlags)f timestamp:(NSTimeInterval)ts
    windowNumber:(NSInteger)w context:(id)c subtype:(short)s data1:(NSInteger)d1 data2:(NSInteger)d2;
+ (void)startPeriodicEventsAfterDelay:(NSTimeInterval)d withPeriod:(NSTimeInterval)p;
+ (void)stopPeriodicEvents;
@end

/* ============================================================================================ NSScreen */
@interface NSScreen : NSObject
@property(class, readonly) NSScreen *mainScreen, *deepestScreen;
@property(class, readonly) NSArray<NSScreen *> *screens;
@property(class, readonly) BOOL screensHaveSeparateSpaces;
@property(readonly) NSRect frame, visibleFrame;
@property(readonly) CGFloat backingScaleFactor;
@property(readonly, copy) NSDictionary *deviceDescription;
@property(readonly, copy) NSString *localizedName;
@property(readonly) NSInteger maximumFramesPerSecond;
@property(readonly) NSTimeInterval minimumRefreshInterval, maximumRefreshInterval, displayUpdateGranularity;
@property(readonly) NSEdgeInsets safeAreaInsets;
@property(readonly) CGFloat maximumExtendedDynamicRangeColorComponentValue, maximumPotentialExtendedDynamicRangeColorComponentValue;
- (NSRect)convertRectToBacking:(NSRect)r; - (NSRect)convertRectFromBacking:(NSRect)r;
- (CGFloat)backingAlignedRect:(NSRect)r options:(NSAlignmentOptions)o;
@end

/* ============================================================================================ NSCursor */
@interface NSCursor : NSObject
@property(class, readonly) NSCursor *arrowCursor, *IBeamCursor, *pointingHandCursor, *closedHandCursor, *openHandCursor, *crosshairCursor,
    *resizeLeftRightCursor, *resizeUpDownCursor, *resizeLeftCursor, *resizeRightCursor, *resizeUpCursor, *resizeDownCursor,
    *operationNotAllowedCursor, *disappearingItemCursor, *dragCopyCursor, *dragLinkCursor, *contextualMenuCursor, *currentCursor,
    *currentSystemCursor;
- (instancetype)initWithImage:(NSImage *)i hotSpot:(NSPoint)p;
@property(nullable, readonly) NSImage *image;
@property(readonly) NSPoint hotSpot;
+ (void)hide; + (void)unhide; + (void)setHiddenUntilMouseMoves:(BOOL)f; + (void)pop;
- (void)set; - (void)push; - (void)pop;
@end

/* ============================================================================================ NSView */
@interface NSView : NSResponder <NSAppearanceCustomization, NSAnimatablePropertyContainer>
/* NSAccessibility (stored, nothing reads it yet) */
@property(copy) NSString *accessibilityLabel, *accessibilityIdentifier, *accessibilityHelp, *accessibilityTitle;
@property(retain) id accessibilityValue;
@property(getter=isAccessibilityElement) BOOL accessibilityElement;
- (instancetype)initWithFrame:(NSRect)r;
- (instancetype)initWithCoder:(NSCoder *)c;
@property NSRect frame, bounds;
@property(nullable, readonly, assign) NSWindow *window;
@property(nullable, readonly, assign) NSView *superview;
@property(copy) NSArray<NSView *> *subviews;
@property(getter=isHidden) BOOL hidden;
@property(readonly, getter=isHiddenOrHasHiddenAncestor) BOOL hiddenOrHasHiddenAncestor;
@property(readonly, getter=isFlipped) BOOL flipped;
@property(readonly, getter=isOpaque) BOOL opaque;
@property BOOL wantsLayer, autoresizesSubviews, needsDisplay, needsLayout, postsFrameChangedNotifications, postsBoundsChangedNotifications,
    canDrawConcurrently, translatesAutoresizingMaskIntoConstraints, wantsRestingTouches, acceptsTouchEvents, clipsToBounds;
@property(readonly) BOOL wantsUpdateLayer, inLiveResize, canBecomeKeyView, needsPanelToBecomeKey, mouseDownCanMoveWindow;
@property(nullable, retain) CALayer *layer;
@property NSAutoresizingMaskOptions autoresizingMask;
@property NSViewLayerContentsRedrawPolicy layerContentsRedrawPolicy;
@property NSViewLayerContentsPlacement layerContentsPlacement;
@property CGFloat alphaValue, frameRotation, frameCenterRotation, boundsRotation;
@property NSInteger tag;
@property(copy) NSUserInterfaceItemIdentifier identifier;
@property(nullable, copy) NSString *toolTip;
@property(nullable, retain) NSAppearance *appearance;
@property(readonly) NSAppearance *effectiveAppearance;
@property NSFocusRingType focusRingType;
@property(readonly) NSRect visibleRect;
@property(readonly) NSSize intrinsicContentSize, fittingSize;
@property(readonly) NSEdgeInsets safeAreaInsets; @property NSEdgeInsets additionalSafeAreaInsets; @property(readonly) NSRect safeAreaRect;
@property(readonly, copy) NSArray<NSTrackingArea *> *trackingAreas;
@property(readonly, copy) NSArray<NSLayoutConstraint *> *constraints;
@property(readonly) NSLayoutXAxisAnchor *leadingAnchor, *trailingAnchor, *leftAnchor, *rightAnchor, *centerXAnchor;
@property(readonly) NSLayoutYAxisAnchor *topAnchor, *bottomAnchor, *centerYAnchor, *firstBaselineAnchor, *lastBaselineAnchor;
@property(readonly) NSLayoutDimension *widthAnchor, *heightAnchor;
@property(readonly) CGFloat firstBaselineOffsetFromTop, lastBaselineOffsetFromBottom, baselineOffsetFromBottom;
@property(readonly) NSUserInterfaceLayoutDirection userInterfaceLayoutDirection;
@property(assign) NSView *nextKeyView;
@property(nullable, readonly, retain) NSViewController *viewController;
- (void)setFrameOrigin:(NSPoint)p; - (void)setFrameSize:(NSSize)s;
- (void)setBoundsOrigin:(NSPoint)p; - (void)setBoundsSize:(NSSize)s;
- (void)addSubview:(NSView *)v;
- (void)addSubview:(NSView *)v positioned:(NSWindowOrderingMode)place relativeTo:(nullable NSView *)other;
- (void)removeFromSuperview;
- (void)replaceSubview:(NSView *)old with:(NSView *)v;
- (void)sortSubviewsUsingFunction:(NSComparisonResult (*)(id, id, void *))f context:(void *)c;
- (BOOL)isDescendantOf:(NSView *)v;
- (NSView *)ancestorSharedWithView:(NSView *)v;
- (nullable __kindof NSView *)viewWithTag:(NSInteger)t;
- (void)viewWillMoveToWindow:(NSWindow *)w; - (void)viewDidMoveToWindow;
- (void)viewWillMoveToSuperview:(NSView *)v; - (void)viewDidMoveToSuperview;
- (void)didAddSubview:(NSView *)v; - (void)willRemoveSubview:(NSView *)v;
- (void)viewDidChangeBackingProperties; - (void)viewDidChangeEffectiveAppearance; - (void)viewDidHide; - (void)viewDidUnhide;
- (void)viewWillStartLiveResize; - (void)viewDidEndLiveResize;
- (void)resizeSubviewsWithOldSize:(NSSize)s; - (void)resizeWithOldSuperviewSize:(NSSize)s;
- (CALayer *)makeBackingLayer;
- (void)updateLayer;
- (void)drawRect:(NSRect)r;
- (void)setNeedsDisplayInRect:(NSRect)r;
- (void)display; - (void)displayIfNeeded; - (void)displayRect:(NSRect)r;
- (void)lockFocus; - (void)unlockFocus;
- (void)layout; - (void)layoutSubtreeIfNeeded; - (void)updateConstraints; - (void)updateConstraintsForSubtreeIfNeeded;
- (void)setNeedsUpdateConstraints:(BOOL)f;
- (void)addConstraint:(NSLayoutConstraint *)c; - (void)addConstraints:(NSArray *)c;
- (void)removeConstraint:(NSLayoutConstraint *)c; - (void)removeConstraints:(NSArray *)c;
- (NSLayoutPriority)contentHuggingPriorityForOrientation:(NSLayoutConstraintOrientation)o;
- (void)setContentHuggingPriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o;
- (NSLayoutPriority)contentCompressionResistancePriorityForOrientation:(NSLayoutConstraintOrientation)o;
- (void)setContentCompressionResistancePriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o;
- (void)invalidateIntrinsicContentSize;
- (NSPoint)convertPoint:(NSPoint)p fromView:(nullable NSView *)v; - (NSPoint)convertPoint:(NSPoint)p toView:(nullable NSView *)v;
- (NSSize)convertSize:(NSSize)s fromView:(nullable NSView *)v; - (NSSize)convertSize:(NSSize)s toView:(nullable NSView *)v;
- (NSRect)convertRect:(NSRect)r fromView:(nullable NSView *)v; - (NSRect)convertRect:(NSRect)r toView:(nullable NSView *)v;
- (NSRect)convertRectToBacking:(NSRect)r; - (NSRect)convertRectFromBacking:(NSRect)r;
- (NSSize)convertSizeToBacking:(NSSize)s; - (NSSize)convertSizeFromBacking:(NSSize)s;
- (NSPoint)convertPointToBacking:(NSPoint)p; - (NSPoint)convertPointFromBacking:(NSPoint)p;
- (NSRect)backingAlignedRect:(NSRect)r options:(NSAlignmentOptions)o;
- (nullable NSView *)hitTest:(NSPoint)p;
- (BOOL)mouse:(NSPoint)p inRect:(NSRect)r;
- (BOOL)acceptsFirstMouse:(NSEvent *)event NS_SWIFT_NAME(acceptsFirstMouse(for:));
- (nullable NSMenu *)menuForEvent:(NSEvent *)event NS_SWIFT_NAME(menu(for:));
- (void)addTrackingArea:(NSTrackingArea *)a; - (void)removeTrackingArea:(NSTrackingArea *)a; - (void)updateTrackingAreas;
- (void)addCursorRect:(NSRect)r cursor:(NSCursor *)c; - (void)removeCursorRect:(NSRect)r cursor:(NSCursor *)c;
- (void)discardCursorRects; - (void)resetCursorRects;
- (BOOL)enterFullScreenMode:(NSScreen *)s withOptions:(NSDictionary *)o; - (void)exitFullScreenModeWithOptions:(NSDictionary *)o;
@property(readonly, getter=isInFullScreenMode) BOOL inFullScreenMode;
- (void)scrollPoint:(NSPoint)p; - (BOOL)scrollRectToVisible:(NSRect)r;
- (NSBitmapImageRep *)bitmapImageRepForCachingDisplayInRect:(NSRect)r;
- (void)cacheDisplayInRect:(NSRect)r toBitmapImageRep:(NSBitmapImageRep *)b;
- (instancetype)animator;
- (void)registerForDraggedTypes:(NSArray *)t; - (void)unregisterDraggedTypes;
@end

/* ============================================================================================ NSWindow */
@interface NSWindow : NSResponder <NSAppearanceCustomization, NSAnimatablePropertyContainer, NSUserInterfaceValidations>
- (instancetype)initWithContentRect:(NSRect)r styleMask:(NSWindowStyleMask)s backing:(NSBackingStoreType)b defer:(BOOL)d;
- (instancetype)initWithContentRect:(NSRect)r styleMask:(NSWindowStyleMask)s backing:(NSBackingStoreType)b defer:(BOOL)d screen:(NSScreen *)sc;
+ (instancetype)windowWithContentViewController:(NSViewController *)vc;
+ (NSRect)frameRectForContentRect:(NSRect)r styleMask:(NSWindowStyleMask)s;
+ (NSRect)contentRectForFrameRect:(NSRect)r styleMask:(NSWindowStyleMask)s;
@property(class) BOOL allowsAutomaticWindowTabbing;
@property(copy) NSString *title, *subtitle, *representedFilename;
@property(nullable, readonly, copy) NSString *frameAutosaveName;
@property(copy) NSURL *representedURL;
@property(nullable, retain) __kindof NSView *contentView;
@property(nullable, retain) NSViewController *contentViewController;
@property(assign) id<NSWindowDelegate> delegate;
@property NSWindowStyleMask styleMask;
@property(readonly) NSRect frame;
@property(readonly) NSRect contentLayoutRect;
@property NSSize contentAspectRatio, contentMinSize, contentMaxSize, minSize, maxSize, aspectRatio, resizeIncrements, contentResizeIncrements;
@property NSWindowCollectionBehavior collectionBehavior;
@property NSWindowLevel level;
@property(readonly) NSInteger windowNumber;
@property(readonly) CGFloat backingScaleFactor;
@property(readonly, retain) NSScreen *screen, *deepestScreen;
@property(readonly, getter=isKeyWindow) BOOL keyWindow;
@property(readonly, getter=isMainWindow) BOOL mainWindow;
@property(readonly, getter=isVisible) BOOL visible;
@property(readonly, getter=isMiniaturized) BOOL miniaturized;
@property(readonly, getter=isZoomed) BOOL zoomed;
@property(readonly) BOOL canBecomeKeyWindow, canBecomeMainWindow, isOnActiveSpace, isSheet, inLiveResize;
@property(readonly) NSWindowOcclusionState occlusionState;
@property(nullable, readonly, assign) NSResponder *firstResponder;
@property(retain) NSColor *backgroundColor;
@property(getter=isOpaque) BOOL opaque;
@property(getter=isReleasedWhenClosed) BOOL releasedWhenClosed;
@property(getter=isMovableByWindowBackground) BOOL movableByWindowBackground;
@property(getter=isMovable) BOOL movable;
@property(getter=isRestorable) BOOL restorable;
@property(getter=isExcludedFromWindowsMenu) BOOL excludedFromWindowsMenu;
@property(getter=isDocumentEdited) BOOL documentEdited;
@property BOOL hasShadow, acceptsMouseMovedEvents, ignoresMouseEvents, titlebarAppearsTransparent, hidesOnDeactivate, preservesContentDuringLiveResize,
    showsResizeIndicator, allowsConcurrentViewDrawing, displaysWhenScreenProfileChanges, canHide, worksWhenModal, autorecalculatesKeyViewLoop;
@property CGFloat alphaValue;
@property NSWindowTitleVisibility titleVisibility;
@property NSWindowTabbingMode tabbingMode;
@property NSWindowAnimationBehavior animationBehavior;
@property NSWindowToolbarStyle toolbarStyle;
@property(nullable, assign) NSWindowController *windowController;
@property(retain) id toolbar;
@property(nullable, retain) NSAppearance *appearance;
@property(readonly) NSAppearance *effectiveAppearance;
@property(nullable, readonly, assign) NSWindow *parentWindow, *sheetParent, *attachedSheet;
@property(readonly, copy) NSArray<NSWindow *> *childWindows, *sheets;
@property(assign) NSView *initialFirstResponder;
@property(readonly) NSPoint mouseLocationOutsideOfEventStream;
@property(nullable, readonly, retain) NSEvent *currentEvent;
@property(retain) NSColorSpace *colorSpace;
- (void)setFrame:(NSRect)r display:(BOOL)d;
- (void)setFrame:(NSRect)r display:(BOOL)d animate:(BOOL)a;
- (void)setFrameOrigin:(NSPoint)p; - (void)setFrameTopLeftPoint:(NSPoint)p;
- (NSPoint)cascadeTopLeftFromPoint:(NSPoint)p;
- (void)setContentSize:(NSSize)s;
- (NSRect)contentRectForFrameRect:(NSRect)r; - (NSRect)frameRectForContentRect:(NSRect)r;
- (BOOL)setFrameUsingName:(NSString *)n; - (void)saveFrameUsingName:(NSString *)n; - (BOOL)setFrameAutosaveName:(NSString *)n;
- (void)center;
- (void)makeKeyAndOrderFront:(nullable id)s; - (void)orderFront:(nullable id)s; - (void)orderBack:(nullable id)s; - (void)orderOut:(nullable id)s; - (void)orderFrontRegardless;
- (void)orderWindow:(NSWindowOrderingMode)m relativeTo:(NSInteger)w;
- (void)makeKeyWindow; - (void)makeMainWindow; - (void)becomeKeyWindow; - (void)resignKeyWindow; - (void)becomeMainWindow; - (void)resignMainWindow;
- (void)setIsVisible:(BOOL)f;
- (void)close; - (void)performClose:(nullable id)s;
- (void)miniaturize:(nullable id)s; - (void)deminiaturize:(nullable id)s; - (void)performMiniaturize:(nullable id)s;
- (void)zoom:(nullable id)s; - (void)performZoom:(nullable id)s;
- (void)toggleFullScreen:(nullable id)s;
- (BOOL)makeFirstResponder:(NSResponder *)r;
- (void)sendEvent:(NSEvent *)event;
- (nullable NSEvent *)nextEventMatchingMask:(NSEventMask)m;
- (nullable NSEvent *)nextEventMatchingMask:(NSEventMask)m untilDate:(NSDate *)d inMode:(NSRunLoopMode)mode dequeue:(BOOL)dq;
- (void)postEvent:(NSEvent *)e atStart:(BOOL)f;
- (void)display; - (void)displayIfNeeded; - (void)update; - (void)disableScreenUpdatesUntilFlush; - (void)invalidateShadow;
- (void)invalidateCursorRectsForView:(NSView *)v; - (void)disableCursorRects; - (void)enableCursorRects; - (void)resetCursorRects;
- (NSRect)convertRectToBacking:(NSRect)r; - (NSRect)convertRectFromBacking:(NSRect)r;
- (NSPoint)convertPointToBacking:(NSPoint)p; - (NSPoint)convertPointFromBacking:(NSPoint)p;
- (NSRect)convertRectToScreen:(NSRect)r NS_SWIFT_NAME(convertToScreen(_:)); - (NSRect)convertRectFromScreen:(NSRect)r NS_SWIFT_NAME(convertFromScreen(_:));
- (NSPoint)convertPointToScreen:(NSPoint)p; - (NSPoint)convertPointFromScreen:(NSPoint)p;
- (NSRect)backingAlignedRect:(NSRect)r options:(NSAlignmentOptions)o;
- (NSButton *)standardWindowButton:(NSWindowButton)b;
- (void)addChildWindow:(NSWindow *)w ordered:(NSWindowOrderingMode)o; - (void)removeChildWindow:(NSWindow *)w;
- (void)beginSheet:(NSWindow *)w completionHandler:(void (^ _Nullable)(NSModalResponse r))h;
- (void)beginCriticalSheet:(NSWindow *)w completionHandler:(void (^ _Nullable)(NSModalResponse r))h;
- (void)endSheet:(NSWindow *)w; - (void)endSheet:(NSWindow *)w returnCode:(NSModalResponse)r;
- (void)selectNextKeyView:(nullable id)s; - (void)selectPreviousKeyView:(nullable id)s; - (void)recalculateKeyViewLoop;
- (void)setDynamicDepthLimit:(BOOL)f;
- (void)registerForDraggedTypes:(NSArray *)t;
- (void)trackEventsMatchingMask:(NSEventMask)m timeout:(NSTimeInterval)t mode:(NSRunLoopMode)mode handler:(void (^ _Nullable)(NSEvent *e, BOOL *stop))h;
- (CGFloat)titlebarHeight;
@end
@interface NSPanel : NSWindow
@property(getter=isFloatingPanel) BOOL floatingPanel;
@property BOOL becomesKeyOnlyIfNeeded, worksWhenModal;
@end

/* ============================================================================================ NSMenu */
@interface NSMenu : NSObject <NSCopying>
- (instancetype)initWithTitle:(NSString *)t;
@property(copy) NSString *title;
@property(nullable, readonly, assign) NSMenu *supermenu;
@property(copy) NSArray<NSMenuItem *> *itemArray NS_SWIFT_NAME(items);
@property(readonly) NSInteger numberOfItems;
@property BOOL autoenablesItems, showsStateColumn;
@property(assign) id<NSMenuDelegate> delegate;
@property(retain) NSFont *font;
@property CGFloat minimumWidth;
@property(nullable, readonly, retain) NSMenuItem *highlightedItem;
- (void)addItem:(NSMenuItem *)i NS_SWIFT_NAME(addItem(_:));
- (NSMenuItem *)addItemWithTitle:(NSString *)t action:(nullable SEL)a keyEquivalent:(NSString *)k;
- (void)insertItem:(NSMenuItem *)i atIndex:(NSInteger)n NS_SWIFT_NAME(insertItem(_:at:));
- (NSMenuItem *)insertItemWithTitle:(NSString *)t action:(nullable SEL)a keyEquivalent:(NSString *)k atIndex:(NSInteger)n;
- (void)removeItem:(NSMenuItem *)i NS_SWIFT_NAME(removeItem(_:)); - (void)removeItemAtIndex:(NSInteger)n NS_SWIFT_NAME(removeItem(at:)); - (void)removeAllItems;
- (nullable NSMenuItem *)itemAtIndex:(NSInteger)n; - (nullable NSMenuItem *)itemWithTitle:(NSString *)t; - (nullable NSMenuItem *)itemWithTag:(NSInteger)t;
- (NSInteger)indexOfItem:(NSMenuItem *)i; - (NSInteger)indexOfItemWithTitle:(NSString *)t; - (NSInteger)indexOfItemWithTag:(NSInteger)t;
- (NSInteger)indexOfItemWithSubmenu:(NSMenu *)m; - (NSInteger)indexOfItemWithTarget:(nullable id)t andAction:(nullable SEL)a;
- (void)setSubmenu:(NSMenu *)m forItem:(NSMenuItem *)i;
- (void)itemChanged:(NSMenuItem *)i;
- (void)update;
- (BOOL)performKeyEquivalent:(NSEvent *)event NS_SWIFT_NAME(performKeyEquivalent(with:));
- (void)performActionForItemAtIndex:(NSInteger)n;
- (BOOL)popUpMenuPositioningItem:(nullable NSMenuItem *)i atLocation:(NSPoint)p inView:(nullable NSView *)v NS_SWIFT_NAME(popUp(positioning:at:in:));
- (void)cancelTracking;
+ (void)popUpContextMenu:(NSMenu *)m withEvent:(NSEvent *)e forView:(NSView *)v;
+ (void)setMenuBarVisible:(BOOL)f; + (BOOL)menuBarVisible;
@end
@interface NSMenuItem : NSObject <NSCopying>
+ (NSMenuItem *)separatorItem;
+ (NSMenuItem *)sectionHeaderWithTitle:(NSString *)t;
- (instancetype)initWithTitle:(NSString *)t action:(nullable SEL)a keyEquivalent:(NSString *)k;
@property(copy) NSString *title, *keyEquivalent, *toolTip;
@property(nullable, copy) NSAttributedString *attributedTitle;
@property SEL action;
@property(assign) id target;
@property NSInteger tag, indentationLevel;
@property NSControlStateValue state;
@property(getter=isEnabled) BOOL enabled;
@property(getter=isHidden) BOOL hidden;
@property(getter=isAlternate) BOOL alternate;
@property(readonly, getter=isHiddenOrHasHiddenAncestor) BOOL hiddenOrHasHiddenAncestor;
@property(readonly, getter=isSeparatorItem) BOOL separatorItem;
@property(readonly, getter=isHighlighted) BOOL highlighted;
@property(readonly) BOOL hasSubmenu;
@property NSEventModifierFlags keyEquivalentModifierMask;
@property(nullable, retain) NSMenu *submenu;
@property(nullable, readonly, assign) NSMenu *menu;
@property(nullable, readonly, assign) NSMenuItem *parentItem;
@property(retain) id representedObject;
@property(retain) NSImage *image, *onStateImage, *offStateImage;
@property(retain) NSView *view;
@property BOOL allowsKeyEquivalentWhenHidden;
@end

/* ============================================================================================ NSApplication */
@interface NSApplication : NSResponder <NSUserInterfaceValidations, NSAppearanceCustomization>
@property(class, readonly, strong) NSApplication *sharedApplication NS_SWIFT_NAME(shared);
@property(assign) id<NSApplicationDelegate> delegate;
@property(nullable, retain) NSMenu *mainMenu, *windowsMenu, *servicesMenu, *helpMenu, *dockMenu;
@property(readonly, copy) NSArray<NSWindow *> *windows, *orderedWindows;
@property(nullable, readonly, assign) NSWindow *keyWindow, *mainWindow, *modalWindow;
@property(nullable, readonly, retain) NSEvent *currentEvent;
@property(readonly, getter=isActive) BOOL active;
@property(readonly, getter=isHidden) BOOL hidden;
@property(readonly, getter=isRunning) BOOL running;
@property NSApplicationPresentationOptions presentationOptions;
@property(readonly) NSApplicationPresentationOptions currentSystemPresentationOptions;
@property(retain) NSImage *applicationIconImage;
@property(nullable, retain) NSAppearance *appearance;
@property(readonly) NSAppearance *effectiveAppearance;
@property(readonly) NSUserInterfaceLayoutDirection userInterfaceLayoutDirection;
@property(readonly) NSWindowOcclusionState occlusionState;
@property BOOL automaticCustomizeTouchBarMenuItemEnabled;
- (NSApplicationActivationPolicy)activationPolicy;
- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)p;
- (void)activateIgnoringOtherApps:(BOOL)f; - (void)activate; - (void)deactivate; - (void)yieldActivationToApplication:(NSRunningApplication *)a;
- (void)finishLaunching;
- (void)run;
- (void)stop:(nullable id)s;
- (void)terminate:(nullable id)s;
- (void)replyToApplicationShouldTerminate:(BOOL)f;
- (void)hide:(nullable id)s; - (void)unhide:(nullable id)s; - (void)unhideWithoutActivation; - (void)hideOtherApplications:(nullable id)s; - (void)unhideAllApplications:(nullable id)s;
- (nullable NSEvent *)nextEventMatchingMask:(NSEventMask)m untilDate:(NSDate *)d inMode:(NSRunLoopMode)mode dequeue:(BOOL)dq;
- (void)discardEventsMatchingMask:(NSEventMask)m beforeEvent:(NSEvent *)event;
- (void)postEvent:(NSEvent *)e atStart:(BOOL)f;
- (void)sendEvent:(NSEvent *)event;
- (BOOL)sendAction:(nullable SEL)a to:(nullable id)t from:(nullable id)s;
- (id)targetForAction:(nullable SEL)a; - (id)targetForAction:(nullable SEL)a to:(nullable id)t from:(nullable id)s;
- (BOOL)tryToPerform:(nullable SEL)a with:(nullable id)o;
- (nullable NSWindow *)windowWithWindowNumber:(NSInteger)n;
- (void)updateWindows; - (void)setWindowsNeedUpdate:(BOOL)f;
- (void)miniaturizeAll:(nullable id)s; - (void)arrangeInFront:(nullable id)s;
- (NSModalResponse)runModalForWindow:(NSWindow *)w; - (void)stopModal; - (void)stopModalWithCode:(NSModalResponse)c; - (void)abortModal;
- (NSInteger)requestUserAttention:(NSRequestUserAttentionType)t; - (void)cancelUserAttentionRequest:(NSInteger)r;
- (void)orderFrontStandardAboutPanel:(nullable id)s; - (void)orderFrontStandardAboutPanelWithOptions:(NSDictionary *)o; - (void)orderFrontCharacterPalette:(nullable id)s;
- (void)registerForRemoteNotifications; - (void)registerServicesMenuSendTypes:(NSArray *)s returnTypes:(NSArray *)r;
- (void)enumerateWindowsWithOptions:(NSUInteger)o usingBlock:(void (^)(NSWindow *w, BOOL *stop))b;
- (void)setWindowsMenu:(NSMenu *)m; - (void)addWindowsItem:(NSWindow *)w title:(NSString *)t filename:(BOOL)f;
- (void)toggleTouchBarCustomizationPalette:(nullable id)s;
@end
APPKIT_EXTERN NSApplication *NSApp;
int NSApplicationMain(int argc, const char *argv[]);
void NSBeep(void);
@interface NSSound : NSObject <NSCopying>
@property(copy) NSString *name; @property float volume; @property BOOL loops; @property(nullable, assign) id delegate;
+ (nullable instancetype)soundNamed:(NSString *)n;
- (BOOL)play; - (BOOL)stop;
@end
void NSRectFill(NSRect r); void NSFrameRect(NSRect r); void NSRectFillUsingOperation(NSRect r, NSCompositingOperation op);
void NSFrameRectWithWidth(NSRect r, CGFloat w); void NSRectClip(NSRect r); void NSEraseRect(NSRect r);
void NSRectFillList(const NSRect *r, NSInteger n); void NSRectClipList(const NSRect *r, NSInteger n);

@interface NSRunningApplication : NSObject
@property(class, readonly) NSRunningApplication *currentApplication;
@property(readonly) int processIdentifier;
@property(readonly, copy) NSString *localizedName, *bundleIdentifier;
@property(readonly, getter=isActive) BOOL active;
@property(readonly, getter=isHidden) BOOL hidden;
- (BOOL)activateWithOptions:(NSApplicationActivationOptions)o;
- (BOOL)hide; - (BOOL)unhide; - (BOOL)terminate; - (BOOL)forceTerminate;
@end
@interface NSWorkspace : NSObject
@property(class, readonly) NSWorkspace *sharedWorkspace;
@property(readonly) NSNotificationCenter *notificationCenter;
@property(readonly, retain) NSRunningApplication *frontmostApplication, *menuBarOwningApplication;
@property(readonly, copy) NSArray<NSRunningApplication *> *runningApplications;
@property(readonly) BOOL accessibilityDisplayShouldReduceMotion, accessibilityDisplayShouldIncreaseContrast, accessibilityDisplayShouldReduceTransparency,
    accessibilityDisplayShouldDifferentiateWithoutColor, accessibilityDisplayShouldInvertColors;
@property(readonly, getter=isVoiceOverEnabled) BOOL voiceOverEnabled;
@property(readonly, getter=isSwitchControlEnabled) BOOL switchControlEnabled;
- (BOOL)openURL:(NSURL *)u; - (BOOL)openFile:(NSString *)f;
- (void)activateFileViewerSelectingURLs:(NSArray *)u; - (BOOL)selectFile:(NSString *)f inFileViewerRootedAtPath:(NSString *)r;
- (NSImage *)iconForFile:(NSString *)f;
@end
@interface NSWorkspaceOpenConfiguration : NSObject <NSCopying>
+ (instancetype)configuration;
@property BOOL promptsUserIfNeeded, addsToRecentItems, activates, hides, hidesOthers, createsNewApplicationInstance, allowsRunningApplicationSubstitution;
@property(copy) NSArray<NSString *> *arguments;
@property(copy) NSDictionary<NSString *, NSString *> *environment;
@end
@interface NSWorkspace (MWOpenConfiguration)
- (void)openURL:(NSURL *)url configuration:(NSWorkspaceOpenConfiguration *)c completionHandler:(void (^ _Nullable)(NSRunningApplication * _Nullable app, NSError * _Nullable error))h;
- (void)openApplicationAtURL:(NSURL *)url configuration:(NSWorkspaceOpenConfiguration *)c completionHandler:(void (^ _Nullable)(NSRunningApplication * _Nullable app, NSError * _Nullable error))h;
@end

/* ============================================================================================ colors, fonts, images, appearance */
@interface NSColorSpace : NSObject
@property(class, readonly) NSColorSpace *sRGBColorSpace, *genericRGBColorSpace, *deviceRGBColorSpace, *displayP3ColorSpace, *extendedSRGBColorSpace;
@property(readonly) CGColorSpaceRef CGColorSpace;
@property(readonly, copy) NSString *localizedName;
@end
@interface NSColor : NSObject <NSCopying>
+ (NSColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithSRGBRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithCalibratedRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithDeviceRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithDisplayP3Red:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithWhite:(CGFloat)w alpha:(CGFloat)a;
+ (NSColor *)colorWithCalibratedWhite:(CGFloat)w alpha:(CGFloat)a;
+ (NSColor *)colorWithDeviceWhite:(CGFloat)w alpha:(CGFloat)a;
+ (NSColor *)colorWithGenericGamma22White:(CGFloat)w alpha:(CGFloat)a;
+ (NSColor *)colorWithHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithCGColor:(CGColorRef)c;
+ (NSColor *)colorWithName:(NSString *)n dynamicProvider:(NSColor * (^)(NSAppearance *a))p;
+ (nullable NSColor *)colorWithPatternImage:(NSImage *)i;
@property(class, readonly) NSColor *blackColor, *whiteColor, *clearColor, *redColor, *greenColor, *blueColor, *yellowColor, *orangeColor,
    *purpleColor, *brownColor, *cyanColor, *magentaColor, *grayColor, *lightGrayColor, *darkGrayColor,
    *systemRedColor, *systemGreenColor, *systemBlueColor, *systemOrangeColor, *systemYellowColor, *systemPinkColor, *systemPurpleColor,
    *systemTealColor, *systemIndigoColor, *systemBrownColor, *systemGrayColor, *systemMintColor, *systemCyanColor;
@property(class, readonly) NSColor *labelColor NS_SWIFT_NAME(labelColor);
@property(class, readonly) NSColor *secondaryLabelColor NS_SWIFT_NAME(secondaryLabelColor);
@property(class, readonly) NSColor *tertiaryLabelColor NS_SWIFT_NAME(tertiaryLabelColor);
@property(class, readonly) NSColor *quaternaryLabelColor NS_SWIFT_NAME(quaternaryLabelColor);
@property(class, readonly) NSColor *textColor NS_SWIFT_NAME(textColor);
@property(class, readonly) NSColor *textBackgroundColor NS_SWIFT_NAME(textBackgroundColor);
@property(class, readonly) NSColor *windowBackgroundColor NS_SWIFT_NAME(windowBackgroundColor);
@property(class, readonly) NSColor *controlColor NS_SWIFT_NAME(controlColor);
@property(class, readonly) NSColor *controlBackgroundColor NS_SWIFT_NAME(controlBackgroundColor);
@property(class, readonly) NSColor *controlTextColor NS_SWIFT_NAME(controlTextColor);
@property(class, readonly) NSColor *disabledControlTextColor NS_SWIFT_NAME(disabledControlTextColor);
@property(class, readonly) NSColor *controlAccentColor NS_SWIFT_NAME(controlAccentColor);
@property(class, readonly) NSColor *selectedControlColor NS_SWIFT_NAME(selectedControlColor);
@property(class, readonly) NSColor *selectedTextBackgroundColor NS_SWIFT_NAME(selectedTextBackgroundColor);
@property(class, readonly) NSColor *separatorColor NS_SWIFT_NAME(separatorColor);
@property(class, readonly) NSColor *gridColor NS_SWIFT_NAME(gridColor);
@property(class, readonly) NSColor *linkColor NS_SWIFT_NAME(linkColor);
@property(class, readonly) NSColor *placeholderTextColor NS_SWIFT_NAME(placeholderTextColor);
@property(class, readonly) NSColor *underPageBackgroundColor NS_SWIFT_NAME(underPageBackgroundColor);
@property(class, readonly) NSColor *unemphasizedSelectedContentBackgroundColor NS_SWIFT_NAME(unemphasizedSelectedContentBackgroundColor);
@property(class, readonly) NSColor *selectedContentBackgroundColor NS_SWIFT_NAME(selectedContentBackgroundColor);
@property(class, readonly) NSColor *keyboardFocusIndicatorColor NS_SWIFT_NAME(keyboardFocusIndicatorColor);
@property(class, readonly) NSColor *headerTextColor NS_SWIFT_NAME(headerTextColor);
@property(class, readonly) NSColor *shadowColor NS_SWIFT_NAME(shadowColor);
@property(class, readonly) NSColor *highlightColor NS_SWIFT_NAME(highlightColor);
@property(class, readonly) NSColor *windowFrameTextColor NS_SWIFT_NAME(windowFrameTextColor);
@property(class, readonly) NSColor *alternateSelectedControlTextColor NS_SWIFT_NAME(alternateSelectedControlTextColor);
@property(class, readonly) NSColor *selectedMenuItemTextColor NS_SWIFT_NAME(selectedMenuItemTextColor);
@property(class, readonly) NSColor *findHighlightColor NS_SWIFT_NAME(findHighlightColor);
@property(readonly) CGFloat redComponent, greenComponent, blueComponent, alphaComponent, whiteComponent, hueComponent,
    saturationComponent, brightnessComponent;
@property(readonly) CGColorRef CGColor;
@property(readonly) NSColorSpace *colorSpace;
@property(readonly) NSInteger numberOfComponents;
- (void)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a;
- (void)getComponents:(CGFloat *)c;
- (void)getHue:(CGFloat *)h saturation:(CGFloat *)s brightness:(CGFloat *)b alpha:(CGFloat *)a;
- (NSColor *)colorWithAlphaComponent:(CGFloat)a;
- (nullable NSColor *)colorUsingColorSpace:(NSColorSpace *)s;
- (nullable NSColor *)colorUsingColorSpaceName:(NSString *)n;
- (NSColor *)blendedColorWithFraction:(CGFloat)f ofColor:(NSColor *)c;
- (NSColor *)highlightWithLevel:(CGFloat)l; - (NSColor *)shadowWithLevel:(CGFloat)l;
- (void)set; - (void)setFill; - (void)setStroke;
@end
APPKIT_EXTERN NSString *const NSCalibratedRGBColorSpace, *const NSDeviceRGBColorSpace;
@interface NSFontDescriptor : NSObject
@property(readonly) CGFloat pointSize;
- (NSFontDescriptor *)fontDescriptorWithSymbolicTraits:(uint32_t)t;
@end
typedef unsigned int NSGlyph; typedef NSSize *NSSizeArray;
typedef NSString *NSFontTextStyle NS_TYPED_ENUM;
APPKIT_EXTERN NSFontTextStyle const NSFontTextStyleLargeTitle, NSFontTextStyleTitle1, NSFontTextStyleTitle2, NSFontTextStyleTitle3, NSFontTextStyleHeadline,
    NSFontTextStyleSubheadline, NSFontTextStyleBody, NSFontTextStyleCallout, NSFontTextStyleFootnote, NSFontTextStyleCaption1, NSFontTextStyleCaption2;
@interface NSFont : NSObject <NSCopying>
+ (NSFont *)systemFontOfSize:(CGFloat)s;
+ (NSFont *)preferredFontForTextStyle:(NSFontTextStyle)style options:(NSDictionary<NSString *, id> *)options;
+ (NSFont *)preferredFontForTextStyle:(NSFontTextStyle)style;
+ (NSFont *)systemFontOfSize:(CGFloat)s weight:(NSFontWeight)w;
+ (NSFont *)boldSystemFontOfSize:(CGFloat)s;
+ (NSFont *)monospacedSystemFontOfSize:(CGFloat)s weight:(NSFontWeight)w;
+ (NSFont *)monospacedDigitSystemFontOfSize:(CGFloat)s weight:(NSFontWeight)w;
+ (nullable NSFont *)userFixedPitchFontOfSize:(CGFloat)s;
+ (nullable NSFont *)userFontOfSize:(CGFloat)s;
+ (NSFont *)labelFontOfSize:(CGFloat)s;
+ (NSFont *)menuFontOfSize:(CGFloat)s;
+ (NSFont *)messageFontOfSize:(CGFloat)s;
+ (NSFont *)controlContentFontOfSize:(CGFloat)s;
+ (nullable NSFont *)fontWithName:(NSString *)n size:(CGFloat)s;
+ (nullable NSFont *)fontWithDescriptor:(NSFontDescriptor *)d size:(CGFloat)s;
+ (CGFloat)systemFontSize; + (CGFloat)smallSystemFontSize; + (CGFloat)labelFontSize;
+ (CGFloat)systemFontSizeForControlSize:(NSControlSize)c;
@property(readonly) CGFloat pointSize, ascender, descender, capHeight, xHeight, leading, underlinePosition;
@property(readonly) NSFontWeight weight;
@property(readonly, copy) NSString *fontName, *familyName, *displayName;
@property(readonly) NSFontDescriptor *fontDescriptor;
@property(readonly, getter=isFixedPitch) BOOL fixedPitch;
@property(readonly) NSRect boundingRectForFont;
- (CGFloat)defaultLineHeightForFont;
@end
@interface NSFont (MWGlyphs)
- (void)getAdvancements:(NSSizeArray)adv forGlyphs:(const NSGlyph *)g count:(NSUInteger)n;
- (void)getAdvancements:(NSSizeArray)adv forCGGlyphs:(const CGGlyph *)g count:(NSUInteger)n;
- (NSSize)advancementForGlyph:(NSGlyph)g; - (NSSize)advancementForCGGlyph:(CGGlyph)g;
- (NSRect)boundingRectForGlyph:(NSGlyph)g; - (NSRect)boundingRectForCGGlyph:(CGGlyph)g; - (NSGlyph)glyphWithName:(NSString *)n;
- (void)set; - (void)setInContext:(NSGraphicsContext *)c;
@end
@interface NSImageRep : NSObject
@property NSSize size;
@property NSInteger pixelsWide, pixelsHigh;
@property(readonly) BOOL hasAlpha;
@property(readonly) NSInteger bitsPerSample;
- (BOOL)draw; - (BOOL)drawInRect:(NSRect)r; - (BOOL)drawAtPoint:(NSPoint)p;
@end
APPKIT_EXTERN NSString *const NSImageCompressionFactor;
@interface NSBitmapImageRep : NSImageRep
- (instancetype)initWithBitmapDataPlanes:(unsigned char *_Nullable *_Nullable)planes pixelsWide:(NSInteger)w pixelsHigh:(NSInteger)h bitsPerSample:(NSInteger)bps
    samplesPerPixel:(NSInteger)spp hasAlpha:(BOOL)a isPlanar:(BOOL)p colorSpaceName:(NSString *)cs bytesPerRow:(NSInteger)bpr bitsPerPixel:(NSInteger)bpp;
- (instancetype)initWithBitmapDataPlanes:(unsigned char *_Nullable *_Nullable)planes pixelsWide:(NSInteger)w pixelsHigh:(NSInteger)h bitsPerSample:(NSInteger)bps
    samplesPerPixel:(NSInteger)spp hasAlpha:(BOOL)a isPlanar:(BOOL)p colorSpaceName:(NSString *)cs bitmapFormat:(NSBitmapFormat)f
    bytesPerRow:(NSInteger)bpr bitsPerPixel:(NSInteger)bpp;
- (instancetype)initWithCGImage:(CGImageRef)i;
- (instancetype)initWithData:(NSData *)d;
+ (instancetype)imageRepWithData:(NSData *)d;
+ (NSArray *)imageRepsWithData:(NSData *)d;
+ (instancetype)imageRepWithContentsOfFile:(NSString *)f;
+ (NSData *)representationOfImageRepsInArray:(NSArray *)reps usingType:(NSBitmapImageFileType)t properties:(NSDictionary *)p;
@property(readonly) NSBitmapFormat bitmapFormat;
@property(readonly, getter=isPlanar) BOOL planar;
- (NSColor *)colorAtX:(NSInteger)x y:(NSInteger)y;
- (void)setColor:(NSColor *)c atX:(NSInteger)x y:(NSInteger)y;
- (NSData *)TIFFRepresentation;
@property(readonly) unsigned char *bitmapData;
@property(readonly) NSInteger bytesPerRow, bitsPerPixel, samplesPerPixel;
@property(readonly) CGImageRef CGImage;
- (NSData *)representationUsingType:(NSBitmapImageFileType)t properties:(NSDictionary *)p;
@end
@interface NSImage : NSObject <NSCopying>
+ (nullable NSImage *)imageNamed:(NSString *)n;
+ (nullable NSImage *)imageWithSystemSymbolName:(NSString *)n accessibilityDescription:(nullable NSString *)d;
+ (NSImage *)imageWithSize:(NSSize)s flipped:(BOOL)f drawingHandler:(BOOL (^)(NSRect r))h;
- (instancetype)initWithSize:(NSSize)s;
- (instancetype)initWithContentsOfFile:(NSString *)f;
- (instancetype)initWithContentsOfURL:(NSURL *)u;
- (instancetype)initWithData:(NSData *)d;
- (instancetype)initWithCGImage:(CGImageRef)i size:(NSSize)s;
- (instancetype)initByReferencingFile:(NSString *)f;
- (void)removeRepresentation:(NSImageRep *)r;
- (void)drawInRect:(NSRect)r fromRect:(NSRect)f operation:(NSCompositingOperation)o fraction:(CGFloat)a respectFlipped:(BOOL)rf hints:(nullable NSDictionary *)h;
@property NSSize size;
@property(getter=isTemplate) BOOL template;
@property(copy) NSString *accessibilityDescription;
@property(readonly, copy) NSArray<NSImageRep *> *representations;
@property(readonly, getter=isValid) BOOL valid;
- (void)addRepresentation:(NSImageRep *)r;
- (CGImageRef)CGImageForProposedRect:(NSRect *)r context:(NSGraphicsContext *)c hints:(NSDictionary *)h;
- (NSData *)TIFFRepresentation;
- (void)lockFocus; - (void)unlockFocus;
- (void)drawInRect:(NSRect)r; - (void)drawAtPoint:(NSPoint)p fromRect:(NSRect)f operation:(NSCompositingOperation)o fraction:(CGFloat)a;
- (void)drawInRect:(NSRect)r fromRect:(NSRect)f operation:(NSCompositingOperation)o fraction:(CGFloat)a;
@end
@interface NSAppearance : NSObject
+ (NSAppearance *)appearanceNamed:(NSAppearanceName)n;
@property(class, retain) NSAppearance *currentAppearance;
@property(class, readonly) NSAppearance *currentDrawingAppearance;
@property(readonly, copy) NSAppearanceName name;
- (NSAppearanceName)bestMatchFromAppearancesWithNames:(NSArray<NSAppearanceName> *)names;
- (void)performAsCurrentDrawingAppearance:(void (^)(void))b;
@end
@interface NSGraphicsContext : NSObject
@property(nullable, class, retain) NSGraphicsContext *currentContext;
+ (NSGraphicsContext *)graphicsContextWithBitmapImageRep:(NSBitmapImageRep *)b;
+ (NSGraphicsContext *)graphicsContextWithCGContext:(CGContextRef)c flipped:(BOOL)f;
+ (void)saveGraphicsState; + (void)restoreGraphicsState;
@property(readonly) CGContextRef CGContext;
@property(readonly, getter=isFlipped) BOOL flipped;
@property BOOL shouldAntialias;
@property NSImageInterpolation imageInterpolation;
@property NSCompositingOperation compositingOperation;
@property(readonly) void *graphicsPort;
@property(readonly, getter=isDrawingToScreen) BOOL drawingToScreen;
- (void)saveGraphicsState; - (void)restoreGraphicsState; - (void)flushGraphics;
@end
@interface NSBezierPath : NSObject <NSCopying>
+ (NSBezierPath *)bezierPath;
+ (NSBezierPath *)bezierPathWithRect:(NSRect)r;
+ (NSBezierPath *)bezierPathWithOvalInRect:(NSRect)r;
+ (NSBezierPath *)bezierPathWithRoundedRect:(NSRect)r xRadius:(CGFloat)x yRadius:(CGFloat)y;
+ (void)fillRect:(NSRect)r; + (void)strokeRect:(NSRect)r; + (void)strokeLineFromPoint:(NSPoint)a toPoint:(NSPoint)b;
+ (void)clipRect:(NSRect)r;
@property(class) CGFloat defaultLineWidth;
@property NSWindingRule windingRule;
@property(readonly) CGPathRef CGPath;
- (void)appendBezierPathWithArcWithCenter:(NSPoint)c radius:(CGFloat)r startAngle:(CGFloat)a endAngle:(CGFloat)b clockwise:(BOOL)cw;
- (void)appendBezierPathWithArcFromPoint:(NSPoint)a toPoint:(NSPoint)b radius:(CGFloat)r;
- (void)appendBezierPathWithPoints:(NSPointArray)pts count:(NSInteger)n;
@property CGFloat lineWidth, miterLimit, flatness;
@property NSLineJoinStyle lineJoinStyle;
@property NSLineCapStyle lineCapStyle;
@property(readonly) NSRect bounds, controlPointBounds;
@property(readonly, getter=isEmpty) BOOL empty;
@property(readonly) NSInteger elementCount;
@property(readonly) NSPoint currentPoint;
- (void)moveToPoint:(NSPoint)p; - (void)lineToPoint:(NSPoint)p; - (void)curveToPoint:(NSPoint)p controlPoint1:(NSPoint)a controlPoint2:(NSPoint)b;
- (void)relativeMoveToPoint:(NSPoint)p; - (void)relativeLineToPoint:(NSPoint)p; - (void)closePath; - (void)removeAllPoints;
- (void)appendBezierPath:(NSBezierPath *)p; - (void)appendBezierPathWithRect:(NSRect)r; - (void)appendBezierPathWithOvalInRect:(NSRect)r;
- (void)appendBezierPathWithRoundedRect:(NSRect)r xRadius:(CGFloat)x yRadius:(CGFloat)y;
- (void)appendBezierPathWithArcWithCenter:(NSPoint)c radius:(CGFloat)r startAngle:(CGFloat)a endAngle:(CGFloat)b;
- (void)setLineDash:(const CGFloat *)d count:(NSInteger)n phase:(CGFloat)p;
- (void)fill; - (void)stroke; - (void)addClip; - (void)setClip;
- (BOOL)containsPoint:(NSPoint)p;
- (void)transformUsingAffineTransform:(nullable id)t;
@end
@interface NSShadow : NSObject
@property NSSize shadowOffset;
@property CGFloat shadowBlurRadius;
@property(copy) NSColor *shadowColor;
- (void)set;
@end
@interface NSTextTab : NSObject <NSCopying>
- (instancetype)initWithTextAlignment:(NSTextAlignment)a location:(CGFloat)l options:(NSDictionary *)o;
@property(readonly) NSTextAlignment alignment; @property(readonly) CGFloat location; @property(readonly, copy) NSDictionary *options;
@end
@interface NSParagraphStyle : NSObject <NSCopying, NSMutableCopying> {
@protected
    NSTextAlignment _alignment; NSLineBreakMode _lineBreakMode; NSInteger _baseWritingDirection, _lineBreakStrategy;
    CGFloat _lineSpacing, _paragraphSpacing, _paragraphSpacingBefore, _headIndent, _tailIndent, _firstLineHeadIndent,
        _minimumLineHeight, _maximumLineHeight, _lineHeightMultiple, _hyphenationFactor, _defaultTabInterval;
    NSArray *_tabStops; BOOL _allowsDefaultTighteningForTruncation;
}
@property(class, readonly, copy) NSParagraphStyle *defaultParagraphStyle;
@property(readonly) NSTextAlignment alignment;
@property(readonly) NSLineBreakMode lineBreakMode;
@property(readonly) CGFloat lineSpacing, paragraphSpacing, paragraphSpacingBefore, headIndent, tailIndent, firstLineHeadIndent,
    minimumLineHeight, maximumLineHeight, lineHeightMultiple, hyphenationFactor, defaultTabInterval;
@property(readonly) NSInteger baseWritingDirection, lineBreakStrategy;
@property(readonly, copy) NSArray<NSTextTab *> *tabStops;
@property(readonly) BOOL allowsDefaultTighteningForTruncation;
@end
@interface NSMutableParagraphStyle : NSParagraphStyle
@property NSTextAlignment alignment;
@property NSLineBreakMode lineBreakMode;
@property CGFloat lineSpacing, paragraphSpacing, paragraphSpacingBefore, headIndent, tailIndent, firstLineHeadIndent,
    minimumLineHeight, maximumLineHeight, lineHeightMultiple, hyphenationFactor, defaultTabInterval;
@property NSInteger baseWritingDirection, lineBreakStrategy;
@property(copy) NSArray<NSTextTab *> *tabStops;
@property BOOL allowsDefaultTighteningForTruncation;
- (void)setParagraphStyle:(NSParagraphStyle *)p; - (void)addTabStop:(NSTextTab *)t; - (void)removeTabStop:(NSTextTab *)t;
@end
@interface NSString (AppKitDrawing)
- (NSSize)sizeWithAttributes:(NSDictionary *)a;
- (void)drawAtPoint:(NSPoint)p withAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)a;
- (void)drawInRect:(NSRect)r withAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)a;
- (NSRect)boundingRectWithSize:(NSSize)s options:(NSStringDrawingOptions)o attributes:(nullable NSDictionary<NSAttributedStringKey, id> *)a;
- (NSRect)boundingRectWithSize:(NSSize)s options:(NSStringDrawingOptions)o attributes:(nullable NSDictionary<NSAttributedStringKey, id> *)a context:(nullable id)c;
- (void)drawWithRect:(NSRect)r options:(NSStringDrawingOptions)o attributes:(nullable NSDictionary<NSAttributedStringKey, id> *)a;
- (void)drawWithRect:(NSRect)r options:(NSStringDrawingOptions)o attributes:(nullable NSDictionary<NSAttributedStringKey, id> *)a context:(nullable id)c;
@end
@interface NSAttributedString (AppKitDrawing)
- (NSSize)size; - (void)drawAtPoint:(NSPoint)p; - (void)drawInRect:(NSRect)r;
- (NSRect)boundingRectWithSize:(NSSize)s options:(NSStringDrawingOptions)o;
- (NSRect)boundingRectWithSize:(NSSize)s options:(NSStringDrawingOptions)o context:(nullable id)c;
- (void)drawWithRect:(NSRect)r options:(NSStringDrawingOptions)o;
- (void)drawWithRect:(NSRect)r options:(NSStringDrawingOptions)o context:(nullable id)c;
@end

/* ============================================================================================ pasteboard, alerts, panels */
@interface NSPasteboard : NSObject
@property(class, readonly) NSPasteboard *generalPasteboard;
@property(readonly, copy) NSArray<NSPasteboardType> *types;
@property(readonly) NSInteger changeCount;
- (NSInteger)clearContents;
- (NSInteger)declareTypes:(NSArray<NSPasteboardType> *)t owner:(nullable id)o;
- (BOOL)setString:(NSString *)s forType:(NSPasteboardType)t;
- (BOOL)setData:(NSData *)d forType:(NSPasteboardType)t;
- (nullable NSString *)stringForType:(NSPasteboardType)t;
- (nullable NSData *)dataForType:(NSPasteboardType)t;
- (BOOL)writeObjects:(NSArray *)o;
- (NSArray *)readObjectsForClasses:(NSArray<Class> *)c options:(NSDictionary *)o;
- (NSPasteboardType)availableTypeFromArray:(NSArray<NSPasteboardType> *)t;
- (BOOL)canReadObjectForClasses:(NSArray<Class> *)c options:(NSDictionary *)o;
@end
@interface NSAlert : NSObject
+ (NSAlert *)alertWithError:(NSError *)e;
@property(copy) NSString *messageText, *informativeText;
@property NSAlertStyle alertStyle;
@property(retain) NSImage *icon;
@property(readonly) NSArray<NSButton *> *buttons;
@property(nullable, retain) NSView *accessoryView;
@property BOOL showsSuppressionButton, showsHelp;
@property(readonly) NSButton *suppressionButton;
@property(nullable, readonly) NSWindow *window;
@property(assign) id delegate; @property(copy) NSString *helpAnchor;
- (NSButton *)addButtonWithTitle:(NSString *)t;
- (NSModalResponse)runModal;
- (void)beginSheetModalForWindow:(NSWindow *)w completionHandler:(void (^ _Nullable)(NSModalResponse r))h;
- (void)layout;
@end
@interface NSSavePanel : NSPanel
+ (NSSavePanel *)savePanel;
@property(nullable, copy) NSURL *directoryURL;
@property(nullable, readonly, copy) NSURL *URL;
@property(copy) NSString *nameFieldStringValue, *message, *prompt;
@property(copy) NSArray<NSString *> *allowedFileTypes;
@property(copy) NSArray *allowedContentTypes;
@property BOOL canCreateDirectories, showsHiddenFiles, extensionHidden, canSelectHiddenExtension, allowsOtherFileTypes;
- (NSModalResponse)runModal;
- (void)beginWithCompletionHandler:(void (^)(NSModalResponse r))h;
- (void)beginSheetModalForWindow:(NSWindow *)w completionHandler:(void (^ _Nullable)(NSModalResponse r))h;
@end
@interface NSOpenPanel : NSSavePanel
+ (NSOpenPanel *)openPanel;
@property(readonly, copy) NSArray<NSURL *> *URLs;
@property BOOL canChooseFiles, canChooseDirectories, allowsMultipleSelection, resolvesAliases;
@end

/* ============================================================================================ controllers */
typedef NSString *NSNibName NS_SWIFT_BRIDGED_TYPEDEF;
@interface NSNib : NSObject
- (instancetype)initWithNibNamed:(NSNibName)n bundle:(nullable NSBundle *)b;
- (instancetype)initWithNibData:(NSData *)d bundle:(nullable NSBundle *)b;
- (instancetype)initWithContentsOfURL:(NSURL *)u;
- (BOOL)instantiateWithOwner:(nullable id)owner topLevelObjects:(NSArray * _Nullable * _Nullable)top;
- (BOOL)instantiateNibWithOwner:(nullable id)owner topLevelObjects:(NSArray * _Nullable * _Nullable)top;
@end
@interface NSBundle (NSNibLoading)
- (BOOL)loadNibNamed:(NSNibName)n owner:(nullable id)owner topLevelObjects:(NSArray * _Nullable * _Nullable)top;
+ (BOOL)loadNibNamed:(NSString *)n owner:(nullable id)owner;
- (BOOL)loadNibFile:(NSString *)f externalNameTable:(NSDictionary *)t withZone:(NSZone *)z;
@end
@interface NSObject (NSNibAwaking) - (void)awakeFromNib; - (void)prepareForInterfaceBuilder; @end
@interface NSViewController : NSResponder
- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b;
@property(readonly, copy) NSNibName nibName;
@property(nullable, readonly, retain) NSBundle *nibBundle;
@property(retain) NSView *view;
@property(copy) NSString *title;
@property(retain) id representedObject;
@property NSSize preferredContentSize;
@property(readonly, getter=isViewLoaded) BOOL viewLoaded;
- (void)loadView; - (void)viewDidLoad; - (void)viewWillAppear; - (void)viewDidAppear; - (void)viewWillDisappear; - (void)viewDidDisappear;
- (void)viewWillLayout; - (void)viewDidLayout; - (void)updateViewConstraints;
- (void)addChildViewController:(NSViewController *)c; - (void)removeFromParentViewController;
@property(readonly, copy) NSArray<NSViewController *> *childViewControllers;
@property(nullable, readonly, assign) NSViewController *parentViewController;
- (void)presentViewControllerAsSheet:(NSViewController *)vc; - (void)presentViewControllerAsModalWindow:(NSViewController *)vc;
- (void)dismissViewController:(NSViewController *)vc; - (void)dismissController:(nullable id)s;
@end
@interface NSWindowController : NSResponder
- (instancetype)initWithWindow:(NSWindow *)w;
- (instancetype)initWithWindowNibName:(NSString *)n;
- (instancetype)initWithWindowNibName:(NSString *)n owner:(nullable id)owner;
- (instancetype)initWithWindowNibPath:(NSString *)p owner:(nullable id)owner;
@property(readonly, copy) NSNibName windowNibName;
@property(readonly, copy) NSString *windowNibPath;
@property(readonly, assign) id owner;
@property(nullable, retain) NSWindow *window;
@property(nullable, retain) NSViewController *contentViewController;
@property(readonly, getter=isWindowLoaded) BOOL windowLoaded;
@property(assign) id document;
@property BOOL shouldCascadeWindows, shouldCloseDocument;
@property(copy) NSString *windowFrameAutosaveName;
- (void)showWindow:(nullable id)s; - (void)close; - (void)loadWindow; - (void)windowDidLoad; - (void)windowWillLoad;
@end



/* ============================================================================================ misc.m */
typedef NSString *NSPasteboardName NS_TYPED_EXTENSIBLE_ENUM;
APPKIT_EXTERN NSPasteboardName const NSPasteboardNameGeneral, NSPasteboardNameFont, NSPasteboardNameRuler, NSPasteboardNameFind, NSPasteboardNameDrag;
APPKIT_EXTERN NSString *const NSPasteboardURLReadingFileURLsOnlyKey, *const NSPasteboardURLReadingContentsConformToTypesKey;
APPKIT_EXTERN NSString *const NSImageNameStopProgressTemplate, *const NSImageNameStopProgressFreestandingTemplate, *const NSImageNameRefreshTemplate,
    *const NSImageNameAddTemplate, *const NSImageNameRemoveTemplate, *const NSImageNameActionTemplate, *const NSImageNameFolder,
    *const NSImageNameMultipleDocuments, *const NSImageNameGoLeftTemplate, *const NSImageNameGoRightTemplate, *const NSImageNameMenuOnStateTemplate,
    *const NSImageNameLockLockedTemplate, *const NSImageNameLockUnlockedTemplate;
APPKIT_EXTERN NSString *const NSWorkspaceRecycleOperation, *const NSWorkspaceMoveOperation, *const NSWorkspaceCopyOperation;
APPKIT_EXTERN NSNotificationName const NSWorkspaceWillPowerOffNotification, NSWorkspaceDidMountNotification, NSWorkspaceDidUnmountNotification,
    NSWorkspaceWillUnmountNotification, NSColorPanelColorDidChangeNotification;
APPKIT_EXTERN NSString *const NSObservedObjectKey, *const NSObservedKeyPathKey, *const NSOptionsKey, *const NSValueTransformerBindingOption,
    *const NSValueTransformerNameBindingOption, *const NSContinuouslyUpdatesValueBindingOption, *const NSNullPlaceholderBindingOption,
    *const NSValueBinding, *const NSEnabledBinding, *const NSHiddenBinding, *const NSTitleBinding;
typedef NS_ENUM(NSUInteger, NSFocusRingPlacement) { NSFocusRingOnly = 0, NSFocusRingBelow = 1, NSFocusRingAbove = 2 };
APPKIT_EXTERN void NSFrameRectWithWidthUsingOperation(NSRect r, CGFloat w, NSCompositingOperation op);
APPKIT_EXTERN void NSRectFillListWithColors(const NSRect *r, NSColor *const *c, NSInteger n);
APPKIT_EXTERN void NSRectFillListWithColorsUsingOperation(const NSRect *r, NSColor *const *c, NSInteger n, NSCompositingOperation op);
APPKIT_EXTERN void NSRectFillListWithGrays(const NSRect *r, const CGFloat *g, NSInteger n);
APPKIT_EXTERN void NSRectFillListUsingOperation(const NSRect *r, NSInteger n, NSCompositingOperation op);
APPKIT_EXTERN void NSSetFocusRingStyle(NSFocusRingPlacement p);
typedef NS_ENUM(NSInteger, NSGestureRecognizerState) { NSGestureRecognizerStatePossible, NSGestureRecognizerStateBegan, NSGestureRecognizerStateChanged,
    NSGestureRecognizerStateEnded, NSGestureRecognizerStateCancelled, NSGestureRecognizerStateFailed };
@interface NSGestureRecognizer : NSObject
- (instancetype)initWithTarget:(nullable id)t action:(nullable SEL)a;
@property(assign) id target; @property SEL action; @property(getter=isEnabled) BOOL enabled; @property(assign) id delegate;
@property(assign) NSView *view; @property NSGestureRecognizerState state;
@property BOOL delaysPrimaryMouseButtonEvents, delaysSecondaryMouseButtonEvents, delaysKeyEvents;
- (NSPoint)locationInView:(nullable NSView *)v; - (void)reset;
@end
@interface NSClickGestureRecognizer : NSGestureRecognizer @property NSUInteger buttonMask, numberOfClicksRequired, numberOfTouchesRequired; @end
@interface NSPanGestureRecognizer : NSGestureRecognizer @property NSUInteger buttonMask;
- (NSPoint)translationInView:(nullable NSView *)v; - (void)setTranslation:(NSPoint)p inView:(nullable NSView *)v; - (NSPoint)velocityInView:(nullable NSView *)v; @end
@interface NSMagnificationGestureRecognizer : NSGestureRecognizer @property CGFloat magnification; @end
@interface NSPressGestureRecognizer : NSGestureRecognizer @property NSTimeInterval minimumPressDuration; @end
@interface NSRotationGestureRecognizer : NSGestureRecognizer @property CGFloat rotation; @end
@interface NSView (MWGestures) @property(copy) NSArray<NSGestureRecognizer *> *gestureRecognizers;
- (void)addGestureRecognizer:(NSGestureRecognizer *)g; - (void)removeGestureRecognizer:(NSGestureRecognizer *)g; @end
typedef NS_OPTIONS(NSUInteger, NSGradientDrawingOptions) { NSGradientDrawsBeforeStartingLocation = 1, NSGradientDrawsAfterEndingLocation = 2 };
@interface NSGradient : NSObject <NSCopying>
- (nullable instancetype)initWithStartingColor:(NSColor *)a endingColor:(NSColor *)b;
- (nullable instancetype)initWithColors:(NSArray<NSColor *> *)c;
- (nullable instancetype)initWithColors:(NSArray<NSColor *> *)c atLocations:(nullable const CGFloat *)l colorSpace:(nullable NSColorSpace *)s;
- (nullable instancetype)initWithColorsAndLocations:(NSColor *)first, ... NS_REQUIRES_NIL_TERMINATION;
@property(readonly) NSInteger numberOfColorStops;
- (void)getColor:(NSColor * _Nullable * _Nullable)c location:(nullable CGFloat *)l atIndex:(NSInteger)i;
- (NSColor *)interpolatedColorAtLocation:(CGFloat)t;
- (void)drawInRect:(NSRect)r angle:(CGFloat)a; - (void)drawInBezierPath:(NSBezierPath *)p angle:(CGFloat)a;
- (void)drawFromPoint:(NSPoint)a toPoint:(NSPoint)b options:(NSGradientDrawingOptions)o;
- (void)drawInRect:(NSRect)r relativeCenterPosition:(NSPoint)p; - (void)drawInBezierPath:(NSBezierPath *)p relativeCenterPosition:(NSPoint)c;
@end
typedef NS_ENUM(NSInteger, NSPopoverBehavior) { NSPopoverBehaviorApplicationDefined = 0, NSPopoverBehaviorTransient = 1, NSPopoverBehaviorSemitransient = 2 };
APPKIT_EXTERN NSNotificationName const NSPopoverWillShowNotification, NSPopoverDidShowNotification, NSPopoverWillCloseNotification, NSPopoverDidCloseNotification;
@protocol NSPopoverDelegate <NSObject> @optional - (void)popoverDidShow:(NSNotification *)n; - (void)popoverDidClose:(NSNotification *)n; @end
@interface NSPopover : NSResponder
@property(nullable, retain) NSViewController *contentViewController; @property NSSize contentSize; @property NSPopoverBehavior behavior;
@property BOOL animates; @property(assign) id<NSPopoverDelegate> delegate; @property(retain) id appearance;
@property(readonly, getter=isShown) BOOL shown; @property NSRect positioningRect;
- (void)showRelativeToRect:(NSRect)r ofView:(nullable NSView *)v preferredEdge:(NSRectEdge)e; - (void)close; - (IBAction)performClose:(nullable id)s;
@end
typedef NS_OPTIONS(NSUInteger, NSColorPanelOptions) { NSColorPanelAllModesMask = 0xffff };
typedef NS_ENUM(NSInteger, NSColorPanelMode) { NSColorPanelModeNone = -1, NSColorPanelModeGray = 0, NSColorPanelModeRGB = 1, NSColorPanelModeWheel = 6 };
@interface NSColorPanel : NSPanel
@property(class, readonly, retain) NSColorPanel *sharedColorPanel; @property(class, readonly) BOOL sharedColorPanelExists;
+ (void)setPickerMask:(NSColorPanelOptions)m; + (void)setPickerMode:(NSColorPanelMode)m;
@property(retain) NSColor *color; @property NSColorPanelMode mode; @property BOOL continuous, showsAlpha;
- (void)setTarget:(nullable id)t; - (void)setAction:(nullable SEL)a; - (void)attachColorList:(nullable id)l;
@end
@interface NSFontPanel : NSPanel
@property(class, readonly, retain) NSFontPanel *sharedFontPanel; @property(class, readonly) BOOL sharedFontPanelExists;
- (void)setPanelFont:(NSFont *)f isMultiple:(BOOL)m; - (NSFont *)panelConvertFont:(NSFont *)f;
@end
typedef NS_OPTIONS(NSUInteger, NSFontTraitMask) { NSItalicFontMask = 1, NSBoldFontMask = 2, NSUnboldFontMask = 4, NSNonStandardCharacterSetFontMask = 8,
    NSNarrowFontMask = 16, NSExpandedFontMask = 32, NSCondensedFontMask = 64, NSSmallCapsFontMask = 128, NSPosterFontMask = 256,
    NSCompressedFontMask = 512, NSFixedPitchFontMask = 1024, NSUnitalicFontMask = 0x01000000 };
@interface NSFontManager : NSObject
@property(class, readonly, retain) NSFontManager *sharedFontManager;
+ (void)setFontManagerFactory:(nullable Class)c; + (void)setFontPanelFactory:(nullable Class)c;
@property(readonly, copy) NSArray<NSString *> *availableFonts, *availableFontFamilies;
- (nullable NSArray *)availableMembersOfFontFamily:(NSString *)f; - (nullable NSArray<NSString *> *)availableFontNamesWithTraits:(NSFontTraitMask)t;
- (NSFont *)convertFont:(NSFont *)f; - (NSFont *)convertFont:(NSFont *)f toSize:(CGFloat)s;
- (NSFont *)convertFont:(NSFont *)f toHaveTrait:(NSFontTraitMask)t; - (NSFont *)convertFont:(NSFont *)f toNotHaveTrait:(NSFontTraitMask)t;
- (NSFont *)convertFont:(NSFont *)f toFamily:(NSString *)fam;
- (NSFontTraitMask)traitsOfFont:(NSFont *)f; - (NSInteger)weightOfFont:(NSFont *)f;
- (nullable NSFont *)fontWithFamily:(NSString *)fam traits:(NSFontTraitMask)t weight:(NSInteger)w size:(CGFloat)s;
@property(nullable, readonly, retain) NSFont *selectedFont; - (void)setSelectedFont:(NSFont *)f isMultiple:(BOOL)m;
- (IBAction)orderFrontFontPanel:(nullable id)s; - (IBAction)addFontTrait:(nullable id)s; - (IBAction)removeFontTrait:(nullable id)s;
- (IBAction)modifyFont:(nullable id)s; - (IBAction)modifyFontViaPanel:(nullable id)s;
@property(assign) id target; @property SEL action; @property(assign) id delegate; @property(getter=isEnabled) BOOL enabled;
- (nullable NSMenu *)fontMenu:(BOOL)create;
@end
@class NSLayoutManager;
@interface NSTextStorage : NSMutableAttributedString
@property(readonly, copy) NSArray<NSLayoutManager *> *layoutManagers;
- (void)addLayoutManager:(NSLayoutManager *)m; - (void)removeLayoutManager:(NSLayoutManager *)m;
@end
@interface NSTextContainer : NSObject
- (instancetype)initWithSize:(NSSize)s; - (instancetype)initWithContainerSize:(NSSize)s;
@property NSSize size, containerSize; @property CGFloat lineFragmentPadding; @property(nullable, assign) NSLayoutManager *layoutManager;
@property BOOL widthTracksTextView, heightTracksTextView; @property NSUInteger maximumNumberOfLines; @property NSLineBreakMode lineBreakMode;
@end
@interface NSLayoutManager : NSObject
@property(nullable, assign) NSTextStorage *textStorage; @property(readonly, copy) NSArray<NSTextContainer *> *textContainers;
@property BOOL usesFontLeading, allowsNonContiguousLayout, showsInvisibleCharacters, showsControlCharacters;
- (void)addTextContainer:(NSTextContainer *)c; - (void)removeTextContainerAtIndex:(NSUInteger)i;
- (CGFloat)defaultLineHeightForFont:(NSFont *)f; - (CGFloat)defaultBaselineOffsetForFont:(NSFont *)f;
- (NSRange)glyphRangeForTextContainer:(NSTextContainer *)c; - (NSRect)usedRectForTextContainer:(NSTextContainer *)c;
- (void)ensureLayoutForTextContainer:(NSTextContainer *)c; @property(readonly) NSUInteger numberOfGlyphs;
- (NSRect)boundingRectForGlyphRange:(NSRange)r inTextContainer:(NSTextContainer *)c;
- (void)drawGlyphsForGlyphRange:(NSRange)r atPoint:(NSPoint)p; - (void)drawBackgroundForGlyphRange:(NSRange)r atPoint:(NSPoint)p;
@end
@interface NSController : NSObject <NSCoding> - (BOOL)commitEditing; - (void)discardEditing; @property(readonly, getter=isEditing) BOOL editing; @end
@interface NSObjectController : NSController
- (instancetype)initWithContent:(nullable id)c; @property(retain) id content; @property(readonly, retain) id selection;
@property(readonly, copy) NSArray *selectedObjects; @property(assign) Class objectClass; @property BOOL automaticallyPreparesContent, editable;
@end
@interface NSArrayController : NSObjectController
@property(readonly, retain) id arrangedObjects; - (void)addObject:(nullable id)o; - (void)removeObject:(nullable id)o;
@property(readonly) NSUInteger selectionIndex; - (BOOL)setSelectionIndex:(NSUInteger)i;
@property(readonly, copy) NSIndexSet *selectionIndexes; - (BOOL)setSelectionIndexes:(NSIndexSet *)i; - (void)rearrangeObjects;
@property(copy) NSArray *sortDescriptors; @property BOOL avoidsEmptySelection, preservesSelection, selectsInsertedObjects, automaticallyRearrangesObjects;
@end
@interface NSUserDefaultsController : NSController
@property(class, readonly, retain) NSUserDefaultsController *sharedUserDefaultsController;
- (instancetype)initWithDefaults:(nullable NSUserDefaults *)d initialValues:(nullable NSDictionary *)v;
@property(readonly, retain) NSUserDefaults *defaults; @property(readonly, retain) id values; @property(copy) NSDictionary *initialValues;
@property BOOL appliesImmediately; @property(readonly) BOOL hasUnappliedChanges;
- (IBAction)revert:(nullable id)s; - (IBAction)save:(nullable id)s; - (IBAction)revertToInitialValues:(nullable id)s;
@end
@interface WebView : NSView
@property(readonly, retain) id mainFrame; - (void)setFrameLoadDelegate:(nullable id)d; - (void)setPolicyDelegate:(nullable id)d; - (void)setUIDelegate:(nullable id)d;
- (void)setResourceLoadDelegate:(nullable id)d; - (void)setDrawsBackground:(BOOL)d; - (void)setMainFrameURL:(NSString *)u;
@end
@interface NSObject (NSKeyValueBindingCreation)
+ (void)exposeBinding:(NSString *)b; @property(readonly, copy) NSArray<NSString *> *exposedBindings; - (nullable Class)valueClassForBinding:(NSString *)b;
- (void)bind:(NSString *)b toObject:(nullable id)o withKeyPath:(NSString *)p options:(nullable NSDictionary<NSString *, id> *)opts;
- (void)unbind:(NSString *)b; - (nullable NSDictionary<NSString *, id> *)infoForBinding:(NSString *)b;
@end
@interface NSColor (MWMoreColors)
@property(class, readonly, copy) NSArray<NSColor *> *alternatingContentBackgroundColors, *controlAlternatingRowBackgroundColors;
@property(class, readonly, retain) NSColor *textInsertionPointColor, *unemphasizedSelectedTextBackgroundColor;
+ (NSColor *)colorWithCalibratedHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)b alpha:(CGFloat)a; - (nullable NSColor *)colorUsingType:(NSInteger)t;
@end
@interface NSWindow (MWMore) - (void)disableFlushWindow; - (void)enableFlushWindow; - (void)setContentBorderThickness:(CGFloat)t forEdge:(NSRectEdge)e;
- (CGFloat)contentBorderThicknessForEdge:(NSRectEdge)e; - (void)setAutorecalculatesContentBorderThickness:(BOOL)f forEdge:(NSRectEdge)e;
@property(nullable, readonly, copy) NSArray<NSWindow *> *tabbedWindows; @end
@interface NSView (MWMenuItem) @property(nullable, readonly, retain) NSMenuItem *enclosingMenuItem; @end
@interface NSWorkspace (MWMore) - (NSImage *)iconForFileType:(NSString *)t;
- (BOOL)performFileOperation:(NSString *)op source:(NSString *)src destination:(NSString *)dst files:(NSArray *)files tag:(nullable NSInteger *)tag; @end
@interface NSImage (MWMore) - (void)lockFocusFlipped:(BOOL)f; @end
@interface NSBundle (NSBundleImageExtension) - (nullable NSImage *)imageForResource:(NSString *)name; - (nullable NSString *)pathForImageResource:(NSString *)name; @end
@interface NSColor (NSColorNamed) + (nullable NSColor *)colorNamed:(NSString *)name; + (nullable NSColor *)colorNamed:(NSString *)name bundle:(nullable NSBundle *)bundle; @end
@interface NSFont (MWMore) @property(readonly) NSSize maximumAdvancement; @property(readonly, retain) NSCharacterSet *coveredCharacterSet; @end
@interface NSApplication (MWDocuments) @property(readonly, copy) NSArray *orderedDocuments; @end
@interface NSPasteboard (MWMore) + (NSPasteboard *)pasteboardWithName:(NSPasteboardName)n;
- (nullable id)propertyListForType:(NSPasteboardType)t; - (BOOL)setPropertyList:(nullable id)p forType:(NSPasteboardType)t; @end
@interface NSSavePanel (MWMore) @property BOOL treatsFilePackagesAsDirectories; @end
@interface NSOpenPanel (MWMore) @property(getter=isAccessoryViewDisclosed) BOOL accessoryViewDisclosed; @end
/* ============================================================================================ documents (document.m) */
#ifndef IBAction
#define IBAction void
#define IBOutlet
#endif
typedef NS_ENUM(NSUInteger, NSDocumentChangeType) { NSChangeDone = 0, NSChangeUndone = 1, NSChangeRedone = 5, NSChangeCleared = 2,
    NSChangeReadOtherContents = 3, NSChangeAutosaved = 4, NSChangeDiscardable = 256 };
typedef NS_ENUM(NSUInteger, NSSaveOperationType) { NSSaveOperation = 0, NSSaveAsOperation = 1, NSSaveToOperation = 2,
    NSAutosaveInPlaceOperation = 4, NSAutosaveElsewhereOperation = 3, NSAutosaveAsOperation = 5 };
@class NSPrintInfo;
@interface NSDocument : NSObject
+ (BOOL)autosavesInPlace; + (BOOL)autosavesDrafts; + (BOOL)preservesVersions; + (BOOL)usesUbiquitousStorage;
+ (BOOL)canConcurrentlyReadDocumentsOfType:(NSString *)t;
+ (NSArray<NSString *> *)readableTypes; + (NSArray<NSString *> *)writableTypes; + (BOOL)isNativeType:(NSString *)t;
- (instancetype)init;
- (nullable instancetype)initWithType:(NSString *)type error:(NSError **)e;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)u ofType:(NSString *)type error:(NSError **)e;
- (nullable instancetype)initForURL:(nullable NSURL *)u withContentsOfURL:(nullable NSURL *)c ofType:(NSString *)type error:(NSError **)e;
@property (nullable, copy) NSURL *fileURL; @property (nullable, copy) NSString *fileType; @property (nullable, copy) NSDate *fileModificationDate;
@property (copy) NSString *displayName; @property (readonly) NSString *lastComponentOfFileName;
@property (getter=isDraft) BOOL draft; @property (readonly, getter=isEntireFileLoaded) BOOL entireFileLoaded;
@property (readonly, getter=isInViewingMode) BOOL inViewingMode; @property (readonly, getter=isLocked) BOOL locked;
@property (readonly, getter=isBrowsingVersions) BOOL browsingVersions; @property (readonly) BOOL hasUnautosavedChanges, keepBackupFile;
@property (nullable, readonly) NSString *windowNibName;
@property (readonly, copy) NSArray<NSWindowController *> *windowControllers;
- (void)makeWindowControllers; - (void)addWindowController:(NSWindowController *)wc; - (void)removeWindowController:(NSWindowController *)wc;
- (void)showWindows; - (void)windowControllerWillLoadNib:(NSWindowController *)wc; - (void)windowControllerDidLoadNib:(NSWindowController *)wc;
- (void)setWindow:(nullable NSWindow *)w; @property (nullable, readonly) NSWindow *windowForSheet;
- (void)shouldCloseWindowController:(NSWindowController *)wc delegate:(nullable id)d shouldCloseSelector:(nullable SEL)s contextInfo:(nullable void *)c;
- (void)canCloseDocumentWithDelegate:(nullable id)d shouldCloseSelector:(nullable SEL)s contextInfo:(nullable void *)c;
- (void)close; - (BOOL)_mwCanClose;
@property (readonly, getter=isDocumentEdited) BOOL documentEdited;
- (void)updateChangeCount:(NSDocumentChangeType)t;
- (id)changeCountTokenForSaveOperation:(NSSaveOperationType)op; - (void)updateChangeCountWithToken:(nullable id)tok forSaveOperation:(NSSaveOperationType)op;
@property BOOL hasUndoManager; @property (nullable, retain) NSUndoManager *undoManager;
- (BOOL)readFromURL:(NSURL *)u ofType:(NSString *)type error:(NSError **)e;
- (BOOL)readFromFileWrapper:(NSFileWrapper *)fw ofType:(NSString *)type error:(NSError **)e;
- (BOOL)readFromData:(NSData *)d ofType:(NSString *)type error:(NSError **)e;
- (BOOL)revertToContentsOfURL:(NSURL *)u ofType:(NSString *)type error:(NSError **)e;
- (nullable NSData *)dataOfType:(NSString *)type error:(NSError **)e;
- (nullable NSFileWrapper *)fileWrapperOfType:(NSString *)type error:(NSError **)e;
- (BOOL)writeToURL:(NSURL *)u ofType:(NSString *)type error:(NSError **)e;
- (BOOL)writeToURL:(NSURL *)u ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)op originalContentsURL:(nullable NSURL *)o error:(NSError **)e;
- (BOOL)writeSafelyToURL:(NSURL *)u ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)op error:(NSError **)e;
- (nullable NSDictionary *)fileAttributesToWriteToURL:(NSURL *)u ofType:(NSString *)t forSaveOperation:(NSSaveOperationType)op originalContentsURL:(nullable NSURL *)o error:(NSError **)e;
- (BOOL)saveToURL:(NSURL *)u ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)op error:(NSError **)e;
- (void)saveToURL:(NSURL *)u ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)op completionHandler:(void (^ _Nullable)(NSError * _Nullable))h;
- (void)saveToURL:(NSURL *)u ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)op delegate:(nullable id)d didSaveSelector:(nullable SEL)s contextInfo:(nullable void *)c;
- (NSArray<NSString *> *)writableTypesForSaveOperation:(NSSaveOperationType)op;
- (nullable NSString *)fileNameExtensionForType:(NSString *)type saveOperation:(NSSaveOperationType)op;
- (BOOL)prepareSavePanel:(NSSavePanel *)p; @property (readonly) BOOL shouldRunSavePanelWithAccessoryView, fileNameExtensionWasHiddenInLastRunSavePanel;
@property (nullable, readonly, copy) NSString *fileTypeFromLastRunSavePanel;
- (IBAction)saveDocument:(nullable id)s; - (IBAction)saveDocumentAs:(nullable id)s; - (IBAction)saveDocumentTo:(nullable id)s;
- (IBAction)revertDocumentToSaved:(nullable id)s; - (IBAction)printDocument:(nullable id)s; - (IBAction)runPageLayout:(nullable id)s;
- (IBAction)duplicateDocument:(nullable id)s; - (IBAction)renameDocument:(nullable id)s; - (IBAction)moveDocument:(nullable id)s;
- (void)saveDocumentWithDelegate:(nullable id)d didSaveSelector:(nullable SEL)s contextInfo:(nullable void *)c;
- (void)autosaveWithImplicitCancellability:(BOOL)c completionHandler:(void (^ _Nullable)(NSError * _Nullable))h;
- (BOOL)checkAutosavingSafetyAndReturnError:(NSError **)e;
@property (nullable, copy) NSPrintInfo *printInfo;
- (BOOL)presentError:(NSError *)e; - (NSError *)willPresentError:(NSError *)e;
- (void)presentError:(NSError *)e modalForWindow:(NSWindow *)w delegate:(nullable id)d didPresentSelector:(nullable SEL)s contextInfo:(nullable void *)c;
- (void)performActivityWithSynchronousWaiting:(BOOL)w usingBlock:(void (^)(void (^)(void)))b;
- (void)continueActivityUsingBlock:(void (^)(void))b; - (void)continueAsynchronousWorkOnMainThreadUsingBlock:(void (^)(void))b;
- (void)performSynchronousFileAccessUsingBlock:(void (^)(void))b; - (void)performAsynchronousFileAccessUsingBlock:(void (^)(void (^)(void)))b;
- (BOOL)validateUserInterfaceItem:(nullable id)i; - (BOOL)validateMenuItem:(NSMenuItem *)i;
@end
@interface NSDocumentController : NSObject
@property (class, readonly, retain) __kindof NSDocumentController *sharedDocumentController;
@property (readonly, copy) NSArray<__kindof NSDocument *> *documents;
@property (nullable, readonly, retain) __kindof NSDocument *currentDocument;
@property (nullable, readonly, copy) NSString *defaultType; @property (readonly, copy) NSArray<NSString *> *documentClassNames;
@property (readonly) BOOL hasEditedDocuments; @property (readonly) NSUInteger maximumRecentDocumentCount;
@property (readonly, copy) NSArray<NSURL *> *recentDocumentURLs; @property NSTimeInterval autosavingDelay;
- (void)addDocument:(NSDocument *)d; - (void)removeDocument:(NSDocument *)d;
- (nullable __kindof NSDocument *)documentForWindow:(NSWindow *)w; - (nullable __kindof NSDocument *)documentForURL:(NSURL *)u;
- (nullable Class)documentClassForType:(NSString *)t; - (nullable NSString *)displayNameForType:(NSString *)t;
- (NSArray<NSString *> *)fileExtensionsFromType:(NSString *)t;
- (nullable NSString *)typeForContentsOfURL:(NSURL *)u error:(NSError **)e;
- (nullable __kindof NSDocument *)makeUntitledDocumentOfType:(NSString *)t error:(NSError **)e;
- (nullable __kindof NSDocument *)makeDocumentWithContentsOfURL:(NSURL *)u ofType:(NSString *)t error:(NSError **)e;
- (nullable __kindof NSDocument *)makeDocumentForURL:(nullable NSURL *)u withContentsOfURL:(NSURL *)c ofType:(NSString *)t error:(NSError **)e;
- (nullable __kindof NSDocument *)openUntitledDocumentAndDisplay:(BOOL)d error:(NSError **)e;
- (nullable __kindof NSDocument *)openDocumentWithContentsOfURL:(NSURL *)u display:(BOOL)d error:(NSError **)e;
- (void)openDocumentWithContentsOfURL:(NSURL *)u display:(BOOL)d completionHandler:(void (^ _Nullable)(NSDocument * _Nullable, BOOL, NSError * _Nullable))h;
- (nullable NSArray<NSURL *> *)URLsFromRunningOpenPanel; - (NSInteger)runModalOpenPanel:(NSOpenPanel *)p forTypes:(nullable NSArray<NSString *> *)t;
- (void)beginOpenPanel:(NSOpenPanel *)p forTypes:(nullable NSArray<NSString *> *)t completionHandler:(void (^ _Nullable)(NSInteger))h;
- (IBAction)newDocument:(nullable id)s; - (IBAction)openDocument:(nullable id)s; - (IBAction)saveAllDocuments:(nullable id)s;
- (IBAction)clearRecentDocuments:(nullable id)s;
- (void)noteNewRecentDocumentURL:(NSURL *)u; - (void)noteNewRecentDocument:(NSDocument *)d;
- (void)closeAllDocumentsWithDelegate:(nullable id)d didCloseAllSelector:(nullable SEL)s contextInfo:(nullable void *)c;
- (void)reviewUnsavedDocumentsWithAlertTitle:(nullable NSString *)t cancellable:(BOOL)c delegate:(nullable id)d didReviewAllSelector:(nullable SEL)s contextInfo:(nullable void *)ctx;
- (BOOL)presentError:(NSError *)e; - (NSError *)willPresentError:(NSError *)e;
- (BOOL)validateUserInterfaceItem:(nullable id)i; - (BOOL)validateMenuItem:(NSMenuItem *)i;
- (NSString *)_untitledName;
@end
@interface NSWindowController (MWDocumentAPI)
- (NSString *)windowTitleForDocumentDisplayName:(NSString *)n; - (void)synchronizeWindowTitleWithDocumentName; - (void)setDocumentEdited:(BOOL)f;
@end
/* ============================================================================================ tracking, layout */
@interface NSTrackingArea : NSObject <NSCopying>
- (instancetype)initWithRect:(NSRect)r options:(NSTrackingAreaOptions)o owner:(nullable id)owner userInfo:(NSDictionary *)u;
@property(readonly) NSRect rect;
@property(readonly) NSTrackingAreaOptions options;
@property(readonly, assign) id owner;
@property(readonly, copy) NSDictionary *userInfo;
@end
@interface NSLayoutConstraint : NSObject
+ (instancetype)constraintWithItem:(nullable id)a attribute:(NSLayoutAttribute)aa relatedBy:(NSLayoutRelation)r toItem:(nullable id)b attribute:(NSLayoutAttribute)ba
    multiplier:(CGFloat)m constant:(CGFloat)c;
+ (NSArray<NSLayoutConstraint *> *)constraintsWithVisualFormat:(NSString *)f options:(NSLayoutFormatOptions)o metrics:(NSDictionary *)m views:(NSDictionary *)v;
+ (void)activateConstraints:(NSArray<NSLayoutConstraint *> *)c;
+ (void)deactivateConstraints:(NSArray<NSLayoutConstraint *> *)c;
@property(readonly, assign) id firstItem, secondItem;
@property(readonly) NSLayoutAttribute firstAttribute, secondAttribute;
@property(readonly) NSLayoutRelation relation;
@property(readonly) CGFloat multiplier;
@property CGFloat constant;
@property NSLayoutPriority priority;
@property(getter=isActive) BOOL active;
@property BOOL shouldBeArchived;
@property(copy) NSString *identifier;
@end
@interface NSLayoutAnchor : NSObject
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)a;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)a;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)a;
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor *)a constant:(CGFloat)c;
@end
@interface NSLayoutXAxisAnchor : NSLayoutAnchor
- (NSLayoutConstraint *)constraintEqualToSystemSpacingAfterAnchor:(NSLayoutXAxisAnchor *)a multiplier:(CGFloat)m;
@end
@interface NSLayoutYAxisAnchor : NSLayoutAnchor
- (NSLayoutConstraint *)constraintEqualToSystemSpacingBelowAnchor:(NSLayoutYAxisAnchor *)a multiplier:(CGFloat)m;
@end
@interface NSLayoutDimension : NSLayoutAnchor
- (NSLayoutConstraint *)constraintEqualToConstant:(CGFloat)c;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToConstant:(CGFloat)c;
- (NSLayoutConstraint *)constraintLessThanOrEqualToConstant:(CGFloat)c;
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m;
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutDimension *)a multiplier:(CGFloat)m;
@end
@interface NSLayoutGuide : NSObject { @public BOOL _mwSafeArea; /* scion: the owner's safe area, not its bounds */ }
@property(assign) NSView *owningView;
@property(copy) NSString *identifier;
@property(readonly) NSRect frame;
@property(readonly) NSLayoutXAxisAnchor *leadingAnchor, *trailingAnchor, *leftAnchor, *rightAnchor, *centerXAnchor;
@property(readonly) NSLayoutYAxisAnchor *topAnchor, *bottomAnchor, *centerYAnchor;
@property(readonly) NSLayoutDimension *widthAnchor, *heightAnchor;
@end
@interface NSView (NSLayoutGuideSupport)
- (void)addLayoutGuide:(NSLayoutGuide *)g; - (void)removeLayoutGuide:(NSLayoutGuide *)g;
@property(readonly, copy) NSArray<NSLayoutGuide *> *layoutGuides;
@property(readonly, retain) NSLayoutGuide *safeAreaLayoutGuide, *layoutMarginsGuide;
@end
@interface NSAnimationContext : NSObject
+ (void)runAnimationGroup:(void (^)(NSAnimationContext *c))changes completionHandler:(void (^ _Nullable)(void))done;
+ (void)runAnimationGroup:(void (^)(NSAnimationContext *c))changes;
+ (void)beginGrouping; + (void)endGrouping;
@property(nullable, class, readonly) NSAnimationContext *currentContext;
@property NSTimeInterval duration;
@property BOOL allowsImplicitAnimation;
@property(retain) id timingFunction;
@property(copy) void (^completionHandler)(void);
@end

/* ============================================================================================ controls */
@class NSText;
@interface NSCell : NSObject <NSCopying>
@property(copy) NSString *stringValue, *title;
@property(retain) id objectValue;
@property(retain) NSFont *font;
@property NSTextAlignment alignment;
@property NSLineBreakMode lineBreakMode;
@property NSControlSize controlSize;
@property NSControlStateValue state;
@property(getter=isEnabled) BOOL enabled;
@property(getter=isEditable) BOOL editable;
@property(getter=isSelectable) BOOL selectable;
@property(getter=isBordered) BOOL bordered;
@property(getter=isBezeled) BOOL bezeled;
@property(getter=isScrollable) BOOL scrollable;
@property BOOL wraps, truncatesLastVisibleLine, usesSingleLineMode;
@property NSInteger tag;
@property SEL action;
@property(assign) id target;
- (instancetype)initTextCell:(NSString *)s; - (instancetype)initImageCell:(nullable NSImage *)i;
@property(nullable, retain) NSImage *image; @property NSInteger type; @property(getter=isHighlighted) BOOL highlighted;
@property int intValue; @property NSInteger integerValue; @property float floatValue; @property double doubleValue; @property(readonly) BOOL boolValue;
@property(copy) NSAttributedString *attributedStringValue; @property(nullable, assign) NSView *controlView; @property(retain) id formatter, representedObject;
@property(readonly) NSSize cellSize; - (NSSize)cellSizeForBounds:(NSRect)r;
- (void)drawWithFrame:(NSRect)f inView:(nullable NSView *)v; - (void)drawInteriorWithFrame:(NSRect)f inView:(nullable NSView *)v;
- (NSRect)titleRectForBounds:(NSRect)r; - (NSRect)imageRectForBounds:(NSRect)r; - (NSRect)drawingRectForBounds:(NSRect)r;
- (void)highlight:(BOOL)f withFrame:(NSRect)r inView:(nullable NSView *)v;
@property NSInteger backgroundStyle; @property(readonly) NSInteger interiorBackgroundStyle;
@property BOOL sendsActionOnEndEditing, allowsMixedState, showsFirstResponder, refusesFirstResponder, allowsEditingTextAttributes, importsGraphics, allowsUndo;
@property(getter=isContinuous) BOOL continuous; @property NSInteger nextState; - (void)setNextState;
@property NSFocusRingType focusRingType; @property(nullable, retain) NSMenu *menu; @property(readonly) BOOL acceptsFirstResponder;
@property NSInteger controlTint, baseWritingDirection, userInterfaceLayoutDirection;
@property(copy) NSString *keyEquivalent;
- (BOOL)trackMouse:(NSEvent *)e inRect:(NSRect)r ofView:(nullable NSView *)v untilMouseUp:(BOOL)u;
- (NSRect)expansionFrameWithFrame:(NSRect)f inView:(nullable NSView *)v;
- (NSUInteger)hitTestForEvent:(NSEvent *)e inRect:(NSRect)r ofView:(nullable NSView *)v;
- (void)resetCursorRect:(NSRect)r inView:(nullable NSView *)v; - (void)endEditing:(NSText *)t;
- (void)drawFocusRingMaskWithFrame:(NSRect)f inView:(nullable NSView *)v; - (NSRect)focusRingMaskBoundsForFrame:(NSRect)f inView:(nullable NSView *)v;
@end
@interface NSControl : NSView
@property(assign) id target;
@property SEL action;
@property(copy) NSString *stringValue;
@property(copy) NSAttributedString *attributedStringValue;
@property(retain) id objectValue;
@property int intValue;
@property NSInteger integerValue;
@property float floatValue;
@property double doubleValue;
@property(retain) NSFont *font;
@property NSTextAlignment alignment;
@property NSLineBreakMode lineBreakMode;
@property NSControlSize controlSize;
@property(getter=isEnabled) BOOL enabled;
@property(getter=isContinuous) BOOL continuous;
@property(getter=isHighlighted) BOOL highlighted;
@property BOOL usesSingleLineMode, refusesFirstResponder;
@property(retain) id formatter;
@property(nullable, retain) NSCell *cell;
@property(class) Class cellClass;
- (BOOL)sendAction:(nullable SEL)a to:(nullable id)t;
- (void)sizeToFit;
- (NSSize)sizeThatFits:(NSSize)s;
- (void)takeStringValueFrom:(nullable id)s; - (void)takeIntValueFrom:(nullable id)s; - (void)takeDoubleValueFrom:(nullable id)s;
- (void)performClick:(nullable id)s;
@end
@interface NSButton : NSControl <NSUserInterfaceValidations>
+ (instancetype)buttonWithTitle:(NSString *)t target:(nullable id)tg action:(nullable SEL)a;
+ (instancetype)buttonWithImage:(NSImage *)i target:(nullable id)tg action:(nullable SEL)a;
+ (instancetype)buttonWithTitle:(NSString *)t image:(NSImage *)i target:(nullable id)tg action:(nullable SEL)a;
+ (instancetype)checkboxWithTitle:(NSString *)t target:(nullable id)tg action:(nullable SEL)a;
+ (instancetype)radioButtonWithTitle:(NSString *)t target:(nullable id)tg action:(nullable SEL)a;
@property(copy) NSString *title, *alternateTitle, *keyEquivalent;
@property(nullable, copy) NSAttributedString *attributedTitle;
@property NSControlStateValue state;
@property NSBezelStyle bezelStyle;
@property NSEventModifierFlags keyEquivalentModifierMask;
@property(nullable, retain) NSImage *image, *alternateImage;
@property NSImageScaling imageScaling;
@property NSInteger imagePosition;
@property(retain) NSColor *bezelColor, *contentTintColor;
@property(getter=isBordered) BOOL bordered;
@property(getter=isTransparent) BOOL transparent;
@property BOOL allowsMixedState, showsBorderOnlyWhileMouseInside, hasDestructiveAction;
- (void)setButtonType:(NSButtonType)t;
- (void)setNextState;
- (void)highlight:(BOOL)f;
@end
/* NSStatusBar: icons in the notification area (statusbar.m) */
#define NSVariableStatusItemLength (-1)
#define NSSquareStatusItemLength (-2)
typedef NS_OPTIONS(NSUInteger, NSStatusItemBehavior) { NSStatusItemBehaviorRemovalAllowed = 1 << 1, NSStatusItemBehaviorTerminationOnRemoval = 1 << 2 };
@class NSStatusItem;
APPKIT_EXTERN NSDictionary<NSString *, id> *_NSDictionaryOfVariableBindings(NSString *commaSeparatedKeys, id firstValue, ...);
#define NSDictionaryOfVariableBindings(...) _NSDictionaryOfVariableBindings(@"" # __VA_ARGS__, __VA_ARGS__, nil)
@interface NSStatusBar : NSObject
@property(class, readonly, strong) NSStatusBar *systemStatusBar NS_SWIFT_NAME(system);
- (NSStatusItem *)statusItemWithLength:(CGFloat)l;
- (void)removeStatusItem:(NSStatusItem *)i;
@property(readonly) CGFloat thickness;
@property(readonly, getter=isVertical) BOOL vertical;
@end
@interface NSStatusBarButton : NSButton
@property BOOL appearsDisabled;
@end
@interface NSStatusItem : NSObject
@property(readonly) NSStatusBar *statusBar;
@property CGFloat length;
@property(retain, nullable) NSMenu *menu;
@property(readonly, nullable) NSStatusBarButton *button;
@property NSStatusItemBehavior behavior;
@property(getter=isVisible) BOOL visible;
@property(copy, nullable) NSString *autosaveName;
@property(retain, nullable) NSView *view;
@property(nullable) SEL action, doubleAction;
@property(assign, nullable) id target;
@property(copy, nullable) NSString *title, *toolTip;
@property(copy, nullable) NSAttributedString *attributedTitle;
@property(retain, nullable) NSImage *image, *alternateImage;
@property BOOL highlightMode;
@property(getter=isEnabled) BOOL enabled;
- (NSInteger)sendActionOn:(NSInteger)m;
- (void)popUpStatusItemMenu:(NSMenu *)m;
- (void)drawStatusBarBackgroundInRect:(NSRect)r withHighlight:(BOOL)h;
@end
@interface NSControl (MWSendActionOn)
- (NSInteger)sendActionOn:(NSInteger)m;
@end
enum { NSNoCellMask = 0, NSContentsCellMask = 1, NSPushInCellMask = 2, NSChangeGrayCellMask = 4, NSChangeBackgroundCellMask = 8 };
@interface NSTextField : NSControl <NSUserInterfaceValidations>
+ (instancetype)labelWithString:(NSString *)s;
+ (instancetype)wrappingLabelWithString:(NSString *)s;
+ (instancetype)labelWithAttributedString:(NSAttributedString *)s;
+ (instancetype)textFieldWithString:(NSString *)s;
@property(nullable, copy) NSString *placeholderString;
@property(nullable, copy) NSAttributedString *placeholderAttributedString;
@property(retain) NSColor *textColor, *backgroundColor;
@property(getter=isEditable) BOOL editable;
@property(getter=isSelectable) BOOL selectable;
@property(getter=isBordered) BOOL bordered;
@property(getter=isBezeled) BOOL bezeled;
@property BOOL drawsBackground, allowsEditingTextAttributes, importsGraphics, allowsDefaultTighteningForTruncation;
@property CGFloat preferredMaxLayoutWidth;
@property NSInteger maximumNumberOfLines;
@property(assign) id<NSTextFieldDelegate> delegate;
- (void)selectText:(nullable id)s;
@end
@interface NSSecureTextField : NSTextField @end
@interface NSSearchField : NSTextField @end
@interface NSSegmentedControl : NSControl
+ (instancetype)segmentedControlWithLabels:(NSArray<NSString *> *)l trackingMode:(NSSegmentSwitchTracking)m target:(nullable id)t action:(nullable SEL)a;
+ (instancetype)segmentedControlWithImages:(NSArray<NSImage *> *)i trackingMode:(NSSegmentSwitchTracking)m target:(nullable id)t action:(nullable SEL)a;
@property NSInteger segmentCount, selectedSegment;
@property(readonly) NSInteger indexOfSelectedItem;
@property NSSegmentSwitchTracking trackingMode;
@property NSSegmentDistribution segmentDistribution;
@property NSSegmentStyle segmentStyle;
@property(retain) NSColor *selectedSegmentBezelColor;
- (void)setLabel:(NSString *)l forSegment:(NSInteger)s; - (NSString *)labelForSegment:(NSInteger)s;
- (void)setWidth:(CGFloat)w forSegment:(NSInteger)s; - (CGFloat)widthForSegment:(NSInteger)s;
- (void)setEnabled:(BOOL)e forSegment:(NSInteger)s; - (BOOL)isEnabledForSegment:(NSInteger)s;
- (void)setSelected:(BOOL)f forSegment:(NSInteger)s; - (BOOL)isSelectedForSegment:(NSInteger)s;
- (void)setImage:(NSImage *)i forSegment:(NSInteger)s; - (NSImage *)imageForSegment:(NSInteger)s;
- (void)setToolTip:(NSString *)t forSegment:(NSInteger)s; - (void)setTag:(NSInteger)t forSegment:(NSInteger)s;
- (NSInteger)tagForSegment:(NSInteger)s; - (BOOL)selectSegmentWithTag:(NSInteger)t;
- (void)setMenu:(NSMenu *)m forSegment:(NSInteger)s;
@end
@interface NSSwitch : NSControl
@property NSControlStateValue state;
@end
@interface NSSlider : NSControl
+ (instancetype)sliderWithTarget:(nullable id)t action:(nullable SEL)a;
+ (instancetype)sliderWithValue:(double)v minValue:(double)mn maxValue:(double)mx target:(nullable id)t action:(nullable SEL)a;
@property double minValue, maxValue, altIncrementValue;
@property NSInteger numberOfTickMarks;
@property BOOL allowsTickMarkValuesOnly;
@property(getter=isVertical) BOOL vertical;
@property(retain) NSColor *trackFillColor;
@end
@interface NSStepper : NSControl
@property double minValue, maxValue, increment;
@property BOOL valueWraps, autorepeat;
@end
@interface NSPopUpButton : NSButton
- (instancetype)initWithFrame:(NSRect)r pullsDown:(BOOL)f;
+ (instancetype)popUpButtonWithMenu:(NSMenu *)m target:(nullable id)t action:(nullable SEL)a;
+ (instancetype)pullDownButtonWithTitle:(NSString *)t menu:(NSMenu *)m;
@property(nullable, retain) NSMenu *menu;
@property BOOL pullsDown, autoenablesItems;
@property(readonly) NSInteger numberOfItems, indexOfSelectedItem;
@property(readonly, copy) NSArray<NSMenuItem *> *itemArray;
@property(readonly, copy) NSArray<NSString *> *itemTitles;
@property(readonly, retain) NSMenuItem *selectedItem, *lastItem;
@property(readonly, copy) NSString *titleOfSelectedItem;
@property(readonly) NSInteger selectedTag;
- (void)addItemWithTitle:(NSString *)t; - (void)addItemsWithTitles:(NSArray<NSString *> *)t;
- (void)insertItemWithTitle:(NSString *)t atIndex:(NSInteger)i;
- (void)removeItemWithTitle:(NSString *)t; - (void)removeItemAtIndex:(NSInteger)i; - (void)removeAllItems;
- (void)selectItem:(NSMenuItem *)i; - (void)selectItemAtIndex:(NSInteger)i; - (void)selectItemWithTitle:(NSString *)t; - (BOOL)selectItemWithTag:(NSInteger)t;
- (nullable NSMenuItem *)itemAtIndex:(NSInteger)i; - (nullable NSMenuItem *)itemWithTitle:(NSString *)t; - (NSString *)itemTitleAtIndex:(NSInteger)i;
- (NSInteger)indexOfItemWithTitle:(NSString *)t; - (NSInteger)indexOfItemWithTag:(NSInteger)t; - (NSInteger)indexOfItem:(NSMenuItem *)i;
- (void)synchronizeTitleAndSelectedItem;
@end
@interface NSColorWell : NSControl
@property(copy) NSColor *color;
@end
@interface NSProgressIndicator : NSView
@property double doubleValue, minValue, maxValue;
@property(getter=isIndeterminate) BOOL indeterminate;
@property(getter=isDisplayedWhenStopped) BOOL displayedWhenStopped;
@property BOOL usesThreadedAnimation;
@property NSProgressIndicatorStyle style;
@property NSControlSize controlSize;
- (void)startAnimation:(nullable id)s; - (void)stopAnimation:(nullable id)s; - (void)incrementBy:(double)d; - (void)sizeToFit;
@end
@interface NSImageView : NSControl
+ (instancetype)imageViewWithImage:(NSImage *)i;
@property(nullable, retain) NSImage *image;
@property NSImageScaling imageScaling;
@property(retain) NSColor *contentTintColor;
@property(getter=isEditable) BOOL editable;
@property BOOL animates;
@end
@interface NSBox : NSView
@property NSBoxType boxType;
@property NSTitlePosition titlePosition;
@property(copy) NSString *title;
@property(retain) NSColor *fillColor, *borderColor;
@property CGFloat borderWidth, cornerRadius;
@property(getter=isTransparent) BOOL transparent;
@property NSSize contentViewMargins;
@property(nullable, retain) NSView *contentView;
@end
@interface NSVisualEffectView : NSView
@property NSVisualEffectMaterial material;
@property NSVisualEffectBlendingMode blendingMode;
@property NSVisualEffectState state;
@property(getter=isEmphasized) BOOL emphasized;
@property(retain) NSImage *maskImage;
@end
@interface NSClipView : NSView
@property(nullable, retain) NSView *documentView;
@property(retain) NSColor *backgroundColor;
@property BOOL drawsBackground;
@end
@interface NSScrollView : NSView
@property(nullable, retain) NSView *documentView;
@property(nullable, retain) NSClipView *contentView;
@property BOOL hasVerticalScroller, hasHorizontalScroller, autohidesScrollers, drawsBackground, allowsMagnification;
@property NSBorderType borderType;
@property(retain) NSColor *backgroundColor;
@property(readonly) NSSize contentSize;
@property CGFloat magnification;
@end
@class NSScroller;
@interface NSClipView (MWScrolling)
@property(readonly) NSRect documentRect, documentVisibleRect;
- (NSRect)constrainBoundsRect:(NSRect)r; - (void)scrollToPoint:(NSPoint)p; - (void)viewFrameChanged:(NSNotification *)n;
@end
@interface NSScrollView (MWScrolling)
- (void)reflectScrolledClipView:(NSClipView *)c; @property(readonly) NSRect documentVisibleRect; - (void)tile; - (void)flashScrollers;
@property(retain) NSScroller *verticalScroller, *horizontalScroller;
@end
@interface NSView (MWScrolling) @property(nullable, readonly, assign) NSScrollView *enclosingScrollView; - (NSRect)_mwVisible; @end
@interface NSScrollView (MWSizes)
+ (NSSize)frameSizeForContentSize:(NSSize)s hasHorizontalScroller:(BOOL)h hasVerticalScroller:(BOOL)v borderType:(NSBorderType)b;
+ (NSSize)contentSizeForFrameSize:(NSSize)s hasHorizontalScroller:(BOOL)h hasVerticalScroller:(BOOL)v borderType:(NSBorderType)b;
@property BOOL usesPredominantAxisScrolling; @end

typedef NS_ENUM(NSInteger, NSScrollerStyle) { NSScrollerStyleLegacy = 0, NSScrollerStyleOverlay = 1 };
typedef NS_ENUM(NSInteger, NSScrollerKnobStyle) { NSScrollerKnobStyleDefault = 0, NSScrollerKnobStyleDark = 1, NSScrollerKnobStyleLight = 2 };
typedef NS_ENUM(NSUInteger, NSScrollerPart) { NSScrollerNoPart = 0, NSScrollerDecrementPage = 1, NSScrollerKnob = 2, NSScrollerIncrementPage = 3,
    NSScrollerDecrementLine = 4, NSScrollerIncrementLine = 5, NSScrollerKnobSlot = 6 };
typedef NS_ENUM(NSUInteger, NSUsableScrollerParts) { NSNoScrollerParts = 0, NSOnlyScrollerArrows = 1, NSAllScrollerParts = 2 };
@interface NSScroller : NSControl
+ (CGFloat)scrollerWidthForControlSize:(NSControlSize)s scrollerStyle:(NSScrollerStyle)st; + (CGFloat)scrollerWidth;
@property(class, readonly) NSScrollerStyle preferredScrollerStyle; @property(class, readonly, getter=isCompatibleWithOverlayScrollers) BOOL compatibleWithOverlayScrollers;
@property CGFloat knobProportion; @property NSScrollerStyle scrollerStyle; @property NSScrollerKnobStyle knobStyle;
@property(readonly) NSScrollerPart hitPart; @property(readonly) NSUsableScrollerParts usableParts;
- (NSRect)rectForPart:(NSScrollerPart)p; - (NSScrollerPart)testPart:(NSPoint)p;
- (void)drawKnob; - (void)drawKnobSlotInRect:(NSRect)r highlight:(BOOL)h;
@end

/* ============================================================================================ cells and tables (nib.m, table.m) */
@interface NSActionCell : NSCell @end
@interface NSTextFieldCell : NSActionCell @property(retain) NSColor *textColor, *backgroundColor; @property BOOL drawsBackground; @property(nullable, copy) NSString *placeholderString;
@property(nullable, copy) NSAttributedString *placeholderAttributedString; @property NSInteger bezelStyle; @property(copy) NSArray *allowedInputSourceLocales;
- (void)setWantsNotificationForMarkedText:(BOOL)f; @end
@interface NSButtonCell : NSActionCell
@property NSBezelStyle bezelStyle; @property(copy) NSString *alternateTitle; @property(nullable, retain) NSImage *alternateImage;
@property NSInteger imagePosition, imageScaling, highlightsBy, showsStateBy; @property NSEventModifierFlags keyEquivalentModifierMask;
@property(getter=isTransparent) BOOL transparent; @property BOOL imageDimsWhenDisabled, showsBorderOnlyWhileMouseInside;
@property(retain) NSColor *backgroundColor; @property(nullable, copy) NSAttributedString *attributedTitle, *attributedAlternateTitle; @property(retain) id sound;
- (void)setButtonType:(NSButtonType)t;
- (void)drawBezelWithFrame:(NSRect)f inView:(nullable NSView *)v; - (void)drawImage:(NSImage *)i withFrame:(NSRect)f inView:(nullable NSView *)v;
- (NSRect)drawTitle:(NSAttributedString *)t withFrame:(NSRect)f inView:(nullable NSView *)v;
- (void)mouseEntered:(NSEvent *)event NS_SWIFT_NAME(mouseEntered(with:)); - (void)mouseExited:(NSEvent *)event NS_SWIFT_NAME(mouseExited(with:));
@end
@interface NSPopUpButtonCell : NSButtonCell @property BOOL pullsDown, autoenablesItems, usesItemFromMenu, altersStateOfSelectedItem;
@property NSInteger preferredEdge, arrowPosition; - (instancetype)initTextCell:(NSString *)s pullsDown:(BOOL)p; @end
@interface NSSearchFieldCell : NSTextFieldCell @end
@interface NSSecureTextFieldCell : NSTextFieldCell @end
@interface NSTableHeaderCell : NSTextFieldCell @end
@interface NSSegmentedCell : NSActionCell @end
@interface NSImageCell : NSActionCell @property NSImageScaling imageScaling; @property NSInteger imageAlignment, imageFrameStyle; @end
@interface NSSliderCell : NSActionCell @end
@interface NSComboBoxCell : NSTextFieldCell @end
@class NSTableView, NSOutlineView;
typedef NS_OPTIONS(NSUInteger, NSTableColumnResizingOptions) { NSTableColumnNoResizing = 0, NSTableColumnAutoresizingMask = 1, NSTableColumnUserResizingMask = 2 };
@interface NSTableColumn : NSObject
- (instancetype)initWithIdentifier:(NSUserInterfaceItemIdentifier)i;
@property(copy) NSUserInterfaceItemIdentifier identifier; @property(assign) NSTableView *tableView;
@property CGFloat width, minWidth, maxWidth; @property(copy) NSString *title, *headerToolTip;
@property(retain) id headerCell, dataCell; @property(getter=isEditable) BOOL editable; @property(getter=isHidden) BOOL hidden;
@property NSTableColumnResizingOptions resizingMask; @property(nullable, copy) NSSortDescriptor *sortDescriptorPrototype;
- (void)sizeToFit; - (id)dataCellForRow:(NSInteger)r;
@end
@interface NSTableHeaderView : NSView
@property(assign) NSTableView *tableView;
- (NSRect)headerRectOfColumn:(NSInteger)c; - (NSInteger)columnAtPoint:(NSPoint)p;
@end
typedef NS_OPTIONS(NSUInteger, NSTableViewGridLineStyle) { NSTableViewGridNone = 0, NSTableViewSolidVerticalGridLineMask = 1, NSTableViewSolidHorizontalGridLineMask = 2, NSTableViewDashedHorizontalGridLineMask = 8 };
typedef NS_ENUM(NSUInteger, NSTableViewColumnAutoresizingStyle) { NSTableViewNoColumnAutoresizing = 0, NSTableViewUniformColumnAutoresizingStyle,
    NSTableViewSequentialColumnAutoresizingStyle, NSTableViewReverseSequentialColumnAutoresizingStyle, NSTableViewLastColumnOnlyAutoresizingStyle, NSTableViewFirstColumnOnlyAutoresizingStyle };
typedef NS_OPTIONS(NSUInteger, NSTableViewAnimationOptions) { NSTableViewAnimationEffectNone = 0, NSTableViewAnimationEffectFade = 1, NSTableViewAnimationEffectGap = 2,
    NSTableViewAnimationSlideUp = 0x10, NSTableViewAnimationSlideDown = 0x20, NSTableViewAnimationSlideLeft = 0x30, NSTableViewAnimationSlideRight = 0x40 };
typedef NS_ENUM(NSUInteger, NSTableViewDropOperation) { NSTableViewDropOn, NSTableViewDropAbove };
typedef NS_ENUM(NSInteger, NSTableViewSelectionHighlightStyle) { NSTableViewSelectionHighlightStyleNone = -1, NSTableViewSelectionHighlightStyleRegular = 0, NSTableViewSelectionHighlightStyleSourceList = 1 };
typedef NS_ENUM(NSInteger, NSTableViewStyle) { NSTableViewStyleAutomatic, NSTableViewStyleFullWidth, NSTableViewStyleInset, NSTableViewStyleSourceList, NSTableViewStylePlain };
APPKIT_EXTERN NSNotificationName const NSTableViewSelectionDidChangeNotification, NSTableViewSelectionIsChangingNotification,
    NSTableViewColumnDidMoveNotification, NSTableViewColumnDidResizeNotification;
@protocol NSTableViewDataSource <NSObject> @optional
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t;
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)r;
- (void)tableView:(NSTableView *)t setObjectValue:(nullable id)v forTableColumn:(NSTableColumn *)c row:(NSInteger)r;
@end
@protocol NSTableViewDelegate <NSObject> @optional
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)r;
- (void)tableView:(NSTableView *)t willDisplayCell:(nullable id)cell forTableColumn:(NSTableColumn *)c row:(NSInteger)r;
- (CGFloat)tableView:(NSTableView *)t heightOfRow:(NSInteger)r;
- (BOOL)tableView:(NSTableView *)t shouldSelectRow:(NSInteger)r;
- (void)tableView:(NSTableView *)t mouseDownInHeaderOfTableColumn:(NSTableColumn *)c;
- (void)tableView:(NSTableView *)t didClickTableColumn:(NSTableColumn *)c;
- (void)tableViewSelectionDidChange:(NSNotification *)n;
@end
typedef NS_ENUM(NSInteger, NSBackgroundStyle) { NSBackgroundStyleNormal = 0, NSBackgroundStyleEmphasized = 1, NSBackgroundStyleRaised = 2, NSBackgroundStyleLowered = 3,
    NSBackgroundStyleLight = 0, NSBackgroundStyleDark = 1 };
/* view-based tables (table.m) */
@interface NSTableRowView : NSView
@property(getter=isSelected) BOOL selected;
@property(getter=isGroupRowStyle) BOOL groupRowStyle;
@property(getter=isEmphasized) BOOL emphasized;
@property(getter=isFloating) BOOL floating;
@property(getter=isTargetForDropOperation) BOOL targetForDropOperation;
@property(getter=isNextRowSelected) BOOL nextRowSelected;
@property(getter=isPreviousRowSelected) BOOL previousRowSelected;
@property NSTableViewSelectionHighlightStyle selectionHighlightStyle;
@property(retain) NSColor *backgroundColor;
@property(readonly) NSBackgroundStyle interiorBackgroundStyle;
@property(readonly) NSInteger numberOfColumns;
- (void)drawBackgroundInRect:(NSRect)r; - (void)drawSelectionInRect:(NSRect)r; - (void)drawSeparatorInRect:(NSRect)r;
- (void)drawDraggingDestinationFeedbackInRect:(NSRect)r;
- (nullable id)viewAtColumn:(NSInteger)c;
@end
@interface NSTableCellView : NSView
@property(retain, nullable) id objectValue;
@property(assign, nullable) NSTextField *textField;
@property(assign, nullable) NSImageView *imageView;
@property NSBackgroundStyle backgroundStyle;
@property NSInteger rowSizeStyle;
@property(retain, nullable) NSArray *draggingImageComponents;
@end
@interface NSTableView : NSControl
@property(assign) id dataSource; @property(assign) id delegate;
@property(nullable, retain) NSTableHeaderView *headerView; @property(nullable, retain) NSView *cornerView;
@property CGFloat rowHeight; @property NSSize intercellSpacing;
@property BOOL allowsMultipleSelection, allowsEmptySelection, allowsColumnSelection, allowsColumnReordering, allowsColumnResizing,
    usesAlternatingRowBackgroundColors, allowsTypeSelect, verticalMotionCanBeginDrag, floatsGroupRows, usesAutomaticRowHeights;
@property(retain) NSColor *backgroundColor, *gridColor; @property NSTableViewGridLineStyle gridStyleMask;
@property NSTableViewColumnAutoresizingStyle columnAutoresizingStyle; @property NSTableViewSelectionHighlightStyle selectionHighlightStyle;
@property NSTableViewStyle style;
@property SEL doubleAction; @property(nullable, copy) NSString *autosaveName; @property BOOL autosaveTableColumns;
@property(copy) NSArray<NSSortDescriptor *> *sortDescriptors; @property(retain) NSTableColumn *highlightedTableColumn;
@property(readonly, copy) NSArray<NSTableColumn *> *tableColumns; @property(readonly) NSInteger numberOfColumns, numberOfRows;
@property(readonly) NSInteger selectedRow, selectedColumn, numberOfSelectedRows, clickedRow, clickedColumn, editedRow, editedColumn;
@property(readonly, copy) NSIndexSet *selectedRowIndexes, *selectedColumnIndexes;
- (void)addTableColumn:(NSTableColumn *)c; - (void)removeTableColumn:(NSTableColumn *)c; - (void)moveColumn:(NSInteger)from toColumn:(NSInteger)to;
- (NSInteger)columnWithIdentifier:(NSUserInterfaceItemIdentifier)i; - (nullable NSTableColumn *)tableColumnWithIdentifier:(NSUserInterfaceItemIdentifier)i;
- (void)tile; - (void)sizeLastColumnToFit; - (void)reloadData; - (void)noteNumberOfRowsChanged;
- (void)reloadDataForRowIndexes:(NSIndexSet *)r columnIndexes:(NSIndexSet *)c; - (void)noteHeightOfRowsWithIndexesChanged:(NSIndexSet *)r;
- (void)beginUpdates; - (void)endUpdates;
- (void)insertRowsAtIndexes:(NSIndexSet *)i withAnimation:(NSTableViewAnimationOptions)a; - (void)removeRowsAtIndexes:(NSIndexSet *)i withAnimation:(NSTableViewAnimationOptions)a;
- (void)moveRowAtIndex:(NSInteger)a toIndex:(NSInteger)b;
- (NSRect)rectOfRow:(NSInteger)r; - (NSRect)rectOfColumn:(NSInteger)c; - (NSRect)frameOfCellAtColumn:(NSInteger)c row:(NSInteger)r;
- (NSInteger)rowAtPoint:(NSPoint)p; - (NSInteger)columnAtPoint:(NSPoint)p; - (NSRange)rowsInRect:(NSRect)r; - (NSIndexSet *)columnIndexesInRect:(NSRect)r;
- (BOOL)isRowSelected:(NSInteger)r; - (void)selectRowIndexes:(NSIndexSet *)i byExtendingSelection:(BOOL)e;
- (void)selectRow:(NSInteger)r byExtendingSelection:(BOOL)e; - (void)deselectRow:(NSInteger)r; - (void)deselectAll:(nullable id)s; - (void)selectAll:(nullable id)s;
- (void)selectColumnIndexes:(NSIndexSet *)i byExtendingSelection:(BOOL)e; - (void)deselectColumn:(NSInteger)c;
- (void)editColumn:(NSInteger)c row:(NSInteger)r withEvent:(nullable NSEvent *)e select:(BOOL)s;
- (void)scrollRowToVisible:(NSInteger)r; - (void)scrollColumnToVisible:(NSInteger)c;
- (NSCell *)preparedCellAtColumn:(NSInteger)c row:(NSInteger)r;
- (void)drawRow:(NSInteger)r clipRect:(NSRect)clip; - (void)drawBackgroundInClipRect:(NSRect)c; - (void)highlightSelectionInClipRect:(NSRect)c; - (void)drawGridInClipRect:(NSRect)c;
- (nullable id)makeViewWithIdentifier:(NSUserInterfaceItemIdentifier)i owner:(nullable id)o;
- (nullable id)viewAtColumn:(NSInteger)c row:(NSInteger)r makeIfNecessary:(BOOL)m; - (nullable id)rowViewAtRow:(NSInteger)r makeIfNecessary:(BOOL)m;
- (NSInteger)rowForView:(NSView *)v; - (NSInteger)columnForView:(NSView *)v;
- (void)registerNib:(nullable NSNib *)n forIdentifier:(NSUserInterfaceItemIdentifier)i;
- (void)enumerateAvailableRowViewsUsingBlock:(void (^)(id rowView, NSInteger row))b;
- (void)setIndicatorImage:(nullable NSImage *)i inTableColumn:(NSTableColumn *)c; - (nullable NSImage *)indicatorImageInTableColumn:(NSTableColumn *)c;
- (void)setDraggingSourceOperationMask:(NSDragOperation)m forLocal:(BOOL)l; - (void)setDropRow:(NSInteger)r dropOperation:(NSTableViewDropOperation)o;
@end
APPKIT_EXTERN NSNotificationName const NSOutlineViewItemWillExpandNotification, NSOutlineViewItemDidExpandNotification,
    NSOutlineViewItemWillCollapseNotification, NSOutlineViewItemDidCollapseNotification, NSOutlineViewSelectionDidChangeNotification;
@protocol NSOutlineViewDataSource <NSObject> @optional
- (NSInteger)outlineView:(NSOutlineView *)o numberOfChildrenOfItem:(nullable id)i;
- (id)outlineView:(NSOutlineView *)o child:(NSInteger)n ofItem:(nullable id)i;
- (BOOL)outlineView:(NSOutlineView *)o isItemExpandable:(nullable id)i;
- (nullable id)outlineView:(NSOutlineView *)o objectValueForTableColumn:(nullable NSTableColumn *)c byItem:(nullable id)i;
@end
@protocol NSOutlineViewDelegate <NSObject> @optional
- (BOOL)outlineView:(NSOutlineView *)o shouldExpandItem:(nullable id)i; - (BOOL)outlineView:(NSOutlineView *)o shouldCollapseItem:(nullable id)i;
- (BOOL)outlineView:(NSOutlineView *)o shouldSelectItem:(nullable id)i;
- (void)outlineView:(NSOutlineView *)o willDisplayCell:(nullable id)cell forTableColumn:(nullable NSTableColumn *)c item:(nullable id)i;
@end
@interface NSOutlineView : NSTableView
@property CGFloat indentationPerLevel; @property BOOL autoresizesOutlineColumn, indentationMarkerFollowsCell, autosaveExpandedItems;
@property(assign) NSTableColumn *outlineTableColumn;
- (nullable id)itemAtRow:(NSInteger)r; - (NSInteger)rowForItem:(nullable id)i; - (NSInteger)levelForRow:(NSInteger)r; - (NSInteger)levelForItem:(nullable id)i;
- (nullable id)parentForItem:(nullable id)i; - (NSInteger)childIndexForItem:(nullable id)i;
- (NSInteger)numberOfChildrenOfItem:(nullable id)i; - (nullable id)child:(NSInteger)n ofItem:(nullable id)i;
- (BOOL)isExpandable:(nullable id)i; - (BOOL)isItemExpanded:(nullable id)i;
- (void)expandItem:(nullable id)i; - (void)expandItem:(nullable id)i expandChildren:(BOOL)a;
- (void)collapseItem:(nullable id)i; - (void)collapseItem:(nullable id)i collapseChildren:(BOOL)a;
- (void)reloadItem:(nullable id)i; - (void)reloadItem:(nullable id)i reloadChildren:(BOOL)c;
- (void)insertItemsAtIndexes:(NSIndexSet *)i inParent:(nullable id)p withAnimation:(NSTableViewAnimationOptions)a;
- (void)removeItemsAtIndexes:(NSIndexSet *)i inParent:(nullable id)p withAnimation:(NSTableViewAnimationOptions)a;
- (NSRect)frameOfOutlineCellAtRow:(NSInteger)r; - (void)setDropItem:(nullable id)i dropChildIndex:(NSInteger)c;
@end
@interface NSText : NSView
@property(copy) NSString *string;
@property(retain) NSFont *font;
@property(retain) NSColor *textColor, *backgroundColor;
@property(getter=isEditable) BOOL editable;
@property(getter=isSelectable) BOOL selectable;
@property BOOL drawsBackground, richText;
@property NSRange selectedRange;
@end
APPKIT_EXTERN NSNotificationName const NSTextDidBeginEditingNotification, NSTextDidEndEditingNotification, NSTextDidChangeNotification, NSTextViewDidChangeSelectionNotification;
@class NSTextView;
@protocol NSTextDelegate <NSObject>
@optional
- (BOOL)textShouldBeginEditing:(NSText *)t; - (BOOL)textShouldEndEditing:(NSText *)t;
- (void)textDidBeginEditing:(NSNotification *)n; - (void)textDidEndEditing:(NSNotification *)n; - (void)textDidChange:(NSNotification *)n;
@end
@protocol NSTextViewDelegate <NSTextDelegate>
@optional
- (BOOL)textView:(NSTextView *)v doCommandBySelector:(SEL)s;
- (BOOL)textView:(NSTextView *)v shouldChangeTextInRange:(NSRange)r replacementString:(nullable NSString *)s;
- (void)textViewDidChangeSelection:(NSNotification *)n;
@end
@interface NSTextView : NSText
+ (NSScrollView *)scrollableTextView; + (NSScrollView *)scrollablePlainDocumentContentTextView; + (NSScrollView *)scrollableDocumentContentTextView;
- (instancetype)initWithFrame:(NSRect)r textContainer:(nullable NSTextContainer *)c;
- (void)insertText:(nullable id)s replacementRange:(NSRange)r;
- (void)scrollRangeToVisible:(NSRange)r;
@property NSSize textContainerInset;
@property(nullable, assign) id<NSTextViewDelegate> delegate;
@property(nullable, readonly) NSTextStorage *textStorage;
@property(nullable, readonly) NSLayoutManager *layoutManager;
@property(nullable, retain) NSTextContainer *textContainer;
@property(copy) NSDictionary<NSAttributedStringKey, id> *typingAttributes;
@property(copy) NSArray<NSValue *> *selectedRanges;
@property(retain) NSColor *insertionPointColor;
@property BOOL allowsUndo, fieldEditor, verticallyResizable, horizontallyResizable;
@property NSSize minSize, maxSize;
- (BOOL)shouldChangeTextInRange:(NSRange)r replacementString:(nullable NSString *)s;
- (void)didChangeText;
@end
@interface NSStackView : NSView
+ (instancetype)stackViewWithViews:(NSArray<NSView *> *)v;
@property NSUserInterfaceLayoutOrientation orientation;
@property NSLayoutAttribute alignment;
@property NSStackViewDistribution distribution;
@property CGFloat spacing;
@property NSEdgeInsets edgeInsets;
@property BOOL detachesHiddenViews;
@property(assign) id<NSStackViewDelegate> delegate;
@property(readonly, copy) NSArray<NSView *> *arrangedSubviews, *views, *detachedViews;
- (void)addArrangedSubview:(NSView *)v; - (void)insertArrangedSubview:(NSView *)v atIndex:(NSInteger)i; - (void)removeArrangedSubview:(NSView *)v;
- (void)addView:(NSView *)v inGravity:(NSStackViewGravity)g; - (void)insertView:(NSView *)v atIndex:(NSUInteger)i inGravity:(NSStackViewGravity)g;
- (void)removeView:(NSView *)v;
- (void)setViews:(NSArray<NSView *> *)v inGravity:(NSStackViewGravity)g; - (NSArray<NSView *> *)viewsInGravity:(NSStackViewGravity)g;
- (void)setCustomSpacing:(CGFloat)s afterView:(NSView *)v; - (CGFloat)customSpacingAfterView:(NSView *)v;
- (void)setHuggingPriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o;
- (void)setClippingResistancePriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o;
- (void)setVisibilityPriority:(float)p forView:(NSView *)v;
@end
@interface NSGridCell : NSObject
@property(nullable, retain) NSView *contentView;
@property NSGridCellPlacement xPlacement, yPlacement;
@property NSGridRowAlignment rowAlignment;
@property(readonly, assign) NSGridColumn *column;
@property(readonly, assign) NSGridRow *row;
@property(copy) NSArray<NSLayoutConstraint *> *customPlacementConstraints;
+ (NSView *)emptyContentView;
@end
@interface NSGridColumn : NSObject
@property NSGridCellPlacement xPlacement;
@property CGFloat width, leadingPadding, trailingPadding;
@property(getter=isHidden) BOOL hidden;
@property(readonly) NSInteger numberOfCells;
- (nullable NSGridCell *)cellAtIndex:(NSInteger)i;
- (void)mergeCellsInRange:(NSRange)r;
@end
@interface NSGridRow : NSObject
@property NSGridCellPlacement yPlacement;
@property NSGridRowAlignment rowAlignment;
@property CGFloat height, topPadding, bottomPadding;
@property(getter=isHidden) BOOL hidden;
@property(readonly) NSInteger numberOfCells;
- (nullable NSGridCell *)cellAtIndex:(NSInteger)i;
- (void)mergeCellsInRange:(NSRange)r;
@end
@interface NSGridView : NSView
+ (instancetype)gridViewWithNumberOfColumns:(NSInteger)c rows:(NSInteger)r;
+ (instancetype)gridViewWithViews:(NSArray<NSArray<NSView *> *> *)rows;
@property(readonly) NSInteger numberOfRows, numberOfColumns;
@property NSGridCellPlacement xPlacement, yPlacement;
@property NSGridRowAlignment rowAlignment;
@property CGFloat rowSpacing, columnSpacing;
- (NSGridRow *)rowAtIndex:(NSInteger)i; - (NSGridColumn *)columnAtIndex:(NSInteger)i;
- (NSInteger)indexOfRow:(NSGridRow *)r; - (NSInteger)indexOfColumn:(NSGridColumn *)c;
- (NSGridCell *)cellAtColumnIndex:(NSInteger)c rowIndex:(NSInteger)r; - (NSGridCell *)cellForView:(NSView *)v;
- (NSGridRow *)addRowWithViews:(NSArray<NSView *> *)v; - (NSGridRow *)insertRowAtIndex:(NSInteger)i withViews:(NSArray<NSView *> *)v;
- (NSGridColumn *)addColumnWithViews:(NSArray<NSView *> *)v;
- (void)removeRowAtIndex:(NSInteger)i; - (void)removeColumnAtIndex:(NSInteger)i;
- (void)mergeCellsInHorizontalRange:(NSRange)h verticalRange:(NSRange)v;
@end
@interface NSSplitView : NSView
@property(getter=isVertical) BOOL vertical;
@property CGFloat dividerThickness;
@end
@interface NSTabViewItem : NSObject
- (instancetype)initWithIdentifier:(nullable id)i;
+ (instancetype)tabViewItemWithViewController:(NSViewController *)vc;
@property(copy) NSString *label;
@property(retain) NSView *view;
@property(retain) id identifier;
@end
@interface NSTabView : NSView
- (void)addTabViewItem:(NSTabViewItem *)i; - (void)selectTabViewItemAtIndex:(NSInteger)i;
@property(readonly, copy) NSArray<NSTabViewItem *> *tabViewItems;
@property(nullable, readonly, retain) NSTabViewItem *selectedTabViewItem;
@end

NS_ASSUME_NONNULL_END
