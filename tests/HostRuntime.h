#define ABT_CONTACTS_ADAPTER_CLASS_NAME @"ABTHostContactsAdapter"
// macOS doubles for testing the actual Runtime.m hook bodies. Not part of the package.
#define ABT_WORKSPACE_CLASS_NAME @"ABTHostWorkspace"
#define ABT_EXTENSION_CLASS_NAME @"ABTHostExtensionContext"
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
typedef NS_ENUM(NSInteger, UIApplicationState) { UIApplicationStateActive, UIApplicationStateInactive, UIApplicationStateBackground };
typedef NS_ENUM(NSInteger, UISceneActivationState) { UISceneActivationStateForegroundActive, UISceneActivationStateForegroundInactive, UISceneActivationStateBackground };
typedef NS_ENUM(NSInteger, UIAlertControllerStyle) { UIAlertControllerStyleAlert };
typedef NS_ENUM(NSInteger, UIAlertActionStyle) { UIAlertActionStyleDefault, UIAlertActionStyleCancel };
static NSString *const UIApplicationWillResignActiveNotification = @"ABTTestBackground";
@class UIWindow, UIAlertAction;
@interface UIView : NSObject
@property(nonatomic,strong) UIWindow *window;
@end
@interface UIViewController : NSObject
@property(nonatomic,strong) UIView *viewIfLoaded;
@property(nonatomic,strong) UIViewController *presentedViewController;
@property(nonatomic,weak) UIViewController *presentingViewController;
@property(nonatomic) BOOL isBeingDismissed;
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion;
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion;
@end
@interface UINavigationController : UIViewController
@property(nonatomic,strong) UIViewController *visibleViewController;
@end
@interface UITabBarController : UIViewController
@property(nonatomic,strong) UIViewController *selectedViewController;
@end
@interface UIWindow : NSObject
@property(nonatomic) BOOL isKeyWindow, hidden;
@property(nonatomic,strong) UIViewController *rootViewController;
@end
@interface UIScene : NSObject
@property(nonatomic) UISceneActivationState activationState;
@end
@interface UIWindowScene : UIScene
@property(nonatomic,strong) NSArray *windows;
@end
@interface UIApplication : NSObject
@property(nonatomic) UIApplicationState applicationState;
@property(nonatomic,strong) NSSet *connectedScenes;
+ (instancetype)sharedApplication;
- (void)openURL:(NSURL *)url withCompletionHandler:(void (^)(BOOL))completion;
- (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion;
- (void)_openURL:(NSURL *)url options:(id)options openApplicationEndpoint:(id)endpoint completionHandler:(void (^)(BOOL))completion;
- (BOOL)_openURL:(NSURL *)url;
@end
@interface UIAlertAction : NSObject
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) void (^handler)(UIAlertAction *);
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler;
@end
@interface UIAlertController : UIViewController
@property(nonatomic,copy) NSString *title, *message;
@property(nonatomic,strong) NSMutableArray<UIAlertAction *> *actions;
@property(nonatomic,strong) UIAlertAction *preferredAction;
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style;
- (void)addAction:(UIAlertAction *)action;
@end
typedef NSInteger CNAuthorizationStatus;
enum { CNAuthorizationStatusAuthorized = 3, CNAuthorizationStatusLimited = 4, CNEntityTypeContacts = 0 };
static NSString *const CNContactIdentifierKey = @"identifier", *const CNContactPhoneNumbersKey = @"phoneNumbers", *const CNContactEmailAddressesKey = @"emailAddresses";
@interface CNPhoneNumber : NSObject
@property(nonatomic,copy) NSString *stringValue;
@end
@interface CNLabeledValue<ObjectType> : NSObject
@property(nonatomic,strong) ObjectType value;
@end
@interface CNContact : NSObject
@property(nonatomic,strong) NSArray *phoneNumbers, *emailAddresses;
+ (NSPredicate *)predicateForContactsWithIdentifiers:(NSArray *)identifiers;
@end
@interface CNContactFetchRequest : NSObject
@property(nonatomic,strong) NSPredicate *predicate;
- (instancetype)initWithKeysToFetch:(NSArray *)keys;
@end
@interface CNContactStore : NSObject
+ (CNAuthorizationStatus)authorizationStatusForEntityType:(NSInteger)type;
- (BOOL)enumerateContactsWithFetchRequest:(CNContactFetchRequest *)request error:(NSError **)error usingBlock:(void (^)(CNContact *,BOOL *))block;
@end
static NSString *ABTHostRoot;
static NSString *jbroot(NSString *path) { return [ABTHostRoot stringByAppendingPathComponent:path]; }
static void MSHookMessageEx(Class cls,SEL selector,IMP hook,IMP *original) {
    Method method=class_getInstanceMethod(cls,selector); *original=method_getImplementation(method);
    if (!class_addMethod(cls,selector,hook,method_getTypeEncoding(method))) method_setImplementation(method,hook);
}
struct mach_header;
static void _dyld_register_func_for_add_image(void (*callback)(const struct mach_header *,intptr_t)) { }
