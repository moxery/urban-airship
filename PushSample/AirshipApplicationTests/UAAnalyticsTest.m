/*
 Copyright 2009-2013 Urban Airship Inc. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 
 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 2. Redistributions in binaryform must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided withthe distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <OCMock/OCMock.h>
#import <OCMock/OCMConstraint.h>
#import <SenTestingKit/SenTestingKit.h>

#import "UAConfig.h"
#import "UAAnalyticsDBManager.h"
#import "UAEvent.h"
#import "UALocationEvent.h"
#import "UAAnalytics+Internal.h"
#import "UAirship+Internal.h"
#import "UALocationTestUtils.h"

/* This class involves lots of async calls to the web
 Care should be taken to mock out responses and calls, race conditions
 can cause tests to fail, these conditions would not occur in normal app 
 usage */


@interface UAAnalyticsTest : SenTestCase {
    UAAnalytics *analytics;
}

@end

@implementation UAAnalyticsTest


- (void)setUp {
    UAConfig *config = [[[UAConfig alloc] init] autorelease];
    analytics = [[UAAnalytics alloc] initWithConfig:config];

    [UAirship shared].analytics = analytics;
}

- (void)tearDown {
    RELEASE(analytics);
}

- (void)testLastSendTimeGetSetMethods {
    // setup a date with a random number to make sure values aren't stale
    NSDate *testDate = [NSDate dateWithTimeIntervalSinceNow:arc4random() % 9999];
    [analytics setLastSendTime:testDate];
    NSDate* analyticsDateFromDefaults = [analytics lastSendTime];
    NSTimeInterval timeBetweenDates = [testDate timeIntervalSinceDate:analyticsDateFromDefaults];
    // Date formatting for string representation truncates the date value to the nearest second
    // hence, expect to be off by a second
    STAssertEqualsWithAccuracy(timeBetweenDates, (NSTimeInterval)0, 1, nil);
}

- (void)testHandleNotification {
    id mockAnalytics = [OCMockObject partialMockForObject:analytics];
    __block id arg = nil;
    void (^getSingleArg)(NSInvocation*) = ^(NSInvocation *invocation){
        [invocation getArgument:&arg atIndex:2];
    };
    [[[mockAnalytics stub] andDo:getSingleArg] addEvent:OCMOCK_ANY];
    [analytics handleNotification:[NSDictionary dictionaryWithObject:@"stuff" forKey:@"key"] inApplicationState:UIApplicationStateActive];
    STAssertNotNil(arg, nil);
    STAssertTrue([arg isKindOfClass:[UAEventPushReceived class]], nil);    
}

//// Refactor this next time it's changed

/*
 * Ensure that an app entering the foreground resets state and sets
 * the flag that will insert a flag on didBecomeActive.
 */
- (void)testEnterForeground {
    id mockAnalytics = [OCMockObject partialMockForObject:analytics];
    [[mockAnalytics expect] invalidateBackgroundTask];
    
    //set up event capture
    __block id arg = nil;
    void (^getSingleArg)(NSInvocation *) = ^(NSInvocation *invocation){
        [invocation getArgument:&arg atIndex:2];
    };
    [[[mockAnalytics stub] andDo:getSingleArg] addEvent:OCMOCK_ANY];
    
    [analytics enterForeground];
    
    STAssertTrue(analytics.isEnteringForeground, @"`enterForeground` should set `isEnteringForeground_` to YES");
    STAssertNil(arg, @"`enterForeground` should not insert an event");
    
    [mockAnalytics verify];
}

- (void)testDidBecomeActiveAfterForeground {
    id mockAnalytics = [OCMockObject partialMockForObject:analytics];
    [[mockAnalytics expect] refreshSessionWhenNetworkChanged];
    [[mockAnalytics expect] refreshSessionWhenActive];
    
    __block int foregroundCount = 0;
    __block int activeCount = 0;
    __block int eventCount = 0;
    __block id arg = nil;
    void (^getSingleArg)(NSInvocation*) = ^(NSInvocation *invocation){
        
        [invocation getArgument:&arg atIndex:2];
        if ([arg isKindOfClass:[UAEventAppActive class]]) {
            activeCount++;
        }
        
        if ([arg isKindOfClass:[UAEventAppForeground class]]) {
            foregroundCount++;
        }
        
        eventCount++;
        
    };
    [[[mockAnalytics stub] andDo:getSingleArg] addEvent:OCMOCK_ANY];
    
    analytics.isEnteringForeground = YES;
    [analytics didBecomeActive];
    
    STAssertFalse(analytics.isEnteringForeground, @"`didBecomeActive` should set `isEnteringForeground_` to NO");
    
    STAssertTrue([arg isKindOfClass:[UAEventAppActive class]] , @"didBecomeActive should fire UAEventAppActive");
    
    STAssertEquals(foregroundCount, 1, @"One foreground event inserted.");
    STAssertEquals(activeCount, 1, @"One active event inserted.");
    STAssertEquals(eventCount, 2, @"Two total events inserted.");
    
    [mockAnalytics verify];
}

/*
 * This is a larger test, but the intent is to test the full foreground from notification flow
 */
- (void)testForegroundFromPush {
    //We have to mock the singleton analytics rather than the analytics ivar
    //so we can test analytics insert end to end - the event generation code
    //uses the singleton version, so if we want to pull the right session into
    //an event, we have to use that one.
    id mockAnalytics = [OCMockObject partialMockForObject:[UAirship shared].analytics];
    
    NSString *incomingPushId = @"the_push_id";
    
    //count events and grab the push ID
    __block int foregroundCount = 0;
    __block int activeCount = 0;
    __block int eventCount = 0;
    __block NSString *eventPushId = nil;
    void (^getSingleArg)(NSInvocation *) = ^(NSInvocation *invocation){
        
        id arg = nil;
        [invocation getArgument:&arg atIndex:2];
        if ([arg isKindOfClass:[UAEventAppActive class]]) {
            activeCount++;
        }
        
        if ([arg isKindOfClass:[UAEventAppForeground class]]) {
            foregroundCount++;
            
            // save the push id for later
            UAEventAppForeground *fgEvent = (UAEventAppForeground *)arg;
            eventPushId = [fgEvent.data objectForKey:@"push_id"];
        }
        
        eventCount++;
        
    };
    [[[mockAnalytics stub] andDo:getSingleArg] addEvent:OCMOCK_ANY];
    
    // We're in the background
    id mockApplication = [OCMockObject partialMockForObject:[UIApplication sharedApplication]];
    UIApplicationState state = UIApplicationStateBackground;
    [[[mockApplication stub] andReturnValue:OCMOCK_VALUE(state)] applicationState];
    
    [[UAirship shared].analytics enterForeground];// fired from NSNotificationCenter
    
    //mock a notification - the "_" id is all that matters - we don't need an aps payload
    //this value is passed in through the app delegate's didReceiveRemoteNotification method
    [[UAirship shared].analytics handleNotification:[NSDictionary dictionaryWithObject:incomingPushId forKey:@"_"] inApplicationState:UIApplicationStateInactive];
    
    //now the app is active, according to NSNotificationCenter
    [[UAirship shared].analytics didBecomeActive];
    
    STAssertFalse([UAirship shared].analytics.isEnteringForeground, @"`didBecomeActive` should set `isEnteringForeground_` to NO");
        
    STAssertEquals(foregroundCount, 1, @"One foreground event should be inserted.");
    STAssertEquals(activeCount, 1, @"One active event should be inserted.");
    STAssertEquals(eventCount, 2, @"Two total events should be inserted.");
    STAssertTrue([incomingPushId isEqualToString:eventPushId], @"The incoming push ID is not included in the event payload.");
    
    [mockAnalytics verify];
}


- (void)testEnterBackground {
    id mockAnalytics = [OCMockObject partialMockForObject:analytics];
    [[mockAnalytics expect] send];
    __block id arg = nil;
    void (^getSingleArg)(NSInvocation*) = ^(NSInvocation *invocation){
        [invocation getArgument:&arg atIndex:2];
    };
    [[[mockAnalytics expect] andDo:getSingleArg] addEvent:OCMOCK_ANY];
    [analytics enterBackground];
    STAssertTrue([arg isKindOfClass:[UAEventAppBackground class]], @"Enter background should fire UAEventAppBackground");
    STAssertTrue(analytics.sendBackgroundTask != UIBackgroundTaskInvalid, @"A background task should exist");
    [mockAnalytics verify];
}

- (void)testInvalidateBackgroundTask {
    __block UIBackgroundTaskIdentifier identifier;
    identifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:identifier];
        identifier = UIBackgroundTaskInvalid;
    }];
    analytics.sendBackgroundTask = identifier;
    [analytics invalidateBackgroundTask];
    STAssertTrue(analytics.sendBackgroundTask == UIBackgroundTaskInvalid, nil);
}

- (void)testDidBecomeActive {
    id mockAnalytics = [OCMockObject partialMockForObject:analytics];
    
    //set up event capture
    __block id arg = nil;
    void (^getSingleArg)(NSInvocation*) = ^(NSInvocation *invocation){
        [invocation getArgument:&arg atIndex:2];
    };
    [[[mockAnalytics stub] andDo:getSingleArg] addEvent:OCMOCK_ANY];
    
    [analytics didBecomeActive];
    
    STAssertFalse(analytics.isEnteringForeground, @"`enterForeground` should set `isEnteringForeground_` to NO");
    
    STAssertTrue([arg isKindOfClass:[UAEventAppActive class]] , @"didBecomeActive should fire UAEventAppActive");
}

- (void)testWillResignActive {
    id mockAnalytics = [OCMockObject partialMockForObject:analytics];
    __block id arg = nil;
    void (^getSingleArg)(NSInvocation*) = ^(NSInvocation *invocation){
        [invocation getArgument:&arg atIndex:2];
    };
    [[[mockAnalytics stub] andDo:getSingleArg] addEvent:OCMOCK_ANY];
    [analytics willResignActive];
    STAssertTrue([arg isKindOfClass:[UAEventAppInactive class]], @"willResignActive should fire UAEventAppInactive");
}

- (void)testAddEvent {
    // Should add an event in the foreground
    UAEventAppActive *event = [[[UAEventAppActive alloc] init] autorelease];
    id mockDBManager = [OCMockObject partialMockForObject:[UAAnalyticsDBManager shared]];
    [[mockDBManager expect] addEvent:event withSession:analytics.session];
    analytics.oldestEventTime = 0;
    [analytics addEvent:event];
    [mockDBManager verify];

    // Should not send an event in the background when not location event
    STAssertTrue(analytics.oldestEventTime == [event.time doubleValue], nil);
    [[mockDBManager expect] addEvent:event withSession:analytics.session];
    id mockApplication = [OCMockObject partialMockForObject:[UIApplication sharedApplication]];
    UIApplicationState state = UIApplicationStateBackground;
    [[[mockApplication stub] andReturnValue:OCMOCK_VALUE(state)] applicationState];
    analytics.sendBackgroundTask = UIBackgroundTaskInvalid;
    id mockAnalytics = [OCMockObject partialMockForObject:analytics];
    [[mockAnalytics reject] send];
    [analytics addEvent:event];
    [mockAnalytics verify];

    // Should send a location event in the background
    mockAnalytics = [OCMockObject partialMockForObject:analytics];
    UALocationEvent *locationEvent = [[[UALocationEvent alloc] initWithLocationContext:nil] autorelease];
    [[mockDBManager expect] addEvent:locationEvent withSession:analytics.session];
    [[mockAnalytics expect] send];
    [analytics addEvent:locationEvent];
    [mockAnalytics verify];
}

- (void)testShouldSendAnalyticsCore {
    analytics.config.analyticsEnabled = NO;
    STAssertFalse([analytics shouldSendAnalytics], nil);
    analytics.config.analyticsEnabled = YES;
    id mockDBManger = [OCMockObject partialMockForObject:[UAAnalyticsDBManager shared]];
    NSInteger zero = 0;
    [[[mockDBManger stub] andReturnValue:OCMOCK_VALUE(zero)] eventCount];
    STAssertFalse([analytics shouldSendAnalytics], nil);
    analytics.databaseSize = 0;
    mockDBManger = [OCMockObject partialMockForObject:[UAAnalyticsDBManager shared]];
    NSInteger five = 5;
    [[[mockDBManger stub] andReturnValue:OCMOCK_VALUE(five)] eventCount];
    STAssertFalse([analytics shouldSendAnalytics], nil);
}

- (void)testShouldSendAnalyticsBackgroundLogic {
    analytics.config.analyticsURL = @"cats";
    id mockDBManger = [OCMockObject partialMockForObject:[UAAnalyticsDBManager shared]];
    mockDBManger = [OCMockObject partialMockForObject:[UAAnalyticsDBManager shared]];
    NSInteger five = 5;
    [[[mockDBManger stub] andReturnValue:OCMOCK_VALUE(five)] eventCount];
    id mockApplication = [OCMockObject partialMockForObject:[UIApplication sharedApplication]];
    UIApplicationState state = UIApplicationStateBackground;
    [[[mockApplication stub] andReturnValue:OCMOCK_VALUE(state)] applicationState];
    analytics.sendBackgroundTask = 9;
    STAssertTrue([analytics shouldSendAnalytics], nil);
    analytics.sendBackgroundTask = UIBackgroundTaskInvalid;
    analytics.lastSendTime = [NSDate distantPast];
    STAssertTrue([analytics shouldSendAnalytics], nil);
    analytics.lastSendTime = [NSDate date];
    STAssertFalse([analytics shouldSendAnalytics], nil);
    mockApplication = [OCMockObject partialMockForObject:[UIApplication sharedApplication]];
    state = UIApplicationStateActive;
    [[[mockApplication stub] andReturnValue:OCMOCK_VALUE(state)] applicationState];
    STAssertTrue([analytics shouldSendAnalytics], nil);
}

- (void)testSend {
    id mockAnalytics = [OCMockObject partialMockForObject:analytics];
    id mockQueue = [OCMockObject niceMockForClass:[NSOperationQueue class]];
    analytics.queue = mockQueue;
    [[mockQueue expect] addOperation:[OCMArg any]];
    BOOL yes = YES;
    [[[mockAnalytics stub] andReturnValue:OCMOCK_VALUE(yes)] shouldSendAnalytics];
    NSArray* data = [NSArray arrayWithObjects:@"one", @"two", nil];
    [[[mockAnalytics stub] andReturn:data] prepareEventsForUpload];
    [analytics send];
    [mockQueue verify];
}

// This test is not comprehensive for this method, as the method needs refactoring.
- (void)testPrepareEventsForUpload {
    UAEventAppForeground *appEvent = [[[UAEventAppForeground alloc] initWithContext:nil] autorelease];
    // If the events database is empty, everything crashes
    STAssertNotNil(appEvent, nil);
    // Remember, the NSUserPreferences are in an unknown state in every test, so reset
    // preferences if the methods under test rely on them
    analytics.maxTotalDBSize = kMaxTotalDBSizeBytes;
    analytics.maxBatchSize = kMaxBatchSizeBytes;
    [analytics addEvent:appEvent];
    NSArray* events = [analytics prepareEventsForUpload];
    STAssertTrue([events isKindOfClass:[NSArray class]], nil);
    STAssertTrue([events count] > 0, nil);
}

- (void)testAnalyticsIsThreadSafe {
    UAAnalytics *airshipAnalytics = [[UAirship shared] analytics];
    dispatch_queue_t testQueue = dispatch_queue_create("com.urbanairship.analyticsThreadsafeTest", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t testGroup = dispatch_group_create();
    dispatch_group_async(testGroup, testQueue, ^{
        UALocationEvent *event = [UALocationEvent locationEventWithLocation:[UALocationTestUtils testLocationPDX] locationManager:nil andUpdateType:@"testUpdate"];
        int random = 0;
        for (int i = 0; i < 10; i++) {
            random = arc4random() % 2;
            if (random == 0) {
                dispatch_group_async(testGroup, dispatch_get_main_queue(), ^{
                    UALOG(@"Added test event on main thread");
                    [airshipAnalytics addEvent:event];
                });
                continue;
            }
            UALOG(@"Added test event on a background thread");
            [airshipAnalytics addEvent:event];
        }
    });
    dispatch_group_wait(testGroup, 5 * NSEC_PER_SEC);
    dispatch_release(testGroup);
    dispatch_release(testQueue);
    UAAnalyticsDBManager *analyticsDb = [UAAnalyticsDBManager shared];
    NSArray *bunchOevents = [analyticsDb getEvents:100];
    __block BOOL testFail = YES;
    [bunchOevents enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        __block BOOL isNull = NO;
        if ([obj isKindOfClass:[NSDictionary class]]) {
            [(NSDictionary*)obj enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                if (key == NULL || obj == NULL) {
                    isNull = YES;
                    *stop = YES;
                }
            }];
        }
        if (isNull == YES) {
            testFail = YES;
            *stop = YES;
        }
        else {
            testFail = NO;
        }
    }];
    STAssertFalse(testFail, @"NULL value in UAAnalyticsDB, check threading issues");
}


@end
