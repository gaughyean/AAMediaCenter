//
//  AAConverter.h
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "AAAudioUnit.h"

@class AAOutputUnit, AAInputUnit;
@interface AAConverter : AAAudioUnit

@property (strong, nonatomic) AAInputUnit *inputUnit;

@property (weak, nonatomic) AAOutputUnit *outputUnit;

@property (strong, nonatomic) NSMutableData *convertedData;

- (id)initWithInputUnit:(AAInputUnit *)inputUnit;

- (BOOL)setupWithOutputUnit:(AAOutputUnit *)outputUnit;

- (void)reinitWithNewInput:(AAInputUnit *)inputUnit withDataFlush:(BOOL)flush;

- (int)shiftBytes:(NSUInteger)amount buffer:(void *)buffer;

- (BOOL)isReadyForBuffering;

- (void)flushBuffer;

@end
