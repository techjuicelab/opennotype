#import "ONTExceptionCatcher.h"

BOOL ONTPerformCatchingException(NS_NOESCAPE void (^block)(void), NSString *_Nullable *_Nullable reason) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (reason) { *reason = [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason ?: @""]; }
        return NO;
    }
}
