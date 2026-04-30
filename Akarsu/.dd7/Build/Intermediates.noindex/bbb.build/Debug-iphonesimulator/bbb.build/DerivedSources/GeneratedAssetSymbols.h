#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "UploadTipsBad" asset catalog image resource.
static NSString * const ACImageNameUploadTipsBad AC_SWIFT_PRIVATE = @"UploadTipsBad";

/// The "UploadTipsGood" asset catalog image resource.
static NSString * const ACImageNameUploadTipsGood AC_SWIFT_PRIVATE = @"UploadTipsGood";

#undef AC_SWIFT_PRIVATE