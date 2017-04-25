//
//  AAProtocols.h
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#define kErrorDomain @"com.aa.mediaCenter.error"

static NSString * _Nullable const kAAHTTPSourceCachedFailedNotificationName = @"kAAHTTPSourceCachedFailedNotificationName";
static NSString * _Nullable const kAAHTTPSourceCachedSucceedNotificationName = @"kAAHTTPSourceCachedSucceedNotificationName";
static NSString * _Nullable const kAAHTTPSourceCachedMoveToCachedFileNotificationName = @"kAAHTTPSourceCachedMoveToCachedFileNotificationName";
static NSString * _Nullable const kAAHTTPSourceCachedMoveToDownloadedFileNotificationName = @"kAAHTTPSourceCachedMoveToDownloadedFileNotificationName";

typedef enum : NSInteger {
    AAMediaCenterErrorCodesSourceFailed,
    AAMediaCenterErrorCodesConverterFailed,
    AAMediaCenterErrorCodesDecoderFailed,
    AAMediaCenterErrorCodesContainerFailed
} AAMediaCenterErrorCodes;


@protocol AAMediaCenterObject <NSObject>
@end

@protocol AASource <AAMediaCenterObject>

+ (NSString * _Nonnull)scheme;

- (NSURL * _Nonnull)url;

- (long)size;

- (BOOL)open:(NSURL * _Nonnull)url withName:(NSString * _Nullable)fileName andAuthorization:(NSDictionary *_Nullable)authorizationDict;

- (BOOL)seekable;

- (BOOL)seek:(long)position whence:(int)whence;

- (long)tell;

- (int)read:(void * _Nonnull)buffer amount:(int)amount;

- (void)close;

@end

@protocol AADecoder <AAMediaCenterObject>
@required

+ (NSArray * _Nullable)fileTypes;

- (NSDictionary * _Nullable)properties;

- (NSDictionary * _Nullable)metadata;

- (int)readAudio:(void * _Nonnull)buffer frames:(UInt32)frames;

- (BOOL)open:(id<AASource> _Nonnull)source;

- (long)seek:(long)frame;

- (void)close;

@end
