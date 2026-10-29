#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Both the host tests and the device engine use these implementations.
BOOL ABTSignature(Method method, const char *result, NSArray<NSString *> *arguments);
id ABTGet(id object, NSString *selector);
BOOL ABTBool(id object, NSString *selector, id argument, BOOL hasArgument);
NSString *ABTNormalize(NSString *address);
BOOL ABTWhitelistMatches(NSArray<NSString *> *recipients, NSSet<NSString *> *allowed, BOOL all);
NSString *ABTText(NSDictionary *settings, NSString *key, NSString *fallback, NSString *recipient);

@interface ABTDecision : NSObject
@property(nonatomic, readonly) BOOL finished;
// A transaction can be resolved exactly once, including from competing callbacks.
- (BOOL)finish;
@end
