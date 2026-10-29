#import <Foundation/Foundation.h>
NSArray<NSDictionary *> *ABC26Sections(NSDictionary *schema, NSString *page);
NSDictionary *ABC26Defaults(NSDictionary *schema);
NSString *ABC26Label(NSDictionary *schema, NSString *text, NSString *page);
BOOL ABC26ValidateValue(NSDictionary *schema, NSString *key, id value);
NSDictionary<NSString *, NSString *> *ABC26Whitelist(NSDictionary *settings);
