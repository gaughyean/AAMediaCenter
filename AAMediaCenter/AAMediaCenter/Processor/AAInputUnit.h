//
//  AAInputUnit.h
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "AAAudioUnit.h"

@interface AAInputUnit : AAAudioUnit

@property (strong, nonatomic) NSProgress * progress;

@property (assign, nonatomic, readonly) BOOL isProcessing;

@property (assign, nonatomic, readonly) BOOL endOfInput;

- (BOOL)openWithUrl:(NSURL *)url andName:(NSString *)fileName andAuthorization:(NSDictionary *)authorizationDict;

- (void)close;

- (AudioStreamBasicDescription)format;

- (NSDictionary *)metadata;

- (double)framesCount;

- (void)seek:(double)time withDataFlush:(BOOL)flush;

- (void)seek:(double)time;

- (int)shiftBytes:(NSUInteger)amount buffer:(void *)buffer;

@end
