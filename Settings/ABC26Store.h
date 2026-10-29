#import <Foundation/Foundation.h>
@interface ABC26Store : NSObject
@property(nonatomic, copy, readonly) NSString *path;
- (instancetype)initWithPath:(NSString *)path schema:(NSDictionary *)schema;
- (NSDictionary *)read:(NSError **)error;
- (BOOL)saveValue:(id)value key:(NSString *)key error:(NSError **)error;
- (BOOL)updateWhitelist:(NSDictionary *)additions removing:(NSArray *)identifiers error:(NSError **)error;
- (BOOL)addWhitelist:(NSDictionary *)entries addresses:(NSDictionary *)addresses error:(NSError **)error;
@end
