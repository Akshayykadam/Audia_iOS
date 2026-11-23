#import <Foundation/Foundation.h>

@interface ReturnCode : NSObject
+ (BOOL)isSuccess:(nullable ReturnCode *)returnCode;
+ (BOOL)isCancel:(nullable ReturnCode *)returnCode;
- (int)getValue;
@end

@interface Statistics : NSObject
- (double)getSize;
- (double)getTime;
- (double)getBitrate;
- (float)getSpeed;
@end

@interface FFmpegSession : NSObject
- (nullable ReturnCode *)getReturnCode;
- (nullable NSString *)getOutput;
- (long)getSessionId;
- (void)cancel;
@end

@interface FFmpegKit : NSObject
+ (nullable FFmpegSession *)executeWithArgumentsAsync:(NSArray<NSString *> *)arguments
                                withCompleteCallback:(nullable void (^)(FFmpegSession * _Nullable))completeCallback
                                     withLogCallback:(nullable id)logCallback
                              withStatisticsCallback:(nullable void (^)(Statistics * _Nullable))statisticsCallback;
+ (void)cancel;
+ (void)cancel:(long)sessionId;
@end
