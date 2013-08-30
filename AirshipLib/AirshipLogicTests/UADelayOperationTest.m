
#import "UADelayOperationTest.h"
#import "UADelayOperation.h"

@interface UADelayOperationTest()
@property(nonatomic, retain) NSOperationQueue *queue;
@end

@implementation UADelayOperationTest

- (void)setUp {
    [super setUp];
    self.queue = [[[NSOperationQueue alloc] init] autorelease];
    self.queue.maxConcurrentOperationCount = 1;
}

- (void)testDelay {
    __block BOOL finished = NO;
    [self.queue addOperation:[UADelayOperation operationWithDelayInSeconds:1]];
    [self.queue addOperation:[NSBlockOperation blockOperationWithBlock:^{
        finished = YES;
    }]];

    STAssertFalse(finished, @"flag should not be set until after delay completes");
    //give it enough time to complete
    sleep(2);
    STAssertTrue(finished, @"flag should be set once delay completes");
}

- (void)testCancel {
    __block BOOL finished = NO;
    //add a long running delay
    [self.queue addOperation:[UADelayOperation operationWithDelayInSeconds:20]];
    [self.queue addOperation:[NSBlockOperation blockOperationWithBlock:^{
        finished = YES;
    }]];

    //give it some time to spin things up
    sleep(1);

    STAssertTrue(self.queue.operationCount == 2, @"we should have two operations running");
    [self.queue cancelAllOperations];

    //give it some time to wind things down
    sleep(1);

    STAssertFalse(finished, @"flag should still be unset");
    STAssertTrue(self.queue.operationCount == 0, @"operation count should be zero");
}

- (void)tearDown {
    self.queue = nil;
    [super tearDown];
}


@end
