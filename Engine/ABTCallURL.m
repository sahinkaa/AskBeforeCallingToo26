#import "ABTCallURL.h"

BOOL ABTCallURLEmergencyScheme(NSURL *url) {
    if (![url isKindOfClass:NSURL.class]) return NO;
    return [@[@"telsos", @"telemergencycall"] containsObject:url.scheme.lowercaseString];
}
NSDictionary<NSString *, NSString *> *ABTCallURLInfo(NSURL *url) {
    if (![url isKindOfClass:NSURL.class] || ABTCallURLEmergencyScheme(url)) return nil;
    NSString *scheme = url.scheme.lowercaseString;
    // Exact values found in the device's TelephonyUtilities URL helpers. Navigation,
    // incoming calls, join links, messages and mail URLs are deliberately excluded.
    if (![@[@"tel",@"telprompt",@"telephony",@"telephonyprompt",@"callto",@"facetime",@"facetime-audio",@"facetime-prompt",@"facetime-audio-prompt"] containsObject:scheme]) return nil;
    NSString *raw = url.absoluteString;
    NSRange colon = [raw rangeOfString:@":"];
    if (colon.location == NSNotFound) return nil;
    NSString *recipient = [raw substringFromIndex:colon.location+1];
    while ([recipient hasPrefix:@"/"]) recipient = [recipient substringFromIndex:1];
    NSRange query = [recipient rangeOfString:@"?"];
    if (query.location != NSNotFound) recipient = [recipient substringToIndex:query.location];
    recipient = recipient.stringByRemovingPercentEncoding ?: recipient;
    if (!recipient.length) {
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem *item in components.queryItems) if ([item.name isEqual:@"isVoicemail"] && item.value.boolValue) recipient = @"voicemail";
    }
    if (!recipient.length) return nil; // Opening an app without a dial destination.
    return @{@"scheme":scheme, @"recipient":recipient};
}
