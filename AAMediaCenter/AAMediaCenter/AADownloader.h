//
//  AADownloader.h
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

static NSString * _Nullable const kAADownloaderTaskDelegateDownloadFailedNotificationName = @"kAADownloaderTaskDelegateDownloadFailedNotificationName";
static NSString * _Nullable const kAADownloaderTaskDelegateDownloadSucceedNotificationName = @"kAADownloaderTaskDelegateDownloadSucceedNotificationName";

typedef void(^startCachingBlock)(long long, NSFileHandle * _Nonnull);
typedef void(^cachingBlock)(NSData * _Nullable);
typedef void(^successCachingBlock)();
typedef void(^failCachingBlock)();

@class AADownloaderTaskDelegate;
@interface AADownloader : NSObject

@property(strong, nonatomic, nullable) NSFileHandle * cacheHandle;
/*
    正在在线播放中的歌曲标记为下载时设置为YES
 */
@property(assign, nonatomic) BOOL moveCurrentMusicToDownloadedPath;
/*
    通过FileName为key找到对应的下载任务
    重新启动程序后，本字典为空，即不对上次启动但未完成的任务作记录，使用者需要用自己的数据库去记录下载完成、下载中和待下载任务，获取下载任务状况可以使用下载方法中的completionHandler或者监听kAADownloaderTaskDelegateDownloadFailedNotificationName和kAADownloaderTaskDelegateDownloadSucceedNotificationName通知
 */
@property(strong, nonatomic, nullable) NSMutableDictionary * mutableTasksKeyedByTaskDescription;
/*
    completionQueue和completionGroup为后续扩展用
 */
@property(nonatomic, strong, nullable) dispatch_queue_t completionQueue;

@property(nonatomic, strong, nullable) dispatch_group_t completionGroup;

+ (instancetype _Nonnull)shareHelper;
/*
    在线播放开始缓存的方法，不需要自己调用(HTTPSource唯一调用)
    注意：如果该播放歌曲正在下载的话，该方法将自动暂停原下载任务后从之前进度开始缓存在线播放歌曲。
    可以通过监听kAAHTTPSourceCachedSucceedNotificationName和kAAHTTPSourceCachedFailedNotificationName获取缓存情况
 */
- (NSURLSessionDataTask * _Nullable)prepareCachingWithRequest:(NSMutableURLRequest * _Nonnull)request andFileName:(NSString * _Nonnull)fileName andAuthorization:(NSDictionary * _Nullable)authorizationDict andCacheDelegate:(AADownloaderTaskDelegate * _Nonnull)delegate;
/*
    下载歌曲对外接口
    注意：如果歌曲已下载，请不要传入，否则将重复下载，本方法只检查未下载完成的文件，不检查已经下载完成的文件
    特别注意：如果歌曲正在在线播放缓存的话，不用传入该歌曲url进行下载，只需要把参数moveCurrentMusicToDownloadedPath设置为YES。如果该歌曲没有完成缓存便结束播放（AAPlayer stop了）的话，原下载将停止，使用者需要重新对该歌曲用此方法进行下载操作便可接着之前的进度下载。
    可以监听kAAHTTPSourceCachedMoveToDownloadedFileNotificationName通知获取在线缓存歌曲是否缓存成功并转移至已下载文件夹里
 */
- (NSURLSessionDataTask * _Nullable)downloadMusicWithFileName:(NSString * _Nonnull)fileName andURL:(NSURL * _Nonnull)url andAuthorization:(NSDictionary * _Nullable)authorizationDict andDownloadProgress:(nullable void (^)(NSProgress * _Nullable downloadProgress)) downloadProgressBlock completionHandler:(nullable void (^)(NSURLResponse  * _Nullable response, NSData * _Nullable data,  NSError * _Nullable error))completionHandler;


+ (NSString * _Nonnull)downloadedPath;

+ (NSString * _Nonnull)downloadingPath;

+ (NSString * _Nonnull)cachedPath;

@end
