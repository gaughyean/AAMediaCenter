//
//  AADownloaderDelegate.m
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/27.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "AADownloaderTaskDelegate.h"
#import "AADownloader.h"

static dispatch_group_t url_downloadSession_completion_group() {
    static dispatch_group_t aa_url_downloadSession_completion_group;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        aa_url_downloadSession_completion_group = dispatch_group_create();
    });
    
    return aa_url_downloadSession_completion_group;
}

static dispatch_queue_t url_downloadSession_processing_queue() {
    static dispatch_queue_t af_url_downloadSession_processing_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        af_url_downloadSession_processing_queue = dispatch_queue_create("com.aa.downloadSession.processing", DISPATCH_QUEUE_CONCURRENT);
    });
    return af_url_downloadSession_processing_queue;
}

@interface AADownloaderTaskDelegate ()

@end

@implementation AADownloaderTaskDelegate


- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    self.downloadProgress = [[NSProgress alloc] initWithParent:nil userInfo:nil];
    self.downloadProgress.totalUnitCount = NSURLSessionTransferSizeUnknown;
    _originalOffset = 0;
    return self;
}

- (void)setOriginalOffset:(long long)originalOffset
{
    if (_originalOffset == 0) {
        _originalOffset = originalOffset;
    }
}

#pragma mark - NSProgress Tracking

- (void)setupProgressForTask:(NSURLSessionTask *)task {
    __weak __typeof__(task) weakTask = task;
    
    [self.downloadProgress setCancellable:YES];
    [self.downloadProgress setCancellationHandler:^{
        __typeof__(weakTask) strongTask = weakTask;
        [strongTask cancel];
    }];
    [self.downloadProgress setPausable:YES];
    [self.downloadProgress setPausingHandler:^{
        __typeof__(weakTask) strongTask = weakTask;
        [strongTask suspend];
    }];
    
    if ([self.downloadProgress respondsToSelector:@selector(setResumingHandler:)]) {
        [self.downloadProgress setResumingHandler:^{
            __typeof__(weakTask) strongTask = weakTask;
            [strongTask resume];
        }];
    }
    
    [self.downloadProgress addObserver:self
                            forKeyPath:NSStringFromSelector(@selector(fractionCompleted))
                               options:NSKeyValueObservingOptionNew
                               context:NULL];
}

- (void)cleanUpProgressForTask:(NSURLSessionTask *)task {
    [self.downloadProgress removeObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted))];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    if ([object isEqual:self.downloadProgress]) {
        if (self.downloadProgressBlock) {
            self.downloadProgressBlock(object);
        }
    }
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    [self prepareDownloadFileHandleWithName:[NSString stringWithFormat:@"%@.%@",
                                             dataTask.taskDescription,
                                             dataTask.currentRequest.URL.pathExtension]];
}

- (void)URLSession:(__unused NSURLSession *)session
          dataTask:(__unused NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    self.downloadProgress.totalUnitCount = dataTask.countOfBytesExpectedToReceive + self.originalOffset;
    self.downloadProgress.completedUnitCount = dataTask.countOfBytesReceived + self.originalOffset;
    int64_t offset = dataTask.countOfBytesReceived - data.length + self.originalOffset;
    [self.fileHandle seekToFileOffset:offset];
    [self.fileHandle writeData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    __strong AADownloader * helper = self.helper;
    __block NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    NSData *data = nil;
    if (self.fileHandle) {
        [self.fileHandle seekToFileOffset:0];
        data = [self.fileHandle readDataToEndOfFile];
        [self.fileHandle closeFile];
    }
    
    if (error) {
        userInfo[@"kCompleteErrorKey"] = error;
        dispatch_group_async(helper.completionGroup ?: url_downloadSession_completion_group(), helper.completionQueue ?: dispatch_get_main_queue(), ^{
            if (self.completionHandler) {
                self.completionHandler(task.response, data, error);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:kAADownloaderTaskDelegateDownloadFailedNotificationName object:task userInfo:userInfo];
            });
        });
    } else {
        dispatch_async(url_downloadSession_processing_queue(), ^{
            dispatch_group_async(helper.completionGroup ?: url_downloadSession_completion_group(), helper.completionQueue ?: dispatch_get_main_queue(), ^{
                NSError * moveFileErr = [self moveDownloadedFile];
                if (moveFileErr) {
                    if (self.completionHandler) {
                        self.completionHandler(task.response, data, moveFileErr);
                    }
                    userInfo[@"kCompleteErrorKey"] = moveFileErr;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:kAADownloaderTaskDelegateDownloadFailedNotificationName object:task userInfo:userInfo];
                    });
                }else{
                    if (self.completionHandler) {
                        self.completionHandler(task.response, data, nil);
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:kAADownloaderTaskDelegateDownloadSucceedNotificationName object:task userInfo:userInfo];
                    });
                }
            });
        });
    }
}

#pragma mark - fileHandle

- (void)prepareDownloadFileHandleWithName:(NSString*)fileName {
    
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
    
    NSString *filePath = [AADownloadingPath stringByAppendingPathComponent:fileName];
    NSString *downloadedfilePath = [AADownloadedPath stringByAppendingPathComponent:fileName];
    if (![defaultFileManger fileExistsAtPath:filePath]) {
        if (![defaultFileManger createFileAtPath:filePath
                                        contents:nil
                                      attributes:nil]) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:NSLocalizedString(@"Unable create cache file", nil)
                                         userInfo:nil];
        }
    }
    
    self.downloadingFilePath = filePath;
    self.downloadedFilePath = downloadedfilePath;
    if (!self.fileHandle) {
        self.fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:filePath];
    }
    [self.fileHandle seekToFileOffset:0];
}

- (NSError *)moveDownloadedFile
{
    NSFileManager *defaultFileManger = [NSFileManager defaultManager];
    NSError * error = nil;
    if ([defaultFileManger copyItemAtPath:self.downloadingFilePath toPath:self.downloadedFilePath error:&error]) {
        if ([defaultFileManger removeItemAtPath:self.downloadingFilePath error:&error]) {
            return nil;
        }
    }
    return error;
}


@end
