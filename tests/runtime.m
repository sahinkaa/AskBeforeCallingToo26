#define ABT_HOST_TEST 1
#include "../Engine/Runtime.m"
#include <stdlib.h>
static NSUInteger urlOpens, legacyURLOpens, urlCallbacks;
static NSURL *lastOpenedURL;
static id lastOptions, lastEndpoint;
static BOOL nestedLegacyURL, nativeEmergencyAvailable = YES;
static _Atomic NSUInteger workspaceOpens, launchCalls, workspaceCallbacks;
static NSURL *workspaceURL;
static id workspaceOptions, workspaceConfiguration, launchedRequest;
static BOOL bridgeUIKitToWorkspace, bridgeLaunchToWorkspace;
@interface ABTHostWorkspace : NSObject
- (void)commonClientOpenURL:(NSURL *)url options:(id)options configuration:(id)configuration synchronous:(BOOL)synchronous completionHandler:(void (^)(id,NSError *))completion;
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(id)options;
- (void)openURL:(NSURL *)url configuration:(id)configuration completionHandler:(void (^)(id,NSError *))completion;
+ (instancetype)defaultWorkspace;
@end
@implementation ABTHostWorkspace
+ (instancetype)defaultWorkspace { static id value;static dispatch_once_t once;dispatch_once(&once,^{value=[self new];});return value; }
- (void)commonClientOpenURL:(NSURL *)url options:(id)options configuration:(id)configuration synchronous:(BOOL)synchronous completionHandler:(void (^)(id,NSError *))completion {
    workspaceOpens++;workspaceURL=url;workspaceOptions=options;workspaceConfiguration=configuration;
    NSCAssert(completion!=nil,@"Native common opener requires a completion even during deferred sync replay");
    completion(@{@"opened":@YES},nil);
}
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(id)options {
    __block BOOL success=NO;__block BOOL callbackReturned=NO;
    [self commonClientOpenURL:url options:options configuration:nil synchronous:YES completionHandler:^(id result,NSError *error){NSCAssert(!callbackReturned,@"Sync completion cannot outlive caller stack");workspaceCallbacks++;success=result!=nil && !error;}];
    callbackReturned=YES;return success;
}
- (void)openURL:(NSURL *)url configuration:(id)configuration completionHandler:(void (^)(id,NSError *))completion { [self commonClientOpenURL:url options:@{} configuration:configuration synchronous:NO completionHandler:completion]; }
@end
// Reproduce the contact-number route from the iOS 26 symbols. The legacy
// options/error workspace backend is separate and never calls commonClientOpenURL.
static _Atomic NSUInteger contactBackendOpens, contactReplies;
static NSURL *contactBackendURL;
static id contactBackendOptions;
static BOOL contactNestedCommon;
@interface ABTHostContactsAdapter : NSObject
- (void)openSensitiveURLInBackground:(NSURL *)url withOptions:(id)options withReply:(void (^)(BOOL,NSError *))reply;
@end
@implementation ABTHostContactsAdapter
- (void)openSensitiveURLInBackground:(NSURL *)url withOptions:(id)options withReply:(void (^)(BOOL,NSError *))reply {
    NSCAssert(!NSThread.isMainThread,@"Contact backend stays off UI thread");
    contactBackendOpens++;contactBackendURL=url;contactBackendOptions=options;
    if(contactNestedCommon) [[ABTHostWorkspace defaultWorkspace] commonClientOpenURL:url options:options configuration:nil synchronous:NO completionHandler:^(id result,NSError *error){if(reply)reply(result!=nil,error);}];
    else if(reply)reply(YES,nil);
}
@end

@interface ABTFuture : NSObject
@property(atomic) BOOL resolved;
@property(atomic,strong) NSError *error;
@end
@implementation ABTFuture @end
static NSUInteger extensionOpens,extensionCallbacks;
static NSURL *extensionURL;
@interface ABTHostExtensionContext : NSObject
- (void)openURL:(NSURL *)url completionHandler:(void (^)(BOOL))completion;
@end
@implementation ABTHostExtensionContext
- (void)openURL:(NSURL *)url completionHandler:(void (^)(BOOL))completion {
    NSCAssert(NSThread.isMainThread,@"Extension UI replay on main thread");extensionOpens++;extensionURL=url;if(completion)completion(YES);
}
@end

@implementation UIView @end
@implementation UIViewController
- (instancetype)init { if((self=[super init])) { _viewIfLoaded=[UIView new]; _viewIfLoaded.window=[UIWindow new]; } return self; }
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion { self.presentedViewController=controller; controller.presentingViewController=self; if(completion) completion(); }
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion { self.presentingViewController.presentedViewController=nil; self.presentingViewController=nil; if(completion) completion(); }
@end
@implementation UINavigationController @end
@implementation UITabBarController @end
@implementation UIWindow @end
@implementation UIScene @end
@implementation UIWindowScene @end
@implementation UIApplication
+ (instancetype)sharedApplication { static id app; static dispatch_once_t once; dispatch_once(&once,^{app=[self new];}); return app; }
- (void)openURL:(NSURL *)url withCompletionHandler:(void (^)(BOOL))completion { [self openURL:url options:@{} completionHandler:completion]; }
- (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion { [self _openURL:url options:options openApplicationEndpoint:nil completionHandler:completion]; }
- (void)_openURL:(NSURL *)url options:(id)options openApplicationEndpoint:(id)endpoint completionHandler:(void (^)(BOOL))completion {
    NSCAssert(NSThread.isMainThread,@"UIKit replay stays on main thread");urlOpens++;lastOpenedURL=url;lastOptions=options;lastEndpoint=endpoint;
    if(bridgeUIKitToWorkspace) [[ABTHostWorkspace defaultWorkspace] commonClientOpenURL:url options:options configuration:nil synchronous:NO completionHandler:^(id result,NSError *error){if(completion)completion(result!=nil && !error);}];
    else if(completion)completion(YES);
}
- (BOOL)_openURL:(NSURL *)url { legacyURLOpens++;if(nestedLegacyURL)[self openURL:url options:@{} completionHandler:nil];return YES; }
@end
@implementation UIAlertAction
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler { UIAlertAction *a=[self new];a.title=title;a.handler=handler;return a; }
@end
@implementation UIAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style { UIAlertController *a=[self new];a.title=title;a.message=message;a.actions=[NSMutableArray new];return a; }
- (void)addAction:(UIAlertAction *)action { [self.actions addObject:action]; }
@end
@implementation CNPhoneNumber @end
@implementation CNLabeledValue @end
@implementation CNContact
+ (NSPredicate *)predicateForContactsWithIdentifiers:(NSArray *)identifiers { return [NSPredicate predicateWithValue:NO]; }
@end
@implementation CNContactFetchRequest
- (instancetype)initWithKeysToFetch:(NSArray *)keys { return [super init]; }
@end
@implementation CNContactStore
+ (CNAuthorizationStatus)authorizationStatusForEntityType:(NSInteger)type { return 2; /* denied */ }
- (BOOL)enumerateContactsWithFetchRequest:(CNContactFetchRequest *)request error:(NSError **)error usingBlock:(void (^)(CNContact *,BOOL *))block { abort(); }
@end

static NSUInteger messagesSent, mailsSent, callsSent, callbacks;
static void *queueKey=&queueKey;
@interface ABTHandle:NSObject
@property(nonatomic,copy) NSString *value;
@end
@implementation ABTHandle @end
@interface ABTDialRequest:NSObject<NSCopying>
@property(nonatomic,strong) ABTHandle *handle;
@property(nonatomic,copy) NSString *contactIdentifier;
@property(nonatomic) BOOL isSOS;
@property(nonatomic,strong) NSURL *URL;
@end
@implementation ABTDialRequest
- (id)copyWithZone:(NSZone *)zone { ABTDialRequest *r=[ABTDialRequest new];r.handle=self.handle;r.contactIdentifier=self.contactIdentifier;r.isSOS=self.isSOS;r.URL=self.URL;return r; }
@end
@interface TUDialRequest:ABTDialRequest
- (instancetype)initWithURL:(NSURL *)url;
@end
@implementation TUDialRequest
- (instancetype)initWithURL:(NSURL *)url {
    if((self=[super init])) { self.URL=url;self.handle=[ABTHandle new];self.handle.value=ABTCallURLInfo(url)[@"recipient"];self.isSOS=[self.handle.value isEqual:@"112"]; }return self;
}
@end
@interface TUCallCenter:NSObject
@property(nonatomic,strong) dispatch_queue_t queue;
- (id)_dialWithRequest:(id)request completion:(void (^)(id))completion;
- (BOOL)_isEmergencyDialRequest:(id)request;
- (void)launchAppForDialRequest:(id)request completion:(void (^)(NSError *))completion;
+ (instancetype)sharedInstance;
@end
@implementation TUCallCenter
+ (instancetype)sharedInstance { static id center;static dispatch_once_t once;dispatch_once(&once,^{center=[self new];});return nativeEmergencyAvailable ? center : nil; }
- (id)_dialWithRequest:(id)request completion:(void (^)(id))completion { NSCAssert(dispatch_get_specific(queueKey),@"call replay lost its queue");callsSent++;if(completion)completion(@"call");return @"call"; }
- (BOOL)_isEmergencyDialRequest:(id)request { return [request isSOS]; }
- (void)launchAppForDialRequest:(id)request completion:(void (^)(NSError *))completion {
    NSCAssert(dispatch_get_specific(queueKey),@"Launch/cancel callback queue changed");launchCalls++;launchedRequest=request;
    if(bridgeLaunchToWorkspace) [[ABTHostWorkspace defaultWorkspace] commonClientOpenURL:[request URL] options:@{} configuration:nil synchronous:NO completionHandler:^(id result,NSError *error){if(completion)completion(error);}];
    else if(completion)completion(nil);
}
@end
@interface _CNUIUserActionDialRequestOpener : NSObject
@property(nonatomic,strong) TUCallCenter *callCenter;
- (ABTFuture *)openDialRequest:(id)request;
@end
@implementation _CNUIUserActionDialRequestOpener
- (ABTFuture *)openDialRequest:(id)request {
    ABTFuture *future=[ABTFuture new];
    dispatch_async(self.callCenter.queue,^{ [self.callCenter launchAppForDialRequest:request completion:^(NSError *error){future.error=error;future.resolved=YES;}]; });
    return future;
}
@end
@interface ABTComposition:NSObject
@property(nonatomic,copy) NSAttributedString *text;
@property(nonatomic,copy) NSString *subject;
@property(nonatomic,strong) NSArray *mediaObjects;
@property(nonatomic,strong) id shelfPluginPayload;
@end
@implementation ABTComposition @end
@interface ABTConversation:NSObject
@property(nonatomic,strong) NSArray *recipientStrings;
@end
@implementation ABTConversation @end
@interface CKChatController:UIViewController
@property(nonatomic,strong) ABTConversation *conversation;
@property(nonatomic,strong) ABTComposition *composition;
- (void)sendComposition:(id)composition animations:(void (^)(void))animations;
@end
@implementation CKChatController
- (void)sendComposition:(id)composition animations:(void (^)(void))animations { messagesSent++; self.composition=nil; if(animations)animations(); }
@end
@interface MFMailComposeController:UIViewController
@property(nonatomic,strong) NSArray *toRecipients,*ccRecipients,*bccRecipients;
- (void)performSend:(id)source;
@end
@implementation MFMailComposeController
- (void)performSend:(id)source { mailsSent++;self.toRecipients=@[]; }
@end
@interface ABTWrongABI:NSObject
- (double)performSend:(id)source;
@end
@implementation ABTWrongABI
- (double)performSend:(id)source { return 1; }
@end
static void Check(BOOL condition,NSString *message) { if(!condition) { NSLog(@"FAILED: %@",message);abort(); } }
static void Pump(NSTimeInterval seconds) { NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds]; while(end.timeIntervalSinceNow>0) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.01,YES); }
static void WaitPrompt(void) { for(int i=0;i<200 && !ABTPending.alert;i++) Pump(.01);Check(ABTPending.alert != nil,@"confirmation presented"); }
static void Choose(BOOL yes) { UIAlertController *alert=ABTPending.alert;Check(alert!=nil,@"pending prompt");UIAlertAction *a=alert.actions[yes?1:0];[alert dismissViewControllerAnimated:NO completion:nil];a.handler(a);Pump(.05); }
static void Save(NSDictionary *settings) { NSString *path=jbroot(ABTPrefs);[NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];Check([settings writeToFile:path atomically:YES],@"save fixture"); }
int main(int argc,const char **argv) { @autoreleasepool {
    ABTHostRoot=@(argv[1]);
    UIViewController *host=[UIViewController new]; UIWindow *window=[UIWindow new];window.isKeyWindow=YES;window.rootViewController=host;
    UIWindowScene *scene=[UIWindowScene new];scene.windows=@[window];UIApplication.sharedApplication.connectedScenes=[NSSet setWithObject:scene];
    Check(ABTHostWorkspace.class==NSClassFromString(ABT_WORKSPACE_CLASS_NAME),@"workspace fixture isolated from macOS native LaunchServices");
    ABTCallsProcess=ABTMessagesProcess=ABTMailProcess=YES;ABTInstallHooks();
    Check(ABTOriginalDial && ABTOriginalMessages && ABTOriginalMail,@"all three actual hooks installed");
    Check(ABTOriginalOpenURL && ABTOriginalLegacyOpenURL,@"both Phone URL handoff hooks installed");
    Check(ABTOriginalLaunchDial && ABTOriginalWorkspaceOpen,@"contact launch and direct workspace hooks installed");
    Check(ABTOriginalContactsAdapter && ABTHostContactsAdapter.class==NSClassFromString(ABT_CONTACTS_ADAPTER_CLASS_NAME),@"isolated Contacts local adapter hook installed");
    Check(ABTOriginalExtensionOpen && ABTHostExtensionContext.class==NSClassFromString(ABT_EXTENSION_CLASS_NAME),@"isolated contact-extension hook installed");
    for(NSString *bundle in @[@"com.apple.mobilephone",@"com.apple.facetime",@"com.apple.MobileAddressBook",@"com.apple.ContactsUI.ContactsViewService",@"com.apple.ContactsUI.ContactViewViewService"]) Check(ABTCallsBundle(bundle),@"call process coverage includes standalone Contacts and hosted cards");
    for(NSString *bundle in @[@"com.apple.springboard",@"com.apple.Preferences",@"com.apple.MobileSMS",@"com.apple.mobilemail",@"other.app"]) Check(!ABTCallsBundle(bundle),@"no unrelated or system-wide call process injection");
    IMP wrong=NULL;ABTInstall(ABTWrongABI.class,@"performSend:","v",@[@"@"],(IMP)ABTMail,&wrong);Check(!wrong,@"wrong return ABI rejected");
    Check(!ABTSignature(class_getInstanceMethod(CKChatController.class,@selector(sendComposition:animations:)),"v",@[@"@",@"@"]),@"block ABI distinguished");
    Check(!ABTGet(host,@"missingGetter"),@"missing getter safe");Check(!ABTGet([ABTWrongABI new],@"performSend:"),@"bad getter safe");
    Check([ABTNormalize(@" +1 (202) 555-0100 ") isEqual:@"+12025550100"],@"phone normalization");
    Check([ABTNormalize(@" Person@Example.COM ") isEqual:@"person@example.com"],@"email normalization");
    Check(!ABTNormalize(@"*67+12025550100").length,@"special dial codes never whitelist");
    Check([ABTText(@{@"text":@"Call %@? %d"},@"text",@"unused",@"recipient") isEqual:@"Call recipient? %d"],@"legacy placeholder is literal, never printf");
    Check(!ABTWhitelistMatches(@[@"+12025550100",@""],[NSSet setWithObject:@"+12025550100"],YES),@"unknown group member blocks all exemption");
    Check(ABTWhitelistMatches(@[@"person@example.com",@"unknown@other.com"],[NSSet setWithObject:@"person@example.com"],NO),@"any mode");
    ABTDecision *decision=[ABTDecision new];__block NSUInteger wins=0;dispatch_apply(100,dispatch_get_global_queue(0,0),^(size_t i){if([decision finish]) @synchronized(decision){wins++;}});Check(wins==1,@"transaction resolves exactly once");
    Save(@{});
    CKChatController *chat=[CKChatController new];chat.conversation=[ABTConversation new];chat.conversation.recipientStrings=@[@"+12025550100"];
    ABTComposition *draft=[ABTComposition new];draft.text=[[NSAttributedString alloc]initWithString:@"unsent draft"];chat.composition=draft;
    [chat sendComposition:draft animations:^{ }];WaitPrompt();Check(!messagesSent && chat.composition==draft,@"no transmission or draft clearing before consent");
    [chat sendComposition:draft animations:nil];Check(!messagesSent,@"duplicate tap never forwards");Choose(NO);Check(!messagesSent && chat.composition==draft,@"cancel preserves message");
    [chat sendComposition:draft animations:nil];WaitPrompt();UIAlertAction *approve=ABTPending.alert.actions[1];[ABTPending.alert dismissViewControllerAnimated:NO completion:nil];approve.handler(approve);approve.handler(approve);Pump(.05);Check(messagesSent==1,@"double confirmation sends only once");
    chat.composition=draft;[chat sendComposition:draft animations:nil];WaitPrompt();chat.conversation.recipientStrings=@[@"+12025550199"];Choose(YES);Check(messagesSent==1,@"changed recipients cannot send");
    [chat sendComposition:draft animations:nil];WaitPrompt();draft.text=[[NSAttributedString alloc]initWithString:@"changed"];Choose(YES);Check(messagesSent==1,@"changed draft cannot send");
    MFMailComposeController *mail=[MFMailComposeController new];mail.toRecipients=@[@"one@example.com"];mail.bccRecipients=@[@"two@example.com"];
    [mail performSend:nil];WaitPrompt();Choose(NO);Check(!mailsSent && mail.toRecipients.count==1,@"cancel preserves mail");
    [mail performSend:nil];WaitPrompt();mail.bccRecipients=@[@"different@example.com"];Choose(YES);Check(!mailsSent,@"BCC changes invalidate approval");
    [mail performSend:nil];WaitPrompt();Choose(YES);Check(mailsSent==1,@"mail confirm forwards once");
    TUCallCenter *center=[TUCallCenter new];center.queue=dispatch_queue_create("ABT.call",DISPATCH_QUEUE_SERIAL);dispatch_queue_set_specific(center.queue,queueKey,queueKey,NULL);
    ABTDialRequest *request=[ABTDialRequest new];request.handle=[ABTHandle new];request.handle.value=@"+12025550100";
    __block id immediate;dispatch_sync(center.queue,^{immediate=[center _dialWithRequest:request completion:^(id call){Check(dispatch_get_specific(queueKey)!=NULL,@"completion queue");Check(!call,@"canceled call has native nil result");callbacks++;}];});
    WaitPrompt();Check(!immediate && !callsSent,@"call held with native nil result");Choose(NO);dispatch_sync(center.queue,^{});Check(!callsSent && callbacks==1,@"cancel never dials; completion once");
    dispatch_sync(center.queue,^{[center _dialWithRequest:request completion:^(id call){Check(call!=nil,@"approved call result");callbacks++;}];});WaitPrompt();Choose(YES);dispatch_sync(center.queue,^{});Check(callsSent==1 && callbacks==2,@"confirm dials on original queue");
    request.isSOS=YES;dispatch_sync(center.queue,^{[center _dialWithRequest:request completion:nil];});Check(callsSent==2 && !ABTPending,@"SOS bypasses gate");request.isSOS=NO;
    Save(@{@"enabled":@NO});[mail performSend:nil];Check(mailsSent==2 && !ABTPending,@"master disable");
    Save(@{@"emailEnabled":@NO});[mail performSend:nil];Check(mailsSent==3,@"email disable");
    Save(@{@"messagesEnabled":@NO});[chat sendComposition:draft animations:nil];Check(messagesSent==2,@"message disable");
    Save(@{@"phoneCallsEnabled":@NO});dispatch_sync(center.queue,^{[center _dialWithRequest:request completion:nil];});Check(callsSent==3,@"calls disable");
    Save(@{@"whitelist":@{@"contact":@"Known"},@"whitelistAddresses":@{@"contact":@[@"one@example.com"]}});mail.toRecipients=@[@"one@example.com"];mail.bccRecipients=@[];[mail performSend:nil];Pump(.2);Check(mailsSent==4 && !ABTPending,@"saved whitelist works even when contacts access denied");
    mail.toRecipients=@[@"one@example.com"];mail.bccRecipients=@[@"unknown@example.com"];[mail performSend:nil];WaitPrompt();Choose(NO);Check(mailsSent==4,@"all recipients defaults to safe match");
    Save(@{@"swapButtonOrder":@YES,@"customTitle":@"Custom",@"customMessageForEmail":@"To {recipient}",@"customYes":@"Send it",@"customCancel":@"Keep draft"});
    [mail performSend:nil];WaitPrompt();Check([ABTPending.alert.title isEqual:@"Custom"] && [ABTPending.alert.message containsString:@"unknown@example.com"] && [ABTPending.alert.actions[0].title isEqual:@"Send it"] && [ABTPending.alert.actions[1].title isEqual:@"Keep draft"],@"custom strings and swapped order");
    UIAlertAction *cancel=ABTPending.alert.actions[1];[ABTPending.alert dismissViewControllerAnimated:NO completion:nil];cancel.handler(cancel);
    Save(@{});UIApplication.sharedApplication.applicationState=UIApplicationStateBackground;[mail performSend:nil];Pump(.2);Check(!ABTPending && mailsSent==4,@"no presenter cannot silently send");
    UIApplication.sharedApplication.applicationState=UIApplicationStateActive;
    [mail performSend:nil];WaitPrompt();UIAlertAction *lateApproval=ABTPending.alert.actions[1];ABTBackground();lateApproval.handler(lateApproval);Check(mailsSent==4 && !ABTPending,@"background cancellation invalidates late confirmation");
    [mail performSend:nil];WaitPrompt();[ABTPending.alert dismissViewControllerAnimated:NO completion:nil];Pump(.65);Check(mailsSent==4 && !ABTPending,@"external dismissal cancels and releases gate");
    Save(@{@"whitelistAllContacts":@YES});request.contactIdentifier=@"contact-id";dispatch_sync(center.queue,^{[center _dialWithRequest:request completion:nil];});Pump(.2);dispatch_sync(center.queue,^{});Check(callsSent==4 && !ABTPending,@"all contacts call exemption");
    Save(@{});
    Check([ABTCallURLInfo([NSURL URLWithString:@"tel://%2B12025550100?originatingUI=keypad"])[@"recipient"] isEqual:@"+12025550100"],@"encoded keypad destination");
    Check([ABTCallURLInfo([NSURL URLWithString:@"facetime-audio://person%40example.com?video=0"])[@"recipient"] isEqual:@"person@example.com"],@"FaceTime address");
    Check(ABTCallURLInfo([NSURL URLWithString:@"telephonyprompt://+12025550100"])!=nil,@"native telephony prompt scheme");
    for(NSString *value in @[@"https://example.com/tel:123",@"sms:123",@"mailto:person@example.com",@"facetime-recents:",@"facetimeapp:",@"tel:",@"telsos://112",@"telemergencycall://112"]) Check(!ABTCallURLInfo([NSURL URLWithString:value]),@"non-call/navigation/emergency classification");
    UIApplication *app=UIApplication.sharedApplication;NSURL *dialURL=[NSURL URLWithString:@"tel://+12025550100?originatingUI=keypad&sim=2"];
    // This is the actual iOS 26 keypad chain, with no TUCallCenter dial call at all.
    [app openURL:dialURL withCompletionHandler:^(BOOL opened){Check(!opened,@"cancel returns BOOL false");urlCallbacks++;}];WaitPrompt();Check(!urlOpens,@"keypad cannot reach system opener before consent");
    [app openURL:dialURL withCompletionHandler:^(BOOL opened){Check(!opened,@"duplicate URL tap canceled");urlCallbacks++;}];Check(!urlOpens && urlCallbacks==1,@"duplicate URL attempt never forwards");Choose(NO);Check(!urlOpens && urlCallbacks==2,@"keypad cancel prevents handoff");
    NSMutableDictionary *options=[@{@"custom":@"preserved"} mutableCopy];NSObject *endpoint=[NSObject new];
    [app _openURL:dialURL options:options openApplicationEndpoint:endpoint completionHandler:^(BOOL opened){Check(opened,@"approved URL completion BOOL true");urlCallbacks++;}];WaitPrompt();options[@"custom"]=@"changed outside";Choose(YES);
    Check(urlOpens==1 && urlCallbacks==3 && [lastOpenedURL isEqual:dialURL] && [lastOptions[@"custom"] isEqual:@"preserved"] && lastEndpoint==endpoint,@"original URL/SIM/query/options/endpoint preserved");
    [app openURL:dialURL withCompletionHandler:nil];WaitPrompt();Choose(YES);Check(urlOpens==2,@"same number requires new confirmation after first action");
    BOOL immediateLegacy=[app _openURL:dialURL];WaitPrompt();Check(!immediateLegacy && !legacyURLOpens,@"legacy URL reports failure while held");Choose(NO);Check(!legacyURLOpens,@"legacy cancel prevents handoff");
    nestedLegacyURL=YES;[app _openURL:dialURL];WaitPrompt();Choose(YES);Check(legacyURLOpens==1 && urlOpens==3 && !ABTPending,@"nested opener chain prompts exactly once");nestedLegacyURL=NO;
    @try { ABTReplayCallURL(dialURL, ^{ Check(ABTURLApproved(dialURL),@"scoped matching URL permit");Check(!ABTURLApproved([NSURL URLWithString:@"tel:another"]),@"permit cannot cover different target");@throw [NSException exceptionWithName:@"test" reason:nil userInfo:nil]; }); } @catch(NSException *exception) { }
    Check(!ABTURLApproved(dialURL),@"URL permit restored during exception unwind");
    for(NSString *scheme in @[@"facetime",@"facetime-audio",@"telprompt",@"telephony",@"callto"]) { [app openURL:[NSURL URLWithString:[scheme stringByAppendingString:@":+12025550100"]] withCompletionHandler:nil];WaitPrompt();Choose(NO); }
    Check(urlOpens==3,@"unified Calls category cancels each supported scheme");
    [app openURL:[NSURL URLWithString:@"https://example.com"] withCompletionHandler:nil];[app openURL:[NSURL URLWithString:@"mailto:person@example.com"] withCompletionHandler:nil];Check(urlOpens==5 && !ABTPending,@"unrelated URL traffic unchanged");
    [app openURL:[NSURL URLWithString:@"tel:112"] withCompletionHandler:nil];Check(urlOpens==6 && !ABTPending,@"native emergency classifier bypasses prompt");
    [app openURL:[NSURL URLWithString:@"telSOS:112"] withCompletionHandler:nil];Check(urlOpens==7 && !ABTPending,@"dedicated SOS scheme bypasses prompt");
    Save(@{@"phoneCallsEnabled":@NO});[app openURL:dialURL withCompletionHandler:nil];Check(urlOpens==8 && !ABTPending,@"Calls switch covers URL route");
    Save(@{});[app openURL:dialURL withCompletionHandler:^(BOOL opened){Check(!opened,@"background cancels URL handoff");urlCallbacks++;}];WaitPrompt();ABTBackground();Check(urlOpens==8 && urlCallbacks==4,@"background never forwards call URL");
    request.contactIdentifier=nil;request.URL=dialURL;dispatch_sync(center.queue,^{ ABTReplayCallURL(dialURL, ^{ [center _dialWithRequest:request completion:nil]; }); });Check(callsSent==5 && !ABTPending,@"same-target nested call-center route uses scoped approval");
    Check(messagesSent==2 && mailsSent==4,@"message and email regressions remain stable");
    _CNUIUserActionDialRequestOpener *contactAction=[_CNUIUserActionDialRequestOpener new];contactAction.callCenter=center;
    ABTFuture *contactFuture=[contactAction openDialRequest:request];WaitPrompt();Check(contactFuture && !contactFuture.resolved && !launchCalls,@"contact action keeps native future pending without dialing");Choose(NO);dispatch_sync(center.queue,^{});Check(contactFuture.resolved && contactFuture.error.code==NSUserCancelledError && !launchCalls,@"contact cancel resolves native error-only adapter");
    contactFuture=[contactAction openDialRequest:request];WaitPrompt();Choose(YES);dispatch_sync(center.queue,^{});Check(contactFuture.resolved && !contactFuture.error && launchCalls==1 && [launchedRequest URL]==dialURL,@"contact confirm launches preserved request once");
    ABTHostWorkspace *workspace=ABTHostWorkspace.defaultWorkspace;
    BOOL favoriteResult=[workspace openSensitiveURL:dialURL withOptions:@{@"sensitive":@YES}];WaitPrompt();Check(!favoriteResult && !workspaceOpens && workspaceCallbacks==1,@"sensitive URL wrapper gets synchronous failure before it returns");Choose(NO);Check(!workspaceOpens && workspaceCallbacks==1,@"favorite cancel never calls backend or stale stack callback");
    [workspace openSensitiveURL:dialURL withOptions:@{@"sensitive":@YES}];WaitPrompt();Choose(YES);Pump(.15);Check(workspaceOpens==1 && workspaceCallbacks==2 && [workspaceURL isEqual:dialURL] && [workspaceOptions[@"sensitive"] boolValue],@"favorite confirm replays with independent callback and intact options");
    __block ABTFuture *recentFuture=[ABTFuture new];NSMutableDictionary *configuration=[@{@"sim":@"secondary"} mutableCopy];
    [workspace openURL:dialURL configuration:configuration completionHandler:^(id result,NSError *error){recentFuture.error=error;recentFuture.resolved=YES;workspaceCallbacks++;}];WaitPrompt();Choose(NO);Pump(.1);Check(recentFuture.resolved && recentFuture.error.code==NSUserCancelledError && workspaceOpens==1,@"direct async Recents cancel uses two-object error completion");
    recentFuture=[ABTFuture new];[workspace openURL:dialURL configuration:configuration completionHandler:^(id result,NSError *error){recentFuture.error=error;recentFuture.resolved=YES;workspaceCallbacks++;}];WaitPrompt();configuration[@"sim"]=@"changed";Choose(YES);Pump(.15);Check(recentFuture.resolved && !recentFuture.error && workspaceOpens==2 && [workspaceConfiguration[@"sim"] isEqual:@"secondary"],@"direct Recents confirm preserves config and opens once");
    bridgeUIKitToWorkspace=YES;[app openURL:dialURL withCompletionHandler:nil];WaitPrompt();Choose(YES);Check(workspaceOpens==3 && !ABTPending,@"working keypad nested workspace chain prompts once");bridgeUIKitToWorkspace=NO;
    bridgeLaunchToWorkspace=YES;contactFuture=[contactAction openDialRequest:request];WaitPrompt();Choose(YES);dispatch_sync(center.queue,^{});Check(launchCalls==2 && workspaceOpens==4 && contactFuture.resolved && !contactFuture.error && !ABTPending,@"contact launch nested workspace chain prompts once");bridgeLaunchToWorkspace=NO;
    [workspace openURL:dialURL configuration:nil completionHandler:^(id result,NSError *error){workspaceCallbacks++;}];WaitPrompt();[workspace openURL:dialURL configuration:nil completionHandler:^(id result,NSError *error){NSCAssert(error.code==NSUserCancelledError,@"duplicate canceled");workspaceCallbacks++;}];Choose(NO);Pump(.15);Check(workspaceOpens==4,@"duplicate workspace attempts cannot forward");
    BOOL emergencyResult=[workspace openSensitiveURL:[NSURL URLWithString:@"tel:112"] withOptions:nil];Check(emergencyResult && workspaceOpens==5 && !ABTPending,@"sync emergency bypass keeps native successful completion");
    Save(@{@"phoneCallsEnabled":@NO});BOOL disabledResult=[workspace openSensitiveURL:dialURL withOptions:nil];dispatch_sync(center.queue,^{[center launchAppForDialRequest:request completion:nil];});Check(disabledResult && workspaceOpens==6 && launchCalls==3 && !ABTPending,@"Calls toggle covers both added handoffs");Save(@{});
    Check(messagesSent==2 && mailsSent==4,@"all added routes preserve working message/email counts");
    ABTHostExtensionContext *extension=[ABTHostExtensionContext new];
    [extension openURL:dialURL completionHandler:^(BOOL opened){Check(!opened,@"contact-card cancel uses BOOL false");extensionCallbacks++;}];WaitPrompt();Check(!extensionOpens,@"card number held before host extension handoff");
    [extension openURL:dialURL completionHandler:^(BOOL opened){Check(!opened,@"duplicate card action canceled");extensionCallbacks++;}];Choose(NO);Check(!extensionOpens && extensionCallbacks==2,@"card cancel and repeated taps cannot initiate call");
    [extension openURL:dialURL completionHandler:^(BOOL opened){Check(opened,@"approved card reports opened");extensionCallbacks++;}];WaitPrompt();Choose(YES);Check(extensionOpens==1 && extensionCallbacks==3 && [extensionURL isEqual:dialURL],@"card confirm preserves full original number/provider/SIM URI");
    [extension openURL:dialURL completionHandler:nil];WaitPrompt();Choose(NO);Check(extensionOpens==1,@"same card number needs fresh confirmation");
    [extension openURL:[NSURL URLWithString:@"sms:123"] completionHandler:nil];[extension openURL:[NSURL URLWithString:@"mailto:person@example.com"] completionHandler:nil];Check(extensionOpens==3 && !ABTPending,@"contact card message/email navigation unaffected");
    [extension openURL:dialURL completionHandler:^(BOOL opened){Check(!opened,@"dismissed card cannot launch");extensionCallbacks++;}];WaitPrompt();ABTBackground();Check(extensionOpens==3 && extensionCallbacks==4,@"background cancels contact card action");
    [extension openURL:[NSURL URLWithString:@"telSOS:112"] completionHandler:nil];Check(extensionOpens==4 && !ABTPending,@"emergency card URL bypass");
    Save(@{@"phoneCallsEnabled":@NO});[extension openURL:dialURL completionHandler:nil];Check(extensionOpens==5 && !ABTPending,@"Calls toggle covers contact extension");Save(@{});
    Check(urlOpens==9 && workspaceOpens==6 && launchCalls==3 && messagesSent==2 && mailsSent==4,@"all previously working route counts preserved");
    ABTContactServiceProcess=YES;app.applicationState=UIApplicationStateInactive;
    [extension openURL:dialURL completionHandler:nil];WaitPrompt();Choose(YES);Check(extensionOpens==6,@"foreground hosted card can confirm while service application is inactive");
    scene.activationState=UISceneActivationStateBackground;
    [extension openURL:dialURL completionHandler:^(BOOL opened){Check(!opened,@"background card has no permission to call");}];Pump(.2);Check(extensionOpens==6 && !ABTPending,@"service scene must actually be foreground");
    scene.activationState=UISceneActivationStateForegroundActive;ABTContactServiceProcess=NO;
    [extension openURL:dialURL completionHandler:nil];Pump(.2);Check(extensionOpens==6 && !ABTPending,@"inactive ordinary apps do not inherit hosted-card exception");
    app.applicationState=UIApplicationStateActive;
    // A contact page number-row schedules the local adapter, retaining a native
    // bool/error future. Neither UIApplication nor commonClientOpenURL is entered.
    ABTHostContactsAdapter *numberAdapter=[ABTHostContactsAdapter new];
    NSMutableDictionary *numberOptions=[@{@"sim":@"secondary",@"sensitive":@YES} mutableCopy];
    __block ABTFuture *numberFuture=[ABTFuture new];__block BOOL numberOpened=YES;
    dispatch_async(dispatch_get_global_queue(0,0),^{[numberAdapter openSensitiveURLInBackground:dialURL withOptions:numberOptions withReply:^(BOOL opened,NSError *error){Check(!NSThread.isMainThread,@"Contact reply off UI queue");numberOpened=opened;numberFuture.error=error;numberFuture.resolved=YES;contactReplies++;}];});
    WaitPrompt();Check(!contactBackendOpens && !numberFuture.resolved,@"number tap cannot dial or resolve native future before consent");
    Choose(NO);for(int i=0;i<100 && !numberFuture.resolved;i++)Pump(.01);
    Check(!contactBackendOpens && !numberOpened && numberFuture.error.code==NSUserCancelledError && contactReplies==1,@"number-row cancel gives one BOOL false and NSError, with no backend call");
    numberFuture=[ABTFuture new];
    dispatch_async(dispatch_get_global_queue(0,0),^{[numberAdapter openSensitiveURLInBackground:dialURL withOptions:numberOptions withReply:^(BOOL opened,NSError *error){numberOpened=opened;numberFuture.error=error;numberFuture.resolved=YES;contactReplies++;}];});
    WaitPrompt();numberOptions[@"sim"]=@"changed";Choose(YES);for(int i=0;i<100 && !numberFuture.resolved;i++)Pump(.01);
    Check(contactBackendOpens==1 && numberOpened && numberFuture.resolved && !numberFuture.error && contactReplies==2 && [contactBackendURL isEqual:dialURL] && [contactBackendOptions[@"sim"] isEqual:@"secondary"],@"number-row approval preserves URI and options, resolves original future once");
    // Same number later is a separate decision, including service-hosted cards.
    ABTContactServiceProcess=YES;app.applicationState=UIApplicationStateInactive;
    dispatch_async(dispatch_get_global_queue(0,0),^{[numberAdapter openSensitiveURLInBackground:dialURL withOptions:nil withReply:nil];});WaitPrompt();Choose(NO);Pump(.1);
    Check(contactBackendOpens==1,@"hosted card number needs fresh consent");ABTContactServiceProcess=NO;app.applicationState=UIApplicationStateActive;
    contactNestedCommon=YES;
    dispatch_async(dispatch_get_global_queue(0,0),^{[numberAdapter openSensitiveURLInBackground:dialURL withOptions:nil withReply:nil];});WaitPrompt();Choose(YES);Pump(.2);
    Check(contactBackendOpens==2 && workspaceOpens==7 && !ABTPending,@"nested common backend cannot double-prompt same approved number");contactNestedCommon=NO;
    dispatch_async(dispatch_get_global_queue(0,0),^{[numberAdapter openSensitiveURLInBackground:dialURL withOptions:nil withReply:^(BOOL opened,NSError *error){Check(!opened && error.code==NSUserCancelledError,@"background denies number action");contactReplies++;}];});WaitPrompt();ABTBackground();Pump(.2);Check(contactBackendOpens==2 && contactReplies==3,@"background cancellation never opens contact-number call");
    Save(@{@"phoneCallsEnabled":@NO});dispatch_async(dispatch_get_global_queue(0,0),^{[numberAdapter openSensitiveURLInBackground:dialURL withOptions:nil withReply:nil];});Pump(.2);Check(contactBackendOpens==3 && !ABTPending,@"Calls disable preserves native number route");Save(@{});
    dispatch_async(dispatch_get_global_queue(0,0),^{[numberAdapter openSensitiveURLInBackground:[NSURL URLWithString:@"sms:123"] withOptions:nil withReply:nil];});Pump(.2);Check(contactBackendOpens==4 && !ABTPending,@"number adapter leaves non-call navigation alone");
    dispatch_async(dispatch_get_global_queue(0,0),^{[numberAdapter openSensitiveURLInBackground:[NSURL URLWithString:@"tel:112"] withOptions:nil withReply:nil];});Pump(.2);Check(contactBackendOpens==5 && !ABTPending,@"native emergency bypass still works on contact adapter");
    Check(messagesSent==2 && mailsSent==4 && urlOpens==9 && launchCalls==3,@"contact-number correction preserves existing routes");
    NSLog(@"PASS: contact-number background adapter preserves native BOOL/error future, cancel/approve/options, hosted cards, repeat actions, nested handoff, background and emergency safety; all prior regressions.");
    NSLog(@"PASS: standalone/hosted Contacts process coverage and extension handoff cancel/confirm; duplicate and background safety; preserved URI; existing keypad, Favorites/Recents workspace, launch, message/email/settings regressions.");
    return 0;
} }
