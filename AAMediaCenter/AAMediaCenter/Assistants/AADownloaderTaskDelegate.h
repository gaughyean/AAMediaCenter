//
//  AADownloaderTaskDelegate.h
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/27.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

@class AADownloader;

typedef void (^AADownloaderTaskProgressBlock)(NSProgress *);
typedef void (^AADownloaderTaskCompletionHandler)(NSURLResponse *response, NSData * data, NSError *error);

@interface AADownloaderTaskDelegate : NSObject<NSURLSessionDataDelegate>

@property (weak, nonatomic) AADownloader * helper;

@property (nonatomic, strong) NSProgress *downloadProgress;

@property (strong, nonatomic) NSString * taskDescription;

@property (strong, nonatomic) NSFileHandle *fileHandle;

@property (assign, nonatomic) long long originalOffset;

@property (strong, nonatomic) NSString * downloadingFilePath;

@property (strong, nonatomic) NSString * downloadedFilePath;

@property (nonatomic, copy) AADownloaderTaskProgressBlock downloadProgressBlock;

@property (nonatomic, copy) AADownloaderTaskCompletionHandler completionHandler;

- (void)setupProgressForTask:(NSURLSessionTask *)task;

- (void)cleanUpProgressForTask:(NSURLSessionTask *)task;

@end
