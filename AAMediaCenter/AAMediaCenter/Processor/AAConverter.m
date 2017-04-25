//
//  AAConverter.m
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "AAConverter.h"
#import "AAQueues.h"
#import "AAInputUnit.h"
#import "AAOutputUnit.h"

@interface AAConverter () {
    AudioStreamBasicDescription _inputFormat;
    AudioStreamBasicDescription _outputFormat;
    AudioConverterRef _converter;
    void *callbackBuffer;
    void *writeBuf;
}
@end

@implementation AAConverter


- (id)initWithInputUnit:(AAInputUnit *)inputUnit {
    self = [super init];
    if (self) {
        self.convertedData = [NSMutableData data];
        
        self.inputUnit = inputUnit;
        _inputFormat = inputUnit.format;
        
        writeBuf = malloc(CHUNK_SIZE);
    }
    return self;
}

- (void)dealloc {
    free(callbackBuffer);
    free(writeBuf);
    _inputUnit = nil;
    _outputUnit = nil;
}

#pragma mark - public

- (BOOL)setupWithOutputUnit:(AAOutputUnit *)outputUnit {
    self.outputUnit = outputUnit;
    [_outputUnit setSampleRate:_inputFormat.mSampleRate];
  
    _outputFormat = outputUnit.format;
    callbackBuffer = malloc((CHUNK_SIZE/_outputFormat.mBytesPerFrame) * _inputFormat.mBytesPerPacket);
    
    OSStatus stat = AudioConverterNew(&_inputFormat, &_outputFormat, &_converter);
    if (stat != noErr) {
        NSLog(NSLocalizedString(@"Error creating converter", nil));
        return NO;
    }
    
    if (_inputFormat.mChannelsPerFrame == 1) {
        SInt32 channelMap[2] = { 0, 0 };
        
        stat = AudioConverterSetProperty(_converter,
                                         kAudioConverterChannelMap,
                                         sizeof(channelMap),
                                         channelMap);
        if (stat != noErr) {
            NSLog(NSLocalizedString(@"Error mapping channels", nil));
            return NO;
        }
    }
    
    return YES;
}

- (void)process {
    int amountConverted = 0;
    do {
        if (_convertedData.length >= BUFFER_SIZE) {
            break;
        }
        amountConverted = [self convert:writeBuf amount:CHUNK_SIZE];
        dispatch_sync([AAQueues lock_queue], ^{
            [_convertedData appendBytes:writeBuf length:amountConverted];
        });
    } while (amountConverted > 0);
    
    if (!_outputUnit.isProcessing) {
        if (_convertedData.length < BUFFER_SIZE) {
            dispatch_source_merge_data([AAQueues buffering_source], 1);
            return;
        }
        [_outputUnit process];
    }
}

- (void)reinitWithNewInput:(AAInputUnit *)inputUnit withDataFlush:(BOOL)flush {
    if (flush) {
        [self flushBuffer];
    }
    self.inputUnit = inputUnit;
    _inputFormat = inputUnit.format;
    [self setupWithOutputUnit:_outputUnit];
}

- (int)shiftBytes:(NSUInteger)amount buffer:(void *)buffer {
    int bytesToRead = (int)MIN(_convertedData.length, amount);
    
    dispatch_sync([AAQueues lock_queue], ^{
        memcpy(buffer, _convertedData.bytes, bytesToRead);
        [_convertedData replaceBytesInRange:NSMakeRange(0, bytesToRead) withBytes:NULL length:0];
    });
    
    return bytesToRead;
}

- (BOOL)isReadyForBuffering {
    return (_convertedData.length <= 0.5*BUFFER_SIZE && !_inputUnit.isProcessing);
}

- (void)flushBuffer {
    dispatch_sync([AAQueues lock_queue], ^{
        self.convertedData = [NSMutableData data];
    });
}

#pragma mark - private

- (int)convert:(void *)dest amount:(int)amount {
    AudioBufferList ioData;
    UInt32 ioNumberFrames;
    OSStatus err;
    
    ioNumberFrames = amount/_outputFormat.mBytesPerFrame;
    ioData.mBuffers[0].mData = dest;
    ioData.mBuffers[0].mDataByteSize = amount;
    ioData.mBuffers[0].mNumberChannels = _outputFormat.mChannelsPerFrame;
    ioData.mNumberBuffers = 1;
    
    err = AudioConverterFillComplexBuffer(_converter, ACInputProc, (__bridge void * _Nullable)(self), &ioNumberFrames, &ioData, NULL);
    int amountRead = ioData.mBuffers[0].mDataByteSize;
    if (err == kAudioConverterErr_InvalidInputSize)	{
        amountRead += [self convert:dest + amountRead amount:amount - amountRead];
    }
    
    return amountRead;
}

static OSStatus ACInputProc(AudioConverterRef inAudioConverter,
                            UInt32* ioNumberDataPackets, AudioBufferList* ioData,
                            AudioStreamPacketDescription** outDataPacketDescription,
                            void* inUserData) {
    AAConverter *converter = (__bridge AAConverter *)inUserData;
    OSStatus err = noErr;
    int amountToWrite;
    
    amountToWrite = [converter.inputUnit shiftBytes:(*ioNumberDataPackets)*(converter->_inputFormat.mBytesPerPacket)
                                             buffer:converter->callbackBuffer];
    
    if (amountToWrite == 0) {
        ioData->mBuffers[0].mDataByteSize = 0;
        *ioNumberDataPackets = 0;
        
        return 100;
    }
    
    ioData->mBuffers[0].mData = converter->callbackBuffer;
    ioData->mBuffers[0].mDataByteSize = amountToWrite;
    ioData->mBuffers[0].mNumberChannels = (converter->_inputFormat.mChannelsPerFrame);
    ioData->mNumberBuffers = 1;
    
    return err;
}

@end
