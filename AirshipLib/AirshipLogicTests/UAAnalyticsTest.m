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

#import "UAConfig.h"
#import "UAAnalytics+Internal.h"
#import "UAHTTPConnection+Internal.h"
#import "UAAnalyticsTest.h"
#import <OCMock/OCMock.h>
#import <OCMock/OCMConstraint.h>
#import "UAKeychainUtils.h"

@interface UAAnalyticsTest()
@property(nonatomic, retain) UAAnalytics *analytics;
@property(nonatomic, retain) id mockedKeychainClass;
@property(nonatomic, retain) id mockLocaleClass;
@property(nonatomic, retain) id mockTimeZoneClass;
@end

@implementation UAAnalyticsTest

- (void)dealloc {
    self.mockedKeychainClass = nil;
    self.mockLocaleClass = nil;
    self.mockTimeZoneClass = nil;
    self.analytics = nil;

    [super dealloc];
}

- (void)setUp {
    [super setUp];
    
    self.mockedKeychainClass = [OCMockObject mockForClass:[UAKeychainUtils class]];
    [[[self.mockedKeychainClass stub] andReturn:@"some-device-id"] getDeviceID];

    self.mockLocaleClass = [OCMockObject mockForClass:[NSLocale class]];
    self.mockTimeZoneClass = [OCMockObject mockForClass:[NSTimeZone class]];

    UAConfig *config = [[[UAConfig alloc] init] autorelease];
    self.analytics = [[[UAAnalytics alloc] initWithConfig:config] autorelease];
 }

- (void)tearDown {
    [super tearDown];

    [self.mockedKeychainClass stopMocking];
    [self.mockLocaleClass stopMocking];
    [self.mockTimeZoneClass stopMocking];
}

- (void)testRequestTimezoneHeader {
    [self setTimeZone:@"America/New_York"];
    
    NSDictionary *headers = [self.analytics analyticsRequest].headers;
    
    STAssertEqualObjects([headers objectForKey:@"X-UA-Timezone"], @"America/New_York", @"Wrong timezone in event headers");
}

- (void)testRequestLocaleHeadersFullCode {
    [self setCurrentLocale:@"en_US_POSIX"];

    NSDictionary *headers = [self.analytics analyticsRequest].headers;
    
    STAssertEqualObjects([headers objectForKey:@"X-UA-Locale-Language"], @"en", @"Wrong local language code in event headers");
    STAssertEqualObjects([headers objectForKey:@"X-UA-Locale-Country"],  @"US", @"Wrong local country code in event headers");
    STAssertEqualObjects([headers objectForKey:@"X-UA-Locale-Variant"],  @"POSIX", @"Wrong local variant in event headers");
}

- (void)testAnalyticRequestLocationHeadersPartialCode {
    [self setCurrentLocale:@"de"];
    
    NSDictionary *headers = [self.analytics analyticsRequest].headers;
    
    STAssertEqualObjects([headers objectForKey:@"X-UA-Locale-Language"], @"de", @"Wrong local language code in event headers");
    STAssertNil([headers objectForKey:@"X-UA-Locale-Country"], @"Wrong local country code in event headers");
    STAssertNil([headers objectForKey:@"X-UA-Locale-Variant"], @"Wrong local variant in event headers");
}

- (void)restoreSavedUploadEventSettingsEmptyUserDefaults {
    // Clear the settings from the standard user defaults
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMaxTotalDBSizeUserDefaultsKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMaxBatchSizeUserDefaultsKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMaxWaitUserDefaultsKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMinBatchIntervalUserDefaultsKey];

    [self.analytics restoreSavedUploadEventSettings];

    // Should try to set the values to 0 and the setter should normalize them to the min values.
    STAssertEquals(self.analytics.maxTotalDBSize, kMinTotalDBSizeBytes, @"maxTotalDBSize is setting an incorrect value when trying to set the value to 0");
    STAssertEquals(self.analytics.maxBatchSize, kMinBatchSizeBytes, @"maxBatchSize is setting an incorrect value when trying to set the value to 0");
    STAssertEquals(self.analytics.maxWait, kMinWaitSeconds, @"maxWait is setting an incorrect value when trying to set the value to 0");
    STAssertEquals(self.analytics.minBatchInterval, kMinBatchIntervalSeconds, @"minBatchInterval is setting an incorrect value when trying to set the value to 0");
}

- (void)restoreSavedUploadEventSettingsExistingData {
    // Set valid date for the defaults
    [[NSUserDefaults standardUserDefaults] setInteger:kMinTotalDBSizeBytes + 5 forKey:kMaxTotalDBSizeUserDefaultsKey];
    [[NSUserDefaults standardUserDefaults] setInteger:kMinBatchSizeBytes + 5 forKey:kMaxBatchSizeUserDefaultsKey];
    [[NSUserDefaults standardUserDefaults] setInteger:kMinWaitSeconds + 5 forKey:kMaxWaitUserDefaultsKey];
    [[NSUserDefaults standardUserDefaults] setInteger:kMinBatchIntervalSeconds + 5 forKey:kMinBatchIntervalUserDefaultsKey];

    [self.analytics restoreSavedUploadEventSettings];

    // Should try to set the values to 0 and the setter should normalize them to the min values.
    STAssertEquals(self.analytics.maxTotalDBSize, kMinTotalDBSizeBytes + 5, @"maxTotalDBSize value did not restore properly");
    STAssertEquals(self.analytics.maxBatchSize, kMinBatchSizeBytes + 5, @"maxBatchSize value did not restore properly");
    STAssertEquals(self.analytics.maxWait, kMinWaitSeconds + 5, @"maxWait value did not restore properly");
    STAssertEquals(self.analytics.minBatchInterval, kMinBatchIntervalSeconds + 5, @"minBatchInterval value did not restore properly");
}

- (void)testSaveUploadEventSettings {
    // Clear the settings from the standard user defaults
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMaxTotalDBSizeUserDefaultsKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMaxBatchSizeUserDefaultsKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMaxWaitUserDefaultsKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMinBatchIntervalUserDefaultsKey];

    [self.analytics saveUploadEventSettings];

    // Make sure all the expected settings are set to the current analytics properties
    STAssertEquals(self.analytics.maxTotalDBSize, [[NSUserDefaults standardUserDefaults] integerForKey:kMaxTotalDBSizeUserDefaultsKey], @"maxTotalDBSize failed to save to user defaults");
    STAssertEquals(self.analytics.maxBatchSize, [[NSUserDefaults standardUserDefaults] integerForKey:kMaxBatchSizeUserDefaultsKey], @"maxBatchSize failed to save to user defaults");
    STAssertEquals(self.analytics.maxWait, [[NSUserDefaults standardUserDefaults] integerForKey:kMaxWaitUserDefaultsKey], @"maxWait is setting failed to save to user defaults");
    STAssertEquals(self.analytics.minBatchInterval, [[NSUserDefaults standardUserDefaults] integerForKey:kMinBatchIntervalUserDefaultsKey], @"minBatchInterval failed to save to user defaults");
}

- (void)testUpdateAnalyticsParameters {
    // Create headers with response values for the event header settings
    NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithCapacity:4];
    [headers setValue:[NSNumber numberWithInt:kMinTotalDBSizeBytes + 1] forKey:@"X-UA-Max-Total"];
    [headers setValue:[NSNumber numberWithInt:kMinBatchSizeBytes + 1] forKey:@"X-UA-Max-Batch"];
    [headers setValue:[NSNumber numberWithInt:kMinWaitSeconds + 1] forKey:@"X-UA-Max-Wait"];
    [headers setValue:[NSNumber numberWithInt:kMinBatchIntervalSeconds + 1] forKey:@"X-UA-Min-Batch-Interval"];

    id mockResponse = [OCMockObject niceMockForClass:[NSHTTPURLResponse class]];
    [[[mockResponse stub] andReturn:headers] allHeaderFields];
    
    [self.analytics updateAnalyticsParametersWithHeaderValues:mockResponse];

    // Make sure all the expected settings are set to the current analytics properties
    STAssertEquals(self.analytics.maxTotalDBSize, [[NSUserDefaults standardUserDefaults] integerForKey:kMaxTotalDBSizeUserDefaultsKey], @"maxTotalDBSize failed to save update its value from response header");
    STAssertEquals(self.analytics.maxBatchSize, [[NSUserDefaults standardUserDefaults] integerForKey:kMaxBatchSizeUserDefaultsKey], @"maxBatchSize failed to save update its value from response header");
    STAssertEquals(self.analytics.maxWait, [[NSUserDefaults standardUserDefaults] integerForKey:kMaxWaitUserDefaultsKey], @"maxWait is setting failed to save update its value from response header");
    STAssertEquals(self.analytics.minBatchInterval, [[NSUserDefaults standardUserDefaults] integerForKey:kMinBatchIntervalUserDefaultsKey], @"minBatchInterval failed to save update its value from response header");
}

- (void)testSetMaxTotalDBSize {
    // Set a value higher then the max, should set to the max
    self.analytics.maxTotalDBSize = kMaxTotalDBSizeBytes + 1;
    STAssertEquals(self.analytics.maxTotalDBSize, kMaxTotalDBSizeBytes, @"maxTotalDBSize is able to be set above the max value");

    // Set a value lower then then min, should set to the min
    self.analytics.maxTotalDBSize = kMinTotalDBSizeBytes - 1;
    STAssertEquals(self.analytics.maxTotalDBSize, kMinTotalDBSizeBytes, @"maxTotalDBSize is able to be set below the min value");

    // Set a value between
    self.analytics.maxTotalDBSize = kMinTotalDBSizeBytes + 1;
    STAssertEquals(self.analytics.maxTotalDBSize, kMinTotalDBSizeBytes + 1, @"maxTotalDBSize is unable to be set to a valid value");
}

- (void)testSetMaxBatchSize {
    // Set a value higher then the max, should set to the max
    self.analytics.maxBatchSize = kMaxBatchSizeBytes + 1;
    STAssertEquals(self.analytics.maxBatchSize, kMaxBatchSizeBytes, @"maxBatchSize is able to be set above the max value");

    // Set a value lower then then min, should set to the min
    self.analytics.maxBatchSize = kMinBatchSizeBytes - 1;
    STAssertEquals(self.analytics.maxBatchSize, kMinBatchSizeBytes, @"maxBatchSize is able to be set below the min value");

    // Set a value between
    self.analytics.maxBatchSize = kMinBatchSizeBytes + 1;
    STAssertEquals(self.analytics.maxBatchSize, kMinBatchSizeBytes + 1, @"maxBatchSize is unable to be set to a valid value");
}

- (void)testSetMaxWait {
    // Set a value higher then the max, should set to the max
    self.analytics.maxWait = kMaxWaitSeconds + 1;
    STAssertEquals(self.analytics.maxWait, kMaxWaitSeconds, @"maxWait is able to be set above the max value");

    // Set a value lower then then min, should set to the min
    self.analytics.maxWait = kMinWaitSeconds - 1;
    STAssertEquals(self.analytics.maxWait, kMinWaitSeconds, @"maxWait is able to be set below the min value");

    // Set a value between
    self.analytics.maxWait = kMinWaitSeconds + 1;
    STAssertEquals(self.analytics.maxWait, kMinWaitSeconds + 1, @"maxWait is unable to be set to a valid value");
}

- (void)testSetMinBatchInterval {
    // Set a value higher then the max, should set to the max
    self.analytics.minBatchInterval = kMaxBatchIntervalSeconds + 1;
    STAssertEquals(self.analytics.minBatchInterval, kMaxBatchIntervalSeconds, @"minBatchInterval is able to be set above the max value");

    // Set a value lower then then min, should set to the min
    self.analytics.minBatchInterval = kMinBatchIntervalSeconds - 1;
    STAssertEquals(self.analytics.minBatchInterval, kMinBatchIntervalSeconds, @"minBatchInterval is able to be set below the min value");

    // Set a value between
    self.analytics.minBatchInterval = kMinBatchIntervalSeconds + 1;
    STAssertEquals(self.analytics.minBatchInterval, kMinBatchIntervalSeconds + 1, @"minBatchInterval is unable to be set to a valid value");
}

- (void)testIsEventValid {
    // Create a valid dictionary
    NSMutableDictionary *event = [self createValidEvent];
    STAssertTrue([self.analytics isEventValid:event], @"isEventValid should be true for a valid event");
}

- (void)testIsEventValidEmptyDictionary {
    NSMutableDictionary *invalidEventData = [NSMutableDictionary dictionary];
    STAssertFalse([self.analytics isEventValid:invalidEventData], @"isEventValid should be false for an empty dictionary");
}

- (void)testIsEventValidInvalidValues {
    NSArray *eventKeysToTest = @[@"event_id", @"session_id", @"type", @"time", @"event_size", @"data"];

    for (NSString *key in eventKeysToTest) {
        // Create a valid event
        NSMutableDictionary *event = [self createValidEvent];

        // Make the value invalid - empty array is an invalid type for all the fields
        [event setValue:@[] forKey:key];
        STAssertFalse([self.analytics isEventValid:event], [NSString stringWithFormat:@"isEventValid did not detect invalid %@", key]);

        // Remove the value
        [event setValue:NULL forKey:key];
        STAssertFalse([self.analytics isEventValid:event], [NSString stringWithFormat:@"isEventValid did not detect empty %@", key]);
    }
}

- (void)setCurrentLocale:(NSString*)localeCode {
    NSLocale *locale = [[[NSLocale alloc] initWithLocaleIdentifier:localeCode] autorelease];

    [[[self.mockLocaleClass stub] andReturn:locale] currentLocale];
}

- (void)setTimeZone:(NSString*)name {
    NSTimeZone *timeZone = [[[NSTimeZone alloc] initWithName:name] autorelease];
    
    [[[self.mockTimeZoneClass stub] andReturn:timeZone] defaultTimeZone];
}

-(NSMutableDictionary *) createValidEvent {
    return [[@{@"event_id": @"some-event-id",
             @"data": [NSMutableData dataWithCapacity:1],
             @"session_id": @"some-session-id",
             @"type": @"base",
             @"time":[NSString stringWithFormat:@"%f",[[NSDate date] timeIntervalSince1970]],
             @"event_size":@"40"} mutableCopy] autorelease];
}

@end
