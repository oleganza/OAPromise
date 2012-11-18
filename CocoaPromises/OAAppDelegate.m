#import "OAAppDelegate.h"
#import "OAPromise.h"

@implementation OAAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// Simple test.
	
	OAPromise* promise = [OAPromise promise];
	
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC);
	dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		promise.value = @"Okay";
	});
	
	[promise then:^OAPromise*(id value){
		NSLog(@"Got value: %@", value);
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
