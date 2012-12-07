#import <Foundation/Foundation.h>

/*
 
 OAPromise is an API to decouple operations and completion callbacks. 
 Instead of accepting callback directly, a method should return a promise object.
 Creator of a promise later *resolves* it with either a value or an error. It can also report
 progress.
 
 Caller attaches success and failure callbacks to be notified about operation completion.
 Attaching a callback produces another promise object,
 
 Only one success callback and one error callback can be set for a promise.
 When the promise is resolved, you cannot update its state (value, error, progress).
 
 If the callback is attached when promise is already resolved, it will be called on the next runloop cycle.
 
 There is no explicit API for cancellation. It is recommended to set a NSError with appropriate domain/code.
 For instance, NSCocoaErrorDomain and NSUserCancelledError.
 Alternatively, one may set value to nil to resolve the promise with a success, but no value.
 It is then a responsibility of a caller to interpret nil value and nil error as cancellation.
 
 OAPromise remembers caller dispatch queue for each added block and thus 
 guarantees that the block is always called on the same queue it was added.
 In addition, to provide consistent ordering of operations, all callbacks 
 are performed always asynchronously, even when the promise is already resolved.
 
 */

@class OAPromise;

typedef OAPromise*(^OAPromiseFinishBlock)(id);
typedef OAPromise*(^OAPromiseFailureBlock)(NSError*);
typedef OAPromise*(^OAPromiseCompletionBlock)(id, NSError*);
typedef void(^OAPromiseProgressBlock)(double);

@interface OAPromise : NSObject

//== Client API

// Attaches callback blocks for successful completion, failure and progress notifications.
// Every block is optional. Success and failure blocks can be added only once. You can add multiple progress blocks.
// Returns a new promise object if either success or failure block is added. Returns self otherwise.
//
// Each callback is guaranteed to be called on the next runloop cycle (even if the promise is already resolved).
// Each callback is called on the dispatch queue.
// If the queue is nil, main dispatch queue is used.
- (OAPromise*) then:(OAPromiseFinishBlock)block error:(OAPromiseFailureBlock)errorBlock progress:(OAPromiseProgressBlock)progressBlock queue:(dispatch_queue_t)queue;

// Equivalent to -then:error:progress: with nil error block.
- (OAPromise*) then:(OAPromiseFinishBlock)block queue:(dispatch_queue_t)queue;
- (OAPromise*) then:(OAPromiseFinishBlock)block progress:(OAPromiseProgressBlock)progressBlock  queue:(dispatch_queue_t)queue;

// Equivalent to -then:error:progress: with nil progress block.
- (OAPromise*) then:(OAPromiseFinishBlock)block error:(OAPromiseFailureBlock)errorBlock queue:(dispatch_queue_t)queue;

// Equivalent to -then:error:progress: with nil completion and progress blocks.
- (OAPromise*) error:(OAPromiseFailureBlock)errorBlock queue:(dispatch_queue_t)queue;

// Adds a progress block. Returns self. Equivalent to -then:error:progress: with first two arguments being nil.
- (OAPromise*) progress:(OAPromiseProgressBlock)progressBlock queue:(dispatch_queue_t)queue;

// Equivalent to -then:error:progress:, but uses a single completion block with value and error instead of two separate blocks.
// Returns a new promise object if block is not nil. Otherwise returns self.
- (OAPromise*) completion:(OAPromiseCompletionBlock)block queue:(dispatch_queue_t)queue;
- (OAPromise*) completion:(OAPromiseCompletionBlock)block progress:(OAPromiseProgressBlock)progressBlock queue:(dispatch_queue_t)queue;

// Returns a promise which will be resolved with a value returned by -valueForKey: sent to the value of the receiver (when it is resolved).
- (OAPromise*) promisedValueForKey:(NSString*)key;


//== Sender API

// Returns a new unresolved promise.
+ (OAPromise*) promise;

// Returns a new promise resolved with value immediately.
+ (OAPromise*) promiseWithValue:(id)value;

// Returns a new promise resolved with error immediately.
+ (OAPromise*) promiseWithError:(NSError*)error;

// When the value is set (nil is allowed to mean cancellation), promise is resolved and the success completion block is called.
// If the value is set second time, exception is raised.
// Value can be set from any thread.
@property(atomic) id value;

// When the error is set (nil is ignored), promise is resolved and the failure completion block is called.
// If the value is set second time, exception is raised.
// Error can be set from any thread.
@property(atomic) NSError* error;

// A value from 0.0 to 1.0 inclusive. Setter caps the value to the valid range.
// Progress is set to 1.0 when the promise is resolved with a value.
// When the progress is updated, all progress blocks are called in the order they have been added.
// Exception is raised when the progress is set when the promise is already resolved.
@property(atomic) double progress;

// Returns YES if the receiver is already assigned either failure or success callback.
@property(atomic, readonly, getter=isAssignedCallback) BOOL assignedCallback;

// Returns YES if the receiver is already resolved with either error or value.
@property(atomic, readonly, getter=isResolved) BOOL resolved;

// Returns YES if this promise or any promise down the chain is discarded using -discard.
- (BOOL) isDiscarded;

// Marks promise as discarded so the owner of the promise may (but not required) to check -isDiscarded to resolve the promise early with an error or a value.
- (void) discard;

- (BOOL) orly; //https://twitter.com/michaelklishin/status/272997040496209920

@end


// Block-property API is useful for long chains of commands as a syntactic sugar.
// Example:
// [self doSomething].then(^(id _){
//     return [self nextCommand];
// }).then(^(id _){
//     return [self finalCommand];
// }).then(^(id _){
//     return nil; // done already.
// })

@interface OAPromise (BlockProperties)

// promise.then(^(id){ ... }) is equivalent to [promise then:^(id){ ... }]
- (OAPromise*(^)(OAPromiseFinishBlock, dispatch_queue_t)) then;

// promise.onError(^(NSError*){ ... }) is equivalent to [promise error:^(NSError*){ ... }]
- (OAPromise*(^)(OAPromiseFailureBlock, dispatch_queue_t)) onError;

// promise.onCompletion(^(id, NSError*){ ... }) is equivalent to [promise completion:^(id, NSError*){ ... }]
- (OAPromise*(^)(OAPromiseCompletionBlock, dispatch_queue_t)) onCompletion;

@end
