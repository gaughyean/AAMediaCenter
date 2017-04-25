//
//  AAOutputUnit.h
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "AAAudioUnit.h"
#import "AAConverter.h"

@interface AAOutputUnit : AAAudioUnit

@property (assign, nonatomic, readonly) BOOL isProcessing;

@property (assign, nonatomic) AAMediaCenterOutputFormat outputFormat;

- (id)initWithConverter:(AAConverter *)converter;

- (AudioStreamBasicDescription)format;

- (void)pause;

- (void)resume;

- (void)stop;

- (double)framesToSeconds:(double)framesCount;

- (double)amountPlayed;

- (void)seek:(double)time;

- (void)setVolume:(float)volume;

- (void)setSampleRate:(double)sampleRate;


@end
