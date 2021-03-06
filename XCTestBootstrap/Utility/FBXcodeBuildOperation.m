/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXcodeBuildOperation.h"

#import <FBControlCore/FBControlCore.h>

static NSString *XcodebuildEnvironmentTargetUDID = @"XCTESTBOOTSTRAP_TARGET_UDID";

@implementation FBXcodeBuildOperation

+ (FBFuture<FBTask *> *)operationWithUDID:(NSString *)udid configuration:(FBTestLaunchConfiguration *)configuration xcodeBuildPath:(NSString *)xcodeBuildPath testRunFilePath:(NSString *)testRunFilePath queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  NSMutableArray<NSString *> *arguments = [[NSMutableArray alloc] init];
  [arguments addObjectsFromArray:@[
    @"test-without-building",
    @"-xctestrun", testRunFilePath,
    @"-destination", [NSString stringWithFormat:@"id=%@", udid],
  ]];

  if (configuration.resultBundlePath) {
    [arguments addObjectsFromArray:@[
      @"-resultBundlePath",
      configuration.resultBundlePath,
    ]];
  }

  for (NSString *test in configuration.testsToRun) {
    [arguments addObject:[NSString stringWithFormat:@"-only-testing:%@", test]];
  }

  for (NSString *test in configuration.testsToSkip) {
    [arguments addObject:[NSString stringWithFormat:@"-skip-testing:%@", test]];
  }

  NSMutableDictionary<NSString *, NSString *> *environment = [NSProcessInfo.processInfo.environment mutableCopy];
  environment[XcodebuildEnvironmentTargetUDID] = udid;

  [logger logFormat:@"Starting test with xcodebuild %@", [arguments componentsJoinedByString:@" "]];
  FBTaskBuilder *builder = [[FBTaskBuilder
    withLaunchPath:xcodeBuildPath arguments:arguments]
    withEnvironment:environment];
  if (logger) {
    [builder withStdOutToLogger:logger];
    [builder withStdErrToLogger:logger];
  }
  return [[builder
    start]
    onQueue:queue map:^(FBTask *task) {
      [logger logFormat:@"Task started %@ for xcodebuild %@", task, [arguments componentsJoinedByString:@" "]];
      return task;
    }];
}

#pragma mark Public

+ (NSDictionary<NSString *, NSDictionary<NSString *, NSObject *> *> *)xctestRunProperties:(FBTestLaunchConfiguration *)testLaunch
{
  return @{
    @"StubBundleId" : @{
      @"TestHostPath" : testLaunch.testHostPath,
      @"TestBundlePath" : testLaunch.testBundlePath,
      @"UseUITargetAppProvidedByTests" : @YES,
      @"IsUITestBundle" : @YES,
      @"CommandLineArguments": testLaunch.applicationLaunchConfiguration.arguments,
      @"EnvironmentVariables": testLaunch.applicationLaunchConfiguration.environment,
      @"TestingEnvironmentVariables": @{
        @"DYLD_FRAMEWORK_PATH": @"__TESTROOT__:__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
        @"DYLD_LIBRARY_PATH": @"__TESTROOT__:__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
      },
    }
  };
}

+ (FBFuture<NSArray<FBProcessInfo *> *> *)terminateAbandonedXcodebuildProcessesForUDID:(NSString *)udid processFetcher:(FBProcessFetcher *)processFetcher queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  NSArray<FBProcessInfo *> *processes = [self activeXcodebuildProcessesForUDID:udid processFetcher:processFetcher];
  if (processes.count == 0) {
    [logger logFormat:@"No processes for %@ to terminate", udid];
    return [FBFuture futureWithResult:@[]];
  }
  [logger logFormat:@"Terminating abandoned xcodebuild processes %@", [FBCollectionInformation oneLineDescriptionFromArray:processes]];
  FBProcessTerminationStrategy *strategy = [FBProcessTerminationStrategy strategyWithProcessFetcher:processFetcher workQueue:queue logger:logger];
  NSMutableArray<FBFuture<FBProcessInfo *> *> *futures = [NSMutableArray array];
  for (FBProcessInfo *process in processes) {
    FBFuture<FBProcessInfo *> *termination = [[strategy killProcess:process] mapReplace:process];
    [futures addObject:termination];
  }
  return [FBFuture futureWithFutures:futures];
}

#pragma mark Private

+ (NSArray<FBProcessInfo *> *)activeXcodebuildProcessesForUDID:(NSString *)udid processFetcher:(FBProcessFetcher *)processFetcher
{
  NSArray<FBProcessInfo *> *xcodebuildProcesses = [processFetcher processesWithProcessName:@"xcodebuild"];
  NSMutableArray<FBProcessInfo *> *relevantProcesses = [NSMutableArray array];
  for (FBProcessInfo *process in xcodebuildProcesses) {
    if (![process.environment[XcodebuildEnvironmentTargetUDID] isEqualToString:udid]) {
      continue;
    }
    [relevantProcesses addObject:process];
  }
  return relevantProcesses;
}

@end
