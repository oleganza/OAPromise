# OAPromise - Work In Progress

Promise is an object returned from an asynchronous API. Creator of a promise resolves it asynchronously with either a resulting value, or an error. Receiver of the promise uses callbacks to receive the value or error.

OAPromise objects can be passed and stored between different objects.

OAPromise is thread-safe. Callbacks are invoked on the caller's dispatch queue. Value and error can be set from any thread.

OAPromise allows at most one callback. Methods attaching the callback (-then:, -then:error:, -completion: etc.) return another promise instance.

OAPromise allows attaching the callback when the value is already set. 

Completion blocks are guaranteed to be called asynchronously in all cases.

OAPromise supports progress notifications.


### Motivation

In comparison to usual callback-based APIs, OAPromise:

* allows passing unfinished result between objects,
* automatically deals with dispatch queues of the callers,
* provides consistent API for reporting errors and progress.


### Reading promises


##### Example 1: simple callback

Send a message, receive a promise. Attach a callback to the promise.

    [[Person loadFromDisk] then:^(id person){
    	NSLog(@"Person loaded.");
    	return nil;
    }];

##### Example 2: handling errors

Send a message, receive a promise. Attach a success callback and an error callback to the promise.

    [[Person loadFromDisk] then:^(id person){
    	NSLog(@"Person loaded.");
    	return nil;
    } error:^(NSError* error){
    	NSLog(@"Failed to load person.");
    	return nil;
    }];

##### Example 3: call sequence with simplified error handling (trying out crazy property-block syntax)

Send a message, receive a promise. Attach a success callback and an error callback to the promise. Success callback sends another message returning another promise. Next attached callbacks will apply to the returned promise. Error will be handled by the first error handler in the chain of callbacks.

    [Person loadFromDisk].then(^(id person){
    	return [person loadPicture];
    }).then(^(id picture){
    	NSLog(@"Picture loaded.");
    	return nil;
    }).onError(^(NSError* error){
    	NSLog(@"Failed to load either person or picture.");
    	return nil;
    });

##### Example 4: call sequence with error handling at each step



	[[[Person loadFromDisk] then:^(id person){
		return [person loadPicture];
	} error:^(NSError* error){
		NSLog(@"Failed to load person.");
		return nil;
	}] then:^(id picture){
		NSLog(@"Picture loaded");
	} error:^(NSError* error){
		NSLog(@"Failed to load picture.");
		return nil;
	}];



### Creating promises


##### Example 1: simple callback


    - (OAPromise*) loadFromDisk { 
    	OAPromise* promise = [OAPromise promise];
    	dispatch_async(my_queue, ^{
    	    ...
    	    if (loaded) {
	    		promise.result = person;
	    	} else {
		    	promise.error = [NSError ...];
	    	}
    	});
    	return promise;
    }



##### Example 2: a composition




### Balancing

In this code we have to balance the semaphore state. Regardless of whether any operation completed successfully or not, in the end semaphore should have the same value as before entering the method.



	- (void) someMethod {
				
		_semaphore++;		
		
		[[[self makeFirstStep] then:^(id value){
			
			if ([value isSpecialCase]) {
				_semaphore--;
				return nil;
			}
			
			return [self makeSecondStep];
			
		} error:^(NSError* error){
			_semaphore--;
			return nil;
		}] then:^(id value){
			
			_semaphore--;
			return nil;
		}];
	}


Returning ready value:

	- (void) someMethod {
				
		_semaphore++;
		OAPromise* semaphoreCompletion = [OAPromise promiseWithValue:@YES];
		
		[[[self makeFirstStep] then:^(id value){
			
			if ([value isSpecialCase]) {
				return semaphoreCompletion;
			}
			return [self makeSecondStep];
			
		} error:^(NSError* error){

			return semaphoreCompletion;
			
		}] completion:^(id,id){
		
			_semaphore--;
			return nil;
			
		}];
	}


### Extras


	[[BackgroundJob runInBackground:^{
		return resizedImage();
	}] then:^(id image){
		
	}];













