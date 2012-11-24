#import <Foundation/Foundation.h>

@interface OAConcurrentOperation : NSOperation
@property (nonatomic, readonly) BOOL success;               // After completion, if the operation has not been cancelled, contains a success boolean.
@property (nonatomic, readonly) NSError *error;     // After completion, if the operation has not been cancelled, and success is false, contains an NSError.

// @see main
- (void)finishWithSuccess:(BOOL)success error:(NSError *)error;

// Subclasses should override, and eventually invoke [cancel] of [finishWithSuccess:error:].
- (void)main;
@end
