//
//  AAInputUnit.m
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "AAInputUnit.h"
#import "AAQueues.h"
#import "AAAgent.h"

@interface AAInputUnit () {
    int bytesPerFrame;
    void *inputBuffer;
    BOOL _shouldSeek;
    long seekFrame;
}

@property (strong, nonatomic) NSMutableData *data;
@property (strong, nonatomic) NSObject<AASource> * source;
@property (strong, nonatomic) id<AADecoder> decoder;
@property (assign, nonatomic) BOOL endOfInput;
@end

@implementation AAInputUnit

- (id)init {
    self = [super init];
    if (self) {
        self.data = [NSMutableData data];
        self.progress = [[NSProgress alloc] initWithParent:nil userInfo:nil];
        inputBuffer = malloc(CHUNK_SIZE);
        _endOfInput = NO;
    }
    return self;
}

- (void)dealloc {
    [self close];
    self.source = nil;
    self.decoder = nil;
    self.data = nil;
    free(inputBuffer);
}

#pragma mark - public

- (BOOL)openWithUrl:(NSURL *)url andName:(NSString *)fileName andAuthorization:(NSDictionary *)authorizationDict{
    self.source = [[AAAgent sharedManager] sourceForURL:url error:nil];
    if (!_source || ![_source open:url withName:fileName andAuthorization:authorizationDict]) return NO;
    self.decoder = [[AAAgent sharedManager] decoderForSource:_source error:nil];
    if (!_decoder || ![_decoder open:_source]) return NO;
    
    if ([_source isKindOfClass:NSClassFromString(@"HTTPSource")]) {
        NSProgress * progress = [_source valueForKey:@"downloadProgress"];
        self.progress = progress;
    }
    int bitsPerSample = [[_decoder.properties objectForKey:@"bitsPerSample"] intValue];
    int channels = [[_decoder.properties objectForKey:@"channels"] intValue];
    bytesPerFrame = (bitsPerSample/8) * channels;
    
    return YES;
}

- (void)close {
    [_decoder close];
}

- (void)process {
    _isProcessing = YES;
    int amountInBuffer = 0;
    int framesRead = 0;
    
    do {
        if (_data.length >= BUFFER_SIZE) {
            framesRead = 1;
            break;
        }
        
        if (_shouldSeek) {
            [_decoder seek:seekFrame];
            _shouldSeek = NO;
        }
        int framesToRead = 0;
        if (bytesPerFrame > 0) {
            framesToRead = CHUNK_SIZE/bytesPerFrame;
        }
        framesRead = [_decoder readAudio:inputBuffer frames:framesToRead];
        amountInBuffer = (framesRead * bytesPerFrame);
        
        dispatch_sync([AAQueues lock_queue], ^{
            [_data appendBytes:inputBuffer length:amountInBuffer];
        });
    } while (framesRead > 0);
    
    if (framesRead <= 0) {
        [self setEndOfInput:YES];
    }
    
    _isProcessing = NO;
}

- (double)framesCount {
    NSNumber *frames = [_decoder.properties objectForKey:@"totalFrames"];
    return [frames doubleValue];
}

- (void)seek:(double)time withDataFlush:(BOOL)flush {
    if (flush) {
        dispatch_sync([AAQueues lock_queue], ^{ self.data = [NSMutableData data]; });
    }
    seekFrame = time * [[_decoder.properties objectForKey:@"sampleRate"] floatValue];
    _shouldSeek = YES;
}

- (void)seek:(double)time {
    [self seek:time withDataFlush:NO];
}

- (AudioStreamBasicDescription)format {
    return propertiesToASBD(_decoder.properties);
}

- (NSDictionary *)metadata {
    return [_decoder metadata];
}

- (int)shiftBytes:(NSUInteger)amount buffer:(void *)buffer {
    int bytesToRead = (int)MIN(amount, _data.length);
    
    dispatch_sync([AAQueues lock_queue], ^{
        memcpy(buffer, _data.bytes, bytesToRead);
        [_data replaceBytesInRange:NSMakeRange(0, bytesToRead) withBytes:NULL length:0];
    });
    
    return bytesToRead;
}

#pragma mark - private

@end
