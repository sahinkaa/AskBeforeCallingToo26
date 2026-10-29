#import <Foundation/Foundation.h>
#import "../Settings/ABC26Model.h"
#import "../Settings/ABC26Store.h"
#include <assert.h>

static NSArray *rows(NSArray *groups) {
    NSMutableArray *result = [NSMutableArray new];
    for (NSDictionary *group in groups) [result addObjectsFromArray:group[@"rows"]];
    return result;
}
int main(int argc, char **argv) {
    @autoreleasepool {
        assert(argc == 3);
        NSDictionary *schema = [NSDictionary dictionaryWithContentsOfFile:@(argv[1])];


        NSArray *root = rows(ABC26Sections(schema, @"root"));
        NSArray *strings = rows(ABC26Sections(schema, @"strings"));
        assert(root.count == 11 && strings.count == 6);
        unsigned switches = 0, editors = 0;
        for (NSDictionary *row in [root arrayByAddingObjectsFromArray:strings]) {
            if (row[@"defaults"]) assert([row[@"defaults"] isEqual:schema[@"domain"]]);
            if (row[@"PostNotification"]) assert([row[@"PostNotification"] isEqual:schema[@"notification"]]);
            if ([row[@"cell"] isEqual:@"PSSwitchCell"]) {
                switches++;
                assert(ABC26ValidateValue(schema, row[@"key"], @NO));
                assert(ABC26ValidateValue(schema, row[@"key"], @YES));
                assert(!ABC26ValidateValue(schema, row[@"key"], @2));
            }
            if ([row[@"cell"] isEqual:@"PSEditTextCell"]) {
                editors++;
                assert(ABC26ValidateValue(schema, row[@"key"], @"Hello\n%@ 🟩"));
                assert(!ABC26ValidateValue(schema, row[@"key"], @42));
            }
        }
        assert(switches == 8 && editors == 6);


        assert([ABC26Defaults(schema)[@"enabled"] boolValue]);
        assert(![ABC26Defaults(schema)[@"swapButtonOrder"] boolValue]);
        assert(!ABC26ValidateValue(schema, @"unknown", @YES));
        assert(rows(ABC26Sections(@{}, @"root")).count == 1);

        NSString *path = [@(argv[2]) stringByAppendingPathComponent:@"preferences.plist"];
        NSDictionary *original = @{@"enabled": @NO, @"customCancel": @"Stop!", @"whitelist": @{@"OLD-CONTACT-ID": @"Original Name"}, @"futureSetting": @[@1, @2]};
        NSData *bytes = [NSPropertyListSerialization dataWithPropertyList:original format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        assert([bytes writeToFile:path atomically:YES]);
        ABC26Store *a = [[ABC26Store alloc] initWithPath:path schema:schema];
        ABC26Store *b = [[ABC26Store alloc] initWithPath:path schema:schema];
        assert([[a read:nil] isEqual:original]);
        assert(![NSFileManager.defaultManager fileExistsAtPath:[path stringByAppendingString:@".before-ask26-rebuild"]]);
        assert([a saveValue:@YES key:@"phoneCallsEnabled" error:nil]);
        assert([b saveValue:@"Cancel\n%@ 🟩" key:@"customCancel" error:nil]);
        NSDictionary *saved = [a read:nil];
        assert([saved[@"phoneCallsEnabled"] boolValue]);
        assert([saved[@"customCancel"] isEqual:@"Cancel\n%@ 🟩"]);
        assert([saved[@"futureSetting"] isEqual:original[@"futureSetting"]]);
        assert([saved[@"whitelist"] isEqual:original[@"whitelist"]]);
        assert([[NSData dataWithContentsOfFile:[path stringByAppendingString:@".before-ask26-rebuild"]] isEqual:bytes]);
        assert([a updateWhitelist:@{@"NEW-CONTACT-ID": @"New Name"} removing:@[] error:nil]);
        assert([b updateWhitelist:@{@"OTHER-ID": @"Other Name"} removing:@[@"OLD-CONTACT-ID"] error:nil]);
        NSDictionary *whitelist = ABC26Whitelist([a read:nil]);
        assert(whitelist.count == 2 && whitelist[@"NEW-CONTACT-ID"] && whitelist[@"OTHER-ID"] && !whitelist[@"OLD-CONTACT-ID"]);
        assert(([a updateWhitelist:@{} removing:@[@"NEW-CONTACT-ID", @"OTHER-ID"] error:nil]));
        assert(ABC26Whitelist([a read:nil]).count == 0);
        assert([a saveValue:nil key:@"customCancel" error:nil]);
        assert(![a read:nil][@"customCancel"]);
        assert(![a saveValue:@"YES" key:@"enabled" error:nil]);
        assert(![a updateWhitelist:@{@"bad": @1} removing:@[] error:nil]);
        NSMutableDictionary *bad = [[a read:nil] mutableCopy];
        bad[@"whitelist"] = @[@"unexpected"];
        assert([bad writeToFile:path atomically:YES]);
        NSData *malformedWhitelist = [NSData dataWithContentsOfFile:path];
        assert(![a updateWhitelist:@{@"id": @"Name"} removing:@[] error:nil]);
        assert([[NSData dataWithContentsOfFile:path] isEqual:malformedWhitelist]);
        NSData *corrupt = [@"not a plist" dataUsingEncoding:NSUTF8StringEncoding];
        assert([corrupt writeToFile:path atomically:YES]);
        assert(![a saveValue:@YES key:@"enabled" error:nil]);
        assert([[NSData dataWithContentsOfFile:path] isEqual:corrupt]);
        assert(([a addWhitelist:@{@"ADDRESS-ID":@"Address Name"} addresses:@{@"ADDRESS-ID":@[@"one@example.com",@"+12025550100"]} error:nil] == NO)); // corrupt file preserved
        assert([@{} writeToFile:path atomically:YES]);
        assert(([a addWhitelist:@{@"ADDRESS-ID":@"Address Name"} addresses:@{@"ADDRESS-ID":@[@"one@example.com",@"+12025550100"]} error:nil]));
        assert([[a read:nil][@"whitelistAddresses"][@"ADDRESS-ID"] count] == 2);
        assert([a updateWhitelist:@{} removing:@[@"ADDRESS-ID"] error:nil]);
        assert(![a read:nil][@"whitelistAddresses"][@"ADDRESS-ID"]);
        puts("PASS: reduced schema, defaults, atomic saves, merge, backup, Unicode, whitelist identifier format/add/remove/clear, invalid and corrupt-file preservation");
    }
    return 0;
}
