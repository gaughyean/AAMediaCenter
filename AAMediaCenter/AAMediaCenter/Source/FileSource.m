//
//  FileSource.m
//  AAMediaCenter
//
//  Created by Gavin Tsang on 2017/3/24.
//  Copyright © 2017年 Gavin Tsang. All rights reserved.
//

#import "FileSource.h"

@interface FileSource () {
    FILE *_fd;
}
@property (strong, nonatomic) NSURL *url;
@end

@implementation FileSource

- (instancetype)init
{
    if (self = [super init]) {
    }
    return self;
}

- (void)dealloc {
    [self close];
}

#pragma mark - AASource
+ (NSString *)scheme {
    return @"file";
}

- (NSURL *)url {
    return _url;
}

- (long)size {
    long curpos = ftell(_fd);
    fseek (_fd, 0, SEEK_END);
    long size = ftell(_fd);
    fseek(_fd, curpos, SEEK_SET);
    return size;
}


- (BOOL)open:(NSURL *)url withName:(NSString *)fileName andAuthorization:(NSDictionary *)authorizationDict{
    return [self open:url];
}

- (BOOL)open:(NSURL *)url {
    [self setUrl:url];
    _fd = fopen([[url path] UTF8String], "r");
    return (_fd != NULL);
}

- (BOOL)seekable {
    return YES;
}

- (BOOL)seek:(long)position whence:(int)whence {
    return (fseek(_fd, position, whence) == 0);
}

- (long)tell {
    return ftell(_fd);
}

- (int)read:(void *)buffer amount:(int)amount {
    return (int)fread(buffer, 1, amount, _fd);
}

- (void)close {
    if (_fd) {
        fclose(_fd);
        _fd = NULL;
    }
}

@end
