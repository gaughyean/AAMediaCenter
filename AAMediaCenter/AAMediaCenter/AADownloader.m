//
//  AADownloader.m
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "AADownloader.h"
#import "AADownloaderTaskDelegate.h"

#define AAFlacRequestAuthorization @"Authorization"
#define AAFlacRequestAuthorizationDate @"date"
#define AAFlacRequestAuthorizationSecurityToken @"x-oss-security-token"
#define AAFlacRequestAuthorizationValidatecode @"validatecode"

static dispatch_queue_t url_downloadSession_creation_queue() {
    static dispatch_queue_t aa_url_downloadSession_creation_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        aa_url_downloadSession_creation_queue = dispatch_queue_create("com.aa.downloadSession.creation", DISPATCH_QUEUE_SERIAL);
    });
    
    return aa_url_downloadSession_creation_queue;
}

static NSString * const kAADownloadSessionDescription
        = @"aaMediaPlayerDownloadSessionDescription";
static NSString * const kAACacheSessionDescription
        = @"aaMediaPlayerCacheSessionDescription";
static NSString * const kAADownloadSessionIdentifier
        = @"aaMediaPlayerDownloadSessionIdentifier";
static NSString * const kAACacheSessionIdentifier
        = @"aaMediaPlayerCacheSessionIdentifier";

@interface AADownloader ()<NSURLSessionDataDelegate>
{
    dispatch_semaphore_t _switchSemaphore;
}
@property(weak, nonatomic, nullable) AADownloaderTaskDelegate * cacheDelegate;

@property(strong, nonatomic) NSURLSession * cacheSession;

@property(strong, nonatomic) NSURLSession * downloadSession;

@property (nonatomic, strong) NSLock *lock;

@property(strong, nonatomic, nullable) NSMutableDictionary * mutableTaskDelegatesKeyedByTaskIdentifier;

@property (readonly, nonatomic, copy) NSString *taskDescriptionForSessionTasks;

@end

@implementation AADownloader


+ (instancetype)shareHelper
{
    static AADownloader * shareInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shareInstance = [[AADownloader alloc] init];
    });
    return shareInstance;
}

- (instancetype)init
{
    if (self = [super init]) {
        
        self.lock = [[NSLock alloc] init];
        self.lock.name = @"com.aa.delegateDictionaryLock";
        self.mutableTaskDelegatesKeyedByTaskIdentifier = [[NSMutableDictionary alloc] init];
        self.mutableTasksKeyedByTaskDescription = [[NSMutableDictionary alloc] init];

        NSURLSessionConfiguration * cConfiguration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:kAACacheSessionIdentifier];
        NSURLSessionConfiguration * dConfiguration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:kAADownloadSessionIdentifier];
        //单元测试的时候取消注销
//        NSURLSessionConfiguration * configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
//        cConfiguration = configuration;
//        dConfiguration = configuration;
        
        NSOperationQueue * cacheQueue = [[NSOperationQueue alloc] init];
        cacheQueue.name = @"com.aa.cacheSession.queue";
        cacheQueue.maxConcurrentOperationCount = 1;
        NSURLSession * cacheSession = [NSURLSession sessionWithConfiguration:cConfiguration delegate:self delegateQueue:cacheQueue];
        cacheSession.sessionDescription = kAACacheSessionDescription;
        self.cacheSession = cacheSession;
        
        NSOperationQueue * downloadQueue = [[NSOperationQueue alloc] init];
        downloadQueue.name = @"com.aa.downloadSession.queue";
        downloadQueue.maxConcurrentOperationCount = 3;
        NSURLSession * downloadSession = [NSURLSession sessionWithConfiguration:dConfiguration delegate:self delegateQueue:downloadQueue];
        downloadSession.sessionDescription = kAADownloadSessionDescription;
        self.downloadSession = downloadSession;
    }
    return self;
}

- (NSString *)taskDescriptionForSessionTasks
{
    return [NSString stringWithFormat:@"%p", self];
}

#pragma mark - plubic

- (NSURLSessionDataTask *)downloadMusicWithFileName:(NSString * _Nonnull)fileName andURL:(NSURL * _Nonnull)url andAuthorization:(NSDictionary *)authorizationDict andDownloadProgress:(nullable void (^)(NSProgress * _Nullable downloadProgress)) downloadProgressBlock completionHandler:(nullable void (^)(NSURLResponse  * _Nullable response, NSData * _Nullable data,  NSError * _Nullable error))completionHandler
{
    NSURLSessionDataTask * previousTask = [self dataTaskForTaskDescription:fileName];
    if (previousTask) {//已经有相同资源在下载了
        return nil;
    }
    if ([self.cacheDelegate.taskDescription isEqualToString:fileName]) {//在线听歌缓存正在进行
        AALog(@"此曲正在在线缓存播放");
        self.moveCurrentMusicToDownloadedPath = YES;
        return nil;
    }
    NSMutableURLRequest * request = [NSMutableURLRequest requestWithURL:url];
    NSString * modifidFileName = [NSString stringWithFormat:@"%@.%@",fileName,url.pathExtension];
    NSString * filePath = [self checkDownloadingFile:modifidFileName];
    unsigned long long offset = 0;
    if (filePath) {
        offset = [self setRequest:request rangeWithExistingFilePath:filePath];
    }
    NSMutableURLRequest * modifiedRequest = [self modifyURLRequest:request withAuthorizationDict:authorizationDict];
    NSURLSessionDataTask * dataTask = [self dataTaskWithRequest:modifiedRequest andOffset:offset andFileName:fileName downloadProgress:downloadProgressBlock completionHandler:completionHandler];
    return dataTask;
}

- (NSURLSessionDataTask *)prepareCachingWithRequest:(NSMutableURLRequest *)request andFileName:(NSString *)fileName andAuthorization:(NSDictionary *)authorizationDict andCacheDelegate:(AADownloaderTaskDelegate *)delegate {
    
    NSURLSessionDataTask * previousTask = [self dataTaskForTaskDescription:fileName];
    if (previousTask) {//正在下载，先暂停
        _switchSemaphore = dispatch_semaphore_create(0);
        [previousTask cancel];
        dispatch_semaphore_wait(_switchSemaphore, DISPATCH_TIME_FOREVER);
        self.moveCurrentMusicToDownloadedPath = YES;
        _switchSemaphore = nil;
    }else{
        //默认为NO
        self.moveCurrentMusicToDownloadedPath = NO;
    }
    NSURL * url = request.URL;
    NSString * modifidFileName = [NSString stringWithFormat:@"%@.%@",fileName,url.pathExtension];
    NSString * filePath = [self checkDownloadingFile:modifidFileName];
    unsigned long long offset = 0;
    if (filePath) {
        offset = [self setRequest:request rangeWithExistingFilePath:filePath];
    }
    self.cacheDelegate = delegate;
    delegate.helper = self;
    delegate.taskDescription = fileName;
    delegate.originalOffset = offset;
    NSMutableURLRequest * modifiedRequest = [self modifyURLRequest:request withAuthorizationDict:authorizationDict];
    NSURLSessionDataTask * task = [self.cacheSession dataTaskWithRequest:modifiedRequest];
    task.taskDescription = fileName;
    
    return task;
}

+ (NSString *)downloadedPath
{
    return AADownloadedPath;
}

+ (NSString *)downloadingPath
{
    return AADownloadingPath;
}

+ (NSString *)cachedPath
{
    return AACacheMainURL;
}

#pragma mark - private

- (unsigned long long)setRequest:(NSMutableURLRequest *)request rangeWithExistingFilePath:(NSString * _Nonnull)filePath
{
    NSFileHandle * fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:filePath];
    unsigned long long offset = fileHandle.availableData.length;
    if ( offset > 0 && --offset > 0) {
        NSString *requestRange = [NSString stringWithFormat:@"bytes=%llu-", offset];
        [request setValue:requestRange forHTTPHeaderField:@"Range"];
        return offset;
    }
    return 0;
}

- (NSMutableURLRequest *)modifyURLRequest:(NSMutableURLRequest *)request withAuthorizationDict:(NSDictionary *)authorizationDict
{
    if (authorizationDict) {
        [request addValue:authorizationDict[AAFlacRequestAuthorization] forHTTPHeaderField:AAFlacRequestAuthorization];
        [request addValue:authorizationDict[AAFlacRequestAuthorizationDate] forHTTPHeaderField:AAFlacRequestAuthorizationDate];
        [request addValue:authorizationDict[AAFlacRequestAuthorizationSecurityToken] forHTTPHeaderField:AAFlacRequestAuthorizationSecurityToken];
        [request addValue:authorizationDict[AAFlacRequestAuthorizationValidatecode] forHTTPHeaderField:AAFlacRequestAuthorizationValidatecode];
    }
    return request;
}

- (NSString *)checkDownloadingFile:(NSString *)fileName
{
    NSString * filePath = [AADownloadingPath stringByAppendingPathComponent:fileName];
    NSFileManager *defaultFileManger = [NSFileManager defaultManager];
    if ([defaultFileManger fileExistsAtPath:filePath]) {
        return filePath;
    }
    return nil;
}

- (AADownloaderTaskDelegate *)delegateForTask:(NSURLSessionTask *)task {
    NSParameterAssert(task);
    
    AADownloaderTaskDelegate *delegate = nil;
    [self.lock lock];
    delegate = self.mutableTaskDelegatesKeyedByTaskIdentifier[@(task.taskIdentifier)];
    [self.lock unlock];
    
    return delegate;
}

- (NSURLSessionDataTask *)dataTaskForTaskDescription:(NSString *)taskDescription {
    NSParameterAssert(taskDescription);
    
    NSURLSessionDataTask *dataTask = nil;
    [self.lock lock];
    dataTask = self.mutableTasksKeyedByTaskDescription[taskDescription];
    [self.lock unlock];
    
    return dataTask;
}

- (void)setDelegate:(AADownloaderTaskDelegate *)delegate
            forTask:(NSURLSessionTask *)task
{
    NSParameterAssert(task);
    NSParameterAssert(delegate);
    [self.lock lock];
    self.mutableTasksKeyedByTaskDescription[task.taskDescription] = task;
    self.mutableTaskDelegatesKeyedByTaskIdentifier[@(task.taskIdentifier)] = delegate;
    [delegate setupProgressForTask:task];
    [self.lock unlock];
}

- (void)removeDelegateForTask:(NSURLSessionTask *)task {
    NSParameterAssert(task);
    AADownloaderTaskDelegate *delegate = [self delegateForTask:task];
    [self.lock lock];
    [delegate cleanUpProgressForTask:task];
    [self.mutableTaskDelegatesKeyedByTaskIdentifier removeObjectForKey:@(task.taskIdentifier)];
    [self.mutableTasksKeyedByTaskDescription removeObjectForKey:task.taskDescription];
    [self.lock unlock];
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request andOffset:(unsigned long long)offset andFileName:(NSString * _Nonnull)fileName downloadProgress:(nullable void (^)(NSProgress *downloadProgress)) downloadProgressBlock completionHandler:(nullable void (^)(NSURLResponse *response, id _Nullable responseObject,  NSError * _Nullable error))completionHandler {
    __block NSURLSessionDataTask *dataTask = nil;
    dispatch_sync(url_downloadSession_creation_queue(), ^{
        dataTask = [self.downloadSession dataTaskWithRequest:request];
        dataTask.taskDescription = fileName;
    });
 
    [self addDelegateForDataTask:dataTask andOffset:(unsigned long long)offset andFileName:fileName downloadProgress:downloadProgressBlock completionHandler:completionHandler];
    
    return dataTask;
}

- (void)addDelegateForDataTask:(NSURLSessionDataTask *)dataTask andOffset:(unsigned long long)offset andFileName:(NSString * _Nonnull)fileName downloadProgress:(nullable void (^)(NSProgress *downloadProgress)) downloadProgressBlock completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
{
    AADownloaderTaskDelegate * delegate = [[AADownloaderTaskDelegate alloc] init];
    delegate.helper = self;
    delegate.originalOffset = offset;
    delegate.completionHandler = completionHandler;
    [self setDelegate:delegate forTask:dataTask];
    delegate.downloadProgressBlock = downloadProgressBlock;
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        return;
    }
    NSHTTPURLResponse * httpResponse = (NSHTTPURLResponse *)response;
    NSString * description = session.sessionDescription;
    if ([description isEqualToString:kAADownloadSessionDescription]) {
        if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            AADownloaderTaskDelegate *delegate = [self delegateForTask:dataTask];
            if (delegate) {
                NSDictionary * userInfo = [NSDictionary dictionaryWithObject:@(httpResponse.statusCode) forKey:@"HTTPStatusCode"];
                NSError * httpError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:userInfo];
                [delegate URLSession:session task:dataTask didCompleteWithError:httpError];
                [self removeDelegateForTask:dataTask];
            }
            return;
        }
        AADownloaderTaskDelegate *delegate = [self delegateForTask:dataTask];
        if (delegate) {
            [delegate URLSession:session dataTask:dataTask didReceiveResponse:response completionHandler:completionHandler];
        }
    }else{
        if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            NSDictionary * userInfo = [NSDictionary dictionaryWithObject:@(httpResponse.statusCode) forKey:@"HTTPStatusCode"];
            NSError * httpError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:userInfo];
            [self.cacheDelegate URLSession:session task:dataTask didCompleteWithError:httpError];
            return;
        }
        [self.cacheDelegate URLSession:session dataTask:dataTask didReceiveResponse:response completionHandler:completionHandler];
    }
    NSURLSessionResponseDisposition disposition = NSURLSessionResponseAllow;
    if (completionHandler) {
        completionHandler(disposition);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    NSString * description = session.sessionDescription;
    if ([description isEqualToString:kAADownloadSessionDescription]) {
        AADownloaderTaskDelegate *delegate = [self delegateForTask:dataTask];
        if (delegate) {
            [delegate URLSession:session dataTask:dataTask didReceiveData:data];
        }
    }else{
        [self.cacheDelegate URLSession:session dataTask:dataTask didReceiveData:data];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    NSString * description = session.sessionDescription;
    if ([description isEqualToString:kAADownloadSessionDescription]) {
        AADownloaderTaskDelegate *delegate = [self delegateForTask:task];
        if (delegate) {
            [delegate URLSession:session task:task didCompleteWithError:error];
            [self removeDelegateForTask:task];
        }
        if (_switchSemaphore) {
            dispatch_semaphore_signal(_switchSemaphore);
        }
    }else{
        [self.cacheDelegate URLSession:session task:task didCompleteWithError:error];
    }
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session
{
    AALog(@"%@",session);
}

@end


