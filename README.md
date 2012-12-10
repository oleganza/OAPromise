# OAPromise v0.1

Promise is an object returned from an asynchronous API. Creator of a promise resolves it asynchronously with either a resulting value, or an error. Receiver of the promise attaches callbacks to it to get notified about the value or error.

OAPromise objects can be passed and stored between different objects.

OAPromise is thread-safe. Callbacks are invoked on the dispatch queue specified by caller. Value and error can be set from any thread.

OAPromise allows attaching multiple callbacks. Methods attaching the callback (-then:, -then:error:, -completion: etc.) return another promise instance. This way promises can be organized in trees with multiple concurrent consumers for a single producer.

OAPromise allows attaching the callback when the value is already set. In this case the callback will be called immediately (on the next runloop cycle).

All callback blocks are guaranteed to be called asynchronously in all cases even when the promise was already resolved when the callback was attached.

OAPromise supports progress notifications. Multiple callback blocks can be attached to listen for progress updates.

OAPromise can be discarded to cleanup memory and signal current operation that it can be cancelled. Parent promise is discard too if it has all children discarded. Discarded promises 



## Motivation

Comparing to usual callback-based APIs, OAPromise has several advantages:

* Allows passing unfinished result between objects.
* Automatically deals with dispatch queues of the callers.
* Provides consistent API for reporting errors and progress.
* Enables fall-through for errors to the nearest error handler.


## To be done

* Easy API for chaining several typical promises. (E.g. uploading several pictures.)
* API for concurrent operations with explicit policy of error handling.
* Cancellation API (isResolved must look into the chain of promises)


## Interesting Issues

* Allowing multiple success/failure callbacks allows building a tree of dependent promises. 
* Promise can be considered discarded only if it has its own flag set, or if all its child promises are discarded.
* Sometimes we want to discard "observation" of a promise, not the whole chain of operations. E.g. view controller uploads a picture, has Back and Cancel buttons. If Back button is tapped, operation must continue, but all promises and callbacks related to UI updates must be cleaned up. Thus we must distinguish between canceling the whole chain and only some promises in the end.
* When promise is discarded we want to cleanup its callbacks immediately without waiting for the current task to acknowledge and cancel.
* Also, chain of promises may have its own assumptions about values and errors, so discard coming from the end of the chain should not break these assumptions.
* This brings us to an idea that discard process should be parallel to success and failure propagation + should deal with the fact that callbacks were possibly cleaned up.
* 3 ways to avoid chaining: 1) manually managing promise(s), 2) [promise observation], 3) [promise observe:…]
* Discard may deserve its own callback like "finally" in exception handling. 
* If succeeding promises were already cleaned up, "finally" blocks are either not called or called before real operation have finished. Which may look odd sometimes, but perhaps not unfixable.
* Thus, "finally" callback should not return any promise at all: ^(BOOL finished){ … }
* If -completion: is used to handle finally, then it may return promise when not appropriate which must be immediately cleaned up, but operations are already started. So -completion: must not deal with discards.


## Receiving future values

Send a message, receive a promise. Attach a callback to the promise to receive its value when it becomes available.

    [[Person loadFromDisk] then:^(id person){
        NSLog(@"Person loaded.");
        return nil;
    }];


## Handling errors

Send a message, receive a promise. Attach a success callback and a failure callback to the promise.

    [[Person loadFromDisk] then:^(id person){
        NSLog(@"Person loaded.");
        return nil;
    } error:^(NSError* error){
        NSLog(@"Failed to load person.");
        return nil;
    }];



## Giving promises

Providing promise-based API is very simple.

1. Before starting an operation, create a new instance of OAPromise and return it to the caller.
2. When operation finishes or fails, set the `value` or `error` respectively.
    
```
- (OAPromise*) loadFromDisk
{
    OAPromise* promise = [OAPromise promise];
    dispatch_async(my_queue, ^{
        ...
        if (loaded) {
            promise.value = data;
        } else {
            promise.error = [NSError ...];
        }
    });
    return promise;
}
```


## Chaining promises

Each success or failure callback returns a promise or `nil`. This allows chaining several operations.

    [[[Person loadFromDisk] then:^(id person){
        return [person loadPicture];
    }] then:^(id picture){
        NSLog(@"Picture loaded.");
        return nil;
    }]

In this example `-then:` assigns the first callback and returns a promise to which we attach a second callback. When the first operation completes, `-loadPicture` returns another promise which magically linked with the one returned by `-then:` before. This way we have chained two callbacks even before the first operation (`loadFromDisk`) has completed.

If a callback returns nil, then the next `-then:` and `-error:` callbacks are not called and the chain of promises is effectively broken. However, all the remaining `-completion:` blocks are called anyway (see below **Cleaning up resources**).


## Handling all errors in one place

When the promise is resolved with an error, it falls through the chain of promises until the first failure callback. This allows to handle different errors in a single place.

    [[[[Person loadFromDisk] then:^(id person){
        return [person loadPicture];
    }] then:^(id picture){
        NSLog(@"Picture loaded.");
        return nil;
    }] error:^(NSError* error) {
    	NSLog(@"Error occurred: %@", error);
    	return nil;
    }];

In this example, if `-loadFromDisk` fails, the error will be handled without picture being loaded.

Fall-through errors allow to not deal with errors in some parts of your code and cleanly handle them in some others. For instance, `-loadPicture` internally may have three different operations returning promises and not handle any error by itself because it will be handled at UI level by whatever piece of code currently in charge.


## Recovering from errors

Success and error callbacks behave the same way: they both must return a promise or `nil`. If promise is returned, the chain will continue as expected. If `nil` is returned, the chain will halt.

It means, that if an error callback returns a promise, we have recovered from the error and may continue.


    [[[Person loadFromDisk] then:^(id person){
        return [person loadPicture];
    } error:^(NSError* error){
        NSLog(@"Failed to load person from disk. Try the server.");
        return [[Person loadFromServer] then:^(id person){ 
        	return [person loadPicture];
        }];
    }] then:^(id picture){
        NSLog(@"Picture loaded");
    } error:^(NSError* error){
        NSLog(@"Failed to load picture (or person from the server).");
        return nil;
    }];

Here we try to load some data from disk, but if it fails, we go to the server. In this example we do not handle the error from `-loadFromServer` and let it fall through to the common error handler.



## Providing progress updates

Promises are also useful for providing current progress. The owner of the promise can update its progress property.

    - (OAPromise*) loadFromDisk
    {
        OAPromise* promise = [OAPromise promise];
        dispatch_async(my_queue, ^{
            ...
            promise.progress = 0.3;
            ...
            promise.progress = 0.6;
            ...
            if (loaded) {
                promise.value = data;
            } else {
                promise.error = [NSError ...];
            }
        });
        return promise;
    }

The client adds a callback to get notification whenever progress changes:

    [[self loadFromDisk] progress:^(double progress){

        NSLog(@"Current progress: %f%%", 100*progress);

    } queue:nil];

Unlike success and failure callbacks, you can attach multiple progress callbacks to a single promise.


## Combined progress

It is also possible to combine progress from multiple operations.

In this example we load person data from disk and then load his picture. Lets assume that loading from disk usually takes 30% of the time and picture takes 70%. Also `-loadFromDisk` and `loadPicture` should provide progress updates for their operations.

```
__block OAPromise* promise = [[Person loadFromDisk] then:^(id person){
    return [[person loadPicture] progress:^(double picProgress){
        promise.progress = 0.30 + 0.70 * picProgress;
    }];
} progress:^(double personProgress){
    promise.progress = 0.30 * personProgress;
}];

[promise progress:^(double p){
    NSLog(@"combined progress = %f", p);
}];
```



## Canceling operations

It is important to understand that promise does not represent an _operation_, but a future _result_. Operation is controlled by someone else while the promise merely reflects what the operation is doing.

However, there is a way to let the operation know if we wish to cancel it. User receiving a promise, can send it a message `-discard` when the promise is no longer interesting. This will cleanup all resources occupied by pending promises immediately. An operation owning a promise may check from time to time if the promise `isDiscarded` and stop the task. Operation is not required to even check if the promise is discarded. When it sets the value or error for the discarded promise, no callbacks will be called.

This works with chained promises as well. If the promise on the end of the chain is discarded, all preceding promises will be discarded too.

If promise has several children (then: or error: callback were assigned several times), then all the children must be discarded to make that promise discarded too. If the parent promise is discarded, all its children are discarded as well.

For balancing resource use, `completion` callback must be used. It will always be called either right after a success or failure callback, or when the promise is discard.

1) During the operation, check if the promise `-isDiscarded` and resolve it early.

```
+ (OAPromise*) loadFromDisk {
    OAPromise* promise = [OAPromise promise];
    dispatch_async(my_queue, ^{
        ...
        // Check if the promise is not longer needed and exit early.
        if (promise.isDiscarded) {
            return; // no need to resolve the promise, it was cleaned up already.
        }
        ...
        promise.value = result;
    });
    return promise;
}
```

2) Start an operation (or a chain of operations) and keep the reference to the promise.

```
OAPromise* promise = [[Person loadFromDisk] then:^(id person){
    return [person loadPicture];
}];
```

3) When you need to cancel an operation, send a `-discard` message.

```
- (IBAction) cancel
{
    [promise discard];
}
```


## Cleaning up resources


Promise has 4 types of callback blocks: success, failure, progress, completion. Promise callbacks are cleaned up when it is resolved or discarded.

Success blocks are invoked when the value is set. Failure blocks are invoked when the error is set. Progress blocks are invoked when the progress property is updated. Completion block is called when the promise is either resolved (with success or failure) or discarded.

Completion block is guaranteed to be invoked in all cases, therefore it is the best place to cleanup some resources allocated before the operation.

    - (void) uploadPicture
    {
    	[self showProgressIndicator];
    	[[[self preparePictureData] then:^(NSData* data){ 
    		return [[self uploadData:data] then:^(id _){
    			[self alert:@"Thank you!"];
    			return nil;
    		}];
    	}] completion:^(id _, NSError* __, BOOL finished){
    		// No matter what happens, hide the progress indicator. 
    		// Some operation could have failed, or cancelled, 
    		// but this block will still be called.
    		[self hideProgressIndicator];
    	}];
    }

Completion block takes three arguments: value, error and finished flag. When the promise is discarded, all related promises are discarded too and all their completion blocks are called immediately.


## Memory ownership

Promises form a chain, or more generally, a tree (when you attach multiple callbacks to a single promise using `-then:` etc.).

Current operation owns the promise and updates its status. New promises returned from -then: are retained by the receiver in order to be connected with a returned promise from the callback. When the callback is fired, its promise is cleaned up and its child promises become owned by the respective promises returned from the callback. 

Thus, consumer is not required to keep a strong reference to the promise or worry about retained self in their blocks. However, consumer might want to cancel some operations to reclaim memory sooner (e.g. user leaves the window). This is done via `-discard`. Discarded promises cannot force operation to stop (only inform them), but they do clean up all the callbacks and linked promises immediately.



## Forwarding promises

If you need to attach a `-then:` or `error:` callback, but without continuing with another operation, you may want to forward the existing result to the next consumers. It may be useful for debugging. In such cases return [OAPromise promiseWithValue:value] or [OAPromise promiseWithError:error]:

    [[server downloadPicture] then:^(UIImage* picture){
    	NSLog(@"Downloaded picture with size: %@", [picture valueForKey:@"size"]);
    	return [OAPromise promiseWithValue:picture];
    }];

Next consumer will attach `-then:` callback to the resulting chain of promises and will get picture value exactly the same way (with one runloop cycle delay) as if we did not have logging block added.

Same idea applies to error callbacks. 




## Chaining common operations

How do we chain several operations in a loop easier than this:

```
OAPromise* promise = [OAPromise promiseWithValue:@1];
for (id user in users) {
	promise = [promise then:^(id _){
		return [user uploadPicture];
	}];
};
```

Maybe like this:

```
OAPromise* promise = [OAPromise serialPromisesForObjects:users each:^OAPromise*(id user){
	return [user uploadPicture];
}];
```

And with concurrent promises (see below):

```
OAPromise* promise = [OAPromise concurrentPromisesForObjects:users each:^OAPromise*(id user){
	return [user uploadPicture];
} policy:OAPromiseJoinPolicyFailOnFirstError];
```

## Concurrent operations

Several concurrent operations can be joined using promises. Create a promise which takes an array of _source_ promises to join together. 

When all promises succeed, the result value is always an array of values of all source promises (the order is kept the same) with nil values replaced with NSNull.

Some or all of the promises can fail and there are different ways to handle that. This is specified by _join policies_.

OAPromiseJoinPolicy**FailOnFirstError** — promise is resolved with an error of the first failed promise. All other promises are discarded so the related operations may finish early.

OAPromiseJoinPolicy**FailWithAllErrors** — promise is resolved when all source promises are completed. If at least one has failed, the join also fails with a composite error. The error object will encapsulate all original errors.

OAPromiseJoinPolicy**IgnoreErrors** — promise does not fail. Result value is an array of values from succeeded promises (NSNull is used when the value is nil). Failed promises are ignored. If no promise succeeds, result is empty array.

OAPromiseJoinPolicy**ReplaceErrorsWithNulls** — promise does not fail. Result value is an array of values or `NSNull` instances where the promise has failed. NSNull is also used for promises resolved with nil value.

For more sophisticated handling of individual errors and values, it is advised to monitor each promise individually and have a custom scheme to deal with their errors.

Join promise can be discarded. This will discard every source promise and clean up resources.

It makes little sense to join discarded promises or discard them outside the join promise, but this is handled reasonably: discards are treated as failures and are subject to the specified policy. However, as this is not intended behavior, a warning is logged each time an unexpected discard appears.

```
[[OAPromise promiseByJoiningPromises:@[ [self loadPicture1], [self loadPicture2] ] policy:OAPromiseJoinPolicyFailOnFirstError] then:^(NSArray* results){
	// Got both images.
	return nil;
}];
```

## Operation helpers (value is questionable)

Some tasks are performed often and deserve a handy shortcut.

Execute a block in a queue with default priority and pass the result in a promise. If value is nil and error is not nil, then the promise is resolved with an error.

```
[OAPromise promiseForOperation:^id(NSError** error){ 
	return [self loadPicture];
} queue:nil];
```

Execute a block in a background queue with default priority and pass the result in a promise.

```
[[OAPromise promiseForBackgroundOperation:^id(NSError*){ 
	return [self loadPicture]; 
}];
```



## Deferred operations (rough idea)

Idea: return a promise which encapsulates a block running an operation to trigger it later (on the next runloop cycle). If nobody attaches this promise in a chain of other promises, this operation will start. Otherwise, it will start only when its turn comes and previous operations did not fail.

Probably this idea is not smart because it leads to a confusion between deferred and non-deferred operations and make it harder to reason about local piece of code.

This may deserve another class like NSOperation as it's no longer a value promise, but an operation promise.











