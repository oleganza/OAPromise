#import "OAAppDelegate.h"
#import "OAPromise.h"

@implementation OAAppDelegate

- (OAPromise*) delayedSuccess:(NSString*)string
{
	OAPromise* promise = [OAPromise promise];
	
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC);
	dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		promise.value = string;
	});
	
	return promise;
}

- (OAPromise*) delayedError:(NSString*)string
{
	OAPromise* promise = [OAPromise promise];
	
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC);
	dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		promise.error = [NSError errorWithDomain:@"TestDomain" code:0 userInfo:@{NSLocalizedDescriptionKey: string}];
	});
	
	return promise;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// Simple test.
	
	[[[[self delayedSuccess:@"1"] then:^OAPromise*(id value){
		NSLog(@"Got value #1: %@", value);
		return [self delayedSuccess:@"2"];
	}] then:^OAPromise *(id value) {
		NSLog(@"Got value #2: %@", value);
		return nil;
	}] error:^OAPromise *(NSError *err) {
		NSLog(@"Got error: %@", err.localizedDescription);
		return nil;
	}];
	
	// To test:
	//
	// 1. Errors.
	// 2. Queues.
	// 3. Callbacks attached when the value is already there.
	// 4. Duplicate callbacks create an exception.
	// 5. Progress
	// 6. Derived promise callbacks are never called and properly freed when previous promise's block returns nil.
}

@end
