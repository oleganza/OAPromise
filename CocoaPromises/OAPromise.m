#import "OAPromise.h"

@implementation OAPromise {
	struct {
		unsigned int resolved:1;
		unsigned int callbackSet:1; // use these flags because we will clear callbacks when they are called to break possible retain cycles.
		unsigned int errbackSet:1;
	} _flags;
	OAPromiseFinishBlock _callbackBlock;
	OAPromiseFailureBlock _errbackBlock;
	OAPromiseCompletionBlock _completionBlock;
	NSMutableArray* _progressBlocksAndQueues; // list of pairs of [block, queue]
 	dispatch_queue_t _callbackQueue; // retained/released by ARC
	dispatch_queue_t _errbackQueue; // retained/released by ARC
}

@synthesize progress=_progress;
@synthesize value=_value;
@synthesize error=_error;


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
	@synchronized(self) {
		return _progress;
	}
}

- (void) setProgress:(double)progress
{
	@synchronized(self) {
		if (_flags.resolved) {
			@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot update progress when the promise is already resolved with either a value or an error." userInfo:nil];
		}
		if (progress > 1.0) progress = 1.0;
		if (progress < 0.0) progress = 0.0;
		if (progress == _progress) return;
		_progress = progress;
		[self notifyProgress:_progress];
	}
}

- (id) value
{
	@synchronized(self) {
		return _value;
	}
}

- (void) setValue:(id)value
{
	@synchronized(self) {
		if (_flags.resolved) {
			@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot set value when the promise is already resolved with either a value or an error." userInfo:nil];
		}
		_flags.resolved = 1;
		_value = value;
		if (_progress != 1.0) {
			_progress = 1.0;
			[self notifyProgress:_progress];
		}
		[self notifyValue:_value];
	}
}

- (NSError*) error
{
	@synchronized(self) {
		return _error;
	}
}

- (void) setError:(NSError *)error
{
	@synchronized(self) {
		if (_flags.resolved) {
			@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot set error when the promise is already resolved with either a value or an error." userInfo:nil];
		}
		_flags.resolved = 1;
		_error = error;
		[self notifyError:_error];
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

// This is not a public method because it's incorrect to expose both then/error and completion arguments: only either of them can be set.
- (OAPromise*) then:(OAPromiseFinishBlock)thenBlock
			  error:(OAPromiseFailureBlock)errorBlock
		 completion:(OAPromiseCompletionBlock)completionBlock
		   progress:(OAPromiseProgressBlock)progressBlock
{
	@synchronized(self) {
		
		// If it'll remain nil, it means we have no callback added, only progress; should return self.
		OAPromise* newPromise = nil;
		
		// Decide what API do we use: then:error: or completion:
		if (completionBlock)
		{
			if (_flags.callbackSet || _flags.errbackSet)
			{
				@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot set completion block, callback(s) already provided." userInfo:nil];
			}
			
			_flags.callbackSet = 1;
			_flags.errbackSet = 1;
			_completionBlock = [completionBlock copy];
			_callbackQueue = dispatch_get_current_queue();
			_errbackQueue = dispatch_get_current_queue(); // set also for consistency to avoid nasty errors.
		}
		else // We are using then:error: callbacks.
		{
			if (thenBlock)
			{
				if (_flags.callbackSet)
				{
					@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot set success block, callback(s) already provided." userInfo:nil];
				}

				_flags.callbackSet = 1;
				_callbackBlock = [thenBlock copy];
				_callbackQueue = dispatch_get_current_queue();
			}
			
			if (errorBlock)
			{
				if (_flags.errbackSet)
				{
					@throw [NSException exceptionWithName:@"OAPromiseInconsistency" reason:@"Cannot set error block, callback(s) already provided." userInfo:nil];
				}
				_flags.errbackSet = 1;
				_errbackBlock = [errorBlock copy];
				_errbackQueue = dispatch_get_current_queue();
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
		
		if (!newPromise)
		{
			return self;
		}
		return newPromise;
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
			block(value, nil);
		});
	}
	else if (_callbackBlock)
	{
		OAPromiseFinishBlock block = _callbackBlock;
		dispatch_async(_callbackQueue, ^{
			block(value);
		});
	}
	[self cleanupCallbacks];
}

- (void) notifyError:(NSError*)error
{
	if (_completionBlock)
	{
		OAPromiseCompletionBlock block = _completionBlock;
		dispatch_async(_errbackQueue, ^{
			block(nil, error);
		});
	}
	else if (_callbackBlock)
	{
		OAPromiseFailureBlock block = _errbackBlock;
		dispatch_async(_errbackQueue, ^{
			block(error);
		});
	}

	[self cleanupCallbacks];
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


@end
