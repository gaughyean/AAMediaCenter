//
//  HTTPSource.m
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "HTTPSource.h"
#import "AADownloader.h"

@interface HTTPSource (){
    long _byteCount;
    long _bytesRead;
    long long _bytesExpected;
    long long _bytesWaitingFromCache;
    dispatch_semaphore_t _downloadingSemaphore;
    BOOL _connectionDidFail;
    BOOL _cacheDidFinished;
}
@property (strong, nonatomic) NSURLSessionDataTask * currentTask;
@property (strong, nonatomic) NSMutableURLRequest *request;
@property (strong, nonatomic) NSString * cachingFilePath;
@property (strong, nonatomic) NSString * cachedFilePath;
@property (strong, nonatomic) NSFileHandle * fileHandle;
@property (strong, nonatomic) NSProgress * downloadProgress;
@property (assign, nonatomic) long originalOffset;

@end

@implementation HTTPSource

@synthesize fileHandle = _fileHandle;
@synthesize originalOffset = _originalOffset;
@synthesize downloadProgress = _downloadProgress;

- (instancetype)init
{
    if (self = [super init]) {
        _originalOffset = 0;
    }
    return self;
}

- (void)dealloc {
    [self close];
    [self dealWithTheCachedDataWhileDealloc];
}

#pragma mark - AASource

+ (NSString *)scheme {
    return @"http";
}

- (NSURL *)url {
    return [_request URL];
}

- (long)size {
    return (long)_bytesExpected;
}

- (BOOL)open:(NSURL *)url withName:(NSString *)fileName andAuthorization:(NSDictionary *)authorizationDict{
    self.request = [NSMutableURLRequest requestWithURL:url];
    [self.request addValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];
    NSString * modifidFileName = [NSString stringWithFormat:@"%@.%@",fileName,url.pathExtension];
    self.fileHandle = [self prepareFilePathWithName:modifidFileName];
    
    AADownloader * helper = [AADownloader shareHelper];

    NSURLSessionDataTask * task = [helper prepareCachingWithRequest:self.request andFileName:fileName andAuthorization:authorizationDict andCacheDelegate:self ];
    
    self.currentTask = task;
    
    if ([NSThread isMainThread]) {
        [_currentTask resume];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [_currentTask resume];
        });
    }
    
    _bytesExpected = 0;
    _bytesRead     = 0;
    _byteCount     = 0;
    _connectionDidFail = NO;
    
    _downloadingSemaphore = dispatch_semaphore_create(0);
    dispatch_semaphore_wait(_downloadingSemaphore, DISPATCH_TIME_FOREVER);

    return YES;
}

- (BOOL)seekable {
    return YES;
}

- (BOOL)seek:(long)position whence:(int)whence {
    switch (whence) {
        case SEEK_SET:
            _bytesRead = position;
            break;
        case SEEK_CUR:
            _bytesRead += position;
            break;
        case SEEK_END:
            _bytesRead = (long)_bytesExpected - position;
            break;
    }
    return YES;
}

- (long)tell {
    return _bytesRead;
}

- (int)read:(void *)buffer amount:(int)amount {
    if (_bytesRead + amount > _bytesExpected)
        return 0;
    
    while(_byteCount < _bytesRead + amount) {
        if (_connectionDidFail) return 0;
        _bytesWaitingFromCache = _bytesRead + amount;
        dispatch_semaphore_wait(_downloadingSemaphore, dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC));
    }
    
    int result = 0;
    @autoreleasepool {
        NSData *data = nil;
        @synchronized(_fileHandle) {
            [_fileHandle seekToFileOffset:_bytesRead];
            data = [_fileHandle readDataOfLength:amount];
        }
        [data getBytes:buffer length:data.length];
        _bytesRead += data.length;
        
        result = (int)data.length;
    }
    
    return result;
}

- (void)close {
    [_currentTask cancel];
    [_fileHandle closeFile];
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    [_fileHandle seekToFileOffset:0];
    long long totalBytes = response.expectedContentLength + _originalOffset;
    
    _bytesExpected = totalBytes;
    if (_byteCount == 0) {
        _byteCount = _originalOffset;
    }
    if ([_fileHandle seekToEndOfFile] == _bytesExpected) {
        _downloadProgress.totalUnitCount = dataTask.countOfBytesExpectedToReceive + _originalOffset;
        _downloadProgress.completedUnitCount = dataTask.countOfBytesReceived + _originalOffset;
        [_currentTask cancel];
        _cacheDidFinished = YES;
        dispatch_async([HTTPSource cachingQueue], ^{
            _byteCount = (long)_bytesExpected;
        });
    }
    dispatch_semaphore_signal(_downloadingSemaphore);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    if(_byteCount >= _bytesWaitingFromCache) {
        dispatch_semaphore_signal(_downloadingSemaphore);
    }
    if (data && _fileHandle) {
        dispatch_async([HTTPSource cachingQueue], ^{
            if (_byteCount < _bytesExpected) {
                @synchronized(_fileHandle) {
                    [_fileHandle seekToFileOffset:_byteCount];
                    [_fileHandle writeData:data];
                }
                _byteCount += data.length;
            }
        });
    }
    _downloadProgress.totalUnitCount = dataTask.countOfBytesExpectedToReceive + _originalOffset;
    _downloadProgress.completedUnitCount = dataTask.countOfBytesReceived + _originalOffset;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (error) {AALog(@"%@",error);
        _connectionDidFail = YES;
        dispatch_semaphore_signal(_downloadingSemaphore);
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        userInfo[@"kCompleteErrorKey"] = error;
        [[NSNotificationCenter defaultCenter] postNotificationName:kAAHTTPSourceCachedFailedNotificationName object:task userInfo:userInfo];
    }else{
        _cacheDidFinished = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:kAAHTTPSourceCachedSucceedNotificationName object:task userInfo:nil];
    }
}

#pragma mark - private

+ (dispatch_queue_t)cachingQueue {
    static dispatch_queue_t _cachingQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _cachingQueue = dispatch_queue_create("com.aa.httpcache",
                                              DISPATCH_QUEUE_SERIAL);
    });
    return _cachingQueue;
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

- (NSFileHandle *)prepareFilePathWithName:(NSString *)fileName
{
    NSFileManager *defaultFileManger = [NSFileManager defaultManager];
    if (![defaultFileManger fileExistsAtPath:AADownloadingPath]) {
        if (![defaultFileManger createDirectoryAtPath:AADownloadingPath
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil]) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:NSLocalizedString(@"Unable create cache directory", nil)
                                         userInfo:nil];
        }
    }
    NSString *filePath = [AADownloadingPath stringByAppendingPathComponent:fileName];
    
    if (![defaultFileManger fileExistsAtPath:filePath]) {
        if (![defaultFileManger createFileAtPath:filePath
                                        contents:nil
                                      attributes:nil]) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:NSLocalizedString(@"Unable create cache file", nil)
                                         userInfo:nil];
        }
    }
    
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
    NSString *cachedfilePath = [AACacheMainURL stringByAppendingPathComponent:fileName];
    
    if (![defaultFileManger fileExistsAtPath:AADownloadedPath]) {
        if (![defaultFileManger createDirectoryAtPath:AADownloadedPath
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil]) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:NSLocalizedString(@"Unable create cache directory", nil)
                                         userInfo:nil];
        }
    }
    NSString *downloadedFilePath = [AADownloadedPath stringByAppendingPathComponent:fileName];
    
    self.cachingFilePath = filePath;
    self.cachedFilePath = cachedfilePath;
    self.downloadedFilePath = downloadedFilePath;
    
    NSFileHandle * fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:filePath];
    
    return fileHandle;
}

- (void)dealWithTheCachedDataWhileDealloc
{
    NSFileManager *defaultFileManger = [NSFileManager defaultManager];
    NSError * fileMangerError = nil;
    if ([AADownloader shareHelper].moveCurrentMusicToDownloadedPath && _cacheDidFinished) {//在线试听转下载，完成缓存后转移文件
        if ([defaultFileManger copyItemAtPath:self.cachingFilePath toPath:self.downloadedFilePath error:&fileMangerError]) {
            [defaultFileManger removeItemAtPath:self.cachingFilePath error:&fileMangerError];
            [[NSNotificationCenter defaultCenter] postNotificationName:kAAHTTPSourceCachedMoveToDownloadedFileNotificationName object:nil userInfo:nil];
        }else if (fileMangerError){
            AALog(@"%@",fileMangerError);
        }
    }else if(_cacheDidFinished){//在线试听缓存完成后转移文件
        if ([defaultFileManger copyItemAtPath:self.cachingFilePath toPath:self.cachedFilePath error:&fileMangerError]) {
            [defaultFileManger removeItemAtPath:self.cachingFilePath error:&fileMangerError];
            [[NSNotificationCenter defaultCenter] postNotificationName:kAAHTTPSourceCachedMoveToCachedFileNotificationName object:nil userInfo:nil];
        }else if (fileMangerError){
            AALog(@"%@",fileMangerError);
        }
    }
    //在线试听没有完成全部缓存不用处理
}

@end
