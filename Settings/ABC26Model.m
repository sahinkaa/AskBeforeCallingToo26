#import "ABC26Model.h"

NSString *ABC26Label(NSDictionary *schema, NSString *text, NSString *page) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSString *table = [page isEqual:@"strings"] ? @"ABCCustomStrings" : @"AskBeforeCallingToo13";
    id value = schema[@"translations"][table][text];
    return [value isKindOfClass:NSString.class] ? value : text;
}
NSArray<NSDictionary *> *ABC26Sections(NSDictionary *schema, NSString *page) {
    id items = schema[page][@"items"];
    if (![items isKindOfClass:NSArray.class]) return @[@{@"title": @"Settings Unavailable", @"rows": @[@{@"cell": @"Error", @"label": @"The settings resource could not be loaded."}]}];
    NSMutableArray *result = [NSMutableArray new];
    NSMutableDictionary *section = nil;
    for (NSDictionary *row in items) {
        if (![row isKindOfClass:NSDictionary.class]) continue;
        if ([row[@"cell"] isEqual:@"PSGroupCell"]) {
            section = [@{@"title": ABC26Label(schema, row[@"label"], page), @"rows": [NSMutableArray new]} mutableCopy];
            [result addObject:section];
        } else {
            if (!section) { section = [@{@"title": @"", @"rows": [NSMutableArray new]} mutableCopy]; [result addObject:section]; }
            [section[@"rows"] addObject:row];
        }
    }
    NSIndexSet *empty = [result indexesOfObjectsPassingTest:^BOOL(NSDictionary *group, NSUInteger index, BOOL *stop) { return [group[@"rows"] count] == 0; }];
    [result removeObjectsAtIndexes:empty];
    return result;
}
NSDictionary *ABC26Defaults(NSDictionary *schema) {
    NSMutableDictionary *defaults = [NSMutableDictionary new];
    for (NSString *page in @[@"root", @"strings"]) for (NSDictionary *row in schema[page][@"items"]) {
        NSString *key = row[@"key"];
        if (key && row[@"default"]) defaults[key] = row[@"default"];
    }
    return defaults;
}
BOOL ABC26ValidateValue(NSDictionary *schema, NSString *key, id value) {
    if (![key isKindOfClass:NSString.class]) return NO;
    for (NSString *page in @[@"root", @"strings"]) for (NSDictionary *row in schema[page][@"items"]) {
        if (![row[@"key"] isEqual:key]) continue;
        if (!value) return YES;
        if ([row[@"cell"] isEqual:@"PSSwitchCell"]) return [value isKindOfClass:NSNumber.class] && ([value doubleValue] == 0 || [value doubleValue] == 1);
        if ([row[@"cell"] isEqual:@"PSEditTextCell"]) return [value isKindOfClass:NSString.class] && [value length] <= 2048;
        return NO;
    }
    return NO;
}
NSDictionary<NSString *, NSString *> *ABC26Whitelist(NSDictionary *settings) {
    id value = settings[@"whitelist"];
    if (!value) return @{};
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    for (id key in value) if (![key isKindOfClass:NSString.class] || ![key length] || ![value[key] isKindOfClass:NSString.class]) return nil;
    return value;
}
