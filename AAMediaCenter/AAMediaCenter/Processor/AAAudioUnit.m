//
//  AAAudioUnit.m
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "AAAudioUnit.h"

@interface AAAudioUnit ()
@property (nonatomic) BOOL isProcessing;
@end

@implementation AAAudioUnit

- (void)process {
    NSString *error = [NSString stringWithFormat:
                       NSLocalizedString(@"You must override %@ in a subclass", nil),
                       NSStringFromSelector(_cmd)];
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:error
                                 userInfo:nil];
}

AudioStreamBasicDescription propertiesToASBD(NSDictionary *properties) {
    AudioStreamBasicDescription asbd;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = 0;
    
    asbd.mSampleRate = [[properties objectForKey:@"sampleRate"] doubleValue];
    
    asbd.mBitsPerChannel = [[properties objectForKey:@"bitsPerSample"] intValue];
    
    asbd.mChannelsPerFrame = [[properties objectForKey:@"channels"] intValue];;
    asbd.mBytesPerFrame = (asbd.mBitsPerChannel/8)*asbd.mChannelsPerFrame;
    
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerPacket = asbd.mBytesPerFrame * asbd.mFramesPerPacket;
    asbd.mReserved = 0;
    
    if ([[properties objectForKey:@"endian"] isEqualToString:@"big"]) {
        asbd.mFormatFlags |= kLinearPCMFormatFlagIsBigEndian;
        asbd.mFormatFlags |= kLinearPCMFormatFlagIsAlignedHigh;
    }
    
    if ([[properties objectForKey:@"unsigned"] boolValue] == NO) {
        asbd.mFormatFlags |= kLinearPCMFormatFlagIsSignedInteger;
    }
    
    return asbd;
}

@end
