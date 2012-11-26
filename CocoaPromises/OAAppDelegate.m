#import "OAAppDelegate.h"
#import "OAPromise.h"
#import "OAPromiseTestSuite.h"

@implementation OAAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	[[[OAPromiseTestSuite alloc] init] testAll];
}


@end
