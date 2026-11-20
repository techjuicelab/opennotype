#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and converts an Objective-C exception into a NO result. Swift cannot catch these
/// exceptions, and some system APIs (AVAudioNode.installTap on a changed input format) raise them.
/// The caller must treat any object the block was using as unusable after a NO result.
BOOL ONTPerformCatchingException(NS_NOESCAPE void (^block)(void), NSString *_Nullable *_Nullable reason);

NS_ASSUME_NONNULL_END
