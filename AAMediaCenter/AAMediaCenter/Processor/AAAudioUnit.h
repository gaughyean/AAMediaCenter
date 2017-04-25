//
//  AAAudioUnit.h
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import <AudioToolbox/AudioToolbox.h>


// default reading chunk size
#define CHUNK_SIZE 16 * 1024
// deault buffer size
#define BUFFER_SIZE 256 * 1024

typedef enum : NSUInteger {
    AAOutputFormatDefault,
    AAOutputFormat24bit
} AAMediaCenterOutputFormat;

@interface AAAudioUnit : NSObject

- (void)process;

AudioStreamBasicDescription propertiesToASBD(NSDictionary *properties);

@end
