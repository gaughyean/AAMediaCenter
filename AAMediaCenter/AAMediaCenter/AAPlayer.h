//
//  AAPlayer.h
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "AAAudioUnit.h"

@protocol AAPlayerDelegate;

typedef enum : NSInteger {
    AAPlayerStateStopped,
    AAPlayerStatePlaying,
    AAPlayerStatePaused,
    AAPlayerStateError
} AAPlayerState;

@interface AAPlayer : NSObject

@property (assign, nonatomic) AAMediaCenterOutputFormat outputFormat;

@property (assign, nonatomic) float volume;

@property (assign, nonatomic, readonly) AAPlayerState currentState;

@property (strong, nonatomic, readonly) NSError *currentError;

@property (weak, nonatomic) id<AAPlayerDelegate> delegate;

/**
    url:播放歌曲的直接路径，不能是跳转的路径
    fileName:识别歌曲的唯一ID
    authorizationDict:url鉴权的headerfield
    注意：如果歌曲已下载，请传入本地URL，否则将重复下载，本方法只检查未下载完成的文件，不检查已经下载完成的文件
    如果正在下载的歌曲再在线播放，将自动暂停正在下载的任务，由在线播放延续下载缓存
 */
- (void)playUrl:(NSURL *)url withName:(NSString *)fileName andAuthorization:(NSDictionary *)authorizationDict;

- (void)pause;

- (void)resume;

- (void)stop;
/**
    当前歌曲的总时长（秒）
 */
- (double)trackTime;
/**
    当前歌曲的已播放时间（秒）
 */
- (double)amountPlayed;
/**
    选择歌曲的某个时间开始播放（秒）
 */
- (void)seekToTime:(double)time;

- (NSDictionary *)metadata;

@end

@protocol AAPlayerDelegate <NSObject>

/**
    在此代理方法里面播放下一首歌
 */
- (void)playerExpectsNextUrl:(AAPlayer *)player;

@optional

/**
    播放器状态变化
 */
- (void)player:(AAPlayer *)player didChangeState:(AAPlayerState)state;

/**
    在线播放缓存情况
 */

- (void)player:(AAPlayer *)player didSetCacheProgress:(NSProgress *)progress;

@end

