//
//  AAAgent.m
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "AAAgent.h"
#import "HTTPSource.h"
#import "FileSource.h"
#import "CoreAudioDecoder.h"
#import "FlacDecoder.h"

@interface AAAgent ()
@property(strong, nonatomic) NSDictionary *sources;
@property(strong, nonatomic) NSMutableDictionary *decoders;
@end

@implementation AAAgent

+ (AAAgent *)sharedManager {
    static AAAgent *_sharedManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedManager = [[AAAgent alloc] init];
    });
    return _sharedManager;
}

- (id)init {
    self = [super init];
    if (self) {
        
        /* Sources */
        self.sources = [NSDictionary dictionaryWithObjectsAndKeys:
                        [HTTPSource class], [HTTPSource scheme],
                        [HTTPSource class], @"https",
                        [FileSource class], [FileSource scheme],
                        nil];
        
        /* Decoders */
        NSMutableDictionary *decodersDict = [NSMutableDictionary dictionary];
        [[CoreAudioDecoder fileTypes] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [decodersDict setObject:[CoreAudioDecoder class] forKey:obj];
        }];

        self.decoders = decodersDict;
        
        Class class;
        if ((class = [FlacDecoder class])) [self registerDecoder:class forFileTypes:@[ @"flac" ]];
    }
    return self;
}

- (id<AASource>)sourceForURL:(NSURL *)url error:(NSError **)error {
    id<AASource> result;
    if (_resolver && (result = [_resolver sourceForURL:url error:error])) {
        return result;
    }
    
    NSString *scheme = [url scheme];
    Class source = [_sources objectForKey:scheme];
    if (!source) {
        if (error) {
            NSString *message = [NSString stringWithFormat:@"%@ %@",
                                 NSLocalizedString(@"Unable to find source for scheme", nil),
                                 scheme];
            *error = [NSError errorWithDomain:kErrorDomain
                                         code:AAMediaCenterErrorCodesSourceFailed
                                     userInfo:@{ NSLocalizedDescriptionKey: message }];
        }
        return nil;
    }
    return [[source alloc] init];
}

- (id<AADecoder>)decoderForSource:(id<AASource>)source error:(NSError **)error {
    if (!source || ![source url]) {
        return nil;
    }
    
    id<AADecoder> result;
    if (_resolver && (result = [_resolver decoderForSource:source error:error])) {
        return result;
    }
    
    NSString *extension = [[[source url] path] pathExtension];
    Class decoder = [_decoders objectForKey:[extension lowercaseString]];
    if (!decoder) {
        if (error) {
            NSString *message = [NSString stringWithFormat:@"%@ %@",
                                 NSLocalizedString(@"Unable to find decoder for extension", nil),
                                 extension];
            *error = [NSError errorWithDomain:kErrorDomain
                                         code:AAMediaCenterErrorCodesDecoderFailed
                                     userInfo:@{ NSLocalizedDescriptionKey: message }];
        }
        return nil;
    }
    
    return [[decoder alloc] init];
}


#pragma mark - private

- (void)registerDecoder:(Class)class forFileTypes:(NSArray *)fileTypes {
    
    [fileTypes enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [_decoders setObject:class forKey:obj];
    }];
}

@end
