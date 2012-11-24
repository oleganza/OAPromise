#import "OAConcurrentOperation.h"

@interface OAConcurrentOperation()
@property (atomic, getter=isExecuting, readonly) BOOL executing;
@property (atomic, getter=isFinished, readonly) BOOL finished;
@property (atomic, getter=isCancelled, readonly) BOOL cancelled;
@property (nonatomic) BOOL success;
@property (nonatomic) NSError *error;
- (void)finishWithSuccess:(BOOL)success error:(NSError *)error;
@end

@implementation OAConcurrentOperation
@synthesize executing=_executing;   // make sure compiler implements executing alias
@synthesize finished=_finished;     // make sure compiler implements finished alias
@synthesize cancelled=_cancelled;   // make sure compiler implements cancelled alias

- (id)init
{
    self = [super init];
    if (self) {
        _executing = NO;
        _finished = NO;
    }
    return self;
}

- (BOOL)isConcurrent
{
    return YES;
}

- (BOOL)isExecuting
{
    @synchronized(self) {
        return _executing;
    }
}

- (BOOL)isFinished
{
    @synchronized(self) {
        return _finished;
    }
}

- (BOOL)isCancelled
{
    @synchronized(self) {
        return _cancelled;
    }
}

- (void)cancel
{
    if (self.isFinished) {
        // too late
        return;
    }
    
    @synchronized(self) {
        // manually manage isExecuting and isFinished KVO, because properties would not.
        
        [self willChangeValueForKey:@"isCancelled"];
        [self willChangeValueForKey:@"isExecuting"];
        [self willChangeValueForKey:@"isFinished"];
        
        _cancelled = YES;
        _executing = NO;
        _finished = YES;
        
        [self didChangeValueForKey:@"isCancelled"];
        [self didChangeValueForKey:@"isExecuting"];
        [self didChangeValueForKey:@"isFinished"];
    }
}

- (void)start
{
    if (self.isCancelled) {
        return;
    }
    
    {
        // NSOperation state machine
        // Manually manage isExecuting and isFinished KVO, because properties would not.
        
        [self willChangeValueForKey:@"isExecuting"];
        _executing = YES;
        [self didChangeValueForKey:@"isExecuting"];
    }
    
    
    [self main];
}

- (void)main
{
    [self finishWithSuccess:YES error:nil];
}


#pragma mark - Private

- (void)finishWithSuccess:(BOOL)success error:(NSError *)error
{
    if (self.isFinished) {
        // too late
        return;
    }
    
    @synchronized(self) {
        if (success) {
            self.success = YES;
        } else {
            NSAssert([error isKindOfClass:[NSError class]], @"WTF");
            self.error = error;
            self.success = NO;
        }
        
        
        {
            // NSOperation state machine
            // Manually manage isExecuting and isFinished KVO, because properties would not.
            
            [self willChangeValueForKey:@"isExecuting"];
            [self willChangeValueForKey:@"isFinished"];
            
            _executing = NO;
            _finished = YES;
            
            [self didChangeValueForKey:@"isExecuting"];
            [self didChangeValueForKey:@"isFinished"];
        }
    }
}


@end
