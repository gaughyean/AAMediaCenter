//
//  AAQueues.m
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "AAQueues.h"

@implementation AAQueues

+ (dispatch_queue_t)lock_queue {
    static dispatch_queue_t _lock_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _lock_queue = dispatch_queue_create("com.aa.lock",
                                            DISPATCH_QUEUE_SERIAL);
    });
    return _lock_queue;
}

+ (dispatch_queue_t)processing_queue {
    static dispatch_queue_t _processing_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _processing_queue = dispatch_queue_create("com.aa.processing",
                                                  DISPATCH_QUEUE_SERIAL);
    });
    return _processing_queue;
}

+ (dispatch_source_t)buffering_source {
    static dispatch_source_t _buffering_source;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _buffering_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD,
                                                   0, 0, [AAQueues processing_queue]);
        dispatch_resume(_buffering_source);
    });
    return _buffering_source;
}

@end
