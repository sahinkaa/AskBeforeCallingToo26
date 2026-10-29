#pragma once
#import <Foundation/Foundation.h>

#if defined(ABT_HOST_TEST)
// The host fixture supplies an isolated filesystem root.
static inline NSString *ABTPath(NSString *path) { return jbroot(path); }
#elif defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
#import <roothide.h>
static inline NSString *ABTPath(NSString *path) { return jbroot(path); }
#elif defined(THEOS_PACKAGE_SCHEME_ROOTLESS)
#import <rootless.h>
static inline NSString *ABTPath(NSString *path) { return ROOT_PATH_NS_VAR(path); }
#else
#error Choose the rootless or roothide package scheme.
#endif
