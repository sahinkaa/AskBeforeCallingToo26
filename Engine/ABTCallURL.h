#import <Foundation/Foundation.h>
// Recognize only system dial intents. Preserve the complete NSURL for the original opener.
NSDictionary<NSString *, NSString *> *ABTCallURLInfo(NSURL *url);
BOOL ABTCallURLEmergencyScheme(NSURL *url);
