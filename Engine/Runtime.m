#ifdef ABT_HOST_TEST
#import "HostRuntime.h"
#import "../ABTPaths.h"
#else
#import <UIKit/UIKit.h>
#import <Contacts/Contacts.h>
#import "../ABTPaths.h"
#import <substrate.h>
#import <mach-o/dyld.h>
#include <dlfcn.h>
#endif
#import "ABTCore.h"
#import "ABTCallURL.h"
#import "ABC26Model.h"
#import "ABC26Store.h"
#include <stdatomic.h>
#ifndef ABT_WORKSPACE_CLASS_NAME
#define ABT_WORKSPACE_CLASS_NAME @"LSApplicationWorkspace"
#endif
#ifndef ABT_EXTENSION_CLASS_NAME
#define ABT_EXTENSION_CLASS_NAME @"NSExtensionContext"
#endif
#ifndef ABT_CONTACTS_ADAPTER_CLASS_NAME
#define ABT_CONTACTS_ADAPTER_CLASS_NAME @"CNLaunchServicesLocalAdapter"
#endif

static BOOL ABTCallsBundle(NSString *bundle) {
    return [@[@"com.apple.mobilephone",@"com.apple.facetime",@"com.apple.MobileAddressBook",@"com.apple.ContactsUI.ContactsViewService",@"com.apple.ContactsUI.ContactViewViewService"] containsObject:bundle];
}

static NSString *const ABTPrefs = @"/var/mobile/Library/Preferences/net.tateu.askbeforecallingtoo11.plist";
static NSMutableDictionary *ABTReport;
static BOOL ABTCallsProcess, ABTMessagesProcess, ABTMailProcess, ABTContactServiceProcess;
static BOOL ABTForegroundCallUI(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (app.applicationState == UIApplicationStateActive) return YES;
    if (!ABTContactServiceProcess) return NO;
    // A hosted card's foreground scene can remain active while its service's
    // application state is inactive. Require an attached, visible foreground
    // window; never grant this exception to ordinary/background app processes.
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (!window.hidden && window.rootViewController.viewIfLoaded.window) return YES;
    }
    return NO;
}
static void ABTRecord(NSString *key, id value) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ ABTRecord(key,value); }); return; }
    if (!ABTReport) ABTReport = [NSMutableDictionary new];
    ABTReport[key] = value;
    ABTReport[@"build"] = @"1.0";
    ABTReport[@"process"] = NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName;
    NSString *dir = ABTPath(@"/var/mobile/Library/Logs");
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [ABTReport writeToFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"AskBeforeCallingToo26-%@.plist", ABTReport[@"process"]]] atomically:YES];
}
static NSDictionary *ABTSettings(void) {
    NSDictionary *stored = [[[ABC26Store alloc] initWithPath:ABTPath(ABTPrefs) schema:@{}] read:nil];
    // On malformed preferences, keep the three protections enabled and ignore the whitelist.
    NSMutableDictionary *settings = [@{@"enabled":@YES, @"phoneCallsEnabled":@YES, @"messagesEnabled":@YES, @"emailEnabled":@YES, @"messagesMatchAllRecipients":@YES, @"emailMatchAllRecipients":@YES} mutableCopy];
    for (NSString *key in settings.allKeys) if ([stored[key] isKindOfClass:NSNumber.class]) settings[key] = @([stored[key] boolValue]);
    for (NSString *key in @[@"swapButtonOrder", @"whitelistAllContacts"]) settings[key] = @([stored[key] isKindOfClass:NSNumber.class] && [stored[key] boolValue]);
    for (NSString *key in @[@"customTitle", @"customMessage", @"customMessageForMessages", @"customMessageForEmail", @"customYes", @"customCancel"]) if ([stored[key] isKindOfClass:NSString.class]) settings[key] = stored[key];
    settings[@"whitelist"] = ABC26Whitelist(stored ?: @{}) ?: @{};
    if ([stored[@"whitelistAddresses"] isKindOfClass:NSDictionary.class]) settings[@"whitelistAddresses"] = stored[@"whitelistAddresses"];
    return settings;
}
static NSArray<NSString *> *ABTStrings(id value) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *strings = [NSMutableArray new];
    for (id item in value) {
        if ([item isKindOfClass:NSString.class]) [strings addObject:[item copy]];
        else [strings addObject:@""]; // Unknown recipients must not disappear from an all-match check.
    }
    return strings;
}
static NSString *ABTString(id value) {
    if ([value isKindOfClass:NSString.class]) return [value copy];
    if ([value isKindOfClass:NSAttributedString.class]) return [[value string] copy];
    return @"";
}
static NSArray *ABTMailRecipients(id controller) {
    NSMutableArray *result = [NSMutableArray new];
    for (NSString *name in @[@"toRecipients", @"ccRecipients", @"bccRecipients"]) {
        id recipients = ABTGet(controller,name);
        if (![recipients isKindOfClass:NSArray.class]) continue;
        for (id recipient in recipients) {
            NSString *address = [recipient isKindOfClass:NSString.class] ? recipient : ABTString(ABTGet(recipient,@"address"));
            if (!address.length) address = ABTString(ABTGet(recipient,@"emailAddress"));
            [result addObject:address ?: @""];
        }
    }
    return result;
}
static NSDictionary *ABTCompositionSnapshot(id composition) {
    NSMutableArray *media = [NSMutableArray new];
    id objects = ABTGet(composition,@"mediaObjects");
    if ([objects isKindOfClass:NSArray.class]) for (id object in objects) {
        // Retain identities only in memory. No message bodies or addresses go into diagnostics.
        [media addObject:[NSValue valueWithNonretainedObject:object]];
    }
    id payload = ABTGet(composition,@"shelfPluginPayload");
    return @{@"text":ABTString(ABTGet(composition,@"text")), @"subject":ABTString(ABTGet(composition,@"subject")), @"media":[media copy], @"payload":payload ? [NSValue valueWithNonretainedObject:payload] : NSNull.null};
}
static NSSet *ABTAllowedAddresses(NSDictionary *settings, BOOL allContacts) {
    NSMutableSet *allowed = [NSMutableSet new];
    NSDictionary *whitelist = settings[@"whitelist"];
    NSDictionary *saved = settings[@"whitelistAddresses"];
    for (NSString *identifier in whitelist) for (NSString *address in ABTStrings(saved[identifier])) {
        NSString *value = ABTNormalize(address); if (value.length) [allowed addObject:value];
    }
    CNAuthorizationStatus status = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
    if (status != CNAuthorizationStatusAuthorized && status != CNAuthorizationStatusLimited) return allowed;
    if (!allContacts && !whitelist.count) return allowed;
    CNContactStore *store = [CNContactStore new];
    CNContactFetchRequest *fetch = [[CNContactFetchRequest alloc] initWithKeysToFetch:@[CNContactIdentifierKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey]];
    if (!allContacts) fetch.predicate = [CNContact predicateForContactsWithIdentifiers:whitelist.allKeys];
    @try {
        [store enumerateContactsWithFetchRequest:fetch error:nil usingBlock:^(CNContact *contact, BOOL *stop) {
            for (CNLabeledValue<CNPhoneNumber *> *phone in contact.phoneNumbers) { NSString *value = ABTNormalize(phone.value.stringValue); if (value.length) [allowed addObject:value]; }
            for (CNLabeledValue<NSString *> *email in contact.emailAddresses) { NSString *value = ABTNormalize(email.value); if (value.length) [allowed addObject:value]; }
        }];
    } @catch (__unused NSException *exception) { /* Unavailable contacts never grant an exemption. */ }
    return allowed;
}
static UIViewController *ABTPresenter(UIViewController *preferred) {
    if (!ABTForegroundCallUI()) return nil;
    UIViewController *controller = preferred.viewIfLoaded.window ? preferred : nil;
    if (!controller) for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow && !window.hidden) controller = window.rootViewController;
    }
    while (controller) {
        if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) controller = controller.presentedViewController;
        else if ([controller isKindOfClass:UINavigationController.class]) controller = ((UINavigationController *)controller).visibleViewController;
        else if ([controller isKindOfClass:UITabBarController.class]) controller = ((UITabBarController *)controller).selectedViewController;
        else break;
    }
    if ([controller isKindOfClass:UIAlertController.class] || !controller.viewIfLoaded.window || controller.isBeingDismissed) return nil;
    return controller;
}

@interface ABTTransaction : NSObject
@property(nonatomic,strong) ABTDecision *decision;
@property(nonatomic,strong) UIAlertController *alert;
@property(nonatomic,copy) void (^reply)(BOOL);
@end
@implementation ABTTransaction
@end
static ABTTransaction *ABTPending;
static void ABTResolve(ABTTransaction *transaction, BOOL approved) {
    NSCAssert(NSThread.isMainThread, @"Confirmation must resolve on the main thread");
    if (!transaction || ![transaction.decision finish]) return;
    if (ABTPending == transaction) ABTPending = nil;
    void (^reply)(BOOL) = transaction.reply;
    transaction.reply = nil;
    transaction.alert = nil;
    ABTRecord(@"decision", approved ? @"approved" : @"canceled");
    if (reply) reply(approved);
}
static void ABTBackground(void) {
    ABTTransaction *current = ABTPending;
    [current.alert dismissViewControllerAnimated:NO completion:nil];
    ABTResolve(current,NO);
}
static void ABTWatch(ABTTransaction *transaction) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC/2), dispatch_get_main_queue(), ^{
        if (transaction.decision.finished) return;
        if (transaction.alert && !transaction.alert.presentingViewController) ABTResolve(transaction,NO);
        else ABTWatch(transaction);
    });
}
static void ABTAsk(NSString *kind, NSDictionary *settings, NSArray *recipients, NSString *contactID, UIViewController *presenter, BOOL (^valid)(void), void (^reply)(BOOL)) {
    NSCAssert(NSThread.isMainThread, @"Capture UI state on the main thread");
    if (ABTPending) { ABTRecord(@"duplicateBlocked",@YES); reply(NO); return; }
    ABTTransaction *transaction = [ABTTransaction new]; transaction.decision = [ABTDecision new]; transaction.reply = reply; ABTPending = transaction;
    ABTRecord(@"reached",kind);
    // Whitelist lookups do not block the UI and nothing is forwarded while they run.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        BOOL calls = [kind isEqual:@"calls"];
        BOOL allContacts = calls && [settings[@"whitelistAllContacts"] boolValue];
        BOOL identifierMatch = calls && contactID.length && (allContacts || settings[@"whitelist"][contactID] != nil);
        BOOL all = calls || [settings[[kind isEqual:@"messages"] ? @"messagesMatchAllRecipients" : @"emailMatchAllRecipients"] boolValue];
        BOOL exempt = identifierMatch || ABTWhitelistMatches(recipients, ABTAllowedAddresses(settings,allContacts), all);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (transaction.decision.finished) return;
            if (!valid()) { ABTRecord(@"rejected",@"target changed or unavailable"); ABTResolve(transaction,NO); return; }
            if (exempt) { ABTRecord(@"whitelistBypass",@YES); ABTResolve(transaction,YES); return; }
            UIViewController *host = ABTPresenter(presenter);
            if (!host) { ABTRecord(@"rejected",@"no foreground presenter"); ABTResolve(transaction,NO); return; }
            NSString *recipient = recipients.count ? [recipients componentsJoinedByString:@", "] : @"this recipient";
            NSString *key = calls ? @"customMessage" : [kind isEqual:@"messages"] ? @"customMessageForMessages" : @"customMessageForEmail";
            NSString *fallback = calls ? @"Call {recipient}?" : [kind isEqual:@"messages"] ? @"Send message to {recipient}?" : @"Send email to {recipient}?";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:ABTText(settings,@"customTitle",@"AskBeforeCalling Too 26",recipient) message:ABTText(settings,key,fallback,recipient) preferredStyle:UIAlertControllerStyleAlert];
            transaction.alert = alert;
            __weak ABTTransaction *weakTransaction = transaction;
            UIAlertAction *cancel = [UIAlertAction actionWithTitle:ABTText(settings,@"customCancel",@"Cancel",recipient) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { ABTResolve(weakTransaction,NO); }];
            UIAlertAction *confirm = [UIAlertAction actionWithTitle:ABTText(settings,@"customYes",@"Confirm",recipient) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                ABTTransaction *current = weakTransaction;
                BOOL allow = current && ABTForegroundCallUI() && valid();
                ABTResolve(current,allow);
            }];
            // Both use default style so UIKit does not reorder a cancel-style action.
            // Escape, backgrounding and dismissal still resolve as cancellation below.
            if ([settings[@"swapButtonOrder"] boolValue]) { [alert addAction:confirm]; [alert addAction:cancel]; }
            else { [alert addAction:cancel]; [alert addAction:confirm]; }
            alert.preferredAction = cancel;
            [host presentViewController:alert animated:YES completion:^{ ABTRecord(@"promptPresented",kind); }];
            ABTWatch(transaction);
        });
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!transaction.decision.finished) { [transaction.alert dismissViewControllerAnimated:YES completion:nil]; ABTResolve(transaction,NO); }
    });
}

// UIKit hooks are deliberately at the compose entry, before the original clears a draft.
static void (*ABTOriginalMessages)(id,SEL,id,id);
static void ABTMessages(id owner, SEL command, id composition, id animations) {
    NSDictionary *settings = ABTSettings();
    if (![settings[@"enabled"] boolValue] || ![settings[@"messagesEnabled"] boolValue]) { ABTOriginalMessages(owner,command,composition,animations); return; }
    if (!NSThread.isMainThread) { ABTRecord(@"rejected",@"message send on unexpected thread"); return; }
    id conversation = ABTGet(owner,@"conversation");
    if (!composition || !conversation) { ABTRecord(@"rejected",@"missing message composition or conversation"); return; }
    NSArray *recipients = ABTStrings(ABTGet(conversation,@"recipientStrings"));
    NSDictionary *snapshot = ABTCompositionSnapshot(composition);
    __weak id weakOwner = owner;
    BOOL (^valid)(void) = ^BOOL {
        id current = weakOwner;
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive || ![current isKindOfClass:UIViewController.class] || ![current viewIfLoaded].window || ABTGet(current,@"conversation") != conversation) return NO;
        id draft = ABTGet(current,@"composition");
        return [recipients isEqual:ABTStrings(ABTGet(conversation,@"recipientStrings"))] && [snapshot isEqual:ABTCompositionSnapshot(composition)] && (!draft || [snapshot isEqual:ABTCompositionSnapshot(draft)]);
    };
    id savedAnimations = [animations copy];
    ABTAsk(@"messages",settings,recipients,nil,[owner isKindOfClass:UIViewController.class] ? owner : nil,valid,^(BOOL approved) {
        id current = weakOwner;
        if (approved && current && valid()) ABTOriginalMessages(current,command,composition,savedAnimations);
    });
}
static void (*ABTOriginalMail)(id,SEL,id);
static void ABTMail(id owner, SEL command, id source) {
    NSDictionary *settings = ABTSettings();
    if (![settings[@"enabled"] boolValue] || ![settings[@"emailEnabled"] boolValue]) { ABTOriginalMail(owner,command,source); return; }
    if (!NSThread.isMainThread) { ABTRecord(@"rejected",@"mail send on unexpected thread"); return; }
    NSArray *recipients = ABTMailRecipients(owner);
    __weak id weakOwner = owner;
    BOOL (^valid)(void) = ^BOOL {
        id current = weakOwner;
        return UIApplication.sharedApplication.applicationState == UIApplicationStateActive && [current isKindOfClass:UIViewController.class] && [current viewIfLoaded].window && [recipients isEqual:ABTMailRecipients(current)];
    };
    ABTAsk(@"emails",settings,recipients,nil,[owner isKindOfClass:UIViewController.class] ? owner : nil,valid,^(BOOL approved) {
        id current = weakOwner; if (approved && current && valid()) ABTOriginalMail(current,command,source);
    });
}

// iOS 26.0.1 returns TUCall* or nil, with a one-object completion block.
// The public wrappers already accept nil as the native dial-failure result.
static NSString *const ABTApprovedURLKey = @"com.sahinkaa.askbeforecallingtoo26.approvedURL";
static BOOL ABTURLApproved(NSURL *url) {
    return [url isKindOfClass:NSURL.class] && [NSThread.currentThread.threadDictionary[ABTApprovedURLKey] isEqual:url.absoluteString];
}
static void ABTReplayCallURL(NSURL *url, void (^action)(void)) {
    NSMutableDictionary *thread = NSThread.currentThread.threadDictionary;
    id previous = thread[ABTApprovedURLKey];
    if ([url isKindOfClass:NSURL.class]) thread[ABTApprovedURLKey] = url.absoluteString;
    @try { action(); }
    @finally { if (previous) thread[ABTApprovedURLKey] = previous; else [thread removeObjectForKey:ABTApprovedURLKey]; }
}
static id (*ABTOriginalDial)(id,SEL,id,void (^)(id));
static id ABTDial(id owner, SEL command, id request, void (^completion)(id)) {
    NSDictionary *settings = ABTSettings();
    if (ABTURLApproved(ABTGet(request,@"URL"))) return ABTOriginalDial(owner,command,request,completion);
    if (![settings[@"enabled"] boolValue] || ![settings[@"phoneCallsEnabled"] boolValue] || ABTBool(request,@"isSOS",nil,NO) || ABTBool(owner,@"_isEmergencyDialRequest:",request,YES)) return ABTOriginalDial(owner,command,request,completion);
    id queueObject = ABTGet(owner,@"queue");
    Class queueClass = NSClassFromString(@"OS_dispatch_queue");
    dispatch_queue_t queue = queueClass && [queueObject isKindOfClass:queueClass] ? (dispatch_queue_t)queueObject : NSThread.isMainThread ? dispatch_get_main_queue() : nil;
    id savedRequest = nil;
    if ([request conformsToProtocol:@protocol(NSCopying)]) savedRequest = [request copy];
    if (!queue || !savedRequest) {
        ABTRecord(@"rejected",@"cannot capture safe call replay");
        // Do not invoke a callback on an unverified queue.
        if (queue && completion) dispatch_async(queue, ^{ completion(nil); });
        return nil;
    }
    NSString *contactID = ABTString(ABTGet(savedRequest,@"contactIdentifier"));
    id handle = ABTGet(savedRequest,@"handle");
    NSString *address = ABTString(ABTGet(handle,@"value"));
    dispatch_async(dispatch_get_main_queue(), ^{
        ABTAsk(@"calls",settings,address.length ? @[address] : @[],contactID,nil,^BOOL {
            return ABTForegroundCallUI();
        },^(BOOL approved) {
            dispatch_async(queue, ^{
                if (approved) ABTReplayCallURL(ABTGet(savedRequest,@"URL"), ^{ id call = ABTOriginalDial(owner,command,savedRequest,completion); (void)call; });
                else if (completion) completion(nil);
            });
        });
    });
    return nil;
}

@protocol ABTNativeURLRequest <NSObject>
- (instancetype)initWithURL:(NSURL *)url;
@end
static id ABTNativeRequestForURL(NSURL *url) {
    Class cls = NSClassFromString(@"TUDialRequest");
#ifndef ABT_HOST_TEST
    // Contact-card extensions can open a tel: URL without having loaded TU.
    // Load the existing system framework before the native emergency check;
    // otherwise the old "classification unavailable" fallback would allow it.
    if (!cls) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{ dlopen("/System/Library/PrivateFrameworks/TelephonyUtilities.framework/TelephonyUtilities",RTLD_LAZY|RTLD_LOCAL); });
        cls = NSClassFromString(@"TUDialRequest");
        ABTRecord(@"telephony.frameworkAvailable",@(cls != Nil));
    }
#endif
    if (!ABTSignature(class_getInstanceMethod(cls,@selector(initWithURL:)),"@",@[@"@"])) return nil;
    @try { return [(id<ABTNativeURLRequest>)[cls alloc] initWithURL:url]; }
    @catch (__unused NSException *exception) { return nil; }
}
static BOOL ABTShouldGateURL(NSURL *url, NSDictionary **settings, NSDictionary **info) {
    *info = ABTCallURLInfo(url);
    if (!*info || ABTURLApproved(url)) return NO;
    *settings = ABTSettings();
    return [(*settings)[@"enabled"] boolValue] && [(*settings)[@"phoneCallsEnabled"] boolValue];
}
static void ABTConfirmURL(NSURL *url, NSDictionary *settings, NSDictionary *info, void (^reply)(BOOL)) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ ABTConfirmURL(url,settings,info,reply); }); return; }
    ABTRecord(@"callURL.reached",@YES);
    ABTRecord(@"callURL.scheme",info[@"scheme"]);
    ABTRecord(@"callUI.applicationState",@(UIApplication.sharedApplication.applicationState));
    ABTRecord(@"callUI.sceneCount",@(UIApplication.sharedApplication.connectedScenes.count));
    id request = ABTNativeRequestForURL(url);
    id center = ABTGet(NSClassFromString(@"TUCallCenter"),@"sharedInstance");
    BOOL canCheckEmergency = request && center && ABTSignature(class_getInstanceMethod(object_getClass(center),NSSelectorFromString(@"_isEmergencyDialRequest:")),"B",@[@"@"]);
    if (!canCheckEmergency) {
        // Safety takes precedence when the system cannot classify an emergency call.
        // The dialer constructs TUDialRequest before opening its URL, so this path
        // is diagnostic fallback rather than an expected normal Phone path.
        ABTRecord(@"callURL.bypass",@"system emergency classification unavailable"); reply(YES); return;
    }
    if (ABTBool(request,@"isSOS",nil,NO) || ABTBool(center,@"_isEmergencyDialRequest:",request,YES)) {
        ABTRecord(@"callURL.bypass",@"system emergency request"); reply(YES); return;
    }
    NSString *contactID = ABTString(ABTGet(request,@"contactIdentifier"));
    ABTAsk(@"calls",settings,@[info[@"recipient"]],contactID,nil,^BOOL {
        return ABTForegroundCallUI();
    },reply);
}
// The iOS 26 dialer opens TUDialRequest.URL through this UIApplication endpoint.
// It does not enter TUCallCenter._dialWithRequest:completion: in Phone's process.
static void (*ABTOriginalOpenURL)(id,SEL,NSURL *,id,id,void (^)(BOOL));
static void ABTOpenURL(id owner, SEL command, NSURL *url, id options, id endpoint, void (^completion)(BOOL)) {
    NSDictionary *settings = nil, *info = nil;
    if (!ABTShouldGateURL(url,&settings,&info)) { ABTOriginalOpenURL(owner,command,url,options,endpoint,completion); return; }
    NSURL *savedURL = [url copy];
    id savedOptions = [options isKindOfClass:NSDictionary.class] ? [options copy] : options;
    ABTConfirmURL(savedURL,settings,info,^(BOOL approved) {
        if (approved) ABTReplayCallURL(savedURL, ^{ ABTOriginalOpenURL(owner,command,savedURL,savedOptions,endpoint,completion); });
        else if (completion) completion(NO);
    });
}
// The deprecated synchronous URL opener has a separate system implementation.
// Return native failure while consent is pending; never claim it already opened.
static BOOL (*ABTOriginalLegacyOpenURL)(id,SEL,NSURL *);
static BOOL ABTLegacyOpenURL(id owner, SEL command, NSURL *url) {
    NSDictionary *settings = nil, *info = nil;
    if (!ABTShouldGateURL(url,&settings,&info)) return ABTOriginalLegacyOpenURL(owner,command,url);
    NSURL *savedURL = [url copy];
    ABTConfirmURL(savedURL,settings,info,^(BOOL approved) {
        if (approved) ABTReplayCallURL(savedURL, ^{ BOOL opened = ABTOriginalLegacyOpenURL(owner,command,savedURL); (void)opened; });
    });
    return NO;
}

// Contact cards can run in a separate extension process and open through their
// NSExtensionContext instead of UIApplication or a local workspace. This is the
// public void API with a one-BOOL callback; do not substitute the LS error ABI.
static void (*ABTOriginalExtensionOpen)(id,SEL,NSURL *,void (^)(BOOL));
static void ABTExtensionOpen(id owner, SEL command, NSURL *url, void (^completion)(BOOL)) {
    NSDictionary *settings = nil, *info = nil;
    if (!ABTShouldGateURL(url,&settings,&info)) { ABTOriginalExtensionOpen(owner,command,url,completion); return; }
    ABTRecord(@"callContactExtension.reached",@YES);
    NSURL *savedURL = [url copy];
    ABTConfirmURL(savedURL,settings,info,^(BOOL approved) {
        if (approved) ABTReplayCallURL(savedURL, ^{ ABTOriginalExtensionOpen(owner,command,savedURL,completion); });
        else if (completion) completion(NO);
    });
}

static NSError *ABTCallCanceled(void) {
    return [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:@{NSLocalizedDescriptionKey:@"Call canceled."}];
}
// Number-row default actions schedule CNLaunchServicesLocalAdapter on a
// background scheduler. Its native BOOL/NSError reply resolves the Contacts
// promise. Its openSensitiveURL:withOptions:error: backend does NOT enter
// LSApplicationWorkspace.commonClientOpenURL (a distinct implementation).
// Hold this void asynchronous adapter, not the synchronous BOOL/error** API.
static void (*ABTOriginalContactsAdapter)(id,SEL,NSURL *,id,void (^)(BOOL,NSError *));
static void ABTContactsAdapter(id owner, SEL command, NSURL *url, id options, void (^completion)(BOOL,NSError *)) {
    ABTRecord(@"callContactNumber.reached",@YES);
    ABTRecord(@"callContactNumber.scheme",[url isKindOfClass:NSURL.class] ? (url.scheme.lowercaseString ?: @"none") : @"not URL");
    NSDictionary *settings = nil, *info = nil;
    if (!ABTShouldGateURL(url,&settings,&info)) { ABTOriginalContactsAdapter(owner,command,url,options,completion); return; }
    NSURL *savedURL = [url copy];
    id savedOptions = [options isKindOfClass:NSDictionary.class] ? [options copy] : options;
    // The system already invokes this adapter off the UI thread. The examined
    // implementation has no queue affinity; replay stays off the UI thread and
    // retains only its asynchronous block, never any NSError** caller storage.
    ABTConfirmURL(savedURL,settings,info,^(BOOL approved) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
            if (approved) ABTReplayCallURL(savedURL, ^{ ABTOriginalContactsAdapter(owner,command,savedURL,savedOptions,completion); });
            else if (completion) completion(NO,ABTCallCanceled());
        });
    });
}

// ContactsUICore's dial-request opener returns a CNFuture to its caller, but its
// actual side effect is this separate void method, with ONE NSError* callback.
// Gate here so the native future remains pending and is resolved by its own adapter.
static void (*ABTOriginalLaunchDial)(id,SEL,id,void (^)(NSError *));
static void ABTLaunchDial(id owner, SEL command, id request, void (^completion)(NSError *)) {
    ABTRecord(@"callLaunch.reached",@YES);
    NSDictionary *settings = ABTSettings();
    if (![settings[@"enabled"] boolValue] || ![settings[@"phoneCallsEnabled"] boolValue] || ABTURLApproved(ABTGet(request,@"URL")) || ABTBool(request,@"isSOS",nil,NO) || ABTBool(owner,@"_isEmergencyDialRequest:",request,YES)) {
        ABTOriginalLaunchDial(owner,command,request,completion); return;
    }
    id saved = [request conformsToProtocol:@protocol(NSCopying)] ? [request copy] : nil;
    id interface = ABTGet(owner,@"callServicesInterface");
    id queueObject = ABTGet(interface,@"queue") ?: ABTGet(owner,@"queue");
    Class queueClass = NSClassFromString(@"OS_dispatch_queue");
    dispatch_queue_t queue = queueClass && [queueObject isKindOfClass:queueClass] ? (dispatch_queue_t)queueObject : NSThread.isMainThread ? dispatch_get_main_queue() : nil;
    if (!saved || !queue) {
        ABTRecord(@"callLaunch.rejected",@"cannot capture request and callback queue");
        if (queue && completion) dispatch_async(queue, ^{ completion(ABTCallCanceled()); });
        return;
    }
    NSString *address = ABTString(ABTGet(ABTGet(saved,@"handle"),@"value"));
    NSString *contactID = ABTString(ABTGet(saved,@"contactIdentifier"));
    dispatch_async(dispatch_get_main_queue(), ^{
        ABTAsk(@"calls",settings,address.length ? @[address] : @[],contactID,nil,^BOOL {
            return ABTForegroundCallUI();
        },^(BOOL approved) {
            dispatch_async(queue, ^{
                if (approved) ABTReplayCallURL(ABTGet(saved,@"URL"), ^{ ABTOriginalLaunchDial(owner,command,saved,completion); });
                else if (completion) completion(ABTCallCanceled());
            });
        });
    });
}

// Direct LaunchServices clients bypass UIApplication. All observed workspace
// configuration-based URL wrappers converge here. Legacy options/error wrappers
// use a separate backend. Its completion has TWO OBJECT arguments, unlike
// UIKit's one-BOOL completion and TUCallCenter launch's one-error completion.
static void (*ABTOriginalWorkspaceOpen)(id,SEL,NSURL *,id,id,BOOL,void (^)(id,NSError *));
static void ABTWorkspaceOpen(id owner, SEL command, NSURL *url, id options, id configuration, BOOL synchronous, void (^completion)(id,NSError *)) {
    NSDictionary *settings = nil, *info = nil;
    if (!ABTShouldGateURL(url,&settings,&info)) { ABTOriginalWorkspaceOpen(owner,command,url,options,configuration,synchronous,completion); return; }
    // Classify emergencies before returning a synchronous failure to any wrapper.
    id nativeRequest = ABTNativeRequestForURL(url);
    id nativeCenter = ABTGet(NSClassFromString(@"TUCallCenter"),@"sharedInstance");
    BOOL emergencyCheck = nativeRequest && nativeCenter && ABTSignature(class_getInstanceMethod(object_getClass(nativeCenter),NSSelectorFromString(@"_isEmergencyDialRequest:")),"B",@[@"@"]);
    if (!emergencyCheck || ABTBool(nativeRequest,@"isSOS",nil,NO) || ABTBool(nativeCenter,@"_isEmergencyDialRequest:",nativeRequest,YES)) {
        ABTRecord(@"callWorkspace.bypass",emergencyCheck ? @"system emergency request" : @"system emergency classification unavailable");
        ABTOriginalWorkspaceOpen(owner,command,url,options,configuration,synchronous,completion); return;
    }
    ABTRecord(@"callWorkspace.reached",@YES);
    ABTRecord(@"callWorkspace.synchronous",@(synchronous));
    NSURL *savedURL = [url copy];
    id savedOptions = [options isKindOfClass:NSDictionary.class] ? [options copy] : options;
    id savedConfiguration = [configuration conformsToProtocol:@protocol(NSCopying)] ? [configuration copy] : configuration;
    if (synchronous) {
        // A sync wrapper's result/error storage belongs to its caller's stack.
        // Complete it before returning. Never retain/reuse that callback after
        // return; approved transport replay gets an independent heap block.
        if (completion) completion(nil,ABTCallCanceled());
        ABTConfirmURL(savedURL,settings,info,^(BOOL approved) {
            if (!approved) return;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
                ABTReplayCallURL(savedURL, ^{
                    ABTOriginalWorkspaceOpen(owner,command,savedURL,savedOptions,savedConfiguration,YES,^(id result,NSError *error) {
                        if (error) ABTRecord(@"callWorkspace.replayFailed",@YES);
                    });
                });
            });
        });
    } else {
        ABTConfirmURL(savedURL,settings,info,^(BOOL approved) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
                if (approved) ABTReplayCallURL(savedURL, ^{ ABTOriginalWorkspaceOpen(owner,command,savedURL,savedOptions,savedConfiguration,NO,completion); });
                else if (completion) completion(nil,ABTCallCanceled());
            });
        });
    }
}

static void ABTInstall(Class cls, NSString *name, const char *result, NSArray *arguments, IMP hook, IMP *original) {
    if (*original || !cls) return;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(cls,selector);
    NSString *key = [NSString stringWithFormat:@"hook.%@.%@",NSStringFromClass(cls),name];
    if (!ABTSignature(method,result,arguments)) { ABTRecord(key,method ? [@"rejected ABI: " stringByAppendingString:@(method_getTypeEncoding(method))] : @"missing"); return; }
    MSHookMessageEx(cls,selector,hook,original);
    ABTRecord(key,*original ? @"installed" : @"installation failed");
}
static void ABTInstallHooks(void) {
    if (ABTCallsProcess) {
        ABTInstall(NSClassFromString(@"TUCallCenter"),@"_dialWithRequest:completion:","@",@[@"@",@"@?"],(IMP)ABTDial,(IMP *)&ABTOriginalDial);
        ABTInstall(UIApplication.class,@"_openURL:options:openApplicationEndpoint:completionHandler:","v",@[@"@",@"@",@"@",@"@?"],(IMP)ABTOpenURL,(IMP *)&ABTOriginalOpenURL);
        ABTInstall(UIApplication.class,@"_openURL:","B",@[@"@"],(IMP)ABTLegacyOpenURL,(IMP *)&ABTOriginalLegacyOpenURL);
        ABTInstall(NSClassFromString(@"TUCallCenter"),@"launchAppForDialRequest:completion:","v",@[@"@",@"@?"],(IMP)ABTLaunchDial,(IMP *)&ABTOriginalLaunchDial);
        ABTInstall(NSClassFromString(ABT_WORKSPACE_CLASS_NAME),@"commonClientOpenURL:options:configuration:synchronous:completionHandler:","v",@[@"@",@"@",@"@",@"B",@"@?"],(IMP)ABTWorkspaceOpen,(IMP *)&ABTOriginalWorkspaceOpen);
        ABTInstall(NSClassFromString(ABT_CONTACTS_ADAPTER_CLASS_NAME),@"openSensitiveURLInBackground:withOptions:withReply:","v",@[@"@",@"@",@"@?"],(IMP)ABTContactsAdapter,(IMP *)&ABTOriginalContactsAdapter);
        ABTInstall(NSClassFromString(ABT_EXTENSION_CLASS_NAME),@"openURL:completionHandler:","v",@[@"@",@"@?"],(IMP)ABTExtensionOpen,(IMP *)&ABTOriginalExtensionOpen);
    }
    if (ABTMessagesProcess) ABTInstall(NSClassFromString(@"CKChatController"),@"sendComposition:animations:","v",@[@"@",@"@?"],(IMP)ABTMessages,(IMP *)&ABTOriginalMessages);
    if (ABTMailProcess) ABTInstall(NSClassFromString(@"MFMailComposeController"),@"performSend:","v",@[@"@"],(IMP)ABTMail,(IMP *)&ABTOriginalMail);
}
static void ABTImageLoaded(const struct mach_header *header, intptr_t slide) {
    // The callback executes under dyld's loader lock. All Objective-C work is deferred.
    static atomic_bool queued = false;
    if (atomic_exchange(&queued,true)) return;
    dispatch_async(dispatch_get_main_queue(), ^{ atomic_store(&queued,false); ABTInstallHooks(); });
}
#ifndef ABT_HOST_TEST
__attribute__((constructor))
#endif
static void ABTInitialize(void) {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        ABTCallsProcess = ABTCallsBundle(bundle);
        ABTContactServiceProcess = [@[@"com.apple.ContactsUI.ContactsViewService",@"com.apple.ContactsUI.ContactViewViewService"] containsObject:bundle];
        ABTMessagesProcess = [@[@"com.apple.MobileSMS",@"com.apple.mobilesms.compose"] containsObject:bundle];
        ABTMailProcess = [@[@"com.apple.mobilemail",@"com.apple.MailCompositionService"] containsObject:bundle];
        if (!ABTCallsProcess && !ABTMessagesProcess && !ABTMailProcess) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            ABTRecord(@"loaded",@YES);
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                ABTBackground();
            }];
            ABTInstallHooks();
        });
        _dyld_register_func_for_add_image(ABTImageLoaded);
    }
}
