//
//  AAPlayer.m
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "AAPlayer.h"
#import "AAQueues.h"
#import "AAInputUnit.h"
#import "AAOutputUnit.h"
#import "AAConverter.h"
#import "AAProtocols.h"

@interface AAPlayer ()
@property (strong, nonatomic) AAInputUnit *input;
@property (strong, nonatomic) AAOutputUnit *output;
@property (strong, nonatomic) AAConverter *converter;
@property (assign, nonatomic) AAPlayerState currentState;
@property (strong, nonatomic) NSError *currentError;
@property (strong, nonatomic) NSProgress * cacheProgress;
@end

@implementation AAPlayer

- (id)init {
    self = [super init];
    if (self) {
        self.volume = 100.0f;
        [self setup];
        [self setCurrentState:AAPlayerStateStopped];
        [self addObserver:self forKeyPath:@"currentState"
                  options:NSKeyValueObservingOptionNew
                  context:nil];
    }
    return self;
}

- (void)dealloc {
    [self removeObserver:self forKeyPath:@"currentState"];
}

#pragma mark - public

- (void)playUrl:(NSURL *)url withOutputUnitClass:(Class)outputUnitClass andName:(NSString *)fileName andAuthorization:(NSDictionary *)authorizationDict{
    if (!outputUnitClass || ![outputUnitClass isSubclassOfClass:[AAOutputUnit class]]) {
        
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:NSLocalizedString(@"Output unit should be subclass of AAOutputUnit", nil)
                                     userInfo:nil];
    }
    
    if (self.currentState == AAPlayerStatePlaying) [self stop];
    dispatch_async([AAQueues processing_queue], ^{
        self.currentError = nil;
        NSURL * actualUrl = nil;
        NSURL * cachedUrl = nil;
        if (![[url scheme] isEqualToString:@"file"]) {
            cachedUrl = [self checkIfOnlineMusicHasBeenCachedWithName:fileName];
        }
        if (cachedUrl) {
            actualUrl = cachedUrl;
        }else{
            actualUrl = url;
        }
        AAInputUnit *input = [[AAInputUnit alloc] init];
        self.input = input;
        
        [_input addObserver:self forKeyPath:@"endOfInput" options:NSKeyValueObservingOptionNew context:nil];
        [_input addObserver:self forKeyPath:@"progress" options:NSKeyValueObservingOptionNew context:nil];
        
        if (![_input openWithUrl:actualUrl andName:fileName andAuthorization:authorizationDict]) {
            self.currentState = AAPlayerStateError;
            self.currentError = [NSError errorWithDomain:kErrorDomain
                                                    code:AAMediaCenterErrorCodesSourceFailed
                                                userInfo:@{ NSLocalizedDescriptionKey:
                                                                NSLocalizedString(@"Couldn't open source", nil) }];
            return;
        }

        AAConverter *converter = [[AAConverter alloc] initWithInputUnit:_input];
        self.converter = converter;

        AAOutputUnit *output = [[outputUnitClass alloc] initWithConverter:_converter];
        output.outputFormat = _outputFormat;
        self.output = output;
        [_output setVolume:_volume];

        
        if (![_converter setupWithOutputUnit:_output]) {
            self.currentState = AAPlayerStateError;
            self.currentError = [NSError errorWithDomain:kErrorDomain
                                                    code:AAMediaCenterErrorCodesConverterFailed
                                                userInfo:@{ NSLocalizedDescriptionKey:
                                                                NSLocalizedString(@"Couldn't setup converter", nil) }];
            return;
        }
        
        [self setCurrentState:AAPlayerStatePlaying];
        dispatch_source_merge_data([AAQueues buffering_source], 1);
    });
}

- (void)playUrl:(NSURL *)url withName:(NSString *)fileName andAuthorization:(NSDictionary *)authorizationDict{
    
    [self playUrl:url withOutputUnitClass:[AAOutputUnit class] andName:fileName andAuthorization:authorizationDict];
}

- (void)pause {
    if (_currentState != AAPlayerStatePlaying)
        return;
    
    [_output pause];
    [self setCurrentState:AAPlayerStatePaused];
}

- (void)resume {
    if (_currentState != AAPlayerStatePaused)
        return;
    
    [_output resume];
    [self setCurrentState:AAPlayerStatePlaying];
}

- (void)stop {
    dispatch_async([AAQueues processing_queue], ^{
        if (_currentState != AAPlayerStateError) {
            [_input removeObserver:self forKeyPath:@"endOfInput"];
            [_input removeObserver:self forKeyPath:@"progress"];
        }
        self.output = nil;
        self.input = nil;
        self.converter = nil;
        self.cacheProgress = nil;
        [self setCurrentState:AAPlayerStateStopped];
    });
}

- (double)trackTime {
    return [_output framesToSeconds:_input.framesCount];
}

- (double)amountPlayed {
    return [_output amountPlayed];
}

- (NSDictionary *)metadata {
    return [_input metadata];
}

- (void)seekToTime:(double)time withDataFlush:(BOOL)flush {
    [_output seek:time];
    [_input seek:time withDataFlush:flush];
    if (flush) [_converter flushBuffer];
}

- (void)seekToTime:(double)time {
    [self seekToTime:time withDataFlush:NO];
}

#pragma mark - private

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if ([keyPath isEqualToString:@"currentState"] && _currentState == AAPlayerStateError){
        [_input removeObserver:self forKeyPath:@"endOfInput"];
        [_input removeObserver:self forKeyPath:@"progress"];
    }
    if (!_delegate)
        return;
    if ([keyPath isEqualToString:@"currentState"] &&
        [_delegate respondsToSelector:@selector(player:didChangeState:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate player:self didChangeState:_currentState];
        });
    } else if ([keyPath isEqualToString:@"endOfInput"]) {
        [self stop];
        [_delegate playerExpectsNextUrl:self];
    }else if ([keyPath isEqualToString:@"progress"]){
        NSProgress * progress = [_input valueForKeyPath:@"progress"];
        if ([_delegate respondsToSelector:@selector(player:didSetCacheProgress:)]) {
            [_delegate player:self didSetCacheProgress:progress];
        }
    }
}

- (void)setup {
    dispatch_source_set_event_handler([AAQueues buffering_source], ^{
        [_input process];
        [_converter process];
    });
}

- (void)setVolume:(float)volume {
    _volume = volume;
    [_output setVolume:volume];
}

- (NSURL *)checkIfOnlineMusicHasBeenCachedWithName:(NSString *)fileName
{
    NSString * mp3FilePath = [NSString stringWithFormat:@"%@.mp3",fileName];
    NSString * flacFilePath = [NSString stringWithFormat:@"%@.flac",fileName];
    NSFileManager *defaultFileManger = [NSFileManager defaultManager];
    if (![defaultFileManger fileExistsAtPath:AACacheMainURL]) {
        if (![defaultFileManger createDirectoryAtPath:AACacheMainURL
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil]) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:NSLocalizedString(@"Unable create cache directory", nil)
                                         userInfo:nil];
        }
    }
    NSString *cachedfilePath = [AACacheMainURL stringByAppendingPathComponent:mp3FilePath];
    if ([defaultFileManger fileExistsAtPath:cachedfilePath]) {
        NSURL * fileURL = [NSURL fileURLWithPath:cachedfilePath];
        return fileURL;
    }
    cachedfilePath = [AACacheMainURL stringByAppendingPathComponent:flacFilePath];
    if ([defaultFileManger fileExistsAtPath:cachedfilePath]) {
        NSURL * fileURL = [NSURL fileURLWithPath:cachedfilePath];
        return fileURL;
    }
    return nil;
}

@end
