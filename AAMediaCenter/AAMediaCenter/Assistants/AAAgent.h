//
//  AAAgent.h
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "AAProtocols.h"

@protocol AAAgentResoler;

@interface AAAgent : NSObject

@property (nonatomic, weak) id<AAAgentResoler> resolver;

+ (AAAgent *)sharedManager;

- (id<AASource>)sourceForURL:(NSURL *)url error:(NSError **)error;


- (id<AADecoder>)decoderForSource:(id<AASource>)source error:(NSError **)error;

@end

@protocol AAAgentResoler <NSObject>

- (id<AASource>)sourceForURL:(NSURL *)url error:(NSError **)error;

- (id<AADecoder>)decoderForSource:(id<AASource>)source error:(NSError **)error;

- (NSArray *)urlsForContainerURL:(NSURL *)url error:(NSError **)error;

@end
