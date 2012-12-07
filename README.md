# OAPromise v0.1

Promise is an object returned from an asynchronous API. Creator of a promise resolves it asynchronously with either a resulting value, or an error. Receiver of the promise attaches callbacks to it to get notified about the value or error.

OAPromise objects can be passed and stored between different objects.

OAPromise is thread-safe. Callbacks are invoked on the caller's dispatch queue. Value and error can be set from any thread.

OAPromise allows at most one callback. Methods attaching the callback (-then:, -then:error:, -completion: etc.) return another promise instance.

OAPromise allows attaching the callback when the value is already set.

Completion blocks are guaranteed to be called asynchronously in all cases.

OAPromise supports progress notifications.


### Motivation

Comparing to usual callback-based APIs, OAPromise has several advantages:

* Allows passing unfinished result between objects.
* Automatically deals with dispatch queues of the callers.
* Provides consistent API for reporting errors and progress.
* Enables fall-through for errors to the nearest error handler.


### To be done

* Easy API for chaining several typical promises. (E.g. uploading several pictures.)
* API for concurrent operations with explicit policy of error handling.
* Cancellation API (isResolved must look into the chain of promises)


### Interesting Issues

* Allowing multiple success/failure callbacks allows building a tree of dependant promises. 
* Promise can be considered discarded only if it has its own flag set, or if all its child promises are discarded.
* Sometimes we want to discard "observation" of a promise, not the whole chain of operations. E.g. view controller uploads a picture, has Back and Cancel buttons. If Back button is tapped, operation must continue, but all promises and callbacks related to UI updates must be cleaned up. Thus we must distinguish between cancelling the whole chain and only some promises in the end.
* When promise is discarded we want to cleanup its callbacks immediately without waiting for the current task to acknowledge and cancel.
* This brings us to an idea that discard process should be parallel to succes and failure propagation + should deal with the fact that callbacks were possibly cleaned up.
* 3 ways to avoid chaining: 1) manually managing promise(s), 2) [promise observation], 3) [promise observe:…]
* Discard may deserve its own callback like "finally" in exception handling. 
* If succeeding promises were already cleaned up, "finally" blocks are either not called or called before real operation have finished. Which may look odd sometimes, but perhaps not unfixable.
* Thus, "finally" callback should not return any promise at all: ^(BOOL finished){ … }
* If -completion: is used to handle finally, then it may return promise when not appropriate which must be immediately cleaned up, but operations are already started. So -completion: must not deal with discards.


### Simple callback

Send a message, receive a promise. Attach a callback to the promise.

    [[Person loadFromDisk] then:^(id person){
        NSLog(@"Person loaded.");
        return nil;
    }];


### Handling errors

Send a message, receive a promise. Attach a success callback and a failure callback to the promise.

    [[Person loadFromDisk] then:^(id person){
        NSLog(@"Person loaded.");
        return nil;
    } error:^(NSError* error){
        NSLog(@"Failed to load person.");
        return nil;
    }];



### Giving promises

Providing promise-based API is very simple.

1. When the operation is started, create new instance of OAPromise and return it to caller.
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


### Chaining promises

Each success or failure callback returns a promise or `nil`. This allows chaining several operations.

    [[[Person loadFromDisk] then:^(id person){
        return [person loadPicture];
    }] then:^(id picture){
        NSLog(@"Picture loaded.");
        return nil;
    }]

In this example `-then:` assigns the first callback and returns a promise to which we attach a second callback. When the first operation completes, `-loadPicture` returns another promise which magically linked with the one returned by `-then:` before. This way we have chained two callbacks even before the first operation (`loadFromDisk`) has completed.


### Handling all errors in one place

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


### Recovering from errors

Success and error callbacks behave the same way: they both must return a promise or `nil`. If promise is returned, the chain will continue as expected. If `nil` is returned, the chain will halt.

It means, that if error callback returns a promise, we have recovered from the error and may continue.


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

Here we try to load the data from disk, but if it fails, we go to the server. In this example we do not handle the error from `-loadFromServer` and let it fall through to the common error handler.



### Providing progress updates

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


### Combined progress

It is also possible to combine progress from multiple operations.
Say, we need to load person data from disk and then load his picture.

In this example we assume that loading data usually takes 30% of the time and picture takes 70%. Also `-loadFromDisk` and `loadPicture` should provide progress updates for their operations.

```
__block OAPromise* promise = [[Person loadFromDisk] then:^(id person){
    return [[person loadPicture] progress:^(double picProgress){
        promise.progress = 0.30 + 0.70*picProgress;
    }];
} progress:^(double personProgress){
    promise.progress = 0.30*personProgress;
}];

[promise progress:^(double p){
    NSLog(@"combined progress = %f", p);
}];
```


### Cancelling operations

It is important to understand that promise does not represent an _operation_, but a future _result_. Operation is controlled by someone else while the promise merely reflects what the operation is doing.

However, there is a way to let the operation know if we wish to cancel it. User receiving a promise, can send it a message `-discard` when the promise is no longer interesting. An operation owning a promise may check from time to time if the promise `isDiscarded` and resolve it with a value or an error. Discarding promise does not produce any immediate side effect. Every operation has complete control on how and when to resolve the promise. Operation is not required to even check if the promise is discarded.

This works with chained promises as well. If the promise on the end of the chain is discarded, all preceding promises will be discarded too.

1) During the operation, check if the promise `-isDiscarded` and resolve it early.

```
+ (OAPromise*) loadFromDisk {
    OAPromise* promise = [OAPromise promise];
    dispatch_async(my_queue, ^{
        ...
        // Check if the promise is not longer needed and exit early.
        if (promise.isDiscarded) {
            promise.error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
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



### Balancing state

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













