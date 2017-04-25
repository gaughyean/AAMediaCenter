//
//  AAQueues.h
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

@interface AAQueues : NSObject

+ (dispatch_queue_t)lock_queue;

+ (dispatch_queue_t)processing_queue;

+ (dispatch_source_t)buffering_source;

@end
