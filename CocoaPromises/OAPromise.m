#import "OAPromise.h"

@interface OAPromise ()
@property(atomic) OAPromise* returnedPromise;
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
 	dispatch_queue_t _callbackQueue; // retained/released by ARC
	dispatch_queue_t _errbackQueue; // retained/released by ARC
	OAPromise* _substitutePromise; // when not nil, replaces self
}

@synthesize progress=_progress;
@synthesize value=_value;
@synthesize error=_error;
@dynamic assignedCallback;


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





- (OAPromise*) then:(OAPromiseFinishBlock)block error:(OAPromiseFailureBlock)errorBlock progress:(OAPromiseProgressBlock)progressBlock
{
	return [self then:block error:errorBlock completion:nil progress:progressBlock];
}

- (OAPromise*) then:(OAPromiseFinishBlock)block
{
	return [self then:block error:nil completion:nil progress:nil];
}

- (OAPromise*) then:(OAPromiseFinishBlock)block progress:(OAPromiseProgressBlock)progressBlock
{
	return [self then:block error:nil completion:nil progress:progressBlock];
}

- (OAPromise*) then:(OAPromiseFinishBlock)block error:(OAPromiseFailureBlock)errorBlock
{
	return [self then:block error:errorBlock completion:nil progress:nil];
}

- (OAPromise*) error:(OAPromiseFailureBlock)errorBlock
{
	return [self then:nil error:errorBlock completion:nil progress:nil];
}

- (OAPromise*) progress:(OAPromiseProgressBlock)progressBlock
{
	return [self then:nil error:nil completion:nil progress:progressBlock];
}

- (OAPromise*) completion:(OAPromiseCompletionBlock)block
{
	return [self then:nil error:nil completion:block progress:nil];
}

- (OAPromise*) completion:(OAPromiseCompletionBlock)block progress:(OAPromiseProgressBlock)progressBlock
{
	return [self then:nil error:nil completion:block progress:progressBlock];
}

// This is not a public method because it's incorrect to expose both then/error and completion arguments. Only either of them can be set.
- (OAPromise*) then:(OAPromiseFinishBlock)thenBlock
			  error:(OAPromiseFailureBlock)errorBlock
		 completion:(OAPromiseCompletionBlock)completionBlock
		   progress:(OAPromiseProgressBlock)progressBlock
{
	@synchronized(self)
	{
		
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
			_callbackQueue = dispatch_get_current_queue();
			_errbackQueue = dispatch_get_current_queue(); // set also for consistency to avoid nasty errors.
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
				_callbackQueue = dispatch_get_current_queue();
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
				_errbackQueue = dispatch_get_current_queue();
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
				dispatch_get_current_queue()
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
			// self is not resolved yet, but may generate some progress events.
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
		dispatch_queue_t queue = blockAndQueue[1];
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
		dispatch_async(_callbackQueue, ^{
			OAPromise* nextPromise = block(value, nil);
			[self connectNextPromise:nextPromise context:@"completion block on success"];
		});
	}
	else if (_callbackBlock)
	{
		OAPromiseFinishBlock block = _callbackBlock;
		dispatch_async(_callbackQueue, ^{
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
		dispatch_async(_errbackQueue, ^{
			OAPromise* nextPromise = block(nil, error);
			[self connectNextPromise:nextPromise context:@"completion block on failure"];
		});
	}
	else if (_errbackBlock)
	{
		OAPromiseFailureBlock block = _errbackBlock;
		dispatch_async(_errbackQueue, ^{
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
	_callbackQueue = nil;
	_callbackBlock = nil;
	_errbackQueue = nil;
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
