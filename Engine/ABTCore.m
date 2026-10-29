#import "ABTCore.h"
#import <objc/message.h>
#include <string.h>

static const char *ABTUnqualified(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}
static BOOL ABTType(const char *actual, const char *expected) {
    actual = ABTUnqualified(actual);
    if (!actual) return NO;
    // Object class annotations are ABI-equivalent; a block is not a plain object argument.
    if (!strcmp(expected, "@")) return actual[0] == '@' && actual[1] != '?';
    if (!strcmp(expected, "B")) return !strcmp(actual, "B") || !strcmp(actual, "c");
    return !strcmp(actual, expected);
}
BOOL ABTSignature(Method method, const char *result, NSArray<NSString *> *arguments) {
    if (!method || method_getNumberOfArguments(method) != arguments.count + 2) return NO;
    char *type = method_copyReturnType(method); BOOL valid = ABTType(type, result); free(type);
    for (unsigned i = 0; valid && i < arguments.count + 2; i++) {
        type = method_copyArgumentType(method, i);
        const char *expected = i == 0 ? "@" : i == 1 ? ":" : arguments[i-2].UTF8String;
        valid = ABTType(type, expected); free(type);
    }
    return valid;
}
id ABTGet(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!object || !ABTSignature(class_getInstanceMethod(object_getClass(object), selector), "@", @[])) return nil;
    // Only this optional private getter is guarded. Never catch/retry an original action.
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return nil; }
}
BOOL ABTBool(id object, NSString *name, id argument, BOOL hasArgument) {
    SEL selector = NSSelectorFromString(name);
    if (!object || !ABTSignature(class_getInstanceMethod(object_getClass(object), selector), "B", hasArgument ? @[@"@"] : @[])) return NO;
    @try { return hasArgument ? ((BOOL (*)(id, SEL, id))objc_msgSend)(object,selector,argument) : ((BOOL (*)(id, SEL))objc_msgSend)(object,selector); }
    @catch (__unused NSException *exception) { return NO; }
}
NSString *ABTNormalize(NSString *address) {
    if (![address isKindOfClass:NSString.class]) return @"";
    NSString *value = [address stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([value containsString:@"@"]) return value.lowercaseString;
    NSMutableString *digits = [NSMutableString new];
    for (NSUInteger i=0; i<value.length; i++) {
        unichar c = [value characterAtIndex:i];
        if ((c >= '0' && c <= '9') || (c == '+' && i == 0)) [digits appendFormat:@"%C", c];
        else if (![[NSCharacterSet characterSetWithCharactersInString:@" ()-.\u00a0"] characterIsMember:c]) return @"";
    }
    return digits;
}
BOOL ABTWhitelistMatches(NSArray<NSString *> *recipients, NSSet<NSString *> *allowed, BOOL all) {
    if (!recipients.count || !allowed.count) return NO;
    BOOL any = NO;
    for (NSString *recipient in recipients) {
        NSString *normalized = ABTNormalize(recipient);
        BOOL matched = normalized.length && [allowed containsObject:normalized];
        if (all && !matched) return NO;
        any |= matched;
    }
    return any;
}
NSString *ABTText(NSDictionary *settings, NSString *key, NSString *fallback, NSString *recipient) {
    id text = settings[key];
    NSString *value = [text isKindOfClass:NSString.class] && [text length] && [text length] <= 2048 ? text : fallback;
    NSString *destination = recipient.length ? recipient : @"this recipient";
    // Legacy %@ is replaced literally; saved text is never executed as a format string.
    value = [value stringByReplacingOccurrencesOfString:@"%@" withString:destination];
    return [value stringByReplacingOccurrencesOfString:@"{recipient}" withString:destination];
}
@implementation ABTDecision { BOOL _finished; }
- (BOOL)finished { @synchronized(self) { return _finished; } }
- (BOOL)finish { @synchronized(self) { if (_finished) return NO; _finished = YES; return YES; } }
@end
