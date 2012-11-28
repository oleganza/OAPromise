#import "OAPromise.h"

#if !__has_feature(objc_arc)
#error ARC required: make sure you do not use -fno-objc-arc on this file in Build Phases. Or use -fobjc-arc.
#endif

#if OS_OBJECT_USE_OBJC
#define OAPromiseDispatchBox(obj)   (obj)
#define OAPromiseDispatchUnbox(obj) (obj)
#else
#define OAPromiseDispatchBox(obj)   ([OAPromiseDispatchBox withQueue:obj])
#define OAPromiseDispatchUnbox(box) (((OAPromiseDispatchBox*)box).queue)
#endif

@interface OAPromiseDispatchBox: NSObject
+ (OAPromiseDispatchBox*) withQueue:(dispatch_queue_t)obj;
@property(nonatomic) dispatch_queue_t queue;
@end

@implementation OAPromiseDispatchBox
+ (OAPromiseDispatchBox*) withQueue:(dispatch_queue_t)obj
{
    OAPromiseDispatchBox* b = [[OAPromiseDispatchBox alloc] init];
    b.queue = obj;
    return b;
}
#if !OS_OBJECT_USE_OBJC
- (void) setQueue:(dispatch_queue_t)queue
{
    if (queue == _queue) return;
    if (_queue) dispatch_release(_queue);
    _queue = queue;
    if (_queue) dispatch_retain(_queue);
}
#endif
- (void) dealloc
{
    self.queue = NULL;
}
@end



@interface OAPromise ()
@property(atomic) OAPromise* returnedPromise;
@property(nonatomic) dispatch_queue_t callbackQueue;
@property(nonatomic) dispatch_queue_t errbackQueue;
@end

@implementation OAPromise {
	struct {
		unsigned int resolved:1;
		unsigned int resolvedWithError:1;
		unsigned int callbacksSet:1; // use these flags because we will clear callbacks when they are called to break possible retain cycles.
	} _flags;
	OAPromiseFinishBlock _callbackBlock;
	OAPromiseFailureBlock _errbackBlock;
	OAPromiseCompletionBlock _completionBlock;
	NSMutableArray* _progressBlocksAndQueues; // list of pairs of [block, queue]
	OAPromise* _substitutePromise; // when not nil, replaces self
}

@synthesize progress=_progress;
@synthesize value=_value;
@synthesize error=_error;
@dynamic assignedCallback;

- (void) dealloc
{
    self.callbackQueue = nil;
    self.errbackQueue = nil;
}

#if !OS_OBJECT_USE_OBJC
- (void) setCallbackQueue:(dispatch_queue_t)q
{
    if (q == _callbackQueue) return;
    if (_callbackQueue) dispatch_release(_callbackQueue);
    _callbackQueue = q;
    if (_callbackQueue) dispatch_retain(_callbackQueue);
}
- (void) setErrbackQueue:(dispatch_queue_t)q
{
    if (q == _errbackQueue) return;
    if (_errbackQueue) dispatch_release(_errbackQueue);
    _errbackQueue = q;
    if (_errbackQueue) dispatch_retain(_errbackQueue);
}
#endif

#pragma mark - Sender API



+ (OAPromise*) promise
{
	return [[self alloc] init];
}

+ (OAPromise*) promiseWithValue:(id)value
{
	OAPromise* promise = [self promise];
	promise.value = value;
	return promise;
}

+ (OAPromise*) promiseWithError:(NSError*)error
{
	OAPromise* promise = [self promise];
	promise.error = error;
	return promise;
}

- (double) progress
{
	@synchronized(self)
	{
		return _progress;
	}
}

- (void) setProgress:(double)progress
{
	@synchronized(self)
	{
		if (_flags.resolved)
		{
			@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot update progress when the promise is already resolved with either a value or an error." userInfo:nil];
		}
		if (progress > 1.0) progress = 1.0;
		if (progress < 0.0) progress = 0.0;
		if (progress == _progress) return;
		_progress = progress;
		[self notifyProgress:_progress];
		_substitutePromise.progress = progress;
	}
}

- (id) value
{
	@synchronized(self)
	{
		return _value;
	}
}

- (void) setValue:(id)value
{
	@synchronized(self)
	{
		if (_flags.resolved)
		{
			@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot set value when the promise is already resolved with either a value or an error." userInfo:nil];
		}
		_flags.resolved = 1;
		_value = value;
		if (_progress != 1.0) {
			_progress = 1.0;
			[self notifyProgress:_progress];
		}
		[self notifyValue:_value];
		_substitutePromise.value = value;
		[self cleanupCallbacks];
	}
}

- (NSError*) error
{
	@synchronized(self)
	{
		return _error;
	}
}

- (void) setError:(NSError *)error
{
	@synchronized(self)
	{
		if (_flags.resolved)
		{
			@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot set error when the promise is already resolved with either a value or an error." userInfo:nil];
		}
		_flags.resolved = 1;
		_flags.resolvedWithError = 1;
		_error = error;
		[self notifyError:_error];
		_substitutePromise.error = error;
		[self cleanupCallbacks];
	}
}

- (BOOL) isAssignedCallback
{
	@synchronized(self)
	{
		return (BOOL)_flags.callbacksSet;
	}
}




#pragma mark - Client API





- (OAPromise*) then:(OAPromiseFinishBlock)block error:(OAPromiseFailureBlock)errorBlock progress:(OAPromiseProgressBlock)progressBlock queue:(dispatch_queue_t)queue
{
	return [self then:block error:errorBlock completion:nil progress:progressBlock queue:queue];
}

- (OAPromise*) then:(OAPromiseFinishBlock)block queue:(dispatch_queue_t)queue
{
	return [self then:block error:nil completion:nil progress:nil queue:queue];
}

- (OAPromise*) then:(OAPromiseFinishBlock)block progress:(OAPromiseProgressBlock)progressBlock queue:(dispatch_queue_t)queue
{
	return [self then:block error:nil completion:nil progress:progressBlock queue:queue];
}

- (OAPromise*) then:(OAPromiseFinishBlock)block error:(OAPromiseFailureBlock)errorBlock queue:(dispatch_queue_t)queue
{
	return [self then:block error:errorBlock completion:nil progress:nil queue:queue];
}

- (OAPromise*) error:(OAPromiseFailureBlock)errorBlock queue:(dispatch_queue_t)queue
{
	return [self then:nil error:errorBlock completion:nil progress:nil queue:queue];
}

- (OAPromise*) progress:(OAPromiseProgressBlock)progressBlock queue:(dispatch_queue_t)queue
{
	return [self then:nil error:nil completion:nil progress:progressBlock queue:queue];
}

- (OAPromise*) completion:(OAPromiseCompletionBlock)block queue:(dispatch_queue_t)queue
{
	return [self then:nil error:nil completion:block progress:nil queue:queue];
}

- (OAPromise*) completion:(OAPromiseCompletionBlock)block progress:(OAPromiseProgressBlock)progressBlock queue:(dispatch_queue_t)queue
{
	return [self then:nil error:nil completion:block progress:progressBlock queue:queue];
}

// This is not a public method because it's incorrect to expose both then/error and completion arguments. Only either of them can be set.
- (OAPromise*) then:(OAPromiseFinishBlock)thenBlock
			  error:(OAPromiseFailureBlock)errorBlock
		 completion:(OAPromiseCompletionBlock)completionBlock
		   progress:(OAPromiseProgressBlock)progressBlock
              queue:(dispatch_queue_t)queue
{
	@synchronized(self)
	{
		if (!queue) queue = dispatch_get_main_queue();
        
		// If it'll remain nil, it means we have no callback added, only progress; should return self.
		OAPromise* newPromise = nil;
		
		// Decide what API do we use: then:error: or completion:
		if (completionBlock)
		{
			if (_flags.callbacksSet)
			{
				@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot set completion block, callback(s) already provided." userInfo:nil];
			}
			else if (_substitutePromise)
			{
				@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot set completion block, substitute promise is already assigned." userInfo:nil];
			}
			
			_flags.callbacksSet = 1;
			_completionBlock = [completionBlock copy];
			self.callbackQueue = queue;
			self.errbackQueue = queue; // set also for consistency to avoid nasty errors.
			newPromise = newPromise ?: [OAPromise promise];
		}
		else // We are using then:error: callbacks.
		{
			if (thenBlock)
			{
				if (_flags.callbacksSet)
				{
					@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot set success block, callback(s) already provided." userInfo:nil];
				}
				else if (_substitutePromise)
				{
					@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot set success block, substitute promise is already assigned." userInfo:nil];
				}

				_flags.callbacksSet = 1;
				_callbackBlock = [thenBlock copy];
				self.callbackQueue = queue;
				newPromise = newPromise ?: [OAPromise promise];
			}
			
			if (errorBlock)
			{
				if (_flags.callbacksSet)
				{
					@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot set error block, callback(s) already provided." userInfo:nil];
				}
				else if (_substitutePromise)
				{
					@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot set error block, substitute promise is already assigned." userInfo:nil];
				}
				_flags.callbacksSet = 1;
				_errbackBlock = [errorBlock copy];
				self.errbackQueue = queue;
				newPromise = newPromise ?: [OAPromise promise];
			}
		}
		
		if (progressBlock)
		{
			if (!_progressBlocksAndQueues)
			{
				_progressBlocksAndQueues = [NSMutableArray array];
			}
			
			[_progressBlocksAndQueues addObject:@[
				[progressBlock copy],
				OAPromiseDispatchBox(queue)
			 ]];
		}
		
		// If already resolved, invoke the callbacks and cleanup.
		if (_flags.resolved && _flags.callbacksSet)
		{
			if (!_flags.resolvedWithError)
			{
				[self notifyValue:_value];
			}
			else
			{
				[self notifyError:_error];
			}
			[self cleanupCallbacks];
		}
		
		if (!newPromise)
		{
			return self;
		}
		
		_returnedPromise = newPromise;
		return newPromise;
	}
}

- (void) connectExistingPromise:(OAPromise*)existingPromise
{
	// Self is a promise without callbacks owned by some operation.
	// existingPromise is a returned promise from some other operation.
	// It already has, or will have callbacks attached.
	
	@synchronized(self)
	{
		if (_flags.resolved)
		{
			// self is already resolved, just need to assign a proper value to existing promise.
			if (!_flags.resolvedWithError)
			{
				existingPromise.value = self.value;
			}
			else
			{
				existingPromise.error = self.error;
			}
		}
		else
		{
			// self is not resolved yet, but may have generated some progress events.
			if (_progress > 0.0)
			{
				existingPromise.progress = _progress;
			}
			// This variable will mean that this promise is replaced by the substitute.
			_substitutePromise = existingPromise;
		}
	}
}




#pragma mark - Notification Helpers




- (void) notifyProgress:(double)progress
{
	for (NSArray* blockAndQueue in _progressBlocksAndQueues)
	{
		OAPromiseProgressBlock block = blockAndQueue[0];
		dispatch_queue_t queue = OAPromiseDispatchUnbox(blockAndQueue[1]);
		dispatch_async(queue, ^{
			block(progress);
		});
	}
}

- (void) notifyValue:(id)value
{
	if (_completionBlock)
	{
		OAPromiseCompletionBlock block = _completionBlock;
		dispatch_async(self.callbackQueue, ^{
			OAPromise* nextPromise = block(value, nil);
			[self connectNextPromise:nextPromise context:@"completion block on success"];
		});
	}
	else if (_callbackBlock)
	{
		OAPromiseFinishBlock block = _callbackBlock;
		dispatch_async(self.callbackQueue, ^{
			OAPromise* nextPromise = block(value);
			[self connectNextPromise:nextPromise context:@"success callback"];
		});
	}
}

- (void) notifyError:(NSError*)error
{
	if (_completionBlock)
	{
		OAPromiseCompletionBlock block = _completionBlock;
		dispatch_async(self.errbackQueue, ^{
			OAPromise* nextPromise = block(nil, error);
			[self connectNextPromise:nextPromise context:@"completion block on failure"];
		});
	}
	else if (_errbackBlock)
	{
		OAPromiseFailureBlock block = _errbackBlock;
		dispatch_async(self.errbackQueue, ^{
			OAPromise* nextPromise = block(error);
			[self connectNextPromise:nextPromise context:@"failure callback"];
		});
	}
	else
	{
		// There is no error handling block, so we need to pass the error through to the next promise.
		if (_returnedPromise)
		{
			_returnedPromise.error = error;
		}
	}
}

- (void) connectNextPromise:(OAPromise*)nextPromise context:(NSString*)context
{
	if (nextPromise.isAssignedCallback)
	{
		@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:[NSString stringWithFormat:@"Cannot accept a promise returned from the %@, callbacks are already assigned.", context] userInfo:nil];
		return;
	}
	
	if (!nextPromise)
	{
		// No next promise, need to break the chain of all callbacks.
		[self cleanupCallbacksAndReturnedPromises];
		return;
	}
	
	if (!_returnedPromise)
	{
		NSAssert(NO, @"This is impossible codepath. Next promise may arise only when the callback is called and if it was called, we must have stored returnedPromise");
		return;
	}
	
	// Now, the self was owned by the operation which created it, but then was abandoned and owned briefly by caller dispatch queue.
	// _returnedPromise is owned by us and not owned by the caller. But it has some callbacks assigned to it.
	// _nextPromise is owned by another operation, has no callbacks assigned.
	// Simply speaking, we need to assign _returnedPromise (RP) to some property of _nextPromise (NP) to make NP redirect all callbacks to RP.
	// Also, there could be a race condition because here we are in the caller's dispatch queue, but NP is owned and controlled by its owner from another dispatch queue.
	// Moreover, the NP may already be resolved.
	
	[nextPromise connectExistingPromise:_returnedPromise];
}

- (void) cleanupCallbacks
{
	_progressBlocksAndQueues = nil;
	self.callbackQueue = nil;
    self.errbackQueue = nil;
	_callbackBlock = nil;
	_errbackBlock = nil;
	_completionBlock = nil;
}

- (void) cleanupCallbacksAndReturnedPromises
{
	[self cleanupCallbacks];
	[_returnedPromise cleanupCallbacksAndReturnedPromises];
	_returnedPromise = nil;
}


@end






@implementation OAPromise (BlockProperties)

// promise.then(^(id){ ... }) is equivalent to [promise then:^(id){ ... }]
- (OAPromise*(^)(OAPromiseFinishBlock,dispatch_queue_t)) then
{
	return ^(OAPromiseFinishBlock block, dispatch_queue_t queue) {
		return [self then:block queue:queue];
	};
}

// promise.onError(^(NSError*){ ... }) is equivalent to [promise error:^(NSError*){ ... }]
- (OAPromise*(^)(OAPromiseFailureBlock,dispatch_queue_t)) onError
{
	return ^(OAPromiseFailureBlock block, dispatch_queue_t queue) {
		return [self error:block queue:queue];
	};
}

// promise.onCompletion(^(id, NSError*){ ... }) is equivalent to [promise completion:^(id, NSError*){ ... }]
- (OAPromise*(^)(OAPromiseCompletionBlock,dispatch_queue_t)) onCompletion
{
	return ^(OAPromiseCompletionBlock block, dispatch_queue_t queue) {
		return [self completion:block queue:queue];
	};
}

@end








