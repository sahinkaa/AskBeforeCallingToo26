#import "ABC26Store.h"
#import "ABC26Model.h"
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

static void ABC26Error(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"AskBeforeCalling26.Settings" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
@interface ABC26Store ()
@property(nonatomic, copy) NSDictionary *schema;
@end
@implementation ABC26Store
- (instancetype)initWithPath:(NSString *)path schema:(NSDictionary *)schema {
    if ((self = [super init])) { _path = [path copy]; self.schema = schema; }
    return self;
}
- (NSDictionary *)read:(NSError **)error {
    if (error) *error = nil;
    if (![NSFileManager.defaultManager fileExistsAtPath:self.path]) return @{};
    NSData *data = [NSData dataWithContentsOfFile:self.path options:0 error:error];
    if (!data) return nil;
    id value = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
    if (![value isKindOfClass:NSDictionary.class]) { ABC26Error(error, @"The existing settings could not be read. They have not been replaced."); return nil; }
    return value;
}
- (BOOL)change:(BOOL (^)(NSMutableDictionary *settings, NSError **error))change error:(NSError **)error {
    if (error) *error = nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtPath:self.path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    int descriptor = open([self.path stringByAppendingString:@".ios26-settings.lock"].fileSystemRepresentation, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
    if (descriptor < 0) { if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]; return NO; }
    if (flock(descriptor, LOCK_EX)) { int code = errno; close(descriptor); if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil]; return NO; }
    @try {
        NSDictionary *old = [self read:error];
        if (!old) return NO;
        NSMutableDictionary *updated = [old mutableCopy];
        if (!change(updated, error)) return NO;
        if ([updated isEqual:old]) return YES;
        NSString *backup = [self.path stringByAppendingString:@".before-ask26-rebuild"];
        if ([fm fileExistsAtPath:self.path] && ![fm fileExistsAtPath:backup] && ![fm copyItemAtPath:self.path toPath:backup error:error]) return NO;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:updated format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
        if (!data || ![data writeToFile:self.path options:NSDataWritingAtomic error:error]) return NO;
        if (![[self read:error] isEqual:updated]) { ABC26Error(error, @"The saved settings did not pass readback verification."); return NO; }
        return YES;
    } @finally { flock(descriptor, LOCK_UN); close(descriptor); }
}
- (BOOL)saveValue:(id)value key:(NSString *)key error:(NSError **)error {
    if (!ABC26ValidateValue(self.schema, key, value)) { ABC26Error(error, @"That setting value is invalid. Nothing was saved."); return NO; }
    return [self change:^BOOL(NSMutableDictionary *settings, NSError **failure) {
        if (value) settings[key] = value; else [settings removeObjectForKey:key];
        return YES;
    } error:error];
}
- (BOOL)updateWhitelist:(NSDictionary *)additions removing:(NSArray *)identifiers error:(NSError **)error {
    if (!ABC26Whitelist(@{@"whitelist": additions ?: @{}})) { ABC26Error(error, @"The contact identifiers are invalid."); return NO; }
    for (id identifier in identifiers) if (![identifier isKindOfClass:NSString.class] || ![identifier length]) { ABC26Error(error, @"The contact identifier is invalid."); return NO; }
    return [self change:^BOOL(NSMutableDictionary *settings, NSError **failure) {
        NSDictionary *existing = ABC26Whitelist(settings);
        if (!existing) { ABC26Error(failure, @"The existing whitelist has an unsupported format. It has not been replaced."); return NO; }
        NSMutableDictionary *whitelist = [existing mutableCopy];
        [whitelist addEntriesFromDictionary:additions ?: @{}];
        [whitelist removeObjectsForKeys:identifiers ?: @[]];
        settings[@"whitelist"] = whitelist;
        id saved = settings[@"whitelistAddresses"];
        NSMutableDictionary *addresses = [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary new];
        [addresses removeObjectsForKeys:identifiers ?: @[]];
        settings[@"whitelistAddresses"] = addresses;
        return YES;
    } error:error];
}
- (BOOL)addWhitelist:(NSDictionary *)entries addresses:(NSDictionary *)addresses error:(NSError **)error {
    if (!ABC26Whitelist(@{@"whitelist":entries ?: @{}})) return NO;
    for (NSString *key in addresses) {
        if (!entries[key] || ![addresses[key] isKindOfClass:NSArray.class]) return NO;
        for (id address in addresses[key]) if (![address isKindOfClass:NSString.class]) return NO;
    }
    return [self change:^BOOL(NSMutableDictionary *settings, NSError **failure) {
        NSDictionary *existing = ABC26Whitelist(settings);
        if (!existing) { ABC26Error(failure,@"The existing whitelist is unreadable and was not changed."); return NO; }
        NSMutableDictionary *names = [existing mutableCopy]; [names addEntriesFromDictionary:entries]; settings[@"whitelist"] = names;
        id saved = settings[@"whitelistAddresses"];
        NSMutableDictionary *values = [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary new];
        [values addEntriesFromDictionary:addresses]; settings[@"whitelistAddresses"] = values;
        return YES;
    } error:error];
}
@end
